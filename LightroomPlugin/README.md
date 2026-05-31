# Lightroom Classic Plugin

Install `Live Loupe.lrplugin` through:

```text
Lightroom Classic > File > Plug-in Manager > Add
```

The plugin adds these Library menu commands:

- `Library > Plug-in Extras > Start Export Preview`
- `Library > Plug-in Extras > Stop Preview`
- `Library > Plug-in Extras > Export Selected to Live Loupe`
- `Library > Plug-in Extras > Start Preview App`
- `Library > Plug-in Extras > Choose Preview Folder...`
- `Library > Plug-in Extras > Reveal Preview Folder`
- `Library > Plug-in Extras > Show Live Loupe Diagnostic Log`

It also adds the live commands to `File > Plug-in Extras`, so they are reachable while Lightroom is in Develop.

`Start Export Preview` watches the active Lightroom photo and writes `__lr_live_preview.jpg` into the preview folder. The iPhone page switches to a full-screen live view when this file exists.

Diagnostics are written to `~/Library/Application Support/Live Loupe/live-debug.log`.

`Export Selected to Live Loupe` renders the current Library selection as JPEG/sRGB using the app's export settings, writes into the preview folder, and starts the macOS app with that folder.

The plugin auto-detects the app when it is next to the `.lrplugin` folder, in `/Applications`, or in `~/Applications`. If it cannot find the app, it prompts you to choose it.

This plugin is for Lightroom Classic. The cloud Lightroom desktop app does not support this Lua SDK plugin format.
