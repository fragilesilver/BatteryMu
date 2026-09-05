# Changelog

All notable changes to BatteryMu are documented here.
Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
this project follows [Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-09-06

First release under the **fragilesilver** app family, reprogrammed for
**muOS Andromeda 2606.0** and the full **RG35XX family** (all Allwinner H700),
Jacaranda-compatible.

### Added
- Shared **fskit** kit: letterboxed 640×480 virtual canvas, theme model and
  palette, fonts, glyphs, input abstraction, header/footer chrome — shared with
  ClockMu and JarMu.
- `love.resize` handling; render letterboxes instead of stretching, so every
  RG35XX panel variant (and HDMI-out) is correct.
- Andromeda launcher (`mux_launch.sh`): bind-storage app-dir resolution with a
  Jacaranda fallback, `HOME`/`XDG_*` export, `CAFFEINE` on/off with a cleanup
  trap, resolution passed from `GET_VAR device mux/width`.
- Battery source resolved through muOS vars: prefers the pre-parsed
  `$MUOS_RUN_DIR/battery/{capacity,charging}` and the `battery_usage` tracker,
  falling back to raw AXP2202 sysfs (`BATTERYMU_BASE` and friends from
  `GET_VAR device battery/*`).
- `BATTERYMU_DATA` persistence path: theme/settings written via plain `io`,
  independent of LÖVE's save-dir under muOS bind-storage.
- Health/voltage detail screen, charge-history graph, in-app theme picker.
- `VERSION`, `.gitignore`, `build.sh`, `README.md`, this changelog.

### Changed
- Theme save cadence relaxed from 1 s to 30 s.
- Theme keys mapped onto fskit roles via a `KEYMAP` + `rebuildT()` snapshot,
  refreshed on `fskit.theme.onChange`.
