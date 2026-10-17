local bits = lwRequire("lib/bits")
local band, bshr, bor, bshl = bits.band, bits.shr, bits.bor, bits.shl
local char, sub = string.char, string.sub
local max, min = math.max, math.min

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
  local fpsData
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

  local hadTextureChanges = false
  local function recompositeIfNeeded()
    if hadTextureChanges then
      virtCanv.compositeTextures()
      hadTextureChanges = false
    end
  end

  local function getColor(op)
    local c = op or currentColorTbl
    return char(colors(c[1], c[2], c[3], c[4]))
  end

  function virtCanv.attachMonitoring(fpsD)
    fpsData = fpsD
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
    recompositeIfNeeded()
    local startTime = os.clock()
    updateCallback(buffer, l, h)
    _G.__drawTextureTime = _G.__drawTextureTime + (os.clock() - startTime)
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

    recompositeIfNeeded()
    local startTime = os.clock()
    
    local currentColor = getColor()
    local between = currentColor:rep(rl)
    for y2 = 1, rh do
      local rowStr = buffer[y + y2]
      local before = rowStr:sub(1, x)
      local after = rowStr:sub(x + rl + 1)
      buffer[y + y2] = table.concat({ before, between, after })
    end

    if fpsData then
      fpsData.drawTime = fpsData.drawTime + (os.clock() - startTime)
    end
  end

  function virtCanv.setColor(r, g, b, a)
    currentColorTbl = { r, g, b, a }
  end

  function virtCanv.clear()
    colorCache = {}
    hadTextureChanges = false
    virtCanv.fillRect(0, 0, l, h)
  end

  function virtCanv.createTexture(w, h, buf, bufOffset)
    local texture = {}
    local usedColors = {}
    local usedColorsCache = {}

    local nextIdx = 0
    for y = 1, h do
      local pixels, opaque, opaqueStart, opaqueRun = {}, {}, 1, 0

      for x = 1, w do
        local abgr = buf[bufOffset]
        bufOffset = bufOffset + 1

        local a, b, g, r = unpackABGR(abgr)

        local usedColor
        local existingColor = usedColorsCache[abgr]
        if existingColor then
          usedColor = existingColor
        else
          usedColor = char(nextIdx)
          usedColors[usedColor] = { r, g, b, a }
          usedColorsCache[abgr] = usedColor
          nextIdx = nextIdx + 1
          if #usedColors > 255 then
            error("Out of colors")
          end
        end

        if a ~= 0 then
          opaqueRun = opaqueRun + 1
          pixels[x] = usedColor
        else
          if opaqueRun > 0 then
            opaque[#opaque + 1] = opaqueStart
            opaque[#opaque + 1] = opaqueStart + opaqueRun - 1
            opaqueRun = 0
          end

          opaqueStart = x + 1
        end
      end

      if opaqueRun > 0 then
        opaque[#opaque + 1] = opaqueStart
        opaque[#opaque + 1] = opaqueStart + opaqueRun - 1
      end

      texture[y] = {
        pixels = pixels,
        opaque = opaque,
      }
    end

    texture.colors = usedColors

    return texture
  end

  local drawQueue = {}

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

    drawQueue[#drawQueue + 1] = {
      texture = texture,
      srcX = srcX,
      srcY = srcY,
      srcW = srcW,
      srcH = srcH,
      destX = destX,
      destY = destY,
    }

    hadTextureChanges = true

    return true
  end

  local function getBufRow(rowBuffers, destY)
    local bufRow = rowBuffers[destY]

    if not bufRow then
      local row = buffer[destY]
      if row then
        bufRow = {}
        for x = 1, #row do
          bufRow[x] = sub(row, x, x)
        end
        rowBuffers[destY] = bufRow
      end
    end

    return bufRow
  end

  function virtCanv.compositeTextures()
    local startTime = os.clock()

    local rowBuffers = {}
    local colorCaches = {}

    for _, v in ipairs(drawQueue) do
      local texture = v.texture
      local colorMap = texture.colors

      local mappedColors = colorCaches[texture]
      if not mappedColors then
        mappedColors = {}
        colorCaches[texture] = mappedColors
      end

      for y = 1, v.srcH do
        local srcRow = texture[v.srcY + y]
        local destY = v.destY + y

        local bufRow = getBufRow(rowBuffers, destY)
        if bufRow and srcRow then -- TODO: Why is srcRow, on rare occassion, nil?
          local opaque = srcRow.opaque

          for i = 1, #opaque, 2 do
            local xStart = max(opaque[i], v.srcX + 1)
            local xEnd = min(opaque[i + 1], v.srcX + v.srcW)

            for srcX = xStart, xEnd do
              local destX = srcX - v.srcX + v.destX
              local ch = srcRow.pixels[srcX]

              local mapped = mappedColors[ch]
              if mapped == nil then
                local rgba = colorMap[ch]
                mapped = char(colors(
                  rgba[1], rgba[2], rgba[3], rgba[4]
                ))
                mappedColors[ch] = mapped
              end

              bufRow[destX] = mapped
            end
          end
        end
      end
    end

    for y, row in pairs(rowBuffers) do
      buffer[y] = table.concat(row)
    end

    drawQueue = {}

    if fpsData then
      fpsData.drawTime = fpsData.drawTime + (os.clock() - startTime)
    end
  end

  return virtCanv
end

return {
  createVirtCanv = createVirtCanv
}