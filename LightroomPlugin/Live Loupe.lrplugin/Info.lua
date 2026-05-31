-- Live Loupe
-- Author: Artsiom Shabanau  - The Capture Crafter
-- License: MIT

return {
  LrSdkVersion = 6.0,
  LrSdkMinimumVersion = 6.0,
  LrToolkitIdentifier = 'com.local.liveloupe.lightroom',
  LrPluginName = 'Live Loupe',
  LrPluginInfoProvider = 'PluginInfoProvider.lua',
  VERSION = { major = 0, minor = 1, revision = 0, build = 1 },

  LrExportMenuItems = {
    {
      title = 'Start Screen Preview',
      file = 'StartScreenPreview.lua',
    },
    {
      title = 'Start Export Preview',
      file = 'StartLivePreview.lua',
    },
    {
      title = 'Stop Preview',
      file = 'StopLivePreview.lua',
    },
    {
      title = 'Start Preview App',
      file = 'StartApp.lua',
    },
    {
      title = 'Show Live Loupe Diagnostic Log',
      file = 'ShowDiagnosticLog.lua',
    },
  },

  LrLibraryMenuItems = {
    {
      title = 'Start Screen Preview',
      file = 'StartScreenPreview.lua',
    },
    {
      title = 'Start Export Preview',
      file = 'StartLivePreview.lua',
    },
    {
      title = 'Stop Preview',
      file = 'StopLivePreview.lua',
    },
    {
      title = 'Export Selected to Live Loupe',
      file = 'ExportSelected.lua',
    },
    {
      title = 'Start Preview App',
      file = 'StartApp.lua',
    },
    {
      title = 'Choose Preview Folder...',
      file = 'ChoosePreviewFolder.lua',
    },
    {
      title = 'Reveal Preview Folder',
      file = 'RevealPreviewFolder.lua',
    },
    {
      title = 'Show Live Loupe Diagnostic Log',
      file = 'ShowDiagnosticLog.lua',
    },
  },
}
