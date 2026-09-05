## BatteryMu

A live battery monitor for **[muOS](https://muos.dev/) Andromeda** on the
**Anbernic RG35XX family** (all Allwinner H700 — Pro, Plus, H, SP, 2024).
Built with LÖVE2D on the shared **[fskit](#-built-on-fskit)** kit. Jacaranda-compatible.

### 🚀 Features
- Live charge %, voltage, and charge/discharge state
- Health readout: design vs. current voltage window, reported battery health
- Charge history graph from the muOS `battery_usage` tracker (last charged,
  time on battery, capacity at unplug)
- Reads muOS's pre-parsed battery values first, falling back to raw AXP2202
  sysfs — identical across every RG35XX variant
- 8-colour in-app theme picker shared with ClockMu and JarMu
- Letterboxed 640×480 render — safe on every RG35XX panel variant, and on HDMI-out

### 📥 Installation
1. Download the latest `.muxapp` from [Releases](https://github.com/fragilesilver/BatteryMu/releases).
2. Copy it to `ARCHIVE/` on your SD card.
3. On the device: **Applications → Archive Manager**, select the file.
4. Launch from **Applications → BatteryMu**.

### 🎮 Controls

#### Main Screen
| Button | Action |
|--------|--------|
| **A** | Health & voltage detail |
| **X** | Charge history graph |
| **Y** | Theme picker |
| **B** | Quit |

#### Health / Graph Screens
| Button | Action |
|--------|--------|
| **B** | Back to main |

#### Theme Picker
| Button | Action |
|--------|--------|
| Up/Down | Move selection |
| **A** | Apply theme |
| **B** | Cancel |

### 💾 Data Persistence

The selected theme is written to `save/settings.txt` under the app directory
(via the `BATTERYMU_DATA` path the launcher exports), independent of LÖVE's
save-dir resolution under muOS bind-storage.

### 📝 Notes

- Battery figures update once per second; the theme is saved on a 30-second cadence.
- On a fully charged or freshly booted device the history tracker may be empty
  until the first charge/unplug cycle.
- The launcher does not touch audio — BatteryMu is silent.

### 🎨 Themes

Eight in-app colour themes (BatteryMu's own picker, not a muOS theme), matching
ClockMu and JarMu: Mustard (default), Intense Orange, Bloody Red, Ocean Blue,
Forest Green, Funky Purple, Yoga White, Midnight Black.

### 🧩 Built on fskit

BatteryMu, [ClockMu](https://github.com/fragilesilver/ClockMu) and
[JarMu](https://github.com/fragilesilver/JarMu) share **fskit** — a small LÖVE2D
kit providing the letterboxed 640×480 screen, the theme model and palette, fonts,
glyphs, input abstraction and the header/footer chrome — so the three apps look,
feel and behave the same on every RG35XX variant.

### 🙏 Credits

- LÖVE2D aarch64 runtime by [Cebion/love2d_aarch64](https://github.com/Cebion/love2d_aarch64)
- Built for the muOS community

### 📄 Licence

GPL-3.0-or-later. See [LICENSE](LICENSE).

---

Part of the **fragilesilver** muOS app family — [ClockMu](https://github.com/fragilesilver/ClockMu) · [JarMu](https://github.com/fragilesilver/JarMu) · [BatteryMu](https://github.com/fragilesilver/BatteryMu).
