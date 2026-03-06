local addonName, addon = ...

addon.Fonts = addon.Fonts or {}
addon.WorldTextFontLog = addon.WorldTextFontLog or {}

local function SnapshotFontObject(fontObj)
    if type(fontObj) ~= "table" or not fontObj.GetFont then
        return "<unavailable>"
    end
    local ok, path, size, flags = pcall(fontObj.GetFont, fontObj)
    if not ok then
        return "<error>"
    end
    return string.format("%s | size=%s | flags=%s", tostring(path or "?"), tostring(size or "?"), tostring(flags or ""))
end

local function FormatExtra(info)
    if type(info) ~= "table" then
        return tostring(info or "")
    end
    local parts = {}
    for k, v in pairs(info) do
        table.insert(parts, string.format("%s=%s", tostring(k), tostring(v)))
    end
    table.sort(parts)
    return table.concat(parts, "; ")
end

local function AppendWorldTextFontLog(stage, info)
    local log = addon.WorldTextFontLog
    if type(log) ~= "table" then
        log = {}
        addon.WorldTextFontLog = log
    end
    local timestamp = string.format("%.1fms", debugprofilestop())
    local snapshot = string.format("DAMAGE_TEXT_FONT=%s | CombatTextFont=%s | CombatTextFontOutline=%s",
        tostring(_G.DAMAGE_TEXT_FONT),
        SnapshotFontObject(_G.CombatTextFont),
        SnapshotFontObject(_G.CombatTextFontOutline)
    )
    local line = string.format("[%s] %s :: %s", timestamp, tostring(stage or "?"), snapshot)
    local extra = FormatExtra(info)
    if extra ~= "" then
        line = line .. " || " .. extra
    end
    table.insert(log, line)
    -- Limit log size
    if #log > 200 then
        table.remove(log, 1)
    end
end

addon.LogWorldTextFont = AppendWorldTextFontLog

function addon.ShowWorldTextFontLog()
    if addon.DebugShowWindow then
        addon.DebugShowWindow("World Text Font Log", addon.WorldTextFontLog)
    elseif addon.Print then
        addon:Print("Debug window unavailable; open after core/debug.lua loads.")
    end
end

AppendWorldTextFontLog("fonts.lua:load", { init = true })

-- Build a container compatible with Settings dropdown options for font faces.
-- This mirrors RIP's behavior but keeps Scoot self-contained. We rely on
-- stock fonts available in all clients and allow future extension via media.
function addon.BuildFontOptionsContainer()
    local create = _G.Settings and _G.Settings.CreateControlTextContainer
    local displayNames = addon.FontDisplayNames or {}

    local add = function(container, key, text)
        if container._seen and container._seen[key] then return end
        if create then
            container:Add(key, text)
        else
            table.insert(container, { value = key, text = text })
        end
        if container._seen then container._seen[key] = true end
    end

    local container = create and create() or {}
    container._seen = {}

    -- Always include FRIZQT__ first (stock default)
    add(container, "FRIZQT__", displayNames.FRIZQT__ or "FRIZQT__")

    -- Add stock fonts next (excluding FRIZQT__ which is already added)
    local stockFonts = { "ARIALN", "MORPHEUS", "SKURRI" }
    for _, k in ipairs(stockFonts) do
        add(container, k, displayNames[k] or k)
    end

    -- Collect and sort all registered fonts by their display names for alphabetical ordering
    local fontEntries = {}
    for k, _ in pairs(addon.Fonts or {}) do
        -- Skip stock fonts (already added above)
        if k ~= "FRIZQT__" and k ~= "ARIALN" and k ~= "MORPHEUS" and k ~= "SKURRI" then
            local display = displayNames[k] or k
            table.insert(fontEntries, { key = k, display = display })
        end
    end

    -- Sort by display name for cleaner grouping (Dosis, Exo 2, Lato, etc.)
    table.sort(fontEntries, function(a, b)
        return a.display < b.display
    end)

    -- Add all custom fonts
    for _, entry in ipairs(fontEntries) do
        add(container, entry.key, entry.display)
    end

    container._seen = nil
    return create and container:GetData() or container
end

-- Resolve a font face name to an actual file path for SetFont.
-- Falls back to the face of GameFontNormal if unknown.
function addon.ResolveFontFace(key)
    local face = (addon.Fonts and addon.Fonts[key or "FRIZQT__"]) or (select(1, _G.GameFontNormal:GetFont()))
    return face
end

--------------------------------------------------------------------------------
-- Font Style Application Helper (supports SHADOW and HEAVY prefixes)
--------------------------------------------------------------------------------
-- Apply font settings to a FontString with support for shadow-prefixed styles.
-- Supported styles: NONE, OUTLINE, THICKOUTLINE, plus these prefixes:
--   SHADOW*: adds a subtle drop shadow (offset 1, -1) for extra visual weight.
--   HEAVY*: adds a centered glow effect (offset 0, 0) - thickens without directional shadow.
function addon.ApplyFontStyle(fs, font, size, style)
    if not fs then return end
    style = style or ""

    -- Detect prefixes (check longer ones first to avoid partial matches)
    local heavy = false
    local shadow = false

    if style:sub(1, 11) == "HEAVYSHADOW" then
        -- Backward compat: HEAVYSHADOW* saved settings render as regular SHADOW
        shadow = true
        style = style:sub(12) -- Strip HEAVYSHADOW prefix
    elseif style:sub(1, 5) == "HEAVY" then
        heavy = true
        style = style:sub(6) -- Strip HEAVY prefix
    elseif style:sub(1, 6) == "SHADOW" then
        shadow = true
        style = style:sub(7) -- Strip SHADOW prefix
    end

    -- Normalize "NONE" to empty string (Blizzard convention)
    if style == "NONE" or style == "" then
        style = ""
    end

    -- Apply the font
    if fs.SetFont then
        pcall(fs.SetFont, fs, font, size, style)
    end

    -- Apply shadow settings
    if fs.SetShadowColor and fs.SetShadowOffset then
        if heavy then
            -- Heavy: thickens text with upper-right offset (opposite of drop shadow look)
            pcall(fs.SetShadowColor, fs, 0, 0, 0, 0.9)
            pcall(fs.SetShadowOffset, fs, 1, 1)
        elseif shadow then
            -- Regular shadow: dark color with subtle offset
            pcall(fs.SetShadowColor, fs, 0, 0, 0, 0.8)
            pcall(fs.SetShadowOffset, fs, 1, -1)
        else
            -- No shadow: transparent with no offset
            pcall(fs.SetShadowColor, fs, 0, 0, 0, 0)
            pcall(fs.SetShadowOffset, fs, 0, 0)
        end
    end
