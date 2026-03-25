-- classauras/mage.lua - Mage class aura definitions
local addonName, addon = ...

local CA = addon.ClassAuras

--------------------------------------------------------------------------------
-- Alter Time: Health % Snapshot Helpers
--------------------------------------------------------------------------------

-- Anchor mapping for "inside" mode (mirrors layout.lua)
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
local GAP = 2

local function applyHealthTextFont(auraId, state)
    local fs = state._healthPctFS
    if not fs then return end
    local auraDef = CA._registry[auraId]
    local db = auraDef and CA._GetDB(auraDef)
    if not db then return end
    local fontKey = db.healthTextFont or "FRIZQT__"
    local fontFace = addon.ResolveFontFace(fontKey)
    local fontSize = db.healthTextSize or 16
    local fontStyle = db.healthTextStyle or "OUTLINE"
    addon.ApplyFontStyle(fs, fontFace, fontSize, fontStyle)
end

local function positionHealthText(auraId, state)
    local fs = state._healthPctFS
    if not fs then return end
    local auraDef = CA._registry[auraId]
    local db = auraDef and CA._GetDB(auraDef)
    if not db then return end

    fs:ClearAllPoints()

    local position = db.healthTextPosition or "outside"
    local txOff = tonumber(db.healthTextOffsetX) or 0
    local tyOff = tonumber(db.healthTextOffsetY) or 0

    -- Find icon texture element for anchoring
    local anchorWidget = state.container
    for _, elem in ipairs(state.elements) do
        if elem.type == "texture" then anchorWidget = elem.widget; break end
    end

    if position == "outside" then
        local anchor = db.healthTextOuterAnchor or "ABOVE"
        if anchor == "RIGHT" then
            fs:SetJustifyH("LEFT")
            fs:SetPoint("LEFT", anchorWidget, "RIGHT", GAP + txOff, tyOff)
        elseif anchor == "LEFT" then
            fs:SetJustifyH("RIGHT")
            fs:SetPoint("RIGHT", anchorWidget, "LEFT", -GAP + txOff, tyOff)
        elseif anchor == "ABOVE" then
            fs:SetJustifyH("CENTER")
            fs:SetPoint("BOTTOM", anchorWidget, "TOP", txOff, GAP + tyOff)
        elseif anchor == "BELOW" then
            fs:SetJustifyH("CENTER")
            fs:SetPoint("TOP", anchorWidget, "BOTTOM", txOff, -GAP + tyOff)
        end
    else -- "inside"
        local innerAnchor = db.healthTextInnerAnchor or "CENTER"
        local offsets = INSIDE_OFFSETS[innerAnchor] or { 0, 0 }
        fs:SetPoint(innerAnchor, state.container, innerAnchor, offsets[1] + txOff, offsets[2] + tyOff)
        fs:SetJustifyH("CENTER")
    end
end

-- Read health text from Blizzard's PlayerFrame (secret string, but SetText accepts it).
-- RightText is typically health percentage on the default frame.
local function getBlizzardHealthText()
    local pf = _G.PlayerFrame
    if not pf then return nil end
    local content = pf.PlayerFrameContent
    local main = content and content.PlayerFrameContentMain
    local hbc = main and main.HealthBarsContainer
    local bar = hbc and hbc.HealthBar
    local leftText = bar and bar.LeftText
    if leftText and leftText.GetText then
        local ok, text = pcall(leftText.GetText, leftText)
        if ok and text then return text end
    end
    return nil
end

-- Apply Color by Value color from current player health to a FontString.
-- RGB values are secret — pass them directly to SetTextColor (AllowedWhenTainted).
local function applyHealthColorToFS(fs)
    local curve = addon.BarsTextures and addon.BarsTextures.getHealthValueCurve
        and addon.BarsTextures.getHealthValueCurve()
    if curve then
        local ok, color = pcall(UnitHealthPercent, "player", true, curve)
        if ok and color and type(color) ~= "number" and color.GetRGB then
            local r, g, b = color:GetRGB()
            pcall(fs.SetTextColor, fs, r, g, b, 1)  -- AllowedWhenTainted: accepts secret RGB
            return true
        end
    end
    pcall(fs.SetTextColor, fs, 0, 1, 0, 1)  -- fallback green
    return false
end

--------------------------------------------------------------------------------
-- Alter Time: Lifecycle Hooks
--------------------------------------------------------------------------------

