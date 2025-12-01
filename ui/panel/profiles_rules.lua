local addonName, addon = ...

addon.SettingsPanel = addon.SettingsPanel or {}
local panel = addon.SettingsPanel

-- Track which rules are in edit mode (keyed by rule.id)
local editingRules = {}

-- Track partial breadcrumb selections (keyed by rule.id)
-- Stores { [1] = "Component", [2] = "Sub", ... } for incomplete paths
local breadcrumbSelections = {}

-- Dropdown menu state
local activeMenuData = nil

-- Card height constants
local DISPLAY_MODE_HEIGHT = 130
local EDIT_MODE_HEIGHT = 320
local DIVIDER_HEIGHT = 24

-- Layout constants for badge positioning outside card
local INDEX_BADGE_SIZE = 26
local INDEX_BADGE_LEFT_MARGIN = 8
local CARD_LEFT_MARGIN = INDEX_BADGE_SIZE + INDEX_BADGE_LEFT_MARGIN + 10  -- badge + gap + padding
local CARD_RIGHT_MARGIN = 6
local CARD_VERTICAL_PADDING = 4

-- Max badges to display before showing "+X more"
local MAX_DISPLAY_BADGES = 3
local MAX_EDIT_BADGES = 3

-- Index badge colors
local BADGE_BG_COLOR = { r = 0.20, g = 0.90, b = 0.30, a = 1.0 }         -- Scooter green background
local BADGE_TEXT_COLOR = { r = 0.05, g = 0.05, b = 0.05, a = 1.0 }       -- Dark text for contrast

--------------------------------------------------------------------------------
-- Value Display Helper
--------------------------------------------------------------------------------

-- Format an action value for display in the collapsed "DO" row.
-- Returns a text string for most types; for colors, returns nil and a color table.
-- @param actionId: The action registry ID
-- @param value: The current value
-- @return displayText, colorValue (colorValue is nil for non-color types)
local function FormatActionValueForDisplay(actionId, value)
    if not addon.Rules then
        return tostring(value or "?"), nil
    end

    local meta = addon.Rules:GetActionMetadata(actionId)
    if not meta then
        return tostring(value or "?"), nil
    end

    local widget = meta.widget or "checkbox"
    local valueType = meta.valueType or "boolean"

    if widget == "checkbox" or valueType == "boolean" then
        -- Boolean: "True" or "False"
        return value and "True" or "False", nil

    elseif widget == "slider" or valueType == "number" then
        -- Number: Show the numeric value
        local num = tonumber(value) or 0
        -- Check if uiMeta has a format (e.g., percent)
        if meta.uiMeta and meta.uiMeta.format == "percent" then
            return string.format("%d%%", num), nil
        end
        return tostring(num), nil

    elseif widget == "dropdown" then
        -- Dropdown: Show the display label, not the key
        if meta.uiMeta and meta.uiMeta.values then
            local displayLabel = meta.uiMeta.values[value]
            if displayLabel then
                return displayLabel, nil
            end
        end
        return tostring(value or "?"), nil

    elseif widget == "color" or valueType == "color" then
        -- Color: Return a color table for swatch rendering
        local colorValue = value
        if type(colorValue) ~= "table" then
            colorValue = { 1, 1, 1, 1 }
        end
        return nil, colorValue

    else
        -- Fallback
        return tostring(value or "?"), nil
    end
end

--------------------------------------------------------------------------------
-- Utility Functions
--------------------------------------------------------------------------------

local function EnsureCallbackContainer(frame)
    if not frame then return end
    if not frame.cbrHandles then
        if Settings and Settings.CreateCallbackHandleContainer then
            frame.cbrHandles = Settings.CreateCallbackHandleContainer()
        else
            frame.cbrHandles = {
                Unregister = function() end,
                RegisterCallback = function() end,
                AddHandle = function() end,
                SetOnValueChangedCallback = function() end,
                IsEmpty = function() return true end,
            }
        end
    end
end

--------------------------------------------------------------------------------
-- Rule Deletion Confirmation (using ScooterMod's custom dialog system)
-- Note: We avoid StaticPopupDialogs to prevent tainting Blizzard's global,
-- which can block protected functions like ForceQuit(), Logout(), etc.
--------------------------------------------------------------------------------

local function ResetListRow(frame)
    EnsureCallbackContainer(frame)
    if not frame then return end
    -- Hide all possible recycled elements
    local elementsToHide = {
        "Text", "InfoText", "ButtonContainer", "MessageText", "ActiveDropdown",
        "SpecEnableCheck", "SpecIcon", "SpecName", "SpecDropdown", "RenameBtn",
        "CopyBtn", "DeleteBtn", "CreateBtn", "RuleCard", "EmptyText", "AddRuleBtn",
        "EnabledLabel", "IndexBadge", "AccentBar", "DividerLine", "DividerLineRight",
        "DividerOrnament", "DividerOrnamentBg"
    }
    for _, key in ipairs(elementsToHide) do
        if frame[key] then frame[key]:Hide() end
    end
end

local function StyleLabel(fs, size)
    if not fs then return end
    if panel and panel.ApplyRobotoWhite then
        panel.ApplyRobotoWhite(fs, size)
    end
end

local function StyleLabelMuted(fs, size)
    if not fs then return end
    if panel and panel.ApplyRoboto then
        panel.ApplyRoboto(fs, size)
        if fs.SetTextColor then
            fs:SetTextColor(0.6, 0.6, 0.6, 1)
        end
    end
end

local function applyButtonTheme(btn)
    if panel and panel.ApplyButtonTheme then
        panel.ApplyButtonTheme(btn)
    end
end

--------------------------------------------------------------------------------
-- Simple Custom Dropdown Widget (for breadcrumb selectors)
--------------------------------------------------------------------------------

local activeSimpleDropdown = nil  -- Track currently open dropdown

local function CloseSimpleDropdown()
    if activeSimpleDropdown then
        activeSimpleDropdown:Hide()
        activeSimpleDropdown = nil
    end
end

-- Create a simple dropdown button with a popup list
-- parent: Parent frame
-- options: Array of { text = "label", value = any, disabled = bool }
-- currentValue: The currently selected value (matched against option.value or option.text)
-- onSelect: function(selectedOption) called when user picks an option
-- placeholder: Text to show when nothing is selected
local function CreateSimpleDropdown(parent, options, currentValue, onSelect, placeholder)
    placeholder = placeholder or "Select..."

    -- Main button
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(140, 22)
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    btn:SetBackdropColor(0.15, 0.15, 0.15, 0.95)
    btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    -- Button text
    local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btnText:SetPoint("LEFT", btn, "LEFT", 6, 0)
    btnText:SetPoint("RIGHT", btn, "RIGHT", -16, 0)
    btnText:SetJustifyH("LEFT")
    btnText:SetWordWrap(false)
    btn.Text = btnText

    -- Arrow indicator (simple "v" for down arrow)
    local arrow = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    arrow:SetPoint("RIGHT", btn, "RIGHT", -5, -1)
    arrow:SetText("v")
    arrow:SetTextColor(0.7, 0.7, 0.7, 1)
    btn.Arrow = arrow

    -- Create popup list frame
    local popup = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    popup:SetFrameStrata("TOOLTIP")
    popup:SetFrameLevel(200)
    popup:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    popup:SetBackdropColor(0.1, 0.1, 0.1, 0.98)
    popup:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    popup:Hide()
    btn.Popup = popup

    -- Update display based on current value
    local function UpdateDisplay()
        local displayText = placeholder
        for _, opt in ipairs(options) do
            local optValue = opt.value ~= nil and opt.value or opt.text
            if optValue == currentValue then
                displayText = opt.text
                break
            end
        end
        btnText:SetText(displayText)
        if displayText == placeholder then
            btnText:SetTextColor(0.5, 0.5, 0.5, 1)
        else
            btnText:SetTextColor(1, 1, 1, 1)
        end
    end

    -- Build popup content
    local function BuildPopup()
        -- Clear existing option buttons
        if popup.optionButtons then
            for _, optBtn in ipairs(popup.optionButtons) do
                optBtn:Hide()
            end
        end
        popup.optionButtons = {}

        local yOffset = -4
        local maxWidth = btn:GetWidth() - 2

        for _, opt in ipairs(options) do
            local optBtn = CreateFrame("Button", nil, popup)
            optBtn:SetHeight(20)
            optBtn:SetPoint("TOPLEFT", popup, "TOPLEFT", 2, yOffset)
            optBtn:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -2, yOffset)

            local optText = optBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            optText:SetPoint("LEFT", optBtn, "LEFT", 6, 0)
            optText:SetPoint("RIGHT", optBtn, "RIGHT", -6, 0)
            optText:SetJustifyH("LEFT")
            optText:SetText(opt.text)
            optBtn.Text = optText

            -- Calculate width needed
            local textWidth = optText:GetStringWidth() + 20
            if textWidth > maxWidth then
                maxWidth = textWidth
            end

            -- Hover highlight
            local highlight = optBtn:CreateTexture(nil, "HIGHLIGHT")
            highlight:SetAllPoints()
            highlight:SetColorTexture(0.3, 0.5, 0.3, 0.5)

            -- Check if this is the selected option
            local optValue = opt.value ~= nil and opt.value or opt.text
            if optValue == currentValue then
                optText:SetTextColor(0.5, 1, 0.5, 1)
            elseif opt.disabled then
                optText:SetTextColor(0.4, 0.4, 0.4, 1)
            else
                optText:SetTextColor(0.9, 0.9, 0.9, 1)
            end

            if not opt.disabled then
                optBtn:SetScript("OnClick", function()
                    CloseSimpleDropdown()
                    if onSelect then
                        onSelect(opt)
                    end
                end)
            end

            table.insert(popup.optionButtons, optBtn)
            yOffset = yOffset - 20
        end

        -- Size the popup
        local popupHeight = math.abs(yOffset) + 6
        popup:SetSize(math.max(maxWidth, btn:GetWidth()), popupHeight)
        popup:ClearAllPoints()
        popup:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
    end

    -- Button click handler
    btn:SetScript("OnClick", function()
        if popup:IsShown() then
            CloseSimpleDropdown()
        else
            CloseSimpleDropdown()  -- Close any other open dropdown first
            BuildPopup()
            popup:Show()
            activeSimpleDropdown = popup
        end
    end)

    -- Hover effects
    btn:SetScript("OnEnter", function()
        btn:SetBackdropBorderColor(0.5, 0.8, 0.5, 1)
    end)
    btn:SetScript("OnLeave", function()
        btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    end)

    -- Click outside to close
    popup:SetScript("OnShow", function()
        popup:SetScript("OnUpdate", function(self)
            if not self:IsMouseOver() and not btn:IsMouseOver() and IsMouseButtonDown("LeftButton") then
                CloseSimpleDropdown()
            end
        end)
    end)
    popup:SetScript("OnHide", function()
        popup:SetScript("OnUpdate", nil)
    end)

    UpdateDisplay()
    btn.UpdateDisplay = UpdateDisplay
    btn.SetCurrentValue = function(self, val)
        currentValue = val
        UpdateDisplay()
    end
    btn.SetOptions = function(self, opts)
        options = opts
    end
    btn.SetOnSelect = function(self, callback)
        onSelect = callback
    end

    return btn