end

--------------------------------------------------------------------------------
-- Custom Font Picker Popup (Tabbed 3-Column Scrollable Grid)
--------------------------------------------------------------------------------

local fontPickerFrame = nil
local fontPickerSetting = nil
local fontPickerCallback = nil
local fontPickerAnchor = nil
local selectedFontTab = "default"

-- Grid layout constants
local FONTS_PER_ROW = 3
local FONT_BUTTON_WIDTH = 160
local FONT_BUTTON_HEIGHT = 26
local FONT_BUTTON_SPACING = 4
local PICKER_PADDING = 12
local PICKER_TITLE_HEIGHT = 30
local TAB_WIDTH = 90
local TAB_HEIGHT = 32

-- Scoot theme colors
local BRAND_R, BRAND_G, BRAND_B = 0.20, 0.90, 0.30

--------------------------------------------------------------------------------
-- Font Category Tables
--------------------------------------------------------------------------------

local DEFAULT_FONTS = { "FRIZQT__", "ARIALN", "MORPHEUS", "SKURRI" }

local GOOGLE_FONTS = {
    -- Fira Sans
    "FIRASANS_REG", "FIRASANS_LIGHT", "FIRASANS_MED", "FIRASANS_SEMIBOLD",
    "FIRASANS_BOLD", "FIRASANS_EXTRABOLD", "FIRASANS_BLACK",
    -- Roboto
    "ROBOTO_REG", "ROBOTO_LIGHT", "ROBOTO_MED", "ROBOTO_SEMIBOLD",
    "ROBOTO_BLD", "ROBOTO_EXTRABOLD", "ROBOTO_BLACK",
    -- Roboto Condensed
    "ROBOTO_COND_REG", "ROBOTO_COND_LIGHT", "ROBOTO_COND_MED", "ROBOTO_COND_SEMIBOLD",
    "ROBOTO_COND_BOLD", "ROBOTO_COND_EXTRABOLD", "ROBOTO_COND_BLACK",
    -- Roboto SemiCondensed
    "ROBOTO_SEMICOND_REG", "ROBOTO_SEMICOND_LIGHT", "ROBOTO_SEMICOND_MED", "ROBOTO_SEMICOND_SEMIBOLD",
    "ROBOTO_SEMICOND_BOLD", "ROBOTO_SEMICOND_EXTRABOLD", "ROBOTO_SEMICOND_BLACK",
    -- Dosis
    "DOSIS_REG", "DOSIS_LIGHT", "DOSIS_MED", "DOSIS_SEMIBOLD",
    "DOSIS_BOLD", "DOSIS_EXTRABOLD",
    -- Exo 2
    "EXO2_REG", "EXO2_LIGHT", "EXO2_MED", "EXO2_SEMIBOLD",
    "EXO2_BOLD", "EXO2_EXTRABOLD", "EXO2_BLACK",
    -- Lato
    "LATO_REG", "LATO_LIGHT", "LATO_BOLD", "LATO_BLACK",
    -- Montserrat
    "MONTSERRAT_REG", "MONTSERRAT_LIGHT", "MONTSERRAT_MED", "MONTSERRAT_SEMIBOLD",
    "MONTSERRAT_BOLD", "MONTSERRAT_EXTRABOLD", "MONTSERRAT_BLACK",
    -- Mukta
    "MUKTA_REG", "MUKTA_LIGHT", "MUKTA_MED", "MUKTA_SEMIBOLD",
    "MUKTA_BOLD", "MUKTA_EXTRABOLD",
    -- Poppins
    "POPPINS_REG", "POPPINS_LIGHT", "POPPINS_MED", "POPPINS_SEMIBOLD",
    "POPPINS_BOLD", "POPPINS_EXTRABOLD", "POPPINS_BLACK",
}

local PIXEL_FONTS = {
    "PIXELLARI",
    "DOGICA_REG", "DOGICA_BOLD", "DOGICA_PIXEL", "DOGICA_PIXELBOLD",
    "PIXELOP_REG", "PIXELOP_BOLD", "PIXELOP_MONO", "PIXELOP_MONOBOLD",
    "PIXELOP_SC", "PIXELOP_SCBOLD",
    "RAINYHEARTS", "FONT_04B30", "MINECRAFT",
}

local FONT_TABS = {
    { key = "default", label = "Default", fonts = DEFAULT_FONTS },
    { key = "google",  label = "Google",  fonts = GOOGLE_FONTS },
    { key = "pixel",   label = "Pixel",   fonts = PIXEL_FONTS },
}

-- Build a reverse lookup: font key -> tab key
local fontCategoryMap = {}
for _, tabData in ipairs(FONT_TABS) do
    for _, fontKey in ipairs(tabData.fonts) do
        fontCategoryMap[fontKey] = tabData.key
    end