local function AlterTimeOnContainerCreated(auraId, state)
    local fs = state.container:CreateFontString(nil, "OVERLAY")
    local fontFace = addon.ResolveFontFace("FRIZQT__")
    addon.ApplyFontStyle(fs, fontFace, 16, "OUTLINE")
    fs:Hide()
    state._healthPctFS = fs
    state._healthPctInstance = nil
    state._healthPctSnapped = nil
end

local function AlterTimeOnAuraFound(auraId, state)
    local fs = state._healthPctFS
    if not fs then return end

    local auraDef = CA._registry[auraId]
    local db = auraDef and CA._GetDB(auraDef)
    if not db then return end

    if db.hideHealthText then
        fs:Hide()
        return
    end

    -- Snapshot health % when aura instance changes (new cast).
    -- Health values are secret in 12.0. Arithmetic on secrets errors, so we copy
    -- the already-rendered health text from Blizzard's PlayerFrame (SetText accepts secrets).
    local tracked = CA._auraTracking[auraId]
    if tracked then
        local iid = tracked.auraInstanceID
        if iid and iid ~= state._healthPctInstance then
            state._healthPctInstance = iid
            -- Text: copy Blizzard's health % text (secret string, SetText accepts it)
            local healthText = getBlizzardHealthText()
            if healthText then
                pcall(fs.SetText, fs, healthText)
            end
            -- Color: secret RGB → SetTextColor (AllowedWhenTainted)
            applyHealthColorToFS(fs)
            state._healthPctSnapped = true
        end
    end

    -- Apply font styling and position (runs every call for settings changes)
    if state._healthPctSnapped then
        applyHealthTextFont(auraId, state)
        positionHealthText(auraId, state)
        fs:Show()
    end
end

local function AlterTimeOnAuraMissing(auraId, state)
    local fs = state._healthPctFS
    if fs then
        pcall(fs.SetText, fs, "")
        fs:Hide()
    end
    state._healthPctInstance = nil
    state._healthPctSnapped = nil
end

local function AlterTimeOnEditModeEnter(auraId, state)
    local fs = state._healthPctFS
    if not fs then return end
    local auraDef = CA._registry[auraId]
    local db = auraDef and CA._GetDB(auraDef)
    if not db or db.hideHealthText then
        fs:Hide()
        return
    end
    -- Copy Blizzard's health % text for preview (secret string, SetText accepts it)
    local healthText = getBlizzardHealthText()
    if healthText then
        pcall(fs.SetText, fs, healthText)
    end
    applyHealthColorToFS(fs)
    applyHealthTextFont(auraId, state)
    positionHealthText(auraId, state)
    fs:Show()
end

local function AlterTimeOnEditModeExit(auraId, state)
    local fs = state._healthPctFS
    if fs then
        pcall(fs.SetText, fs, "")
        fs:Hide()
    end
end

--------------------------------------------------------------------------------
-- Alter Time: Settings UI (additionalTabs callback)
--------------------------------------------------------------------------------

