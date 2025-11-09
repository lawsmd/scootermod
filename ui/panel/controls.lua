local addonName, addon = ...

addon.SettingsPanel = addon.SettingsPanel or {}
local panel = addon.SettingsPanel

-- Expose helpers globally for builder modules
function CreateLocalSetting(name, varType, getValue, setValue, defaultValue)
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

function clampPositionValue(v)
    if v > 1000 then return 1000 end
    if v < -1000 then return -1000 end
    return v
end

function roundPositionValue(v)
    v = tonumber(v) or 0
    return v >= 0 and math.floor(v + 0.5) or math.ceil(v - 0.5)
end

function ConvertSliderInitializerToTextInput(initializer)
    if not initializer or initializer._scooterTextInput then return initializer end
    local baseInitFrame = initializer.InitFrame
    initializer.InitFrame = function(self, frame)
        if baseInitFrame then baseInitFrame(self, frame) end
        if frame.SliderWithSteppers then frame.SliderWithSteppers:Hide() end
        local input = frame.ScooterTextInput
        if not input then
            input = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
            input:SetAutoFocus(false)
            input:SetWidth(120); input:SetHeight(24); input:SetJustifyH("CENTER")
            input:SetPoint("LEFT", frame, "CENTER", -40, 0)
            frame.ScooterTextInput = input
            local function restore()
                local setting = (frame and frame.data and frame.GetSetting) and frame:GetSetting() or nil
                local value = setting and setting.GetValue and setting:GetValue() or nil
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
                local setting = (frame and frame.data and frame.GetSetting) and frame:GetSetting() or nil
                if setting and setting.GetValue and setting:GetValue() ~= num then setting:SetValue(num) else input:SetText(string.format("%.0f", num)) end
            end
            input:SetScript("OnEnterPressed", function(b) commit(); b:ClearFocus() end)
            input:SetScript("OnEditFocusLost", function(b) commit(); b:HighlightText(0, 0) end)
            input:SetScript("OnEscapePressed", function(b) b:ClearFocus(); restore() end)
        end
        local setting = (frame and frame.data and frame.GetSetting) and frame:GetSetting() or nil
        local value = setting and setting.GetValue and setting:GetValue() or nil
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
        if frame.ScooterTextInput and SettingsControlMixin and SettingsControlMixin.IsEnabled then frame.ScooterTextInput:SetEnabled(SettingsControlMixin.IsEnabled(frame)) end
    end
    initializer._scooterTextInput = true
    return initializer
end

