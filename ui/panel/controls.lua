local addonName, addon = ...

--[[============================================================================
    ██╗     ███████╗ ██████╗  █████╗  ██████╗██╗   ██╗
    ██║     ██╔════╝██╔════╝ ██╔══██╗██╔════╝╚██╗ ██╔╝
    ██║     █████╗  ██║  ███╗███████║██║      ╚████╔╝
    ██║     ██╔══╝  ██║   ██║██╔══██║██║       ╚██╔╝
    ███████╗███████╗╚██████╔╝██║  ██║╚██████╗   ██║
    ╚══════╝╚══════╝ ╚═════╝ ╚═╝  ╚═╝ ╚═════╝   ╚═╝

    ⚠️  WARNING: THIS IS LEGACY CODE - DO NOT MODIFY ⚠️

    This entire directory (ui/panel/) is the LEGACY UI system.

    The NEW UI is located in: ui/v2/

    This legacy code is kept only for backwards compatibility and will
    eventually be removed. ALL new development should happen in ui/v2/.

    If you are an AI assistant or developer reading this:
    - DO NOT add new features to files in ui/panel/
    - DO NOT modify files in ui/panel/ for new functionality
    - GO TO ui/v2/ for all UI work

============================================================================]]--

addon.SettingsPanel = addon.SettingsPanel or {}
local panel = addon.SettingsPanel

