local driver = localRequire("driver")
local memutils = lwRequire("lib/memutils")

local canvasLib = {}
for k, v in pairs(driver.canvas) do
  canvasLib[k] = v
end

local memory
function canvasLib.initialize(m)
  memory = m
end

function canvasLib.canvas_create(titlePtr)
  local title = memutils.readCString(memory, titlePtr)
  return driver.canvas.canvas_create(title)
end

function canvasLib.canvas_load_image(w, h, bitmapPtr)
  print(string.format("CALL LOAD %d %d %d", w, h, bitmapPtr or 0))
  if not bitmapPtr or bitmapPtr == 0 or w == 0 or h == 0 then return 0 end
  
  local rgbaBytes = memory.raw()
  return driver.canvas.canvas_load_image(w, h, rgbaBytes, math.floor(bitmapPtr / 4))
end

return {
  env = canvasLib
}