local function AlterTimeAdditionalTabs(tabs, buildContent, h, getSetting, componentId, builder)
    local Helpers = addon.UI.Settings.Helpers

    local OUTSIDE_ANCHOR_VALUES = { LEFT = "Left", RIGHT = "Right", ABOVE = "Above", BELOW = "Below" }
    local OUTSIDE_ANCHOR_ORDER = { "LEFT", "RIGHT", "ABOVE", "BELOW" }
    local INSIDE_ANCHOR_VALUES = {
        TOPLEFT = "Top-Left", TOP = "Top", TOPRIGHT = "Top-Right",
        LEFT = "Left", CENTER = "Center", RIGHT = "Right",
        BOTTOMLEFT = "Bottom-Left", BOTTOM = "Bottom", BOTTOMRIGHT = "Bottom-Right",
    }
    local INSIDE_ANCHOR_ORDER = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }

    table.insert(tabs, { key = "healthText", label = "Health Text" })
    buildContent.healthText = function(tabContent, tabBuilder)
        tabBuilder:AddToggle({
            label = "Hide Health Text",
            description = "Hide the health % snapshot text element.",
            get = function() return getSetting("hideHealthText") or false end,
            set = function(val) h.setAndApply("hideHealthText", val) builder:DeferredRefreshAll() end,
        })

        tabBuilder:AddFontSelector({
            label = "Font",
            get = function() return getSetting("healthTextFont") or "FRIZQT__" end,
            set = function(v) h.setAndApply("healthTextFont", v) builder:DeferredRefreshAll() end,
        })

        tabBuilder:AddSelector({
            label = "Font Style",
            values = Helpers.fontStyleValues,
            order = Helpers.fontStyleOrder,
            get = function() return getSetting("healthTextStyle") or "OUTLINE" end,
            set = function(v) h.setAndApply("healthTextStyle", v) builder:DeferredRefreshAll() end,
        })

        tabBuilder:AddSlider({
            label = "Font Size",
            min = 6, max = 48, step = 1,
            get = function() return getSetting("healthTextSize") or 16 end,
            set = function(v) h.setAndApply("healthTextSize", v) builder:DeferredRefreshAll() end,
            minLabel = "6pt", maxLabel = "48pt",
        })

        tabBuilder:AddDescription(
            "Color is automatic (green\226\134\146yellow\226\134\146red based on health %).",
            { color = {0.6, 0.6, 0.6}, fontSize = 12, topPadding = 4 }
        )

        -- Position DualSelector
        local currentPos = getSetting("healthTextPosition") or "outside"
        local initialBValues = currentPos == "outside" and OUTSIDE_ANCHOR_VALUES or INSIDE_ANCHOR_VALUES
        local initialBOrder = currentPos == "outside" and OUTSIDE_ANCHOR_ORDER or INSIDE_ANCHOR_ORDER

        tabBuilder:AddDualSelector({
            label = "Position",
            key = "healthTextPositionDual",
            maxContainerWidth = 420,
            selectorA = {
                values = { inside = "Inside the Icon", outside = "Outside of Icon" },
                order = { "inside", "outside" },
                get = function() return getSetting("healthTextPosition") or "outside" end,
                set = function(v)
                    h.setAndApply("healthTextPosition", v)
                    local dualSelector = tabBuilder:GetControl("healthTextPositionDual")
                    if dualSelector then
                        if v == "outside" then
                            dualSelector:SetOptionsB(OUTSIDE_ANCHOR_VALUES, OUTSIDE_ANCHOR_ORDER)
                        else
                            dualSelector:SetOptionsB(INSIDE_ANCHOR_VALUES, INSIDE_ANCHOR_ORDER)
                        end
                    end
                    builder:DeferredRefreshAll()
                end,
            },
            selectorB = {
                values = initialBValues,
                order = initialBOrder,
                get = function()
                    local pos = getSetting("healthTextPosition") or "outside"
                    if pos == "outside" then
                        return getSetting("healthTextOuterAnchor") or "ABOVE"
                    else
                        return getSetting("healthTextInnerAnchor") or "CENTER"
                    end
                end,
                set = function(v)
                    local pos = getSetting("healthTextPosition") or "outside"
                    if pos == "outside" then
                        h.setAndApply("healthTextOuterAnchor", v)
                    else
                        h.setAndApply("healthTextInnerAnchor", v)
                    end
                    builder:DeferredRefreshAll()
                end,
            },
        })

        tabBuilder:AddDualSlider({
            label = "Offset",
            sliderA = {
                axisLabel = "X", min = -50, max = 50, step = 1,
                get = function() return getSetting("healthTextOffsetX") or 0 end,
                set = function(v) h.setAndApply("healthTextOffsetX", v) builder:DeferredRefreshAll() end,
                minLabel = "-50", maxLabel = "+50",
            },
            sliderB = {
                axisLabel = "Y", min = -50, max = 50, step = 1,
                get = function() return getSetting("healthTextOffsetY") or 0 end,
                set = function(v) h.setAndApply("healthTextOffsetY", v) builder:DeferredRefreshAll() end,
                minLabel = "-50", maxLabel = "+50",
            },
        })

        tabBuilder:Finalize()
    end
end

--------------------------------------------------------------------------------
-- Alter Time: Settings Defaults
--------------------------------------------------------------------------------

local alterTimeSettings = CA.DefaultSettings({
    textColor = { 0.85, 0.65, 0.13, 1.0 },
    barForegroundTint = { 0.85, 0.65, 0.13, 1.0 },
    -- Novel health text settings (injected via { type = "addon", default = ... })
    hideHealthText        = { type = "addon", default = false },
    healthTextFont        = { type = "addon", default = "FRIZQT__" },
    healthTextStyle       = { type = "addon", default = "OUTLINE" },
    healthTextSize        = { type = "addon", default = 16 },
    healthTextPosition    = { type = "addon", default = "outside" },
    healthTextInnerAnchor = { type = "addon", default = "CENTER" },
    healthTextOuterAnchor = { type = "addon", default = "ABOVE" },
    healthTextOffsetX     = { type = "addon", default = 0 },
    healthTextOffsetY     = { type = "addon", default = 0 },
})