-- LEGACY: Expose helpers globally for builder modules
-- ⚠️ DO NOT MODIFY - Use ui/v2/ instead
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
        -- Attach simple metadata from the initializer so commit/Init logic can
        -- distinguish which logical setting this row represents.
        if self and self.data then
            if self.data.settingId then
                frame.ScooterSettingId = self.data.settingId
            end
            if self.data.componentId then
                frame.ScooterComponentId = self.data.componentId
            end
        end
        if frame.SliderWithSteppers then
            frame.SliderWithSteppers:Hide()
            if frame.SliderWithSteppers.EnableMouse then frame.SliderWithSteppers:EnableMouse(false) end
            if frame.SliderWithSteppers.SetEnabled then frame.SliderWithSteppers:SetEnabled(false) end
            local slider = frame.SliderWithSteppers.Slider
            if slider then
                if slider.EnableMouse then slider:EnableMouse(false) end
                if slider.SetEnabled then slider:SetEnabled(false) end
            end
        end
        local input = frame.ScooterTextInput
        if not input then
            input = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
            input:SetAutoFocus(false)
            input:SetWidth(120); input:SetHeight(24); input:SetJustifyH("CENTER")
            input:SetPoint("LEFT", frame, "CENTER", -40, 0)
            frame.ScooterTextInput = input
            local function restore()
                -- Try frame:GetSetting() first, fall back to initializer's setting
                local setting = (frame and frame.GetSetting and frame:GetSetting()) or (self and self.data and self.data.setting) or nil
                local value = setting and setting.GetValue and setting:GetValue() or nil
                input:SetText(value == nil and "" or string.format("%.0f", value))
            end
            local function commit()
                local function scheduleClear()
                    if not input then return end
                    local function clearInhibit()
                        if input then input.ScooterFocusInhibit = nil end
                    end
                    if C_Timer and C_Timer.After then
                        C_Timer.After(0.12, clearInhibit)
                    else
                        clearInhibit()
                    end
                end
                if input then
                    input.ScooterFocusInhibit = true
                end
                local num = roundPositionValue(tonumber(input:GetText()))
                if not num then restore(); scheduleClear(); return end
                local options = self:GetOptions()
                if options then
                    if options.minValue ~= nil then num = math.max(options.minValue, num) end
                    if options.maxValue ~= nil then num = math.min(options.maxValue, num) end
                end
                -- Try frame:GetSetting() first, fall back to initializer's setting
                local setting = (frame and frame.GetSetting and frame:GetSetting()) or (self and self.data and self.data.setting) or nil
                if setting and setting.GetValue and setting:GetValue() ~= num then
                    setting:SetValue(num)
                    -- For position X/Y text inputs, remember that we just authored
                    -- a value so that when the Settings list later reinitializes
                    -- the row (after Edit Mode Save/Apply), we can automatically
                    -- restore focus to this box. This mitigates the focus drop
                    -- caused by the late row rebuild described in HOLDING.md.
                    if panel and frame.ScooterSettingId and (frame.ScooterSettingId == "positionX" or frame.ScooterSettingId == "positionY") then
                        local pending = panel._pendingPositionRefocus or {}
                        pending.settingId = frame.ScooterSettingId
                        pending.settingName = setting.GetName and setting:GetName() or nil
                        if type(GetTime) == "function" then
                            pending.expire = GetTime() + 0.8
                        else
                            pending.expire = nil
                        end
                        panel._pendingPositionRefocus = pending
                    end
                else
                    input:SetText(string.format("%.0f", num))
                end
                scheduleClear()
            end
            input:SetScript("OnEnterPressed", function(b)
                commit()
                -- Delay ClearFocus to prevent Enter key from propagating after
                -- the EditBox releases keyboard focus. Without this delay, the
                -- Enter key can interact with other UI elements (e.g., addons
                -- like DialogKey, or platform-specific behaviors) and cause
                -- unintended actions like closing the settings panel.
                C_Timer.After(0, function()
                    if b and b.ClearFocus then b:ClearFocus() end
                end)
            end)
            input:SetScript("OnEditFocusLost", function(b) commit(); b:HighlightText(0, 0) end)
            input:SetScript("OnEscapePressed", function(b) b:ClearFocus(); restore() end)
        end
        -- Try frame:GetSetting() first, fall back to initializer's setting
        local setting = (frame and frame.GetSetting and frame:GetSetting()) or (self and self.data and self.data.setting) or nil
        local value = setting and setting.GetValue and setting:GetValue() or nil
        frame.ScooterTextInput:SetText(value == nil and "" or string.format("%.0f", value))
        if frame.ScooterTextInput then frame.ScooterTextInput:Show() end
        if frame.ScooterTextInput and not frame.ScooterTextInput.ScooterFocusHooks then
            frame.ScooterTextInput.ScooterFocusHooks = true
            frame.ScooterTextInput:HookScript("OnEditFocusGained", function(box)
                box.ScooterFocusInhibit = nil
            end)
            frame.ScooterTextInput:HookScript("OnEscapePressed", function(box)
                box.ScooterFocusInhibit = nil
            end)
        end
        if frame and not frame.ScooterFocusRetainHooked then
            frame.ScooterFocusRetainHooked = true
            frame:HookScript("OnMouseDown", function(rowFrame, button)
                if button ~= "LeftButton" then return end
                local box = rowFrame and rowFrame.ScooterTextInput
                if not box then return end
                local function attemptFocus(delay, retries)
                    if not box or not box:IsShown() or not box:IsVisible() or not box.SetFocus then return end
                    if box.ScooterFocusInhibit then
                        if retries <= 0 then return end
                        if C_Timer and C_Timer.After then
                            C_Timer.After(delay or 0.05, function()
                                attemptFocus(delay, retries - 1)
                            end)
                        end
                        return
                    end
                    if box.HasFocus and box:HasFocus() then return end
                    box:SetFocus()
                    if box.HighlightText then box:HighlightText(0, -1) end
                end
                if C_Timer and C_Timer.After then
                    C_Timer.After(0.01, function()
                        attemptFocus(0.05, 4)
                    end)
                else
                    attemptFocus(0, 0)
                end
            end)
        end
        -- IMPORTANT: Never override Blizzard methods (persistent taint). Use hooksecurefunc instead.
        if not frame.ScooterOnSettingValueChangedHooked then
            frame.ScooterOnSettingValueChangedHooked = true
            if hooksecurefunc and type(frame.OnSettingValueChanged) == "function" then
                hooksecurefunc(frame, "OnSettingValueChanged", function(ctrl, setting, val)
                    if not (ctrl and ctrl.ScooterTextInput) then return end
                    local s = setting
                    local function update()
                        if not (ctrl and ctrl.ScooterTextInput) then return end
                        local current = (s and s.GetValue) and s:GetValue() or nil
                        ctrl.ScooterTextInput:SetText(current == nil and "" or string.format("%.0f", current))
                    end
                    if C_Timer and C_Timer.After then
                        C_Timer.After(0, update)
                    else
                        update()
                    end
                end)
            end
        end
        if frame.ScooterTextInput and SettingsControlMixin and SettingsControlMixin.IsEnabled then frame.ScooterTextInput:SetEnabled(SettingsControlMixin.IsEnabled(frame)) end

        -- If a recent X/Y position edit was just committed, and this row
        -- corresponds to that same logical setting, auto-refocus the text box
        -- once the row has finished initializing. This specifically targets the
        -- second Settings row rebuild that occurs after Edit Mode save/apply,
        -- preventing it from stealing focus from the user's active input.
        if panel and panel._pendingPositionRefocus and frame.ScooterSettingId and (frame.ScooterSettingId == "positionX" or frame.ScooterSettingId == "positionY") then
            local pending = panel._pendingPositionRefocus
            local now = type(GetTime) == "function" and GetTime() or nil
            local withinWindow = (not pending.expire) or (now and now <= pending.expire)
            if withinWindow and frame.ScooterTextInput then
                -- Clear the pending flag so we only refocus once per commit.
                panel._pendingPositionRefocus = nil
                if C_Timer and C_Timer.After then
                    C_Timer.After(0, function()
                        if frame and frame.ScooterTextInput and frame.ScooterTextInput.SetFocus then
                            frame.ScooterTextInput:SetFocus()
                            if frame.ScooterTextInput.HighlightText then
                                frame.ScooterTextInput:HighlightText(0, -1)
                            end
                        end
                    end)
                else
                    if frame.ScooterTextInput and frame.ScooterTextInput.SetFocus then
                        frame.ScooterTextInput:SetFocus()
                        if frame.ScooterTextInput.HighlightText then
                            frame.ScooterTextInput:HighlightText(0, -1)
                        end
                    end
                end
            end
        end
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
        -- Defense-in-depth: recycled Settings rows may carry an unrelated Scooter info icon
        -- Swatch rows should NEVER carry any info icon. Remove any stray icon unconditionally.
        if frame and frame.ScooterInfoIcon then
            frame.ScooterInfoIcon:Hide()
            frame.ScooterInfoIcon:SetParent(nil)
            frame.ScooterInfoIcon = nil
        end
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
                -- Ensure default slider widgets are visible when no Scooter
                -- text-input override is active.
                if frame.ScooterTextInput then frame.ScooterTextInput:Hide() end
                if frame.SliderWithSteppers then frame.SliderWithSteppers:Show() end

                -- Defense-in-depth for label text on recycled Settings rows:
                -- when a Slider control is rebound to a new Setting, always
                -- refresh the visible label from the Setting's canonical name,
                -- but only for sliders that live inside the ScooterMod panel.
                local function belongsToScooterPanel(ctrl)
                    local p = ctrl
                    local root = addon and addon.SettingsPanel and addon.SettingsPanel.frame
                    while p do
                        if p == root then return true end
                        p = (p.GetParent and p:GetParent()) or nil
                    end
                    return false
                end

                if not belongsToScooterPanel(frame) then
                    return
                end

                local setting = frame.GetSetting and frame:GetSetting() or nil
                local name = setting and setting.GetName and setting:GetName() or nil
                local lbl = frame.Text or frame.Label
                if lbl and lbl.SetText and type(name) == "string" and name ~= "" then
                    lbl:SetText(name)
                end
            end)
        end
    end
