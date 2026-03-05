-- classauras/core.lua - Shared infrastructure for Class Auras system
local addonName, addon = ...

addon.ClassAuras = addon.ClassAuras or {}
local CA = addon.ClassAuras

local Component = addon.ComponentPrototype

--------------------------------------------------------------------------------
-- Registry
--------------------------------------------------------------------------------

CA._registry = {}       -- [auraId] = auraDef (flat lookup)
CA._classAuras = {}     -- [classToken] = { auraDef, auraDef, ... }
CA._activeAuras = {}    -- [auraId] = { container, elements, component }
CA._trackedUnits = {}   -- [unitToken] = true — built from registered auras

local spellToAura = {}  -- [spellId] = auraDef — O(1) reverse lookup for UNIT_AURA addedAuras matching
local nameToAura = {}   -- [lowerName] = auraDef — O(1) name-based fallback when spellId is secret

local editModeActive = false

-- CDM Borrow subsystem: hides CDM icons via SetAlphaFromBoolean when Class Auras
-- takes over display. Duration/timing data comes from DurationObject API (live C++ object).
local cdmBorrow = {
    hookInstalled = false,
}
-- Track which CDM item frames already have Show/SetShown hooks installed
local hookedItemFrames = setmetatable({}, { __mode = "k" })
-- Track CDM item frames we've hidden via SetAlphaFromBoolean — itemFrame → auraId
local hiddenItemFrames = setmetatable({}, { __mode = "k" })

-- DurationObject-based aura tracking: maps auraId → { unit, auraInstanceID }
-- Populated by FindAuraOnUnit (direct scan), CDM SetAuraInstanceInfo hook, and RescanForCDMBorrow.
-- OnUpdate uses C_UnitAuras.GetAuraDuration(unit, auraInstanceID) to get live DurationObject each frame.
local auraTracking = {}

-- Deferred retry gate: prevents duplicate timers per aura. Separate from state
-- so StopAuraDisplay can't inadvertently reset it (which caused infinite loops in v1).
local pendingRetries = {}  -- [auraId] = true

-- GUID-based identity cache: persists across target switches for instant re-acquisition.
-- Populated by any successful aura identification (direct scan, CDM hook, addedAuras, rescan).
-- Indexed by unit GUID (not "target" token) so cache survives target switching.
local guidCache = {}  -- [unitGUID] = { auraId, auraInstanceID, activeSpellId }

local function CacheAuraIdentity(unit, auraId, auraInstanceID, activeSpellId)
    local ok, guid = pcall(UnitGUID, unit)
    if ok and guid and not issecretvalue(guid) then
        guidCache[guid] = {
            auraId = auraId,
            auraInstanceID = auraInstanceID,
            activeSpellId = activeSpellId,
        }
    end
end

-- Forward declarations (defined after Layout/Styling sections)
local FindCDMItemForSpell, BindCDMBorrowTarget, InstallMixinHooks, RescanForCDMBorrow
local StartAuraDisplay, StopAuraDisplay, StyleCooldownText
local GetActiveOverride

-- Expose for debug command
CA._cdmBorrow = cdmBorrow
CA._guidCache = guidCache

function CA.RegisterAuras(classToken, auras)
    if not classToken or not auras then return end
    CA._classAuras[classToken] = CA._classAuras[classToken] or {}
    for _, aura in ipairs(auras) do
        aura.classToken = classToken
        CA._registry[aura.id] = aura
        table.insert(CA._classAuras[classToken], aura)
        if aura.unit then
            CA._trackedUnits[aura.unit] = true
        end
        spellToAura[aura.auraSpellId] = aura
        if aura.linkedSpellIds then
            for _, linkedId in ipairs(aura.linkedSpellIds) do
                spellToAura[linkedId] = aura
            end
        end
        -- Populate name-based fallback for when spellId is secret in combat
        local nameOk, spellName = pcall(C_Spell.GetSpellName, aura.auraSpellId)
        if nameOk and spellName and not issecretvalue(spellName) then
            nameToAura[spellName:lower()] = aura
        end
        if aura.linkedSpellIds then
            for _, linkedId in ipairs(aura.linkedSpellIds) do
                local lok, lname = pcall(C_Spell.GetSpellName, linkedId)
                if lok and lname and not issecretvalue(lname) then
                    nameToAura[lname:lower()] = aura
                end
            end
        end
    end
end

--- Returns the list of aura definitions for a class token (or empty table).
function CA.GetClassAuras(classToken)
    return CA._classAuras[classToken] or {}
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local _, playerClassToken = UnitClass("player")

local function GetComponentId(aura)
    return "classAura_" .. aura.id
end

local function GetDB(aura)
    local comp = addon.Components and addon.Components[GetComponentId(aura)]
    return comp and comp.db
end

--------------------------------------------------------------------------------
-- Element Creation
--------------------------------------------------------------------------------

local function CreateTextElement(container, elemDef)
    local fs = container:CreateFontString(nil, "OVERLAY")
    local fontFace = addon.ResolveFontFace("FRIZQT__")
    addon.ApplyFontStyle(fs, fontFace, elemDef.baseSize or 24, "OUTLINE")
    if elemDef.justifyH then
        fs:SetJustifyH(elemDef.justifyH)
    end
    fs:Hide()
    return { type = "text", widget = fs, def = elemDef }
end

local function CreateTextureElement(container, elemDef)
    local tex = container:CreateTexture(nil, "ARTWORK")
    if elemDef.path then
        tex:SetTexture(elemDef.path)
    elseif elemDef.customPath then
        tex:SetTexture(elemDef.customPath)
    end
    local size = elemDef.defaultSize or { 32, 32 }
    tex:SetSize(size[1], size[2])
    tex:Hide()
    return { type = "texture", widget = tex, def = elemDef }
end

local function CreateBarElement(container, elemDef)
    local barRegion = CreateFrame("Frame", nil, container)
    local size = elemDef.defaultSize or { 120, 12 }
    barRegion:SetSize(size[1], size[2])

    -- Background texture
    local barBg = barRegion:CreateTexture(nil, "BACKGROUND", nil, -1)
    barBg:SetAllPoints(barRegion)

    -- StatusBar fill
    local barFill = CreateFrame("StatusBar", nil, barRegion)
    barFill:SetAllPoints(barRegion)
    barFill:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    barFill:SetMinMaxValues(0, elemDef.maxValue or 20)
    barFill:SetValue(0)

    barRegion:Hide()

    return {
        type = "bar",
        widget = barRegion,
        barFill = barFill,
        barBg = barBg,
        def = elemDef,
    }
end

local elementCreators = {
    text = CreateTextElement,
    texture = CreateTextureElement,
    bar = CreateBarElement,
}

--------------------------------------------------------------------------------
-- Layout Engine
--------------------------------------------------------------------------------

-- Anchor mapping for "inside" mode: anchor point → offset direction
local INSIDE_OFFSETS = {
    TOPLEFT     = {  2, -2 },
    TOP         = {  0, -2 },
    TOPRIGHT    = { -2, -2 },
    LEFT        = {  2,  0 },
    CENTER      = {  0,  0 },
    RIGHT       = { -2,  0 },
    BOTTOMLEFT  = {  2,  2 },
    BOTTOM      = {  0,  2 },
    BOTTOMRIGHT = { -2,  2 },
}

local GAP = 2 -- hardcoded gap between icon and text in "outside" mode