--------------------------------------------------------------------------------
-- Aura Registrations
--------------------------------------------------------------------------------

CA.RegisterAuras("MAGE", {
    {
        id = "freezing",
        label = "Freezing",
        auraSpellId = 1221389,
        cdmSpellId = 1246769,  -- Shatter passive (CDM tracks Freezing stacks under this ID)
        cdmBorrow = true,
        unit = "target",
        filter = "HARMFUL|PLAYER",
        enableLabel = "Enable Freezing Stacks Tracker",
        enableDescription = "Show your target's Freezing stacks as a dedicated, customizable aura.",
        editModeName = "Freezing",
        defaultPosition = { point = "CENTER", x = 0, y = -200 },
        defaultBarColor = { 0.68, 0.85, 1.0, 1.0 },  -- frost blue
        elements = {
            { type = "text",    key = "stacks", source = "applications", baseSize = 24, justifyH = "RIGHT" },
            { type = "texture", key = "icon",   customPath = "Interface\\AddOns\\Scoot\\media\\classauras\\PixelSnowflake", defaultSize = { 32, 32 } },
            { type = "bar",     key = "stackBar", source = "applications", maxValue = 20, fillMode = "fill", defaultSize = { 120, 12 } },
        },
        settings = CA.DefaultSettings({
            textColor = { 0.68, 0.85, 1.0, 1.0 },
            barForegroundTint = { 0.68, 0.85, 1.0, 1.0 },
        }),
    },
    {
        id = "arcaneSalvo",
        label = "Arcane Salvo",
        auraSpellId = 1242974,
        cdmSpellId = 384452,
        cdmBorrow = true,
        unit = "player",
        filter = "HELPFUL|PLAYER",
        enableLabel = "Enable Arcane Salvo Stacks Tracker",
        enableDescription = "Show your Arcane Salvo stacks as a dedicated, customizable aura.",
        editModeName = "Arcane Salvo",
        defaultPosition = { point = "CENTER", x = 0, y = -200 },
        defaultBarColor = { 0.58, 0.38, 0.93, 1.0 },  -- arcane purple
        elements = {
            { type = "text",    key = "stacks", source = "applications", baseSize = 24, justifyH = "RIGHT" },
            { type = "texture", key = "icon",   customPath = "Interface\\AddOns\\Scoot\\media\\classauras\\PixelArcane", defaultSize = { 32, 32 } },
            { type = "bar",     key = "stackBar", source = "applications", maxValue = 25, fillMode = "fill", defaultSize = { 120, 12 } },
        },
        settings = CA.DefaultSettings({
            textColor = { 0.58, 0.38, 0.93, 1.0 },
            barForegroundTint = { 0.58, 0.38, 0.93, 1.0 },
        }),
    },
    {
        id = "alterTime",
        label = "Alter Time",
        auraSpellId = 342246,   -- Alter Time buff on player
        cdmSpellId = 342245,    -- Base spell (CDM Tracked Buffs)
        cdmBorrow = true,
        unit = "player",
        filter = "HELPFUL|PLAYER",
        enableLabel = "Enable Alter Time Tracker",
        enableDescription = "Show your Alter Time buff duration and snapshotted health % as a dedicated, customizable aura.",
        editModeName = "Alter Time",
        defaultPosition = { point = "CENTER", x = 0, y = -240 },
        defaultBarColor = { 0.85, 0.65, 0.13, 1.0 },  -- golden amber
        elements = {
            { type = "text",    key = "duration",    source = "duration", baseSize = 24, justifyH = "RIGHT" },
            { type = "texture", key = "icon",        customPath = "Interface\\AddOns\\Scoot\\media\\classauras\\PixelHourglass", defaultSize = { 32, 32 } },
            { type = "bar",     key = "durationBar", source = "duration", fillMode = "deplete", defaultSize = { 120, 12 } },
        },
        onContainerCreated = AlterTimeOnContainerCreated,
        onAuraFound = AlterTimeOnAuraFound,
        onAuraMissing = AlterTimeOnAuraMissing,
        onEditModeEnter = AlterTimeOnEditModeEnter,
        onEditModeExit = AlterTimeOnEditModeExit,
        additionalTabs = AlterTimeAdditionalTabs,
        settings = alterTimeSettings,
    },
})
