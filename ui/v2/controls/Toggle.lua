-- Toggle.lua - Full-row toggle control with ON/OFF state indicator
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Controls = addon.UI.Controls or {}
local Controls = addon.UI.Controls
local Theme -- Will be set after Theme.lua loads

-- Lazy Theme accessor
local function GetTheme()
    if not Theme then
        Theme = addon.UI.Theme
    end
    return Theme
end

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local BORDER_WIDTH = 2
local TOGGLE_HEIGHT = 36
local TOGGLE_HEIGHT_WITH_DESC = 60  -- Increased for better description spacing
local TOGGLE_BORDER = 1
local TOGGLE_INDICATOR_WIDTH = 60
local TOGGLE_INDICATOR_HEIGHT = 22
local TOGGLE_PADDING = 12

--------------------------------------------------------------------------------
-- Toggle: Full-row toggle control with ON/OFF state indicator
--------------------------------------------------------------------------------
-- Creates a clickable row with:
--   - Label text on the left (accent when ON, dim when OFF)
--   - State indicator on the right: [  ON  ] or [ OFF  ]
--   - Hover effect on the entire row
--   - Optional description text below the label
--
-- Options table:
--   label       : Setting name/label (string)
--   description : Optional description text below label
--   get         : Function that returns current boolean state
--   set         : Function(newValue) called when toggled
--   parent      : Parent frame (required)
--   width       : Control width (optional, defaults to parent width)
--   name        : Global frame name (optional)
--------------------------------------------------------------------------------