end

--------------------------------------------------------------------------------
-- Simple UIDropDownMenu wrapper (for boolean True/False menus)
--------------------------------------------------------------------------------

local menuFrame = nil

local function GetMenuFrame()
    if not menuFrame then
        menuFrame = CreateFrame("Frame", "ScooterRulesMenuFrame", UIParent, "UIDropDownMenuTemplate")
    end
    return menuFrame
end

local function InitializeMenu(self, level, menuList)
    level = level or 1
    local entries = menuList or activeMenuData
    if not entries then return end

    for _, entry in ipairs(entries) do
        local info = UIDropDownMenu_CreateInfo()
        info.text = entry.text
        info.isTitle = entry.isTitle
        info.notCheckable = entry.notCheckable
        info.disabled = entry.disabled
        info.icon = entry.icon
        info.keepShownOnClick = entry.keepShownOnClick
        info.colorCode = entry.colorCode

        if entry.checked ~= nil then
            info.checked = entry.checked
        end

        if entry.func then
            info.func = entry.func
        end

        UIDropDownMenu_AddButton(info, level)
    end
end

local function OpenMenu(anchor, menuEntries)
    if not menuEntries then return end

    activeMenuData = menuEntries
    local frame = GetMenuFrame()

    UIDropDownMenu_Initialize(frame, InitializeMenu, "MENU")
    ToggleDropDownMenu(1, nil, frame, anchor, 0, 0)
end

--------------------------------------------------------------------------------
-- Custom Spec Picker Popup (Grid Layout)
--------------------------------------------------------------------------------

local specPickerFrame = nil
local specPickerRule = nil
local specPickerCallback = nil

local SPECS_PER_ROW = 3
local SPEC_BUTTON_WIDTH = 130
local SPEC_BUTTON_HEIGHT = 22
local CLASS_HEADER_HEIGHT = 20

local function CloseSpecPicker()
    if specPickerFrame then
        specPickerFrame:Hide()
    end
    specPickerRule = nil
    specPickerCallback = nil
end

local function CreateSpecPicker()
    if specPickerFrame then return specPickerFrame end

    local frame = CreateFrame("Frame", "ScooterSpecPickerFrame", UIParent, "BackdropTemplate")
    frame:SetSize(420, 400)
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(100)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0.1, 0.1, 0.1, 0.98)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)

    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", frame, "TOP", 0, -10)
    title:SetText("Select Specializations")
    StyleLabel(title, 14)
    frame.Title = title

    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", CloseSpecPicker)

    -- Scroll frame for content
    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -36)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 10)
    frame.ScrollFrame = scrollFrame

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(380, 800) -- Will be adjusted dynamically
    scrollFrame:SetScrollChild(content)
    frame.Content = content

    -- Click outside to close
    frame:SetScript("OnShow", function()
        frame:SetScript("OnUpdate", function(self, elapsed)
            if not self:IsMouseOver() and IsMouseButtonDown("LeftButton") then
                CloseSpecPicker()
            end
        end)
    end)
    frame:SetScript("OnHide", function()
        frame:SetScript("OnUpdate", nil)
    end)

    specPickerFrame = frame
    return frame
end

local function PopulateSpecPicker(rule, callback)
    local frame = CreateSpecPicker()
    local content = frame.Content

    -- Clear existing content
    if content.buttons then
        for _, btn in ipairs(content.buttons) do
            btn:Hide()
        end
    end
    content.buttons = {}

    -- Get selected specs
    local selected = {}
    if rule and rule.trigger and rule.trigger.specIds then
        for _, id in ipairs(rule.trigger.specIds) do
            selected[id] = true
        end
    end

    -- Get spec data
    local buckets = addon.Rules and addon.Rules:GetSpecBuckets() or {}

    local yOffset = -5
    for _, classEntry in ipairs(buckets) do
        -- Class header
        local header = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        header:SetPoint("TOPLEFT", content, "TOPLEFT", 5, yOffset)
        header:SetText(classEntry.name)
        if panel and panel.GetClassColor then
            local r, g, b = panel.GetClassColor(classEntry.file)
            header:SetTextColor(r, g, b, 1)
        end
        table.insert(content.buttons, header)
        yOffset = yOffset - CLASS_HEADER_HEIGHT

        -- Spec buttons in rows
        local specsInClass = classEntry.specs or {}
        for i, spec in ipairs(specsInClass) do
            local col = ((i - 1) % SPECS_PER_ROW)
            local row = math.floor((i - 1) / SPECS_PER_ROW)

            if col == 0 and i > 1 then
                yOffset = yOffset - SPEC_BUTTON_HEIGHT - 2
            end

            local btn = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
            btn:SetSize(22, 22)
            btn:SetPoint("TOPLEFT", content, "TOPLEFT", 10 + (col * SPEC_BUTTON_WIDTH), yOffset)
            btn:SetChecked(selected[spec.specID] and true or false)

            -- Icon
            local icon = btn:CreateTexture(nil, "ARTWORK")
            icon:SetSize(16, 16)
            icon:SetPoint("LEFT", btn, "RIGHT", 2, 0)
            if spec.icon then
                icon:SetTexture(spec.icon)
            end

            -- Name
            local name = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            name:SetPoint("LEFT", icon, "RIGHT", 4, 0)
            name:SetText(spec.name)
            name:SetWidth(80)
            name:SetJustifyH("LEFT")
            name:SetWordWrap(false)
            if panel and panel.GetClassColor then
                local r, g, b = panel.GetClassColor(classEntry.file)
                name:SetTextColor(r, g, b, 1)
            end

            btn:SetScript("OnClick", function(self)
                if addon.Rules and addon.Rules.ToggleRuleSpec then
                    addon.Rules:ToggleRuleSpec(rule.id, spec.specID)
                    if callback then callback() end
                end
            end)

            table.insert(content.buttons, btn)
            table.insert(content.buttons, icon)
            table.insert(content.buttons, name)
        end

        -- Move to next class
        local rowsForClass = math.ceil(#specsInClass / SPECS_PER_ROW)
        yOffset = yOffset - (SPEC_BUTTON_HEIGHT + 2) - 8
    end

    -- Adjust content height
    content:SetHeight(math.abs(yOffset) + 20)
end

local function OpenSpecPicker(anchor, rule, callback)
    specPickerRule = rule
    specPickerCallback = callback

    PopulateSpecPicker(rule, callback)

    local frame = specPickerFrame
    frame:ClearAllPoints()
    -- Position below the anchor
    frame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -5)
    frame:Show()
end

--------------------------------------------------------------------------------
-- Spec Badge Widget Factory
--------------------------------------------------------------------------------

