# STOMP Controller v19.0

A dual-channel Bluetooth stomp pedal controller for live audio mixing, supporting Behringer **WING**, **X32**, and **XR18** mixers via OSC/UDP.

Built on the **ESP32-C5** with a 3.5" TFT display, configurable via a Flutter app (Android + iOS).

---

## Hardware

| Component | Detail |
|-----------|--------|
| MCU | ESP32-C5-DEVKITC-1-N8R8 (5GHz WiFi + BLE) |
| Display | 3.5" TFT ILI9486 — 480×320 |
| Stomp A | SPST switch — GPIO 26 |
| Stomp B | SPST switch — GPIO 25 |
| LED A Tap | Blue — GPIO 24 |
| LED A Mute | Red — GPIO 23 |
| LED B Tap | Blue — GPIO 28 |
| LED B Mute | Red — GPIO 27 |

**Arduino IDE partition:** 8MB with SPIFFS, 3M APP, 1.5M spiffs (required for OTA)

---

## Features

- **Dual independent pedal channels** — each configurable to any mode
- **Three mixer platforms** — WING, X32, XR18 via OSC/UDP over WiFi
- **BLE configuration** — full setup via Flutter app, no serial cable needed
- **OTA firmware updates** — delivered wirelessly through the app
- **TFT display** — shows channel label, name, mute/tap status in real time
- **Scene control** — stomp up/down through scenes; tap to select from app
- **Tap tempo** — sends BPM to FX engine; shows FX name and timing on TFT
- **Scene name refresh** — all channel/bus/FX names update automatically on scene change
- **Dual pedal mode** — secondary pedal mirrors primary via BLE subscription

---

## Supported Modes

| Mode | WING | X32 | XR18 |
|------|:----:|:---:|:----:|
| Tap Tempo | ✅ | ✅ | ✅ |
| Mute Channel | ✅ (36) | ✅ (32) | ✅ (16) |
| Mute Bus | ✅ (16) | ✅ (16) | ✅ (6) |
| Mute Mgrp | ✅ (8) | ✅ (6) | ✅ (4) |
| Mute Aux | ✅ (8) | — | — |
| Mute Main | ✅ (4) | — | — |
| Mute Mtx | ✅ (8) | ✅ (6) | — |
| Mute DCA | ✅ (16) | ✅ (8) | ✅ (4) |
| Mute FX Return | ✅ (8) | ✅ (8) | ✅ (4) |
| Mute Aux In | — | ✅ (8) | ✅ (1) |
| Mute Main ST | — | ✅ | — |
| Mute Main M/C | — | ✅ | — |
| Mute FX Send | — | — | ✅ (4) |
| Mute M/LR | — | — | ✅ |
| Scene Control | ✅ | ✅ | ✅ |

---

## BLE UUIDs

| Characteristic | UUID | Direction | Contents |
|----------------|------|-----------|----------|
| Config R/W | ffe1 | Read/Write | Full JSON config |
| Channel Names | ffe2 | Read | Channel name array |
| FX Names | ffe3 | Read | FX slot names |
| Bus Names | ffe4 | Read | Bus name array |
| Mixer Info | ffe5 | Read | Live status, mute states, scene |
| WING Names | ffe6 | Read | Mgrp, Aux, Main names |
| Common Names | ffe7 | Read | Mtx, DCA, Main ST/M, LR |
| X32 Names | ffe8 | Read | FX Return, Aux In |
| XR18 Names | ffe9 | Read | FX Send, FX Return, AUX |
| Scene Names | ffea | Read | Scene/snapshot name list |
| OTA Control | ffeb | Write | OTA command channel |
| OTA Status | ffec | Read | OTA progress/result |

---

## App — Flutter

**Platforms:** Android, iOS (iPad Mini tested)

**Screens:**
- **Scanner** — BLE device scan and connect
- **Config** — Live pedal status, mute/tap/scene display, virtual pedal graphic
- **Edit Config** — Per-channel mode, target, and scene selection
- **Settings** — WiFi SSID/IP per mixer, secondary pedal toggle
- **OTA** — Firmware update over BLE

**GitHub:** `github.com/goneflyin2002/StompPedalApp`

**iOS deployment (free/pre-App Store):**
- GitHub Actions builds `.ipa` on every push (Flutter 3.41.4)
- AltStore + AltServer for sideloading (7-day signing refresh)

---

## OTA Update Workflow

1. Bump `#define FIRMWARE_VERSION` in `.ino`
2. **Sketch → Export Compiled Binary**
3. Rename to `STOMP_Controller_vXX.X.bin`
4. Upload to `releases/` in `github.com/goneflyin2002/StompPedalFirmware`
5. Update `version.json` (version, url, size, notes)
6. App automatically offers update on next BLE connect

---

## Factory Reset

Hold **both stomp switches** during power-on → LEDs flash 5× → all preferences cleared → reboot

---

## WiFi / OSC

Each mixer type stores its own SSID and IP address in flash. The pedal connects to the correct network automatically based on the configured mixer type.

| Mixer | Default Port |
|-------|-------------|
| WING | 2223 |
| X32 | 10023 |
| XR18 | 10024 |

Subscription renewal: every **9 seconds** (`/xremote` for X32/XR18, `/*S` for WING)

---

## Repositories

| Repo | Contents |
|------|----------|
| `goneflyin2002/StompPedalFirmware` | Firmware binaries + `version.json` for OTA |
| `goneflyin2002/StompPedalApp` | Flutter app source + GitHub Actions iOS build |

---

## Version History

| Version | Summary |
|---------|---------|
| v19.0 | All three mixers complete. Scene name refresh. XR18 live name updates. |
| v18.9 | X32 scene control (`/-action/goscene`). X32 Mgrp. Deferred name refresh. |
| v18.8 | XR18 Mgrp, FX Return (`/rtn/`), AUX (`/rtn/aux`). Bus path fixes. |
| v18.7 | XR18 scene control (`/-snap/load`, 1-based). X32/XR18 scene numbering. |
| v18.6 | WING DCA + Mgrp `queryAndWait` for instant LED response. |
