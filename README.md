# STOMP Controller
### Wireless Dual-Channel Stomp Pedal for Live Audio Mixers
**by DM — v18.4 — March 2026**

---

## Overview

STOMP is a wireless two-channel stomp pedal system for live audio mixing. Each channel independently controls a target on a connected Behringer mixer — muting channels, buses, DCAs, or controlling tap tempo and scene recall — all via OSC over 5 GHz WiFi. The pedal is configured wirelessly from an Android companion app over Bluetooth Low Energy (BLE).

No laptop, no USB, no web browser — just stomp and mix.

---

## Hardware

| Component | Part |
|-----------|------|
| MCU | ESP32-C5-DEVKITC-1-N8R8 (5 GHz WiFi + BLE) |
| Display | 3.5" ILI9486 TFT, 480×320 SPI |
| Stomp switches | 2× SPST momentary foot switches |

**GPIO Pinout**

| Signal | GPIO |
|--------|------|
| Stomp A | 26 |
| Stomp B | 25 |
| LED A — TAP (blue) | 24 |
| LED A — MUTE (red) | 23 |
| LED B — TAP (blue) | 28 |
| LED B — MUTE (red) | 27 |
| TFT MOSI | 4 |
| TFT SCLK | 3 |
| TFT CS | 10 |
| TFT DC | 8 |
| TFT RST | 9 |

---

## Supported Mixers

| Mixer | Protocol | Update Method |
|-------|----------|---------------|
| Behringer WING | OSC / UDP | `/*S` subscription — instant push |
| Behringer X32 | OSC / UDP | `/xremote` + 200 ms polling |
| Behringer XR18 | OSC / UDP | `/xremote` + 200 ms polling |

Each mixer stores its own IP address. Switching between mixers is done in the app — the pedal reconnects automatically.

---

## Stomp Modes

Each channel (A and B) is independently configurable to any of the following modes.

### Behringer WING — 9 modes
| Mode | Description |
|------|-------------|
| **Tap Tempo** | Sets FX delay time. First tap queries FX type; subsequent taps calculate interval and send `/fx/XX/time` in milliseconds. LED flashes at tempo. |
| **Mute Channel** | Toggles mute on channels 1–36 |
| **Mute Bus** | Toggles mute on buses 1–16 |
| **Mute Mgrp** | Toggles mute groups 1–8 |
| **Mute Aux** | Toggles aux sends 1–8 |
| **Mute Main** | Toggles main outputs 1–4 |
| **Mute Mtx** | Toggles matrix outputs 1–8 |
| **Mute DCA** | Toggles DCA groups 1–16 |
| **Scene Control** | Tap = next scene, long press = previous scene |

### Behringer X32 — 10 modes
| Mode | Description |
|------|-------------|
| **Tap Tempo** | Sets FX delay time. Queries `/fx/X/type` to determine correct parameter; sends normalised float to `/fx/X/par/NN` |
| **Mute Channel** | Channels 1–32 |
| **Mute Bus** | Buses 1–16 |
| **Mute Mtx** | Matrix 1–6 |
| **Mute DCA** | DCA groups 1–8 |
| **Mute FX Rtn** | FX returns 1–8 |
| **Mute Aux In** | Aux inputs 1–8 |
| **Mute Main ST** | Main stereo bus |
| **Mute Main C** | Main mono bus |
| **Scene Control** | Tap = next snapshot, long press = previous snapshot |

### Behringer XR18 — 7 modes
| Mode | Description |
|------|-------------|
| **Tap Tempo** | Sets FX delay time |
| **Mute Channel** | Channels 1–16 |
| **Mute Bus** | Buses 1–6 |
| **Mute DCA** | DCA groups 1–4 |
| **Mute FX Send** | FX sends 1–4 |
| **Mute Main LR** | Main LR bus |
| **Scene Control** | Tap = next snapshot, long press = previous snapshot |

---

## Tap Tempo

- **First stomp** — queries the FX type for the configured slot, arms timing
- **Subsequent stomps** — calculates interval, sends tempo to mixer
- **Timeout** — 3 000 ms of no stomps resets the tap sequence; next press is a fresh first tap
- **LED flash modes** (configurable in app):
  - Off — LED stays dark
  - 20× — flashes 20 times then holds
  - Continuous — flashes indefinitely at tempo
- **WING** sends milliseconds directly: `/fx/XX/time`
- **X32/XR18** sends normalised float (0.0–1.0) to the correct parameter for the detected FX type

---

## Scene / Snapshot Control

| Action | Result |
|--------|--------|
| Short press (< 333 ms) | Advance to next scene/snapshot |
| Long press (≥ 333 ms) | Step back to previous scene/snapshot |