local function CreateSpecBadge(parent, specID)
    if not parent or not specID then return nil end

    -- Get spec info
    local specEntry = nil
    if addon.Rules and addon.Rules.GetSpecBuckets then
        local _, specById = addon.Rules:GetSpecBuckets()
        specEntry = specById and specById[specID]
    end

    if not specEntry then return nil end

    local badge = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    badge:SetSize(80, 22)
    badge:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    badge.specID = specID
    badge.specEntry = specEntry

    -- Apply class-colored theme
    if panel and panel.ApplySpecBadgeTheme then
        panel.ApplySpecBadgeTheme(badge, specEntry.file or specEntry.classFile)
    end

    -- Spec icon (16x16)
    local icon = badge:CreateTexture(nil, "ARTWORK")
    icon:SetSize(16, 16)
    icon:SetPoint("LEFT", badge, "LEFT", 3, 0)
    if specEntry.icon then
        icon:SetTexture(specEntry.icon)
    end
    badge.Icon = icon

    -- Spec name (short)
    local name = badge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    name:SetPoint("LEFT", icon, "RIGHT", 3, 0)
    name:SetPoint("RIGHT", badge, "RIGHT", -3, 0)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    local shortName = specEntry.name or tostring(specID)
    name:SetText(shortName)
    -- Use white text for contrast against class-colored background
    name:SetTextColor(1, 1, 1, 1)
    badge.Name = name

    -- Tooltip on hover
    badge:EnableMouse(true)
    badge:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(specEntry.className or "Unknown Class", 1, 1, 1)
        GameTooltip:AddLine(specEntry.name or "Unknown Spec", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    badge:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return badge
end

--------------------------------------------------------------------------------
-- Action Path Helpers
--------------------------------------------------------------------------------

local function GetActionLeafAndPath(actionId)
    if not addon.Rules then return "Select Target", "" end
    local meta = addon.Rules:GetActionMetadata(actionId)
    if not meta or not meta.path then
        return "Select Target", ""
    end
    local path = meta.path
    local leaf = path[#path] or "Unknown"
    local parentPath = ""
    if #path > 1 then
        local parents = {}
        for i = 1, #path - 1 do
            table.insert(parents, path[i])
        end
        parentPath = table.concat(parents, " › ")
    end
    return leaf, parentPath
end

--------------------------------------------------------------------------------
-- Menu Builders
--------------------------------------------------------------------------------

local function BuildSpecMenu(rule, callback)
    local buckets = addon.Rules and addon.Rules:GetSpecBuckets() or {}
    local selected = {}
    if rule and rule.trigger and rule.trigger.specIds then
        for _, id in ipairs(rule.trigger.specIds) do
            selected[id] = true
        end
    end

    local entries = {}
    for _, classEntry in ipairs(buckets) do
        table.insert(entries, {
            text = classEntry.name,
            isTitle = true,
            notCheckable = true,
            colorCode = "|c" .. (classEntry.colorHex or "ffffffff"),
        })
        for _, spec in ipairs(classEntry.specs or {}) do
            table.insert(entries, {
                text = spec.name,
                icon = spec.icon,
                keepShownOnClick = true,
                colorCode = "|c" .. (spec.classColorHex or "ffffffff"),
                checked = selected[spec.specID] and true or false,
                func = function()
                    if addon.Rules and addon.Rules.ToggleRuleSpec then
                        addon.Rules:ToggleRuleSpec(rule.id, spec.specID)
                        if callback then callback() end
                    end
                end,
            })
        end
        table.insert(entries, { text = " ", notCheckable = true, disabled = true })
    end

    if #entries == 0 then
        table.insert(entries, {
            text = "Specialization data unavailable",
            notCheckable = true,
            disabled = true,
        })
    end

    return entries
end

local function BuildBooleanMenu(currentValue, setter, callback)
    local entries = {}
    local values = { { label = "True", value = true }, { label = "False", value = false } }
    for _, data in ipairs(values) do
        table.insert(entries, {
            text = data.label,
            checked = (currentValue == data.value),
            func = function()
                setter(data.value)
                if callback then callback() end
            end,
        })
    end
    return entries
end

--------------------------------------------------------------------------------
-- Display Mode Card (Compact View)
--------------------------------------------------------------------------------

local function RenderDisplayModeCard(card, rule, frame, refreshCard)
    -- Clear any edit mode elements
    if card.TriggerSection then card.TriggerSection:Hide() end
    if card.ActionSection then card.ActionSection:Hide() end
    if card.ValueSection then card.ValueSection:Hide() end
    if card.DoneBtn then card.DoneBtn:Hide() end
    if card.DeleteBtn then card.DeleteBtn:Hide() end

    -- === HEADER ROW ===
    -- "Enabled?" label on the left
    local enabledLabel = card.EnabledLabel
    if not enabledLabel then
        enabledLabel = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        enabledLabel:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -12)
        enabledLabel:SetText("Enabled?")
        card.EnabledLabel = enabledLabel
    end
    StyleLabel(enabledLabel, 11)
    enabledLabel:Show()

    -- Enable checkbox on the right of the label
    local enabledCheck = card.EnabledCheck
    if not enabledCheck then
        enabledCheck = CreateFrame("CheckButton", nil, card, "UICheckButtonTemplate")
        enabledCheck:SetScale(0.9)
        card.EnabledCheck = enabledCheck
    end
    enabledCheck:ClearAllPoints()
    enabledCheck:SetPoint("LEFT", enabledLabel, "RIGHT", 4, 0)
    enabledCheck:SetChecked(rule.enabled ~= false)
    enabledCheck:SetScript("OnClick", function(btn)
        if addon.Rules and addon.Rules.SetRuleEnabled then
            addon.Rules:SetRuleEnabled(rule.id, btn:GetChecked())
        end
    end)
    enabledCheck:Show()

    -- Hide title in display mode (rule names removed)
    if card.Title then card.Title:Hide() end

    -- Edit button (right side)
    local editBtn = card.EditBtn
    if not editBtn then
        editBtn = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
        editBtn:SetSize(50, 22)
        editBtn:SetPoint("TOPRIGHT", card, "TOPRIGHT", -10, -8)
        editBtn:SetText("Edit")
        applyButtonTheme(editBtn)
        card.EditBtn = editBtn
    end
    editBtn:SetScript("OnClick", function()
        editingRules[rule.id] = true
        refreshCard()
    end)
    editBtn:Show()

    -- === WHEN ROW ===
    local whenLabel = card.WhenLabel
    if not whenLabel then
        whenLabel = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        whenLabel:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -38)
        whenLabel:SetText("WHEN")
        card.WhenLabel = whenLabel
    end
    StyleLabel(whenLabel, 13)
    whenLabel:SetTextColor(0.5, 0.8, 0.5, 1)
    whenLabel:Show()

    local triggerType = rule.trigger and rule.trigger.type or "specialization"

    -- Player Level display text (shown for playerLevel triggers)
    local playerLevelText = card.PlayerLevelText
    if not playerLevelText then
        playerLevelText = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        playerLevelText:SetPoint("LEFT", whenLabel, "RIGHT", 12, 0)
        card.PlayerLevelText = playerLevelText
    end

    -- Spec badges container (shown for specialization triggers)
    local specContainer = card.SpecBadgeContainer
    if not specContainer then
        specContainer = CreateFrame("Frame", nil, card)
        specContainer:SetPoint("LEFT", whenLabel, "RIGHT", 12, 0)
        specContainer:SetSize(500, 24)
        card.SpecBadgeContainer = specContainer
    end
    -- Clear old badges
    if specContainer.badges then
        for _, badge in ipairs(specContainer.badges) do
            badge:Hide()
            badge:SetParent(nil)
        end
    end
    specContainer.badges = {}

    -- Show content based on trigger type
    if triggerType == "playerLevel" then
        -- Hide spec container and show player level text
        specContainer:Hide()
        if specContainer.OverflowText then specContainer.OverflowText:Hide() end
        if specContainer.NoSpecText then specContainer.NoSpecText:Hide() end

        local levelVal = rule.trigger and rule.trigger.level
        if levelVal then
            playerLevelText:SetText(string.format("Player Level |cff88ff88=|r %d", levelVal))
        else
            playerLevelText:SetText("Player Level |cff88ff88=|r |cff888888(not set)|r")
        end
        StyleLabel(playerLevelText, 12)
        playerLevelText:Show()

    else  -- specialization
        -- Hide player level text and show spec container
        playerLevelText:Hide()
        specContainer:Show()

        -- Create badges for selected specs (with overflow handling)
        local specIds = rule.trigger and rule.trigger.specIds or {}
        local xOffset = 0
        local visibleCount = math.min(#specIds, MAX_DISPLAY_BADGES)

        for i = 1, visibleCount do
            local specID = specIds[i]
            local badge = CreateSpecBadge(specContainer, specID)
            if badge then
                badge:SetPoint("LEFT", specContainer, "LEFT", xOffset, 0)
                badge:Show()
                table.insert(specContainer.badges, badge)
                xOffset = xOffset + badge:GetWidth() + 4
            end
        end

        -- Show "+X more" overflow indicator
        local overflowCount = #specIds - visibleCount
        local overflowText = specContainer.OverflowText
        if not overflowText then
            overflowText = CreateFrame("Frame", nil, specContainer, "BackdropTemplate")
            overflowText:SetSize(60, 24)
            overflowText:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
                insets = { left = 1, right = 1, top = 1, bottom = 1 },
            })
            overflowText:SetBackdropColor(0.2, 0.2, 0.2, 0.8)
            overflowText:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
            local text = overflowText:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            text:SetPoint("CENTER")
            overflowText.Text = text
            overflowText:EnableMouse(true)
            specContainer.OverflowText = overflowText
        end

        if overflowCount > 0 then
            overflowText:SetPoint("LEFT", specContainer, "LEFT", xOffset, 0)
            overflowText.Text:SetText(string.format("+%d more", overflowCount))
            StyleLabel(overflowText.Text, 10)

            -- Copy the overflow spec IDs for the tooltip (not a reference)
            local overflowSpecIds = {}
            for i = visibleCount + 1, #specIds do
                table.insert(overflowSpecIds, specIds[i])
            end
            overflowText.overflowSpecIds = overflowSpecIds

            overflowText:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:AddLine("Additional Specs:", 1, 0.82, 0) -- Gold header with explicit RGB

                -- Build a single multiline body string so we reuse one font string
                local lines = {}
                if addon.Rules then
                    local _, specById = addon.Rules:GetSpecBuckets()
                    if self.overflowSpecIds and specById then
                        for _, specID in ipairs(self.overflowSpecIds) do
                            local entry = specById[specID]
                            if entry and entry.name then
                                local className = entry.className or ""
                                if className ~= "" then
                                    table.insert(lines, entry.name .. " (" .. className .. ")")
                                else
                                    table.insert(lines, entry.name)
                                end
                            end
                        end
                    end
                end

                if #lines > 0 then
                    GameTooltip:AddLine(table.concat(lines, "\n"), 0.8, 0.8, 0.8)
                end

                GameTooltip:Show()
            end)
            overflowText:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)
            overflowText:Show()
        else
            overflowText:Hide()
        end

        -- Show placeholder if no specs selected
        if #specIds == 0 then
            local noSpecText = specContainer.NoSpecText
            if not noSpecText then
                noSpecText = specContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                noSpecText:SetPoint("LEFT", specContainer, "LEFT", 0, 0)
                specContainer.NoSpecText = noSpecText
            end
            noSpecText:SetText("(no specs selected)")
            StyleLabelMuted(noSpecText, 11)
            noSpecText:Show()
        elseif specContainer.NoSpecText then
            specContainer.NoSpecText:Hide()
        end
    end

    -- === DO ROW ===
    local doLabel = card.DoLabel
    if not doLabel then
        doLabel = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        doLabel:SetPoint("TOPLEFT", whenLabel, "BOTTOMLEFT", 0, -18)
        doLabel:SetText("DO")
        card.DoLabel = doLabel
    end
    StyleLabel(doLabel, 13)
    doLabel:SetTextColor(0.5, 0.8, 0.5, 1)
    doLabel:Show()

    -- Action leaf name + value (using FormatActionValueForDisplay for scalability)
    local actionId = rule.action and rule.action.id
    local leaf, parentPath = GetActionLeafAndPath(actionId)
    local displayText, colorValue = FormatActionValueForDisplay(actionId, rule.action and rule.action.value)

    local actionText = card.ActionText
    if not actionText then
        actionText = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        actionText:SetPoint("LEFT", doLabel, "RIGHT", 28, 0)
        card.ActionText = actionText
    end

    -- Handle color values with inline swatch, otherwise show text
    local colorSwatch = card.DoColorSwatch
    if colorValue then
        -- Color type: show "Setting = [swatch]"
        actionText:SetText(string.format("%s |cff88ff88=|r", leaf))
    StyleLabel(actionText, 12)
    actionText:Show()

        if not colorSwatch then
            colorSwatch = CreateFrame("Frame", nil, card, "BackdropTemplate")
            colorSwatch:SetSize(24, 14)
            colorSwatch:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
                insets = { left = 1, right = 1, top = 1, bottom = 1 },
            })
            colorSwatch:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
            card.DoColorSwatch = colorSwatch
        end
        colorSwatch:ClearAllPoints()
        colorSwatch:SetPoint("LEFT", actionText, "RIGHT", 4, 0)
        local r, g, b, a = colorValue[1] or 1, colorValue[2] or 1, colorValue[3] or 1, colorValue[4] or 1
        colorSwatch:SetBackdropColor(r, g, b, a)
        colorSwatch:Show()
    else
        -- Non-color type: show "Setting = Value"
        actionText:SetText(string.format("%s |cff88ff88=|r %s", leaf, displayText or "?"))
        StyleLabel(actionText, 12)
        actionText:Show()

        if colorSwatch then
            colorSwatch:Hide()
        end
    end

    -- Parent path (muted, smaller)
    local pathText = card.PathText
    if not pathText then
        pathText = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        pathText:SetPoint("TOPLEFT", actionText, "BOTTOMLEFT", 0, -2)
        card.PathText = pathText
    end
    if parentPath and parentPath ~= "" then
        pathText:SetText("|cff88ff88@|r " .. parentPath)
        StyleLabelMuted(pathText, 10)
        pathText:Show()
    else
        pathText:Hide()
    end
