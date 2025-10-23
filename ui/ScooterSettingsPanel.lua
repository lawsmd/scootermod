local addonName, addon = ...

addon.SettingsPanel = {}
local panel = addon.SettingsPanel

-- Collapsible section header (Keybindings-style) ---------------------------------
ScooterExpandableSectionMixin = {}

function ScooterExpandableSectionMixin:OnLoad()
    if SettingsExpandableSectionMixin and SettingsExpandableSectionMixin.OnLoad then
        SettingsExpandableSectionMixin.OnLoad(self)
    end
end

function ScooterExpandableSectionMixin:Init(initializer)
    if SettingsExpandableSectionMixin and SettingsExpandableSectionMixin.Init then
        SettingsExpandableSectionMixin.Init(self, initializer)
    end
    local data = initializer and initializer.data or {}
    self._initializing = true
    self.sectionKey = data.sectionKey
    self.componentId = data.componentId
    -- Increase header text size by ~30% (idempotent). Cache original font so we don't re-scale.
    if self.Button and self.Button.Text and self.Button.Text.GetFont then
        if not self._origHeaderFont then
            local fp, fh, ff = self.Button.Text:GetFont()
            self._origHeaderFont = { fp, fh, ff }
            self._headerFontScaled = false
        end
        if not self._headerFontScaled then
            local fp, fh, ff = self._origHeaderFont[1], self._origHeaderFont[2], self._origHeaderFont[3]
            if fh then
                local bigger = math.max(1, math.floor((fh * 1.3) + 0.5))
                self.Button.Text:SetFont(fp, bigger, ff)
            end
            self._headerFontScaled = true
        end
    end
    self:OnExpandedChanged(self:GetExpanded())
    self._initializing = false
end

function ScooterExpandableSectionMixin:GetExpanded()
    local cid = self.componentId or ""
    local key = self.sectionKey or ""
    addon.SettingsPanel._expanded = addon.SettingsPanel._expanded or {}
    addon.SettingsPanel._expanded[cid] = addon.SettingsPanel._expanded[cid] or {}
    local expanded = addon.SettingsPanel._expanded[cid][key]
    if expanded == nil then expanded = false end
    return expanded
end

function ScooterExpandableSectionMixin:SetExpanded(expanded)
    local cid = self.componentId or ""
    local key = self.sectionKey or ""
    addon.SettingsPanel._expanded = addon.SettingsPanel._expanded or {}
    addon.SettingsPanel._expanded[cid] = addon.SettingsPanel._expanded[cid] or {}
    addon.SettingsPanel._expanded[cid][key] = not not expanded
end

function ScooterExpandableSectionMixin:CalculateHeight()
    return 34
end

function ScooterExpandableSectionMixin:OnExpandedChanged(expanded)
    if self.Button and self.Button.Right then
        if expanded then
            self.Button.Right:SetAtlas("Options_ListExpand_Right_Expanded", TextureKitConstants.UseAtlasSize)
        else
            self.Button.Right:SetAtlas("Options_ListExpand_Right", TextureKitConstants.UseAtlasSize)
        end
    end
    self:SetExpanded(expanded)
    if not self._initializing and addon and addon.SettingsPanel and addon.SettingsPanel.RefreshCurrentCategoryDeferred then
        addon.SettingsPanel.RefreshCurrentCategoryDeferred()
    end
end

-- Helper API for shown predicates
function panel:IsSectionExpanded(componentId, sectionKey)
    self._expanded = self._expanded or {}
    self._expanded[componentId] = self._expanded[componentId] or {}
    local v = self._expanded[componentId][sectionKey]
    if v == nil then v = false end
    return v
end

-- ScooterTabbedSectionMixin (copied from RIPAuras)
ScooterTabbedSectionMixin = {}

function ScooterTabbedSectionMixin:OnLoad()
    self.tabsGroup = self.tabsGroup or CreateRadioButtonGroup()
    self.tabsGroup:AddButtons({ self.TabA, self.TabB })
    self.tabsGroup:SelectAtIndex(1)
    self.tabsGroup:RegisterCallback(ButtonGroupBaseMixin.Event.Selected, function(_, btn)
        self:EvaluateVisibility(btn)
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
    end, self)
    self:EvaluateVisibility(self.TabA)