end

local function GetCategoryForFont(key)
    return fontCategoryMap[key] or "default"
end

local function CloseFontPicker()
    if fontPickerFrame then
        fontPickerFrame:Hide()
    end
    fontPickerSetting = nil
    fontPickerCallback = nil
    fontPickerAnchor = nil
end

local function CreateFontPicker()
    if fontPickerFrame then return fontPickerFrame end

    local Theme = addon.UI and addon.UI.Theme
    local accentR, accentG, accentB = BRAND_R, BRAND_G, BRAND_B
    if Theme and Theme.GetAccentColor then
        accentR, accentG, accentB = Theme:GetAccentColor()
    end

    -- Calculate content area width (right of tabs)
    local contentWidth = (FONT_BUTTON_WIDTH * FONTS_PER_ROW) + (FONT_BUTTON_SPACING * (FONTS_PER_ROW - 1)) + (PICKER_PADDING * 2)
    local totalWidth = TAB_WIDTH + contentWidth + 24 -- tabs + content + scrollbar
    local popupHeight = 420

    local frame = CreateFrame("Frame", "ScootFontPickerFrame", UIParent)
    frame:SetSize(totalWidth, popupHeight)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(100)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    -- TUI-style background
    local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetAllPoints()
    bg:SetColorTexture(0.04, 0.04, 0.06, 0.96)
    frame._bg = bg

    -- TUI-style border (accent color)
    local borderWidth = 1
    local borders = {}

    local topBorder = frame:CreateTexture(nil, "BORDER", nil, -1)
    topBorder:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    topBorder:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    topBorder:SetHeight(borderWidth)
    topBorder:SetColorTexture(accentR, accentG, accentB, 0.8)
    borders.TOP = topBorder

    local bottomBorder = frame:CreateTexture(nil, "BORDER", nil, -1)
    bottomBorder:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    bottomBorder:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    bottomBorder:SetHeight(borderWidth)
    bottomBorder:SetColorTexture(accentR, accentG, accentB, 0.8)
    borders.BOTTOM = bottomBorder

    local leftBorder = frame:CreateTexture(nil, "BORDER", nil, -1)
    leftBorder:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -borderWidth)
    leftBorder:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, borderWidth)
    leftBorder:SetWidth(borderWidth)
    leftBorder:SetColorTexture(accentR, accentG, accentB, 0.8)
    borders.LEFT = leftBorder

    local rightBorder = frame:CreateTexture(nil, "BORDER", nil, -1)
    rightBorder:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -borderWidth)
    rightBorder:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, borderWidth)
    rightBorder:SetWidth(borderWidth)
    rightBorder:SetColorTexture(accentR, accentG, accentB, 0.8)
    borders.RIGHT = rightBorder

    frame._borders = borders

    -- Title
    local titleFont = (Theme and Theme.GetFont and Theme:GetFont("HEADER")) or "Fonts\\FRIZQT__.TTF"
    local title = frame:CreateFontString(nil, "OVERLAY")
    title:SetFont(titleFont, 14, "")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", PICKER_PADDING, -10)
    title:SetText("Select Font")
    title:SetTextColor(1, 1, 1, 1)
    frame.Title = title

    -- Close button (X)
    local closeBtn = CreateFrame("Button", nil, frame)
    closeBtn:SetSize(24, 24)
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -6)
    closeBtn:EnableMouse(true)
    closeBtn:RegisterForClicks("AnyUp")

    local closeBtnBg = closeBtn:CreateTexture(nil, "BACKGROUND", nil, -7)
    closeBtnBg:SetAllPoints()
    closeBtnBg:SetColorTexture(accentR, accentG, accentB, 1)
    closeBtnBg:Hide()
    closeBtn._bg = closeBtnBg

    local closeBtnText = closeBtn:CreateFontString(nil, "OVERLAY")
    closeBtnText:SetFont(titleFont, 14, "")
    closeBtnText:SetPoint("CENTER", 0, 0)
    closeBtnText:SetText("X")
    closeBtnText:SetTextColor(accentR, accentG, accentB, 1)
    closeBtn._text = closeBtnText

    closeBtn:SetScript("OnEnter", function(self)
        self._bg:Show()
        self._text:SetTextColor(0, 0, 0, 1)
    end)
    closeBtn:SetScript("OnLeave", function(self)
        self._bg:Hide()
        self._text:SetTextColor(accentR, accentG, accentB, 1)
    end)
    closeBtn:SetScript("OnClick", CloseFontPicker)
    frame.CloseButton = closeBtn

    -- Tab container (left side)
    local tabContainer = CreateFrame("Frame", nil, frame)
    tabContainer:SetSize(TAB_WIDTH, popupHeight - PICKER_TITLE_HEIGHT - PICKER_PADDING * 2)
    tabContainer:SetPoint("TOPLEFT", frame, "TOPLEFT", PICKER_PADDING, -(PICKER_TITLE_HEIGHT + 4))
    frame.TabContainer = tabContainer

    -- Vertical separator between tabs and content
    local tabSep = frame:CreateTexture(nil, "BORDER", nil, 0)
    tabSep:SetWidth(1)
    tabSep:SetPoint("TOPLEFT", tabContainer, "TOPRIGHT", 4, 0)
    tabSep:SetPoint("BOTTOMLEFT", tabContainer, "BOTTOMRIGHT", 4, 0)
    tabSep:SetColorTexture(accentR, accentG, accentB, 0.4)
    frame._tabSep = tabSep

    -- Tab buttons
    frame.TabButtons = {}
    local labelFont = (Theme and Theme.GetFont and Theme:GetFont("LABEL")) or "Fonts\\FRIZQT__.TTF"

    for i, tabData in ipairs(FONT_TABS) do
        local tabBtn = CreateFrame("Button", nil, tabContainer)
        tabBtn:SetSize(TAB_WIDTH, TAB_HEIGHT)
        tabBtn:SetPoint("TOPLEFT", tabContainer, "TOPLEFT", 0, -((i - 1) * TAB_HEIGHT))
        tabBtn:EnableMouse(true)
        tabBtn:RegisterForClicks("AnyUp")

        local tabBg = tabBtn:CreateTexture(nil, "BACKGROUND", nil, -6)
        tabBg:SetAllPoints()
        tabBg:SetColorTexture(0.06, 0.06, 0.08, 1)
        tabBtn._bg = tabBg

        local indicator = tabBtn:CreateTexture(nil, "OVERLAY", nil, 1)
        indicator:SetSize(2, TAB_HEIGHT)
        indicator:SetPoint("LEFT", tabBtn, "LEFT", 0, 0)
        indicator:SetColorTexture(accentR, accentG, accentB, 1)
        indicator:Hide()
        tabBtn._indicator = indicator

        local tabLabel = tabBtn:CreateFontString(nil, "OVERLAY")
        tabLabel:SetFont(labelFont, 11, "")
        tabLabel:SetPoint("CENTER", tabBtn, "CENTER", 2, 0)
        tabLabel:SetText(tabData.label)
        tabLabel:SetTextColor(0.6, 0.6, 0.6, 1)
        tabBtn._label = tabLabel

        tabBtn._key = tabData.key

        tabBtn:SetScript("OnEnter", function(self)
            if selectedFontTab ~= self._key then
                self._bg:SetColorTexture(accentR, accentG, accentB, 0.15)
            end
        end)
        tabBtn:SetScript("OnLeave", function(self)
            if selectedFontTab ~= self._key then
                self._bg:SetColorTexture(0.06, 0.06, 0.08, 1)
            end
        end)

        tabBtn:SetScript("OnClick", function(self)
            if selectedFontTab ~= self._key then
                selectedFontTab = self._key
                frame:UpdateTabVisuals()
                frame:PopulateContent()
                PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            end
        end)

        frame.TabButtons[tabData.key] = tabBtn
    end

    -- Content area (scroll frame, right of tabs)
    local scrollFrame = CreateFrame("ScrollFrame", "ScootFontPickerScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", tabContainer, "TOPRIGHT", 12, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -(PICKER_PADDING + 20), PICKER_PADDING)
    frame.ScrollFrame = scrollFrame

    -- Style the scrollbar
    local scrollBar = scrollFrame.ScrollBar or _G[scrollFrame:GetName() .. "ScrollBar"]
    if scrollBar then
        scrollBar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", 6, -16)
        scrollBar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", 6, 16)

        if scrollBar.Background then scrollBar.Background:Hide() end
        if scrollBar.Track then
            if scrollBar.Track.Begin then scrollBar.Track.Begin:Hide() end
            if scrollBar.Track.End then scrollBar.Track.End:Hide() end
            if scrollBar.Track.Middle then scrollBar.Track.Middle:Hide() end
        end

        local trackBg = scrollBar:CreateTexture(nil, "BACKGROUND", nil, -8)
        trackBg:SetPoint("TOPLEFT", 4, 0)
        trackBg:SetPoint("BOTTOMRIGHT", -4, 0)
        trackBg:SetColorTexture(accentR, accentG, accentB, 0.15)
        scrollBar._trackBg = trackBg

        local thumb = scrollBar.ThumbTexture or scrollBar:GetThumbTexture()
        if thumb then
            thumb:SetColorTexture(accentR, accentG, accentB, 0.6)
            thumb:SetSize(8, 40)
        end

        local upBtn = scrollBar.ScrollUpButton or scrollBar.Back or _G[scrollBar:GetName() .. "ScrollUpButton"]
        local downBtn = scrollBar.ScrollDownButton or scrollBar.Forward or _G[scrollBar:GetName() .. "ScrollDownButton"]
        if upBtn then upBtn:SetAlpha(0) upBtn:EnableMouse(false) end
        if downBtn then downBtn:SetAlpha(0) downBtn:EnableMouse(false) end

        frame._scrollBar = scrollBar
    end

    -- Content frame (scroll child)
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(contentWidth - PICKER_PADDING, 100)
    scrollFrame:SetScrollChild(content)
    frame.Content = content

    -- Button pool for font options
    frame.Buttons = {}

    -- Store accent colors
    frame._accentR = accentR
    frame._accentG = accentG
    frame._accentB = accentB

    -- Update tab visuals
    function frame:UpdateTabVisuals()
        for key, tabBtn in pairs(self.TabButtons) do
            local isSelected = (selectedFontTab == key)
            if isSelected then
                tabBtn._indicator:Show()
                tabBtn._label:SetTextColor(1, 1, 1, 1)
                tabBtn._bg:SetColorTexture(self._accentR, self._accentG, self._accentB, 0.2)
            else
                tabBtn._indicator:Hide()
                tabBtn._label:SetTextColor(0.6, 0.6, 0.6, 1)
                tabBtn._bg:SetColorTexture(0.06, 0.06, 0.08, 1)
            end
        end
    end

    -- Populate content for selected tab
    function frame:PopulateContent()
        local currentTab = nil
        for _, tabData in ipairs(FONT_TABS) do
            if tabData.key == selectedFontTab then
                currentTab = tabData
                break
            end
        end
        if not currentTab then return end

        local fonts = currentTab.fonts
        local contentFrame = self.Content
        local displayNames = addon.FontDisplayNames or {}
        local defaultFont = select(1, _G.GameFontNormal:GetFont()) or "Fonts\\FRIZQT__.TTF"

        local accentR = self._accentR or BRAND_R
        local accentG = self._accentG or BRAND_G
        local accentB = self._accentB or BRAND_B

        -- Get current value
        local currentValue = nil
        if fontPickerSetting and fontPickerSetting.GetValue then
            currentValue = fontPickerSetting:GetValue()
        end

        -- Calculate content height
        local numRows = math.ceil(#fonts / FONTS_PER_ROW)
        local contentHeight = (numRows * FONT_BUTTON_HEIGHT) + ((numRows - 1) * FONT_BUTTON_SPACING) + PICKER_PADDING
        contentFrame:SetHeight(contentHeight)

        -- Show/hide scrollbar based on content size
        local scrollFrame = self.ScrollFrame
        local scrollBar = self._scrollBar
        if scrollBar and scrollFrame then
            local visibleHeight = scrollFrame:GetHeight()
            if contentHeight > visibleHeight then
                scrollBar:Show()
                if scrollBar._trackBg then scrollBar._trackBg:Show() end
            else
                scrollBar:Hide()
                if scrollBar._trackBg then scrollBar._trackBg:Hide() end
            end
        end

        -- Hide all existing buttons
        for _, btn in ipairs(self.Buttons) do
            btn:Hide()
        end

        -- Create/reuse buttons for each font
        for i, fontKey in ipairs(fonts) do
            local btn = self.Buttons[i]
            if not btn then
                btn = CreateFrame("Button", nil, contentFrame)
                btn:SetSize(FONT_BUTTON_WIDTH, FONT_BUTTON_HEIGHT)
                btn:EnableMouse(true)
                btn:RegisterForClicks("AnyUp")

                local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                label:SetPoint("LEFT", btn, "LEFT", 4, 0)
                label:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
                label:SetJustifyH("LEFT")
                label:SetWordWrap(false)
                btn.Label = label

                self.Buttons[i] = btn
            end

            -- Position in grid
            local col = (i - 1) % FONTS_PER_ROW
            local row = math.floor((i - 1) / FONTS_PER_ROW)
            local x = col * (FONT_BUTTON_WIDTH + FONT_BUTTON_SPACING)
            local y = -(row * (FONT_BUTTON_HEIGHT + FONT_BUTTON_SPACING))
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", x, y)

            -- Set font preview (render label in that font)
            local fontFace = addon.ResolveFontFace(fontKey)
            local fontSet = false
            if fontFace then
                fontSet = pcall(btn.Label.SetFont, btn.Label, fontFace, 12, "")
            end
            if not fontSet then
                pcall(btn.Label.SetFont, btn.Label, defaultFont, 12, "")
            end

            -- Set display name
            local displayText = displayNames[fontKey] or fontKey
            btn.Label:SetText(displayText)

            -- Selection state
            local isSelected = (currentValue == fontKey)
            btn._fontValue = fontKey
            btn._isSelected = isSelected
            btn._accentR = accentR
            btn._accentG = accentG
            btn._accentB = accentB

            if isSelected then
                btn.Label:SetTextColor(accentR, accentG, accentB, 1)
            else
                btn.Label:SetTextColor(1, 1, 1, 0.9)
            end

            -- Click handler
            btn:SetScript("OnClick", function(self)
                local value = self._fontValue
                if fontPickerSetting and fontPickerSetting.SetValue then
                    fontPickerSetting:SetValue(value)
                end
                if fontPickerCallback then
                    fontPickerCallback(value)
                end
                if fontPickerAnchor and fontPickerAnchor.Text then
                    local dt = addon.FontDisplayNames and addon.FontDisplayNames[value] or value
                    fontPickerAnchor.Text:SetText(dt)
                end
                CloseFontPicker()
                PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            end)

            -- Hover effects
            btn:SetScript("OnEnter", function(self)
                if not self._isSelected then
                    self.Label:SetTextColor(self._accentR, self._accentG, self._accentB, 1)
                end
            end)
            btn:SetScript("OnLeave", function(self)
                if self._isSelected then
                    self.Label:SetTextColor(self._accentR, self._accentG, self._accentB, 1)
                else
                    self.Label:SetTextColor(1, 1, 1, 0.9)
                end
            end)

            btn:Show()
        end
    end

    -- Escape key to close
    frame:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            CloseFontPicker()
        end
    end)

    -- Click outside to close
    frame:SetScript("OnShow", function(self)
        self:SetScript("OnUpdate", function(self, elapsed)
            if not self:IsMouseOver() and IsMouseButtonDown("LeftButton") then
                C_Timer.After(0.05, function()
                    if fontPickerFrame and fontPickerFrame:IsShown() and not fontPickerFrame:IsMouseOver() then
                        CloseFontPicker()
                    end
                end)
            end
        end)
    end)
    frame:SetScript("OnHide", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    fontPickerFrame = frame
    return frame
end

function addon.ShowFontPicker(anchor, setting, optionsProvider, callback)
    local frame = CreateFontPicker()

    fontPickerSetting = setting
    fontPickerCallback = callback
    fontPickerAnchor = anchor

    -- Get current value and determine which tab to show
    local currentValue = nil
    if setting and setting.GetValue then
        currentValue = setting:GetValue()
    end

    -- Auto-select tab containing the currently selected font
    if currentValue then
        selectedFontTab = GetCategoryForFont(currentValue)
    else
        selectedFontTab = "default"
    end

    -- Update visuals and populate
    frame:UpdateTabVisuals()
    frame:PopulateContent()

    -- Position relative to anchor
    frame:ClearAllPoints()
    if anchor then
        local anchorBottom = anchor:GetBottom() or 0
        local frameHeight = frame:GetHeight()
        local screenHeight = GetScreenHeight() * UIParent:GetEffectiveScale()

        if anchorBottom - frameHeight < 50 then
            frame:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 4)
        else
            frame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
        end
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end

    frame:Show()
    frame:Raise()

    -- Preload fonts for smooth rendering
    if addon.PreloadFonts then
        addon.PreloadFonts()
    end
