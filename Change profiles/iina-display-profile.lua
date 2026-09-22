-- iina-displayctl-profile-switcher
-- Version: 1.0.1
-- SPDX-License-Identifier: MIT
-- IINA/mpv: automatic displayctl profile selection by profile name.

local DISPLAYCTL = "/usr/local/bin/displayctl"

-- displayctl rate number used during video playback (120 Hz in this setup).
local PLAYBACK_RATE = "2"
local RESTORE_DELAY = 0.4
local METADATA_TIMEOUT = 5

-- Transfer functions take priority over primaries because HDR files are
-- normally tagged with BT.2020 primaries plus either PQ or HLG transfer.
local PRESET_BY_TRANSFER = {
    pq = "HDR Video (P3-ST 2084)",

    -- The display profile list has no dedicated HLG reference preset.
    hlg = "Apple XDR Display (P3-2000 nits)",
}

local PRESET_BY_PRIMARIES = {
    ["bt.601-525"] = "NTSC Video (BT.601 SMPTE-C)",
    ["bt.601-625"] = "PAL & SECAM Video (BT.601 EBU)",
    ["bt.709"] = "HDTV Video (BT.709-BT.1886)",
    ["bt.2020"] = "Apple XDR Display (P3-2000 nits)",
    ["dci-p3"] = "Digital Cinema (P3-DCI)",
    ["display-p3"] = "Apple XDR Display (P3-2000 nits)",
    adobe = "Photography (Adobe RGB-D65)",
}

local timer = nil
local restore_timer = nil
local profile_numbers = nil
local needs_restore = false
local active_profile = nil
local file_loaded = false
local metadata_deadline = 0

local function cancel_timer()
    if timer then
        timer:kill()
        timer = nil
    end
end

local function cancel_restore_timer()
    if restore_timer then
        restore_timer:kill()
        restore_timer = nil
    end
end

