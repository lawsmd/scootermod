-- StartHereRenderer.lua - Module toggles page ("Start Here")
-- Two-column layout with master/sub toggles for each module category.
-- Static RELOAD button below the scrollable area inverts when changes are pending.
local _, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}

local StartHere = {}
addon.UI.Settings.StartHere = StartHere

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local ROW_HEIGHT = 36
local INDICATOR_WIDTH = 60
local INDICATOR_HEIGHT = 22
local INDICATOR_BORDER = 2
local ROW_PADDING = 12
local SUB_INDENT = 20
local COLUMN_GAP = 16
local RELOAD_AREA_HEIGHT = 80

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function deepCopy(t)
    if type(t) ~= "table" then return t end
    local copy = {}
    for k, v in pairs(t) do copy[k] = deepCopy(v) end
    return copy
end

--------------------------------------------------------------------------------
-- Page State (lives for the duration of a single Start Here visit)
--------------------------------------------------------------------------------

local pageState = {
    expandedCategory = nil,
    dirty = false,
    rows = {},
    col1 = nil,
    col2 = nil,
    snapshot = nil,
}

--------------------------------------------------------------------------------
-- ON/OFF Indicator (right-side toggle button)
--------------------------------------------------------------------------------

local function CreateIndicator(parent, theme)
    local ar, ag, ab = theme:GetAccentColor()
    local dimR, dimG, dimB = theme:GetDimTextColor()

    local indicator = CreateFrame("Button", nil, parent)
    indicator:SetSize(INDICATOR_WIDTH, INDICATOR_HEIGHT)
    indicator:RegisterForClicks("AnyUp")

    -- Border textures (same layout as Toggle.lua)
    local border = {}

    local top = indicator:CreateTexture(nil, "BORDER", nil, -1)
    top:SetPoint("TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", 0, 0)
    top:SetHeight(INDICATOR_BORDER)
    top:SetColorTexture(ar, ag, ab, 1)
    border.TOP = top

    local bottom = indicator:CreateTexture(nil, "BORDER", nil, -1)
    bottom:SetPoint("BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", 0, 0)
    bottom:SetHeight(INDICATOR_BORDER)
    bottom:SetColorTexture(ar, ag, ab, 1)
    border.BOTTOM = bottom

    local left = indicator:CreateTexture(nil, "BORDER", nil, -1)
    left:SetPoint("TOPLEFT", 0, -INDICATOR_BORDER)
    left:SetPoint("BOTTOMLEFT", 0, INDICATOR_BORDER)
    left:SetWidth(INDICATOR_BORDER)
    left:SetColorTexture(ar, ag, ab, 1)
    border.LEFT = left

    local right = indicator:CreateTexture(nil, "BORDER", nil, -1)
    right:SetPoint("TOPRIGHT", 0, -INDICATOR_BORDER)
    right:SetPoint("BOTTOMRIGHT", 0, INDICATOR_BORDER)
    right:SetWidth(INDICATOR_BORDER)
    right:SetColorTexture(ar, ag, ab, 1)
    border.RIGHT = right

    indicator._border = border

    -- Fill background (visible when ON)
    local fill = indicator:CreateTexture(nil, "BACKGROUND", nil, -7)
    fill:SetPoint("TOPLEFT", INDICATOR_BORDER, -INDICATOR_BORDER)
    fill:SetPoint("BOTTOMRIGHT", -INDICATOR_BORDER, INDICATOR_BORDER)
    fill:SetColorTexture(ar, ag, ab, 1)
    fill:Hide()
    indicator._fill = fill

    -- ON/OFF text
    local text = indicator:CreateFontString(nil, "OVERLAY")
    text:SetFont(theme:GetFont("BUTTON"), 11, "")
    text:SetPoint("CENTER", 0, 0)
    text:SetText("OFF")
    text:SetTextColor(dimR, dimG, dimB, 1)
    indicator._text = text

    function indicator:UpdateState(isOn, isDisabled)
        local r, g, b = theme:GetAccentColor()
        local dR, dG, dB = theme:GetDimTextColor()
        if isDisabled then
            local a = 0.35
            self._fill:Hide()
            self._text:SetText(isOn and "ON" or "OFF")
            self._text:SetTextColor(dR, dG, dB, a)
            for _, tex in pairs(self._border) do tex:SetColorTexture(dR, dG, dB, a * 0.5) end
        elseif isOn then
            self._fill:Show()
            self._text:SetText("ON")
            self._text:SetTextColor(0, 0, 0, 1)
            for _, tex in pairs(self._border) do tex:SetColorTexture(r, g, b, 1) end
        else
            self._fill:Hide()
            self._text:SetText("OFF")
            self._text:SetTextColor(dR, dG, dB, 1)
            for _, tex in pairs(self._border) do tex:SetColorTexture(r, g, b, 0.4) end
        end
    end

    return indicator