local function LayoutElements(aura, state)
    if not state or not state.elements then return end

    local db = GetDB(aura)

    -- Find text, texture, and bar elements
    local textElem, texElem, barElem
    for _, elem in ipairs(state.elements) do
        if elem.type == "text" then textElem = elem end
        if elem.type == "texture" then texElem = elem end
        if elem.type == "bar" then barElem = elem end
    end

    -- Mode-based visibility
    local displayMode = (db and db.mode) or "icon"
    local showIcon = (displayMode == "icon" or displayMode == "iconbar")
    local showBar  = (displayMode == "bar" or displayMode == "iconbar")
    local showText = not (db and db.hideText)

    -- Backward compat: treat iconMode "hidden" as mode override
    if db and db.iconMode == "hidden" then
        showIcon = false
    end

    -- Compute icon dimensions from settings (avoids secret-value issues from GetWidth/GetHeight)
    local iconW, iconH = 32, 32
    if texElem then
        if not showIcon then
            iconW, iconH = 0, 0
            texElem.widget:Hide()
        else
            local mode = db and db.iconMode or "default"
            local baseW = texElem.def.defaultSize and texElem.def.defaultSize[1] or 32
            local baseH = texElem.def.defaultSize and texElem.def.defaultSize[2] or 32
            if mode == "default" then
                local ratio = tonumber(db and db.iconShape) or 0
                if ratio ~= 0 and addon.IconRatio and addon.IconRatio.CalculateDimensions then
                    iconW, iconH = addon.IconRatio.CalculateDimensions(baseW, ratio)
                else
                    iconW, iconH = baseW, baseH
                end
            else
                iconW, iconH = baseW, baseH
            end
        end
    end

    -- Bar dimensions from settings
    local barW = tonumber(db and db.barWidth) or 120
    local barH = tonumber(db and db.barHeight) or 12

    -- Size and show/hide bar element
    if barElem then
        if showBar then
            barElem.widget:SetSize(barW, barH)
        else
            barElem.widget:Hide()
        end
    end

    -- Hide text if mode is text-only and there's no icon anchor — text still shows
    if not showText and textElem then
        textElem.widget:Hide()
    end

    local textPosition = (db and db.textPosition) or "inside"

    if textPosition == "outside" then
        local anchor = (db and db.textOuterAnchor) or "RIGHT"
        local txOff = tonumber(db and db.textOffsetX) or 0
        local tyOff = tonumber(db and db.textOffsetY) or 0

        if texElem and showIcon then
            texElem.widget:ClearAllPoints()
            texElem.widget:Show()
        end
        if textElem and showText then
            textElem.widget:ClearAllPoints()
            textElem.widget:Show()
        end

        local textW, textH = 0, 0
        if textElem and showText then
            local ok, w = pcall(textElem.widget.GetStringWidth, textElem.widget)
            if ok and type(w) == "number" and not issecretvalue(w) then textW = w end
            local ok2, h = pcall(textElem.widget.GetHeight, textElem.widget)
            if ok2 and type(h) == "number" and not issecretvalue(h) then textH = h end
        end

        if anchor == "RIGHT" then
            if texElem and showIcon then texElem.widget:SetPoint("LEFT", state.container, "LEFT", 0, 0) end
            if textElem and showText then
                textElem.widget:SetJustifyH("LEFT")
                if texElem and showIcon then
                    textElem.widget:SetPoint("LEFT", texElem.widget, "RIGHT", GAP + txOff, tyOff)
                else
                    textElem.widget:SetPoint("LEFT", state.container, "LEFT", txOff, tyOff)
                end
            end
            state.container:SetSize(math.max(iconW + GAP + textW, 1), math.max(iconH, 1))

        elseif anchor == "LEFT" then
            if texElem and showIcon then texElem.widget:SetPoint("RIGHT", state.container, "RIGHT", 0, 0) end
            if textElem and showText then
                textElem.widget:SetJustifyH("RIGHT")
                if texElem and showIcon then
                    textElem.widget:SetPoint("RIGHT", texElem.widget, "LEFT", -GAP + txOff, tyOff)
                else
                    textElem.widget:SetPoint("RIGHT", state.container, "RIGHT", txOff, tyOff)
                end
            end
            state.container:SetSize(math.max(textW + GAP + iconW, 1), math.max(iconH, 1))

        elseif anchor == "ABOVE" then
            if texElem and showIcon then texElem.widget:SetPoint("BOTTOM", state.container, "BOTTOM", 0, 0) end
            if textElem and showText then
                textElem.widget:SetJustifyH("CENTER")
                if texElem and showIcon then
                    textElem.widget:SetPoint("BOTTOM", texElem.widget, "TOP", txOff, GAP + tyOff)
                else
                    textElem.widget:SetPoint("BOTTOM", state.container, "BOTTOM", txOff, tyOff)
                end
            end
            state.container:SetSize(math.max(iconW, 1), math.max(iconH + GAP + textH, 1))

        elseif anchor == "BELOW" then
            if texElem and showIcon then texElem.widget:SetPoint("TOP", state.container, "TOP", 0, 0) end
            if textElem and showText then
                textElem.widget:SetJustifyH("CENTER")
                if texElem and showIcon then
                    textElem.widget:SetPoint("TOP", texElem.widget, "BOTTOM", txOff, -GAP + tyOff)
                else
                    textElem.widget:SetPoint("TOP", state.container, "TOP", txOff, tyOff)
                end
            end
            state.container:SetSize(math.max(iconW, 1), math.max(iconH + GAP + textH, 1))
        end

    else -- "inside" mode
        local innerAnchor = (db and db.textInnerAnchor) or "CENTER"

        if texElem and showIcon then
            texElem.widget:ClearAllPoints()
            texElem.widget:SetAllPoints(state.container)
            texElem.widget:Show()
        end

        if textElem and showText then
            textElem.widget:ClearAllPoints()
            local offsets = INSIDE_OFFSETS[innerAnchor] or { 0, 0 }
            local txOff = tonumber(db and db.textOffsetX) or 0
            local tyOff = tonumber(db and db.textOffsetY) or 0
            textElem.widget:SetPoint(innerAnchor, state.container, innerAnchor, offsets[1] + txOff, offsets[2] + tyOff)
            textElem.widget:SetJustifyH("CENTER")
            textElem.widget:Show()
        end

        state.container:SetSize(math.max(iconW, 1), math.max(iconH, 1))
    end

    -- Position bar relative to icon/container
    if barElem and showBar then
        barElem.widget:ClearAllPoints()
        local barPos = (db and db.barPosition) or "LEFT"
        local bxOff = tonumber(db and db.barOffsetX) or 0
        local byOff = tonumber(db and db.barOffsetY) or 0

        if showIcon and iconW > 0 then
            -- Anchor bar relative to icon
            if barPos == "LEFT" then
                barElem.widget:SetPoint("RIGHT", state.container, "LEFT", -GAP + bxOff, byOff)
            else -- "RIGHT"
                barElem.widget:SetPoint("LEFT", state.container, "RIGHT", GAP + bxOff, byOff)
            end
        else
            -- No icon visible: bar at container center
            barElem.widget:SetPoint("CENTER", state.container, "CENTER", bxOff, byOff)
            -- Resize container to fit bar when bar is the primary element
            if displayMode == "bar" then
                state.container:SetSize(math.max(barW, 1), math.max(barH, 1))
            elseif displayMode == "text" then
                -- text mode: container stays icon-sized for text anchor
            end
        end

        barElem.widget:Show()
    end
end

--------------------------------------------------------------------------------
-- Styling
--------------------------------------------------------------------------------

local function ApplyIconMode(aura, state)
    local db = GetDB(aura)
    if not db then return end

    -- Check if icon should be hidden by display mode
    local displayMode = db.mode or "icon"
    local showIcon = (displayMode == "icon" or displayMode == "iconbar")

    for _, elem in ipairs(state.elements or {}) do
        if elem.type == "texture" then
            local mode = db.iconMode or "default"
            if not showIcon or mode == "hidden" then
                elem.widget:Hide()
            elseif mode == "custom" then
                local override = GetActiveOverride(aura)
                local path = (override and override.customPath) or elem.def.customPath
                if path then elem.widget:SetTexture(path) end
                elem.widget:Show()
            else
                -- "default": use the spell icon (override spell or primary), fallback to customPath
                local override = GetActiveOverride(aura)
                local spellForTexture = (override and override.overrideSpellId) or aura.auraSpellId
                local ok, tex = pcall(function()
                    return C_Spell.GetSpellTexture(spellForTexture)
                end)
                if ok and tex then
                    elem.widget:SetTexture(tex)
                elseif override and override.customPath then
                    elem.widget:SetTexture(override.customPath)
                elseif elem.def.customPath then
                    elem.widget:SetTexture(elem.def.customPath)
                end
                elem.widget:Show()
            end
        end
    end
end

local function ApplyTextStyling(aura, state)
    local db = GetDB(aura)
    if not db then return end

    for _, elem in ipairs(state.elements or {}) do
        if elem.type == "text" then
            local fontKey = db.textFont or "FRIZQT__"
            local fontFace = addon.ResolveFontFace(fontKey)
            local fontStyle = db.textStyle or "OUTLINE"
            local size = db.textSize or elem.def.baseSize or 24
            addon.ApplyFontStyle(elem.widget, fontFace, size, fontStyle)

            local override = GetActiveOverride(aura)
            local color = (override and override.textColor) or db.textColor
            if color and type(color) == "table" then
                elem.widget:SetTextColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
            end
        end
    end
end

local function ApplyIconShape(aura, state)
    local db = GetDB(aura)
    if not db then return end

    for _, elem in ipairs(state.elements or {}) do
        if elem.type == "texture" then
            local mode = db.iconMode or "default"
            local baseW = elem.def.defaultSize and elem.def.defaultSize[1] or 32
            local baseH = elem.def.defaultSize and elem.def.defaultSize[2] or 32
            if mode == "default" then
                local ratio = tonumber(db.iconShape) or 0
                if ratio ~= 0 and addon.IconRatio and addon.IconRatio.CalculateDimensions then
                    local w, h = addon.IconRatio.CalculateDimensions(baseW, ratio)
                    elem.widget:SetSize(w, h)
                else
                    elem.widget:SetSize(baseW, baseH)
                end
            else
                elem.widget:SetSize(baseW, baseH)
            end
        end
    end
