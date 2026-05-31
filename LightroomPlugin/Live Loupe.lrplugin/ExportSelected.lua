local LrPathUtils = import 'LrPathUtils'
local PluginCore = dofile(LrPathUtils.child(_PLUGIN.path, 'PluginCore.lua'))

PluginCore.runAsync(function()
  PluginCore.exportSelected()
end)
