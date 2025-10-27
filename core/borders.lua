local addonName, addon = ...

addon.Borders = addon.Borders or {}
local Borders = addon.Borders

local function hideLegacy(frame)
    if not frame then return end
    if frame.ScootSquareBorder and frame.ScootSquareBorder.edges then
        for _, tex in pairs(frame.ScootSquareBorder.edges) do tex:Hide() end
    end
    if frame.ScootSquareBorderEdges then
        for _, tex in pairs(frame.ScootSquareBorderEdges) do if tex.Hide then tex:Hide() end end
    end
    if frame.ScootSquareBorderContainer then frame.ScootSquareBorderContainer:Hide() end
    if frame.ScootAtlasBorder then frame.ScootAtlasBorder:Hide() end
    if frame.ScootTextureBorder then frame.ScootTextureBorder:Hide() end
    -- Also clear any tint overlays created by icon-border tinting. If these remain visible or keep their
    -- atlas/texture, they can continue to tint even after the base border is re-applied.
    if frame.ScootAtlasBorderTintOverlay then
        frame.ScootAtlasBorderTintOverlay:Hide()
        if frame.ScootAtlasBorderTintOverlay.SetTexture then pcall(frame.ScootAtlasBorderTintOverlay.SetTexture, frame.ScootAtlasBorderTintOverlay, nil) end
        if frame.ScootAtlasBorderTintOverlay.SetAtlas then pcall(frame.ScootAtlasBorderTintOverlay.SetAtlas, frame.ScootAtlasBorderTintOverlay, nil) end
    end
    if frame.ScootTextureBorderTintOverlay then
        frame.ScootTextureBorderTintOverlay:Hide()
        if frame.ScootTextureBorderTintOverlay.SetTexture then pcall(frame.ScootTextureBorderTintOverlay.SetTexture, frame.ScootTextureBorderTintOverlay, nil) end
        if frame.ScootTextureBorderTintOverlay.SetAtlas then pcall(frame.ScootTextureBorderTintOverlay.SetAtlas, frame.ScootTextureBorderTintOverlay, nil) end
    end
    -- Clear mask textures as well (if present) so overlays cannot re-attach and tint unexpectedly.
    if frame.ScootAtlasBorderTintMask and frame.ScootAtlasBorderTintOverlay then
        pcall(frame.ScootAtlasBorderTintOverlay.RemoveMaskTexture, frame.ScootAtlasBorderTintOverlay, frame.ScootAtlasBorderTintMask)
        if frame.ScootAtlasBorderTintMask.Hide then frame.ScootAtlasBorderTintMask:Hide() end
        if frame.ScootAtlasBorderTintMask.SetAtlas then pcall(frame.ScootAtlasBorderTintMask.SetAtlas, frame.ScootAtlasBorderTintMask, nil) end
        if frame.ScootAtlasBorderTintMask.SetTexture then pcall(frame.ScootAtlasBorderTintMask.SetTexture, frame.ScootAtlasBorderTintMask, nil) end
    end
    if frame.ScootTextureBorderTintMask and frame.ScootTextureBorderTintOverlay then
        pcall(frame.ScootTextureBorderTintOverlay.RemoveMaskTexture, frame.ScootTextureBorderTintOverlay, frame.ScootTextureBorderTintMask)
        if frame.ScootTextureBorderTintMask.Hide then frame.ScootTextureBorderTintMask:Hide() end
        if frame.ScootTextureBorderTintMask.SetAtlas then pcall(frame.ScootTextureBorderTintMask.SetAtlas, frame.ScootTextureBorderTintMask, nil) end
        if frame.ScootTextureBorderTintMask.SetTexture then pcall(frame.ScootTextureBorderTintMask.SetTexture, frame.ScootTextureBorderTintMask, nil) end
    end
end

local function ensureContainer(frame, strata, levelOffset, parent)
    local f = frame.ScootSquareBorderContainer
    if not f then
        f = CreateFrame("Frame", nil, parent or UIParent)
        frame.ScootSquareBorderContainer = f
    end
    local valid = { BACKGROUND=true, LOW=true, MEDIUM=true, HIGH=true, DIALOG=true, FULLSCREEN=true, FULLSCREEN_DIALOG=true, TOOLTIP=true }
    local desiredStrata = valid[strata or ""] and strata or (frame.GetFrameStrata and frame:GetFrameStrata()) or "BACKGROUND"
    local lvlOffset = tonumber(levelOffset) or 5
    f:ClearAllPoints();
    f:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    f:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    f:SetFrameStrata(desiredStrata)
    f:SetFrameLevel((frame:GetFrameLevel() or 0) + lvlOffset)
    f:Show()
    return f
