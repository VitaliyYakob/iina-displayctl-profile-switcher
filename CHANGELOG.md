# Changelog

All notable changes to this project are documented in this file.

## 1.0.0 — 2026-07-21

- Detect video color metadata through mpv `video-params`.
- Resolve display profile numbers dynamically from `displayctl profiles`.
- Cache the parsed profile list for the IINA player instance.
- Switch the display profile and refresh-rate index during playback.
- Restore the default profile and refresh rate when playback stops or IINA exits normally.
- Add English and Russian documentation.
- Document that the script was created by OpenAI Codex from the author's instructions and tested on real hardware.
- Document the dependency on the previously published `VitaliyYakob/displayctl` project.
