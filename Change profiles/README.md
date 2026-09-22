# IINA Displayctl Profile Switcher

[Русская версия](README.ru.md)

A lightweight Lua script for [IINA](https://iina.io/) and mpv on macOS. It detects the color metadata of the currently playing video, finds the matching Apple display reference mode in `displayctl profiles`, switches to its current numeric profile ID, and restores the system defaults when playback ends.

> **Project note:** This script was created by OpenAI Codex following the project author's instructions. The original 1.0.0 release was tested on real hardware. Version 1.0.1 has automated regression coverage; see Validation below for its limits.

The script uses [VitaliyYakob/displayctl](https://github.com/VitaliyYakob/displayctl), a command-line display management utility previously published by the project author.

## Features

- Reads `primaries`, `gamma`, and `colormatrix` from mpv's `video-params`.
- Matches video metadata to the exact profile names reported by `displayctl`.
- Resolves profile numbers dynamically instead of hard-coding them.
- Caches the parsed profile list for the lifetime of the IINA player instance.
- Sets the configured refresh-rate ID during playback.
- Keeps the display settings between playlist entries; applies a different profile directly when needed and skips redundant settings for the same profile.
- Restores `--profile default --rate default` after playback actually stops, the playlist finishes, or IINA shuts down normally.
- Handles audio-only entries, missing metadata, and the final frame retained by `keep-open`.
- Shows the detected metadata, selected profile name, and resolved profile number in the IINA OSD.

## Requirements

- macOS
- IINA with mpv Lua scripts enabled
- [VitaliyYakob/displayctl](https://github.com/VitaliyYakob/displayctl) installed at `/usr/local/bin/displayctl`
- A display whose reference modes are exposed by `displayctl profiles`

## Installation

1. In IINA, open **Settings → Advanced**.
2. Enable **Use config directory** and set it to `~/.config/mpv`.
3. Create the scripts directory if it does not exist:

   ```sh
   mkdir -p ~/.config/mpv/scripts
   ```

4. If updating an existing installation, back up the installed script with `cp -p` first (for example, as `iina-display-profile.lua.before-1.0.1`). Copy `iina-display-profile.lua` to:

   ```text
   ~/.config/mpv/scripts/iina-display-profile.lua
   ```

5. Quit IINA completely and open it again.

## How it works

When the first file is loaded, the script runs:

```sh
/usr/local/bin/displayctl profiles
```

It indexes the indented profile rows by exact name. For example:

```text
[1] Studio Display XDR (Main):
    [3] HDR Video (P3-ST 2084)
    [4] HDTV Video (BT.709-BT.1886) *
```

For a video tagged as BT.709 with a BT.1886 transfer function, the selected name is `HDTV Video (BT.709-BT.1886)`. The script resolves that name to profile `4` and runs:

```sh
/usr/local/bin/displayctl set --profile 4 --rate 2
```

Unloading a file does not restore defaults: mpv also unloads files when advancing a playlist. The script observes `idle-active` and `eof-reached` instead. It waits 0.4 seconds after an idle state or a retained end frame, then rechecks the current state before restoring. A new `start-file` cancels this pending restore immediately, even if loading the next file takes a long time. Pause, seeking, and buffering do not trigger restoration. Resuming from a retained end frame applies the video profile again.

On confirmed playback completion or normal IINA shutdown, it runs:

```sh
/usr/local/bin/displayctl set --profile default --rate default
```

For audio-only entries (including album art), unsupported color metadata, or an unavailable profile, the script restores defaults instead of keeping the previous video's profile. Missing metadata is retried for up to 5 seconds after loading; later `video-params` or track changes trigger a new inspection. Failed display commands invalidate the cached active profile, attempt to restore defaults, and retain the shutdown fallback if restoration fails.

## Default mapping

| Video metadata | Display profile name |
| --- | --- |
| PQ | HDR Video (P3-ST 2084) |
| HLG | Apple XDR Display (P3-2000 nits) |
| BT.601 525-line | NTSC Video (BT.601 SMPTE-C) |
| BT.601 625-line | PAL & SECAM Video (BT.601 EBU) |
| BT.709 | HDTV Video (BT.709-BT.1886) |
| BT.2020 SDR | Apple XDR Display (P3-2000 nits) |
| DCI-P3 | Digital Cinema (P3-DCI) |
| Display P3 | Apple XDR Display (P3-2000 nits) |
| Adobe RGB | Photography (Adobe RGB-D65) |
| sRGB RGB content | Internet & Web (sRGB) |

HLG and SDR BT.2020 use the general Apple XDR mode because the referenced profile list does not contain dedicated modes for them.

## Configuration

The playback refresh-rate ID is defined near the top of the script:

```lua
local PLAYBACK_RATE = "2"
```

This is a `displayctl` rate index, not a literal frequency. Change it to the index appropriate for your display.

`RESTORE_DELAY` (0.4 seconds) is the idle/EOF grace period. `METADATA_TIMEOUT` (5 seconds) limits a metadata polling cycle; neither is a maximum file-loading time. Back up the script before changing these values.

## Troubleshooting

Verify that the executable and profile list are available:

```sh
/usr/local/bin/displayctl profiles
```

Profile matching is exact. If your display uses different profile names, update `PRESET_BY_TRANSFER` or `PRESET_BY_PRIMARIES` in the Lua script.

The profile list is cached once per IINA player instance. Restart IINA after changing display reference modes.

A forced termination or application crash cannot restore the defaults because Lua shutdown events are not delivered.

The active-profile cache assumes that other applications and other IINA player instances do not change the same monitor during playback. Simultaneous players are not coordinated by this script.

## Validation

From this directory, run:

```sh
luac -p iina-display-profile.lua
lua tests/profile_switcher_test.lua
```

The 29 regression scenarios simulate mpv events, properties, timers, and displayctl failures without changing a monitor. They cover 100-entry playlists, direct SDR/HDR transitions, slow loading, stop, pause, buffering, looping, retained EOF and replay, audio, metadata timeouts, and shutdown. They pass on Lua 5.5.1 and the LuaJIT 2.1 runtime bundled with IINA 1.4.4. The original 1.0.0 script fails the playlist regression.

Live playback and physical monitor switching have not been verified for 1.0.1. An attempt to load the installed IINA libmpv outside the app failed because its bundled libplacebo did not provide `_pl_log_create_349`. No changes were made to IINA or the installed playback script.

After installation, check a same-profile playlist, an SDR/HDR transition, Stop, the last playlist entry, and normal IINA exit on the actual monitor. To roll back, restore the installed script from the backup and restart IINA; the original source is also available at Git tag `v1.0.0` as `iina-display-profile.lua` at the repository root.

## License

[MIT](LICENSE)