-- Creates a standalone color picker swatch button
-- Parameters:
--   parent: The parent frame to attach the swatch to
--   getColor: Function that returns {r, g, b, a} color table
--   setColor: Function(r, g, b, a) to set the color
--   hasAlpha: Boolean, whether to show opacity slider in color picker
-- Returns: The swatch button frame
function CreateColorSwatch(parent, getColor, setColor, hasAlpha)
    local swatch = CreateFrame("Button", nil, parent, "ColorSwatchTemplate")
    -- Apply ScooterMod swatch sizing: ~30% taller (18 -> 23), 3x wider (18 -> 54)
    swatch:SetSize(54, 23)
    
    -- Add black border background
    if swatch.SwatchBg then 
        swatch.SwatchBg:SetAllPoints(swatch)
        swatch.SwatchBg:SetColorTexture(0, 0, 0, 1)
        swatch.SwatchBg:Show()
    end
    
    -- Inset the color texture slightly to create visible border
    if swatch.Color then
        swatch.Color:ClearAllPoints()
        swatch.Color:SetPoint("TOPLEFT", swatch, "TOPLEFT", 2, -2)
        swatch.Color:SetPoint("BOTTOMRIGHT", swatch, "BOTTOMRIGHT", -2, 2)
    end
    
    -- Hide checkers pattern (we don't need transparency display)
    if swatch.Checkers then
        swatch.Checkers:Hide()
    end
    
    -- Resize normal texture if present
    if swatch:GetNormalTexture() then
        swatch:GetNormalTexture():SetAllPoints(swatch)
    end
    
    local function updateSwatchColor()
        local c = getColor() or {1, 1, 1, 1}
        if swatch.Color then 
            swatch.Color:SetColorTexture(c[1] or 1, c[2] or 1, c[3] or 1, 1) 
        end
    end
    
    swatch:SetScript("OnClick", function()
        local cur = getColor() or {1, 1, 1, 1}
        ColorPickerFrame:SetupColorPickerAndShow({
            r = cur[1] or 1,
            g = cur[2] or 1,
            b = cur[3] or 1,
            hasOpacity = hasAlpha,
            opacity = cur[4] or 1,
            swatchFunc = function()
                local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                local na = hasAlpha and ColorPickerFrame:GetColorAlpha() or 1
                setColor(nr, ng, nb, na)
                updateSwatchColor()
            end,
            cancelFunc = function(prev)
                if prev then
                    setColor(prev.r or 1, prev.g or 1, prev.b or 1, prev.a or 1)
                    updateSwatchColor()
                end
            end,
        })
    end)
    
    updateSwatchColor()
    return swatch
end

function CreateCheckboxWithSwatchInitializer(settingObj, label, getColor, setColor, offset)
    local data = { setting = settingObj, name = label, options = {} }
    local init = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", data)
    local baseInit = init.InitFrame
    init.InitFrame = function(self, frame)
        if baseInit then baseInit(self, frame) end
        local cb = frame.Checkbox or frame.CheckBox or frame.Control or frame
        local swatch = frame.ScooterInlineSwatch
        if cb and cb.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(cb.Text) end
        if frame and frame.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(frame.Text) end
        if not swatch then
            swatch = CreateFrame("Button", nil, frame, "ColorSwatchTemplate")
            -- Apply ScooterMod swatch sizing: ~30% taller (18 -> 23), 3x wider (18 -> 54)
            swatch:SetSize(54, 23)
            
            -- Add black border background
            if swatch.SwatchBg then 
                swatch.SwatchBg:SetAllPoints(swatch)
                swatch.SwatchBg:SetColorTexture(0, 0, 0, 1)
                swatch.SwatchBg:Show()
            end
            
            -- Inset the color texture slightly to create visible border
            if swatch.Color then
                swatch.Color:ClearAllPoints()
                swatch.Color:SetPoint("TOPLEFT", swatch, "TOPLEFT", 2, -2)
                swatch.Color:SetPoint("BOTTOMRIGHT", swatch, "BOTTOMRIGHT", -2, 2)
            end
            
            -- Hide checkers pattern (we don't need transparency display)
            if swatch.Checkers then
                swatch.Checkers:Hide()
            end
            
            -- Resize normal texture if present
            if swatch:GetNormalTexture() then
                swatch:GetNormalTexture():SetAllPoints(swatch)
            end
            
            frame.ScooterInlineSwatch = swatch
        end
        if panel and panel.ApplyControlTheme then panel.ApplyControlTheme(frame) end
        if cb and cb.Text then panel.ApplyRobotoWhite(cb.Text) end
        swatch:ClearAllPoints()
        local dx = tonumber(offset) or 8
        if cb and cb.Text and cb.Text.GetStringWidth then
            swatch:SetPoint("LEFT", cb.Text, "RIGHT", dx, 0)
        elseif cb and cb.GetObjectType and cb:GetObjectType() == "CheckButton" then
            swatch:SetPoint("LEFT", cb, "RIGHT", dx, 0)
        else
            swatch:SetPoint("LEFT", frame, "LEFT", 180, 0)
        end
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
        if frame.ScooterInlineSwatchWrapper and frame.OnSettingValueChanged == frame.ScooterInlineSwatchWrapper then
            frame.OnSettingValueChanged = frame.ScooterInlineSwatchBase
        end
        local baseOnSettingValueChanged = frame.OnSettingValueChanged
        local function scooterInlineSwatchWrapper(ctrl, setting, val)
            if baseOnSettingValueChanged then
                pcall(baseOnSettingValueChanged, ctrl, setting, val)
            end
            local effective = val
            if effective == nil then
                effective = settingObj:GetValue()
            end
            if ctrl.ScooterInlineSwatch then
                ctrl.ScooterInlineSwatch:SetShown((effective and true) or false)
            end
            local current = settingObj and settingObj.GetValue and settingObj:GetValue()
            if current ~= effective then
                if settingObj and settingObj.SetValue then pcall(settingObj.SetValue, settingObj, effective) end
            end
            if addon and addon.ApplyStyles then
                addon:ApplyStyles()
            end
        end
        frame.ScooterInlineSwatchBase = baseOnSettingValueChanged
        frame.ScooterInlineSwatchWrapper = scooterInlineSwatchWrapper
        frame.OnSettingValueChanged = scooterInlineSwatchWrapper
        if cb then
            local canUseCallback = cb.RegisterCallback and SettingsCheckboxMixin and SettingsCheckboxMixin.Event
            if canUseCallback and cb.ScooterInlineSwatchCallbackOwner and cb.UnregisterCallback then
                cb:UnregisterCallback(SettingsCheckboxMixin.Event.OnValueChanged, cb.ScooterInlineSwatchCallbackOwner)
            end
            if canUseCallback then
                local function updateFromCheckbox(ownerFrame, newValue)
                    if ownerFrame and ownerFrame.ScooterInlineSwatch then
                        ownerFrame.ScooterInlineSwatch:SetShown((newValue and true) or false)
                    end
                    local st = ownerFrame and ownerFrame.GetSetting and ownerFrame:GetSetting() or settingObj
                    if st and st.GetValue and st.SetValue and st:GetValue() ~= newValue then
                        pcall(st.SetValue, st, newValue)
                    end
                    if addon and addon.ApplyStyles then
                        addon:ApplyStyles()
                    end
                end
                cb.ScooterInlineSwatchCallbackOwner = frame
                cb:RegisterCallback(SettingsCheckboxMixin.Event.OnValueChanged, updateFromCheckbox, frame)
            else
                cb.ScooterInlineSwatchCallbackOwner = nil
                if not cb.ScooterInlineSwatchFallbackHooked then
                    cb:HookScript("OnClick", function(button)
                        if frame and frame.ScooterInlineSwatch then
                            frame.ScooterInlineSwatch:SetShown((button:GetChecked() and true) or false)
                        end
                    end)
                    cb.ScooterInlineSwatchFallbackHooked = true
                end
            end
        end
    end
    init.reinitializeOnValueChanged = false
    return init
end

-- Guard default slider-vs-text input visibility after template Init()
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