end

-- Public: Re-render the currently selected category and preserve scroll position
function panel.RefreshCurrentCategory()
    local f = panel and panel.frame
    if not f or not f:IsShown() then return end
    local cat = f.CurrentCategory
    if not cat or not f.CatRenderers then return end
    local entry = f.CatRenderers[cat]
    if not entry or not entry.render then return end
    local settingsList = f.SettingsList
    local sb = settingsList and settingsList.ScrollBox
    local percent
    if sb and sb.GetDerivedScrollPercentage then
        percent = sb:GetDerivedScrollPercentage()
    elseif sb and sb.GetScrollPercentage then
        percent = sb:GetScrollPercentage()
    end
    entry.render()
    if percent and sb and sb.SetScrollPercentage then
        C_Timer.After(0, function()
            if panel and panel.frame and panel.frame:IsShown() then
                pcall(sb.SetScrollPercentage, sb, percent)
            end
        end)
    end
end

function panel.RefreshCurrentCategoryDeferred()
    C_Timer.After(0, function() if panel and panel.RefreshCurrentCategory then panel.RefreshCurrentCategory() end end)
end

function ScooterTabbedSectionMixin:SetTitles(sectionTitle, tabAText, tabBText)
    if self.TitleFS then self.TitleFS:SetText(sectionTitle or "") end
    if self.TabA then
        self.TabA.tabText = tabAText or "Tab A"
        if self.TabA.Text then
            self.TabA.Text:SetText(self.TabA.tabText)
            self.TabA:SetWidth(self.TabA.Text:GetStringWidth() + 40)
        end
    end
    if self.TabB then
        self.TabB.tabText = tabBText or "Tab B"
        if self.TabB.Text then
            self.TabB.Text:SetText(self.TabB.tabText)
            self.TabB:SetWidth(self.TabB.Text:GetStringWidth() + 40)
        end
    end
end

function ScooterTabbedSectionMixin:EvaluateVisibility(selected)
    local showA = selected == self.TabA
    if self.PageA then self.PageA:SetShown(showA) end
    if self.PageB then self.PageB:SetShown(not showA) end
end

function ScooterTabbedSectionMixin:Init(initializer)
    local data = initializer and initializer.data or {}
    self:SetTitles(data.sectionTitle or "", data.tabAText or "Tab A", data.tabBText or "Tab B")
    local function ClearChildren(frame)
        if not frame or not frame.GetNumChildren then return end
        for i = frame:GetNumChildren(), 1, -1 do
            local child = select(i, frame:GetChildren())
            if child then child:SetParent(nil); child:Hide() end
        end
    end
    ClearChildren(self.PageA)
    ClearChildren(self.PageB)
    if type(data.build) == "function" then
        data.build(self)
    end
end

local function CreateLocalSetting(name, varType, getValue, setValue, defaultValue)
    local setting = {}
    function setting:GetName() return name end
    function setting:GetVariable() return "Scooter_" .. name end
    function setting:GetVariableType() return varType end
    function setting:GetDefaultValue() return defaultValue end
    function setting:GetValue() return getValue() end
    function setting:SetValue(v) setValue(v) end
    function setting:SetValueToDefault() if defaultValue ~= nil then setting:SetValue(defaultValue); return true end end
    function setting:HasCommitFlag() return false end
    return setting
end

local function clampPositionValue(v)
    if v > 1000 then return 1000 end
    if v < -1000 then return -1000 end
    return v
end

local function roundPositionValue(v)
    v = tonumber(v) or 0
    return v >= 0 and math.floor(v + 0.5) or math.ceil(v - 0.5)
end