end

local function ensureSquare(frame, layer, sublevel, container)
    local anchor = container or frame
    local edges = anchor.ScootSquareBorderEdges
    if not edges then
        edges = {
            Top = anchor:CreateTexture(nil, layer or "ARTWORK"),
            Bottom = anchor:CreateTexture(nil, layer or "ARTWORK"),
            Left = anchor:CreateTexture(nil, layer or "ARTWORK"),
            Right = anchor:CreateTexture(nil, layer or "ARTWORK"),
        }
        anchor.ScootSquareBorderEdges = edges
    end
    -- Ensure desired draw layer
    local lyr = layer or "ARTWORK"
    local lvl = tonumber(sublevel) or 0
    for _, t in pairs(edges) do if t and t.SetDrawLayer then pcall(t.SetDrawLayer, t, lyr, lvl) end end
    return edges
end

local function colorEdges(edges, r, g, b, a)
    for _, t in pairs(edges) do t:SetColorTexture(r, g, b, a) end
end

function Borders.ApplySquare(frame, opts)
    if not frame or not opts then return end
    hideLegacy(frame)
    local size = math.max(1, tonumber(opts.size) or 1)
    local col = opts.color or {0, 0, 0, 1}
    local r, g, b, a = col[1] or 0, col[2] or 0, col[3] or 0, col[4] or 1
    local layer = (type(opts.layer) == "string") and opts.layer or "ARTWORK"
    local layerSublevel = tonumber(opts.layerSublevel) or 0
    local container
    if opts.containerStrata then
        container = ensureContainer(frame, opts.containerStrata, opts.levelOffset, opts.containerParent)
    end
    local e = ensureSquare(frame, layer, layerSublevel, container)
    colorEdges(e, r, g, b, a)
    local anchor = container or frame
    local expand = tonumber(opts.expand) or 0
    local ex = tonumber(opts.expandX) or expand
    local ey = tonumber(opts.expandY) or expand
    e.Top:ClearAllPoints();    e.Top:SetPoint("TOPLEFT", anchor, "TOPLEFT", -ex, ey);       e.Top:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", ex, ey);     e.Top:SetHeight(size)
    e.Bottom:ClearAllPoints(); e.Bottom:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", -ex, -ey); e.Bottom:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", ex, -ey); e.Bottom:SetHeight(size)
    e.Left:ClearAllPoints();   e.Left:SetPoint("TOPLEFT", anchor, "TOPLEFT", -ex, ey);       e.Left:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", -ex, -ey);   e.Left:SetWidth(size)
    e.Right:ClearAllPoints();  e.Right:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", ex, ey);    e.Right:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", ex, -ey); e.Right:SetWidth(size)
    for _, t in pairs(e) do if t.Show then t:Show() end end
    if container and container.Show then container:Show() end
end

function Borders.HideAll(frame)
    hideLegacy(frame)
end

local ATLAS_PRESETS = {
    -- Intentionally empty for now; icon atlas borders are disabled for bar borders testing
}

local function getAtlasPreset(key)
    for _, it in ipairs(ATLAS_PRESETS) do
        if it.key == key then return it end
    end
end

