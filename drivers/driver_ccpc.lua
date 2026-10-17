local virtCanvLib = localRequire("lib/virtcanv")
local audioLib = localRequire("drivers/audio/audio_cc")
local bits = lwRequire("lib/bits")
local lwDriver = lwRequire("driver")
local bor, bshl = bits.bor, bits.shl

local activeCanvases = {}
local nextCanvasId = 1

local loadedImages = {}
local nextImageId = 1

local canvasLib = {}

---@diagnostic disable-next-line: undefined-global
local periphemu, peripheral, keys = periphemu, peripheral, keys

local function packRGBA(r, g, b, a)
  return bor(bshl(r, 24), bshl(g, 16), bshl(b, 8), a)
end

local SDLK_SCANCODE_MASK = bshl(1, 30)
local SDL_KEYDOWN = 0x300
local SDL_KEYUP = 0x301
local luaToScanCodeMap = {}
local luaToKeyCodeMap = {}

for i=("a"):byte(), ("z"):byte() do
  luaToScanCodeMap[keys[string.char(i)]] = i - ("a"):byte() + 4
  luaToKeyCodeMap[keys[string.char(i)]] = i
end

local names = {
  "one", "two", "three", "four", "five",
  "six", "seven", "eight", "nine"}
for i=1, 9 do
  luaToScanCodeMap[keys[names[i]]] = i + 29
  luaToKeyCodeMap[keys[names[i]]] = i + 0x30
end
luaToScanCodeMap[keys["zero"]] = 39
luaToKeyCodeMap[keys["zero"]] = 0x30

local ARROW_SCAN_CODES = {
  [keys.right] = 79,
  [keys.left] = 80,
  [keys.down] = 81,
  [keys.up] = 82,
  [keys.tab] = 41
}

for key, scanCode in pairs(ARROW_SCAN_CODES) do
  luaToScanCodeMap[key] = scanCode
  luaToKeyCodeMap[key] = bor(scanCode, SDLK_SCANCODE_MASK)
end
luaToKeyCodeMap[keys.enter] = 13
luaToKeyCodeMap[keys.tab] = 27

local queuedEvents = {}
local function handleKeyEvent(e)
  queuedEvents[#queuedEvents + 1] = {
    type = e[1] == "key" and SDL_KEYDOWN or SDL_KEYUP,
    scanCode = luaToScanCodeMap[e[2]] or 0,
    keyCode = luaToKeyCodeMap[e[2]] or 0,
  }
end

local memory

function canvasLib.canvas_create(title)
  print(string.format('[Lua] Creating canvas with title: "%s"', title))

  local width, height = 800, 600
  local ok = periphemu.create("top", "monitor")
  if not ok then return nil, "Could not create monitor" end
  local window = peripheral.wrap("top")
  window.setGraphicsMode(2)

  --[[local palette = {}

  for i = 0, 255 do
    local rBits = band(bshr(i, 5), 0x07)
    local gBits = band(bshr(i, 2), 0x07)
    local bBits = band(i, 0x03)

    local r = math.floor((rBits / 7) * 255 + 0.5)
    local g = math.floor((gBits / 7) * 255 + 0.5)
    local b = math.floor((bBits / 4.1) * 255 + 0.5)
    local a = 255

    -- The game uses a lot of blue, so I had to do some manual adjustments
    if rBits == 7 and gBits == 7 and bBits == 3 then
      r, g, b = 255, 255, 255
    elseif rBits == 0 and gBits == 0 and bBits == 3 then
      r, g, b = 0, 0, 255
    end
    window.setPaletteColor(i, r / 255, g / 255, b / 255)
    palette[i] = { r = r, g = g, b = b, a = a }
  end]]

  local palette = {}
  local keyIndex = {
    [packRGBA(0, 0, 0, 255)] = 0
  }
  local nextPaletteIndex = 1

  local function updateRendering(buffer, l, h)
    window.drawPixels(1, 1, buffer)
    for k, v in ipairs(palette) do
      window.setPaletteColor(k, v[1] / 255, v[2] / 255, v[3] / 255)
    end
  end

  window.setPaletteColor(0, 0, 0, 0)
  local renderer = virtCanvLib.createVirtCanv({
    updateCallback = updateRendering,
    colors = function(r, g, b, a)
      local key = packRGBA(r, g, b, a)
      if keyIndex[key] then
        return keyIndex[key]
      end

      -- TODO: Need to find a proper way to handle color overflow
      -- The problem is that the textures are baked, so I can't reset colors per
      -- frame without corrupting textures

      --[[if #palette >= 255 then
        -- error("Out of colors")
      end]]

      local idx = nextPaletteIndex
      nextPaletteIndex = nextPaletteIndex % 255 + 1
      palette[idx] = { r, g, b, a }
      keyIndex[key] = idx
      
      return idx
    end
  })

  local id = nextCanvasId
  nextCanvasId = nextCanvasId + 1

  activeCanvases[id] = {
    window = window,
    renderer = renderer,
    name = "top",
    width = width,
    height = height,
    resetColors = function()
      palette = {}
      keyIndex = {
        [packRGBA(0, 0, 0, 255)] = 0
      }
      nextPaletteIndex = 1
    end
  }
  return id
end

function canvasLib.canvas_resize(windowId, w, h)
  local canvas = activeCanvases[windowId]
  if not canvas then return end

  print(string.format("[Lua] Resizing canvas %d to %dx%d", windowId, w, h))
  local monW = math.ceil(w / 6)
  local monH = math.ceil(h / 9)
  canvas.window.setSize(monW, monH)
  canvas.renderer.resize(w, h)
  canvas.width = w
  canvas.height = h
  canvas.window.drawPixels(0, 0, 0, monW * 6, monH * 9)