end

--------------------------------------------------------------------------------
-- Edit Mode Card (Expanded View)
--------------------------------------------------------------------------------

local function RenderEditModeCard(card, rule, frame, refreshCard)
    -- Hide display-mode specific elements
    if card.WhenLabel then card.WhenLabel:Hide() end
    if card.SpecBadgeContainer then card.SpecBadgeContainer:Hide() end
    if card.PlayerLevelText then card.PlayerLevelText:Hide() end
    if card.DoLabel then card.DoLabel:Hide() end
    if card.ActionText then card.ActionText:Hide() end
    if card.PathText then card.PathText:Hide() end
    if card.EditBtn then card.EditBtn:Hide() end
    if card.EnabledLabel then card.EnabledLabel:Hide() end

    -- === HEADER ROW ===
    -- Hide title in edit mode (rule names removed)
    if card.Title then card.Title:Hide() end

    -- Delete button
    local deleteBtn = card.DeleteBtn
    if not deleteBtn then
        deleteBtn = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
        deleteBtn:SetSize(60, 22)
        deleteBtn:SetText("Delete")
        applyButtonTheme(deleteBtn)
        card.DeleteBtn = deleteBtn
    end
    deleteBtn:ClearAllPoints()
    deleteBtn:SetPoint("TOPRIGHT", card, "TOPRIGHT", -70, -8)
    deleteBtn:SetScript("OnClick", function()
        -- Use ScooterMod's custom dialog to avoid tainting StaticPopupDialogs
        if addon.Dialogs and addon.Dialogs.Show then
            addon.Dialogs:Show("SCOOTERMOD_DELETE_RULE", {
                onAccept = function()
                    if rule.id and addon.Rules and addon.Rules.DeleteRule then
                        editingRules[rule.id] = nil
                        breadcrumbSelections[rule.id] = nil
                        addon.Rules:DeleteRule(rule.id)
                        if type(refreshCard) == "function" then
                            refreshCard()
                        end
                    end
                end,
            })
        end
    end)
    deleteBtn:Show()

    -- Done button
    local doneBtn = card.DoneBtn
    if not doneBtn then
        doneBtn = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
        doneBtn:SetSize(50, 22)
        doneBtn:SetText("Done")
        applyButtonTheme(doneBtn)
        card.DoneBtn = doneBtn
    end
    doneBtn:ClearAllPoints()
    doneBtn:SetPoint("TOPRIGHT", card, "TOPRIGHT", -10, -8)
    doneBtn:SetScript("OnClick", function()
        editingRules[rule.id] = nil
        refreshCard()
    end)
    doneBtn:Show()

    -- Hide enable checkbox in edit mode (or show if desired)
    if card.EnabledCheck then card.EnabledCheck:Hide() end

    -- === TRIGGER SECTION ===
    local triggerSection = card.TriggerSection
    if not triggerSection then
        triggerSection = CreateFrame("Frame", nil, card, "BackdropTemplate")
        triggerSection:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -38)
        triggerSection:SetPoint("TOPRIGHT", card, "TOPRIGHT", -10, -38)
        triggerSection:SetHeight(84)
        triggerSection:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        triggerSection:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
        triggerSection:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.5)
        card.TriggerSection = triggerSection
    end
    triggerSection:Show()

    -- Trigger header
    local triggerHeader = triggerSection.Header
    if not triggerHeader then
        triggerHeader = triggerSection:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        triggerHeader:SetPoint("TOPLEFT", triggerSection, "TOPLEFT", 8, -6)
        triggerHeader:SetText("TRIGGER")
        triggerSection.Header = triggerHeader
    end
    StyleLabel(triggerHeader, 14)
    triggerHeader:SetTextColor(0.5, 0.8, 0.5, 1)
    triggerHeader:Show()

    -- Type label + dropdown
    local typeLabel = triggerSection.TypeLabel
    if not typeLabel then
        typeLabel = triggerSection:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        typeLabel:SetPoint("TOPLEFT", triggerHeader, "BOTTOMLEFT", 0, -10)
        typeLabel:SetText("Type:")
        triggerSection.TypeLabel = typeLabel
    end
    StyleLabel(typeLabel, 11)
    typeLabel:Show()

    -- Hide the old static typeValue if it exists
    if triggerSection.TypeValue then
        triggerSection.TypeValue:Hide()
    end

    -- Trigger type dropdown
    local triggerType = rule.trigger and rule.trigger.type or "specialization"
    local typeDropdownOptions = {
        { text = "Specialization", value = "specialization" },
        { text = "Player Level", value = "playerLevel" },
    }

    local typeDropdown = triggerSection.TypeDropdown
    if not typeDropdown then
        typeDropdown = CreateSimpleDropdown(
            triggerSection,
            typeDropdownOptions,
            triggerType,
            nil,  -- Callback set below
            "Select Type..."
        )
        typeDropdown:SetSize(130, 22)
        triggerSection.TypeDropdown = typeDropdown
    end
    typeDropdown:ClearAllPoints()
    typeDropdown:SetPoint("LEFT", typeLabel, "RIGHT", 6, 0)
    typeDropdown:SetOptions(typeDropdownOptions)
    typeDropdown:SetCurrentValue(triggerType)
    -- Update callback with current rule.id (important when card is reused)
    typeDropdown:SetOnSelect(function(opt)
        if addon.Rules and addon.Rules.SetRuleTriggerType then
            addon.Rules:SetRuleTriggerType(rule.id, opt.value)
        end
        refreshCard()
    end)
    typeDropdown:Show()

    -- === SPECIALIZATION-SPECIFIC CONTROLS ===
    -- Specs row with badges (only shown for specialization trigger)
    local specsLabel = triggerSection.SpecsLabel
    if not specsLabel then
        specsLabel = triggerSection:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        specsLabel:SetPoint("TOPLEFT", typeLabel, "BOTTOMLEFT", 0, -12)
        specsLabel:SetText("Specs:")
        triggerSection.SpecsLabel = specsLabel
    end
    StyleLabel(specsLabel, 11)

    -- Add/Remove Specs button
    local addSpecBtn = triggerSection.AddSpecBtn
    if not addSpecBtn then
        addSpecBtn = CreateFrame("Button", nil, triggerSection, "UIPanelButtonTemplate")
        addSpecBtn:SetSize(115, 22)
        addSpecBtn:SetText("Add/Remove")
        applyButtonTheme(addSpecBtn)
        triggerSection.AddSpecBtn = addSpecBtn
    end
    addSpecBtn:ClearAllPoints()
    addSpecBtn:SetPoint("LEFT", specsLabel, "RIGHT", 8, 0)
    addSpecBtn:SetScript("OnClick", function()
        CloseSpecPicker()
        OpenSpecPicker(triggerSection, rule, refreshCard)
    end)

    -- Edit mode spec badges container
    local editSpecContainer = triggerSection.SpecBadgeContainer
    if not editSpecContainer then
        editSpecContainer = CreateFrame("Frame", nil, triggerSection)
        editSpecContainer:SetSize(320, 22)
        triggerSection.SpecBadgeContainer = editSpecContainer
    end
    editSpecContainer:ClearAllPoints()
    editSpecContainer:SetPoint("LEFT", addSpecBtn, "RIGHT", 8, 0)

    -- Clear old badges
    if editSpecContainer.badges then
        for _, badge in ipairs(editSpecContainer.badges) do
            badge:Hide()
            badge:SetParent(nil)
        end
    end
    editSpecContainer.badges = {}

    -- === PLAYER LEVEL-SPECIFIC CONTROLS ===
    -- Level label
    local levelLabel = triggerSection.LevelLabel
    if not levelLabel then
        levelLabel = triggerSection:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        levelLabel:SetPoint("TOPLEFT", typeLabel, "BOTTOMLEFT", 0, -12)
        levelLabel:SetText("Level:")
        triggerSection.LevelLabel = levelLabel
    end
    StyleLabel(levelLabel, 11)

    -- Level input editbox
    local levelInput = triggerSection.LevelInput
    if not levelInput then
        levelInput = CreateFrame("EditBox", nil, triggerSection, "InputBoxTemplate")
        levelInput:SetSize(60, 22)
        levelInput:SetAutoFocus(false)
        levelInput:SetNumeric(true)
        levelInput:SetMaxLetters(3)
        triggerSection.LevelInput = levelInput
    end
    levelInput:ClearAllPoints()
    levelInput:SetPoint("LEFT", levelLabel, "RIGHT", 8, 0)
    local currentLevel = rule.trigger and rule.trigger.level
    levelInput:SetText(currentLevel and tostring(currentLevel) or "")
    levelInput:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText())
        if addon.Rules and addon.Rules.SetRuleTriggerLevel then
            addon.Rules:SetRuleTriggerLevel(rule.id, val)
        end
        self:ClearFocus()
        refreshCard()
    end)
    levelInput:SetScript("OnEscapePressed", function(self)
        self:SetText(currentLevel and tostring(currentLevel) or "")
        self:ClearFocus()
    end)

    -- Show/hide controls based on trigger type
    if triggerType == "specialization" then
        specsLabel:Show()
        addSpecBtn:Show()
        editSpecContainer:Show()
        levelLabel:Hide()
        levelInput:Hide()

        -- Create badges (with overflow handling)
        local specIds = rule.trigger and rule.trigger.specIds or {}
        local xOffset = 0
        local visibleCount = math.min(#specIds, MAX_EDIT_BADGES)

        for i = 1, visibleCount do
            local specID = specIds[i]
            local badge = CreateSpecBadge(editSpecContainer, specID)
            if badge then
                badge:SetPoint("LEFT", editSpecContainer, "LEFT", xOffset, 0)
                badge:Show()
                table.insert(editSpecContainer.badges, badge)
                xOffset = xOffset + badge:GetWidth() + 4
            end
        end

        -- Show "+X more" overflow indicator in edit mode
        local overflowCount = #specIds - visibleCount
        local editOverflow = editSpecContainer.OverflowText
        if not editOverflow then
            editOverflow = CreateFrame("Frame", nil, editSpecContainer, "BackdropTemplate")
            editOverflow:SetSize(55, 22)
            editOverflow:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
                insets = { left = 1, right = 1, top = 1, bottom = 1 },
            })
            editOverflow:SetBackdropColor(0.2, 0.2, 0.2, 0.8)
            editOverflow:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
            local text = editOverflow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            text:SetPoint("CENTER")
            editOverflow.Text = text
            editOverflow:EnableMouse(true)
            editSpecContainer.OverflowText = editOverflow
        end

        if overflowCount > 0 then
            editOverflow:SetPoint("LEFT", editSpecContainer, "LEFT", xOffset, 0)
            editOverflow.Text:SetText(string.format("+%d more", overflowCount))
            StyleLabel(editOverflow.Text, 10)

            local overflowSpecIds = {}
            for i = visibleCount + 1, #specIds do
                table.insert(overflowSpecIds, specIds[i])
            end
            editOverflow.overflowSpecIds = overflowSpecIds

            editOverflow:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:AddLine("Additional Specs:", 1, 0.82, 0)
                local lines = {}
                if addon.Rules then
                    local _, specById = addon.Rules:GetSpecBuckets()
                    if self.overflowSpecIds and specById then
                        for _, specID in ipairs(self.overflowSpecIds) do
                            local entry = specById[specID]
                            if entry and entry.name then
                                local className = entry.className or ""
                                if className ~= "" then
                                    table.insert(lines, entry.name .. " (" .. className .. ")")
                                else
                                    table.insert(lines, entry.name)
                                end
                            end
                        end
                    end
                end
                if #lines > 0 then
                    GameTooltip:AddLine(table.concat(lines, "\n"), 0.8, 0.8, 0.8)
                end
                GameTooltip:Show()
            end)
            editOverflow:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)
            editOverflow:Show()
        elseif editOverflow then
            editOverflow:Hide()
        end

    elseif triggerType == "playerLevel" then
        specsLabel:Hide()
        addSpecBtn:Hide()
        editSpecContainer:Hide()
        if editSpecContainer.OverflowText then
            editSpecContainer.OverflowText:Hide()
        end
        levelLabel:Show()
        levelInput:Show()
    end

    -- === ACTION SECTION ===
    local actionSection = card.ActionSection
    if not actionSection then
        actionSection = CreateFrame("Frame", nil, card, "BackdropTemplate")
        actionSection:SetPoint("TOPLEFT", triggerSection, "BOTTOMLEFT", 0, -6)
        actionSection:SetPoint("TOPRIGHT", triggerSection, "BOTTOMRIGHT", 0, -6)
        actionSection:SetHeight(84)
        actionSection:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        actionSection:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
        actionSection:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.5)
        card.ActionSection = actionSection
    end
    actionSection:Show()

    -- Hide old elements if they exist (from previous implementation)
    if actionSection.ChangeTargetBtn then actionSection.ChangeTargetBtn:Hide() end
    if actionSection.SettingIndicator then actionSection.SettingIndicator:Hide() end
    if actionSection.TargetPath then actionSection.TargetPath:Hide() end

    -- Target header (was "ACTION", renamed for clarity)
    local actionHeader = actionSection.Header
    if not actionHeader then
        actionHeader = actionSection:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        actionHeader:SetPoint("TOPLEFT", actionSection, "TOPLEFT", 8, -6)
        actionSection.Header = actionHeader
    end
    actionHeader:SetText("TARGET")
    StyleLabel(actionHeader, 14)
    actionHeader:SetTextColor(0.5, 0.8, 0.5, 1)
    actionHeader:Show()

    -- Target label
    local targetLabel = actionSection.TargetLabel
    if not targetLabel then
        targetLabel = actionSection:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        targetLabel:SetPoint("TOPLEFT", actionHeader, "BOTTOMLEFT", 0, -10)
        targetLabel:SetText("Target:")
        actionSection.TargetLabel = targetLabel
    end
    StyleLabel(targetLabel, 11)
    targetLabel:Show()

    -- Get current action path (if any)
    local actionId = rule.action and rule.action.id
    local currentPath = {}
    if actionId and addon.Rules then
        currentPath = addon.Rules:GetActionPath(actionId)
    end

    -- Initialize breadcrumb state: use saved partial selection, or derive from complete action path
    local breadcrumbState
    if breadcrumbSelections[rule.id] then
        -- Use saved partial selection
        breadcrumbState = breadcrumbSelections[rule.id]
    elseif #currentPath > 0 then
        -- Derive from complete action path
        breadcrumbState = { currentPath[1], currentPath[2], currentPath[3], currentPath[4] }
    else
        -- Start fresh
        breadcrumbState = {}
    end

    -- Helper to build options for a given level
    local function GetOptionsForLevel(level)
        local pathPrefix = {}
        for i = 1, level - 1 do
            if breadcrumbState[i] then
                table.insert(pathPrefix, breadcrumbState[i])
            end
        end
        local rawOptions = addon.Rules and addon.Rules:GetActionsAtPath(pathPrefix) or {}
        local options = {}
        for _, opt in ipairs(rawOptions) do
            table.insert(options, { text = opt.text, value = opt.text, hasChildren = opt.hasChildren })
        end
        return options
    end

    -- Helper to update rule action when breadcrumb selection changes
    local function OnBreadcrumbChange(level, selectedText)
        -- Update state
        breadcrumbState[level] = selectedText
        -- Clear downstream selections
        for i = level + 1, 4 do
            breadcrumbState[i] = nil
        end

        -- Save the partial selection for persistence across re-renders
        breadcrumbSelections[rule.id] = breadcrumbState

        -- Check if we have a complete valid path
        local fullPath = {}
        for i = 1, 4 do
            if breadcrumbState[i] then
                table.insert(fullPath, breadcrumbState[i])
            else
                break
            end
        end

        -- Try to find matching action
        local newActionId = addon.Rules and addon.Rules:GetActionIdForPath(fullPath)
        if newActionId then
            -- Complete path found - clear partial selection storage (action.id is source of truth now)
            breadcrumbSelections[rule.id] = nil
            if addon.Rules and addon.Rules.SetRuleAction then
                addon.Rules:SetRuleAction(rule.id, newActionId)
            end
        else
            -- Clear the action if path is incomplete/invalid
            rule.action = rule.action or {}
            rule.action.id = nil
        end

        -- Refresh to update UI
        refreshCard()
    end

    -- Breadcrumb container
    local breadcrumbContainer = actionSection.BreadcrumbContainer
    if not breadcrumbContainer then
        breadcrumbContainer = CreateFrame("Frame", nil, actionSection)
        breadcrumbContainer:SetPoint("TOPLEFT", targetLabel, "BOTTOMLEFT", 0, -8)
        breadcrumbContainer:SetPoint("TOPRIGHT", actionSection, "TOPRIGHT", -10, 0)
        breadcrumbContainer:SetHeight(26)
        actionSection.BreadcrumbContainer = breadcrumbContainer
    end
    breadcrumbContainer:Show()

    -- Hide any existing breadcrumb elements
    for i = 1, 4 do
        if breadcrumbContainer["Dropdown" .. i] then
            breadcrumbContainer["Dropdown" .. i]:Hide()
        end
        if breadcrumbContainer["Separator" .. i] then
            breadcrumbContainer["Separator" .. i]:Hide()
        end
    end

    -- Calculate equal dropdown widths to fill available space
    -- Container width minus space for 3 separators (24px each = 72px total)
    local containerWidth = breadcrumbContainer:GetWidth()
    if containerWidth < 100 then containerWidth = 520 end  -- Fallback if not yet laid out
    local SEPARATOR_WIDTH = 24
    local DROPDOWN_WIDTH = math.floor((containerWidth - (3 * SEPARATOR_WIDTH)) / 4)

    -- Create/update breadcrumb dropdowns
    local xOffset = 0

    for level = 1, 4 do
        -- Only show this level if previous level has a selection (or it's level 1)
        local shouldShow = (level == 1) or (breadcrumbState[level - 1] ~= nil)

        if shouldShow then
            local options = GetOptionsForLevel(level)

            -- Only show if there are options available
            if #options > 0 or breadcrumbState[level] then
                local dropdown = breadcrumbContainer["Dropdown" .. level]
                if not dropdown then
                    dropdown = CreateSimpleDropdown(
                        breadcrumbContainer,
                        options,
                        breadcrumbState[level],
                        function(opt)
                            OnBreadcrumbChange(level, opt.text)
                        end,
                        "Select..."
                    )
                    breadcrumbContainer["Dropdown" .. level] = dropdown
                end

                -- Update dropdown
                dropdown:SetOptions(options)
                dropdown:SetCurrentValue(breadcrumbState[level])
                dropdown:SetSize(DROPDOWN_WIDTH, 22)
                dropdown:ClearAllPoints()
                dropdown:SetPoint("LEFT", breadcrumbContainer, "LEFT", xOffset, 0)
                dropdown:Show()

                -- Rebind click handler with current state
                dropdown:SetScript("OnClick", function()
                    -- Close any open dropdown first
                    CloseSimpleDropdown()

                    -- Rebuild options fresh
                    local freshOptions = GetOptionsForLevel(level)
                    dropdown:SetOptions(freshOptions)

                    -- Build and show popup
                    local popup = dropdown.Popup
                    if popup.optionButtons then
                        for _, optBtn in ipairs(popup.optionButtons) do
                            optBtn:Hide()
                        end
                    end
                    popup.optionButtons = {}

                    local yOff = -4
                    local maxW = dropdown:GetWidth() - 2

                    for _, opt in ipairs(freshOptions) do
                        local optBtn = CreateFrame("Button", nil, popup)
                        optBtn:SetHeight(20)
                        optBtn:SetPoint("TOPLEFT", popup, "TOPLEFT", 2, yOff)
                        optBtn:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -2, yOff)

                        local optText = optBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                        optText:SetPoint("LEFT", optBtn, "LEFT", 6, 0)
                        optText:SetPoint("RIGHT", optBtn, "RIGHT", -6, 0)
                        optText:SetJustifyH("LEFT")
                        optText:SetText(opt.text)

                        local textW = optText:GetStringWidth() + 20
                        if textW > maxW then maxW = textW end

                        local hl = optBtn:CreateTexture(nil, "HIGHLIGHT")
                        hl:SetAllPoints()
                        hl:SetColorTexture(0.3, 0.5, 0.3, 0.5)

                        if opt.text == breadcrumbState[level] then
                            optText:SetTextColor(0.5, 1, 0.5, 1)
                        else
                            optText:SetTextColor(0.9, 0.9, 0.9, 1)
                        end

                        optBtn:SetScript("OnClick", function()
                            CloseSimpleDropdown()
                            OnBreadcrumbChange(level, opt.text)
                        end)

                        table.insert(popup.optionButtons, optBtn)
                        yOff = yOff - 20
                    end

                    local popH = math.abs(yOff) + 6
                    popup:SetSize(math.max(maxW, dropdown:GetWidth()), popH)
                    popup:ClearAllPoints()
                    popup:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 0, -2)
                    popup:Show()
                    activeSimpleDropdown = popup
                end)

                xOffset = xOffset + DROPDOWN_WIDTH

                -- Add separator after dropdown (except after last one)
                if level < 4 and breadcrumbState[level] then
                    local sep = breadcrumbContainer["Separator" .. level]
                    if not sep then
                        sep = breadcrumbContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                        breadcrumbContainer["Separator" .. level] = sep
                    end
                    sep:ClearAllPoints()
                    sep:SetPoint("LEFT", breadcrumbContainer, "LEFT", xOffset + 6, 0)
                    sep:SetText(">")
                    StyleLabel(sep, 14)
                    sep:SetTextColor(0.5, 0.8, 0.5, 1)
                    sep:Show()
                    xOffset = xOffset + SEPARATOR_WIDTH
                end
            end
        end
    end

    -- === VALUE SECTION ===
    local valueSection = card.ValueSection
    if not valueSection then
        valueSection = CreateFrame("Frame", nil, card, "BackdropTemplate")
        valueSection:SetPoint("TOPLEFT", actionSection, "BOTTOMLEFT", 0, -6)
        valueSection:SetPoint("TOPRIGHT", actionSection, "BOTTOMRIGHT", 0, -6)
        valueSection:SetHeight(72)
        valueSection:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        valueSection:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
        valueSection:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.5)
        card.ValueSection = valueSection
    end
    valueSection:Show()

    -- Action header (was "VALUE", renamed for clarity: Trigger → Target → Action)
    local valueHeader = valueSection.Header
    if not valueHeader then
        valueHeader = valueSection:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        valueHeader:SetPoint("TOPLEFT", valueSection, "TOPLEFT", 8, -6)
        valueSection.Header = valueHeader
    end
    valueHeader:SetText("ACTION")
    StyleLabel(valueHeader, 14)
    valueHeader:SetTextColor(0.5, 0.8, 0.5, 1)
    valueHeader:Show()

    -- Hide old elements that are no longer used
    if valueSection.MatchLabel then valueSection.MatchLabel:Hide() end
    if valueSection.DefaultLabel then valueSection.DefaultLabel:Hide() end
    if valueSection.DefaultDropdown then valueSection.DefaultDropdown:Hide() end

    -- Get action metadata to determine which control to render
    local actionId = rule.action and rule.action.id
    local actionMeta = actionId and addon.Rules and addon.Rules:GetActionMetadata(actionId)
    local widget = actionMeta and actionMeta.widget or "checkbox"
    local currentValue = rule.action and rule.action.value

    -- Control container for dynamic widgets
    local controlContainer = valueSection.ControlContainer
    if not controlContainer then
        controlContainer = CreateFrame("Frame", nil, valueSection)
        controlContainer:SetPoint("TOPLEFT", valueHeader, "BOTTOMLEFT", 0, -10)
        controlContainer:SetPoint("TOPRIGHT", valueSection, "TOPRIGHT", -10, 0)
        controlContainer:SetHeight(30)
        valueSection.ControlContainer = controlContainer
    end
    controlContainer:Show()

    -- Hide all possible control types before showing the right one
    if controlContainer.CheckboxControl then controlContainer.CheckboxControl:Hide() end
    if controlContainer.SliderControl then controlContainer.SliderControl:Hide() end
    if controlContainer.DropdownControl then controlContainer.DropdownControl:Hide() end
    if controlContainer.ColorControl then controlContainer.ColorControl:Hide() end
    if valueSection.MatchDropdown then valueSection.MatchDropdown:Hide() end

    -- Render the appropriate control based on widget type
    if widget == "checkbox" then
        -- Checkbox control
        local checkControl = controlContainer.CheckboxControl
        if not checkControl then
            checkControl = CreateFrame("CheckButton", nil, controlContainer, "UICheckButtonTemplate")
            checkControl:SetScale(0.9)
            controlContainer.CheckboxControl = checkControl
        end
        checkControl:ClearAllPoints()
        checkControl:SetPoint("LEFT", controlContainer, "LEFT", 0, 0)
        checkControl:SetChecked(currentValue and true or false)
        checkControl:SetScript("OnClick", function(btn)
            if addon.Rules and addon.Rules.SetRuleActionValue then
                addon.Rules:SetRuleActionValue(rule.id, btn:GetChecked())
            end
        end)
        checkControl:Show()

        -- Label for the checkbox
        local checkLabel = controlContainer.CheckboxLabel
        if not checkLabel then
            checkLabel = controlContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            checkLabel:SetPoint("LEFT", checkControl, "RIGHT", 4, 0)
            controlContainer.CheckboxLabel = checkLabel
        end
        local leafName = actionMeta and actionMeta.path and actionMeta.path[#actionMeta.path] or "Enabled"
        checkLabel:SetText(leafName)
        StyleLabel(checkLabel, 11)
        checkLabel:Show()

    elseif widget == "slider" then
        -- Slider control
        local sliderControl = controlContainer.SliderControl
        if not sliderControl then
            sliderControl = CreateFrame("Slider", nil, controlContainer, "OptionsSliderTemplate")
            sliderControl:SetSize(200, 18)
            sliderControl:SetOrientation("HORIZONTAL")
            controlContainer.SliderControl = sliderControl
        end
        sliderControl:ClearAllPoints()
        sliderControl:SetPoint("LEFT", controlContainer, "LEFT", 0, 0)

        -- Get min/max/step from uiMeta
        local uiMeta = actionMeta and actionMeta.uiMeta or {}
        local minVal = uiMeta.min or 0
        local maxVal = uiMeta.max or 100
        local step = uiMeta.step or 1

        sliderControl:SetMinMaxValues(minVal, maxVal)
        sliderControl:SetValueStep(step)
        sliderControl:SetObeyStepOnDrag(true)
        sliderControl:SetValue(tonumber(currentValue) or minVal)

        -- Update low/high labels
        if sliderControl.Low then sliderControl.Low:SetText(tostring(minVal)) end
        if sliderControl.High then sliderControl.High:SetText(tostring(maxVal)) end
        if sliderControl.Text then
            local leafName = actionMeta and actionMeta.path and actionMeta.path[#actionMeta.path] or "Value"
            sliderControl.Text:SetText(leafName .. ": " .. tostring(math.floor(sliderControl:GetValue())))
        end

        sliderControl:SetScript("OnValueChanged", function(self, value)
            value = math.floor(value + 0.5)
            if self.Text then
                local leafName = actionMeta and actionMeta.path and actionMeta.path[#actionMeta.path] or "Value"
                self.Text:SetText(leafName .. ": " .. tostring(value))
            end
            if addon.Rules and addon.Rules.SetRuleActionValue then
                addon.Rules:SetRuleActionValue(rule.id, value)
            end
        end)
        sliderControl:Show()

    elseif widget == "dropdown" then
        -- Dropdown control (use existing simple dropdown pattern)
        local dropdownControl = controlContainer.DropdownControl
        if not dropdownControl then
            dropdownControl = CreateFrame("Button", nil, controlContainer, "UIPanelButtonTemplate")
            dropdownControl:SetSize(150, 22)
            applyButtonTheme(dropdownControl)
            controlContainer.DropdownControl = dropdownControl
        end
        dropdownControl:ClearAllPoints()
        dropdownControl:SetPoint("LEFT", controlContainer, "LEFT", 0, 0)

        -- Get dropdown values from uiMeta
        local uiMeta = actionMeta and actionMeta.uiMeta or {}
        local values = uiMeta.values or {}

        -- Show current value's display label
        local displayLabel = values[currentValue] or tostring(currentValue or "Select...")
        dropdownControl:SetText(displayLabel)

        dropdownControl:SetScript("OnClick", function()
            local menu = {}
            for key, label in pairs(values) do
                table.insert(menu, {
                    text = label,
                    checked = (currentValue == key),
                    func = function()
                        if addon.Rules and addon.Rules.SetRuleActionValue then
                            addon.Rules:SetRuleActionValue(rule.id, key)
                        end
                        refreshCard()
                    end,
                })
            end
            OpenMenu(dropdownControl, menu)
        end)
        dropdownControl:Show()

        -- Label
        local dropLabel = controlContainer.DropdownLabel
        if not dropLabel then
            dropLabel = controlContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            dropLabel:SetPoint("LEFT", dropdownControl, "RIGHT", 8, 0)
            controlContainer.DropdownLabel = dropLabel
        end
        local leafName = actionMeta and actionMeta.path and actionMeta.path[#actionMeta.path] or "Option"
        dropLabel:SetText(leafName)
        StyleLabel(dropLabel, 11)
        dropLabel:Show()

    elseif widget == "color" then
        -- Color swatch control
        local colorControl = controlContainer.ColorControl
        if not colorControl then
            colorControl = CreateFrame("Button", nil, controlContainer, "BackdropTemplate")
            colorControl:SetSize(48, 22)
            colorControl:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
                insets = { left = 1, right = 1, top = 1, bottom = 1 },
            })
            colorControl:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
            controlContainer.ColorControl = colorControl
        end
        colorControl:ClearAllPoints()
        colorControl:SetPoint("LEFT", controlContainer, "LEFT", 0, 0)

        -- Set current color
        local colorValue = currentValue
        if type(colorValue) ~= "table" then
            colorValue = { 1, 1, 1, 1 }
        end
        local r, g, b, a = colorValue[1] or 1, colorValue[2] or 1, colorValue[3] or 1, colorValue[4] or 1
        colorControl:SetBackdropColor(r, g, b, a)

        colorControl:SetScript("OnClick", function()
            -- Open color picker
            local info = {}
            info.hasOpacity = true
            info.opacity = 1 - (colorValue[4] or 1)
            info.r, info.g, info.b = colorValue[1] or 1, colorValue[2] or 1, colorValue[3] or 1
            info.swatchFunc = function()
                local newR, newG, newB = ColorPickerFrame:GetColorRGB()
                local newA = 1 - (ColorPickerFrame:GetColorAlpha() or 0)
                if addon.Rules and addon.Rules.SetRuleActionValue then
                    addon.Rules:SetRuleActionValue(rule.id, { newR, newG, newB, newA })
                end
                refreshCard()
            end
            info.opacityFunc = info.swatchFunc
            info.cancelFunc = function(prev)
                if addon.Rules and addon.Rules.SetRuleActionValue then
                    addon.Rules:SetRuleActionValue(rule.id, { prev.r, prev.g, prev.b, 1 - prev.opacity })
                end
                refreshCard()
            end
            ColorPickerFrame:SetupColorPickerAndShow(info)
        end)
        colorControl:Show()

        -- Label
        local colorLabel = controlContainer.ColorLabel
        if not colorLabel then
            colorLabel = controlContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            colorLabel:SetPoint("LEFT", colorControl, "RIGHT", 8, 0)
            controlContainer.ColorLabel = colorLabel
        end
        local leafName = actionMeta and actionMeta.path and actionMeta.path[#actionMeta.path] or "Color"
        colorLabel:SetText(leafName)
        StyleLabel(colorLabel, 11)
        colorLabel:Show()

    else
        -- Fallback: show the old boolean dropdown (legacy support)
    local matchDropdown = valueSection.MatchDropdown
    if not matchDropdown then
        matchDropdown = CreateFrame("Button", nil, valueSection, "UIPanelButtonTemplate")
        matchDropdown:SetSize(70, 22)
        applyButtonTheme(matchDropdown)
        valueSection.MatchDropdown = matchDropdown
    end
    matchDropdown:ClearAllPoints()
        matchDropdown:SetPoint("TOPLEFT", valueHeader, "BOTTOMLEFT", 0, -10)
        matchDropdown:SetText(currentValue and "True" or "False")
    matchDropdown:SetScript("OnClick", function()
            local menu = BuildBooleanMenu(currentValue, function(val)
            if addon.Rules and addon.Rules.SetRuleActionValue then
                    addon.Rules:SetRuleActionValue(rule.id, val)
            end
                end, refreshCard)
        OpenMenu(matchDropdown, menu)
    end)
    matchDropdown:Show()
    end
end

--------------------------------------------------------------------------------
-- Card Initializer (Two-State)
--------------------------------------------------------------------------------

local function CreateRuleCardInitializer(rule)
    local init = Settings.CreateElementInitializer("SettingsListElementTemplate")

    -- Dynamic height based on edit state
    init.GetExtent = function()
        if editingRules[rule.id] then
            return EDIT_MODE_HEIGHT
        else
            return DISPLAY_MODE_HEIGHT
        end
    end

    init.InitFrame = function(self, frame)
        ResetListRow(frame)
        frame.RuleId = rule.id

        -- Disable the SettingsListElementTemplate's built-in hover highlighting
        -- which appears as a jarring white overlay on the entire row.
        -- The template has a Tooltip child frame with a HoverBackground texture.
        if frame.Tooltip and frame.Tooltip.HoverBackground then
            frame.Tooltip.HoverBackground:Hide()
            frame.Tooltip.HoverBackground:SetAlpha(0)
        end

        -- === INDEX BADGE (outside the card, on the left) ===
        local indexBadge = frame.IndexBadge
        if not indexBadge then
            indexBadge = CreateFrame("Frame", nil, frame, "BackdropTemplate")
            indexBadge:SetSize(INDEX_BADGE_SIZE, INDEX_BADGE_SIZE)
            indexBadge:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
                insets = { left = 1, right = 1, top = 1, bottom = 1 },
            })
            indexBadge:SetBackdropColor(BADGE_BG_COLOR.r, BADGE_BG_COLOR.g, BADGE_BG_COLOR.b, BADGE_BG_COLOR.a)
            indexBadge:SetBackdropBorderColor(BADGE_BG_COLOR.r * 0.7, BADGE_BG_COLOR.g * 0.7, BADGE_BG_COLOR.b * 0.7, 1)

            local badgeText = indexBadge:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            badgeText:SetPoint("CENTER", indexBadge, "CENTER", 0, 0)
            badgeText:SetTextColor(BADGE_TEXT_COLOR.r, BADGE_TEXT_COLOR.g, BADGE_TEXT_COLOR.b, BADGE_TEXT_COLOR.a)
            indexBadge.Text = badgeText
            frame.IndexBadge = indexBadge
        end
        indexBadge:ClearAllPoints()
        indexBadge:SetPoint("TOPLEFT", frame, "TOPLEFT", INDEX_BADGE_LEFT_MARGIN, -CARD_VERTICAL_PADDING - 8)
        indexBadge.Text:SetText(tostring(rule.displayIndex or "?"))
        -- Apply clean font styling (no outline for better readability)
        if panel and panel.ApplyRoboto then
            panel.ApplyRoboto(indexBadge.Text, 13, "")
            indexBadge.Text:SetTextColor(BADGE_TEXT_COLOR.r, BADGE_TEXT_COLOR.g, BADGE_TEXT_COLOR.b, BADGE_TEXT_COLOR.a)
        end
        indexBadge:Show()

        -- === CARD CONTAINER (shifted right to make room for badge) ===
        local card = frame.RuleCard
        if not card then
            card = CreateFrame("Frame", nil, frame, "BackdropTemplate")
            card:SetBackdrop({
                bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
                edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                tile = true,
                tileSize = 16,
                edgeSize = 16,
                insets = { left = 4, right = 4, top = 4, bottom = 4 },
            })
            card:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
            frame.RuleCard = card
        end
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", frame, "TOPLEFT", CARD_LEFT_MARGIN, -CARD_VERTICAL_PADDING)
        card:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -CARD_RIGHT_MARGIN, CARD_VERTICAL_PADDING)
        card:Show()

        local function refreshCard()
            if panel and panel.RefreshCurrentCategoryDeferred then
                panel.RefreshCurrentCategoryDeferred()
            end
        end

        -- Render appropriate mode
        if editingRules[rule.id] then
            RenderEditModeCard(card, rule, frame, refreshCard)
        else
            RenderDisplayModeCard(card, rule, frame, refreshCard)
        end
    end

    return init