end

function addon.CloseFontPicker()
    CloseFontPicker()
end

--------------------------------------------------------------------------------
-- Font Dropdown Integration
--------------------------------------------------------------------------------

-- Apply font preview to a Settings dropdown by using our custom font picker popup
function addon.InitFontDropdown(dropdown, setting, optionsProvider)
    if not dropdown or dropdown._ScootFontPickerInit then return end

    -- Function to update dropdown display text
    local function updateDropdownText()
        if not setting or not setting.GetValue then return end
        local currentValue = setting:GetValue()
        local displayText = addon.FontDisplayNames and addon.FontDisplayNames[currentValue] or currentValue
        if dropdown.Text and dropdown.Text.SetText then
            dropdown.Text:SetText(displayText)
            -- Also render the dropdown text in the selected font
            local fontFace = addon.ResolveFontFace(currentValue)
            if fontFace then
                pcall(dropdown.Text.SetFont, dropdown.Text, fontFace, 12, "")
            end
        end
    end

    -- Intercept clicks to show our custom picker instead of Blizzard's menu
    local function showPicker()
        -- Close any open Blizzard menus first
        if _G.MenuUtil and _G.MenuUtil.HideAllMenus then
            pcall(_G.MenuUtil.HideAllMenus)
        end
        if _G.CloseDropDownMenus then
            pcall(_G.CloseDropDownMenus)
        end

        addon.ShowFontPicker(dropdown, setting, optionsProvider, function(selectedValue)
            -- Callback after selection - update display
            updateDropdownText()
        end)
    end

    -- Create an invisible overlay button that captures clicks before the dropdown
    local overlay = CreateFrame("Button", nil, dropdown)
    overlay:SetAllPoints(dropdown)
    overlay:SetFrameLevel(dropdown:GetFrameLevel() + 10)
    overlay:RegisterForClicks("LeftButtonUp", "LeftButtonDown")

    overlay:SetScript("OnClick", function(self, button, down)
        if not down then
            showPicker()
        end
    end)

    -- Make overlay transparent but clickable
    overlay:EnableMouse(true)

    -- Store reference so we can access it later if needed
    dropdown._ScootFontPickerOverlay = overlay

    -- Initial text update
    C_Timer.After(0, updateDropdownText)

    dropdown._ScootFontPickerInit = true
