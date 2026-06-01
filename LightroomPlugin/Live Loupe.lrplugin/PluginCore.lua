local LrApplication = import 'LrApplication'
local LrApplicationView = import 'LrApplicationView'
local LrDate = import 'LrDate'
local LrDevelopController = import 'LrDevelopController'
local LrDialogs = import 'LrDialogs'
local LrExportSession = import 'LrExportSession'
local LrFileUtils = import 'LrFileUtils'
local LrFunctionContext = import 'LrFunctionContext'
local LrPathUtils = import 'LrPathUtils'
local LrPrefs = import 'LrPrefs'
local LrShell = import 'LrShell'
local LrTasks = import 'LrTasks'

local PluginCore = {}

local prefs = LrPrefs.prefsForPlugin()
local defaultPort = 8765
local appName = 'Live Loupe.app'
local livePreviewFileName = '__lr_live_preview.jpg'
local liveStateKey = 'LIVE_LOUPE_LIVE_STATE'

local function trim(value)
  return tostring(value or ''):match('^%s*(.-)%s*$')
end

local function booleanValue(value, fallback)
  value = trim(value):lower()
  if value == 'true' or value == '1' or value == 'yes' then
    return true
  end

  if value == 'false' or value == '0' or value == 'no' then
    return false
  end

  return fallback
end

local function clampNumber(value, fallback, minValue, maxValue)
  local number = tonumber(value)
  if not number then
    return fallback
  end

  if number < minValue then
    return minValue
  end

  if number > maxValue then
    return maxValue
  end

  return number
end

local function shellQuote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function urlEncode(value)
  return tostring(value or ''):gsub("([^%w%-_%.~])", function(character)
    return string.format("%%%02X", string.byte(character))
  end)
end

local function liveLoupeLaunchURL(folder, mode, port)
  return table.concat({
    'liveloupe://start?folder=',
    urlEncode(folder),
    '&port=',
    tostring(port or defaultPort),
    '&mode=',
    urlEncode(mode or 'export'),
    '&start=1',
  })
end

local function ensureFolder(path)
  if not path or path == '' then
    return nil
  end

  LrFileUtils.createAllDirectories(path)
  return path
end

local function defaultPreviewFolder()
  local pictures = LrPathUtils.getStandardFilePath('pictures')
  return LrPathUtils.child(pictures, 'Live Loupe')
end

local function fileExists(path)
  return path and LrFileUtils.exists(path) == 'file'
end

local function directoryExists(path)
  return path and LrFileUtils.exists(path) == 'directory'
end

local function liveState()
  _G[liveStateKey] = _G[liveStateKey] or {
    running = false,
    stop = false,
    forceRender = false,
    changeSerial = 0,
    lastSignature = nil,
    lastRenderAt = nil,
    lastError = nil,
  }

  return _G[liveStateKey]
end

-- Timing log to diagnose live-preview latency. Writes to:
--   ~/Library/Application Support/Live Loupe/live-debug.log
local liveDebug = true

local function debugLogPath()
  local folder = LrPathUtils.child(
    LrPathUtils.getStandardFilePath('home'),
    'Library/Application Support/Live Loupe'
  )
  LrFileUtils.createAllDirectories(folder)
  return LrPathUtils.child(folder, 'live-debug.log')
end

local function debugLog(message)
  if not liveDebug then
    return
  end

  pcall(function()
    local path = debugLogPath()
    local f = io.open(path, 'a')
    if f then
      local safeMessage = tostring(message):gsub('[\r\n]+', ' | ')
      f:write(string.format('%s  %.3f  plugin  %s\n', os.date('%Y-%m-%d %H:%M:%S'), LrDate.currentTime(), safeMessage))
      f:close()
    end
  end)
end

local function debugLogSession(message)
  debugLog('--- ' .. message .. ' ---')
end

local function runtimeStateConfigPath()
  local folder = LrPathUtils.child(
    LrPathUtils.getStandardFilePath('home'),
    'Library/Application Support/Live Loupe'
  )
  LrFileUtils.createAllDirectories(folder)
  return LrPathUtils.child(folder, 'runtime-state.conf')
end