end

--------------------------------------------------------------------------------
-- Empty State & Add Button
--------------------------------------------------------------------------------

local function CreateEmptyStateInitializer()
    local init = Settings.CreateElementInitializer("SettingsListElementTemplate")
    init.GetExtent = function() return 80 end
    init.InitFrame = function(self, frame)
        ResetListRow(frame)
        local text = frame.EmptyText
        if not text then
            text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            text:SetPoint("CENTER")
            text:SetWidth(420)
            text:SetJustifyH("CENTER")
            text:SetText("No rules configured. Click 'Add Rule' to create your first automation.")
            frame.EmptyText = text
            StyleLabel(text)
        else
            text:Show()
        end
    end
    return init
end

--------------------------------------------------------------------------------
-- Divider Between Cards (Option D)
--------------------------------------------------------------------------------

local function CreateDividerInitializer()
    local init = Settings.CreateElementInitializer("SettingsListElementTemplate")
    init.GetExtent = function() return DIVIDER_HEIGHT end
    init.InitFrame = function(self, frame)
        ResetListRow(frame)

        -- Disable hover highlighting on divider rows
        if frame.Tooltip and frame.Tooltip.HoverBackground then
            frame.Tooltip.HoverBackground:Hide()
            frame.Tooltip.HoverBackground:SetAlpha(0)
        end

        -- === HORIZONTAL DIVIDER LINE (left half) ===
        local dividerLine = frame.DividerLine
        if not dividerLine then
            dividerLine = frame:CreateTexture(nil, "ARTWORK")
            dividerLine:SetHeight(1)
            dividerLine:SetColorTexture(0.20, 0.90, 0.30, 0.30)  -- Scooter green at 30% opacity
            frame.DividerLine = dividerLine
        end
        dividerLine:ClearAllPoints()
        dividerLine:SetPoint("LEFT", frame, "LEFT", CARD_LEFT_MARGIN, 0)
        dividerLine:SetPoint("RIGHT", frame, "CENTER", -12, 0)
        dividerLine:Show()

        -- === HORIZONTAL DIVIDER LINE (right half) ===
        local dividerLineRight = frame.DividerLineRight
        if not dividerLineRight then
            dividerLineRight = frame:CreateTexture(nil, "ARTWORK")
            dividerLineRight:SetHeight(1)
            dividerLineRight:SetColorTexture(0.20, 0.90, 0.30, 0.30)  -- Scooter green at 30% opacity
            frame.DividerLineRight = dividerLineRight
        end
        dividerLineRight:ClearAllPoints()
        dividerLineRight:SetPoint("LEFT", frame, "CENTER", 12, 0)
        dividerLineRight:SetPoint("RIGHT", frame, "RIGHT", -CARD_RIGHT_MARGIN, 0)
        dividerLineRight:Show()

        -- === CENTER ORNAMENT (small diamond texture) ===
        local ornament = frame.DividerOrnament
        if not ornament then
            ornament = frame:CreateTexture(nil, "OVERLAY")
            ornament:SetSize(10, 10)
            -- Use a simple rotated square texture as a diamond
            ornament:SetTexture("Interface\\Buttons\\WHITE8x8")
            ornament:SetVertexColor(0.20, 0.90, 0.30, 0.60)  -- Scooter green at 60% opacity
            ornament:SetRotation(math.rad(45))  -- Rotate 45 degrees to make diamond
            frame.DividerOrnament = ornament
        end
        ornament:ClearAllPoints()
        ornament:SetPoint("CENTER", frame, "CENTER", 0, 0)
        ornament:Show()
    end
    return init