local function ConvertSliderInitializerToTextInput(initializer)
    if not initializer or initializer._scooterTextInput then return initializer end
    local baseInitFrame = initializer.InitFrame
    initializer.InitFrame = function(self, frame)
        baseInitFrame(self, frame)
        if frame.SliderWithSteppers then frame.SliderWithSteppers:Hide() end
        local input = frame.ScooterTextInput
        if not input then
            input = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
            input:SetAutoFocus(false)
            input:SetWidth(120); input:SetHeight(24); input:SetJustifyH("CENTER")
            input:SetPoint("LEFT", frame, "CENTER", -40, 0)
            frame.ScooterTextInput = input
            local function restore()
                local setting = frame:GetSetting()
                local value = setting and setting:GetValue()
                input:SetText(value == nil and "" or string.format("%.0f", value))
            end
            local function commit()
                local num = roundPositionValue(tonumber(input:GetText()))
                if not num then restore(); return end
                local options = self:GetOptions()
                if options then
                    if options.minValue ~= nil then num = math.max(options.minValue, num) end
                    if options.maxValue ~= nil then num = math.min(options.maxValue, num) end
                end
                local setting = frame:GetSetting()
                if setting and setting:GetValue() ~= num then setting:SetValue(num) else input:SetText(string.format("%.0f", num)) end
            end
            input:SetScript("OnEnterPressed", function(b) commit(); b:ClearFocus() end)
            input:SetScript("OnEditFocusLost", function(b) commit(); b:HighlightText(0, 0) end)
            input:SetScript("OnEscapePressed", function(b) b:ClearFocus(); restore() end)
        end
        local setting = frame:GetSetting()
        local value = setting and setting:GetValue()
        frame.ScooterTextInput:SetText(value == nil and "" or string.format("%.0f", value))
        if frame.ScooterTextInput then frame.ScooterTextInput:Show() end
        if not frame.ScooterOriginalOnSettingValueChanged then
            frame.ScooterOriginalOnSettingValueChanged = frame.OnSettingValueChanged
            frame.OnSettingValueChanged = function(ctrl, setting, val)
                if ctrl.ScooterOriginalOnSettingValueChanged then ctrl.ScooterOriginalOnSettingValueChanged(ctrl, setting, val) end
                if ctrl.ScooterTextInput then
                    local current = (setting and setting.GetValue) and setting:GetValue() or nil
                    ctrl.ScooterTextInput:SetText(current == nil and "" or string.format("%.0f", current))
                end
            end
        end
        if frame.ScooterTextInput then frame.ScooterTextInput:SetEnabled(SettingsControlMixin.IsEnabled(frame)) end
    end
    initializer._scooterTextInput = true
    return initializer
end