**WING OSC:** `/$ctl/lib/$action` with value `GONEXT` or `GOPREV`  
**X32/XR18 OSC:** `/-snap/index` (set new index) → `/-snap/recall` (fire)

Up to 25 scene/snapshot names are fetched from the mixer at startup and cached. The TFT displays the current scene name and number. The companion app mirrors the current snapshot in real time.

---

## Dual Pedal Mode

Two pedals can run simultaneously on the same mixer without conflicting.

| Mode | Behaviour |
|------|-----------|
| **Primary** | Holds the `/*S` subscription (WING) or renews `/xremote` (X32/XR18). Receives instant push updates from the mixer. |
| **Secondary** | Polls every 200 ms instead of subscribing. Safe alongside a primary. Displays a `2ND` badge on the TFT. |

Configure in the app under Settings → Secondary Pedal.

---

## Android App

The companion app connects to the pedal over BLE and provides:

### Main Screen
- Live pedal graphic showing current LED states (TAP blue, MUTE red)
- Virtual TFT display mirroring the pedal screen — shows channel mode, mute state, BPM, or current scene/snapshot
- Channel status labels showing `ON`, `MUTED`, `TAP!`, `175 BPM`, or `SNAP 3`
- Stomp channel cards (A and B) showing mode and target name
- Pull-down to force a full refresh from the pedal

### Edit Channel Config
- Select mode for channel A or B
- Choose the specific channel, bus, DCA, FX slot, or scene target
- Available modes filtered by mixer type — only relevant options shown

### Settings Screen
- WiFi network (SSID + password)
- Mixer type (WING / X32 / XR18) and IP address per mixer — each stored independently
- Tap tempo LED flash mode (Off / 20× / Continuous)
- Secondary pedal mode toggle
- Firmware version display and OTA update trigger

### OTA Firmware Update
- Checks GitHub for newer firmware automatically on connect
- Downloads binary over WiFi, transfers to pedal over BLE in 199-byte chunks
- Dual progress bars (download + flash)
- TFT shows progress bar; all OSC paused during flash
- Pedal reboots automatically into new firmware on completion

---

## BLE Characteristics

| UUID | Name | Access | Contents |
|------|------|--------|----------|
| ffe1 | Config | R/W | Full pedal configuration JSON |
| ffe2 | Channel Names | R | Mixer channel name array |
| ffe3 | FX Names | R | FX slot name array |
| ffe4 | Bus Names | R | Bus name array |
| ffe5 | Mixer Info | R | Live status: WiFi, mute state, BPM, scene, firmware version |
| ffe6 | WING Names | R | Mute group / aux / main names |
| ffe7 | Common Names | R | Matrix / DCA names |
| ffe8 | X32 Names | R | FX return / aux in names |
| ffe9 | XR18 Names | R | FX send names |
| ffea | Scene Names | R | Scene/snapshot name array (up to 25) |
| ffeb | OTA Control | W | OTA JSON commands and binary chunks |
| ffec | OTA Status | Notify | OTA progress percentage and result |

All characteristics under service `0000ffe0-0000-1000-8000-00805f9b34fb`.

---

## Factory Reset

Hold **both stomp switches** during power-on. LEDs flash 5 times to confirm, then all saved settings are cleared and the pedal reboots to defaults.

---

## OTA Update Workflow

1. Make changes in Arduino IDE
2. Update `#define FIRMWARE_VERSION` in the `.ino` file
3. **Sketch → Export Compiled Binary**
4. Rename the `.bin` to `STOMP_Controller_vXX.X.bin`
5. Upload to `releases/` folder in the GitHub repo (`goneflyin2002/StompPedalFirmware`)
6. Update `version.json` at the repo root with new version, URL, size, and release notes
7. App automatically offers the update on next BLE connect

**Arduino IDE partition scheme:** No FS, 4MB with 2MB APP × 2 (required for OTA)

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| **v18.4** | Mar 2026 | Scene/snapshot control for X32 and XR18. App pedal graphic with live LED mirroring. 1-second BLE refresh for near-realtime status. Scene mode shown in app mode selector for all mixer types. |
| v18.3 | Mar 2026 | Hybrid primary/secondary dual-pedal mode. OTA firmware update via BLE and GitHub. X32 FX type detection and correct tap tempo parameter routing. |
| v18.2 | Mar 2026 | WiFi reconnect detection with auto-refresh. Config JSON kept under 512-byte BLE MTU. |
| v18.0 | Mar 2026 | Multi-mixer support (WING / X32 / XR18). BLE Android app. Scene control for WING. |
| v12.0 | Feb 2026 | Hybrid subscription model. Full name fetch at startup; `/*S` / `/xremote` for live updates. |
