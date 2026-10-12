local driver = localRequire("driver")
local memutils = lwRequire("lib/memutils")

local function toS32(n)
  n = n % 0x100000000
  if n >= 0x80000000 then
    return n - 0x100000000
  end
  return n
end

local canvasLib = {}
for k, v in pairs(driver.canvas) do
  canvasLib[k] = v
end

local memory
function canvasLib.initialize(m)
  memory = m
  driver.initialize(m)
end

function canvasLib.canvas_create(titlePtr)
  local title = memutils.readCString(memory, titlePtr)
  return driver.canvas.canvas_create(title)
end

function canvasLib.canvas_load_image(w, h, bitmapPtr)
  if not bitmapPtr or bitmapPtr == 0 or w == 0 or h == 0 then return 0 end
  
  local rgbaBytes = memory.raw()
  return driver.canvas.canvas_load_image(w, h, rgbaBytes, math.floor(bitmapPtr / 4))
end

local nativeDrawImage = canvasLib.canvas_draw_image
function canvasLib.canvas_draw_image(canvasId, imageId, srcX, srcY, srcW, srcH, destX, destY, destW, destH)
  return nativeDrawImage(
    canvasId, imageId,
    toS32(srcX), toS32(srcY), toS32(srcW), toS32(srcH),
    toS32(destX), toS32(destY), toS32(destW), toS32(destH))
end

return {
  env = canvasLib
}