function Controls:CreateToggle(options)
    local theme = GetTheme()
    if not options or not options.parent then
        return nil
    end

    local parent = options.parent
    local label = options.label or "Toggle"
    local description = options.description
    local getValue = options.get or function() return false end
    local setValue = options.set or function() end
    local name = options.name

    local hasDesc = description and description ~= ""
    local height = hasDesc and TOGGLE_HEIGHT_WITH_DESC or TOGGLE_HEIGHT

    -- Create the row frame
    local row = CreateFrame("Button", name, parent)
    row:SetHeight(height)
    row:EnableMouse(true)
    row:RegisterForClicks("AnyUp")

    -- Get theme colors
    local ar, ag, ab = theme:GetAccentColor()
    local dimR, dimG, dimB
    if options.useLightDim then
        dimR, dimG, dimB = theme:GetDimTextLightColor()
    else
        dimR, dimG, dimB = theme:GetDimTextColor()
    end
    local bgR, bgG, bgB, bgA = theme:GetBackgroundSolidColor()

    -- Row hover background (hidden by default)
    local hoverBg = row:CreateTexture(nil, "BACKGROUND", nil, -8)
    hoverBg:SetAllPoints()
    hoverBg:SetColorTexture(ar, ag, ab, 0.08)
    hoverBg:Hide()
    row._hoverBg = hoverBg

    -- Row border (subtle line below only)
    local rowBorder = {}
    local borderAlpha = 0.2

    local bottom = row:CreateTexture(nil, "BORDER", nil, -1)
    bottom:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    bottom:SetHeight(TOGGLE_BORDER)
    bottom:SetColorTexture(ar, ag, ab, borderAlpha)
    rowBorder.BOTTOM = bottom

    row._rowBorder = rowBorder

    -- Label text (left side)
    local labelFS = row:CreateFontString(nil, "OVERLAY")
    local labelFont = theme:GetFont("LABEL")
    labelFS:SetFont(labelFont, 13, "")
    labelFS:SetPoint("LEFT", row, "LEFT", TOGGLE_PADDING, hasDesc and 6 or 0)
    labelFS:SetText(label)
    labelFS:SetTextColor(ar, ag, ab, 1)
    row._label = labelFS

    -- Description text (below label, if provided)
    if hasDesc then
        local descFS = row:CreateFontString(nil, "OVERLAY")
        local descFont = theme:GetFont("VALUE")
        descFS:SetFont(descFont, 11, "")
        descFS:SetPoint("TOPLEFT", labelFS, "BOTTOMLEFT", 0, -2)
        descFS:SetPoint("RIGHT", row, "RIGHT", -(TOGGLE_INDICATOR_WIDTH + TOGGLE_PADDING * 2), 0)
        descFS:SetText(description)
        descFS:SetTextColor(dimR, dimG, dimB, 1)
        descFS:SetJustifyH("LEFT")
        descFS:SetWordWrap(true)
        row._description = descFS
    end

    -- State indicator container (right side)
    local indicator = CreateFrame("Frame", nil, row)
    indicator:SetSize(TOGGLE_INDICATOR_WIDTH, TOGGLE_INDICATOR_HEIGHT)
    indicator:SetPoint("RIGHT", row, "RIGHT", -TOGGLE_PADDING, 0)

    -- Indicator border (edges inset to avoid corner overlap)
    local indBorder = {}

    -- Top edge spans full width
    local indTop = indicator:CreateTexture(nil, "BORDER", nil, -1)
    indTop:SetPoint("TOPLEFT", indicator, "TOPLEFT", 0, 0)
    indTop:SetPoint("TOPRIGHT", indicator, "TOPRIGHT", 0, 0)
    indTop:SetHeight(BORDER_WIDTH)
    indTop:SetColorTexture(ar, ag, ab, 1)
    indBorder.TOP = indTop

    -- Bottom edge spans full width
    local indBottom = indicator:CreateTexture(nil, "BORDER", nil, -1)
    indBottom:SetPoint("BOTTOMLEFT", indicator, "BOTTOMLEFT", 0, 0)
    indBottom:SetPoint("BOTTOMRIGHT", indicator, "BOTTOMRIGHT", 0, 0)
    indBottom:SetHeight(BORDER_WIDTH)
    indBottom:SetColorTexture(ar, ag, ab, 1)
    indBorder.BOTTOM = indBottom

    -- Left edge inset to avoid overlapping top/bottom corners
    local indLeft = indicator:CreateTexture(nil, "BORDER", nil, -1)
    indLeft:SetPoint("TOPLEFT", indicator, "TOPLEFT", 0, -BORDER_WIDTH)
    indLeft:SetPoint("BOTTOMLEFT", indicator, "BOTTOMLEFT", 0, BORDER_WIDTH)
    indLeft:SetWidth(BORDER_WIDTH)
    indLeft:SetColorTexture(ar, ag, ab, 1)
    indBorder.LEFT = indLeft

    -- Right edge inset to avoid overlapping top/bottom corners
    local indRight = indicator:CreateTexture(nil, "BORDER", nil, -1)
    indRight:SetPoint("TOPRIGHT", indicator, "TOPRIGHT", 0, -BORDER_WIDTH)
    indRight:SetPoint("BOTTOMRIGHT", indicator, "BOTTOMRIGHT", 0, BORDER_WIDTH)
    indRight:SetWidth(BORDER_WIDTH)
    indRight:SetColorTexture(ar, ag, ab, 1)
    indBorder.RIGHT = indRight

    indicator._border = indBorder

    -- Indicator background (shown when ON)
    local indBg = indicator:CreateTexture(nil, "BACKGROUND", nil, -7)
    indBg:SetPoint("TOPLEFT", BORDER_WIDTH, -BORDER_WIDTH)
    indBg:SetPoint("BOTTOMRIGHT", -BORDER_WIDTH, BORDER_WIDTH)
    indBg:SetColorTexture(ar, ag, ab, 1)
    indBg:Hide()
    indicator._bg = indBg

    -- Indicator text
    local indText = indicator:CreateFontString(nil, "OVERLAY")
    local btnFont = theme:GetFont("BUTTON")
    indText:SetFont(btnFont, 11, "")
    indText:SetPoint("CENTER", indicator, "CENTER", 0, 0)
    indText:SetText("OFF")
    indText:SetTextColor(dimR, dimG, dimB, 1)
    indicator._text = indText

    row._indicator = indicator

    -- State tracking
    row._value = false

    -- Update visual state
    local function UpdateVisual()
        local isOn = row._value
        local r, g, b = theme:GetAccentColor()
        local dR, dG, dB = theme:GetDimTextColor()

        -- Label always uses accent color for consistency
        labelFS:SetTextColor(r, g, b, 1)

        if isOn then
            -- ON state: lit indicator
            indicator._bg:Show()
            indicator._text:SetText("ON")
            indicator._text:SetTextColor(0, 0, 0, 1)  -- Dark text on accent bg
            -- Bright border on indicator
            for _, tex in pairs(indicator._border) do
                tex:SetColorTexture(r, g, b, 1)
            end
        else
            -- OFF state: dim indicator
            indicator._bg:Hide()
            indicator._text:SetText("OFF")
            indicator._text:SetTextColor(dR, dG, dB, 1)
            -- Dimmer border on indicator
            for _, tex in pairs(indicator._border) do
                tex:SetColorTexture(r, g, b, 0.4)
            end
        end
    end
    row._updateVisual = UpdateVisual

    -- Initialize from getter
    row._value = getValue() or false
    UpdateVisual()

    -- Hover handlers
    row:SetScript("OnEnter", function(self)
        self._hoverBg:Show()
    end)

    row:SetScript("OnLeave", function(self)
        self._hoverBg:Hide()
    end)

    -- Click to toggle
    row:SetScript("OnClick", function(self, mouseButton)
        self._value = not self._value
        setValue(self._value)
        UpdateVisual()
        PlaySound(self._value and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    end)

    -- Generate unique subscription key
    local subscribeKey = "Toggle_" .. (name or tostring(row))
    row._subscribeKey = subscribeKey

    -- Subscribe to theme updates
    theme:Subscribe(subscribeKey, function(r, g, b)
        -- Update hover bg color
        if row._hoverBg then
            row._hoverBg:SetColorTexture(r, g, b, 0.08)
        end
        -- Update row borders
        if row._rowBorder then
            for _, tex in pairs(row._rowBorder) do
                tex:SetColorTexture(r, g, b, 0.2)
            end
        end
        -- Re-run visual update to apply new accent color
        UpdateVisual()
    end)

    -- Public methods
    function row:SetValue(newValue)
        self._value = newValue or false
        self._updateVisual()
    end

    function row:GetValue()
        return self._value
    end

    function row:Refresh()
        self._value = getValue() or false
        self._updateVisual()
    end

    -- Dynamic label update (for orientation-dependent labels)
    function row:SetLabel(newLabel)
        if self._label then
            self._label:SetText(newLabel)
        end
    end

    function row:Cleanup()
        if self._subscribeKey then
            theme:Unsubscribe(self._subscribeKey)
        end
    end

    return row
end