end

--------------------------------------------------------------------------------
-- Module Row (label left, indicator right, optional expand chevron)
--------------------------------------------------------------------------------

local function CreateModuleRow(parent, options)
    local theme = options.theme
    local ar, ag, ab = theme:GetAccentColor()
    local dimR, dimG, dimB = theme:GetDimTextColor()
    local indent = options.indent or 0

    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_HEIGHT)

    -- Bottom border line
    local borderLine = row:CreateTexture(nil, "BORDER", nil, -1)
    borderLine:SetPoint("BOTTOMLEFT", indent, 0)
    borderLine:SetPoint("BOTTOMRIGHT", 0, 0)
    borderLine:SetHeight(1)
    borderLine:SetColorTexture(ar, ag, ab, 0.2)

    -- Hover background
    local hoverBg = row:CreateTexture(nil, "BACKGROUND", nil, -8)
    hoverBg:SetPoint("TOPLEFT", indent, 0)
    hoverBg:SetPoint("BOTTOMRIGHT", 0, 0)
    hoverBg:SetColorTexture(ar, ag, ab, 0.08)
    hoverBg:Hide()

    -- Label button (covers left portion of row)
    local labelBtn = CreateFrame("Button", nil, row)
    labelBtn:SetPoint("TOPLEFT", row, "TOPLEFT", indent, 0)
    labelBtn:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", indent, 0)
    labelBtn:SetPoint("RIGHT", row, "RIGHT", -(INDICATOR_WIDTH + ROW_PADDING * 2), 0)
    labelBtn:RegisterForClicks("AnyUp")

    -- Label text (with optional chevron for expandable categories)
    local labelText = options.label or ""
    if options.isExpandable then
        -- ▼ (expanded) or ▶ (collapsed) appended to label
        labelText = labelText .. (options.isExpanded and "  \226\150\188" or "  \226\150\182")
    end

    local labelFS = labelBtn:CreateFontString(nil, "OVERLAY")
    labelFS:SetFont(theme:GetFont("LABEL"), 13, "")
    labelFS:SetPoint("LEFT", ROW_PADDING, 0)
    labelFS:SetText(labelText)
    if options.isDisabled then
        labelFS:SetTextColor(dimR, dimG, dimB, 0.35)
    else
        labelFS:SetTextColor(ar, ag, ab, 1)
    end

    -- ON/OFF indicator (right side)
    local indicator = CreateIndicator(row, theme)
    indicator:SetPoint("RIGHT", row, "RIGHT", -ROW_PADDING, 0)
    indicator:UpdateState(options.isOn, options.isDisabled)

    -- Click: indicator always toggles on/off
    indicator:SetScript("OnClick", function()
        if not options.isDisabled and options.onToggle then options.onToggle() end
    end)

    -- Click: label expands (if expandable) or toggles (if not)
    labelBtn:SetScript("OnClick", function()
        if options.isDisabled then return end
        if options.isExpandable and options.onExpand then
            options.onExpand()
        elseif options.onToggle then
            options.onToggle()
        end
    end)

    -- Hover handlers (shared across label and indicator)
    labelBtn:SetScript("OnEnter", function() hoverBg:Show() end)
    labelBtn:SetScript("OnLeave", function() hoverBg:Hide() end)
    indicator:SetScript("OnEnter", function() hoverBg:Show() end)
    indicator:SetScript("OnLeave", function() hoverBg:Hide() end)

    return row
end

--------------------------------------------------------------------------------
-- Column Builder
--------------------------------------------------------------------------------

