local addonName, addon = ...

addon.SettingsPanel = {}
local panel = addon.SettingsPanel

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
            for _, sectionName in ipairs(orderedSections) do
                if sectionName == "Text" then
                    if component.id == "essentialCooldowns" then
                        table.insert(init, CreateSettingsListSectionHeaderInitializer("Text"))
                        local data = { sectionTitle = "Text", tabAText = "Charges", tabBText = "Cooldowns" }
                        data.build = function(frame)
                            local textA = frame.PageA:CreateFontString(nil, "OVERLAY", "GameFontNormal"); textA:SetPoint("TOPLEFT", 20, -20); textA:SetText("Charges text settings will be implemented here")
                            local textB = frame.PageB:CreateFontString(nil, "OVERLAY", "GameFontNormal"); textB:SetPoint("TOPLEFT", 20, -20); textB:SetText("Cooldowns text settings will be implemented here")
                        end
                        local initializer = Settings.CreateElementInitializer("ScooterTabbedSectionTemplate", data)
                        initializer.GetExtent = function() return 260 end
                        table.insert(init, initializer)
                    end
                elseif sections[sectionName] and #sections[sectionName] > 0 then
                    local headerName = (sectionName == "Misc") and "Visibility" or sectionName
                    table.insert(init, CreateSettingsListSectionHeaderInitializer(headerName))

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
                                    C_Timer.After(0, function()
                                        if panel.frame and panel.frame:IsShown() then
                                            local cat = panel.frame.CurrentCategory
                                            if cat and panel.frame.CatRenderers and panel.frame.CatRenderers[cat] and panel.frame.CatRenderers[cat].render then
                                                panel.frame.CatRenderers[cat].render()
                                            end
                                        end
                                    end)
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
                            initSlider.reinitializeOnValueChanged = true
                            if settingId == "positionX" or settingId == "positionY" then ConvertSliderInitializerToTextInput(initSlider) end
                            table.insert(init, initSlider)
                        elseif ui.widget == "dropdown" then
                            local containerOpts = Settings.CreateControlTextContainer()
                            local orderedValues = {}
                            if settingId == "orientation" then table.insert(orderedValues, "H"); table.insert(orderedValues, "V") else for val, _ in pairs(values) do table.insert(orderedValues, val) end end
                            for _, valKey in ipairs(orderedValues) do containerOpts:Add(valKey, values[valKey]) end
                            local data = { setting = settingObj, options = function() return containerOpts:GetData() end, name = label }
                            local initDrop = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", data)
                            initDrop.reinitializeOnValueChanged = true
                            table.insert(init, initDrop)
                        elseif ui.widget == "checkbox" then
                            local data = { setting = settingObj, name = label, tooltip = ui.tooltip }
                            table.insert(init, Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", data))
                        end
                    end
                end
            end

            local f = panel.frame
            local settingsList = f.SettingsList
            settingsList.Header.Title:SetText(component.name or component.id)
            settingsList:Display(init)
            settingsList:Show()
            f.Canvas:Hide()
        end
        return { mode = "list", render = render }
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
        if entry and entry.mode == "list" then entry.render() end
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
        local canvas = CreateFrame("Frame", nil, container)
        canvas:SetAllPoints(container); canvas:SetClipsChildren(true); canvas:Hide()
        f.Canvas = canvas
        panel.frame = f
        C_Timer.After(0, BuildCategories)
    else
        local cat = panel.frame.CurrentCategory
        if cat and panel.frame.CatRenderers and panel.frame.CatRenderers[cat] and panel.frame.CatRenderers[cat].render then
            C_Timer.After(0, function() if panel.frame and panel.frame:IsShown() then panel.frame.CatRenderers[cat].render() end end)
        end
    end
    panel.frame:Show()
end

function panel:Toggle()
    if panel.frame and panel.frame:IsShown() then panel.frame:Hide() else ShowPanel() end
end