end

local function ApplyBorders(aura, state)
    local db = GetDB(aura)
    if not db then return end

    for _, elem in ipairs(state.elements or {}) do
        if elem.type == "texture" then
            local mode = db.iconMode or "default"
            local style = db.borderStyle or "none"

            -- Ensure border frame exists (parented to container, anchored to texture)
            if not elem.borderFrame then
                elem.borderFrame = CreateFrame("Frame", nil, state.container)
                elem.borderFrame:SetFrameLevel(state.container:GetFrameLevel() + 2)
                elem.borderFrame.borderEdges = {
                    Top = elem.borderFrame:CreateTexture(nil, "OVERLAY", nil, 1),
                    Bottom = elem.borderFrame:CreateTexture(nil, "OVERLAY", nil, 1),
                    Left = elem.borderFrame:CreateTexture(nil, "OVERLAY", nil, 1),
                    Right = elem.borderFrame:CreateTexture(nil, "OVERLAY", nil, 1),
                }
                for _, tex in pairs(elem.borderFrame.borderEdges) do tex:Hide() end
                elem.borderFrame.atlasBorder = elem.borderFrame:CreateTexture(nil, "OVERLAY", nil, 2)
                elem.borderFrame.atlasBorder:Hide()
            end

            -- Anchor border frame to texture widget
            elem.borderFrame:ClearAllPoints()
            elem.borderFrame:SetAllPoints(elem.widget)

            if mode ~= "default" or style == "none" then
                for _, tex in pairs(elem.borderFrame.borderEdges) do tex:Hide() end
                elem.borderFrame.atlasBorder:Hide()
                elem.borderFrame:Hide()
            else
                elem.borderFrame:Show()
                local opts = {
                    style = style,
                    thickness = tonumber(db.borderThickness) or 1,
                    insetH = tonumber(db.borderInsetH) or 0,
                    insetV = tonumber(db.borderInsetV) or 0,
                    color = db.borderTintEnable and db.borderTintColor or {0, 0, 0, 1},
                    tintEnabled = db.borderTintEnable,
                    tintColor = db.borderTintColor,
                }

                local styleDef = nil
                if style ~= "square" and addon.IconBorders and addon.IconBorders.GetStyle then
                    styleDef = addon.IconBorders.GetStyle(style)
                end

                if styleDef and styleDef.type == "atlas" and styleDef.atlas then
                    -- Atlas border
                    for _, tex in pairs(elem.borderFrame.borderEdges) do tex:Hide() end
                    local atlasTex = elem.borderFrame.atlasBorder
                    local col = opts.tintEnabled and opts.tintColor or styleDef.defaultColor or {1, 1, 1, 1}
                    atlasTex:SetAtlas(styleDef.atlas, true)
                    atlasTex:SetVertexColor(col[1] or 1, col[2] or 1, col[3] or 1, col[4] or 1)
                    local expandX = (styleDef.expandX or 0) - opts.insetH
                    local expandY = (styleDef.expandY or styleDef.expandX or 0) - opts.insetV
                    atlasTex:ClearAllPoints()
                    atlasTex:SetPoint("TOPLEFT", elem.borderFrame, "TOPLEFT", -expandX - (styleDef.adjustLeft or 0), expandY + (styleDef.adjustTop or 0))
                    atlasTex:SetPoint("BOTTOMRIGHT", elem.borderFrame, "BOTTOMRIGHT", expandX + (styleDef.adjustRight or 0), -expandY - (styleDef.adjustBottom or 0))
                    atlasTex:Show()
                else
                    -- Square border
                    elem.borderFrame.atlasBorder:Hide()
                    local edges = elem.borderFrame.borderEdges
                    local thickness = math.max(1, opts.thickness)
                    local col = opts.color
                    local r, g, b, a = col[1] or 0, col[2] or 0, col[3] or 0, col[4] or 1
                    for _, tex in pairs(edges) do tex:SetColorTexture(r, g, b, a) end

                    edges.Top:ClearAllPoints()
                    edges.Top:SetPoint("TOPLEFT", elem.borderFrame, "TOPLEFT", -opts.insetH, opts.insetV)
                    edges.Top:SetPoint("TOPRIGHT", elem.borderFrame, "TOPRIGHT", opts.insetH, opts.insetV)
                    edges.Top:SetHeight(thickness)

                    edges.Bottom:ClearAllPoints()
                    edges.Bottom:SetPoint("BOTTOMLEFT", elem.borderFrame, "BOTTOMLEFT", -opts.insetH, -opts.insetV)
                    edges.Bottom:SetPoint("BOTTOMRIGHT", elem.borderFrame, "BOTTOMRIGHT", opts.insetH, -opts.insetV)
                    edges.Bottom:SetHeight(thickness)

                    edges.Left:ClearAllPoints()
                    edges.Left:SetPoint("TOPLEFT", elem.borderFrame, "TOPLEFT", -opts.insetH, opts.insetV - thickness)
                    edges.Left:SetPoint("BOTTOMLEFT", elem.borderFrame, "BOTTOMLEFT", -opts.insetH, -opts.insetV + thickness)
                    edges.Left:SetWidth(thickness)

                    edges.Right:ClearAllPoints()
                    edges.Right:SetPoint("TOPRIGHT", elem.borderFrame, "TOPRIGHT", opts.insetH, opts.insetV - thickness)
                    edges.Right:SetPoint("BOTTOMRIGHT", elem.borderFrame, "BOTTOMRIGHT", opts.insetH, -opts.insetV + thickness)
                    edges.Right:SetWidth(thickness)

                    for _, tex in pairs(edges) do tex:Show() end
                end
            end
        end
    end
end