-- Reusable factory for "checkbox + inline color swatch" rows that safely cooperate with
-- Blizzard's Settings list recycler. It keeps the standard checkbox template and anchors
-- a ColorSwatchTemplate directly to the checkbox, avoiding custom containers.
local function CreateCheckboxWithSwatchInitializer(settingObj, label, getColor, setColor, offset)
    local data = { setting = settingObj, name = label, options = {} }
    local init = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", data)
    local baseInit = init.InitFrame
    init.InitFrame = function(self, frame)
        if baseInit then baseInit(self, frame) end
        local cb = frame.Checkbox or frame.CheckBox or frame.Control or frame
        local swatch = frame.ScooterInlineSwatch
        if not swatch then
            swatch = CreateFrame("Button", nil, frame, "ColorSwatchTemplate")
            swatch:SetSize(18, 18)
            -- Use the template's built-in layers: SwatchBg (outer), InnerBorder (middle), Color (inner)
            if swatch.SwatchBg then swatch.SwatchBg:SetColorTexture(0, 0, 0, 1) end -- outer pixel ring
            if swatch.InnerBorder then swatch.InnerBorder:SetColorTexture(0, 0, 0, 1) end -- inner ring
            -- Color texture already exists in the template and is sized/centered via OnShow
            frame.ScooterInlineSwatch = swatch
        end
        swatch:ClearAllPoints()
        local dx = tonumber(offset) or 8
        -- Prefer anchoring to the checkbox's Text region so the swatch sits after the label
        if cb and cb.Text and cb.Text.GetStringWidth then
            swatch:SetPoint("LEFT", cb.Text, "RIGHT", dx, 0)
        elseif cb and cb.GetObjectType and cb:GetObjectType() == "CheckButton" then
            swatch:SetPoint("LEFT", cb, "RIGHT", dx, 0)
        else
            swatch:SetPoint("LEFT", frame, "LEFT", 180, 0)
        end
        -- Ensure the swatch is clickable above the label text
        swatch:SetFrameStrata(frame:GetFrameStrata())
        swatch:SetFrameLevel((frame:GetFrameLevel() or 0) + 2)
        swatch:EnableMouse(true)
        local c = getColor() or {1,1,1,1}
        if swatch.Color then swatch.Color:SetColorTexture(c[1] or 1, c[2] or 1, c[3] or 1, 1) end
        swatch:SetShown(settingObj:GetValue() and true or false)
        swatch:SetScript("OnClick", function()
            local cur = getColor() or {1,1,1,1}
            ColorPickerFrame:SetupColorPickerAndShow({
                r = cur[1] or 1, g = cur[2] or 1, b = cur[3] or 1,
                hasOpacity = true,
                opacity = cur[4] or 1,
                swatchFunc = function()
                    local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                    local na = ColorPickerFrame:GetColorAlpha()
                    setColor(nr, ng, nb, na)
                    if swatch.Color then swatch.Color:SetColorTexture(nr or 1, ng or 1, nb or 1, 1) end
                end,
                cancelFunc = function(prev)
                    if prev then setColor(prev.r or 1, prev.g or 1, prev.b or 1, prev.a or 1) end
                end,
            })
        end)
        if not frame.ScooterInlineSwatchHooked then
            local original = frame.OnSettingValueChanged
            frame.OnSettingValueChanged = function(ctrl, setting, val)
                if original then pcall(original, ctrl, setting, val) end
                if ctrl.ScooterInlineSwatch then
                    local show = (val ~= nil) and (val and true or false) or (settingObj:GetValue() and true or false)
                    ctrl.ScooterInlineSwatch:SetShown(show)
                end
            end
            frame.ScooterInlineSwatchHooked = true
        end
        -- Also update visibility immediately on checkbox clicks (some templates delay the OnSettingValueChanged)
        if cb and not cb.ScooterInlineSwatchClickHooked then
            cb:HookScript("OnClick", function()
                if frame and frame.ScooterInlineSwatch then
                    frame.ScooterInlineSwatch:SetShown((cb.GetChecked and cb:GetChecked()) and true or false)
                end
            end)
            cb.ScooterInlineSwatchClickHooked = true
        end
    end
    init.reinitializeOnValueChanged = false
    return init
end

do
    if not addon._sliderControlGuarded then
        addon._sliderControlGuarded = true
        if type(SettingsSliderControlMixin) == "table" and type(SettingsSliderControlMixin.Init) == "function" then
            hooksecurefunc(SettingsSliderControlMixin, "Init", function(frame)
                if frame.ScooterTextInput then frame.ScooterTextInput:Hide() end
                if frame.SliderWithSteppers then frame.SliderWithSteppers:Show() end
            end)
        end
    end
end

