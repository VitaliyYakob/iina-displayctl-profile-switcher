# IINA Displayctl Profile Switcher

[Документация на русском](Change%20profiles/README.ru.md) · [Full documentation in English](Change%20profiles/README.md)

A Lua script for IINA on macOS that selects an Apple display reference profile from the video's color metadata using [displayctl](https://github.com/VitaliyYakob/displayctl). It keeps the selected profile between playlist entries and restores the display defaults when playback ends.

## Download

[Download the latest release (v1.0.1)](https://github.com/VitaliyYakob/iina-displayctl-profile-switcher/releases/tag/v1.0.1). The release includes the script, installation instructions, and a local regression test.

## Install

Enable IINA's mpv config directory, then place [`iina-display-profile.lua`](Change%20profiles/iina-display-profile.lua) in `~/.config/mpv/scripts/` and restart IINA. See the [installation guide](Change%20profiles/README.md#installation) for requirements, setup, and rollback instructions.

## License

[MIT](Change%20profiles/LICENSE)
