local addonName, addon = ...

addon.Borders = addon.Borders or {}
local Borders = addon.Borders

local function hideLegacy(frame)
    if not frame then return end
    if frame.ScootSquareBorder and frame.ScootSquareBorder.edges then
        for _, tex in pairs(frame.ScootSquareBorder.edges) do tex:Hide() end
    end
    if frame.ScootAtlasBorder then frame.ScootAtlasBorder:Hide() end
end

local function ensureSquare(frame)
    if not frame.ScootSquareBorder then
        local f = CreateFrame("Frame", nil, frame)
        f:SetAllPoints(frame)
        f:SetFrameStrata("BACKGROUND")
        f:SetFrameLevel((frame:GetFrameLevel() or 0) + 1)
        f.edges = {
            Top = f:CreateTexture(nil, "ARTWORK"),
            Bottom = f:CreateTexture(nil, "ARTWORK"),
            Left = f:CreateTexture(nil, "ARTWORK"),
            Right = f:CreateTexture(nil, "ARTWORK"),
        }
        frame.ScootSquareBorder = f
    end
    return frame.ScootSquareBorder
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
    local f = ensureSquare(frame)
    f:SetFrameStrata("BACKGROUND")
    f:SetFrameLevel((frame:GetFrameLevel() or 0) + 1)
    local e = f.edges
    colorEdges(e, r, g, b, a)
    e.Top:ClearAllPoints();    e.Top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0);       e.Top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0);     e.Top:SetHeight(size)
    e.Bottom:ClearAllPoints(); e.Bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0); e.Bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0); e.Bottom:SetHeight(size)
    e.Left:ClearAllPoints();   e.Left:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0);       e.Left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0);   e.Left:SetWidth(size)
    e.Right:ClearAllPoints();  e.Right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0);    e.Right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0); e.Right:SetWidth(size)
    for _, t in pairs(e) do t:Show() end
    f:Show()
end

function Borders.HideAll(frame)
    hideLegacy(frame)
end

local ATLAS_PRESETS = {
    { key = "UI-HUD-ActionBar-IconFrame",               name = "Default Blizzard Border",            size = {46,45}, padding = {0,0} },
    { key = "UI-HUD-CoolDownManager-IconOverlay",       name = "Cooldown Manager",                   size = {60,60}, padding = {-6,-6} },
    { key = "wowlabs-ability-icon-frame",               name = "Wowlabs Ability",                    size = {50,50}, padding = {-2,-2} },
    { key = "wowlabs-in-world-item-common",             name = "Wowlabs Item Border",                size = {55,55}, padding = {-4,-4} },
    { key = "plunderstorm-actionbar-slot-border",       name = "Plunderstorm",                        size = {58,58}, padding = {-4,-4} },
    { key = "talents-node-choiceflyout-square-gray",    name = "Talents Gray",                        size = {45,45}, padding = {0,0} },
    { key = "cyphersetupgrade-leftitem-border-empty",   name = "Cypher",                              size = {54,62}, padding = {-5,-5} },
    { key = "Professions-ChoiceReagent-Frame",          name = "Professions",                         size = {50,50}, padding = {-2,-2} },
    { key = "Relicforge-Slot-frame",                    name = "Relicforge",                          size = {62,62}, padding = {-5,-5} },
    { key = "runecarving-icon-reagent-selected",        name = "Runecarving",                         size = {55,55}, padding = {-3,-3} },
    { key = "Soulbinds_Collection_SpecBorder_Primary",  name = "Soulbinds",                           size = {68,68}, padding = {-7,-7} },
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
        for _, it in ipairs(ATLAS_PRESETS) do
            table.insert(out, { value = "atlas:" .. it.key, text = it.name })
        end
        return out
    end
    local c = create()
    c:Add("square", "Default")
    for _, it in ipairs(ATLAS_PRESETS) do
        c:Add("atlas:" .. it.key, it.name)
    end
    return c:GetData()
end