local function applyTextureInternal(frame, textureObject, params)
    if not frame or not textureObject then return end
    local expandX = tonumber(params.expandX) or tonumber(params.expand) or 0
    local expandY = tonumber(params.expandY) or tonumber(params.expand) or expandX
    local layer = params.layer or "OVERLAY"
    local layerSublevel = tonumber(params.layerSublevel) or 7
    if layerSublevel > 7 then
        layerSublevel = 7
    elseif layerSublevel < -8 then
        layerSublevel = -8
    end

    textureObject:SetDrawLayer(layer, layerSublevel)
    if params.setAtlas then
        textureObject:SetAtlas(params.setAtlas, true)
    elseif params.setTexture then
        textureObject:SetTexture(params.setTexture)
    end

    local tint = params.color
    local r = 1
    local g = 1
    local b = 1
    local a = 1
    if tint and type(tint) == "table" then
        r = tonumber(tint[1]) or 1
        g = tonumber(tint[2]) or 1
        b = tonumber(tint[3]) or 1
        a = tonumber(tint[4]) or 1
    end
    textureObject:SetVertexColor(r, g, b, a)

    local offsets = params.offsets
    local topLeftX, topLeftY, bottomRightX, bottomRightY
    if offsets then
        topLeftX = offsets.left or 0
        topLeftY = offsets.top or 0
        bottomRightX = offsets.right or 0
        bottomRightY = offsets.bottom or 0
    else
        topLeftX = -(expandX)
        topLeftY = expandY
        bottomRightX = expandX
        bottomRightY = -(expandY)
    end

    textureObject:ClearAllPoints()
    textureObject:SetPoint("TOPLEFT", frame, "TOPLEFT", topLeftX, topLeftY)
    textureObject:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", bottomRightX, bottomRightY)
    textureObject:Show()
end

function Borders.ApplyAtlas(frame, opts)
    if not frame or not opts or type(opts.atlas) ~= "string" then return end
    hideLegacy(frame)
    if not frame.ScootAtlasBorder then
        frame.ScootAtlasBorder = frame:CreateTexture(nil, "OVERLAY")
    end

    local preset = getAtlasPreset(opts.atlas)
    local px = 0
    local py = 0
    if preset and preset.padding then
        px = tonumber(preset.padding[1]) or 0
        py = tonumber(preset.padding[2]) or 0
    end

    local extra = tonumber(opts.extraPadding)
    if extra then
        if extra < -8 then extra = -8 elseif extra > 8 then extra = 8 end
        px = px + extra
        py = py + extra
    end

    if opts.expandX ~= nil then
        px = -(tonumber(opts.expandX) or 0)
    end
    if opts.expandY ~= nil then
        py = -(tonumber(opts.expandY) or 0)
    elseif opts.expandX ~= nil then
        py = -(tonumber(opts.expandX) or 0)
    end

    local params = {
        setAtlas = opts.atlas,
        color = opts.tintColor or opts.color or opts.defaultColor,
        layer = opts.layer or "OVERLAY",
        layerSublevel = opts.layerSublevel or 7,
        offsets = opts.offsets or { left = px, top = -py, right = -px, bottom = py },
    }

    applyTextureInternal(frame, frame.ScootAtlasBorder, params)
end

function Borders.ApplyTexture(frame, opts)
    if not frame or not opts or type(opts.texture) ~= "string" then return end
    hideLegacy(frame)
    if not frame.ScootTextureBorder then
        frame.ScootTextureBorder = frame:CreateTexture(nil, "OVERLAY")
    end

    local params = {
        setTexture = opts.texture,
        color = opts.tintColor or opts.color or opts.defaultColor,
        expandX = opts.expandX,
        expandY = opts.expandY,
        layer = opts.layer or "OVERLAY",
        layerSublevel = opts.layerSublevel or 7,
        offsets = opts.offsets,
    }

    applyTextureInternal(frame, frame.ScootTextureBorder, params)
end

function addon.BuildBarBorderOptionsContainer()
    if addon.BarBorders and addon.BarBorders.GetDropdownEntries then
        return addon.BarBorders.GetDropdownEntries({
            previewHeight = 18,
            previewWidth = 160,
        })
    end
    local create = _G.Settings and _G.Settings.CreateControlTextContainer
    if not create then
        return { { value = "square", text = "Default (Square)" } }
    end
    local c = create()
    c:Add("square", "Default (Square)")
    return c:GetData()
end

function addon.BuildIconBorderOptionsContainer()
    if addon.IconBorders and addon.IconBorders.GetDropdownEntries then
        return addon.IconBorders.GetDropdownEntries()
    end
    local create = Settings and Settings.CreateControlTextContainer
    if create then
        local container = create()
        container:Add("square", "Default")
        container:Add("blizzard", "Blizzard Default")
        return container:GetData()
    end
    return {
        { value = "square", text = "Default" },
        { value = "blizzard", text = "Blizzard Default" },
    }
end

-- Backwards compatibility for legacy callers
addon.BuildBorderOptionsContainer = addon.BuildBarBorderOptionsContainer