local function BuildColumnContent(column, categories, startIdx, endIdx, state, theme, rebuild)
    local yOffset = 0
    for i = startIdx, endIdx do
        local catId = categories[i]
        local catDef = addon.MODULE_CATEGORIES[catId]
        if not catDef then break end

        local isOn = addon:IsModuleEnabled(catId)
        local hasSubToggles = catDef.subToggles and #catDef.subToggles > 0
        local isExpanded = state.expandedCategory == catId

        -- Master category row
        local masterRow = CreateModuleRow(column, {
            label = catDef.label,
            isOn = isOn,
            isExpandable = hasSubToggles,
            isExpanded = isExpanded,
            theme = theme,
            onToggle = function()
                addon:SetModuleEnabled(catId, nil, not addon:IsModuleEnabled(catId))
                state.dirty = true
                if state.registerGuard then state.registerGuard() end
                rebuild()
            end,
            onExpand = function()
                if state.expandedCategory == catId then
                    state.expandedCategory = nil
                else
                    state.expandedCategory = catId
                end
                rebuild()
            end,
        })
        masterRow:SetPoint("TOPLEFT", column, "TOPLEFT", 0, -yOffset)
        masterRow:SetPoint("TOPRIGHT", column, "TOPRIGHT", 0, -yOffset)
        table.insert(state.rows, masterRow)
        yOffset = yOffset + ROW_HEIGHT

        -- Sub-toggle rows (when expanded)
        if isExpanded and hasSubToggles then
            for _, sub in ipairs(catDef.subToggles) do
                local subIsOn = addon:IsModuleEnabled(catId, sub.id)
                local subRow = CreateModuleRow(column, {
                    label = sub.label,
                    isOn = subIsOn,
                    indent = SUB_INDENT,
                    isDisabled = not isOn,
                    theme = theme,
                    onToggle = function()
                        if not addon:IsModuleEnabled(catId) then return end
                        addon:SetModuleEnabled(catId, sub.id, not addon:IsModuleEnabled(catId, sub.id))
                        state.dirty = true
                        if state.registerGuard then state.registerGuard() end
                        rebuild()
                    end,
                })
                subRow:SetPoint("TOPLEFT", column, "TOPLEFT", 0, -yOffset)
                subRow:SetPoint("TOPRIGHT", column, "TOPRIGHT", 0, -yOffset)
                table.insert(state.rows, subRow)
                yOffset = yOffset + ROW_HEIGHT
            end
        end
    end
    column:SetHeight(math.max(yOffset, 1))
end

--------------------------------------------------------------------------------
-- Reload Area (static, below scroll frame)
--------------------------------------------------------------------------------

local function EnsureReloadArea(panel, contentPane)
    if panel._startHereReloadArea then
        panel._startHereReloadArea:Show()
        return panel._startHereReloadArea
    end

    local theme = addon.UI.Theme
    local Controls = addon.UI.Controls
    local ar, ag, ab = theme:GetAccentColor()
    local dimR, dimG, dimB = theme:GetDimTextColor()

    local area = CreateFrame("Frame", nil, contentPane)
    area:SetHeight(RELOAD_AREA_HEIGHT)
    area:SetPoint("BOTTOMLEFT", contentPane, "BOTTOMLEFT", 8, 8)
    area:SetPoint("BOTTOMRIGHT", contentPane, "BOTTOMRIGHT", -8, 8)

    -- Top separator
    local sep = area:CreateTexture(nil, "BORDER", nil, -1)
    sep:SetPoint("TOPLEFT", 0, 0)
    sep:SetPoint("TOPRIGHT", 0, 0)
    sep:SetHeight(1)
    sep:SetColorTexture(ar, ag, ab, 0.3)

    -- RELOAD button (centered)
    local btn = Controls:CreateButton({
        parent = area,
        text = "RELOAD",
        width = 160,
        height = 34,
        fontSize = 14,
    })
    btn:SetPoint("TOP", area, "TOP", 0, -16)
    btn:SetScript("OnClick", function()
        if ReloadUI then ReloadUI() end
    end)
    area._reloadBtn = btn

    -- Explainer text
    local explainer = area:CreateFontString(nil, "OVERLAY")
    explainer:SetFont(theme:GetFont("VALUE"), 11, "")
    explainer:SetPoint("TOP", btn, "BOTTOM", 0, -9)
    explainer:SetText("To toggle the selected components")
    explainer:SetTextColor(dimR, dimG, dimB, 0.8)
    explainer:SetJustifyH("CENTER")

    panel._startHereReloadArea = area
    return area
end

