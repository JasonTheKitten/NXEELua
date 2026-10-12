local bits = lwRequire("lib/bits")
local band, bshr, bor, bshl = bits.band, bits.shr, bits.bor, bits.shl
local char, gsub, sub = string.char, string.gsub, string.sub
local max, min = math.max, math.min
local concat = table.concat

-- Why does color unpacking here differ from the SDL version??
local function unpackABGR(argb)
  local a = band(bshr(argb, 24), 0xFF)
  local b = band(bshr(argb, 16), 0xFF)
  local g = band(bshr(argb, 8), 0xFF)
  local r = band(argb, 0xFF)

  return a, b, g, r
end

local function packRGBA(r, g, b, a)
  return bor(bshl(r, 24), bshl(g, 16), bshl(b, 8), a)
end

local function createVirtCanv(options)
  local updateCallback = options.updateCallback
  local colors = options.colors --virtCanv currently assumes color indices are 255 or less
  local colorCache = {}
  if type(colors) == "table" then
    local palette = colors
    colors = function(r, g, b, a)
      local packed = packRGBA(r, g, b, a)
      local cached = colorCache[packed]
      if cached then return cached end

      local minDistance = math.huge
      local minColor = 0
      for k, v in pairs(palette) do
        local rDiff = math.abs(v.r - r)
        local gDiff = math.abs(v.g - g)
        local bDiff = math.abs(v.b - b)
        local aDiff = math.abs(v.a - a)
        local totalDiff = rDiff * rDiff + gDiff * gDiff + bDiff * bDiff + aDiff * aDiff
        if totalDiff < minDistance then
          minDistance = totalDiff
          minColor = k
        end
      end

      colorCache[packed] = minColor
      return minColor
    end
  end

  local virtCanv = {}
  local buffer = {}
  local currentColorTbl = { 0, 0, 0, 255 }
  local l, h = 0, 0

  local function getColor(op)
    local c = op or currentColorTbl
    return char(colors(c[1], c[2], c[3], c[4]))
  end

  function virtCanv.resize(nl, nh)
    l = nl
    h = nh

    buffer = {}
    local line = getColor():rep(nl)
    for y=1, h do
      buffer[y] = line
    end
  end

  function virtCanv.present()
    updateCallback(buffer, l, h)
  end

  function virtCanv.fillRect(x, y, rl, rh)
    if rl <= 0 or rh <= 0 or l <= 0 or h <= 0 then
      return
    end

    local clipL = math.max(0, -x)
    local clipT = math.max(0, -y)
    local clipR = math.max(0, x + rl - l)
    local clipB = math.max(0, y + rh - h)

    x = x + clipL
    y = y + clipT
    rl = rl - clipL - clipR
    rh = rh - clipT - clipB

    if rl <= 0 or rh <= 0 then
      return
    end

    local currentColor = getColor()
    local between = currentColor:rep(rl)
    for y2 = 1, rh do
      local rowStr = buffer[y + y2]
      local before = rowStr:sub(1, x)
      local after = rowStr:sub(x + rl + 1)
      buffer[y + y2] = table.concat({ before, between, after })
    end
  end

  function virtCanv.setColor(r, g, b, a)
    currentColorTbl = { r, g, b, a }
  end

  local texCache = {}
  function virtCanv.clear()
    colorCache = {}
    texCache = {}
    virtCanv.fillRect(0, 0, l, h)
  end

  function virtCanv.createTexture(w, h, buf, bufOffset)
    local texture = {}
    local usedColors = {}
    local usedColorsCache = {}

    local nextIdx = 0
    for y = 1, h do
      local pixels, trans, transStart, transRun = {}, {}, 1, 0

      for x = 1, w do
        local abgr = buf[bufOffset]
        bufOffset = bufOffset + 1

        local a, b, g, r = unpackABGR(abgr)
        if a == 0 then
          transRun = transRun + 1
        end

        if transRun > 0 then
          trans[#trans + 1] = transStart
          trans[#trans + 1] = transStart + transRun - 1
          pixels[x] = char(0)
          transRun = 0
        end
        transStart = x + 1

        local usedColor
        local existingColor = usedColorsCache[abgr]
        if existingColor then
          usedColor = existingColor
        else
          usedColor = nextIdx
          usedColors[nextIdx] = { r, g, b, a }
          usedColorsCache[abgr] = nextIdx
          nextIdx = nextIdx + 1
          if #usedColors > 255 then
            error("Out of colors")
          end
        end

        if a ~= 0 then
          pixels[x] = char(usedColor)
        end
      end

      if transRun > 0 then
        trans[#trans + 1] = transStart
        trans[#trans + 1] = transStart + transRun - 1
      end

      texture[y] = {
        pixels = table.concat(pixels),
        transparent = trans,
      }
    end

    texture.colors = usedColors

    return texture
  end

  local function remapRow(row, texColors)
    local replacements = {}

    for i = 0, #texColors do
      local c = texColors[i]
      replacements[char(i)] = char(colors(c[1], c[2], c[3], c[4]))
    end

    return gsub(row, ".", replacements)
  end

  function virtCanv.drawTexture(
    texture, srcX, srcY, srcW, srcH,
    destX, destY, destW, destH
  )
    if srcW ~= destW or srcH ~= destH then
      return false, "Mismatched size"
    end

    if srcW <= 0 or srcH <= 0 then
      return true
    end

    local clipL = max(0, -destX)
    local clipT = max(0, -destY)
    local clipR = max(0, destX + destW - l)
    local clipB = max(0, destY + destH - h)

    srcX = srcX + clipL
    srcY = srcY + clipT
    destX = destX + clipL
    destY = destY + clipT

    srcW = srcW - clipL - clipR
    srcH = srcH - clipT - clipB

    destW = srcW
    destH = srcH

    if srcW <= 0 or srcH <= 0 then
      return true
    end

    texCache[texture] = texCache[texture] or {}
    local cCache = texCache[texture]
    local colors = texture.colors
    for y = 1, srcH do
      local bufRow = buffer[destY + y]
      local texRow = texture[srcY + y]

      local mappedSource = cCache[srcY + y]
      if not mappedSource then
        mappedSource = remapRow(texRow.pixels, colors)
        cCache[srcY + y] = mappedSource
      end
      local source = sub(mappedSource,srcX + 1, srcX + srcW)
      
      local parts = { sub(bufRow, 1, destX) }

      local trans = texRow.transparent
      local cursor = 1

      for i = 1, #trans, 2 do
        local first = max(trans[i], srcX + 1)
        local last = min(trans[i + 1], srcX + srcW)

        if first <= last then
          local runStart = first - srcX
          local runEnd = last - srcX

          if runStart > cursor then
            parts[#parts + 1] = sub(source, cursor, runStart - 1)
          end

          parts[#parts + 1] = sub(
            bufRow, destX + runStart, destX + runEnd)

          cursor = runEnd + 1
        end

        if trans[i] > srcX + srcW then break end
      end

      if cursor <= srcW then
        parts[#parts + 1] = sub(source, cursor, srcW)
      end

      parts[#parts + 1] = sub(bufRow, destX + destW + 1)
      buffer[destY + y] = concat(parts)
    end

    return true
  end

  return virtCanv
end

return {
  createVirtCanv = createVirtCanv
}