local function run_displayctl(arguments)
    local args = {DISPLAYCTL}
    for _, value in ipairs(arguments) do
        args[#args + 1] = tostring(value)
    end

    local ok, result = pcall(mp.command_native, {
        name = "subprocess",
        args = args,
        playback_only = false,
        capture_stdout = true,
        capture_stderr = true,
    })

    if ok and type(result) == "table" then
        return result
    end

    return nil
end

-- Loads and indexes the profile list once per IINA player instance. Only
-- indented profile rows are parsed, so the unindented display header is ignored.
local function load_profile_numbers()
    if profile_numbers then
        return true
    end

    local result = run_displayctl({"profiles"})
    if not result or result.status ~= 0 then
        return false
    end

    local parsed = {}
    for line in (result.stdout or ""):gmatch("[^\r\n]+") do
        local number, name = line:match("^%s+%[(%d+)%]%s+(.+)$")
        if number and name then
            name = name:gsub("%s+%*%s*$", ""):gsub("%s+$", "")
            parsed[name] = number
        end
    end

    profile_numbers = parsed
    return true
end

-- Maps video metadata to the exact name printed by `displayctl profiles`.
-- Profile numbers are obtained only from the indexed displayctl output.
local function preset_for_video(primaries, gamma, matrix)
    local transfer_preset = PRESET_BY_TRANSFER[gamma]
    if transfer_preset then
        return transfer_preset
    end

    -- Treat sRGB as a web preset only for actual RGB content, not YUV video.
    if gamma == "srgb" and (matrix == "rgb" or matrix == "identity") then
        return "Internet & Web (sRGB)"
    end

    return PRESET_BY_PRIMARIES[primaries]
end

local function show_video_info(preset, number, params, success, error_text)
    local title
    if success then
        title = "Рекомендуемый Preset:"
    else
        title = "Не удалось установить Preset:"
    end

    local text =
        "\n" .. title .. "\n\n" ..
        tostring(preset or "Не определён") ..
        (number and ("  [" .. number .. "]") or "") ..
        "\n\nColor    → " .. tostring(params.primaries or "не определено") ..
        "\nTransfer → " .. tostring(params.gamma or "не определено") ..
        "\nMatrix   → " .. tostring(params.colormatrix or "не определено")

    if error_text then
        text = text .. "\n\n" .. error_text
    end

    mp.osd_message(text, 8)
end

local function restore_default()
    if not needs_restore then
        return
    end

    -- A failed command may still have changed part of the display settings.
    active_profile = nil
    local result = run_displayctl({
        "set",
        "--profile", "default",
        "--rate", "default",
    })

    if result and result.status == 0 then
        needs_restore = false
    else
        mp.msg.warn("Не удалось восстановить настройки монитора")
    end
end

local function playback_finished()
    return mp.get_property_native("idle-active") == true or
        (file_loaded and mp.get_property_native("eof-reached") == true)
end

local function has_video_track()
    local tracks = mp.get_property_native("track-list")
    if type(tracks) ~= "table" then
        return nil
    end
    for _, track in ipairs(tracks) do
        if track.type == "video" and track.selected and not track.albumart then
            return true
        end
    end
    return false
end

local inspect_and_switch

inspect_and_switch = function()
    timer = nil

    if not file_loaded or playback_finished() then
        return
    end

    if has_video_track() == false then
        restore_default()
        return
    end

    local params = mp.get_property_native("video-params")
    if type(params) ~= "table" or not params.primaries or not params.gamma then
        if mp.get_time() < metadata_deadline then
            timer = mp.add_timeout(0.1, inspect_and_switch)
        else
            restore_default()
            show_video_info(nil, nil, {}, false, "Истекло время ожидания метаданных видео")
        end
        return
    end

    local preset = preset_for_video(
        params.primaries,
        params.gamma,
        params.colormatrix
    )

    if not preset then
        restore_default()
        show_video_info(nil, nil, params, false, "Нет правила для этих метаданных")
        return
    end

    local profile_number = profile_numbers and profile_numbers[preset]
    if not profile_number then
        restore_default()
        show_video_info(
            preset,
            nil,
            params,
            false,
            "Имя не найдено в выводе displayctl profiles"
        )
        return
    end

    if active_profile == profile_number then
        return
    end

    needs_restore = true
    active_profile = nil
    local result = run_displayctl({
        "set",
        "--profile", profile_number,
        "--rate", PLAYBACK_RATE,
    })

    local success = result and result.status == 0
    if success then
        active_profile = profile_number
    end

    local error_text = nil
    if not success then
        error_text = result and result.stderr or "Ошибка запуска displayctl"
        restore_default()
    end

    show_video_info(preset, profile_number, params, success, error_text)
end

local function schedule_inspection()
    if file_loaded and not playback_finished() and not timer then
        metadata_deadline = mp.get_time() + METADATA_TIMEOUT
        timer = mp.add_timeout(0.1, inspect_and_switch)
    end
end

local function on_playback_state()
    if playback_finished() then
        cancel_timer()
        if needs_restore and not restore_timer then
            restore_timer = mp.add_timeout(RESTORE_DELAY, function()
                restore_timer = nil
                -- Property notifications can be stale by the time we receive them.
                if playback_finished() then
                    restore_default()
                end
            end)
        end
    else
        cancel_restore_timer()
        schedule_inspection()
    end
end

local function shell_quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function restore_default_on_shutdown()
    if not needs_restore then
        return
    end

    -- At shutdown the mpv command interface may already be unavailable.
    -- Run the exact restore command directly and wait for it to finish.
    local command = shell_quote(DISPLAYCTL) ..
        " set --profile default --rate default"
    local invoked, status = pcall(os.execute, command)

    if invoked and (status == true or status == 0) then
        needs_restore = false
        active_profile = nil
    else
        mp.msg.warn("Не удалось восстановить настройки монитора при выходе")
    end
end

local function on_start_file()
    file_loaded = false
    cancel_timer()
    cancel_restore_timer()
end

local function on_file_loaded()
    cancel_timer()
    cancel_restore_timer()
    file_loaded = true

    -- The first file loads the list; subsequent files reuse the indexed table.
    load_profile_numbers()

    on_playback_state()
end

local function on_unload()
    file_loaded = false
    cancel_timer()
    cancel_restore_timer()
end

local function on_end_file()
    on_unload()
    on_playback_state()
end

local function on_shutdown()
    file_loaded = false
    cancel_timer()
    cancel_restore_timer()
    restore_default_on_shutdown()
end

mp.register_event("start-file", on_start_file)
mp.register_event("file-loaded", on_file_loaded)
mp.register_event("end-file", on_end_file)
mp.register_event("shutdown", on_shutdown)
mp.add_hook("on_unload", 50, on_unload)
mp.observe_property("idle-active", "bool", on_playback_state)
mp.observe_property("eof-reached", "bool", on_playback_state)
mp.observe_property("video-params", "native", schedule_inspection)
mp.observe_property("track-list", "native", schedule_inspection)
