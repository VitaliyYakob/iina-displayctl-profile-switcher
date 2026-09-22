-- Run from any directory: lua path/to/tests/profile_switcher_test.lua
-- All display commands and playback events are simulated; no display is changed.
local test_dir = (arg[0]:match("^(.*[/\\])") or "./")
local script = arg[1] or (test_dir .. "../iina-display-profile.lua")
local SDR = {primaries = "bt.709", gamma = "bt.1886", colormatrix = "bt.709"}
local HDR = {primaries = "bt.2020", gamma = "pq", colormatrix = "bt.2020-ncl"}
local VIDEO = {{type = "video", selected = true}}
local AUDIO = {{type = "audio", selected = true}}
local PROFILES = "[1] Display:\n    [3] HDR Video (P3-ST 2084)\n" ..
    "    [4] HDTV Video (BT.709-BT.1886) *\n"

local function player(options)
    options = options or {}
    local p = {
        now = 0, timers = {}, events = {}, hooks = {}, observers = {},
        commands = {}, shell_commands = {}, warnings = {}, messages = {},
        properties = {["idle-active"] = true, ["eof-reached"] = false},
        profile_reads = 0, fail_sets = 0, fail_restores = 0,
    }
    local mp = {
        register_event = function(name, fn) p.events[name] = fn end,
        add_hook = function(name, _, fn) p.hooks[name] = fn end,
        observe_property = function(name, _, fn) p.observers[name] = fn end,
        get_property_native = function(name) return p.properties[name] end,
        get_time = function() return p.now end,
        add_timeout = function(delay, fn)
            local timer = {at = p.now + delay, fn = fn, active = true}
            function timer:kill() self.active = false end
            p.timers[#p.timers + 1] = timer
            return timer
        end,
        osd_message = function(message) p.messages[#p.messages + 1] = message end,
        msg = {warn = function(message) p.warnings[#p.warnings + 1] = message end},
        command_native = function(command)
            assert(command.name == "subprocess")
            assert(command.args[1] == "/usr/local/bin/displayctl")
            assert(command.playback_only == false)
            if command.args[2] == "profiles" then
                p.profile_reads = p.profile_reads + 1
                return {status = options.profiles_status or 0, stdout = options.profiles or PROFILES}
            end
            assert(command.args[2] == "set" and command.args[3] == "--profile")
            assert(command.args[5] == "--rate")
            local profile, rate = command.args[4], command.args[6]
            assert(rate == (profile == "default" and "default" or "2"))
            p.commands[#p.commands + 1] = profile
            if options.throw_commands then error("Simulated subprocess failure") end
            local field = profile == "default" and "fail_restores" or "fail_sets"
            if p[field] > 0 then
                p[field] = p[field] - 1
                return {status = 1, stderr = "Simulated partial failure"}
            end
            return {status = 0, stdout = ""}
        end,
    }
    local env = setmetatable({mp = mp, os = {execute = function(command)
        assert(command == "'/usr/local/bin/displayctl' set --profile default --rate default")
        p.shell_commands[#p.shell_commands + 1] = command
        if options.shell_status ~= nil then return options.shell_status end
        return true, "exit", 0
    end}}, {__index = _G})
    local chunk
    if setfenv then
        chunk = assert(loadfile(script))
        setfenv(chunk, env)
    else
        chunk = assert(loadfile(script, "t", env))
    end
    chunk()

    function p:emit(name, value)
        if self.events[name] then self.events[name](value or {}) end
    end
    function p:property(name, value)
        self.properties[name] = value
        if self.observers[name] then self.observers[name](name, value) end
    end
    function p:advance(seconds)
        local target, count = self.now + seconds, 0
        while true do
            local next_timer
            for _, timer in ipairs(self.timers) do
                if timer.active and timer.at <= target and
                    (not next_timer or timer.at < next_timer.at) then
                    next_timer = timer
                end
            end
            if not next_timer then break end
            count = count + 1
            assert(count < 1000, "Unbounded timer loop")
            self.now = next_timer.at
            next_timer.active = false
            next_timer.fn()
        end
        self.now = target
    end
    function p:pending()
        local count = 0
        for _, timer in ipairs(self.timers) do
            if timer.active then count = count + 1 end
        end
        return count
    end
    function p:start()
        self:property("idle-active", false)
        self:emit("start-file")
        self:property("eof-reached", false)
        self:property("video-params", nil)
    end
    function p:loaded(params, tracks)
        self:property("track-list", tracks or VIDEO)
        self:property("video-params", params)
        self:emit("file-loaded")
        self:advance(0.11)
    end
    function p:play(params, tracks)
        self:start()
        self:loaded(params or SDR, tracks)
    end
    function p:unload(reason)
        self:property("eof-reached", true)
        self.hooks.on_unload()
        self:property("video-params", nil)
        self:emit("end-file", {reason = reason or "eof"})
    end
    function p:expect(expected)
        local actual = table.concat(self.commands, ",")
        assert(actual == expected, "Expected commands [" .. expected .. "], got [" .. actual .. "]")
    end
    -- mpv sends initial notifications for observed properties.
    for name, fn in pairs(p.observers) do
        fn(name, p.properties[name])
    end
    return p
end

local tests = {}
local function test(name, fn) tests[#tests + 1] = {name, fn} end

test("startup idle does not touch the display", function()
    local p = player()
    p:advance(10)
    p:expect("")
    assert(p:pending() == 0)
end)

test("100 same-profile entries keep a single display setting", function()
    local p = player()
    for _ = 1, 100 do
        p:play()
        p:unload()
    end
    p:expect("4")
    assert(p.profile_reads == 1)
    p:property("idle-active", true)
    p:advance(0.5)
    p:expect("4,default")
end)

test("SDR to HDR to SDR switches directly", function()
    local p = player()
    p:play(SDR)
    p:unload()
    p:play(HDR)
    p:unload()
    p:play(SDR)
    p:expect("4,3,4")
end)

for _, reason in ipairs({"eof", "stop", "redirect", "error"}) do
    test("transition with end-file reason " .. reason .. " preserves profile", function()
        local p = player()
        p:play()
        p:unload(reason)
        p:play()
        p:advance(1)
        p:expect("4")
    end)
end

test("slow file loading cancels the idle restore before file-loaded", function()
    local p = player()
    p:play()
    p:unload()
    p:property("idle-active", true)
    p:advance(0.2)
    p:start()
    p:advance(12)
    p:expect("4")
    p:loaded(SDR)
    p:expect("4")
end)

test("restore callback rechecks idle even without its notification", function()
    local p = player()
    p:play()
    p:unload()
    p:property("idle-active", true)
    p.properties["idle-active"] = false
    p:advance(1)
    p:expect("4")
end)

test("Stop restores only after the idle grace period", function()
    local p = player()
    p:play()
    p:unload("stop")
    p:property("idle-active", true)
    p:advance(0.39)
    p:expect("4")
    p:advance(0.02)
    p:expect("4,default")
    p:emit("shutdown")
    assert(#p.shell_commands == 0)
end)

test("idle arriving before end-file still restores", function()
    local p = player()
    p:play()
    p:property("idle-active", true)
    p:unload()
    p:advance(0.5)
    p:expect("4,default")
end)

test("pause, seeking and cache buffering do not restore", function()
    local p = player()
    p:play()
    for _, name in ipairs({"pause", "core-idle", "paused-for-cache", "seeking"}) do
        p:property(name, true)
        p:advance(2)
    end
    p:expect("4")
end)

test("keep-open EOF restores and seek back reapplies", function()
    local p = player()
    p:play()
    p:property("eof-reached", true)
    p:advance(0.5)
    p:expect("4,default")
    p:property("eof-reached", false)
    p:advance(0.2)
    p:expect("4,default,4")
end)

test("looping past transient EOF does not restore", function()
    local p = player()
    p:play()
    p:property("eof-reached", true)
    p:advance(0.2)
    p:property("eof-reached", false)
    p:advance(1)
    p:expect("4")
end)

test("audio restores instead of polling forever", function()
    local p = player()
    p:play()
    p:unload()
    p:start()
    p:loaded(nil, AUDIO)
    p:advance(10)
    p:expect("4,default")
    assert(p:pending() == 0)
    p:unload()
    p:play()
    p:expect("4,default,4")
end)

test("album art does not select a video reference profile", function()
    local p = player()
    p:play()
    p:unload()
    p:play(SDR, {{type = "video", selected = true, albumart = true}})
    p:expect("4,default")
end)

test("disabled video restores and re-enabled track reapplies", function()
    local p = player()
    p:play()
    p:property("track-list", {{type = "video", selected = false}})
    p:advance(0.2)
    p:expect("4,default")
    p:property("track-list", VIDEO)
    p:advance(0.2)
    p:expect("4,default,4")
end)

test("unknown metadata restores the previous profile", function()
    local p = player()
    p:play()
    p:unload()
    p:play({primaries = "unknown", gamma = "unknown"})
    p:expect("4,default")
    assert(p:pending() == 0)
end)

test("missing profile restores the previous profile", function()
    local p = player({profiles = "    [4] HDTV Video (BT.709-BT.1886)\n"})
    p:play()
    p:unload()
    p:play(HDR)
    p:expect("4,default")
end)

test("delayed metadata within timeout preserves the previous profile", function()
    local p = player()
    p:play()
    p:unload()
    p:start()
    p:loaded(nil)
    p:advance(3)
    p:expect("4")
    p:property("video-params", HDR)
    p:advance(0.2)
    p:expect("4,3")
end)

test("missing metadata has a bounded timeout and recovers when available", function()
    local p = player()
    p:play()
    p:unload()
    p:start()
    p:loaded(nil)
    p:advance(6)
    p:expect("4,default")
    assert(p:pending() == 0)
    p:property("video-params", HDR)
    p:advance(0.2)
    p:expect("4,default,3")
end)

test("unload cancels the previous file's metadata retry", function()
    local p = player()
    p:start()
    p:loaded(nil)
    p:unload()
    p:advance(10)
    p:expect("")
    assert(p:pending() == 0)
end)

test("profile changes during a file are applied once", function()
    local p = player()
    p:play()
    p:property("video-params", HDR)
    p:advance(0.2)
    p:property("video-params", HDR)
    p:advance(0.2)
    p:expect("4,3")
end)

test("shutdown during loading restores synchronously and cancels timers", function()
    local p = player()
    p:play()
    p:unload()
    p:start()
    p:emit("shutdown")
    p:advance(10)
    p:expect("4")
    assert(#p.shell_commands == 1 and p:pending() == 0)
end)

test("shutdown cancels a pending idle restore", function()
    local p = player()
    p:play()
    p:unload()
    p:property("idle-active", true)
    p:emit("shutdown")
    p:advance(1)
    p:expect("4")
    assert(#p.shell_commands == 1)
end)

test("failed restore is reported and retried on shutdown", function()
    local p = player({shell_status = 0})
    p:play()
    p.fail_restores = 1
    p:unload()
    p:property("idle-active", true)
    p:advance(0.5)
    assert(#p.warnings == 1)
    p:emit("shutdown")
    p:emit("shutdown")
    assert(#p.shell_commands == 1)
end)

test("failed profile setting is restored and not cached", function()
    local p = player()
    p.fail_sets = 1
    p:play()
    p:expect("4,default")
    p:unload()
    p:play()
    p:expect("4,default,4")
end)

test("subprocess exceptions retain shutdown restoration", function()
    local p = player({throw_commands = true})
    p:play()
    p:emit("shutdown")
    p:expect("4,default")
    assert(#p.shell_commands == 1)
end)

test("failed profile listing is retried for the next file", function()
    local options = {profiles_status = 1}
    local p = player(options)
    p:play()
    p:expect("")
    options.profiles_status = 0
    p:unload()
    p:play()
    p:expect("4")
    assert(p.profile_reads == 2)
end)

local failures = 0
for _, entry in ipairs(tests) do
    local ok, err = pcall(entry[2])
    print((ok and "PASS " or "FAIL ") .. entry[1])
    if not ok then
        failures = failures + 1
        print("  " .. tostring(err))
    end
end
print(string.format("%d/%d tests passed", #tests - failures, #tests))
assert(failures == 0, "Regression tests failed")
