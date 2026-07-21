# IINA Displayctl Profile Switcher

[Русская версия](README.ru.md)

A lightweight Lua script for [IINA](https://iina.io/) and mpv on macOS. It detects the color metadata of the currently playing video, finds the matching Apple display reference mode in `displayctl profiles`, switches to its current numeric profile ID, and restores the system defaults when playback ends.

> **Project note:** This script was created by OpenAI Codex following the project author's instructions and was tested on real hardware.

The script uses [VitaliyYakob/displayctl](https://github.com/VitaliyYakob/displayctl), a command-line display management utility previously published by the project author.

## Features

- Reads `primaries`, `gamma`, and `colormatrix` from mpv's `video-params`.
- Matches video metadata to the exact profile names reported by `displayctl`.
- Resolves profile numbers dynamically instead of hard-coding them.
- Caches the parsed profile list for the lifetime of the IINA player instance.
- Sets the configured refresh-rate ID during playback.
- Restores `--profile default --rate default` on stop, end of file, file unload, or normal IINA shutdown.
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

4. Copy `iina-display-profile.lua` to:

   ```text
   ~/.config/mpv/scripts/iina-display-profile.lua
   ```

5. Quit IINA completely and open it again.

## How it works

When a file is loaded, the script runs:

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

When playback is unloaded or IINA closes normally, it runs:

```sh
/usr/local/bin/displayctl set --profile default --rate default
```

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

## Troubleshooting

Verify that the executable and profile list are available:

```sh
/usr/local/bin/displayctl profiles
```

Profile matching is exact. If your display uses different profile names, update `PRESET_BY_TRANSFER` or `PRESET_BY_PRIMARIES` in the Lua script.

The profile list is cached once per IINA player instance. Restart IINA after changing display reference modes.

A forced termination or application crash cannot restore the defaults because Lua shutdown events are not delivered.

## License

[MIT](LICENSE)