local function readRuntimeState()
  local path = runtimeStateConfigPath()
  local file = io.open(path, 'r')
  if not file then
    return nil
  end

  local state = {}
  for line in file:lines() do
    local key, value = tostring(line):match('^%s*([^=]+)%s*=%s*(.-)%s*$')
    if key and value then
      state[trim(key)] = trim(value)
    end
  end
  file:close()
  return state
end

local function writeRuntimeState(mode, running)
  local path = runtimeStateConfigPath()
  local file = io.open(path, 'w')
  if not file then
    return
  end

  file:write('mode=' .. tostring(mode or 'export') .. '\n')
  file:write('running=' .. (running and 'true' or 'false') .. '\n')
  file:write('updatedAt=' .. tostring(LrDate.currentTime()) .. '\n')
  file:close()
end

local function appAllowsLiveExport()
  local state = readRuntimeState()
  if not state then
    return true, 'missing', 'unknown'
  end

  local mode = tostring(state.mode or 'export')
  local running = tostring(state.running or 'true')
  return mode == 'export' and running ~= 'false', mode, running
end

local function safeRawMetadata(photo, key)
  local ok, value = LrTasks.pcall(function()
    return photo:getRawMetadata(key)
  end)
  if ok then
    return value
  end
  return nil
end

local function photoLabel(photo)
  if not photo then
    return 'nil'
  end

  return tostring(photo.localIdentifier or safeRawMetadata(photo, 'uuid') or safeRawMetadata(photo, 'fileName') or 'unknown')
end

