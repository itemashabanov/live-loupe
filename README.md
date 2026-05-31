# Live Loupe

**See your Lightroom edits on your iPhone, live, over local Wi-Fi — no Adobe sync, no cloud, no uploads.**

Live Loupe is a tiny macOS utility (plus an optional Lightroom Classic plugin) that turns a local preview-export folder into an iPhone-friendly gallery on the same Wi-Fi network. Your Mac serves the selected folder directly to your phone; photos never leave your network.

![platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)
![swift](https://img.shields.io/badge/Swift-6.0-orange)
![license](https://img.shields.io/badge/license-MIT-green)

---

## Why

When you're editing in Lightroom Classic, the laptop screen rarely matches how a shot reads on a phone — the device most of your photos are actually viewed on. Live Loupe gives you a real-time, full-screen preview on your iPhone while you cull and edit, with zero cloud round-trips.

## Features

- 📡 **Local-only** — the Mac serves photos over your Wi-Fi; nothing is uploaded anywhere.
- 🖼️ **Folder gallery** — point it at any folder of exported previews and browse them on your phone.
- 🔴 **Live preview** — mirror the photo you're currently editing in Lightroom, full-screen, auto-refreshing.
- 📱 **QR pairing** — scan a code with the iPhone camera; no app to install on the phone, just Safari.
- 🔌 **Lightroom Classic plugin** — start previews and export selections straight from Lightroom menus.
- 🔒 **No Adobe sync, no account, no telemetry.**

## Requirements

- macOS 14 (Sonoma) or later
- An iPhone on the **same Wi-Fi network** as the Mac
- Adobe Lightroom Classic — only for the optional plugin (the standalone app works with any folder of images)
- [Swift 6 toolchain / Xcode](https://developer.apple.com/xcode/) — only if building from source

---

## Install

### Build from source

```bash
git clone https://github.com/itemashabanov/live-loupe.git
cd live-loupe
./Scripts/package-app.sh
```

The packaged app and a shareable kit are written to:

```text
.build/Live Loupe.app        # the app
.build/Live Loupe.zip        # zipped app
.build/Live Loupe Kit.zip    # app + Lightroom plugin together
```

Move `Live Loupe.app` to `/Applications` (or `~/Applications`).

> The app is **ad-hoc signed** for local use. On first launch macOS Gatekeeper may warn that the developer is unidentified — right-click the app → **Open** → **Open** to allow it. To distribute it broadly without warnings, sign and notarize it with an Apple Developer ID.

---

## Usage

### Mode 1 — Standalone app

1. Open **Live Loupe**.
2. Choose the folder Lightroom exports previews into (or drag the folder onto the window).
3. Click **Start** to launch the server.
4. On the iPhone, scan the QR code with the Camera app, or open the shown URL in Safari.

> The iPhone and Mac must be on the same Wi-Fi network. If macOS asks whether to allow incoming network connections, **Allow**.

The ⚙️ gear button opens the export settings used by the Lightroom Classic plugin.

### Mode 2 — Lightroom Classic plugin

Install `Live Loupe.lrplugin` (found in the `Kit` zip, or in `LightroomPlugin/`):

```text
Lightroom Classic → File → Plug-in Manager → Add…
```

Then use the new menu commands under **Library → Plug-in Extras** (also mirrored under **File → Plug-in Extras** so they work while in Develop):

| Command | What it does |
|---|---|
| **Start Export Preview** | Watches the active photo and writes a live JPEG the iPhone shows full-screen, auto-refreshing. |
| **Stop Preview** | Stops the live preview. |
| **Export Selected to Live Loupe** | Renders the current selection (JPEG / sRGB) into the preview folder and launches the app. |
| **Start Preview App** | Opens the macOS app with the preview server running. |
| **Choose Preview Folder…** | Sets the folder to export into. |
| **Reveal Preview Folder** | Opens that folder in Finder. |
| **Show Live Loupe Diagnostic Log** | Opens the diagnostics log. |

For the lowest live-preview latency, start it from **Develop** via `File → Plug-in Extras` (or let the plugin switch to Develop when started from Library). Live preview has its own size/quality settings, so final preview exports can stay at JPEG quality 100 while live monitoring stays fast.

> The plugin is for **Lightroom Classic**. The cloud Lightroom desktop app does not support this Lua SDK plugin format.

---

## Recommended Lightroom export preset

Use a fast preview preset for the export folder:

| Setting | Value |
|---|---|
| Format | JPEG |
| Color Space | sRGB |
| Quality | 100 |
| Resize (long edge) | ~2000–2556 px |
| Output Sharpening | Screen |
| Destination | the folder selected in the app |

## File locations

```text
~/Library/Application Support/Live Loupe/export-settings.conf   # export settings
~/Library/Application Support/Live Loupe/live-debug.log         # plugin diagnostics
```

## Troubleshooting

- **iPhone can't load the page** — confirm both devices are on the same Wi-Fi (not a guest / AP-isolated network), and that you allowed incoming connections when macOS prompted.
- **Live preview not switching in** — make sure *Start Export Preview* is running; check the diagnostic log above.
- **Gatekeeper blocks the app** — right-click → **Open** the first time (see the Install note).

## Privacy

Live Loupe does not use Adobe sync and does not upload photos anywhere. The Mac serves the selected folder only on the local network, only while the app is running. This is an unofficial tool and is not affiliated with Adobe or Lightroom.

## Author

Created by **Artsiom Shabanau — The Capture Crafter**.

## License

Released under the [MIT License](LICENSE).