end

-- Register stock faces and bundled font variants (paths are relative to the WoW root)
do
    local f = addon.Fonts
    -- Blizzard stock font aliases
    f.FRIZQT__ = "Fonts\\FRIZQT__.TTF"
    f.ARIALN   = "Fonts\\ARIALN.TTF"
    f.MORPHEUS = "Fonts\\MORPHEUS.TTF"
    f.SKURRI   = "Fonts\\SKURRI.TTF"

    local base = "Interface\\AddOns\\Scoot\\media\\fonts\\"

    -- Fira Sans family
    f.FIRASANS_REG       = base .. "FiraSans-Regular.ttf"
    f.FIRASANS_LIGHT     = base .. "FiraSans-Light.ttf"
    f.FIRASANS_MED       = base .. "FiraSans-Medium.ttf"
    f.FIRASANS_SEMIBOLD  = base .. "FiraSans-SemiBold.ttf"
    f.FIRASANS_BOLD      = base .. "FiraSans-Bold.ttf"
    f.FIRASANS_EXTRABOLD = base .. "FiraSans-ExtraBold.ttf"
    f.FIRASANS_BLACK     = base .. "FiraSans-Black.ttf"

    -- Roboto family
    f.ROBOTO_REG       = base .. "Roboto-Regular.ttf"
    f.ROBOTO_LIGHT     = base .. "Roboto-Light.ttf"
    f.ROBOTO_MED       = base .. "Roboto-Medium.ttf"
    f.ROBOTO_SEMIBOLD  = base .. "Roboto-SemiBold.ttf"
    f.ROBOTO_BLD       = base .. "Roboto-Bold.ttf"
    f.ROBOTO_EXTRABOLD = base .. "Roboto-ExtraBold.ttf"
    f.ROBOTO_BLACK     = base .. "Roboto-Black.ttf"

    -- Roboto Condensed family
    f.ROBOTO_COND_REG       = base .. "Roboto_Condensed-Regular.ttf"
    f.ROBOTO_COND_LIGHT     = base .. "Roboto_Condensed-Light.ttf"
    f.ROBOTO_COND_MED       = base .. "Roboto_Condensed-Medium.ttf"
    f.ROBOTO_COND_SEMIBOLD  = base .. "Roboto_Condensed-SemiBold.ttf"
    f.ROBOTO_COND_BOLD      = base .. "Roboto_Condensed-Bold.ttf"
    f.ROBOTO_COND_EXTRABOLD = base .. "Roboto_Condensed-ExtraBold.ttf"
    f.ROBOTO_COND_BLACK     = base .. "Roboto_Condensed-Black.ttf"

    -- Roboto SemiCondensed family
    f.ROBOTO_SEMICOND_REG       = base .. "Roboto_SemiCondensed-Regular.ttf"
    f.ROBOTO_SEMICOND_LIGHT     = base .. "Roboto_SemiCondensed-Light.ttf"
    f.ROBOTO_SEMICOND_MED       = base .. "Roboto_SemiCondensed-Medium.ttf"
    f.ROBOTO_SEMICOND_SEMIBOLD  = base .. "Roboto_SemiCondensed-SemiBold.ttf"
    f.ROBOTO_SEMICOND_BOLD      = base .. "Roboto_SemiCondensed-Bold.ttf"
    f.ROBOTO_SEMICOND_EXTRABOLD = base .. "Roboto_SemiCondensed-ExtraBold.ttf"
    f.ROBOTO_SEMICOND_BLACK     = base .. "Roboto_SemiCondensed-Black.ttf"

    -- Dosis family
    f.DOSIS_REG      = base .. "Dosis-Regular.ttf"
    f.DOSIS_LIGHT    = base .. "Dosis-Light.ttf"
    f.DOSIS_MED      = base .. "Dosis-Medium.ttf"
    f.DOSIS_SEMIBOLD = base .. "Dosis-SemiBold.ttf"
    f.DOSIS_BOLD     = base .. "Dosis-Bold.ttf"
    f.DOSIS_EXTRABOLD= base .. "Dosis-ExtraBold.ttf"

    -- Exo 2 family
    f.EXO2_REG       = base .. "Exo2-Regular.ttf"
    f.EXO2_LIGHT     = base .. "Exo2-Light.ttf"
    f.EXO2_MED       = base .. "Exo2-Medium.ttf"
    f.EXO2_SEMIBOLD  = base .. "Exo2-SemiBold.ttf"
    f.EXO2_BOLD      = base .. "Exo2-Bold.ttf"
    f.EXO2_EXTRABOLD = base .. "Exo2-ExtraBold.ttf"
    f.EXO2_BLACK     = base .. "Exo2-Black.ttf"

    -- Lato family
    f.LATO_REG   = base .. "Lato-Regular.ttf"
    f.LATO_LIGHT = base .. "Lato-Light.ttf"
    f.LATO_BOLD  = base .. "Lato-Bold.ttf"
    f.LATO_BLACK = base .. "Lato-Black.ttf"

    -- Montserrat family
    f.MONTSERRAT_REG       = base .. "Montserrat-Regular.ttf"
    f.MONTSERRAT_LIGHT     = base .. "Montserrat-Light.ttf"
    f.MONTSERRAT_MED       = base .. "Montserrat-Medium.ttf"
    f.MONTSERRAT_SEMIBOLD  = base .. "Montserrat-SemiBold.ttf"
    f.MONTSERRAT_BOLD      = base .. "Montserrat-Bold.ttf"
    f.MONTSERRAT_EXTRABOLD = base .. "Montserrat-ExtraBold.ttf"
    f.MONTSERRAT_BLACK     = base .. "Montserrat-Black.ttf"

    -- Mukta family
    f.MUKTA_REG      = base .. "Mukta-Regular.ttf"
    f.MUKTA_LIGHT    = base .. "Mukta-Light.ttf"
    f.MUKTA_MED      = base .. "Mukta-Medium.ttf"
    f.MUKTA_SEMIBOLD = base .. "Mukta-SemiBold.ttf"
    f.MUKTA_BOLD     = base .. "Mukta-Bold.ttf"
    f.MUKTA_EXTRABOLD= base .. "Mukta-ExtraBold.ttf"

    -- Poppins family
    f.POPPINS_REG       = base .. "Poppins-Regular.ttf"
    f.POPPINS_LIGHT     = base .. "Poppins-Light.ttf"
    f.POPPINS_MED       = base .. "Poppins-Medium.ttf"
    f.POPPINS_SEMIBOLD  = base .. "Poppins-SemiBold.ttf"
    f.POPPINS_BOLD      = base .. "Poppins-Bold.ttf"
    f.POPPINS_EXTRABOLD = base .. "Poppins-ExtraBold.ttf"
    f.POPPINS_BLACK     = base .. "Poppins-Black.ttf"

    -- Pixel fonts
    f.PIXELLARI        = base .. "Pixellari.ttf"
    f.DOGICA_REG       = base .. "dogica.ttf"
    f.DOGICA_BOLD      = base .. "dogicabold.ttf"
    f.DOGICA_PIXEL     = base .. "dogicapixel.ttf"
    f.DOGICA_PIXELBOLD = base .. "dogicapixelbold.ttf"
    f.PIXELOP_REG      = base .. "PixelOperator.ttf"
    f.PIXELOP_BOLD     = base .. "PixelOperator-Bold.ttf"
    f.PIXELOP_MONO     = base .. "PixelOperatorMono.ttf"
    f.PIXELOP_MONOBOLD = base .. "PixelOperatorMono-Bold.ttf"
    f.PIXELOP_SC       = base .. "PixelOperatorSC.ttf"
    f.PIXELOP_SCBOLD   = base .. "PixelOperatorSC-Bold.ttf"
    f.RAINYHEARTS      = base .. "rainyhearts.ttf"
    f.FONT_04B30       = base .. "04B_30__.TTF"
    f.MINECRAFT        = base .. "Minecraft.ttf"