local function createComponentRenderer(componentId)
    return function()
        local render = function()
            local component = addon.Components[componentId]
            if not component then return end

            local init = {}
            local sections = {}
            for settingId, setting in pairs(component.settings) do
                if setting.ui then
                    local section = setting.ui.section or "General"
                    if not sections[section] then sections[section] = {} end
                    table.insert(sections[section], {id = settingId, setting = setting})
                end
            end

            for _, sectionSettings in pairs(sections) do
                table.sort(sectionSettings, function(a, b) return (a.setting.ui.order or 999) < (b.setting.ui.order or 999) end)
            end

            local orderedSections = {"Positioning", "Sizing", "Border", "Text", "Misc"}
            local function RefreshCurrentCategoryDeferred()
                if panel and panel.RefreshCurrentCategoryDeferred then
                    panel.RefreshCurrentCategoryDeferred()
                end
            end
            for _, sectionName in ipairs(orderedSections) do
                if sectionName == "Text" then
                    if component.id == "essentialCooldowns" then
                        -- Collapsible header for Text section, no extra header inside the tabbed control
                        local expInitializer = Settings.CreateElementInitializer("ScooterExpandableSectionTemplate", {
                            name = "Text",
                            sectionKey = "Text",
                            componentId = component.id,
                            expanded = panel:IsSectionExpanded(component.id, "Text"),
                        })
                        expInitializer.GetExtent = function() return 30 end
                        table.insert(init, expInitializer)

                        local data = { sectionTitle = "", tabAText = "Charges", tabBText = "Cooldowns" }
                        data.build = function(frame)
                            local textA = frame.PageA:CreateFontString(nil, "OVERLAY", "GameFontNormal"); textA:SetPoint("TOPLEFT", 20, -20); textA:SetText("Charges text settings will be implemented here")
                            local textB = frame.PageB:CreateFontString(nil, "OVERLAY", "GameFontNormal"); textB:SetPoint("TOPLEFT", 20, -20); textB:SetText("Cooldowns text settings will be implemented here")
                        end
                        local initializer = Settings.CreateElementInitializer("ScooterTabbedSectionTemplate", data)
                        initializer.GetExtent = function() return 260 end
                        initializer:AddShownPredicate(function()
                            return panel:IsSectionExpanded(component.id, "Text")
                        end)
                        table.insert(init, initializer)
                    end
                elseif sections[sectionName] and #sections[sectionName] > 0 then
                    local headerName = (sectionName == "Misc") and "Visibility" or sectionName

                    -- Collapsible section header (expand/collapse like Keybindings)
                    local expInitializer = Settings.CreateElementInitializer("ScooterExpandableSectionTemplate", {
                        name = headerName,
                        sectionKey = sectionName,
                        componentId = component.id,
                        expanded = panel:IsSectionExpanded(component.id, sectionName),
                    })
                    expInitializer.GetExtent = function() return 30 end
                    table.insert(init, expInitializer)

                    for _, item in ipairs(sections[sectionName]) do
                        local settingId = item.id
                        local setting = item.setting
                        local ui = setting.ui
                        local label = ui.label
                        local values = ui.values

                        if ui.dynamicLabel and settingId == "columns" then
                            label = (component.db.orientation or "H") == "H" and "# Columns" or "# Rows"
                        end

                        if ui.dynamicValues and settingId == "direction" then
                            values = ((component.db.orientation or "H") == "H") and {left="Left", right="Right"} or {up="Up", down="Down"}
                        end

                        -- Skip dedicated color row for tint color; swatch is inline with the checkbox row
                        if sectionName == "Border" and settingId == "borderTintColor" then
                            -- Skip: handled by unified tint row above
                        else
                        local settingObj = CreateLocalSetting(label, ui.type or "string",
                            function()
                                return component.db[settingId] or setting.default
                            end,
                            function(v)
                                local finalValue

                                if ui.widget == "dropdown" then
                                    -- Preserve string keys for dropdowns (e.g., "H", "V", "left", "right", "up", "down")
                                    finalValue = v
                                elseif ui.widget == "checkbox" then
                                    finalValue = not not v
                                elseif ui.widget == "slider" then
                                    finalValue = tonumber(v) or 0
                                    if settingId == "iconSize" then
                                        -- Enforce multiples of 10 only
                                        if finalValue < (ui.min or 50) then finalValue = ui.min or 50 end
                                        if finalValue > (ui.max or 200) then finalValue = ui.max or 200 end
                                        finalValue = math.floor(finalValue / 10 + 0.5) * 10
                                    elseif settingId == "positionX" or settingId == "positionY" then
                                        finalValue = clampPositionValue(finalValue)
                                    else
                                        -- For all other sliders (e.g., iconPadding), round to nearest integer.
                                        finalValue = math.floor(finalValue + 0.5)
                                    end
                                else
                                    -- Fallback: attempt numeric, else raw
                                    finalValue = tonumber(v) or v
                                end

                                -- Avoid redundant writes that can bounce values (e.g., 50 -> 200)
                                local changed = component.db[settingId] ~= finalValue
                                component.db[settingId] = finalValue

                                if changed and (setting.type == "editmode" or settingId == "positionX" or settingId == "positionY") then
                                    if addon.EditMode.SyncComponentToEditMode then addon.EditMode.SyncComponentToEditMode(component) end
                                end

                                if settingId == "orientation" then
                                    local dir = component.db.direction or "right"
                                    if v == "H" then
                                        if dir ~= "left" and dir ~= "right" then component.db.direction = "right" end
                                    else
                                        if dir ~= "up" and dir ~= "down" then component.db.direction = "up" end
                                    end
                                end

                                addon:ApplyStyles()

                                if ui.dynamicLabel or ui.dynamicValues or settingId == "orientation" then
                                    RefreshCurrentCategoryDeferred()
                                end
                            end, setting.default)                        if ui.widget == "slider" then
                            local options = Settings.CreateSliderOptions(ui.min, ui.max, ui.step)
                            if settingId == "iconSize" then
                                options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v)
                                    local snapped = math.floor(v / 10 + 0.5) * 10
                                    return tostring(snapped)
                                end)
                            else
                                options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return tostring(math.floor(v + 0.5)) end)
                            end
                            local data = { setting = settingObj, options = options, name = label }
                            local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", data)
                            initSlider:AddShownPredicate(function()
                                return panel:IsSectionExpanded(component.id, sectionName)
                            end)
                            initSlider.reinitializeOnValueChanged = true
                            if settingId == "positionX" or settingId == "positionY" then ConvertSliderInitializerToTextInput(initSlider) end
                            table.insert(init, initSlider)
                        elseif ui.widget == "dropdown" then
                            local data
                            if settingId == "borderStyle" and addon.BuildBorderOptionsContainer then
                                data = { setting = settingObj, options = addon.BuildBorderOptionsContainer, name = label }
                            else
                            local containerOpts = Settings.CreateControlTextContainer()
                            local orderedValues = {}
                            if settingId == "orientation" then table.insert(orderedValues, "H"); table.insert(orderedValues, "V") else for val, _ in pairs(values) do table.insert(orderedValues, val) end end
                            for _, valKey in ipairs(orderedValues) do containerOpts:Add(valKey, values[valKey]) end
                                data = { setting = settingObj, options = function() return containerOpts:GetData() end, name = label }
                            end
                            local initDrop = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", data)
                            initDrop:AddShownPredicate(function()
                                return panel:IsSectionExpanded(component.id, sectionName)
                            end)
                            initDrop.reinitializeOnValueChanged = true
                            table.insert(init, initDrop)
                        elseif ui.widget == "checkbox" then
                            local data = { setting = settingObj, name = label, tooltip = ui.tooltip, options = {} }
                            if settingId == "borderTintEnable" then
                                -- Use the reusable factory for checkbox + swatch
                                local initCb = CreateCheckboxWithSwatchInitializer(
                                    settingObj,
                                    label,
                                    function() return component.db.borderTintColor or {1,1,1,1} end,
                                    function(r, g, b, a)
                                        component.db.borderTintColor = { r, g, b, a }
                                        addon:ApplyStyles()
                                    end,
                                    8
                                )
                                initCb:AddShownPredicate(function()
                                    return panel:IsSectionExpanded(component.id, sectionName)
                                end)
                                -- Ensure swatch visibility updates on checkbox change without reopening the panel
                                local baseInit = initCb.InitFrame
                                initCb.InitFrame = function(self, frame)
                                    if baseInit then baseInit(self, frame) end
                                    local cb = frame.Checkbox or frame.CheckBox or frame.Control or frame
                                    if cb and not cb._ScooterToggleHooked then
                                        cb:HookScript("OnClick", function()
                                            if frame and frame.ScooterInlineSwatch then
                                                frame.ScooterInlineSwatch:SetShown((cb.GetChecked and cb:GetChecked()) and true or false)
                                            end
                                        end)
                                        cb._ScooterToggleHooked = true
                                    end
                                end
                                table.insert(init, initCb)
                            else
                                local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", data)
                                initCb:AddShownPredicate(function()
                                    return panel:IsSectionExpanded(component.id, sectionName)
                                end)
                                table.insert(init, initCb)
                            end
                        elseif ui.widget == "color" then
                            if settingId ~= "borderTintColor" then
                                local colorRow = Settings.CreateElementInitializer("SettingsListElementTemplate")
                                colorRow.GetExtent = function() return 28 end
                                colorRow.InitFrame = function(self, frame)
                                    if not frame.ScooterColorSwatch then
                                        local swatch = CreateFrame("Button", nil, frame)
                                        swatch:SetSize(20, 20)
                                        swatch:SetPoint("LEFT", frame, "LEFT", 16, 0)
                                        swatch.Color = swatch:CreateTexture(nil, "ARTWORK")
                                        swatch.Color:SetAllPoints(swatch)
                                        frame.ScooterColorSwatch = swatch
                                    end
                                    local swatch = frame.ScooterColorSwatch
                                    local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
                                    title:SetPoint("LEFT", swatch, "RIGHT", 8, 0)
                                    title:SetText(label)
                                    local c = component.db[settingId] or setting.default or {1,1,1,1}
                                    swatch.Color:SetColorTexture(c[1] or 1, c[2] or 1, c[3] or 1, 1)
                                    swatch:SetScript("OnClick", function()
                                        local cur = component.db[settingId] or setting.default or {1,1,1,1}
                                        ColorPickerFrame:SetupColorPickerAndShow({
                                            r = cur[1] or 1, g = cur[2] or 1, b = cur[3] or 1,
                                            hasOpacity = true,
                                            opacity = cur[4] or 1,
                                            swatchFunc = function()
                                                local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                                                local na = ColorPickerFrame:GetColorAlpha()
                                                component.db[settingId] = { nr, ng, nb, na }
                                                addon:ApplyStyles()
                                            end,
                                            cancelFunc = function(prev)
                                                if prev then
                                                    component.db[settingId] = { prev.r or 1, prev.g or 1, prev.b or 1, prev.a or 1 }
                                                    addon:ApplyStyles()
                                                end
                                            end,
                                        })
                                    end)
                                end
                                colorRow:AddShownPredicate(function()
                                    return panel:IsSectionExpanded(component.id, sectionName)
                                end)
                                table.insert(init, colorRow)
                            end
                        end
                        end
                    end
                end
            end

            local f = panel.frame
            local settingsList = f.SettingsList
            settingsList.Header.Title:SetText(component.name or component.id)
            settingsList:Display(init)
            -- Save for potential RepairDisplay call by category selection callback
            local currentCategory = f.CurrentCategory
            if currentCategory and f.CatRenderers then
                local entry = f.CatRenderers[currentCategory]
                if entry then entry._lastInitializers = init end
            end
            -- Ensure shown predicates have been applied after initial data provider set
            if settingsList.RepairDisplay then pcall(settingsList.RepairDisplay, settingsList, { EnumerateInitializers = function() return ipairs(init) end, GetInitializers = function() return init end }) end
            settingsList:Show()
            f.Canvas:Hide()
        end
        return { mode = "list", render = render, componentId = componentId }
    end