local function UpdateReloadButtonVisual(area, isDirty)
    local btn = area and area._reloadBtn
    if not btn then return end
    local theme = addon.UI.Theme
    local ar, ag, ab = theme:GetAccentColor()

    if isDirty then
        -- Inverted: accent fill shown permanently, dark text
        btn._hoverFill:Show()
        btn._label:SetTextColor(0, 0, 0, 1)
        btn:SetScript("OnEnter", function() end)
        btn:SetScript("OnLeave", function() end)
    else
        -- Normal: dark background, accent text, standard hover
        btn._hoverFill:Hide()
        btn._label:SetTextColor(ar, ag, ab, 1)
        btn:SetScript("OnEnter", function(self)
            local r, g, b = theme:GetAccentColor()
            self._hoverFill:SetColorTexture(r, g, b, 1)
            self._hoverFill:Show()
            self._label:SetTextColor(0, 0, 0, 1)
        end)
        btn:SetScript("OnLeave", function(self)
            self._hoverFill:Hide()
            local r, g, b = theme:GetAccentColor()
            self._label:SetTextColor(r, g, b, 1)
        end)
    end
end

--------------------------------------------------------------------------------
-- Cleanup (called from ClearContent when navigating away)
--------------------------------------------------------------------------------

local function Cleanup(panel)
    -- Hide reload area
    if panel._startHereReloadArea then
        panel._startHereReloadArea:Hide()
    end

    -- Restore scroll frame, scrollbar anchors, header separator, and scroll top anchor
    local contentPane = panel.frame and panel.frame._contentPane
    if contentPane then
        local scrollFrame = contentPane._scrollFrame
        if scrollFrame then
            scrollFrame:SetPoint("BOTTOMRIGHT", contentPane, "BOTTOMRIGHT", -24, 8)
        end
        local scrollbar = contentPane._scrollbar
        if scrollbar then
            scrollbar:SetPoint("BOTTOMRIGHT", contentPane, "BOTTOMRIGHT", -8, 24)
        end
        if contentPane._headerSep then
            contentPane._headerSep:Show()
        end
        -- Restore scroll frame top anchor (overridden in Render to sit below title)
        if scrollFrame and contentPane._header then
            scrollFrame:SetPoint("TOPLEFT", contentPane._header, "BOTTOMLEFT", 8, -8)
        end
    end

    -- Destroy rows
    for _, row in ipairs(pageState.rows) do
        row:Hide()
        row:SetParent(nil)
    end
    if wipe then wipe(pageState.rows) else pageState.rows = {} end

    -- Destroy columns
    if pageState.col1 then pageState.col1:Hide(); pageState.col1:SetParent(nil); pageState.col1 = nil end
    if pageState.col2 then pageState.col2:Hide(); pageState.col2:SetParent(nil); pageState.col2 = nil end

    pageState.expandedCategory = nil
    pageState.dirty = false
    pageState.snapshot = nil
    pageState.registerGuard = nil
    panel._navigationGuard = nil
    panel._startHereCleanup = nil
end

--------------------------------------------------------------------------------
-- Render
--------------------------------------------------------------------------------