end

-- Unified dropdown + inline color swatch control
-- Usage:
--   panel.DropdownWithInlineSwatch(parent, yRef, {
--       label = "Border Color",
--       getMode = function() return "texture"|"class"|"custom" end,
--       setMode = function(v) ... end,
--       getColor = function() return {r,g,b,a} or {r,g,b} end,
--       setColor = function(r,g,b,a) ... end,
--       options  = function() return Settings.CreateControlTextContainer():GetData() end (optional),
--       isEnabled = function() return true|false end (optional),
--       insideButton = true  -- RECOMMENDED: Always set to true for consistent spacing. Defaults to false if omitted, causing spacing issues.
--   })
function panel.DropdownWithInlineSwatch(parent, yRef, opts)
    opts = opts or {}
    local label = opts.label or "Color"
    local getMode = assert(opts.getMode, "getMode required")
    local setMode = assert(opts.setMode, "setMode required")
    local getColor = assert(opts.getColor, "getColor required")
    local setColor = assert(opts.setColor, "setColor required")

    local function defaultOptions()
        local c = Settings.CreateControlTextContainer()
        c:Add("texture", "Texture Original")
        c:Add("class", "Class Color")
        c:Add("custom", "Custom")
        return c:GetData()
    end
    local optionsFn = opts.options or defaultOptions

    local function applyEnabledState(frame, enabled)
        if frame and frame.Control and frame.Control.SetEnabled then
            frame.Control:SetEnabled(enabled and true or false)
        end
        local lbl = frame and (frame.Text or frame.Label)
        if lbl and lbl.SetTextColor then
            if enabled then lbl:SetTextColor(1, 1, 1, 1) else lbl:SetTextColor(0.6, 0.6, 0.6, 1) end
        end
    end

    -- Local refresh closure (defined after UI creation)
    local function localRefresh() end

    local modeSetting = CreateLocalSetting(label, "string",
        function() return getMode() end,
        function(v)
            setMode(v)
            -- Refresh swatch visibility immediately for this row only
            if localRefresh then localRefresh() end
        end,
        getMode())

    local initDrop = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", { name = label, setting = modeSetting, options = optionsFn })
    local row = CreateFrame("Frame", nil, parent, "SettingsDropdownControlTemplate")
    row.GetElementData = function() return initDrop end
    row:SetPoint("TOPLEFT", 4, yRef.y)
    row:SetPoint("TOPRIGHT", -16, yRef.y)
    initDrop:InitFrame(row)
    if row.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(row.Text) end
    -- Theme the dropdown button/steppers to ScooterMod green + Roboto.
    -- Most Settings dropdown rows expose the actual control as `row.Control`, but be defensive:
    -- only theme objects that look like a DropdownWithSteppers control to avoid setting the
    -- `_scooterDropdownThemed` flag on the wrong frame (which would block later theming).
    if panel and panel.ThemeDropdownWithSteppers then
        if row.Control then
            panel.ThemeDropdownWithSteppers(row.Control)
        elseif row.Dropdown then
            panel.ThemeDropdownWithSteppers(row)
        end
    end

    -- Inline swatch
    local swatchParent = (opts.insideButton and row.Control) or row
    -- Try to parent to the actual dropdown button when requested
    if opts.insideButton and row.Control then
        local btn = (row.Control.Dropdown and row.Control.Dropdown.Button) or row.Control.Button or row.Control
        if btn then swatchParent = btn end
    end
    local swatch = CreateFrame("Button", nil, swatchParent, "ColorSwatchTemplate")
    -- Make the swatch larger for visibility (approx 3x width)
    swatch:SetSize(54, 18)
    if opts.insideButton and swatchParent then
        swatch:SetPoint("RIGHT", swatchParent, "RIGHT", -22, 0)
    else
        if row.Control then
            -- Prefer to place to the right of the dropdown if possible
            swatch:SetPoint("LEFT", row.Control, "RIGHT", 8, 0)
        else
            -- Fallback: pin to the row's right edge
            swatch:SetPoint("RIGHT", row, "RIGHT", -16, 0)
        end
    end
    -- Add a clear black outline and tighten color rect
    if swatch.SwatchBg then
        swatch.SwatchBg:SetAllPoints(swatch)
        swatch.SwatchBg:SetColorTexture(0, 0, 0, 1) -- solid black outline background
        swatch.SwatchBg:Show()
    end
    if swatch.Color then
        swatch.Color:ClearAllPoints()
        swatch.Color:SetPoint("TOPLEFT", swatch, "TOPLEFT", 2, -2)
        swatch.Color:SetPoint("BOTTOMRIGHT", swatch, "BOTTOMRIGHT", -2, 2)
    end
    if swatch.Checkers then swatch.Checkers:Hide() end

    -- Ensure it renders above the dropdown pieces
    local ref = swatchParent or row
    swatch:SetFrameStrata((ref.GetFrameStrata and ref:GetFrameStrata()) or row:GetFrameStrata())
    local baseLvl = (ref.GetFrameLevel and ref:GetFrameLevel()) or (row:GetFrameLevel() or 0)
    swatch:SetFrameLevel(baseLvl + 6)

    -- Prevent clicks on the swatch from propagating to the dropdown button
    -- SetPropagateMouseClicks is protected during combat, so skip it then
    if swatch.SetPropagateMouseClicks and not (InCombatLockdown and InCombatLockdown()) then
        swatch:SetPropagateMouseClicks(false)
    end
    if swatch.RegisterForClicks then swatch:RegisterForClicks("LeftButtonUp") end
    swatch:SetScript("OnMouseDown", function() end)
    -- Normalize inner color texture if present
    if swatch.Color then
        swatch.Color:ClearAllPoints()
        swatch.Color:SetPoint("TOPLEFT", swatch, "TOPLEFT", 2, -2)
        swatch.Color:SetPoint("BOTTOMRIGHT", swatch, "BOTTOMRIGHT", -2, 2)
    end
    if swatch.Checkers then swatch.Checkers:Hide() end

    local function setSwatchVisual(r, g, b, a)
        if swatch.Color then
            swatch.Color:SetColorTexture(r or 1, g or 1, b or 1, 1)
        elseif swatch:GetNormalTexture() then
            swatch:GetNormalTexture():SetVertexColor(r or 1, g or 1, b or 1, a or 1)
        end
    end

    local function readColor()
        local c = getColor() or {1,1,1,1}
        local r,g,b,a
        if type(c) == "table" then
            r = c.r or c[1] or 1
            g = c.g or c[2] or 1
            b = c.b or c[3] or 1
            a = c.a or c[4] or 1
        end
        return r or 1, g or 1, b or 1, a or 1
    end

    setSwatchVisual(readColor())

    swatch:SetScript("OnClick", function()
        local r,g,b,a = readColor()
        ColorPickerFrame:SetupColorPickerAndShow({
            r = r, g = g, b = b,
            hasOpacity = true,
            opacity = a,
            swatchFunc = function()
                local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                local na = ColorPickerFrame:GetColorAlpha() or 1
                setColor(nr, ng, nb, na)
                setSwatchVisual(nr, ng, nb, na)
                if opts.onChanged then opts.onChanged() end
            end,
            cancelFunc = function(prev)
                if prev then
                    setColor(prev.r or 1, prev.g or 1, prev.b or 1, prev.a or 1)
                    setSwatchVisual(prev.r or 1, prev.g or 1, prev.b or 1, prev.a or 1)
                end
            end,
        })
    end)

    -- Live refresh logic wired to parent for ease of reuse
    localRefresh = function()
        local enabled = true
        if type(opts.isEnabled) == "function" then
            enabled = opts.isEnabled() and true or false
        end
        applyEnabledState(row, enabled)
        local mode = getMode()
        local isCustom = (mode == "custom")
        swatch:SetShown(enabled and isCustom)
        swatch:EnableMouse(enabled and isCustom)
        if enabled and isCustom then
            setSwatchVisual(readColor())
        end
    end

    localRefresh()

    if yRef and yRef.y then yRef.y = yRef.y - 34 end
    return row, swatch
end
