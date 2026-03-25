-- AuraTrackingRenderer.lua - Settings page for aura tracking on group frames
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.AuraTracking = {}

local AuraTrackingUI = addon.UI.Settings.AuraTracking
local SettingsBuilder = addon.UI.SettingsBuilder
local GF = addon.UI.GroupFrames

--------------------------------------------------------------------------------
-- Runtime State
--------------------------------------------------------------------------------

AuraTrackingUI._selectedClass = nil
AuraTrackingUI._selectedSpellId = nil

--------------------------------------------------------------------------------
-- Anchor Option Tables (for Position DualSelector)
--------------------------------------------------------------------------------

local INSIDE_VALUES = {
    TOPLEFT = "Top-Left", TOP = "Top", TOPRIGHT = "Top-Right",
    LEFT = "Left", CENTER = "Center", RIGHT = "Right",
    BOTTOMLEFT = "Bottom-Left", BOTTOM = "Bottom", BOTTOMRIGHT = "Bottom-Right",
}
local INSIDE_ORDER = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }

local OUTSIDE_VALUES = {
    TOPLEFT = "Top-Left", TOP = "Top", TOPRIGHT = "Top-Right",
    RIGHT = "Right", BOTTOMRIGHT = "Bottom-Right",
    BOTTOM = "Bottom", BOTTOMLEFT = "Bottom-Left", LEFT = "Left",
}
local OUTSIDE_ORDER = { "TOPLEFT", "TOP", "TOPRIGHT", "RIGHT", "BOTTOMRIGHT", "BOTTOM", "BOTTOMLEFT", "LEFT" }

--------------------------------------------------------------------------------
-- DB Helpers
--------------------------------------------------------------------------------

local function ensureDB()
    if not GF or not GF.ensureAuraTrackingDB then
        local db = addon.db and addon.db.profile
        if not db then return nil end
        db.groupFrames = db.groupFrames or {}
        db.groupFrames.auraTracking = db.groupFrames.auraTracking or {}
        db.groupFrames.auraTracking.spells = db.groupFrames.auraTracking.spells or {}
        return db.groupFrames.auraTracking
    end
    return GF.ensureAuraTrackingDB()
end

local SPELL_DEFAULTS = addon.AuraTracking and addon.AuraTracking.SPELL_DEFAULTS or {
    enabled = false,
    iconStyle = "spell",
    iconColor = "original",
    iconCustomColor = { 1, 1, 1, 1 },
    iconScale = 100,
    position = "inside",
    anchor = "TOPRIGHT",
    offsetX = 0,
    offsetY = 0,
}

local function ensureSpellConfig(spellId)
    local ha = ensureDB()
    if not ha then return SPELL_DEFAULTS end
    if not ha.spells[spellId] then
        ha.spells[spellId] = {}
    end
    return setmetatable(ha.spells[spellId], { __index = SPELL_DEFAULTS })
end

local function getSetting(spellId, key)
    local config = ensureSpellConfig(spellId)
    return config[key]
end

local function setSetting(spellId, key, value)
    local config = ensureSpellConfig(spellId)
    config[key] = value
    -- Notify core to refresh
    if addon.AuraTracking and addon.AuraTracking.OnConfigChanged then
        addon.AuraTracking.OnConfigChanged()
    end
end

--------------------------------------------------------------------------------
-- Icon Style Row (Custom Control)
--------------------------------------------------------------------------------
-- A row that shows the current icon preview and opens the AuraIconPicker.
--------------------------------------------------------------------------------