end
local function renderEssentialCooldowns() return createComponentRenderer("essentialCooldowns")() end
local function renderUtilityCooldowns() return createComponentRenderer("utilityCooldowns")() end
local function renderTrackedBars() return createComponentRenderer("trackedBars")() end
local function renderTrackedBuffs() return createComponentRenderer("trackedBuffs")() end

local function BuildCategories()
    local f = panel.frame
    local categoryList = f.CategoryList
    if f.CategoriesBuilt then return end
    local catRenderers, createdCategories = {}, {}
    local function createCategory(groupText, name, order, renderer)
        local category = CreateFromMixins(SettingsCategoryMixin)
        category:Init(name); category:SetOrder(order or 10)
        categoryList:AddCategory(category, groupText, false)
        catRenderers[category] = renderer
        table.insert(createdCategories, category)
        return category
    end
    createCategory("Cooldown Manager", "Essential Cooldowns", 11, renderEssentialCooldowns())
    createCategory("Cooldown Manager", "Utility Cooldowns", 12, renderUtilityCooldowns())
    createCategory("Cooldown Manager", "Tracked Bars", 13, renderTrackedBars())
    createCategory("Cooldown Manager", "Tracked Buffs", 14, renderTrackedBuffs())
    categoryList:RegisterCallback(SettingsCategoryListMixin.Event.OnCategorySelected, function(_, category)
        f.CurrentCategory = category
        local entry = catRenderers[category]
        if entry and entry.mode == "list" then
            entry.render()
            -- Some parts of the list evaluate shown predicates lazily; force a second pass like the user's second click
            if f.SettingsList and f.SettingsList.RepairDisplay then
                C_Timer.After(0, function()
                    if f and f:IsShown() then
                        pcall(f.SettingsList.RepairDisplay, f.SettingsList, { EnumerateInitializers = function() return ipairs(entry and entry._lastInitializers or {}) end, GetInitializers = function() return entry and entry._lastInitializers or {} end })
                    end
                end)
            end
        end
    end, f)
    f.CategoriesBuilt, f.CatRenderers, f.CreatedCategories = true, catRenderers, createdCategories
    C_Timer.After(0, function() if createdCategories[1] then categoryList:SetCurrentCategory(createdCategories[1]) end end)
