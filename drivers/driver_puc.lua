local SDL = require("SDL")
local bits = lwRequire("lib/bits")
local band, bshr = bits.band, bits.shr

local didInitSDL = false

local activeCanvases = {}
local nextCanvasId = 1

local loadedImages = {}
local nextImageId = 1

local canvasLib = {}
local memory

function canvasLib.input_use_tab()
  return false
end

function canvasLib.canvas_create(title)
  if not didInitSDL then
    SDL.init({ SDL.flags.Video })
    didInitSDL = true
  end

  print(string.format('[Lua] Creating canvas with title: "%s"', title))

  local width, height = 800, 600

  local window, err = SDL.createWindow({
    title = title,
    width = width,
    height = height,
    flags = { SDL.flags.Resizable }
  })
  if not window then error(err) end

  local renderer, rErr = SDL.createRenderer(window, -1, {
    SDL.rendererFlags.Accelerated,
    SDL.rendererFlags.PresentVSync
  })
  if not renderer then error(rErr) end

  local id = nextCanvasId
  nextCanvasId = nextCanvasId + 1

  print("Set id " .. id)
  activeCanvases[id] = {
    window = window,
    renderer = renderer,
    width = width,
    height = height
  }
  return id
end

function canvasLib.canvas_resize(windowId, w, h)
  local canvas = activeCanvases[windowId]
  if not canvas then return end

  print(string.format("[Lua] Resizing canvas %d to %dx%d", windowId, w, h))
  canvas.window:setSize(w, h)
  canvas.width = w
  canvas.height = h
end

function canvasLib.canvas_destroy(windowId)
  activeCanvases[windowId] = nil
end

function canvasLib.canvas_set_color(windowId, r, g, b, a)
  local canvas = activeCanvases[windowId]
  if not canvas then return end

  assert(canvas.renderer:setDrawColor({ a = a or 255, r = r, g = g, b = b}))
end

function canvasLib.canvas_fill_rect(windowId, x, y, w, h)
  local canvas = activeCanvases[windowId]
  if not canvas then return end

  assert(canvas.renderer:fillRect({ x = x, y = y, w = w, h = h }))
end

function canvasLib.canvas_load_image(w, h, buf, bufOffset)
  local primaryCanvas = next(activeCanvases) and activeCanvases[next(activeCanvases)]
  if not primaryCanvas then
    print("[Lua] Error: Cannot load image without an active canvas renderer")
    return 0
  end

  local surface, err = SDL.createRGBSurface(w, h, 32)
  if not surface then
    print("[Lua] Surface creation failed: " .. tostring(err))
    return 0
  end

  -- Proper texture loading is broken in SDL

  local pixelIndex = bufOffset + 1

  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local argb = buf[pixelIndex]
      local a = band(bshr(argb, 24), 0xFF)
      local r = band(bshr(argb, 16), 0xFF)
      local g = band(bshr(argb, 8), 0xFF)
      local b = band(argb, 0xFF)

      surface:fillRect(
        { x = x, y = y, w = 1, h = 1 },
        { r = r, g = g, b = b, a = a })

      pixelIndex = pixelIndex + 1
    end
  end

  local texture, texErr = primaryCanvas.renderer:createTextureFromSurface(surface)
  if not texture then
    print("[Lua] Texture creation failed: " .. tostring(texErr))
    return 0
  end

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

  local srcRect = { x = srcX, y = srcY, w = srcW, h = srcH }
  local destRect = { x = destX, y = destY, w = destW, h = destH }

  return not canvas.renderer:copy(image.texture, srcRect, destRect)
end

local function handleEvent(event, profiler)
  if event.type == SDL.event.KeyDown then
    local key = event.keysym.sym

    if key == SDL.key.F5 then
      profiler.reset()
      profiler.enable()
      print("[Profiler] Profiler reset")
    elseif key == SDL.key.F6 then
      profiler.dump()
    elseif key == SDL.key.F7 then
      if profiler.isInstructionProfilingEnabled() then
        profiler.disableInstructions()
        print("[Profiler] Instruction profiling disabled")
      else
        profiler.enableInstructions()
        print("[Profiler] Instruction profiling enabled")
      end
    elseif key == SDL.key.F8 then
      if profiler.isEnabled() then
        profiler.disable()
        print("[Profiler] Profiler disabled")
      else
        profiler.enable()
        print("[Profiler] Profiler enabled")
      end
    end
  end
end

local eventQueue = {}

function canvasLib.canvas_poll_event(eventPtr)
  if eventPtr < 1 or #eventQueue == 0 then
    return 0
  end

  for i = 0, 56, 4 do
    memory.writeU32(eventPtr + i, 0)
  end

  local event = table.remove(eventQueue, 1)

  if event.type == SDL.event.KeyDown or event.type == SDL.event.KeyUp then
    memory.writeU32(eventPtr, event.type)
    memory.writeU32(eventPtr + 16, event.keysym.scancode)
    memory.writeU32(eventPtr + 20, event.keysym.sym)
    return 1
  end

  return 0
end

function canvasLib.canvas_present()
  for _, v in pairs(activeCanvases) do
    v.renderer:present()
    v.renderer:setDrawColor(0, 0, 0, 255)
    v.renderer:clear()
  end
end

local function runLoop(frame, profiler)
  local lastTime = os.time()
  local frameCount = 0

  while true do
    if not frame() then
      return
    end

    frameCount = frameCount + 1

    local now = os.time()
    local elapsed = now - lastTime

    if elapsed >= 1 then
      print(string.format("Average FPS: %.2f", frameCount / elapsed))
      frameCount = 0
      lastTime = now
    end

    for event in SDL.pollEvent() do
      if event.type == SDL.event.Quit then
        return
      else
        eventQueue[#eventQueue + 1] = event
        handleEvent(event, profiler)
      end
    end
  end
end


return {
  canvas = canvasLib,
  audio = localRequire("drivers/audio/audio_puc"),
  runLoop = runLoop,
  initialize = function(m) memory = m end
}