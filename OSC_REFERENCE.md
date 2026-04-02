# STOMP Controller — OSC Reference v19.0

Complete OSC address reference for all three supported mixer platforms.

---

## WING

**Connection:** WiFi port 2223  
**Subscription:** `/*S~` — push-based, renewed every 9s  
**Mute logic:** `1` = muted, `0` = unmuted  
**Mgrp logic:** `1` = group active (muting), `0` = off  

### Channel Mute
| Address | Type | Notes |
|---------|------|-------|
| `/ch/NN/mute` | int | Zero padded, 01-36 |
| `/ch/NN/name` | string | Channel name |

### Bus Mute
| Address | Type | Notes |
|---------|------|-------|
| `/bus/NN/mute` | int | Zero padded, 01-16 |
| `/bus/NN/name` | string | Bus name |

### Mute Group
| Address | Type | Notes |
|---------|------|-------|
| `/mgrp/N/mute` | int | Not zero padded, 1-8 |
| `/mgrp/N/name` | string | Mgrp name |

### Aux
| Address | Type | Notes |
|---------|------|-------|
| `/aux/NN/mute` | int | Zero padded, 01-08 |
| `/aux/NN/name` | string | Aux name |

### Main
| Address | Type | Notes |
|---------|------|-------|
| `/main/NN/mute` | int | Zero padded, 01-04 |
| `/main/NN/name` | string | Main name |

### Matrix
| Address | Type | Notes |
|---------|------|-------|
| `/mtx/NN/mute` | int | Zero padded, 01-08 |
| `/mtx/NN/name` | string | Matrix name |

### DCA
| Address | Type | Notes |
|---------|------|-------|
| `/dca/N/mute` | int | Not zero padded, 1-16 |
| `/dca/N/name` | string | DCA name |

### FX Return
| Address | Type | Notes |
|---------|------|-------|
| `/fxrtn/NN/mute` | int | Zero padded, 01-08 |
| `/fxrtn/NN/name` | string | FX Return name |

### Tap Tempo
| Address | Type | Notes |
|---------|------|-------|
| `/fx/NN/time` | float | FX delay time in ms |
| `/fx/NN/mdl` | string | FX model name |

### Scene Control
| Address | Type | Notes |
|---------|------|-------|
| `/$ctl/lib/$action` | string | `"GONEXT"` / `"GOPREV"` / `"GO"` |
| `/$ctl/lib/$actionidx` | int | Target scene index (1-based), 0 = reset |
| `/$ctl/lib/$active` | string | Current scene name (push response) |
| `/$ctl/lib/$actidx` | int | Current scene index (push response) |
| `/$ctl/lib` | string | `"?"` to request node dump of all scene names |

---

## X32

**Connection:** WiFi port 10023  
**Subscription:** `/xremote` — renewed every 9s  
**Mute logic:** `0` = muted, `1` = unmuted  
**Mgrp logic:** `1` = active (muting), `0` = off  

### Channel Mute
| Address | Type | Notes |
|---------|------|-------|
| `/ch/NN/mix/on` | int | Zero padded, 01-32 |
| `/ch/NN/config/name` | string | Channel name |

### Bus Mute
| Address | Type | Notes |
|---------|------|-------|
| `/bus/NN/mix/on` | int | Zero padded, 01-16 |
| `/bus/NN/config/name` | string | Bus name |

### Mute Group
| Address | Type | Notes |
|---------|------|-------|
| `/config/mute/N` | int | Not zero padded, 1-6 |

### Matrix
| Address | Type | Notes |
|---------|------|-------|
| `/mtx/NN/mix/on` | int | Zero padded, 01-06 |
| `/mtx/NN/config/name` | string | Matrix name |

### DCA
| Address | Type | Notes |
|---------|------|-------|
| `/dca/N/on` | int | Not zero padded, 1-8 |
| `/dca/N/config/name` | string | DCA name |

### FX Return
| Address | Type | Notes |
|---------|------|-------|
| `/fxrtn/NN/mix/on` | int | Zero padded, stereo pairs: 01/02=FX1L/R, 03/04=FX2L/R, 05/06=FX3L/R, 07/08=FX4L/R |
| `/fxrtn/NN/config/name` | string | FX Return name |

### Aux In
| Address | Type | Notes |
|---------|------|-------|
| `/auxin/NN/mix/on` | int | Zero padded, 01-08 |
| `/auxin/NN/config/name` | string | Aux In name |

### Main
| Address | Type | Notes |
|---------|------|-------|
| `/main/st/mix/on` | int | Main Stereo |
| `/main/st/config/name` | string | Main ST name |
| `/main/m/mix/on` | int | Main Mono |
| `/main/m/config/name` | string | Main M name |

### Tap Tempo
| Address | Type | Notes |
|---------|------|-------|
| `/fx/N/type` | int | FX type index (maps to name lookup table) |
| `/fx/N/par/01` | float | Delay time for most FX types |
| `/fx/N/par/02` | float | Delay time for Stereo Delay (type 10) |