local function stableSerialize(value, depth)
  depth = depth or 0
  if type(value) ~= 'table' or depth > 4 then
    return tostring(value)
  end

  local keys = {}
  for key in pairs(value) do
    keys[#keys + 1] = key
  end
  table.sort(keys, function(left, right)
    return tostring(left) < tostring(right)
  end)

  local parts = {}
  for _, key in ipairs(keys) do
    parts[#parts + 1] = tostring(key) .. '=' .. stableSerialize(value[key], depth + 1)
  end
  return table.concat(parts, ';')
end

-- Full develop settings are expensive. Use this only as a periodic fallback
-- because Develop observer callbacks can be unreliable in some Lightroom builds.
local function developSignature(photo)
  local t0 = LrDate.currentTime()
  local ok, settings = LrTasks.pcall(function()
    return photo:getDevelopSettings()
  end)

  if ok and type(settings) == 'table' then
    local signature = tostring(photo.localIdentifier or '') .. '|' .. stableSerialize(settings)
    return signature, true, LrDate.currentTime() - t0, #signature
  end

  return tostring(photo.localIdentifier or ''), false, LrDate.currentTime() - t0, 0, settings
end

local function cheapPhotoSignature(photo, state)
  return table.concat({
    tostring(photo.localIdentifier or ''),
    tostring(safeRawMetadata(photo, 'uuid') or ''),
    tostring(safeRawMetadata(photo, 'lastEditTime') or ''),
    tostring(safeRawMetadata(photo, 'editCount') or ''),
    tostring(state.changeSerial or 0),
  }, '|')
end

local function liveRenderTempFolder()
  local folder = LrPathUtils.child(
    LrPathUtils.getStandardFilePath('home'),
    'Library/Application Support/Live Loupe/live-render'
  )
  LrFileUtils.createAllDirectories(folder)
  return folder
end

-- Renders the photo through Lightroom's export pipeline (Camera Raw), the only
-- SDK path that reflects the CURRENT Develop adjustments: requestJpegThumbnail
-- returns a stale cached preview and fails outright while Develop is active. The
-- render is expensive (full-res demosaic), so the caller debounces and runs ONE
-- render per change, and only one live task ever runs at a time (generation
-- token) -- concurrent renders murder X-Trans demosaic throughput.
local function renderLivePhoto(photo, folder)
  local t0 = LrDate.currentTime()
  local settings = PluginCore.exportSettings()
  local livePath = LrPathUtils.child(folder, livePreviewFileName)
  local liveTempPath = livePath .. '.tmp'
  local tempFolder = liveRenderTempFolder()
  local longEdge = settings.liveLongEdge -- NUMBER; a string makes LR export 1x1

  debugLog(string.format(
    'render START photo=%s livePath=%s longEdge=%d quality=%.2f',
    photoLabel(photo),
    livePath,
    longEdge,
    settings.liveJpegQuality
  ))

  local exportSession = LrExportSession({
    photosToExport = { photo },
    exportSettings = {
      LR_export_destinationType = 'specificFolder',
      LR_export_destinationPathPrefix = tempFolder,
      LR_export_useSubfolder = false,
      LR_collisionHandling = 'overwrite',

      LR_format = 'JPEG',
      LR_export_colorSpace = 'sRGB',
      LR_jpeg_quality = settings.liveJpegQuality,
      LR_jpeg_useLimitSize = false,

      LR_size_doConstrain = true,
      LR_size_doNotEnlarge = true,
      LR_size_maxHeight = longEdge,
      LR_size_maxWidth = longEdge,
      LR_size_resizeType = 'longEdge',
      LR_size_units = 'pixels',

      LR_outputSharpeningOn = false,
      LR_useWatermark = false,
      LR_minimizeEmbeddedMetadata = true,
      LR_removeLocationMetadata = true,
      LR_reimportExportedPhoto = false,
    },
  })

  local t1 = LrDate.currentTime()

  for _, rendition in exportSession:renditions() do
    local success, pathOrMessage = rendition:waitForRender()
    local t2 = LrDate.currentTime()

    if not success then
      debugLog(string.format('render FAIL setup=%.2f wait=%.2f : %s',
        t1 - t0, t2 - t1, tostring(pathOrMessage)))
      return false, pathOrMessage or 'Lightroom could not render the live preview.'
    end

    if LrFileUtils.exists(liveTempPath) then
      LrFileUtils.delete(liveTempPath)
    end

    local moved, moveError = LrFileUtils.move(pathOrMessage, liveTempPath)
    if not moved then
      if LrFileUtils.exists(pathOrMessage) then
        LrFileUtils.delete(pathOrMessage)
      end
      debugLog(string.format('render MOVE_FAIL temp=%s message=%s', liveTempPath, tostring(moveError)))
      return false, moveError or 'Could not place the live preview file.'
    end

    if LrFileUtils.exists(livePath) then
      LrFileUtils.delete(livePath)
    end

    local replaced, replaceError = LrFileUtils.move(liveTempPath, livePath)

    if not replaced then
      if LrFileUtils.exists(liveTempPath) then
        LrFileUtils.delete(liveTempPath)
      end
      debugLog(string.format('render REPLACE_FAIL livePath=%s message=%s', livePath, tostring(replaceError)))
      return false, replaceError or 'Could not replace the live preview file.'
    end

    debugLog(string.format('render OK setup=%.2f waitForRender=%.2f total=%.2f longEdge=%d q=%.2f',
      t1 - t0, t2 - t1, LrDate.currentTime() - t0, longEdge, settings.liveJpegQuality))
    return true
  end

  return false, 'Lightroom returned no rendition for the live preview.'
end

local function currentTargetPhoto()
  local catalog = LrApplication.activeCatalog()

  local ok, photo = LrTasks.pcall(function()
    return catalog:getTargetPhoto()
  end)
  if ok and photo then
    return photo
  end

  local okPhotos, photos = LrTasks.pcall(function()
    return catalog:getTargetPhotos()
  end)
  if okPhotos and photos and #photos > 0 then
    return photos[1]
  end

  return nil
end

local function ensureDevelopModuleForLive()
  local ok, result = LrTasks.pcall(function()
    local moduleName = LrApplicationView.getCurrentModuleName()
    debugLog('module before live start=' .. tostring(moduleName))

    if moduleName and moduleName ~= 'develop' then
      LrApplicationView.switchToModule('develop')

      local deadline = LrDate.currentTime() + 3
      repeat
        LrTasks.sleep(0.1)
        moduleName = LrApplicationView.getCurrentModuleName()
      until moduleName == 'develop' or LrDate.currentTime() >= deadline
    end

    debugLog('module after live start=' .. tostring(moduleName))
    return moduleName == 'develop'
  end)

  if not ok then
    debugLog('module switch ERROR ' .. tostring(result))
    return false
  end

  if not result then
    debugLog('module switch WARNING Develop module is not active; observer may not register')
  end

  return result
end

local function exportSettingsConfigPath()
  return LrPathUtils.child(
    LrPathUtils.getStandardFilePath('home'),
    'Library/Application Support/Live Loupe/export-settings.conf'
  )
end

function PluginCore.exportSettings()
  local settings = {
    jpegQuality = 100,
    longEdgePixels = 2556,
    outputSharpening = true,
    minimizeMetadata = true,
    removeLocationMetadata = true,
    -- Live preview is a monitor, not a deliverable. Keep it intentionally
    -- small so each Camera Raw pass can finish fast enough to be usable.
    livePreviewLongEdge = 720,
    livePreviewQuality = 45,
  }

  local file = io.open(exportSettingsConfigPath(), 'r')
  if file then
    for line in file:lines() do
      local key, value = line:match('^([%w_]+)=(.*)$')
      if key == 'jpegQuality' then
        settings.jpegQuality = clampNumber(value, settings.jpegQuality, 1, 100)
      elseif key == 'longEdgePixels' then
        settings.longEdgePixels = clampNumber(value, settings.longEdgePixels, 512, 6000)
      elseif key == 'outputSharpening' then
        settings.outputSharpening = booleanValue(value, settings.outputSharpening)
      elseif key == 'minimizeMetadata' then
        settings.minimizeMetadata = booleanValue(value, settings.minimizeMetadata)
      elseif key == 'removeLocationMetadata' then
        settings.removeLocationMetadata = booleanValue(value, settings.removeLocationMetadata)
      elseif key == 'livePreviewLongEdge' then
        settings.livePreviewLongEdge = clampNumber(value, settings.livePreviewLongEdge, 320, 2000)
      elseif key == 'livePreviewQuality' then
        settings.livePreviewQuality = clampNumber(value, settings.livePreviewQuality, 1, 100)
      end
    end
    file:close()
  end

  settings.lrJpegQuality = settings.jpegQuality / 100
  settings.longEdgeText = tostring(math.floor(settings.longEdgePixels))
  settings.liveLongEdge = math.floor(settings.livePreviewLongEdge)
  settings.liveJpegQuality = settings.livePreviewQuality / 100
  return settings
end

function PluginCore.previewFolder()
  local folder = prefs.previewFolder
  if not folder or folder == '' then
    folder = defaultPreviewFolder()
    prefs.previewFolder = folder
  end

  return ensureFolder(folder)
end

function PluginCore.choosePreviewFolder()
  local selected = LrDialogs.runOpenPanel({
    title = 'Choose Live Loupe Folder',
    prompt = 'Choose',
    canChooseFiles = false,
    canChooseDirectories = true,
    allowsMultipleSelection = false,
    canCreateDirectories = true,
    initialDirectory = PluginCore.previewFolder(),
  })

  if selected and #selected > 0 then
    prefs.previewFolder = selected[1]
    ensureFolder(prefs.previewFolder)
    LrDialogs.message('Live Loupe', 'Preview folder set to:\n' .. prefs.previewFolder, 'info')
    return prefs.previewFolder
  end

  return nil
end

function PluginCore.port()
  local stored = tonumber(prefs.serverPort)
  if not stored or stored < 1 or stored > 65535 then
    stored = defaultPort
    prefs.serverPort = stored
  end

  return stored
end

function PluginCore.findAppPath()
  local candidates = {
    prefs.appPath,
    LrPathUtils.child(LrPathUtils.parent(_PLUGIN.path), appName),
    LrPathUtils.child(LrPathUtils.parent(LrPathUtils.parent(_PLUGIN.path)), appName),
    '/Applications/' .. appName,
    LrPathUtils.child(LrPathUtils.getStandardFilePath('home'), 'Applications/' .. appName),
  }

  for _, candidate in ipairs(candidates) do
    if directoryExists(candidate) then
      prefs.appPath = candidate
      return candidate
    end
  end

  return nil
end

function PluginCore.chooseAppPath()
  local selected = LrDialogs.runOpenPanel({
    title = 'Choose Live Loupe.app',
    prompt = 'Choose',
    canChooseFiles = true,
    canChooseDirectories = false,
    allowsMultipleSelection = false,
    initialDirectory = '/Applications',
  })

  if selected and #selected > 0 then
    prefs.appPath = selected[1]
    return prefs.appPath
  end

  return nil
end

function PluginCore.startApp(folder, mode)
  folder = ensureFolder(folder or PluginCore.previewFolder())
  if not folder then
    debugLog('startApp skipped: no folder')
    LrDialogs.message('Live Loupe', 'Choose a preview folder first.', 'warning')
    return false
  end

  local appPath = PluginCore.findAppPath()
  debugLog(string.format('startApp folder=%s appPath=%s port=%d', tostring(folder), tostring(appPath), PluginCore.port()))
  writeRuntimeState(mode or 'export', true)
  if not appPath then
    local shouldChoose = LrDialogs.confirm(
      'Live Loupe',
      'Could not find Live Loupe.app. Choose it manually?',
      'Choose App',
      'Cancel'
    )

    if shouldChoose == 'ok' then
      appPath = PluginCore.chooseAppPath()
    end
  end

  if not appPath or not directoryExists(appPath) then
    debugLog('startApp failed: app not found')
    LrDialogs.message('Live Loupe', 'Live Loupe.app was not found. Put it in /Applications or choose it manually.', 'critical')
    return false
  end

  local launchURL = liveLoupeLaunchURL(folder, mode or 'export', PluginCore.port())
  local activateCommand = table.concat({
    '/usr/bin/open',
    shellQuote(appPath),
  }, ' ')
  local command = table.concat({
    '/usr/bin/open',
    '-b',
    'com.local.liveloupe',
    shellQuote(launchURL),
  }, ' ')

  LrTasks.execute(activateCommand)
  LrTasks.execute(command)
  debugLog('startApp executed url command mode=' .. tostring(mode or 'export') .. ' url=' .. launchURL)
  return true
end

function PluginCore.revealPreviewFolder()
  local folder = PluginCore.previewFolder()
  if folder then
    LrShell.revealInShell(folder)
  end
end

function PluginCore.startLivePreview()
  local folder = PluginCore.previewFolder()
  if not folder then
    debugLogSession('live START failed: no preview folder')
    return
  end

  debugLogSession('live START requested')
  debugLog(string.format('pluginPath=%s previewFolder=%s port=%d', tostring(_PLUGIN.path), tostring(folder), PluginCore.port()))
  PluginCore.startApp(folder, 'export')

  local state = liveState()
  -- Each Start bumps the generation. Any previously running loop sees a newer
  -- generation and exits, so we never accumulate concurrent live tasks across
  -- Stop/Start or Reload Plug-in (Lightroom does not kill running async tasks).
  state.generation = (state.generation or 0) + 1
  local myGeneration = state.generation
  state.running = true
  state.stop = false
  state.forceRender = true
  state.changeSerial = (state.changeSerial or 0) + 1
  state.lastError = nil

  local developActive = ensureDevelopModuleForLive()
  debugLog('developActiveForObserver=' .. tostring(developActive))

  LrFunctionContext.postAsyncTaskWithContext('Live Loupe Live', function(context)
    context:addCleanupHandler(function()
      if state.generation == myGeneration then
        state.running = false
      end
    end)

    local renderedSignature = nil
    local pendingSignature = nil
    local pendingSince = nil
    local lastDevelopPollAt = 0
    local lastDevelopPollSignature = nil
    local lastQuietPollLogAt = 0
    local lastNoPhotoLogAt = 0
    local lastRenderAttemptAt = 0
    local lastRuntimeStateCheckAt = 0
    local loopSettings = PluginCore.exportSettings()
    debugLog(string.format(
      'live loop START gen=%d longEdge=%d quality=%.2f jpegQuality=%d',
      myGeneration,
      loopSettings.liveLongEdge,
      loopSettings.liveJpegQuality,
      loopSettings.jpegQuality
    ))

    local observerOK, observerError = LrTasks.pcall(function()
      LrDevelopController.addAdjustmentChangeObserver(context, state, function(observer)
        observer.changeSerial = (observer.changeSerial or 0) + 1
        observer.forceRender = true
        observer.pendingObserverEvents = (observer.pendingObserverEvents or 0) + 1
      end)
    end)

    if observerOK then
      debugLog('observer REGISTERED')
    else
      debugLog('observer REGISTER_FAILED ' .. tostring(observerError))
    end

    local useDevelopPollForSignature = not (observerOK and developActive)
    local developPollInterval = useDevelopPollForSignature and 0.8 or 30.0
    local liveSettleDelay = observerOK and 0.35 or 0.2
    local renderRetryDelay = 1.0
    debugLog(string.format(
      'develop poll mode=%s interval=%.1f',
      useDevelopPollForSignature and 'signature' or 'diagnostic-only',
      developPollInterval
    ))
    debugLog(string.format('live timing settle=%.2f retry=%.2f', liveSettleDelay, renderRetryDelay))

    while not state.stop and state.generation == myGeneration do
      -- renderLivePhoto() runs an export, which yields. Yielding across the
      -- built-in pcall() boundary is illegal in Lightroom's Lua, so use the
      -- yield-safe LrTasks.pcall.
      local ok, message = LrTasks.pcall(function()
        local now = LrDate.currentTime()
        if now - lastRuntimeStateCheckAt >= 0.5 then
          lastRuntimeStateCheckAt = now
          local liveAllowed, runtimeMode, runtimeRunning = appAllowsLiveExport()
          if not liveAllowed then
            debugLog(string.format(
              'live loop STOP app runtime mode=%s running=%s',
              tostring(runtimeMode),
              tostring(runtimeRunning)
            ))
            state.stop = true
            return
          end
        end

        local photo = currentTargetPhoto()
        if not photo then
          if now - lastNoPhotoLogAt >= 2 then
            lastNoPhotoLogAt = now
            debugLog('loop no target photo')
          end
          return
        end

        local signature = cheapPhotoSignature(photo, state)
        local label = photoLabel(photo)

        -- Fallback for Lightroom builds/modules where the Develop observer
        -- misses events. Polling full settings is expensive, so keep it sparse.
        if now - lastDevelopPollAt >= developPollInterval then
          lastDevelopPollAt = now
          local fullSignature, fullOK, fullElapsed, fullBytes, fullError = developSignature(photo)
          local fullChanged = fullSignature ~= lastDevelopPollSignature
          if fullChanged or now - lastQuietPollLogAt >= 5 then
            lastQuietPollLogAt = now
            debugLog(string.format(
              'develop poll photo=%s ok=%s changed=%s fetch=%.2f bytes=%d error=%s',
              label,
              tostring(fullOK),
              tostring(fullChanged),
              fullElapsed or -1,
              fullBytes or 0,
              tostring(fullError or '')
            ))
          end
          lastDevelopPollSignature = fullSignature
        end

        if useDevelopPollForSignature and lastDevelopPollSignature then
          signature = signature .. '|' .. lastDevelopPollSignature
        end

        -- Debounce: re-render once edits pause briefly, not on every intermediate
        -- slider position (each render is a full Camera Raw pass).
        if state.forceRender or signature ~= pendingSignature then
          local observerEvents = state.pendingObserverEvents or 0
          local reason = state.forceRender and 'observer' or 'signature'
          state.forceRender = false
          state.pendingObserverEvents = 0
          pendingSignature = signature
          pendingSince = now
          lastRenderAttemptAt = 0
          debugLog(string.format(
            'change queued reason=%s photo=%s serial=%s events=%d sigBytes=%d',
            reason,
            label,
            tostring(state.changeSerial),
            observerEvents,
            #signature
          ))
        end

        local settled = pendingSince ~= nil and (now - pendingSince) >= liveSettleDelay
        local retryReady = lastRenderAttemptAt == 0 or (now - lastRenderAttemptAt) >= renderRetryDelay
        if signature ~= renderedSignature and settled and retryReady then
          lastRenderAttemptAt = now
          debugLog(string.format('render queued photo=%s settled=%.2f rendered=%s', label, now - pendingSince, tostring(renderedSignature ~= nil)))
          local renderOK, renderMessage = renderLivePhoto(photo, folder)
          if renderOK then
            renderedSignature = signature
            state.lastError = nil
          else
            state.lastError = renderMessage
            debugLog('render ERROR ' .. tostring(renderMessage))
          end
        end
      end)

      if not ok then
        state.lastError = message
        debugLog('loop ERROR ' .. tostring(message))
        LrTasks.sleep(0.5)
      end

      LrTasks.sleep(0.05)
    end

    debugLog(string.format('live loop EXIT gen=%d', myGeneration))
  end)
end

function PluginCore.startScreenPreview()
  local folder = PluginCore.previewFolder()
  if not folder then
    debugLogSession('screen START failed: no preview folder')
    return
  end

  PluginCore.stopLivePreview()
  debugLogSession('screen START requested')
  debugLog(string.format('pluginPath=%s previewFolder=%s port=%d', tostring(_PLUGIN.path), tostring(folder), PluginCore.port()))
  writeRuntimeState('screen', true)
  PluginCore.startApp(folder, 'screen')
end

function PluginCore.stopLivePreview()
  local state = liveState()
  debugLogSession('live STOP requested')
  state.stop = true
  state.running = false
  state.forceRender = false

  local folder = prefs.previewFolder
  if folder and folder ~= '' then
    LrTasks.pcall(function()
      local livePath = LrPathUtils.child(folder, livePreviewFileName)
      local tmpPath = LrPathUtils.child(folder, livePreviewFileName .. '.tmp')
      if LrFileUtils.exists(livePath) then
        LrFileUtils.delete(livePath)
        debugLog('deleted live preview ' .. livePath)
      end
      if LrFileUtils.exists(tmpPath) then
        LrFileUtils.delete(tmpPath)
        debugLog('deleted live preview temp ' .. tmpPath)
      end
    end)
  end
end

function PluginCore.showDiagnosticLog()
  local path = debugLogPath()
  local file = io.open(path, 'a')
  if file then
    file:write(string.format('%s  %.3f  plugin  diagnostic log opened\n', os.date('%Y-%m-%d %H:%M:%S'), LrDate.currentTime()))
    file:close()
  end
  LrShell.revealInShell(path)
end

function PluginCore.exportSelected()
  local folder = PluginCore.previewFolder()
  if not folder then
    return
  end

  local catalog = LrApplication.activeCatalog()
  local photos = catalog:getTargetPhotos()

  if not photos or #photos == 0 then
    LrDialogs.message('Live Loupe', 'Select one or more photos in Library first.', 'warning')
    return
  end

  PluginCore.startApp(folder, 'export')
  local settings = PluginCore.exportSettings()
  -- Size fields must be NUMBERS; a string makes Lightroom export a 1x1 image.
  local longEdge = math.floor(settings.longEdgePixels)

  local exportSession = LrExportSession({
    photosToExport = photos,
    exportSettings = {
      LR_export_destinationType = 'specificFolder',
      LR_export_destinationPathPrefix = folder,
      LR_collisionHandling = 'overwrite',

      LR_format = 'JPEG',
      LR_export_colorSpace = 'sRGB',
      LR_jpeg_quality = settings.lrJpegQuality,
      LR_jpeg_useLimitSize = false,

      LR_size_doConstrain = true,
      LR_size_doNotEnlarge = true,
      LR_size_maxHeight = longEdge,
      LR_size_maxWidth = longEdge,
      LR_size_resizeType = 'longEdge',
      LR_size_units = 'pixels',

      LR_outputSharpeningOn = settings.outputSharpening,
      LR_outputSharpeningMedia = 'screen',
      LR_outputSharpeningLevel = 2,

      LR_useWatermark = false,
      LR_minimizeEmbeddedMetadata = settings.minimizeMetadata,
      LR_removeLocationMetadata = settings.removeLocationMetadata,
    },
  })

  exportSession:doExportOnCurrentTask()
end

function PluginCore.runAsync(action)
  LrTasks.startAsyncTask(function()
    -- action() may call yielding SDK functions (LrTasks.execute, export sessions,
    -- LrDialogs panels, etc.). The built-in pcall cannot be yielded across in
    -- Lightroom's Lua, so use the yield-safe LrTasks.pcall here.
    local ok, result = LrTasks.pcall(action)
    if not ok then
      LrDialogs.message('Live Loupe', tostring(result), 'critical')
    end
  end, 'Live Loupe')
end

return PluginCore
