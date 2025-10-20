local addonName, addon = ...

-- No longer need a local reference, will try calling globally

addon.SettingsPanel = {}
local panel = addon.SettingsPanel

-- Helper functions for creating settings widgets
local function CreateSlider(parent, yOffset, label, min, max, step, getFunc, setFunc) 
    local setting = {}
    function setting:GetValue() return getFunc() end
    function setting:SetValue(v) setFunc(v) end

    local options = CreateSliderOptions(min, max, step)
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return tostring(math.floor(v + 0.5)) end)
    
    local data = { setting = setting, options = options, name = label }
    local initSlider = CreateSettingInitializer("SettingsSliderControlTemplate", data)
    
    local f = CreateFrame("Frame", nil, parent, "SettingsSliderControlTemplate")
    f.GetElementData = function() return initSlider end
    f:SetPoint("TOPLEFT", 4, yOffset)
    f:SetPoint("TOPRIGHT", -16, yOffset)
    initSlider:InitFrame(f)
    return f, 34
end

local function CreateDropdown(parent, yOffset, label, values, getFunc, setFunc)
    local setting = {}
    function setting:GetValue() return getFunc() end
    function setting:SetValue(v) setFunc(v) end

    local optionsContainer = CreateControlTextContainer()
    for value, text in pairs(values) do
        optionsContainer:Add(value, text)
    end

    local data = { setting = setting, options = function() return optionsContainer:GetData() end, name = label }
    local initDrop = CreateSettingInitializer("SettingsDropdownControlTemplate", data)
    
    local f = CreateFrame("Frame", nil, parent, "SettingsDropdownControlTemplate")
    f.GetElementData = function() return initDrop end
    f:SetPoint("TOPLEFT", 4, yOffset)
    f:SetPoint("TOPRIGHT", -16, yOffset)
    initDrop:InitFrame(f)
    return f, 34
end

local function CreateCheckbox(parent, yOffset, label, getFunc, setFunc)
    local setting = {}
    function setting:GetValue() return getFunc() end
    function setting:SetValue(v) setFunc(v) end

    local data = { setting = setting, name = label }
    local initCheck = CreateSettingInitializer("SettingsCheckboxControlTemplate", data)
    
    local f = CreateFrame("Frame", nil, parent, "SettingsCheckboxControlTemplate")
    f.GetElementData = function() return initCheck end
    f:SetPoint("TOPLEFT", 4, yOffset)
    f:SetPoint("TOPRIGHT", -16, yOffset)
    initCheck:InitFrame(f)
    return f, 26
end

local function RenderComponentSettings(component)
    local f = panel.frame
    local settingsList = f.Container.SettingsList
    settingsList.Header.Title:SetText(component.name or component.id)
    
    if f.Container.ScrollFrame then
        f.Container.ScrollFrame:Hide()
    end

    local scrollFrame = CreateFrame("ScrollFrame", nil, settingsList, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", settingsList, "TOPLEFT", 0, -40)
    scrollFrame:SetPoint("BOTTOMRIGHT", settingsList, "BOTTOMRIGHT", -28, 0)
    f.Container.ScrollFrame = scrollFrame
    
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(scrollFrame:GetWidth(), 1000)
    scrollFrame:SetScrollChild(content)

    local yOffset = -20

    for settingId, setting in pairs(component.settings) do
        if setting.ui then
            local getFunc = function() return component.db[settingId] end
            local setFunc = function(value) 
                component.db[settingId] = value
                addon:ApplyStyles()
            end

            local widget, height
            if setting.ui.widget == "slider" then
                widget, height = CreateSlider(content, yOffset, setting.ui.label, setting.ui.min, setting.ui.max, setting.ui.step, getFunc, setFunc)
            elseif setting.ui.widget == "dropdown" then
                widget, height = CreateDropdown(content, yOffset, setting.ui.label, setting.ui.values, getFunc, setFunc)
            elseif setting.ui.widget == "checkbox" then
                widget, height = CreateCheckbox(content, yOffset, setting.ui.label, getFunc, setFunc)
            end

            if widget and height then
                yOffset = yOffset - height
            end
        end
    end
    
    content:SetHeight(math.abs(yOffset))
end

local function BuildCategories()
    local f = panel.frame

    CreateCategoryList(f.CategoryList, {}) -- Clear existing categories
    
    local categories = {}
    for id, component in pairs(addon.Components) do
        table.insert(categories, {
            name = component.name or component.id,
            key = id,
            onClick = function()
                RenderComponentSettings(component)
            end
        })
    end
    
    table.sort(categories, function(a, b) return a.name < b.name end)
    
    CreateCategoryList(f.CategoryList, categories)
    
    if #categories > 0 and f.CategoryList.buttons[1] then
        f.CategoryList.buttons[1]:Click()
    end
end

local function ShowPanel()
    if not panel.frame then
        local f = CreateFrame("Frame", "ScooterSettingsPanel", UIParent, "SettingsFrameTemplate")
        f:Hide()
        f:SetSize(920, 724)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f.NineSlice.Text:SetText("ScooterMod Settings")

        f:SetMovable(true)
        f:SetClampedToScreen(true)
        local headerDrag = CreateFrame("Frame", nil, f)
        headerDrag:SetPoint("TOPLEFT", f, "TOPLEFT", 7, -2)
        headerDrag:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -2)
        headerDrag:SetHeight(25)
        headerDrag:EnableMouse(true)
        headerDrag:RegisterForDrag("LeftButton")
        headerDrag:SetScript("OnDragStart", function() f:StartMoving() end)
        headerDrag:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

        local closeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        closeBtn:SetSize(96, 22)
        closeBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 16)
        closeBtn.Text:SetText(SETTINGS_CLOSE)
        closeBtn:SetScript("OnClick", function() f:Hide() end)

        local categoryList = CreateFrame("Frame", nil, f, "SettingsCategoryListTemplate")
        categoryList:SetSize(199, 569)
        categoryList:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -76)
        categoryList:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 178, 46)
        f.CategoryList = categoryList

        local container = CreateFrame("Frame", nil, f)
        container:ClearAllPoints()
        container:SetPoint("TOPLEFT", categoryList, "TOPRIGHT", 16, 0)
        container:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -22, 46)
        f.Container = container

        local settingsList = CreateFrame("Frame", nil, container, "SettingsListTemplate")
        settingsList:SetAllPoints(container)
        settingsList:SetClipsChildren(true)
        container.SettingsList = settingsList
        
        panel.frame = f
    end
    
    C_Timer.After(0, BuildCategories)
    panel.frame:Show()
end

function panel:Toggle()
    if panel.frame and panel.frame:IsShown() then
        panel.frame:Hide()
    else
        ShowPanel()
    end
end