local function ApplyBarStyling(aura, state)
    local db = GetDB(aura)
    if not db then return end

    for _, elem in ipairs(state.elements or {}) do
        if elem.type == "bar" then
            -- Dimensions
            local w = tonumber(db.barWidth) or 120
            local h = tonumber(db.barHeight) or 12
            elem.widget:SetSize(w, h)

            -- Foreground texture
            local fgTexKey = db.barForegroundTexture or "bevelled"
            local fgPath = addon.Media.ResolveBarTexturePath(fgTexKey)
            if fgPath then
                elem.barFill:SetStatusBarTexture(fgPath)
            else
                elem.barFill:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
            end

            -- Foreground color
            local fgColorMode = db.barForegroundColorMode or "custom"
            local fgR, fgG, fgB, fgA = 1, 1, 1, 1
            if fgColorMode == "original" then
                fgR, fgG, fgB, fgA = 1, 1, 1, 1  -- no tint, show texture's native color
            elseif fgColorMode == "class" then
                local classColor = RAID_CLASS_COLORS[playerClassToken]
                if classColor then
                    fgR, fgG, fgB, fgA = classColor.r, classColor.g, classColor.b, 1
                end
            else -- "custom" (or any fallback)
                local override = GetActiveOverride(aura)
                local c
                if override and override.barColor then
                    c = override.barColor
                else
                    c = db.barForegroundTint or aura.defaultBarColor or { 1, 1, 1, 1 }
                end
                fgR, fgG, fgB, fgA = c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
            end
            local fillTex = elem.barFill:GetStatusBarTexture()
            if fillTex then
                fillTex:SetVertexColor(fgR, fgG, fgB, fgA)
            end

            -- Background texture
            local bgTexKey = db.barBackgroundTexture or "bevelled"
            local bgPath = addon.Media.ResolveBarTexturePath(bgTexKey)
            if bgPath then
                elem.barBg:SetTexture(bgPath)
            else
                elem.barBg:SetColorTexture(0.1, 0.1, 0.1, 1)
            end

            -- Background color
            local bgColorMode = db.barBackgroundColorMode or "custom"
            if bgColorMode == "original" then
                elem.barBg:SetVertexColor(1, 1, 1, 1)
            else -- "custom"
                local c = db.barBackgroundTint or { 0, 0, 0, 1 }
                elem.barBg:SetVertexColor(c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1)
            end

            -- Background opacity
            elem.barBg:SetAlpha((db.barBackgroundOpacity or 50) / 100)

            -- Border
            local borderStyle = db.barBorderStyle or "none"
            local borderThickness = math.max(1, tonumber(db.barBorderThickness) or 1)
            local borderInsetH = tonumber(db.barBorderInsetH) or 0
            local borderInsetV = tonumber(db.barBorderInsetV) or 0
            local borderColor = { 0, 0, 0, 1 }
            if db.barBorderTintEnable and db.barBorderTintColor then
                borderColor = db.barBorderTintColor
            end
            local bR, bG, bB, bA = borderColor[1] or 0, borderColor[2] or 0, borderColor[3] or 0, borderColor[4] or 1

            if borderStyle == "square" then
                -- Square border: draw edge textures ourselves (BarBorders.ApplyToBarFrame
                -- treats "square" as a clear since it's not a backdrop-template style)
                if addon.BarBorders then
                    addon.BarBorders.ClearBarFrame(elem.barFill)
                end

                -- Ensure edge textures exist on the bar region
                if not elem.squareBorder then
                    local bf = CreateFrame("Frame", nil, elem.widget)
                    bf:SetFrameLevel(elem.widget:GetFrameLevel() + 2)
                    bf.edges = {
                        Top = bf:CreateTexture(nil, "OVERLAY", nil, 1),
                        Bottom = bf:CreateTexture(nil, "OVERLAY", nil, 1),
                        Left = bf:CreateTexture(nil, "OVERLAY", nil, 1),
                        Right = bf:CreateTexture(nil, "OVERLAY", nil, 1),
                    }
                    elem.squareBorder = bf
                end

                local bf = elem.squareBorder
                bf:ClearAllPoints()
                bf:SetAllPoints(elem.widget)
                bf:Show()

                local edges = bf.edges
                for _, tex in pairs(edges) do tex:SetColorTexture(bR, bG, bB, bA) end

                edges.Top:ClearAllPoints()
                edges.Top:SetPoint("TOPLEFT", bf, "TOPLEFT", -borderInsetH, borderInsetV)
                edges.Top:SetPoint("TOPRIGHT", bf, "TOPRIGHT", borderInsetH, borderInsetV)
                edges.Top:SetHeight(borderThickness)

                edges.Bottom:ClearAllPoints()
                edges.Bottom:SetPoint("BOTTOMLEFT", bf, "BOTTOMLEFT", -borderInsetH, -borderInsetV)
                edges.Bottom:SetPoint("BOTTOMRIGHT", bf, "BOTTOMRIGHT", borderInsetH, -borderInsetV)
                edges.Bottom:SetHeight(borderThickness)

                edges.Left:ClearAllPoints()
                edges.Left:SetPoint("TOPLEFT", bf, "TOPLEFT", -borderInsetH, borderInsetV - borderThickness)
                edges.Left:SetPoint("BOTTOMLEFT", bf, "BOTTOMLEFT", -borderInsetH, -borderInsetV + borderThickness)
                edges.Left:SetWidth(borderThickness)

                edges.Right:ClearAllPoints()
                edges.Right:SetPoint("TOPRIGHT", bf, "TOPRIGHT", borderInsetH, borderInsetV - borderThickness)
                edges.Right:SetPoint("BOTTOMRIGHT", bf, "BOTTOMRIGHT", borderInsetH, -borderInsetV + borderThickness)
                edges.Right:SetWidth(borderThickness)

                for _, tex in pairs(edges) do tex:Show() end

            elseif borderStyle ~= "none" and addon.BarBorders and addon.BarBorders.ApplyToBarFrame then
                -- Custom asset border via BarBorders module
                if elem.squareBorder then
                    for _, tex in pairs(elem.squareBorder.edges) do tex:Hide() end
                    elem.squareBorder:Hide()
                end
                addon.BarBorders.ApplyToBarFrame(elem.barFill, borderStyle, {
                    thickness = borderThickness,
                    insetH = borderInsetH,
                    insetV = borderInsetV,
                    color = borderColor,
                })
            else
                -- "none": clear everything
                if elem.squareBorder then
                    for _, tex in pairs(elem.squareBorder.edges) do tex:Hide() end
                    elem.squareBorder:Hide()
                end
                if addon.BarBorders then
                    addon.BarBorders.ClearBarFrame(elem.barFill)
                end
            end
        end
    end
end

GetActiveOverride = function(aura)
    if not aura.spellOverrides then return nil end
    local tracked = auraTracking[aura.id]
    if not tracked or not tracked.activeSpellId then return nil end
    if tracked.activeSpellId == aura.auraSpellId then return nil end
    return aura.spellOverrides[tracked.activeSpellId]
end

local function ApplyStyling(aura)
    local state = CA._activeAuras[aura.id]
    if not state then return end

    local db = GetDB(aura)
    if not db then return end

    -- Reset override tracking so next ScanAura re-evaluates
    state._lastActiveSpellId = nil

    -- CDM borrow: rescan on enable/disable to hide/restore CDM icon
    if aura.cdmBorrow then
        C_Timer.After(0, RescanForCDMBorrow)
    end

    -- Enabled check
    if not db.enabled then
        state.container:Hide()
        return
    end

    -- Scale
    local scale = (db.scale or 100) / 100
    state.container:SetScale(math.max(scale, 0.25))

    -- Opacity (priority: combat > target > out-of-combat)
    local opacityValue = 100
    if InCombatLockdown() then
        opacityValue = tonumber(db.opacityInCombat) or 100
    elseif UnitExists("target") then
        opacityValue = tonumber(db.opacityWithTarget) or 100
    else
        opacityValue = tonumber(db.opacityOutOfCombat) or 100
    end
    state.container:SetAlpha(opacityValue / 100)

    -- Icon mode
    ApplyIconMode(aura, state)

    -- Icon shape (adjusts dimensions based on ratio slider)
    ApplyIconShape(aura, state)

    -- Borders (icon borders)
    ApplyBorders(aura, state)

    -- Text styling
    ApplyTextStyling(aura, state)

    -- Bar styling
    ApplyBarStyling(aura, state)

    -- Re-layout elements
    LayoutElements(aura, state)

    -- Trigger a rescan to show/hide based on current aura state
    CA.ScanAura(aura)
end

--------------------------------------------------------------------------------
-- Aura Scanning
--------------------------------------------------------------------------------

local IsAuraFilteredOutByInstanceID = C_UnitAuras.IsAuraFilteredOutByInstanceID

-- Broad-filter aura scanning: post-scan ownership + name matching.
-- Strips |PLAYER from the filter, scans all matching auras, then verifies ownership afterward.
-- Key design points:
--   1. Filter broadened (strip |PLAYER) — ownership checked post-scan
--   2. Name-based matching fallback via inline canonName resolution
--   3. Post-scan ownership via sourceUnit then IsAuraFilteredOutByInstanceID
local function FindAuraOnUnit(unit, filter, spellId, linkedSpellIds)
    -- Strip |PLAYER from filter — ownership is verified post-scan via
    -- sourceUnit or IsAuraFilteredOutByInstanceID instead.
    local broadFilter = filter and filter:gsub("|PLAYER", "") or filter

    -- Pre-resolve the canonical spell name for name-based matching
    local canonName
    pcall(function()
        local n = C_Spell.GetSpellName(spellId)
        if n and not issecretvalue(n) then canonName = n:lower() end
    end)

    for i = 1, 40 do
        local auraData = C_UnitAuras.GetAuraDataByIndex(unit, i, broadFilter)
        if not auraData then break end

        local matched = false
        local matchedSpell = nil

        -- Primary: spellId match
        pcall(function()
            if not issecretvalue(auraData.spellId) then
                if auraData.spellId == spellId then
                    matched = true
                    matchedSpell = spellId
                elseif linkedSpellIds then
                    for _, linkedId in ipairs(linkedSpellIds) do
                        if auraData.spellId == linkedId then
                            matched = true
                            matchedSpell = linkedId
                            break
                        end
                    end
                end
            end
        end)

        -- Fallback: name match
        if not matched and canonName then
            pcall(function()
                if auraData.name and not issecretvalue(auraData.name) then
                    if auraData.name:lower() == canonName then
                        matched = true
                        matchedSpell = spellId  -- attribute to primary spell
                    end
                end
            end)
        end

        if matched then
            -- Post-scan ownership check (tri-state: nil=unknown, true=mine, false=not mine)
            local isMine = nil  -- nil = unknown, true = yes, false = no

            -- Non-secret path: sourceUnit check
            pcall(function()
                if not issecretvalue(auraData.sourceUnit) then
                    isMine = (auraData.sourceUnit == "player" or auraData.sourceUnit == "pet")
                end
            end)

            -- Secret fallback: IsAuraFilteredOutByInstanceID
            if isMine == nil then
                pcall(function()
                    local iid = auraData.auraInstanceID
                    if iid and not issecretvalue(iid) then
                        isMine = not IsAuraFilteredOutByInstanceID(unit, iid, filter)
                    end
                end)
            end

            -- Accept match if mine or if ownership couldn't be determined
            -- (unknown ownership accepted; CDM de-secrets later if needed)
            if isMine ~= false then
                return auraData, matchedSpell
            end
        end
    end
    return nil, nil
end

function CA.ScanAura(aura)
    local state = CA._activeAuras[aura.id]
    if not state then return end

    local db = GetDB(aura)
    if not db or not db.enabled then
        state.container:Hide()
        return
    end

    if not UnitExists(aura.unit) then
        if not editModeActive then
            StopAuraDisplay(aura.id)
            state.container:Hide()
        end
        return
    end

    if not aura.filter or not aura.auraSpellId then return end

    -- === Try direct scan first (works when spellId comparison isn't secret) ===
    local auraData, matchedSpellId = FindAuraOnUnit(aura.unit, aura.filter, aura.auraSpellId, aura.linkedSpellIds)
    if auraData then
        -- Capture auraInstanceID + activeSpellId for DurationObject tracking
        pcall(function()
            local iid = auraData.auraInstanceID
            if iid and not issecretvalue(iid) then
                auraTracking[aura.id] = { unit = aura.unit, auraInstanceID = iid, activeSpellId = matchedSpellId }
                CacheAuraIdentity(aura.unit, aura.id, iid, matchedSpellId)
            end
        end)

        -- Applications from direct scan
        local ok, apps = pcall(function() return auraData.applications end)
        if ok and apps then
            local scanDb = GetDB(aura)
            local scanHideText = scanDb and scanDb.hideText
            local displayApps = (apps == 0) and 1 or apps
            for _, elem in ipairs(state.elements) do
                if elem.def.source == "applications" then
                    if elem.type == "text" then
                        if not scanHideText then
                            pcall(elem.widget.SetText, elem.widget, tostring(displayApps))
                            pcall(elem.widget.Show, elem.widget)
                        end
                    elseif elem.type == "bar" then
                        pcall(elem.barFill.SetValue, elem.barFill, displayApps)
                    end
                end
            end
        end
    end

    -- === Validate tracked instance (from direct scan, CDM hook, or rescan) ===
    local tracked = auraTracking[aura.id]
    if tracked then
        local dok, durObj = pcall(C_UnitAuras.GetAuraDuration, tracked.unit, tracked.auraInstanceID)
        if not dok or not durObj then
            auraTracking[aura.id] = nil
        end
    end

    -- Re-check after validation
    tracked = auraTracking[aura.id]
    if not tracked then
        StopAuraDisplay(aura.id)
        if not editModeActive then state.container:Hide() end
        -- Single deferred retry: catches CDM hook delay + transient secret windows.
        -- pendingRetries gate prevents duplicate/cascading timers for the same aura.
        if not pendingRetries[aura.id] and UnitExists(aura.unit) then
            pendingRetries[aura.id] = true
            local auraRef = aura
            C_Timer.After(0.2, function()
                pendingRetries[auraRef.id] = nil
                if CA._activeAuras[auraRef.id] and UnitExists(auraRef.unit) then
                    CA.ScanAura(auraRef)
                end
            end)
        end
        return
    end

    -- === Start/update display via DurationObject ===
    StartAuraDisplay(aura.id)

    -- === Detect linked spell override changes (icon/bar/text visual swap) ===
    local tracked2 = auraTracking[aura.id]
    if tracked2 and aura.spellOverrides then
        local prevActive = state._lastActiveSpellId
        local curActive = tracked2.activeSpellId
        if prevActive ~= curActive then
            state._lastActiveSpellId = curActive
            ApplyIconMode(aura, state)
            ApplyTextStyling(aura, state)
            ApplyBarStyling(aura, state)
        end
    end

    -- === Applications via combat-safe API (when direct scan didn't provide them) ===
    if not auraData then
        local fallbackDb = GetDB(aura)
        local fallbackHideText = fallbackDb and fallbackDb.hideText
        for _, elem in ipairs(state.elements) do
            if elem.def.source == "applications" then
                local aok, countStr = pcall(C_UnitAuras.GetAuraApplicationDisplayCount,
                    tracked.unit, tracked.auraInstanceID, 1)
                if aok and countStr then
                    if elem.type == "text" then
                        if not fallbackHideText then
                            local displayStr = countStr
                            if not issecretvalue(countStr) and (countStr == "" or countStr == "0") then
                                displayStr = "1"
                            end
                            pcall(elem.widget.SetText, elem.widget, displayStr)
                            pcall(elem.widget.Show, elem.widget)
                        end
                    elseif elem.type == "bar" then
                        if not issecretvalue(countStr) then
                            local num = tonumber(countStr)
                            if num then
                                pcall(elem.barFill.SetValue, elem.barFill, (num == 0) and 1 or num)
                            end
                        end
                    end
                end
            end
        end
    end
end

local function ScanAllAurasForUnit(unit)
    local auras = CA._classAuras[playerClassToken]
    if not auras then return end
    for _, aura in ipairs(auras) do
        if aura.unit == unit and CA._activeAuras[aura.id] then
            CA.ScanAura(aura)
        end
    end
end

local function ScanAllAuras()
    local auras = CA._classAuras[playerClassToken]
    if not auras then return end
    for _, aura in ipairs(auras) do
        if CA._activeAuras[aura.id] then
            CA.ScanAura(aura)
        end
    end
end

--------------------------------------------------------------------------------
-- Duration Display (DurationObject-based — unified combat/non-combat)
--------------------------------------------------------------------------------
-- Uses C_UnitAuras.GetAuraDuration() to get a live C++ DurationObject each frame.
-- StatusBar:SetValue/SetMinMaxValues and Cooldown:SetCooldown are AllowedWhenTainted,
-- so bar fill and countdown text work correctly even with secret values.

StyleCooldownText = function(elem, auraId)
    if not elem._cdFrame then return end
    local fs = elem._cdFrame:GetCountdownFontString()
    if not fs then return end
    local auraDef = CA._registry[auraId]
    local state = CA._activeAuras[auraId]
    if not state then return end
    local db = GetDB(auraDef)
    if not db then return end
    local fontKey = db.textFont or "FRIZQT__"
    local fontFace = addon.ResolveFontFace(fontKey)
    local fontSize = db.textSize or 24
    local fontFlags = db.textStyle or "OUTLINE"
    pcall(fs.SetFont, fs, fontFace, fontSize, fontFlags)
    local override = GetActiveOverride(CA._registry[auraId])
    local c = (override and override.textColor) or db.textColor or { 1, 1, 1, 1 }
    pcall(fs.SetTextColor, fs, c[1], c[2], c[3], c[4])
end

StopAuraDisplay = function(auraId)
    auraTracking[auraId] = nil
    local state = CA._activeAuras[auraId]
    if not state then return end
    state._lastActiveSpellId = nil
    state.container:SetScript("OnUpdate", nil)
    for _, elem in ipairs(state.elements) do
        if elem.type == "text" and elem.def.source == "duration" then
            pcall(elem.widget.SetText, elem.widget, "")
            pcall(elem.widget.Show, elem.widget)
        end
        if elem.type == "bar" and elem.def.source == "duration" then
            pcall(elem.barFill.SetValue, elem.barFill, 0)
        end
    end
    -- Hide CooldownFrame fallback text if present
    for _, elem in ipairs(state.elements) do
        if elem._cdFrame then elem._cdFrame:Hide() end
    end
    if not editModeActive then
        state.container:Hide()
    end
end

StartAuraDisplay = function(auraId)
    local state = CA._activeAuras[auraId]
    if not state then return end
    local auraDef = CA._registry[auraId]
    if not auraDef then return end
    local t = auraTracking[auraId]
    if not t then return end

    -- Get initial DurationObject for CooldownFrame setup
    local ok, durObj = pcall(C_UnitAuras.GetAuraDuration, t.unit, t.auraInstanceID)
    if not ok or not durObj then
        StopAuraDisplay(auraId)
        return
    end
    -- Set up CooldownFrame for each duration text element (fallback for secret text)
    for _, elem in ipairs(state.elements) do
        if elem.type == "text" and elem.def.source == "duration" then
            if not elem._cdFrame then
                local cdFrame = CreateFrame("Cooldown", nil, state.container, "CooldownFrameTemplate")
                cdFrame:SetAllPoints(elem.widget)
                cdFrame:SetDrawSwipe(false)
                cdFrame:SetDrawEdge(false)
                cdFrame:SetHideCountdownNumbers(false)
                elem._cdFrame = cdFrame
            end
            -- Set the cooldown (accepts secrets via AllowedWhenTainted)
            local startTime = durObj:GetStartTime()
            local totalDur = durObj:GetTotalDuration()
            pcall(elem._cdFrame.SetCooldown, elem._cdFrame, startTime, totalDur)
            -- Style countdown font to match user settings
            StyleCooldownText(elem, auraId)
            elem._cdFrame:Hide()  -- Start hidden; OnUpdate toggles visibility
        end
    end

    -- Set initial bar range
    for _, elem in ipairs(state.elements) do
        if elem.type == "bar" and elem.def.source == "duration" then
            pcall(elem.barFill.SetMinMaxValues, elem.barFill, 0, durObj:GetTotalDuration())
        end
    end

    LayoutElements(auraDef, state)
    state.container:Show()

    -- Single unified OnUpdate — uses DurationObject for all timing
    state.container:SetScript("OnUpdate", function(self)
        local track = auraTracking[auraId]
        if not track then self:SetScript("OnUpdate", nil); return end

        -- Fresh DurationObject each frame (live C++ object, always current)
        local dOk, dObj = pcall(C_UnitAuras.GetAuraDuration, track.unit, track.auraInstanceID)
        if not dOk or not dObj then
            StopAuraDisplay(auraId)
            return
        end
        -- === BAR: always accurate (SetValue/SetMinMaxValues accept secrets) ===
        for _, elem in ipairs(state.elements) do
            if elem.type == "bar" and elem.def.source == "duration" then
                pcall(elem.barFill.SetMinMaxValues, elem.barFill, 0, dObj:GetTotalDuration())
                local fillMode = elem.def.fillMode or "deplete"
                if fillMode == "deplete" then
                    pcall(elem.barFill.SetValue, elem.barFill, dObj:GetRemainingDuration())
                else
                    pcall(elem.barFill.SetValue, elem.barFill, dObj:GetElapsedDuration())
                end
            end
        end

        -- === TEXT: try non-secret custom format, fall back to CooldownFrame ===
        local htDb = GetDB(auraDef)
        local hideText = htDb and htDb.hideText
        for _, elem in ipairs(state.elements) do
            if elem.type == "text" and elem.def.source == "duration" then
                if hideText then
                    pcall(elem.widget.Hide, elem.widget)
                    if elem._cdFrame then elem._cdFrame:Hide() end
                else
                    local rok, remaining = pcall(function()
                        local r = dObj:GetRemainingDuration()
                        if issecretvalue(r) then return nil end
                        return r
                    end)
                    if rok and remaining and remaining > 0 then
                        -- Non-secret: custom formatted text
                        local text
                        if remaining >= 60 then
                            text = string.format("%dm", math.floor(remaining / 60))
                        elseif remaining >= 10 then
                            text = string.format("%.0f", remaining)
                        else
                            text = string.format("%.1f", remaining)
                        end
                        pcall(elem.widget.SetText, elem.widget, text)
                        pcall(elem.widget.Show, elem.widget)
                        if elem._cdFrame then elem._cdFrame:Hide() end
                    else
                        -- Secret: CooldownFrame handles countdown via C++ rendering
                        pcall(elem.widget.Hide, elem.widget)
                        if elem._cdFrame then elem._cdFrame:Show() end
                    end
                end
            end
        end
    end)
end

--------------------------------------------------------------------------------
-- CDM Borrow: Hide CDM icons via SetAlpha(0)
--------------------------------------------------------------------------------
-- When Class Auras takes over display, we hide the corresponding CDM icon
-- to avoid duplicates. Duration comes from DurationObject, stacks from direct scan or GetAuraApplicationDisplayCount.

local function searchViewer(viewerName, spellId)
    local viewer = _G[viewerName]
    if not viewer then return nil end
    local ok, children = pcall(function() return { viewer:GetChildren() } end)
    if not ok or not children then return nil end
    for _, child in ipairs(children) do
        -- GetBaseSpellID() is a plain Lua table read (self.cooldownInfo.spellID),
        -- populated by Blizzard's untainted code — returns real data even in combat.
        local idOk, childSpellId = pcall(function() return child:GetBaseSpellID() end)
        if idOk and childSpellId == spellId then
            return child
        end
    end
    -- Fallback: search linkedSpellIDs (e.g., 188389 Flame Shock is linked under base 470411)
    for _, child in ipairs(children) do
        local ciOk, found = pcall(function()
            local ci = child:GetCooldownInfo()
            if ci and ci.linkedSpellIDs then
                for _, lid in ipairs(ci.linkedSpellIDs) do
                    if lid == spellId then return true end
                end
            end
            return false
        end)
        if ciOk and found then
            return child
        end
    end
    return nil
end

FindCDMItemForSpell = function(spellId)
    -- Search icon layout first (most common), then bar layout
    return searchViewer("BuffIconCooldownViewer", spellId)
        or searchViewer("BuffBarCooldownViewer", spellId)
end

BindCDMBorrowTarget = function(itemFrame, aura)
    -- Install Show/SetShown hooks to re-apply alpha when CDM redisplays the icon
    if not hookedItemFrames[itemFrame] then
        hookedItemFrames[itemFrame] = true

        hooksecurefunc(itemFrame, "Show", function(self)
            if hiddenItemFrames[self] then
                self:SetAlphaFromBoolean(false, 1, 0)
            end
        end)

        hooksecurefunc(itemFrame, "SetShown", function(self, shown)
            if shown and hiddenItemFrames[self] then
                self:SetAlphaFromBoolean(false, 1, 0)
            end
        end)
    end

    -- Apply or remove CDM icon hiding
    local db = GetDB(aura)
    if db and db.enabled and (db.hideFromCDM ~= false) then
        itemFrame:SetAlphaFromBoolean(false, 1, 0)
        hiddenItemFrames[itemFrame] = aura.id
    elseif hiddenItemFrames[itemFrame] then
        itemFrame:SetAlphaFromBoolean(true, 1, 0)
        hiddenItemFrames[itemFrame] = nil
    end
end

InstallMixinHooks = function()
    if cdmBorrow.hookInstalled then return end

    -- Hook SetAuraInstanceInfo to capture auraInstanceID for combat tracking.
    -- When CDM processes an aura in its untainted context, this fires and gives
    -- us the non-secret spellID (from cooldownInfo) and the auraInstanceID.
    local dataMixin = _G.CooldownViewerItemDataMixin
    if dataMixin and dataMixin.SetAuraInstanceInfo then
        hooksecurefunc(dataMixin, "SetAuraInstanceInfo", function(self, auraInfo)
            local ci = self.cooldownInfo
            if not ci then return end
            local spellID = ci.spellID
            if ci.linkedSpellIDs and ci.linkedSpellIDs[1] then
                spellID = ci.linkedSpellIDs[1]
            end
            if not spellID then return end

            local instanceID = auraInfo and auraInfo.auraInstanceID
            local unit = self.auraDataUnit
            if not instanceID or not unit then return end

            local auras = CA._classAuras[playerClassToken]
            if not auras then return end
            for _, aura in ipairs(auras) do
                if aura.cdmBorrow then
                    local cdmId = aura.cdmSpellId or aura.auraSpellId
                    local auraSpell = auraInfo and auraInfo.spellId
                    local matchesAuraSpell = false
                    if auraSpell then
                        pcall(function()
                            if not issecretvalue(auraSpell) then
                                matchesAuraSpell = (auraSpell == aura.auraSpellId)
                            end
                        end)
                    end
                    if spellID == cdmId or spellID == aura.auraSpellId or matchesAuraSpell then
                        -- Determine activeSpellId from auraInfo.spellId (actual debuff spell)
                        local activeSpell = aura.auraSpellId  -- default to primary
                        if auraInfo and auraInfo.spellId then
                            pcall(function()
                                local infoSpell = auraInfo.spellId
                                if not issecretvalue(infoSpell) then
                                    if infoSpell == aura.auraSpellId then
                                        activeSpell = aura.auraSpellId
                                    elseif aura.linkedSpellIds then
                                        for _, lid in ipairs(aura.linkedSpellIds) do
                                            if infoSpell == lid then activeSpell = lid; break end
                                        end
                                    end
                                end
                            end)
                        end
                        local tracked = auraTracking[aura.id]
                        if not tracked or tracked.auraInstanceID ~= instanceID then
                            auraTracking[aura.id] = { unit = unit, auraInstanceID = instanceID, activeSpellId = activeSpell }
                            CacheAuraIdentity(unit, aura.id, instanceID, activeSpell)
                        end
                        local auraId = aura.id
                        C_Timer.After(0, function()
                            local a = CA._registry[auraId]
                            if a then CA.ScanAura(a) end
                        end)
                        break
                    end
                end
            end
        end)
    end

    -- Hook RefreshData to catch icon pool recycling (for CDM icon alpha re-find)
    local buffMixin = _G.CooldownViewerBuffIconItemMixin
    if buffMixin and buffMixin.RefreshData then
        hooksecurefunc(buffMixin, "RefreshData", function()
            C_Timer.After(0, function() RescanForCDMBorrow() end)
        end)
    end

    -- Hook OnAuraInstanceInfoCleared (for CDM icon alpha re-find)
    local baseMixin = _G.CooldownViewerItemMixin
    if baseMixin and baseMixin.OnAuraInstanceInfoCleared then
        hooksecurefunc(baseMixin, "OnAuraInstanceInfoCleared", function()
            C_Timer.After(0, function() RescanForCDMBorrow() end)
        end)
    end

    -- CooldownFrame_Set/Clear hooks removed — duration comes from DurationObject API

    cdmBorrow.hookInstalled = true
end

local function RestoreHiddenCDMFrames(auraId)
    for frame, id in pairs(hiddenItemFrames) do
        if id == auraId then
            frame:SetAlphaFromBoolean(true, 1, 0)
            hiddenItemFrames[frame] = nil
        end
    end
end

RescanForCDMBorrow = function()
    local auras = CA._classAuras[playerClassToken]
    if not auras then return end

    for _, aura in ipairs(auras) do
        if aura.cdmBorrow then
            local state = CA._activeAuras[aura.id]
            if state then
                local db = GetDB(aura)
                if not db or not db.enabled then
                    RestoreHiddenCDMFrames(aura.id)
                elseif UnitExists(aura.unit) then
                    local cdmId = aura.cdmSpellId or aura.auraSpellId
                    local itemFrame = FindCDMItemForSpell(cdmId)
                    if not itemFrame and aura.cdmSpellId and aura.auraSpellId then
                        itemFrame = FindCDMItemForSpell(aura.auraSpellId)
                    end
                    if itemFrame then
                        -- Capture identity (auraInstanceID + unit + activeSpellId) for DurationObject tracking
                        local iid = itemFrame.auraInstanceID
                        local iunit = itemFrame.auraDataUnit
                        if iid and iunit then
                            -- Validate CDM frame's auraInstanceID before storing (prevents stale overwrites)
                            local vOk, vDur = pcall(C_UnitAuras.GetAuraDuration, iunit, iid)
                            if vOk and vDur then
                                local activeSpell = aura.auraSpellId
                                pcall(function()
                                    local fSpell = itemFrame.auraSpellID
                                    if fSpell and not issecretvalue(fSpell) and aura.linkedSpellIds then
                                        for _, lid in ipairs(aura.linkedSpellIds) do
                                            if fSpell == lid then activeSpell = lid; break end
                                        end
                                    end
                                end)
                                local tracked = auraTracking[aura.id]
                                if not tracked or tracked.auraInstanceID ~= iid then
                                    auraTracking[aura.id] = { unit = iunit, auraInstanceID = iid, activeSpellId = activeSpell }
                                    CacheAuraIdentity(iunit, aura.id, iid, activeSpell)
                                end
                            end
                        end
                        BindCDMBorrowTarget(itemFrame, aura)
                    else
                        -- Don't clear auraTracking — let ScanAura's GetAuraDuration handle stale instances.
                        -- CDM icon may be gone due to target switch, but aura may still exist on original target.
                        RestoreHiddenCDMFrames(aura.id)
                    end
                end
            end
        end
    end
end

-- Expose for debug
CA._rescanForCDMBorrow = function() RescanForCDMBorrow() end

--------------------------------------------------------------------------------
-- Frame Creation
--------------------------------------------------------------------------------

local containersInitialized = false

local function CreateAuraContainer(aura)
    local frameName = "ScootClassAura_" .. aura.id
    local container = CreateFrame("Frame", frameName, UIParent)
    container:SetSize(64, 32) -- initial size, auto-resized by layout
    container:SetMovable(true)
    container:SetClampedToScreen(true)

    -- Default position
    local dp = aura.defaultPosition or { point = "CENTER", x = 0, y = -200 }
    container:SetPoint(dp.point, dp.x or 0, dp.y or 0)
    container:Hide()

    -- Create elements from definition
    local elements = {}
    for _, elemDef in ipairs(aura.elements or {}) do
        local creator = elementCreators[elemDef.type]
        if creator then
            table.insert(elements, creator(container, elemDef))
        end
    end

    CA._activeAuras[aura.id] = {
        container = container,
        elements = elements,
    }

    return container
end

local function InitializeContainers()
    local auras = CA._classAuras[playerClassToken]
    if not auras then return end

    for _, aura in ipairs(auras) do
        if not CA._activeAuras[aura.id] then
            CreateAuraContainer(aura)
        end
    end
end

--------------------------------------------------------------------------------
-- LibEditMode Integration
--------------------------------------------------------------------------------

local function SaveAuraPosition(auraId, layoutName, point, x, y)
    if not addon.db or not addon.db.profile then return end
    addon.db.profile.classAuraPositions = addon.db.profile.classAuraPositions or {}
    addon.db.profile.classAuraPositions[auraId] = addon.db.profile.classAuraPositions[auraId] or {}
    addon.db.profile.classAuraPositions[auraId][layoutName] = {
        point = point,
        x = x,
        y = y,
    }
end

local function RestoreAuraPosition(auraId, layoutName)
    local state = CA._activeAuras[auraId]
    if not state or not state.container then return end

    local positions = addon.db and addon.db.profile and addon.db.profile.classAuraPositions
    local auraPositions = positions and positions[auraId]
    local pos = auraPositions and auraPositions[layoutName]

    if pos and pos.point then
        state.container:ClearAllPoints()
        state.container:SetPoint(pos.point, pos.x or 0, pos.y or 0)
    end
end

local function InitializeEditMode()
    local lib = LibStub("LibEditMode", true)
    if not lib then return end

    local auras = CA._classAuras[playerClassToken]
    if not auras then return end

    for _, aura in ipairs(auras) do
        local state = CA._activeAuras[aura.id]
        if state and state.container then
            state.container.editModeName = aura.editModeName or aura.label

            local auraId = aura.id
            local dp = aura.defaultPosition or { point = "CENTER", x = 0, y = -200 }

            lib:AddFrame(state.container, function(frame, layoutName, point, x, y)
                if point and x and y then
                    frame:ClearAllPoints()
                    frame:SetPoint(point, x, y)
                end
                if layoutName then
                    local savedPoint, _, _, savedX, savedY = frame:GetPoint(1)
                    if savedPoint then
                        SaveAuraPosition(auraId, layoutName, savedPoint, savedX, savedY)
                    else
                        SaveAuraPosition(auraId, layoutName, point, x, y)
                    end
                end
            end, {
                point = dp.point,
                x = dp.x or 0,
                y = dp.y or 0,
            }, nil)
        end
    end

    lib:RegisterCallback("layout", function(layoutName, layoutIndex)
        local classAuras = CA._classAuras[playerClassToken]
        if not classAuras then return end
        for _, aura in ipairs(classAuras) do
            RestoreAuraPosition(aura.id, layoutName)
        end
    end)

    lib:RegisterCallback("enter", function()
        editModeActive = true
        local classAuras = CA._classAuras[playerClassToken]
        if not classAuras then return end
        for _, aura in ipairs(classAuras) do
            local st = CA._activeAuras[aura.id]
            if st and st.container then
                local db = GetDB(aura)
                if db and db.enabled then
                    ApplyIconMode(aura, st)
                    ApplyTextStyling(aura, st)
                    ApplyBarStyling(aura, st)
                    LayoutElements(aura, st)
                    st.container:Show()
                    -- Set preview for elements and hide CooldownFrame fallback
                    local emHideText = db.hideText
                    for _, elem in ipairs(st.elements) do
                        if elem._cdFrame then elem._cdFrame:Hide() end
                        if elem.type == "text" and elem.def.source == "applications" then
                            if not emHideText then
                                pcall(elem.widget.SetText, elem.widget, "#")
                                pcall(elem.widget.Show, elem.widget)
                            end
                        end
                        if elem.type == "text" and elem.def.source == "duration" then
                            if not emHideText then
                                pcall(elem.widget.SetText, elem.widget, "8.3")
                                pcall(elem.widget.Show, elem.widget)
                            end
                        end
                        -- Bar preview: ~60% fill
                        if elem.type == "bar" and elem.def.source == "applications" then
                            local maxVal = elem.def.maxValue or 20
                            pcall(elem.barFill.SetValue, elem.barFill, math.floor(maxVal * 0.6))
                        end
                        if elem.type == "bar" and elem.def.source == "duration" then
                            local maxVal = 20  -- preview value for edit mode
                            pcall(elem.barFill.SetMinMaxValues, elem.barFill, 0, maxVal)
                            pcall(elem.barFill.SetValue, elem.barFill, math.floor(maxVal * 0.6))
                        end
                    end
                end
            end
        end
    end)

    lib:RegisterCallback("exit", function()
        editModeActive = false
        local classAuras = CA._classAuras[playerClassToken]
        if not classAuras then return end
        for _, aura in ipairs(classAuras) do
            -- Clear preview text and bar before rescan
            local st = CA._activeAuras[aura.id]
            if st then
                for _, elem in ipairs(st.elements) do
                    if elem.type == "text" and elem.def.source == "applications" then
                        pcall(elem.widget.SetText, elem.widget, "")
                    end
                    if elem.type == "text" and elem.def.source == "duration" then
                        pcall(elem.widget.SetText, elem.widget, "")
                    end
                    if elem.type == "bar" and elem.def.source == "applications" then
                        pcall(elem.barFill.SetValue, elem.barFill, 0)
                    end
                    if elem.type == "bar" and elem.def.source == "duration" then
                        pcall(elem.barFill.SetValue, elem.barFill, 0)
                    end
                end
                -- Stop any active aura display before rescan
                StopAuraDisplay(aura.id)
            end
            if CA._activeAuras[aura.id] then
                CA.ScanAura(aura)
            end
        end
        RescanForCDMBorrow()
    end)
end

--------------------------------------------------------------------------------
-- Rebuild
--------------------------------------------------------------------------------

local function RebuildAll()
    local auras = CA._classAuras[playerClassToken]
    if not auras then return end

    for _, aura in ipairs(auras) do
        ApplyStyling(aura)
    end
end

--------------------------------------------------------------------------------
-- Event Handling
--------------------------------------------------------------------------------

local rebuildPending = false

local caEventFrame = CreateFrame("Frame")
caEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
caEventFrame:RegisterEvent("UNIT_AURA")
caEventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
caEventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
caEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

caEventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        if not containersInitialized then
            InitializeContainers()
            containersInitialized = true

            C_Timer.After(0.5, function()
                RebuildAll()
                InitializeEditMode()
            end)

            -- Install CDM mixin hooks and do initial scans after CDM loads
            C_Timer.After(1.0, function()
                InstallMixinHooks()
                ScanAllAuras()
                RescanForCDMBorrow()
            end)
        else
            RebuildAll()
            C_Timer.After(0.5, function()
                ScanAllAuras()
                RescanForCDMBorrow()
            end)
        end

    elseif event == "UNIT_AURA" then
        local unit, updateInfo = ...
        if CA._trackedUnits[unit] then
            -- Check for removal of tracked instances (NeverSecretContents = true)
            if updateInfo and updateInfo.removedAuraInstanceIDs then
                for _, removedID in ipairs(updateInfo.removedAuraInstanceIDs) do
                    for auraId, tracked in pairs(auraTracking) do
                        if tracked.auraInstanceID == removedID and tracked.unit == unit then
                            auraTracking[auraId] = nil
                            break
                        end
                    end
                    -- Invalidate GUID cache entries referencing the removed instance
                    for guid, cached in pairs(guidCache) do
                        if cached.auraInstanceID == removedID then
                            guidCache[guid] = nil
                            break
                        end
                    end
                end
            end

            -- Detect pandemic refresh: re-trigger CooldownFrame setup with fresh DurationObject
            if updateInfo and updateInfo.updatedAuraInstanceIDs then
                local auras = CA._classAuras[playerClassToken]
                if auras then
                    for _, aura in ipairs(auras) do
                        local tracked = auraTracking[aura.id]
                        if tracked and tracked.unit == unit then
                            for _, updatedID in ipairs(updateInfo.updatedAuraInstanceIDs) do
                                if updatedID == tracked.auraInstanceID then
                                    CA.ScanAura(aura)
                                    break
                                end
                            end
                        end
                    end
                end
            end

            -- === Process addedAuras for instant identity capture ===
            -- Two-tier matching: spellId (O(1)), then name fallback (O(1)) when spellId is secret.
            -- pcall ensures zero regression if fields happen to be secret in some edge case.
            if updateInfo and updateInfo.addedAuras then
                for _, addedAura in ipairs(updateInfo.addedAuras) do
                    pcall(function()
                        local iid = addedAura.auraInstanceID
                        if not iid or issecretvalue(iid) then return end

                        local sid = addedAura.spellId
                        local matchedAura = nil
                        local activeSpell = nil

                        -- Primary: spellId match (O(1))
                        if sid and not issecretvalue(sid) then
                            matchedAura = spellToAura[sid]
                            activeSpell = sid
                        end

                        -- Fallback: name match when spellId is secret (O(1) table lookup)
                        if not matchedAura then
                            local auraName = addedAura.name
                            if auraName and not issecretvalue(auraName) then
                                matchedAura = nameToAura[auraName:lower()]
                                if matchedAura then
                                    activeSpell = matchedAura.auraSpellId
                                end
                            end
                        end

                        if matchedAura and matchedAura.unit == unit and CA._activeAuras[matchedAura.id] then
                            auraTracking[matchedAura.id] = {
                                unit = unit,
                                auraInstanceID = iid,
                                activeSpellId = activeSpell,
                            }
                            CacheAuraIdentity(unit, matchedAura.id, iid, activeSpell)
                        end
                    end)
                end
            end

            -- === GUID cache cross-reference for isFullUpdate (when spellId is secret) ===
            if updateInfo.isFullUpdate and updateInfo.addedAuras then
                local tok2, uguid = pcall(UnitGUID, unit)
                if tok2 and uguid and not issecretvalue(uguid) then
                    local auras2 = CA._classAuras[playerClassToken]
                    if auras2 then
                        for _, aura in ipairs(auras2) do
                            if aura.unit == unit and CA._activeAuras[aura.id] and not auraTracking[aura.id] then
                                local cached = guidCache[uguid]
                                if cached and cached.auraId == aura.id then
                                    for _, addedAura in ipairs(updateInfo.addedAuras) do
                                        pcall(function()
                                            local iid = addedAura.auraInstanceID
                                            if not issecretvalue(iid) and iid == cached.auraInstanceID then
                                                auraTracking[aura.id] = {
                                                    unit = unit,
                                                    auraInstanceID = cached.auraInstanceID,
                                                    activeSpellId = cached.activeSpellId,
                                                }
                                            end
                                        end)
                                    end
                                end
                            end
                        end
                    end
                end
            end

            ScanAllAurasForUnit(unit)   -- Direct scan + DurationObject tracking
            RescanForCDMBorrow()        -- CDM icon alpha + instanceID capture
            C_Timer.After(0, function() ScanAllAurasForUnit(unit) end)
        end

    elseif event == "PLAYER_TARGET_CHANGED" then
        -- GUID cache: instant re-acquisition for previously-seen targets
        local auras = CA._classAuras[playerClassToken]
        if auras then
            local tok, tguid = pcall(UnitGUID, "target")
            if tok and tguid and not issecretvalue(tguid) then
                for _, aura in ipairs(auras) do
                    if aura.unit == "target" and CA._activeAuras[aura.id] then
                        local cached = guidCache[tguid]
                        if cached and cached.auraId == aura.id then
                            local dok, durObj = pcall(C_UnitAuras.GetAuraDuration, "target", cached.auraInstanceID)
                            if dok and durObj then
                                -- Cache hit: populate tracking immediately
                                auraTracking[aura.id] = {
                                    unit = "target",
                                    auraInstanceID = cached.auraInstanceID,
                                    activeSpellId = cached.activeSpellId,
                                }
                            else
                                guidCache[tguid] = nil  -- invalid
                            end
                        end
                    end
                end
            end
        end

        ScanAllAuras()
        RescanForCDMBorrow()
        C_Timer.After(0, function()
            ScanAllAuras()
            RescanForCDMBorrow()
        end)
        C_Timer.After(0.1, function() RescanForCDMBorrow() end)

    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Leaving combat: rescan auras and CDM alpha state
        ScanAllAuras()
        RescanForCDMBorrow()

    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        wipe(guidCache)
        if not rebuildPending then
            rebuildPending = true
            C_Timer.After(0.2, function()
                rebuildPending = false
                RebuildAll()
            end)
        end
    end
end)

--------------------------------------------------------------------------------
-- Component Registration
--------------------------------------------------------------------------------

addon:RegisterComponentInitializer(function(self)
    local auras = CA._classAuras[playerClassToken]
    if not auras then return end

    for _, aura in ipairs(auras) do
        local auraCopy = aura -- upvalue for closure
        local comp = Component:New({
            id = GetComponentId(aura),
            name = "Class Aura: " .. aura.label,
            settings = aura.settings,
            ApplyStyling = function(component)
                ApplyStyling(auraCopy)
            end,
        })
        self:RegisterComponent(comp)
    end
end)