end

function canvasLib.canvas_destroy(windowId)
  local canvas = activeCanvases[windowId]
  if not canvas then return end

  activeCanvases[windowId] = nil
  periphemu.remove(canvas.name)
end

function canvasLib.canvas_set_color(windowId, r, g, b, a)
  local canvas = activeCanvases[windowId]
  if not canvas then return end

  canvas.renderer.setColor(r, g, b, a)
end

function canvasLib.canvas_fill_rect(windowId, x, y, w, h)
  local canvas = activeCanvases[windowId]
  if not canvas then return end

  canvas.renderer.fillRect(x, y, w, h)
end

function canvasLib.canvas_load_image(w, h, buf, bufOffset)
  local primaryCanvas = next(activeCanvases) and activeCanvases[next(activeCanvases)]
  if not primaryCanvas then
    print("[Lua] Error: Cannot load image without an active canvas renderer")
    return 0
  end

  local texture = primaryCanvas.renderer.createTexture(w, h, buf, bufOffset + 1)

  local imageId = nextImageId
  nextImageId = nextImageId + 1

  loadedImages[imageId] = {
    width = w,
    height = h,
    texture = texture
  }

  print(string.format("[Lua] Successfully loaded image #%d (%dx%d)", imageId, w, h))
  return imageId
end

function canvasLib.canvas_destroy_image(imageId)
  local image = loadedImages[imageId]
  if not image then return end

  loadedImages[imageId] = nil
end

function canvasLib.canvas_draw_image(canvasId, imageId, srcX, srcY, srcW, srcH, destX, destY, destW, destH)
  local canvas = activeCanvases[canvasId]
  local image = loadedImages[imageId]
  if not canvas or not image then return true end

  canvas.renderer.drawTexture(image.texture, srcX, srcY, srcW, srcH, destX, destY, destW, destH)
  return false
end

function canvasLib.canvas_poll_event(eventPtr)
  if #queuedEvents < 1 then return 0 end
  if eventPtr < 1 then return 0 end

  for i=0, 56, 4 do
    memory.writeU32(eventPtr + i, 0)
  end

  local event = table.remove(queuedEvents, 1)
  if event.type == SDL_KEYDOWN or event.type == SDL_KEYUP then
    memory.writeU32(eventPtr, event.type)
    memory.writeU32(eventPtr + 16, event.scanCode)
    memory.writeU32(eventPtr + 20, event.keyCode)
  else
    print("[Lua] Unrecognized Event Type", event.type)
    return 0
  end

  return 1
end

function canvasLib.canvas_present()
  for _, v in pairs(activeCanvases) do
    v.renderer.present()
    v.resetColors()
    v.renderer.setColor(0, 0, 0, 255)
    v.renderer.clear()
  end
end

local function showFPS(fpsData, preClock)
  local now = os.clock()
  local frameElapsed = now - preClock

  fpsData.fpsFrames = fpsData.fpsFrames + 1
  fpsData.frameTime = fpsData.frameTime + frameElapsed

  local fpsElapsed = now - fpsData.fpsStart

  if fpsElapsed >= 1 then
    local drawTime = fpsData.drawTime
    local frameTime = fpsData.frameTime
    local audioTime = fpsData.audioTime
    local sleepTime = fpsData.sleepTime

    -- drawTime is excluded because it is called into mid-frame
    local totalTime = frameTime + audioTime + sleepTime

    local drawPercent = drawTime / totalTime * 100
    local audioPercent = audioTime / totalTime * 100
    local sleepPercent = sleepTime / totalTime * 100
    local otherPercent = 100 - drawPercent - audioPercent - sleepPercent

    print(string.format(
      "FPS: %.1f | vm: %.1f%% | gfx: %.1f%% | sfx: %.1f%%",
      fpsData.fpsFrames / fpsElapsed,
      otherPercent,
      drawPercent,
      audioPercent,
      sleepPercent
    ))

    fpsData.fpsFrames = 0
    fpsData.fpsStart = now

    fpsData.frameTime = 0
    fpsData.drawTime = 0
    fpsData.audioTime = 0
    fpsData.sleepTime = 0
  end
end

local function initFPSData()
  return {
    fpsStart = os.clock(),
    fpsFrames = 0,
    frameTime = 0,
    drawTime = 0,
    audioTime = 0,
    sleepTime = 0
  }
end

local function runLoop(frame)
  local fpsData = initFPSData()

  for _, v in pairs(activeCanvases) do
    v.renderer.attachMonitoring(fpsData)
  end

  while true do
    local preClock = os.clock()

    if not frame() then
      return
    end

    local audioClock = os.clock()
    audioLib.frame()
    fpsData.audioTime = fpsData.audioTime + (os.clock() - audioClock)

    showFPS(fpsData, preClock)

    local elapsed = os.clock() - preClock
    ---@diagnostic disable-next-line: undefined-field
    os.startTimer(math.max(0.016 - elapsed - 0.001, 0.001))
    local sleepElapsed = 0
    while true do
      local waitStart = os.clock()
      ---@diagnostic disable-next-line: undefined-field
      local event = { os.pullEvent() }
      lwDriver.resetTimeout()
      sleepElapsed = sleepElapsed + (os.clock() - waitStart)

      if event[1] == "timer" then
        break
      elseif event[1] == "key" or event[1] == "key_up" then
        handleKeyEvent(event)
      end
    end

    fpsData.sleepTime = fpsData.sleepTime + sleepElapsed
  end
end

local function initialize(m)
  memory = m
end

return {
  canvas = canvasLib,
  audio = audioLib,
  runLoop = runLoop,
  initialize = initialize
}