local function CreateIconStyleRow(parent, spellId, builder)
    local theme = addon.UI.Theme
    local accentR, accentG, accentB = 0.20, 0.90, 0.30
    if theme and theme.GetAccentColor then
        accentR, accentG, accentB = theme:GetAccentColor()
    end
    local labelFont = (theme and theme.GetFont and theme:GetFont("LABEL")) or "Fonts\\FRIZQT__.TTF"
    local valueFont = (theme and theme.GetFont and theme:GetFont("VALUE")) or "Fonts\\FRIZQT__.TTF"

    local ROW_HEIGHT = 36
    local ICON_SIZE = 28
    local BUTTON_WIDTH = 200

    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_HEIGHT)

    -- Hover background
    local hoverBg = row:CreateTexture(nil, "BACKGROUND", nil, -7)
    hoverBg:SetAllPoints()
    hoverBg:SetColorTexture(accentR, accentG, accentB, 0)
    row._hoverBg = hoverBg

    -- Bottom border
    local rowBorder = row:CreateTexture(nil, "BORDER", nil, -1)
    rowBorder:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    rowBorder:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    rowBorder:SetHeight(1)
    rowBorder:SetColorTexture(accentR, accentG, accentB, 0.2)
    row._rowBorder = rowBorder

    -- Label
    local label = row:CreateFontString(nil, "OVERLAY")
    label:SetFont(labelFont, 13, "")
    label:SetPoint("LEFT", row, "LEFT", 12, 0)
    label:SetText("Icon Style")
    label:SetTextColor(1, 1, 1, 0.9)
    row._label = label

    -- Selector button (right side)
    local selectorBtn = CreateFrame("Button", nil, row)
    selectorBtn:SetSize(BUTTON_WIDTH, ICON_SIZE + 4)
    selectorBtn:SetPoint("RIGHT", row, "RIGHT", -12, 0)
    selectorBtn:EnableMouse(true)
    selectorBtn:RegisterForClicks("AnyUp")

    -- Border
    local borderAlpha = 0.5
    local bTop = selectorBtn:CreateTexture(nil, "BORDER")
    bTop:SetPoint("TOPLEFT") bTop:SetPoint("TOPRIGHT") bTop:SetHeight(1)
    bTop:SetColorTexture(accentR, accentG, accentB, borderAlpha)
    local bBot = selectorBtn:CreateTexture(nil, "BORDER")
    bBot:SetPoint("BOTTOMLEFT") bBot:SetPoint("BOTTOMRIGHT") bBot:SetHeight(1)
    bBot:SetColorTexture(accentR, accentG, accentB, borderAlpha)
    local bLeft = selectorBtn:CreateTexture(nil, "BORDER")
    bLeft:SetPoint("TOPLEFT", 0, -1) bLeft:SetPoint("BOTTOMLEFT", 0, 1) bLeft:SetWidth(1)
    bLeft:SetColorTexture(accentR, accentG, accentB, borderAlpha)
    local bRight = selectorBtn:CreateTexture(nil, "BORDER")
    bRight:SetPoint("TOPRIGHT", 0, -1) bRight:SetPoint("BOTTOMRIGHT", 0, 1) bRight:SetWidth(1)
    bRight:SetColorTexture(accentR, accentG, accentB, borderAlpha)

    -- Background
    local selBg = selectorBtn:CreateTexture(nil, "BACKGROUND", nil, -6)
    selBg:SetAllPoints()
    selBg:SetColorTexture(0.06, 0.06, 0.08, 1)
    selectorBtn._bg = selBg

    -- Icon preview
    local iconPreview = selectorBtn:CreateTexture(nil, "ARTWORK")
    iconPreview:SetSize(ICON_SIZE, ICON_SIZE)
    iconPreview:SetPoint("LEFT", selectorBtn, "LEFT", 6, 0)
    selectorBtn._iconPreview = iconPreview

    -- Label text
    local selText = selectorBtn:CreateFontString(nil, "OVERLAY")
    selText:SetFont(valueFont, 11, "")
    selText:SetPoint("LEFT", iconPreview, "RIGHT", 8, 0)
    selText:SetPoint("RIGHT", selectorBtn, "RIGHT", -24, 0)
    selText:SetJustifyH("LEFT")
    selText:SetWordWrap(false)
    selectorBtn._text = selText

    -- Drop indicator
    local dropArrow = selectorBtn:CreateFontString(nil, "OVERLAY")
    dropArrow:SetFont(valueFont, 10, "")
    dropArrow:SetPoint("RIGHT", selectorBtn, "RIGHT", -8, 0)
    dropArrow:SetText("\226\150\188") -- ▼
    dropArrow:SetTextColor(accentR, accentG, accentB, 0.8)

    -- Update display
    local function UpdateDisplay()
        local style = getSetting(spellId, "iconStyle") or "spell"
        if style == "spell" then
            -- Show the actual spell icon
            local tex
            pcall(function()
                tex = C_Spell.GetSpellTexture(spellId)
            end)
            iconPreview:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
            iconPreview:SetDesaturated(false)
            iconPreview:SetVertexColor(1, 1, 1, 1)
            selText:SetText("Spell Icon")
        elseif style:sub(1, 5) == "file:" then
            -- File-based custom texture
            local path = style:sub(6)
            iconPreview:SetTexture(path)
            iconPreview:SetDesaturated(true)
            iconPreview:SetVertexColor(0.8, 0.8, 0.8, 1)
            -- Extract short name from path for display
            local shortName = path:match("([^\\]+)$") or style
            selText:SetText(shortName)
        else
            -- Atlas-based icon
            local ok = pcall(iconPreview.SetAtlas, iconPreview, style)
            if not ok then
                iconPreview:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            end
            iconPreview:SetDesaturated(true)
            iconPreview:SetVertexColor(0.8, 0.8, 0.8, 1)
            selText:SetText(style)
        end
    end

    UpdateDisplay()

    -- Hover
    selectorBtn:SetScript("OnEnter", function(self)
        self._bg:SetColorTexture(accentR, accentG, accentB, 0.15)
        row._hoverBg:SetColorTexture(accentR, accentG, accentB, 0.08)
    end)
    selectorBtn:SetScript("OnLeave", function(self)
        self._bg:SetColorTexture(0.06, 0.06, 0.08, 1)
        row._hoverBg:SetColorTexture(0, 0, 0, 0)
    end)

    -- Click opens picker
    selectorBtn:SetScript("OnClick", function(self)
        local currentStyle = getSetting(spellId, "iconStyle") or "spell"
        addon.ShowAuraIconPicker(self, currentStyle, function(selectedKey)
            setSetting(spellId, "iconStyle", selectedKey)
            UpdateDisplay()
        end)
    end)

    row._selectorBtn = selectorBtn
    row._updateDisplay = UpdateDisplay

    return row