end

local function CreateAddButtonInitializer()
    local init = Settings.CreateElementInitializer("SettingsListElementTemplate")
    init.GetExtent = function() return 50 end
    init.InitFrame = function(self, frame)
        ResetListRow(frame)
        local btn = frame.AddRuleBtn
        if not btn then
            btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
            btn:SetPoint("CENTER")
            btn:SetText("Add Rule")
            btn:SetScript("OnClick", function()
                if addon.Rules and addon.Rules.CreateRule then
                    local newRule = addon.Rules:CreateRule()
                    -- Auto-expand the new rule into edit mode
                    if newRule and newRule.id then
                        editingRules[newRule.id] = true
                    end
                    if panel and panel.RefreshCurrentCategoryDeferred then
                        panel.RefreshCurrentCategoryDeferred()
                    end
                end
            end)
            frame.AddRuleBtn = btn
            applyButtonTheme(btn)
        end
        if not btn._ScooterSized then
            btn:SetSize(200, 40)
            local text = btn.Text or btn:GetFontString()
            if text then
                local font, size, flags = text:GetFont()
                text:SetFont(font, math.floor((size or 14) * 1.2 + 0.5), flags)
            end
            btn._ScooterSized = true
        end
        btn:Show()
    end
    return init
end

--------------------------------------------------------------------------------
-- Main Renderer
--------------------------------------------------------------------------------

local function renderProfilesRules()
    local function render()
        local f = panel.frame
        local right = f and f.RightPane
        if not f or not right or not right.Display then
            return
        end
        if right.SetTitle then
            local tooltipText = "Rules are lightweight automations that override specific settings when certain conditions are met, such as your current specialization. For example, you can hide PRD > Power Bar for specs that don't need to see it, like a Fire Mage's Mana. This allows small, conditional customizations without creating dedicated profiles for each situation."
            right:SetTitle("Rules", tooltipText)
        end

        local init = {}
        table.insert(init, CreateAddButtonInitializer())

        local rules = addon.Rules and addon.Rules:GetRules() or {}
        if #rules == 0 then
            table.insert(init, CreateEmptyStateInitializer())
        else
            for index, rule in ipairs(rules) do
                rule.displayIndex = index
                table.insert(init, CreateRuleCardInitializer(rule))
                -- Insert divider between cards (not after the last one)
                if index < #rules then
                    table.insert(init, CreateDividerInitializer())
                end
            end
        end

        right:Display(init)
    end

    return { mode = "list", render = render, componentId = "profilesRules" }
end

function panel.RenderProfilesRules()
    return renderProfilesRules()
end
