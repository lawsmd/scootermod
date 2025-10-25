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

function Borders.ApplyAtlas(frame, opts)
    if not frame or not opts or type(opts.atlas) ~= "string" then return end
    hideLegacy(frame)
    if not frame.ScootAtlasBorder then
        frame.ScootAtlasBorder = frame:CreateTexture(nil, "OVERLAY")
    end
    local tex = frame.ScootAtlasBorder
    tex:SetDrawLayer("OVERLAY", 7)
    tex:SetAtlas(opts.atlas, true)
    do
        local r, g, b, a = 1, 1, 1, 1
        local tc = opts.tintColor
        if tc and type(tc) == "table" then
            r = tonumber(tc[1]) or 1
            g = tonumber(tc[2]) or 1
            b = tonumber(tc[3]) or 1
            a = tonumber(tc[4]) or 1
        end
        tex:SetVertexColor(r, g, b, a)
    end
    tex:ClearAllPoints()
    local preset = getAtlasPreset(opts.atlas)
    local px, py = 0, 0
    if preset and preset.padding then
        px = tonumber(preset.padding[1]) or 0
        py = tonumber(preset.padding[2]) or 0
    end
    local extra = tonumber(opts.extraPadding) or 0
    if extra ~= 0 then
        if extra < -4 then extra = -4 elseif extra > 4 then extra = 4 end
        px = px + extra
        py = py + extra
    end
    tex:SetPoint("TOPLEFT", frame, "TOPLEFT", px, -py)
    tex:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -px, py)
    tex:Show()
end

function addon.BuildBorderOptionsContainer()
    local create = _G.Settings and _G.Settings.CreateControlTextContainer
    if not create then
        local out = {
            { value = "square", text = "Default" },
        }
        return out
    end
    local c = create()
    c:Add("square", "Default")
    return c:GetData()
end