end

--------------------------------------------------------------------------------
-- Spell Icon Grid
--------------------------------------------------------------------------------
-- Creates centered rows of spell icons for the selected class.
--------------------------------------------------------------------------------

local GRID_ICON_SIZE = 36
local GRID_ICON_SPACING = 6
local GRID_MAX_PER_ROW = 8
local GRID_BORDER_WIDTH = 2

local function CreateSpellGrid(parent, classToken, scrollContent, panel, builder)
    local HA = addon.AuraTracking
    if not HA or not HA.SPELL_REGISTRY then return nil, 0 end

    local spells = HA.SPELL_REGISTRY[classToken]
    if not spells or #spells == 0 then return nil, 0 end

    local theme = addon.UI.Theme
    local accentR, accentG, accentB = 0.20, 0.90, 0.30
    if theme and theme.GetAccentColor then
        accentR, accentG, accentB = theme:GetAccentColor()
    end

    local container = CreateFrame("Frame", nil, parent)
    local parentWidth = scrollContent:GetWidth() or 500
    local totalCols = math.min(#spells, GRID_MAX_PER_ROW)
    local gridWidth = totalCols * GRID_ICON_SIZE + (totalCols - 1) * GRID_ICON_SPACING
    local numRows = math.ceil(#spells / GRID_MAX_PER_ROW)
    local gridHeight = numRows * GRID_ICON_SIZE + (numRows - 1) * GRID_ICON_SPACING
    container:SetHeight(gridHeight + 16)

    local iconButtons = {}

    for i, entry in ipairs(spells) do
        local col = (i - 1) % GRID_MAX_PER_ROW
        local row = math.floor((i - 1) / GRID_MAX_PER_ROW)

        -- Calculate row width for centering
        local itemsInRow = math.min(#spells - row * GRID_MAX_PER_ROW, GRID_MAX_PER_ROW)
        local rowWidth = itemsInRow * GRID_ICON_SIZE + (itemsInRow - 1) * GRID_ICON_SPACING

        local btn = CreateFrame("Button", nil, container)
        btn:SetSize(GRID_ICON_SIZE, GRID_ICON_SIZE)
        btn:EnableMouse(true)
        btn:RegisterForClicks("AnyUp")

        -- Center each row
        local xOff = col * (GRID_ICON_SIZE + GRID_ICON_SPACING)
        local yOff = -(row * (GRID_ICON_SIZE + GRID_ICON_SPACING)) - 8

        btn:SetPoint("TOPLEFT", container, "TOP", -rowWidth / 2 + xOff, yOff)

        -- Icon texture
        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", GRID_BORDER_WIDTH, -GRID_BORDER_WIDTH)
        icon:SetPoint("BOTTOMRIGHT", -GRID_BORDER_WIDTH, GRID_BORDER_WIDTH)
        btn._icon = icon

        -- Set spell icon
        local spellTex
        pcall(function()
            spellTex = C_Spell.GetSpellTexture(entry.id)
        end)
        icon:SetTexture(spellTex or "Interface\\Icons\\INV_Misc_QuestionMark")

        -- Border frame (accent highlight)
        local borderBg = btn:CreateTexture(nil, "BACKGROUND", nil, -5)
        borderBg:SetAllPoints()
        borderBg:SetColorTexture(0, 0, 0, 0)
        btn._borderBg = borderBg

        -- Check if enabled (small dot indicator)
        local config = ensureSpellConfig(entry.id)
        if config.enabled then
            -- Small accent dot in corner
            local dot = btn:CreateTexture(nil, "OVERLAY")
            dot:SetSize(6, 6)
            dot:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -1, -1)
            dot:SetColorTexture(accentR, accentG, accentB, 1)
            btn._enabledDot = dot
        end

        -- Highlight if selected
        local isSelected = (AuraTrackingUI._selectedSpellId == entry.id)
        if isSelected then
            borderBg:SetColorTexture(accentR, accentG, accentB, 0.6)
        end

        btn._spellId = entry.id
        btn._spellName = entry.name

        -- Tooltip
        btn:SetScript("OnEnter", function(self)
            if AuraTrackingUI._selectedSpellId ~= self._spellId then
                self._borderBg:SetColorTexture(accentR, accentG, accentB, 0.3)
            end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetSpellByID(self._spellId)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function(self)
            if AuraTrackingUI._selectedSpellId ~= self._spellId then
                self._borderBg:SetColorTexture(0, 0, 0, 0)
            end
            GameTooltip:Hide()
        end)

        -- Click to select
        btn:SetScript("OnClick", function(self)
            AuraTrackingUI._selectedSpellId = self._spellId
            AuraTrackingUI.Render(panel, scrollContent)
        end)

        iconButtons[i] = btn
    end

    container._iconButtons = iconButtons
    return container, gridHeight + 16
end

--------------------------------------------------------------------------------
-- Main Render Function
--------------------------------------------------------------------------------

function AuraTrackingUI.Render(panel, scrollContent)
    panel:ClearContent()

    local HA = addon.AuraTracking
    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    builder:SetOnRefresh(function()
        AuraTrackingUI.Render(panel, scrollContent)
    end)

    -- Feature availability check
    if HA and HA.IsFeatureAvailable and not HA.IsFeatureAvailable() then
        builder:AddDescription("Aura Tracking is currently unavailable. Blizzard has re-protected these aura spells.", {
            color = { 1, 0.4, 0.4 },
        })
        builder:Finalize()
        return
    end

    -- Default to player's class on fresh session
    if not AuraTrackingUI._selectedClass then
        local _, classToken = UnitClass("player")
        -- Only use player class if it's in our registry
        if HA and HA.SPELL_REGISTRY and HA.SPELL_REGISTRY[classToken] then
            AuraTrackingUI._selectedClass = classToken
        else
            AuraTrackingUI._selectedClass = HA.CLASS_ORDER and HA.CLASS_ORDER[1] or "DRUID"
        end
    end

    --------------------------------------------------------------------------
    -- Aura Scale Slider (with explainer description)
    --------------------------------------------------------------------------

    builder:AddSlider({
        key = "auraScale",
        label = "Blizzard Aura Scale",
        description = "Add custom icons for tracking non-secret Auras like popular Healing Spells. "
            .. "Scoot cannot hide the icons, but it can shrink them so much they disappear "
            .. "- this will apply to ALL Blizzard Party/Raid Frame Buff Icons.",
        min = 1,
        max = 100,
        step = 1,
        minLabel = "Hidden",
        maxLabel = "100%",
        displaySuffix = "%",
        get = function()
            local at = ensureDB()
            return (at and at.auraScale) or 100
        end,
        set = function(v)
            local at = ensureDB()
            if at then at.auraScale = v end
            if addon.AuraTracking and addon.AuraTracking.RefreshBuffStripScaling then
                addon.AuraTracking.RefreshBuffStripScaling()
            end
        end,
    })

    -- Plain 1px divider line (no section header/chevron)
    do
        local theme = addon.UI.Theme
        local ar, ag, ab = 0.20, 0.90, 0.30
        if theme and theme.GetAccentColor then
            ar, ag, ab = theme:GetAccentColor()
        end
        local dividerSpacing = 8
        builder._currentY = builder._currentY - dividerSpacing
        local divider = CreateFrame("Frame", nil, scrollContent)
        divider:SetHeight(1)
        divider:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 12, builder._currentY)
        divider:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -12, builder._currentY)
        local divTex = divider:CreateTexture(nil, "BORDER")
        divTex:SetAllPoints()
        divTex:SetColorTexture(ar, ag, ab, 0.3)
        table.insert(builder._controls, divider)
        builder._currentY = builder._currentY - 1 - dividerSpacing
    end

    --------------------------------------------------------------------------
    -- Class Selector (centered, emphasized, 400px wide)
    --------------------------------------------------------------------------

    local selectorValues = {}
    local selectorOrder = {}
    if HA and HA.CLASS_ORDER and HA.CLASS_LABELS then
        for _, classToken in ipairs(HA.CLASS_ORDER) do
            selectorValues[classToken] = HA.CLASS_LABELS[classToken] or classToken
            table.insert(selectorOrder, classToken)
        end
    end

    builder:AddSelector({
        key = "classSelector",
        label = "",
        emphasized = true,
        values = selectorValues,
        order = selectorOrder,
        width = 400,
        get = function() return AuraTrackingUI._selectedClass end,
        set = function(v)
            AuraTrackingUI._selectedClass = v
            AuraTrackingUI._selectedSpellId = nil
            AuraTrackingUI.Render(panel, scrollContent)
        end,
    })

    -- Center the selector widget (same pattern as ActionBarRenderer)
    local selectorRow = builder._controls[#builder._controls]
    if selectorRow then
        local children = { selectorRow:GetChildren() }
        for _, child in ipairs(children) do
            if child._border then
                child:ClearAllPoints()
                child:SetPoint("CENTER", selectorRow, "CENTER", 0, 0)
                break
            end
        end
        if selectorRow._label then
            selectorRow._label:Hide()
        end
        if selectorRow._rowBorder then
            if selectorRow._rowBorder.LEFT then
                selectorRow._rowBorder.LEFT:Hide()
            end
            if selectorRow._rowBorder.BOTTOM then
                selectorRow._rowBorder.BOTTOM:Hide()
            end
        end
        if selectorRow._emphBg then
            selectorRow._emphBg:Hide()
        end
    end

    --------------------------------------------------------------------------
    -- Spell Icon Grid (directly below class selector, no divider)
    --------------------------------------------------------------------------

    local gridContainer, gridHeight = CreateSpellGrid(
        scrollContent, AuraTrackingUI._selectedClass, scrollContent, panel, builder
    )
    if gridContainer then
        -- Position the grid manually in the builder flow
        gridContainer:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 0, builder._currentY)
        gridContainer:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", 0, builder._currentY)
        table.insert(builder._controls, gridContainer)
        builder._currentY = builder._currentY - gridHeight
    end

    --------------------------------------------------------------------------
    -- Per-Spell Config (shown when a spell is selected)
    --------------------------------------------------------------------------

    local selectedId = AuraTrackingUI._selectedSpellId
    if selectedId then
        local spellName = (HA and HA.SPELL_NAMES and HA.SPELL_NAMES[selectedId]) or ("Spell " .. selectedId)

        builder:AddSpacer(12)

        -- Separator
        builder:AddSection("Configuration: " .. spellName)

        -- Enable toggle (always visible)
        builder:AddToggle({
            key = "enableToggle",
            label = "Custom Aura Display for " .. spellName,
            description = "Hide the default buff icon and replace it with a custom styled icon on group frames.",
            emphasized = true,
            get = function() return getSetting(selectedId, "enabled") end,
            set = function(v)
                setSetting(selectedId, "enabled", v)
                AuraTrackingUI.Render(panel, scrollContent)
            end,
        })

        -- Icon Style row (custom control)
        local iconStyleRow = CreateIconStyleRow(scrollContent, selectedId, builder)
        if iconStyleRow then
            -- Add spacing
            if #builder._controls > 0 then
                builder._currentY = builder._currentY - 4
            end
            iconStyleRow:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 12, builder._currentY)
            iconStyleRow:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -12, builder._currentY)
            table.insert(builder._controls, iconStyleRow)
            builder._currentY = builder._currentY - iconStyleRow:GetHeight()

            -- Disabled state
            local isEnabled = getSetting(selectedId, "enabled")
            if not isEnabled then
                iconStyleRow:SetAlpha(0.4)
                iconStyleRow._selectorBtn:EnableMouse(false)
            end
        end

        -- Icon Color (SelectorColorPicker with Custom/Rainbow)
        local isEnabled = getSetting(selectedId, "enabled")

        builder:AddSelectorColorPicker({
            key = "iconColor",
            label = "Icon Color",
            values = { original = "Texture Original", custom = "Custom", rainbow = "Rainbow" },
            order = { "original", "custom", "rainbow" },
            customValue = "custom",
            hasAlpha = true,
            get = function() return getSetting(selectedId, "iconColor") or "original" end,
            set = function(v)
                setSetting(selectedId, "iconColor", v)
            end,
            getColor = function()
                local c = getSetting(selectedId, "iconCustomColor") or { 1, 1, 1, 1 }
                return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
            end,
            setColor = function(r, g, b, a)
                setSetting(selectedId, "iconCustomColor", { r, g, b, a })
            end,
            disabled = function() return not isEnabled end,
        })

        -- Icon Scale
        builder:AddSlider({
            key = "iconScale",
            label = "Icon Scale",
            min = 25,
            max = 300,
            step = 5,
            get = function() return getSetting(selectedId, "iconScale") or 100 end,
            set = function(v)
                setSetting(selectedId, "iconScale", v)
            end,
            displaySuffix = "%",
            disabled = function() return not isEnabled end,
        })

        -- Position (DualSelector: Inside/Outside + anchor points)
        local currentPos = getSetting(selectedId, "position") or "inside"
        local initialBValues = currentPos == "outside" and OUTSIDE_VALUES or INSIDE_VALUES
        local initialBOrder = currentPos == "outside" and OUTSIDE_ORDER or INSIDE_ORDER

        builder:AddDualSelector({
            label = "Position",
            key = "positionDual",
            maxContainerWidth = 420,
            selectorA = {
                values = { inside = "Inside Frame", outside = "Outside Frame" },
                order = { "inside", "outside" },
                get = function() return getSetting(selectedId, "position") or "inside" end,
                set = function(v)
                    setSetting(selectedId, "position", v)
                    local dualSelector = builder:GetControl("positionDual")
                    if dualSelector then
                        if v == "outside" then
                            dualSelector:SetOptionsB(OUTSIDE_VALUES, OUTSIDE_ORDER)
                        else
                            dualSelector:SetOptionsB(INSIDE_VALUES, INSIDE_ORDER)
                        end
                    end
                end,
            },
            selectorB = {
                values = initialBValues,
                order = initialBOrder,
                get = function()
                    return getSetting(selectedId, "anchor") or "TOPRIGHT"
                end,
                set = function(v)
                    setSetting(selectedId, "anchor", v)
                end,
            },
            disabled = function() return not isEnabled end,
        })

        -- Offset (DualSlider: X/Y)
        builder:AddDualSlider({
            label = "Offset",
            sliderA = {
                axisLabel = "X",
                min = -50,
                max = 50,
                step = 1,
                get = function() return getSetting(selectedId, "offsetX") or 0 end,
                set = function(v)
                    setSetting(selectedId, "offsetX", v)
                end,
            },
            sliderB = {
                axisLabel = "Y",
                min = -50,
                max = 50,
                step = 1,
                get = function() return getSetting(selectedId, "offsetY") or 0 end,
                set = function(v)
                    setSetting(selectedId, "offsetY", v)
                end,
            },
            disabled = function() return not isEnabled end,
        })
    end

    builder:Finalize()
end

--------------------------------------------------------------------------------
-- Register Renderer
--------------------------------------------------------------------------------

addon.UI.SettingsPanel:RegisterRenderer("gfAuraTracking", function(panel, scrollContent)
    -- Reset to player's class each time the page is navigated to
    AuraTrackingUI._selectedClass = nil
    AuraTrackingUI._selectedSpellId = nil
    AuraTrackingUI.Render(panel, scrollContent)
end)

return AuraTrackingUI