end

local function ShowPanel()
    if not panel.frame then
        local f = CreateFrame("Frame", "ScooterSettingsPanel", UIParent, "SettingsFrameTemplate")
        f:Hide(); f:SetSize(920, 724); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG")
        f.NineSlice.Text:SetText("ScooterMod Settings")
        f:SetMovable(true); f:SetClampedToScreen(true)
        local headerDrag = CreateFrame("Frame", nil, f)
        headerDrag:SetPoint("TOPLEFT", 7, -2); headerDrag:SetPoint("TOPRIGHT", -3, -2); headerDrag:SetHeight(25)
        headerDrag:EnableMouse(true); headerDrag:RegisterForDrag("LeftButton")
        headerDrag:SetScript("OnDragStart", function() f:StartMoving() end)
        headerDrag:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
        local closeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        closeBtn:SetSize(96, 22); closeBtn:SetPoint("BOTTOMRIGHT", -16, 16)
        closeBtn.Text:SetText(SETTINGS_CLOSE)
        closeBtn:SetScript("OnClick", function() f:Hide() end)
        local categoryList = CreateFrame("Frame", nil, f, "SettingsCategoryListTemplate")
        categoryList:SetSize(199, 569); categoryList:SetPoint("TOPLEFT", 18, -76); categoryList:SetPoint("BOTTOMLEFT", 178, 46)
        f.CategoryList = categoryList
        local container = CreateFrame("Frame", nil, f)
        container:ClearAllPoints(); container:SetPoint("TOPLEFT", categoryList, "TOPRIGHT", 16, 0); container:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -22, 46)
        f.Container = container
        local settingsList = CreateFrame("Frame", nil, container, "SettingsListTemplate")
        settingsList:SetAllPoints(container); settingsList:SetClipsChildren(true)
        f.SettingsList = settingsList
        -- Repurpose the header DefaultsButton as "Collapse All"
        if f.SettingsList and f.SettingsList.Header and f.SettingsList.Header.DefaultsButton then
            local btn = f.SettingsList.Header.DefaultsButton
            btn.Text:SetText("Collapse All")
            btn:SetScript("OnClick", function()
                local current = f.CurrentCategory
                if not current or not f.CatRenderers then return end
                local entry = f.CatRenderers[current]
                if not entry or not entry.componentId then return end
                local cid = entry.componentId
                panel._expanded = panel._expanded or {}
                panel._expanded[cid] = panel._expanded[cid] or {}
                -- Collapse known sections for this component
                for _, key in ipairs({"Positioning","Sizing","Border","Text","Misc","Visibility"}) do
                    panel._expanded[cid][key] = false
                end
                panel.RefreshCurrentCategory()
            end)
        end
        local canvas = CreateFrame("Frame", nil, container)
        canvas:SetAllPoints(container); canvas:SetClipsChildren(true); canvas:Hide()
        f.Canvas = canvas
        panel.frame = f
        C_Timer.After(0, BuildCategories)
    else
        local cat = panel.frame.CurrentCategory
        if cat and panel.frame.CatRenderers and panel.frame.CatRenderers[cat] and panel.frame.CatRenderers[cat].render then
            C_Timer.After(0, function()
                if panel.frame and panel.frame:IsShown() then
                    local entry = panel.frame.CatRenderers[cat]
                    if entry and entry.render then entry.render() end
                    -- Force predicates to settle immediately on open
                    local settingsList = panel.frame.SettingsList
                    if settingsList and settingsList.RepairDisplay and entry and entry._lastInitializers then
                        pcall(settingsList.RepairDisplay, settingsList, { EnumerateInitializers = function() return ipairs(entry._lastInitializers) end, GetInitializers = function() return entry._lastInitializers end })
                    end
                end
            end)
        end
    end
    panel.frame:Show()
end

function panel:Toggle()
    if panel.frame and panel.frame:IsShown() then panel.frame:Hide() else ShowPanel() end
end
