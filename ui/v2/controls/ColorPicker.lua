-- ColorPicker.lua - Standalone color swatch button
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

local COLOR_SWATCH_WIDTH = 54
local COLOR_SWATCH_HEIGHT = 22
local COLOR_SWATCH_BORDER = 2
local COLOR_ROW_HEIGHT = 36
local COLOR_ROW_HEIGHT_WITH_DESC = 60
local COLOR_PADDING = 12

--------------------------------------------------------------------------------
-- ColorPicker: Standalone color swatch button
--------------------------------------------------------------------------------

function Controls:CreateColorPicker(options)
    local theme = GetTheme()
    if not options or not options.parent then
        return nil
    end

    local parent = options.parent
    local label = options.label or "Color"
    local description = options.description
    local getColor = options.get or function() return 1, 1, 1, 1 end
    local setColor = options.set or function() end
    local hasAlpha = options.hasAlpha or false
    local swatchWidth = options.swatchWidth or COLOR_SWATCH_WIDTH
    local swatchHeight = options.swatchHeight or COLOR_SWATCH_HEIGHT
    local name = options.name

    local hasDesc = description and description ~= ""
    local height = hasDesc and COLOR_ROW_HEIGHT_WITH_DESC or COLOR_ROW_HEIGHT

    -- Get theme colors
    local ar, ag, ab = theme:GetAccentColor()
    local dimR, dimG, dimB
    if options.useLightDim then
        dimR, dimG, dimB = theme:GetDimTextLightColor()
    else
        dimR, dimG, dimB = theme:GetDimTextColor()
    end
    local bgR, bgG, bgB, bgA = theme:GetBackgroundSolidColor()

    -- Main row frame
    local row = CreateFrame("Frame", name, parent)
    row:SetHeight(height)

    -- Row hover background
    local hoverBg = row:CreateTexture(nil, "BACKGROUND", nil, -8)
    hoverBg:SetAllPoints()
    hoverBg:SetColorTexture(ar, ag, ab, 0.08)
    hoverBg:Hide()
    row._hoverBg = hoverBg

    -- Row bottom border
    local rowBorder = {}
    local borderAlpha = 0.2
    local bottom = row:CreateTexture(nil, "BORDER", nil, -1)
    bottom:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    bottom:SetHeight(1)
    bottom:SetColorTexture(ar, ag, ab, borderAlpha)
    rowBorder.BOTTOM = bottom
    row._rowBorder = rowBorder

    -- Label text (left side)
    local labelFS = row:CreateFontString(nil, "OVERLAY")
    local labelFont = theme:GetFont("LABEL")
    labelFS:SetFont(labelFont, 13, "")
    labelFS:SetPoint("LEFT", row, "LEFT", COLOR_PADDING, hasDesc and 6 or 0)
    labelFS:SetText(label)
    labelFS:SetTextColor(ar, ag, ab, 1)
    row._label = labelFS

    -- Description text (if provided)
    if hasDesc then
        local descFS = row:CreateFontString(nil, "OVERLAY")
        local descFont = theme:GetFont("VALUE")
        descFS:SetFont(descFont, 11, "")
        descFS:SetPoint("TOPLEFT", labelFS, "BOTTOMLEFT", 0, -2)
        descFS:SetPoint("RIGHT", row, "RIGHT", -(swatchWidth + COLOR_PADDING * 2 + 8), 0)
        descFS:SetText(description)
        descFS:SetTextColor(dimR, dimG, dimB, 1)
        descFS:SetJustifyH("LEFT")
        descFS:SetWordWrap(true)
        row._description = descFS
    end

    -- Color swatch button (right side)
    local swatch = CreateFrame("Button", nil, row)
    swatch:SetSize(swatchWidth, swatchHeight)
    swatch:SetPoint("RIGHT", row, "RIGHT", -COLOR_PADDING, 0)
    swatch:EnableMouse(true)
    swatch:RegisterForClicks("AnyUp")

    -- Swatch border (four edges)
    local swatchBorder = {}

    local sTop = swatch:CreateTexture(nil, "BORDER", nil, -1)
    sTop:SetPoint("TOPLEFT", swatch, "TOPLEFT", 0, 0)
    sTop:SetPoint("TOPRIGHT", swatch, "TOPRIGHT", 0, 0)
    sTop:SetHeight(COLOR_SWATCH_BORDER)
    sTop:SetColorTexture(ar, ag, ab, 1)
    swatchBorder.TOP = sTop

    local sBottom = swatch:CreateTexture(nil, "BORDER", nil, -1)
    sBottom:SetPoint("BOTTOMLEFT", swatch, "BOTTOMLEFT", 0, 0)
    sBottom:SetPoint("BOTTOMRIGHT", swatch, "BOTTOMRIGHT", 0, 0)
    sBottom:SetHeight(COLOR_SWATCH_BORDER)
    sBottom:SetColorTexture(ar, ag, ab, 1)
    swatchBorder.BOTTOM = sBottom

    local sLeft = swatch:CreateTexture(nil, "BORDER", nil, -1)
    sLeft:SetPoint("TOPLEFT", swatch, "TOPLEFT", 0, -COLOR_SWATCH_BORDER)
    sLeft:SetPoint("BOTTOMLEFT", swatch, "BOTTOMLEFT", 0, COLOR_SWATCH_BORDER)
    sLeft:SetWidth(COLOR_SWATCH_BORDER)
    sLeft:SetColorTexture(ar, ag, ab, 1)
    swatchBorder.LEFT = sLeft

    local sRight = swatch:CreateTexture(nil, "BORDER", nil, -1)
    sRight:SetPoint("TOPRIGHT", swatch, "TOPRIGHT", 0, -COLOR_SWATCH_BORDER)
    sRight:SetPoint("BOTTOMRIGHT", swatch, "BOTTOMRIGHT", 0, COLOR_SWATCH_BORDER)
    sRight:SetWidth(COLOR_SWATCH_BORDER)
    sRight:SetColorTexture(ar, ag, ab, 1)
    swatchBorder.RIGHT = sRight

    swatch._border = swatchBorder

    -- Inner color display (checkerboard background for alpha visualization)
    local checkerBg = swatch:CreateTexture(nil, "BACKGROUND", nil, -7)
    checkerBg:SetPoint("TOPLEFT", COLOR_SWATCH_BORDER, -COLOR_SWATCH_BORDER)
    checkerBg:SetPoint("BOTTOMRIGHT", -COLOR_SWATCH_BORDER, COLOR_SWATCH_BORDER)
    checkerBg:SetColorTexture(0.3, 0.3, 0.3, 1)
    swatch._checkerBg = checkerBg

    -- Color fill
    local colorFill = swatch:CreateTexture(nil, "ARTWORK", nil, 0)
    colorFill:SetPoint("TOPLEFT", COLOR_SWATCH_BORDER, -COLOR_SWATCH_BORDER)
    colorFill:SetPoint("BOTTOMRIGHT", -COLOR_SWATCH_BORDER, COLOR_SWATCH_BORDER)
    swatch._colorFill = colorFill

    row._swatch = swatch

    -- Helper to read color (handles both table and multi-return)
    local function ReadColor()
        local result = { getColor() }
        if type(result[1]) == "table" then
            local c = result[1]
            return c.r or c[1] or 1, c.g or c[2] or 1, c.b or c[3] or 1, c.a or c[4] or 1
        else
            return result[1] or 1, result[2] or 1, result[3] or 1, result[4] or 1
        end
    end

    -- Update swatch display
    local function UpdateSwatchColor()
        local r, g, b, a = ReadColor()
        colorFill:SetColorTexture(r, g, b, hasAlpha and a or 1)
    end
    row._updateSwatchColor = UpdateSwatchColor

    -- Initialize color
    UpdateSwatchColor()

    -- Hover handlers for row
    row:SetScript("OnEnter", function(self)
        self._hoverBg:Show()
    end)
    row:SetScript("OnLeave", function(self)
        if not swatch:IsMouseOver() then
            self._hoverBg:Hide()
        end
    end)
    row:EnableMouse(true)

    -- Hover handlers for swatch (highlight border)
    swatch:SetScript("OnEnter", function(self)
        row._hoverBg:Show()
        local r, g, b = theme:GetAccentColor()
        for _, tex in pairs(self._border) do
            tex:SetColorTexture(r, g, b, 1)
        end
    end)
    swatch:SetScript("OnLeave", function(self)
        if not row:IsMouseOver() then
            row._hoverBg:Hide()
        end
        local r, g, b = theme:GetAccentColor()
        for _, tex in pairs(self._border) do
            tex:SetColorTexture(r, g, b, 0.8)
        end
    end)

    -- Click to open color picker
    swatch:SetScript("OnClick", function()
        local curR, curG, curB, curA = ReadColor()

        ColorPickerFrame:SetupColorPickerAndShow({
            r = curR,
            g = curG,
            b = curB,
            hasOpacity = hasAlpha,
            opacity = curA,
            swatchFunc = function()
                local newR, newG, newB = ColorPickerFrame:GetColorRGB()
                local newA = hasAlpha and ColorPickerFrame:GetColorAlpha() or 1
                setColor(newR, newG, newB, newA)
                colorFill:SetColorTexture(newR, newG, newB, hasAlpha and newA or 1)
            end,
            cancelFunc = function(prev)
                if prev then
                    local pR, pG, pB, pA = prev.r or 1, prev.g or 1, prev.b or 1, prev.a or 1
                    setColor(pR, pG, pB, pA)
                    colorFill:SetColorTexture(pR, pG, pB, hasAlpha and pA or 1)
                end
            end,
        })
    end)

    -- Theme subscription
    local subscribeKey = "ColorPicker_" .. (name or tostring(row))
    theme:Subscribe(subscribeKey, function(r, g, b)
        if row._hoverBg then
            row._hoverBg:SetColorTexture(r, g, b, 0.08)
        end
        if row._rowBorder then
            for _, tex in pairs(row._rowBorder) do
                tex:SetColorTexture(r, g, b, 0.2)
            end
        end
        if row._label then
            row._label:SetTextColor(r, g, b, 1)
        end
        if swatch._border then
            local alpha = swatch:IsMouseOver() and 1 or 0.8
            for _, tex in pairs(swatch._border) do
                tex:SetColorTexture(r, g, b, alpha)
            end
        end
    end)
    row._subscribeKey = subscribeKey

    -- Public methods
    function row:SetColor(r, g, b, a)
        setColor(r, g, b, a or 1)
        self._updateSwatchColor()
    end

    function row:GetColor()
        return ReadColor()
    end

    function row:Refresh()
        self._updateSwatchColor()
    end

    function row:Cleanup()
        if self._subscribeKey then
            theme:Unsubscribe(self._subscribeKey)
        end
    end

    return row
end