function StartHere.Render(panel, scrollContent)
    local contentPane = panel.frame._contentPane
    local scrollFrame = contentPane._scrollFrame
    local theme = addon.UI.Theme

    -- Reset state for this visit
    pageState.expandedCategory = nil
    pageState.dirty = false

    -- Snapshot moduleEnabled so "Discard Changes" can restore it
    pageState.snapshot = nil
    local me = addon.db and addon.db.profile and addon.db.profile.moduleEnabled
    if me then
        pageState.snapshot = deepCopy(me)
    end

    -- Register navigate-away dialog (idempotent)
    addon.Dialogs:Register("SCOOT_START_HERE_RELOAD", {
        text = "A Reload is required to apply your changes.",
        acceptText = "Reload",
        cancelText = "Discard Changes",
    })

    -- Override header title for this page
    if contentPane._headerTitle then
        contentPane._headerTitle:SetText("Modules")
    end

    -- Hide the default header separator — we render our own below the intro text
    if contentPane._headerSep then
        contentPane._headerSep:Hide()
    end

    -- Pull scroll frame up so intro text sits right below the header title
    if contentPane._headerTitle then
        scrollFrame:SetPoint("TOPLEFT", contentPane._headerTitle, "BOTTOMLEFT", 0, -4)
    end

    -- Create/show reload area
    local reloadArea = EnsureReloadArea(panel, contentPane)
    UpdateReloadButtonVisual(reloadArea, false)

    -- Shrink scroll frame to leave room for reload area
    -- Original: BOTTOMRIGHT offset = -(8+8+8), 8 → -24, 8
    scrollFrame:SetPoint("BOTTOMRIGHT", contentPane, "BOTTOMRIGHT", -24, 8 + RELOAD_AREA_HEIGHT)
    if contentPane._scrollbar then
        contentPane._scrollbar:SetPoint("BOTTOMRIGHT", contentPane, "BOTTOMRIGHT", -8, 24 + RELOAD_AREA_HEIGHT)
    end

    -- Register cleanup for when user navigates away
    panel._startHereCleanup = function() Cleanup(panel) end

    -- Navigation guard: called by toggle handlers when dirty to register a
    -- confirmation dialog before allowing navigation away from Start Here.
    pageState.registerGuard = function()
        if panel._navigationGuard then return end
        panel._navigationGuard = function(_, proceed)
            addon.Dialogs:Show("SCOOT_START_HERE_RELOAD", {
                cancelWidth = 140,
                onAccept = function()
                    ReloadUI()
                end,
                onCancel = function()
                    -- Restore original moduleEnabled state
                    local profile = addon.db and addon.db.profile
                    if profile and pageState.snapshot then
                        profile.moduleEnabled = deepCopy(pageState.snapshot)
                    end
                    panel._navigationGuard = nil
                    proceed()
                end,
            })
        end
    end

    -- Rebuild function (called on toggle/expand/collapse)
    local function rebuild()
        -- Destroy existing rows and columns
        for _, row in ipairs(pageState.rows) do
            row:Hide()
            row:SetParent(nil)
        end
        if wipe then wipe(pageState.rows) else pageState.rows = {} end
        if pageState.col1 then pageState.col1:Hide(); pageState.col1:SetParent(nil) end
        if pageState.col2 then pageState.col2:Hide(); pageState.col2:SetParent(nil) end

        -- Intro text (recreated each rebuild so it survives row cleanup)
        local introFS = scrollContent:CreateFontString(nil, "OVERLAY")
        introFS:SetFont(theme:GetFont("VALUE"), 12, "")
        introFS:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", ROW_PADDING, 0)
        local availWidth = (scrollContent:GetWidth() or 300) - ROW_PADDING * 2
        introFS:SetWidth(availWidth)
        introFS:SetWordWrap(true)
        introFS:SetJustifyH("LEFT")
        introFS:SetText("Enable or disable Scoot modules. Disabled modules do not load, freeing them for other addons.")
        introFS:SetTextColor(theme:GetDimTextColor())
        table.insert(pageState.rows, introFS)

        -- Separator below intro text (replaces the hidden header separator)
        local sep = scrollContent:CreateTexture(nil, "BORDER", nil, -1)
        sep:SetHeight(1)
        sep:SetPoint("TOPLEFT", introFS, "BOTTOMLEFT", -4, -6)
        sep:SetPoint("TOPRIGHT", introFS, "BOTTOMRIGHT", 4, -6)
        local ar, ag, ab = theme:GetAccentColor()
        sep:SetColorTexture(ar, ag, ab, 0.3)
        table.insert(pageState.rows, sep)

        -- Create columns (below separator)
        local col1 = CreateFrame("Frame", nil, scrollContent)
        col1:SetPoint("TOPLEFT", sep, "BOTTOMLEFT", -8, -4)
        col1:SetPoint("RIGHT", scrollContent, "CENTER", -(COLUMN_GAP / 2), 0)
        pageState.col1 = col1

        local col2 = CreateFrame("Frame", nil, scrollContent)
        col2:SetPoint("TOPLEFT", sep, "BOTTOM", COLUMN_GAP / 2, -4)
        col2:SetPoint("RIGHT", scrollContent, "RIGHT", 0, 0)
        pageState.col2 = col2

        local categories = addon.MODULE_CATEGORY_ORDER
        local half = math.ceil(#categories / 2)

        BuildColumnContent(col1, categories, 1, half, pageState, theme, rebuild)
        BuildColumnContent(col2, categories, half + 1, #categories, pageState, theme, rebuild)

        -- Set scroll content height: intro text + 6px gap + 1px sep + 4px gap + tallest column + padding
        local introUsed = (introFS:GetStringHeight() or 16) + 6 + 1 + 4
        scrollContent:SetHeight(introUsed + math.max(col1:GetHeight(), col2:GetHeight()) + 8)

        -- Update reload button visual
        UpdateReloadButtonVisual(reloadArea, pageState.dirty)

        -- Update scrollbar
        if contentPane._scrollbar and contentPane._scrollbar.Update then
            contentPane._scrollbar:Update()
        end
    end

    rebuild()
end

--------------------------------------------------------------------------------
-- Register
--------------------------------------------------------------------------------

addon.UI.SettingsPanel:RegisterRenderer("startHere", function(panel, scrollContent)
    StartHere.Render(panel, scrollContent)
end)