end

-- Human-readable display names for the font dropdown
addon.FontDisplayNames = {
    -- Stock fonts
    FRIZQT__  = "Friz Quadrata (Default)",
    ARIALN    = "Arial Narrow",
    MORPHEUS  = "Morpheus",
    SKURRI    = "Skurri",
    -- Fira Sans
    FIRASANS_REG       = "Fira Sans",
    FIRASANS_LIGHT     = "Fira Sans Light",
    FIRASANS_MED       = "Fira Sans Medium",
    FIRASANS_SEMIBOLD  = "Fira Sans SemiBold",
    FIRASANS_BOLD      = "Fira Sans Bold",
    FIRASANS_EXTRABOLD = "Fira Sans ExtraBold",
    FIRASANS_BLACK     = "Fira Sans Black",
    -- Roboto
    ROBOTO_REG       = "Roboto",
    ROBOTO_LIGHT     = "Roboto Light",
    ROBOTO_MED       = "Roboto Medium",
    ROBOTO_SEMIBOLD  = "Roboto SemiBold",
    ROBOTO_BLD       = "Roboto Bold",
    ROBOTO_EXTRABOLD = "Roboto ExtraBold",
    ROBOTO_BLACK     = "Roboto Black",
    -- Roboto Condensed
    ROBOTO_COND_REG       = "Roboto Cond",
    ROBOTO_COND_LIGHT     = "Roboto Cond Light",
    ROBOTO_COND_MED       = "Roboto Cond Medium",
    ROBOTO_COND_SEMIBOLD  = "Roboto Cond SemiBold",
    ROBOTO_COND_BOLD      = "Roboto Cond Bold",
    ROBOTO_COND_EXTRABOLD = "Roboto Cond ExtraBold",
    ROBOTO_COND_BLACK     = "Roboto Cond Black",
    -- Roboto SemiCondensed
    ROBOTO_SEMICOND_REG       = "Roboto SemiCond",
    ROBOTO_SEMICOND_LIGHT     = "Roboto SemiCond Light",
    ROBOTO_SEMICOND_MED       = "Roboto SemiCond Medium",
    ROBOTO_SEMICOND_SEMIBOLD  = "Roboto SemiCond SemiBold",
    ROBOTO_SEMICOND_BOLD      = "Roboto SemiCond Bold",
    ROBOTO_SEMICOND_EXTRABOLD = "Roboto SemiCond ExtraBold",
    ROBOTO_SEMICOND_BLACK     = "Roboto SemiCond Black",
    -- Dosis
    DOSIS_REG      = "Dosis",
    DOSIS_LIGHT    = "Dosis Light",
    DOSIS_MED      = "Dosis Medium",
    DOSIS_SEMIBOLD = "Dosis SemiBold",
    DOSIS_BOLD     = "Dosis Bold",
    DOSIS_EXTRABOLD= "Dosis ExtraBold",
    -- Exo 2
    EXO2_REG       = "Exo 2",
    EXO2_LIGHT     = "Exo 2 Light",
    EXO2_MED       = "Exo 2 Medium",
    EXO2_SEMIBOLD  = "Exo 2 SemiBold",
    EXO2_BOLD      = "Exo 2 Bold",
    EXO2_EXTRABOLD = "Exo 2 ExtraBold",
    EXO2_BLACK     = "Exo 2 Black",
    -- Lato
    LATO_REG   = "Lato",
    LATO_LIGHT = "Lato Light",
    LATO_BOLD  = "Lato Bold",
    LATO_BLACK = "Lato Black",
    -- Montserrat
    MONTSERRAT_REG       = "Montserrat",
    MONTSERRAT_LIGHT     = "Montserrat Light",
    MONTSERRAT_MED       = "Montserrat Medium",
    MONTSERRAT_SEMIBOLD  = "Montserrat SemiBold",
    MONTSERRAT_BOLD      = "Montserrat Bold",
    MONTSERRAT_EXTRABOLD = "Montserrat ExtraBold",
    MONTSERRAT_BLACK     = "Montserrat Black",
    -- Mukta
    MUKTA_REG      = "Mukta",
    MUKTA_LIGHT    = "Mukta Light",
    MUKTA_MED      = "Mukta Medium",
    MUKTA_SEMIBOLD = "Mukta SemiBold",
    MUKTA_BOLD     = "Mukta Bold",
    MUKTA_EXTRABOLD= "Mukta ExtraBold",
    -- Poppins
    POPPINS_REG       = "Poppins",
    POPPINS_LIGHT     = "Poppins Light",
    POPPINS_MED       = "Poppins Medium",
    POPPINS_SEMIBOLD  = "Poppins SemiBold",
    POPPINS_BOLD      = "Poppins Bold",
    POPPINS_EXTRABOLD = "Poppins ExtraBold",
    POPPINS_BLACK     = "Poppins Black",
    -- Pixel fonts
    PIXELLARI        = "Pixellari",
    DOGICA_REG       = "Dogica",
    DOGICA_BOLD      = "Dogica Bold",
    DOGICA_PIXEL     = "Dogica Pixel",
    DOGICA_PIXELBOLD = "Dogica Pixel Bold",
    PIXELOP_REG      = "Pixel Operator",
    PIXELOP_BOLD     = "Pixel Operator Bold",
    PIXELOP_MONO     = "Pixel Operator Mono",
    PIXELOP_MONOBOLD = "Pixel Operator Mono Bold",
    PIXELOP_SC       = "Pixel Operator SC",
    PIXELOP_SCBOLD   = "Pixel Operator SC Bold",
    RAINYHEARTS      = "Rainy Hearts",
    FONT_04B30       = "04B_30",
    MINECRAFT        = "Minecraft",
}


-- Preload font faces once to ensure consistent first-use rendering after game launch.
-- This avoids cases where certain Roboto variants appear unstyled until a second open.
function addon.PreloadFonts()
    if addon._fontsPreloaded then return end
    addon._fontsPreloaded = true
    local holder = CreateFrame("Frame")
    holder:Hide()
    local fs = holder:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    local size = 14
    local warmup = "The quick brown fox jumps over the lazy dog 0123456789 !@#%^&*()[]{}"
    for _, path in pairs(addon.Fonts or {}) do
        if type(path) == "string" and path ~= "" then
            pcall(fs.SetFont, fs, path, size, "")
            fs:SetText(warmup)
            pcall(fs.GetStringWidth, fs)
            fs:SetText("")
        end
    end
end