### Scene Control (Mixer Scenes)
| Address | Type | Notes |
|---------|------|-------|
| `/-action/goscene` | int | Load scene immediately, 0-based (0=scene 0) |
| `/-show/showfile/scene/NNN/name` | string | Scene name, NNN = 000-025 (0-based) |

---

## XR18

**Connection:** WiFi port 10024  
**Subscription:** `/xremote` — renewed every 9s  
**Mute logic:** `0` = muted, `1` = unmuted  
**Mgrp logic:** `1` = active (muting), `0` = off  

### Channel Mute
| Address | Type | Notes |
|---------|------|-------|
| `/ch/NN/mix/on` | int | Zero padded, 01-16 |
| `/ch/NN/config/name` | string | Channel name |

### Bus Mute
| Address | Type | Notes |
|---------|------|-------|
| `/bus/N/mix/on` | int | **Not** zero padded, 1-6 |
| `/bus/N/config/name` | string | Bus name |

### Mute Group
| Address | Type | Notes |
|---------|------|-------|
| `/config/mute/N` | int | Not zero padded, 1-4 |

### DCA
| Address | Type | Notes |
|---------|------|-------|
| `/dca/N/on` | int | Not zero padded, 1-4 |
| `/dca/N/config/name` | string | DCA name |

### FX Return
| Address | Type | Notes |
|---------|------|-------|
| `/rtn/N/mix/on` | int | Not zero padded, 1-4 |
| `/rtn/N/config/name` | string | FX Return name |

### AUX (single)
| Address | Type | Notes |
|---------|------|-------|
| `/rtn/aux/mix/on` | int | Single aux input |
| `/rtn/aux/config/name` | string | AUX name |

### FX Send
| Address | Type | Notes |
|---------|------|-------|
| `/fxsend/N/mix/on` | int | Not zero padded, 1-4 |
| `/fxsend/N/config/name` | string | FX Send name |

### Main LR
| Address | Type | Notes |
|---------|------|-------|
| `/lr/mix/on` | int | Main LR |
| `/lr/config/name` | string | LR name |

### Tap Tempo
| Address | Type | Notes |
|---------|------|-------|
| `/fx/N/type` | int | FX type index |
| `/fx/N/par/01` | float | Delay time for most FX types |
| `/fx/N/par/02` | float | Delay time for Stereo Delay (type 10) |

### Scene Control (Snapshots)
| Address | Type | Notes |
|---------|------|-------|
| `/-snap/load` | int | Load snapshot immediately, 1-based (1=snapshot 1) |
| `/-snap/index` | int | Current snapshot index, 1-based (query/response) |
| `/-snap/name` | string | Current snapshot name (response) |
| `/-snap/NN/name` | string | Snapshot name by slot, NN = 01-25 (1-based) |

---

## Mute Value Summary

| Mixer | Mute | Unmute |
|-------|------|--------|
| WING (all modes) | `1` | `0` |
| X32 (all modes) | `0` | `1` |
| XR18 (all modes) | `0` | `1` |
| WING/X32/XR18 Mgrp | `1` = active | `0` = off |

---

## Scene Numbering Summary

| Mixer | Internal | Display | App Dropdown |
|-------|----------|---------|--------------|
| WING | 1-based | SNAP 1, 2... | Scene 1, 2... |
| X32 | 0-based | SNAP 0, 1... | Scene 0, 1... |
| XR18 | 1-based | SNAP 1, 2... | Scene 1, 2... |

---

## BLE Config JSON Structure

```json
{
  "channelA": {
    "mode": 1,
    "muteChannel": 6,
    "muteBus": 1,
    "muteMgrp": 1,
    "muteAux": 1,
    "muteMain": 1,
    "muteMtx": 1,
    "muteDca": 1,
    "muteFxrtn": 1,
    "muteAuxin": 1,
    "muteFxsend": 1,
    "fxNum": 1
  },
  "channelB": {
    "mode": 14,
    "sceneNum": 1
  },
  "mixer": {
    "type": 0,
    "ssid": "MyNetwork",
    "ipWING": "192.168.1.100",
    "ipX32": "192.168.1.101",
    "ipXR18": "192.168.1.102"
  },
  "tapFlashMode": 1,
  "secondaryPedal": false,
  "sceneJump": 5
}
```

**Mode numbers:**

| Mode | Name |
|------|------|
| 0 | Tap Tempo |
| 1 | Mute Channel |
| 2 | Mute Bus |
| 3 | Mute Mgrp |
| 4 | Mute Aux (WING) |
| 5 | Mute Main (WING) |
| 6 | Mute Mtx |
| 7 | Mute DCA |
| 8 | Mute FX Return |
| 9 | Mute Aux In (X32) / AUX (XR18) |
| 10 | Mute Main ST (X32) |
| 11 | Mute Main M/C (X32) |
| 12 | Mute FX Send (XR18) |
| 13 | Mute M/LR (XR18) |
| 14 | Scene Control |
