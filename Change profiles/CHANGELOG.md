# Changelog

All notable changes to this project are documented in this file.

## 1.0.1 — 2026-09-22

- Fix default profile and refresh-rate resets between playlist entries.
- Restore only after confirmed idle or retained EOF with a cancellable 0.4-second delay; preserve immediate shutdown restoration.
- Cancel pending restoration on `start-file`, including slow-loading files.
- Skip redundant settings for the same profile and switch SDR/HDR profiles directly.
- Restore defaults for audio-only entries, unsupported metadata, and missing profiles; bound metadata polling to 5 seconds and inspect later property changes.
- Invalidate cached settings after command failures, report restoration failures, and preserve the shutdown retry.
- Add 29 regression scenarios, verified with Lua 5.5.1 and IINA 1.4.4's LuaJIT 2.1. Physical monitor switching was not tested for this release.
- Record the existing relocation of project files into `Change profiles/`.

## 1.0.0 — 2026-07-21

- Detect video color metadata through mpv `video-params`.
- Resolve display profile numbers dynamically from `displayctl profiles`.
- Cache the parsed profile list for the IINA player instance.
- Switch the display profile and refresh-rate index during playback.
- Restore the default profile and refresh rate when playback stops or IINA exits normally.
- Add English and Russian documentation.
- Document that the script was created by OpenAI Codex from the author's instructions and tested on real hardware.
- Document the dependency on the previously published `VitaliyYakob/displayctl` project.
