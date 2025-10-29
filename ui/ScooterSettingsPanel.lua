local addonName, addon = ...

addon.SettingsPanel = {}
local panel = addon.SettingsPanel

local function PlayerInCombat()
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        return true
    end
    if type(UnitAffectingCombat) == "function" then
        local inCombat = UnitAffectingCombat("player")
        if inCombat then
            return true
        end
    end
    return false
end

local function ShouldBlockForCombat()
    if panel._combatLocked then return true end
    return PlayerInCombat()
end

local function NotifyCombatLocked()
    if addon and addon.Print then
        addon:Print("ScooterMod will reopen once combat ends.")
    end
end

-- Optional refresh suspension to avoid flicker when visibility-related settings write to Edit Mode
panel._suspendRefresh = false
function panel.SuspendRefresh(seconds)
    panel._suspendRefresh = true
    local delay = tonumber(seconds) or 0.2
    if C_Timer and C_Timer.After then
        C_Timer.After(delay, function() panel._suspendRefresh = false end)
    else
        panel._suspendRefresh = false
    end
end

-- Profiles section visibility helper (ensures section contents hide immediately even if
-- the Settings list doesn't re-evaluate predicates quickly enough)
function panel.UpdateProfilesSectionVisibility()
    local widgets = panel._profileWidgets
    if not widgets then return end
    local showActive = panel:IsSectionExpanded("profilesManage", "ActiveLayout")
    if widgets.ActiveLayoutRow and widgets.ActiveLayoutRow:IsShown() ~= showActive then
        widgets.ActiveLayoutRow:SetShown(showActive)
    end
    local showSpec = panel:IsSectionExpanded("profilesManage", "SpecProfiles")
    if widgets.SpecEnabledRow and widgets.SpecEnabledRow:IsShown() ~= showSpec then
        widgets.SpecEnabledRow:SetShown(showSpec)
    end
end

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
    if not self._initializing and addon and addon.SettingsPanel then
        if addon.SettingsPanel.RefreshCurrentCategory then addon.SettingsPanel.RefreshCurrentCategory() end
    end
    -- Nudge profiles section rows immediately
    if addon and addon.SettingsPanel and type(addon.SettingsPanel.UpdateProfilesSectionVisibility) == "function" then
        addon.SettingsPanel:UpdateProfilesSectionVisibility()
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
    if panel._suspendRefresh then return end
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
    -- Remember tab (if any) for tabbed sections before rerender
    local activeTabIndex
    if settingsList and settingsList:GetNumChildren() > 0 then
        for i = 1, settingsList:GetNumChildren() do
            local child = select(i, settingsList:GetChildren())
            if child and child.TabA and child.TabB and child.tabsGroup and child.tabsGroup.GetSelectedIndex then
                activeTabIndex = child.tabsGroup:GetSelectedIndex()
                break
            end
        end
    end
    entry.render()
    if percent and sb and sb.SetScrollPercentage then
        C_Timer.After(0, function()
            if panel and panel.frame and panel.frame:IsShown() then
                pcall(sb.SetScrollPercentage, sb, percent)
            end
        end)
    end
    -- Restore tab after rerender
    if activeTabIndex and settingsList and settingsList:GetNumChildren() > 0 then
        C_Timer.After(0, function()
            for i = 1, settingsList:GetNumChildren() do
                local child = select(i, settingsList:GetChildren())
                if child and child.tabsGroup and child.tabsGroup.SelectAtIndex then
                    child.tabsGroup:SelectAtIndex(activeTabIndex)
                    break
                end
            end
        end)
    end
end

function panel.RefreshCurrentCategoryDeferred()
    if panel._suspendRefresh then return end
    C_Timer.After(0, function()
        if panel and not panel._suspendRefresh and panel.RefreshCurrentCategory then panel.RefreshCurrentCategory() end
    end)
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
        -- Re-wrap the recycler-provided frame each time; the Settings list reuses controls aggressively.
        -- We stash the original handler so we can reapply it and append our swatch visibility updater safely.
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
            -- The Settings list recycles controls heavily; we observed cases where the checkbox visual toggled
            -- but the underlying setting did not persist (causing tint to remain enabled and re-check on reload).
            -- Mirror the live checkbox state to the setting here to guarantee DB updates on every toggle.
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
            -- Prefer the checkbox mixin’s callback API so we get notified even when the control reuses the same frame.
            local canUseCallback = cb.RegisterCallback and SettingsCheckboxMixin and SettingsCheckboxMixin.Event
            if canUseCallback and cb.ScooterInlineSwatchCallbackOwner and cb.UnregisterCallback then
                cb:UnregisterCallback(SettingsCheckboxMixin.Event.OnValueChanged, cb.ScooterInlineSwatchCallbackOwner)
            end
            if canUseCallback then
                local function updateFromCheckbox(ownerFrame, newValue)
                    if ownerFrame and ownerFrame.ScooterInlineSwatch then
                        ownerFrame.ScooterInlineSwatch:SetShown((newValue and true) or false)
                    end
                    -- Mirror the state into the setting immediately to guarantee persistence even if the
                    -- base template skips a SetValue call for recycler reasons.
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
                -- Fallback for templates that don’t expose RegisterCallback (shouldn’t happen in retail, but guarded anyway).
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

            local orderedSections = {"Positioning", "Sizing", "Style", "Border", "Icon", "Text", "Misc"}
            local function RefreshCurrentCategoryDeferred()
                if panel and panel.RefreshCurrentCategoryDeferred then
                    panel.RefreshCurrentCategoryDeferred()
                end
            end
            for _, sectionName in ipairs(orderedSections) do
                if sectionName == "Text" then
                    local supportsText = component and component.settings and component.settings.supportsText
                    if supportsText then
                        -- Collapsible header for Text section, no extra header inside the tabbed control
                        local expInitializer = Settings.CreateElementInitializer("ScooterExpandableSectionTemplate", {
                            name = "Text",
                            sectionKey = "Text",
                            componentId = component.id,
                            expanded = panel:IsSectionExpanded(component.id, "Text"),
                        })
                        expInitializer.GetExtent = function() return 30 end
                        table.insert(init, expInitializer)

                        local function fmtInt(v) return tostring(math.floor((tonumber(v) or 0) + 0.5)) end
                        local function addSlider(parent, label, minV, maxV, step, getFunc, setFunc, yRef)
                            local options = Settings.CreateSliderOptions(minV, maxV, step)
                            options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return fmtInt(v) end)
                            local setting = CreateLocalSetting(label, "number", getFunc, setFunc, getFunc())
                            local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = label, setting = setting, options = options })
                            local f = CreateFrame("Frame", nil, parent, "SettingsSliderControlTemplate")
                            f.GetElementData = function() return initSlider end
                            f:SetPoint("TOPLEFT", 4, yRef.y)
                            f:SetPoint("TOPRIGHT", -16, yRef.y)
                            initSlider:InitFrame(f)
                            yRef.y = yRef.y - 34
                        end
                        local function addDropdown(parent, label, optsProvider, getFunc, setFunc, yRef)
                            local setting = CreateLocalSetting(label, "string", getFunc, setFunc, getFunc())
                            local initDrop = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", { name = label, setting = setting, options = optsProvider })
                            local f = CreateFrame("Frame", nil, parent, "SettingsDropdownControlTemplate")
                            f.GetElementData = function() return initDrop end
                            f:SetPoint("TOPLEFT", 4, yRef.y)
                            f:SetPoint("TOPRIGHT", -16, yRef.y)
                            initDrop:InitFrame(f)
                            -- If this dropdown is for a bar texture, swap to a WowStyle dropdown with custom menu entries
                            if addon.Media and addon.Media.GetBarTextureMenuEntries and string.find(string.lower(label or ""), "texture", 1, true) then
                                local dd = f.Control and f.Control.Dropdown
                                if dd and dd.SetupMenu then
                                    dd:SetupMenu(function(menu, root)
                                        local entries = addon.Media.GetBarTextureMenuEntries()
                                        for _, e in ipairs(entries) do
                                            root:CreateRadio(e.text, function()
                                                return setting:GetValue() == e.key
                                            end, function()
                                                setting:SetValue(e.key)
                                            end)
                                        end
                                    end)
                                end
                            end
                            -- If this is the Font dropdown, install font preview renderer
                            if type(label) == "string" and string.find(label, "Font") and f.Control and f.Control.Dropdown then
                                if addon.InitFontDropdown then
                                    addon.InitFontDropdown(f.Control.Dropdown, setting, optsProvider)
                                end
                            end
                            -- If this is a Bar Texture dropdown, attach a live preview swatch to the control row
                            if type(label) == "string" and string.find(string.lower(label), "texture", 1, true) and f.Control and f.Control.Dropdown then
                                if addon.InitBarTextureDropdown then
                                    addon.InitBarTextureDropdown(f.Control, setting)
                                end
                            end
                            yRef.y = yRef.y - 34
                        end
                        local function addStyle(parent, label, getFunc, setFunc, yRef)
                            local function styleOptions()
                                local container = Settings.CreateControlTextContainer();
                                container:Add("NONE", "Regular");
                                container:Add("OUTLINE", "Outline");
                                container:Add("THICKOUTLINE", "Thick Outline");
                                return container:GetData()
                            end
                            addDropdown(parent, label, styleOptions, getFunc, setFunc, yRef)
                        end
                        local function addColor(parent, label, hasAlpha, getFunc, setFunc, yRef)
                            local f = CreateFrame("Frame", nil, parent, "SettingsListElementTemplate")
                            f:SetHeight(26)
                            f:SetPoint("TOPLEFT", 4, yRef.y)
                            f:SetPoint("TOPRIGHT", -16, yRef.y)
                            f.Text:SetText(label)
                            local right = CreateFrame("Frame", nil, f)
                            right:SetSize(250, 26)
                            right:SetPoint("RIGHT", f, "RIGHT", -16, 0)
                            f.Text:ClearAllPoints()
                            f.Text:SetPoint("LEFT", f, "LEFT", 36.5, 0)
                            f.Text:SetPoint("RIGHT", right, "LEFT", 0, 0)
                            f.Text:SetJustifyH("LEFT")
                            local swatch = CreateFrame("Button", nil, right, "ColorSwatchTemplate")
                            swatch:SetPoint("LEFT", right, "LEFT", 8, 0)
                            local function update()
                                local r, g, b, a = getFunc()
                                if swatch.Color then swatch.Color:SetColorTexture(r or 1, g or 1, b or 1) end
                                swatch.a = a or 1
                            end
                            swatch:SetScript("OnClick", function()
                                local r, g, b, a = getFunc()
                                ColorPickerFrame:SetupColorPickerAndShow({
                                    r = r or 1, g = g or 1, b = b or 1,
                                    hasOpacity = hasAlpha,
                                    opacity = a or 1,
                                    swatchFunc = function()
                                        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                                        local na = hasAlpha and ColorPickerFrame:GetColorAlpha() or 1
                                        setFunc(nr, ng, nb, na)
                                        update()
                                    end,
                                    cancelFunc = function(prev)
                                        if prev then
                                            setFunc(prev.r or 1, prev.g or 1, prev.b or 1, prev.a or 1)
                                            update()
                                        end
                                    end,
                                })
                            end)
                            update()
                            yRef.y = yRef.y - 34
                        end

                        local tabAName, tabBName
                        if component and component.id == "trackedBuffs" then
                            tabAName, tabBName = "Stacks", "Cooldown"
                        elseif component and component.id == "trackedBars" then
                            tabAName, tabBName = "Name", "Duration"
                        else
                            tabAName, tabBName = "Charges", "Cooldowns"
                        end
                        local data = { sectionTitle = "", tabAText = tabAName, tabBText = tabBName }
                        data.build = function(frame)
                            local yA = { y = -50 }
                            local yB = { y = -50 }
                            local db = component.db
                            local function applyText()
                                addon:ApplyStyles()
                            end
                            local function fontOptions()
                                return addon.BuildFontOptionsContainer()
                            end

                            -- Page A labels vary per component
                            local labelA_Font, labelA_Size, labelA_Style, labelA_Color, labelA_OffsetX, labelA_OffsetY
                            if component and component.id == "trackedBuffs" then
                                labelA_Font, labelA_Size, labelA_Style, labelA_Color, labelA_OffsetX, labelA_OffsetY = "Stacks Font", "Stacks Font Size", "Stacks Style", "Stacks Color", "Stacks Offset X", "Stacks Offset Y"
                            elseif component and component.id == "trackedBars" then
                                labelA_Font, labelA_Size, labelA_Style, labelA_Color, labelA_OffsetX, labelA_OffsetY = "Name Font", "Name Font Size", "Name Style", "Name Color", "Name Offset X", "Name Offset Y"
                            else
                                labelA_Font, labelA_Size, labelA_Style, labelA_Color, labelA_OffsetX, labelA_OffsetY = "Charges Font", "Charges Font Size", "Charges Style", "Charges Color", "Charges Offset X", "Charges Offset Y"
                            end

                            addDropdown(frame.PageA, labelA_Font, fontOptions,
                                function()
                                    if component and component.id == "trackedBars" then
                                        return (db.textName and db.textName.fontFace) or "FRIZQT__"
                                    elseif component and component.id == "trackedBuffs" then
                                        return (db.textStacks and db.textStacks.fontFace) or "FRIZQT__"
                                    else
                                        return (db.textStacks and db.textStacks.fontFace) or "FRIZQT__"
                                    end
                                end,
                                function(v)
                                    if component and component.id == "trackedBars" then
                                        db.textName = db.textName or {}
                                        db.textName.fontFace = v
                                    else
                                        db.textStacks = db.textStacks or {}
                                        db.textStacks.fontFace = v
                                    end
                                    applyText()
                                end,
                                yA)
                            addSlider(frame.PageA, labelA_Size, 8, 32, 1,
                                function()
                                    if component and component.id == "trackedBars" then
                                        return (db.textName and db.textName.size) or 14
                                    else
                                        return (db.textStacks and db.textStacks.size) or 16
                                    end
                                end,
                                function(v)
                                    if component and component.id == "trackedBars" then
                                        db.textName = db.textName or {}
                                        db.textName.size = tonumber(v) or 14
                                    else
                                        db.textStacks = db.textStacks or {}
                                        db.textStacks.size = tonumber(v) or 16
                                    end
                                    applyText()
                                end,
                                yA)
                            addStyle(frame.PageA, labelA_Style,
                                function()
                                    if component and component.id == "trackedBars" then
                                        return (db.textName and db.textName.style) or "OUTLINE"
                                    else
                                        return (db.textStacks and db.textStacks.style) or "OUTLINE"
                                    end
                                end,
                                function(v)
                                    if component and component.id == "trackedBars" then
                                        db.textName = db.textName or {}
                                        db.textName.style = v
                                    else
                                        db.textStacks = db.textStacks or {}
                                        db.textStacks.style = v
                                    end
                                    applyText()
                                end,
                                yA)
                            addColor(frame.PageA, labelA_Color, true,
                                function()
                                    local c
                                    if component and component.id == "trackedBars" then
                                        c = (db.textName and db.textName.color) or {1,1,1,1}
                                    else
                                        c = (db.textStacks and db.textStacks.color) or {1,1,1,1}
                                    end
                                    return c[1], c[2], c[3], c[4]
                                end,
                                function(r,g,b,a)
                                    if component and component.id == "trackedBars" then
                                        db.textName = db.textName or {}
                                        db.textName.color = { r, g, b, a }
                                    else
                                        db.textStacks = db.textStacks or {}
                                        db.textStacks.color = { r, g, b, a }
                                    end
                                    applyText()
                                end,
                                yA)
                            addSlider(frame.PageA, labelA_OffsetX, -50, 50, 1,
                                function()
                                    if component and component.id == "trackedBars" then
                                        return (db.textName and db.textName.offset and db.textName.offset.x) or 0
                                    else
                                        return (db.textStacks and db.textStacks.offset and db.textStacks.offset.x) or 0
                                    end
                                end,
                                function(v)
                                    if component and component.id == "trackedBars" then
                                        db.textName = db.textName or {}
                                        db.textName.offset = db.textName.offset or {}
                                        db.textName.offset.x = tonumber(v) or 0
                                    else
                                        db.textStacks = db.textStacks or {}
                                        db.textStacks.offset = db.textStacks.offset or {}
                                        db.textStacks.offset.x = tonumber(v) or 0
                                    end
                                    applyText()
                                end,
                                yA)
                            addSlider(frame.PageA, labelA_OffsetY, -50, 50, 1,
                                function()
                                    if component and component.id == "trackedBars" then
                                        return (db.textName and db.textName.offset and db.textName.offset.y) or 0
                                    else
                                        return (db.textStacks and db.textStacks.offset and db.textStacks.offset.y) or 0
                                    end
                                end,
                                function(v)
                                    if component and component.id == "trackedBars" then
                                        db.textName = db.textName or {}
                                        db.textName.offset = db.textName.offset or {}
                                        db.textName.offset.y = tonumber(v) or 0
                                    else
                                        db.textStacks = db.textStacks or {}
                                        db.textStacks.offset = db.textStacks.offset or {}
                                        db.textStacks.offset.y = tonumber(v) or 0
                                    end
                                    applyText()
                                end,
                                yA)

                            -- Page B (Cooldown or Duration)
                            local labelB_Font = (component and component.id == "trackedBars") and "Duration Font" or "Cooldown Font"
                            local labelB_Size = (component and component.id == "trackedBars") and "Duration Font Size" or "Cooldown Font Size"
                            local labelB_Style = (component and component.id == "trackedBars") and "Duration Style" or "Cooldown Style"
                            local labelB_Color = (component and component.id == "trackedBars") and "Duration Color" or "Cooldown Color"
                            local labelB_OffsetX = (component and component.id == "trackedBars") and "Duration Offset X" or "Cooldown Offset X"
                            local labelB_OffsetY = (component and component.id == "trackedBars") and "Duration Offset Y" or "Cooldown Offset Y"

                            addDropdown(frame.PageB, labelB_Font, fontOptions,
                                function()
                                    if component and component.id == "trackedBars" then
                                        return (db.textDuration and db.textDuration.fontFace) or "FRIZQT__"
                                    else
                                        return (db.textCooldown and db.textCooldown.fontFace) or "FRIZQT__"
                                    end
                                end,
                                function(v)
                                    if component and component.id == "trackedBars" then
                                        db.textDuration = db.textDuration or {}
                                        db.textDuration.fontFace = v
                                    else
                                        db.textCooldown = db.textCooldown or {}
                                        db.textCooldown.fontFace = v
                                    end
                                    applyText()
                                end,
                                yB)
                            addSlider(frame.PageB, labelB_Size, 8, 32, 1,
                                function()
                                    if component and component.id == "trackedBars" then
                                        return (db.textDuration and db.textDuration.size) or 14
                                    else
                                        return (db.textCooldown and db.textCooldown.size) or 16
                                    end
                                end,
                                function(v)
                                    if component and component.id == "trackedBars" then
                                        db.textDuration = db.textDuration or {}
                                        db.textDuration.size = tonumber(v) or 14
                                    else
                                        db.textCooldown = db.textCooldown or {}
                                        db.textCooldown.size = tonumber(v) or 16
                                    end
                                    applyText()
                                end,
                                yB)
                            addStyle(frame.PageB, labelB_Style,
                                function()
                                    if component and component.id == "trackedBars" then
                                        return (db.textDuration and db.textDuration.style) or "OUTLINE"
                                    else
                                        return (db.textCooldown and db.textCooldown.style) or "OUTLINE"
                                    end
                                end,
                                function(v)
                                    if component and component.id == "trackedBars" then
                                        db.textDuration = db.textDuration or {}
                                        db.textDuration.style = v
                                    else
                                        db.textCooldown = db.textCooldown or {}
                                        db.textCooldown.style = v
                                    end
                                    applyText()
                                end,
                                yB)
                            addColor(frame.PageB, labelB_Color, true,
                                function()
                                    local c
                                    if component and component.id == "trackedBars" then
                                        c = (db.textDuration and db.textDuration.color) or {1,1,1,1}
                                    else
                                        c = (db.textCooldown and db.textCooldown.color) or {1,1,1,1}
                                    end
                                    return c[1], c[2], c[3], c[4]
                                end,
                                function(r,g,b,a)
                                    if component and component.id == "trackedBars" then
                                        db.textDuration = db.textDuration or {}
                                        db.textDuration.color = { r, g, b, a }
                                    else
                                        db.textCooldown = db.textCooldown or {}
                                        db.textCooldown.color = { r, g, b, a }
                                    end
                                    applyText()
                                end,
                                yB)
                            addSlider(frame.PageB, labelB_OffsetX, -50, 50, 1,
                                function()
                                    if component and component.id == "trackedBars" then
                                        return (db.textDuration and db.textDuration.offset and db.textDuration.offset.x) or 0
                                    else
                                        return (db.textCooldown and db.textCooldown.offset and db.textCooldown.offset.x) or 0
                                    end
                                end,
                                function(v)
                                    if component and component.id == "trackedBars" then
                                        db.textDuration = db.textDuration or {}
                                        db.textDuration.offset = db.textDuration.offset or {}
                                        db.textDuration.offset.x = tonumber(v) or 0
                                    else
                                        db.textCooldown = db.textCooldown or {}
                                        db.textCooldown.offset = db.textCooldown.offset or {}
                                        db.textCooldown.offset.x = tonumber(v) or 0
                                    end
                                    applyText()
                                end,
                                yB)
                            addSlider(frame.PageB, labelB_OffsetY, -50, 50, 1,
                                function()
                                    if component and component.id == "trackedBars" then
                                        return (db.textDuration and db.textDuration.offset and db.textDuration.offset.y) or 0
                                    else
                                        return (db.textCooldown and db.textCooldown.offset and db.textCooldown.offset.y) or 0
                                    end
                                end,
                                function(v)
                                    if component and component.id == "trackedBars" then
                                        db.textDuration = db.textDuration or {}
                                        db.textDuration.offset = db.textDuration.offset or {}
                                        db.textDuration.offset.y = tonumber(v) or 0
                                    else
                                        db.textCooldown = db.textCooldown or {}
                                        db.textCooldown.offset = db.textCooldown.offset or {}
                                        db.textCooldown.offset.y = tonumber(v) or 0
                                    end
                                    applyText()
                                end,
                                yB)
                        end
                        local initializer = Settings.CreateElementInitializer("ScooterTabbedSectionTemplate", data)
                        initializer.GetExtent = function() return 260 end
                        initializer:AddShownPredicate(function()
                            return panel:IsSectionExpanded(component.id, "Text")
                        end)
                        table.insert(init, initializer)
                    end
                elseif sectionName == "Style" and component and component.id == "trackedBars" then
                    -- Render Style as a tabbed section (Foreground / Background)
                    local expInitializer = Settings.CreateElementInitializer("ScooterExpandableSectionTemplate", {
                        name = "Style",
                        sectionKey = "Style",
                        componentId = component.id,
                        expanded = panel:IsSectionExpanded(component.id, "Style"),
                    })
                    expInitializer.GetExtent = function() return 30 end
                    table.insert(init, expInitializer)

                    local data = { sectionTitle = "", tabAText = "Foreground", tabBText = "Background" }
                    data.build = function(frame)
                        local yA = { y = -50 }
                        local yB = { y = -50 }
                        local db = component.db
                        local function refresh()
                            addon:ApplyStyles()
                        end
                        -- Add master toggle above tabs
        do
            -- Building the master toggle manually gives us tighter control over layout/state than a recycled initializer.
            local row = frame.EnableCustomTexturesRow
            if not row then
                row = CreateFrame("Frame", nil, frame, "SettingsCheckboxControlTemplate")
                row:SetPoint("TOPLEFT", 4, 0)
                row:SetPoint("TOPRIGHT", -16, 0)
                                frame.EnableCustomTexturesRow = row
                                if row.Checkbox then
                                    row.Checkbox:SetHitRectInsets(0, -220, 0, 0)
                                end
                            end

                            if row.Text then
                                row.Text:SetText("Enable Custom Textures")
                            end

                            local checkbox = row.Checkbox
                            if checkbox then
                                -- Persist DB + trigger ApplyStyles + refresh layout so dependent controls (border style) hide/show.
                                checkbox:SetChecked(db.styleEnableCustom ~= false)
                                checkbox.ScooterCustomTexturesDB = db
                                checkbox.ScooterCustomTexturesRefresh = refresh
                                checkbox.ScooterCustomTexturesRefreshLayout = RefreshCurrentCategoryDeferred
                                if not checkbox.ScooterCustomTexturesHooked then
                                    checkbox:HookScript("OnClick", function(btn)
                                        local checked = btn:GetChecked() and true or false
                                        local targetDb = btn.ScooterCustomTexturesDB
                                        if targetDb then
                                            targetDb.styleEnableCustom = checked
                                            if not checked then
                                                targetDb.borderStyle = "square"
                                            end
                                        end
                                        if btn.ScooterCustomTexturesRefresh then
                                            btn.ScooterCustomTexturesRefresh()
                                        end
                                        if btn.ScooterCustomTexturesRefreshLayout then
                                            btn.ScooterCustomTexturesRefreshLayout()
                                        end
                                    end)
                                    checkbox.ScooterCustomTexturesHooked = true
                                end
                            end
                        end
                        local function addDropdown(parent, label, optsProvider, getFunc, setFunc, yRef)
                            local setting = CreateLocalSetting(label, "string", getFunc, setFunc, getFunc())
                            local initDrop = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", { name = label, setting = setting, options = optsProvider })
                            local f = CreateFrame("Frame", nil, parent, "SettingsDropdownControlTemplate")
                            f.GetElementData = function() return initDrop end
                            f:SetPoint("TOPLEFT", 4, yRef.y)
                            f:SetPoint("TOPRIGHT", -16, yRef.y)
                            initDrop:InitFrame(f)
                            -- Keep the standard Settings options provider rendering. The provider strings carry |T previews.
                            if addon.InitBarTextureDropdown then addon.InitBarTextureDropdown(f.Control, setting) end
                            yRef.y = yRef.y - 34
                        end
                        local function addColor(parent, label, hasAlpha, getFunc, setFunc, yRef)
                            local f = CreateFrame("Frame", nil, parent, "SettingsListElementTemplate")
                            f:SetHeight(26)
                            f:SetPoint("TOPLEFT", 4, yRef.y)
                            f:SetPoint("TOPRIGHT", -16, yRef.y)
                            f.Text:SetText(label)
                            local right = CreateFrame("Frame", nil, f)
                            right:SetSize(250, 26)
                            right:SetPoint("RIGHT", f, "RIGHT", -16, 0)
                            f.Text:ClearAllPoints()
                            f.Text:SetPoint("LEFT", f, "LEFT", 36.5, 0)
                            f.Text:SetPoint("RIGHT", right, "LEFT", 0, 0)
                            f.Text:SetJustifyH("LEFT")
                            local swatch = CreateFrame("Button", nil, right, "ColorSwatchTemplate")
                            swatch:SetPoint("LEFT", right, "LEFT", 8, 0)
                            local function update()
                                local r, g, b, a = getFunc()
                                if swatch.Color then swatch.Color:SetColorTexture(r or 1, g or 1, b or 1) end
                                swatch.a = a or 1
                            end
                            swatch:SetScript("OnClick", function()
                                local r, g, b, a = getFunc()
                                ColorPickerFrame:SetupColorPickerAndShow({
                                    r = r or 1, g = g or 1, b = b or 1,
                                    hasOpacity = true,
                                    opacity = a or 1,
                                    swatchFunc = function()
                                        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                                        local na = ColorPickerFrame:GetColorAlpha()
                                        setFunc(nr, ng, nb, na)
                                        update(); refresh()
                                    end,
                                    cancelFunc = function(prev)
                                        if prev then setFunc(prev.r or 1, prev.g or 1, prev.b or 1, prev.a or 1); update(); refresh() end
                                    end,
                                })
                            end)
                            update()
                            yRef.y = yRef.y - 34
                        end
                        -- Foreground tab controls
                        addDropdown(frame.PageA, "Foreground Texture", addon.BuildBarTextureOptionsContainer,
                            function() return db.styleForegroundTexture or (component.settings.styleForegroundTexture and component.settings.styleForegroundTexture.default) end,
                            function(v) db.styleForegroundTexture = v; refresh() end, yA)
                        addColor(frame.PageA, "Foreground Color", true,
                            function() local c = db.styleForegroundColor or {1,1,1,1}; return c[1], c[2], c[3], c[4] end,
                            function(r,g,b,a) db.styleForegroundColor = {r,g,b,a}; end, yA)
                        -- Background tab controls
                        addDropdown(frame.PageB, "Background Texture", addon.BuildBarTextureOptionsContainer,
                            function() return db.styleBackgroundTexture or (component.settings.styleBackgroundTexture and component.settings.styleBackgroundTexture.default) end,
                            function(v) db.styleBackgroundTexture = v; refresh() end, yB)
                        addColor(frame.PageB, "Background Color", true,
                            function() local c = db.styleBackgroundColor or {1,1,1,0.9}; return c[1], c[2], c[3], c[4] end,
                            function(r,g,b,a) db.styleBackgroundColor = {r,g,b,a}; end, yB)
                    end
                    local initializer = Settings.CreateElementInitializer("ScooterTabbedSectionTemplate", data)
                    initializer.GetExtent = function() return 160 end
                    initializer:AddShownPredicate(function()
                        return panel:IsSectionExpanded(component.id, "Style")
                    end)
                    table.insert(init, initializer)
                elseif (sections[sectionName] and #sections[sectionName] > 0) or (sectionName == "Border" and component and component.settings and component.settings.supportsEmptyBorderSection) then
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

                    for _, item in ipairs(sections[sectionName] or {}) do
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
                        if (sectionName == "Border" and settingId == "borderTintColor") or (sectionName == "Icon" and settingId == "iconBorderTintColor") then
                            -- Skip: handled by unified tint row above
                        else
                        local settingObj = CreateLocalSetting(label, ui.type or "string",
                            function()
                                -- Important: do NOT treat false as nil. Only fall back to defaults when the DB value is truly nil,
                                -- otherwise Edit Mode–controlled checkboxes (false) will appear checked in Scoot after EM writes.
                                local v = component.db[settingId]
                                if v == nil then v = setting.default end
                                return v
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
                                        if settingId == "opacityOutOfCombat" then
                                            if ui.min then finalValue = math.max(ui.min, finalValue) end
                                            if ui.max then finalValue = math.min(ui.max, finalValue) end
                                        end
                                    end
                                else
                                    -- Fallback: attempt numeric, else raw
                                    finalValue = tonumber(v) or v
                                end

                                -- Avoid redundant writes that can bounce values (e.g., 50 -> 200)
                                local changed = component.db[settingId] ~= finalValue
                                component.db[settingId] = finalValue

                                if changed and (setting.type == "editmode" or settingId == "positionX" or settingId == "positionY") then
                                    -- Avoid UI flicker by preferring single-setting writes + SaveOnly for Visibility-area controls
                                    local function safeSaveOnly()
                                        if addon.EditMode and addon.EditMode.SaveOnly then addon.EditMode.SaveOnly() end
                                    end
                                    if settingId == "opacity" then
                                        if addon.SettingsPanel and addon.SettingsPanel.SuspendRefresh then addon.SettingsPanel.SuspendRefresh(0.25) end
                                        if addon.EditMode and addon.EditMode.SyncComponentSettingToEditMode then
                                            addon.EditMode.SyncComponentSettingToEditMode(component, "opacity")
                                            safeSaveOnly()
                                        end
                                    elseif settingId == "showTimer" or settingId == "showTooltip" or settingId == "hideWhenInactive" then
                                        if addon.SettingsPanel and addon.SettingsPanel.SuspendRefresh then addon.SettingsPanel.SuspendRefresh(0.25) end
                                        if addon.EditMode and addon.EditMode.SyncComponentSettingToEditMode then
                                            addon.EditMode.SyncComponentSettingToEditMode(component, settingId)
                                            safeSaveOnly()
                                        end
                                    elseif settingId == "visibilityMode" or settingId == "displayMode" then
                                        if addon.SettingsPanel and addon.SettingsPanel.SuspendRefresh then addon.SettingsPanel.SuspendRefresh(0.25) end
                                        if addon.EditMode and addon.EditMode.SyncComponentSettingToEditMode then
                                            addon.EditMode.SyncComponentSettingToEditMode(component, settingId)
                                            safeSaveOnly()
                                        end
                                    else
                                        -- Debounce EM writes slightly for other settings
                                        if addon.EditMode and addon.EditMode.SyncComponentToEditMode then
                                            C_Timer.After(0.05, function()
                                                if addon.EditMode then addon.EditMode.SyncComponentToEditMode(component) end
                                            end)
                                        end
                                    end
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

                                if ui.dynamicLabel or ui.dynamicValues or settingId == "orientation"
                                    or settingId == "iconBorderEnable" or settingId == "iconBorderTintEnable"
                                    or settingId == "iconBorderStyle" then
                                    RefreshCurrentCategoryDeferred()
                                end
                            end, setting.default)                        if ui.widget == "slider" then
                            local options = Settings.CreateSliderOptions(ui.min, ui.max, ui.step)
                            if settingId == "iconSize" then
                                options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v)
                                    local snapped = math.floor(v / 10 + 0.5) * 10
                                    return tostring(snapped)
                                end)
                            elseif settingId == "opacity" or settingId == "opacityOutOfCombat" then
                                options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v)
                                    return string.format("%d%%", math.floor((tonumber(v) or 0) + 0.5))
                                end)
                            else
                                options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return tostring(math.floor(v + 0.5)) end)
                            end
                            local data = { setting = settingObj, options = options, name = label }
                            local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", data)
                            initSlider:AddShownPredicate(function()
                                return panel:IsSectionExpanded(component.id, sectionName)
                            end)
                            if settingId == "iconBorderThickness" then
                                initSlider:AddShownPredicate(function()
                                    local db = component and component.db
                                    if not db or not db.iconBorderEnable then return false end
                                    return panel:IsSectionExpanded(component.id, sectionName)
                                end)
                            end
                            -- Avoid recycler bounce on per-tick updates like opacity steppers
                            if settingId == "opacity" then
                                initSlider.reinitializeOnValueChanged = false
                            else
                                initSlider.reinitializeOnValueChanged = true
                            end
                            if settingId == "positionX" or settingId == "positionY" then ConvertSliderInitializerToTextInput(initSlider) end
                            if settingId == "opacity" then
                                -- Ensure the slider reflects the immediate write to EM by re-pulling DB on value change
                                local baseInit = initSlider.InitFrame
                                initSlider.InitFrame = function(self, frame)
                                    if baseInit then baseInit(self, frame) end
                                    if not frame.ScooterOpacityHooked then
                                        local original = frame.OnSettingValueChanged
                                        frame.OnSettingValueChanged = function(ctrl, setting, val)
                                            if original then pcall(original, ctrl, setting, val) end
                                            -- Pull latest from DB after EM write (raw percent expected)
                                            local cv = component.db.opacity or (component.settings.opacity and component.settings.opacity.default) or 100
                                            local c = ctrl:GetSetting()
                                            if c and c.SetValue and type(cv) == 'number' then
                                                c:SetValue(cv)
                                            end
                                        end
                                        frame.ScooterOpacityHooked = true
                                    end
                                    -- Also guard the underlying slider display to snap to multiples of 1 within 50..100
                                    if frame.SliderWithSteppers and frame.SliderWithSteppers.Slider then
                                        local s = frame.SliderWithSteppers.Slider
                                        if not s.ScooterBoundariesHooked then
                                            s:HookScript("OnValueChanged", function(slider, value)
                                                local v = math.max(50, math.min(100, math.floor((tonumber(value) or 0) + 0.5)))
                                                local c = frame:GetSetting()
                                                if c and c.SetValue and c:GetValue() ~= v then c:SetValue(v) end
                                            end)
                                            s.ScooterBoundariesHooked = true
                                        end
                                    end
                                end
                            end
                            table.insert(init, initSlider)
                        elseif ui.widget == "dropdown" then
                            local data
                            if ui.optionsProvider and type(ui.optionsProvider) == "function" then
                                data = { setting = settingObj, options = ui.optionsProvider, name = label }
                            elseif settingId == "borderStyle" then
                                if component and component.id == "trackedBars" then
                                    if addon.BuildBarBorderOptionsContainer then
                                        data = { setting = settingObj, options = addon.BuildBarBorderOptionsContainer, name = label }
                                    end
                                elseif addon.BuildIconBorderOptionsContainer then
                                    data = { setting = settingObj, options = addon.BuildIconBorderOptionsContainer, name = label }
                                end
                            else
                            local containerOpts = Settings.CreateControlTextContainer()
                            local orderedValues = {}
                            if settingId == "orientation" then
                                table.insert(orderedValues, "H"); table.insert(orderedValues, "V")
                            elseif settingId == "visibilityMode" then
                                -- Preserve RIP sorting order: always, combat, never
                                table.insert(orderedValues, "always")
                                table.insert(orderedValues, "combat")
                                table.insert(orderedValues, "never")
                            else
                                for val, _ in pairs(values) do table.insert(orderedValues, val) end
                            end
                            for _, valKey in ipairs(orderedValues) do containerOpts:Add(valKey, values[valKey]) end
                                data = { setting = settingObj, options = function() return containerOpts:GetData() end, name = label }
                            end
                            local initDrop = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", data)
                            local function shouldShowDropdown()
                                if not panel:IsSectionExpanded(component.id, sectionName) then
                                    return false
                                end
                                if component and component.id == "trackedBars" and settingId == "borderStyle" then
                                    local db = component and component.db
                                    return not db or db.styleEnableCustom ~= false
                                end
                                if settingId == "iconBorderStyle" then
                                    local db = component and component.db
                                    return db and db.iconBorderEnable and db.iconBorderEnable ~= false
                                end
                                return true
                            end
                            initDrop:AddShownPredicate(shouldShowDropdown)
                            if settingId == "visibilityMode" then
                                initDrop.reinitializeOnValueChanged = false
                            else
                                initDrop.reinitializeOnValueChanged = true
                            end
                            table.insert(init, initDrop)
                        elseif ui.widget == "checkbox" then
                            local data = { setting = settingObj, name = label, tooltip = ui.tooltip, options = {} }
                            if settingId == "borderTintEnable" or settingId == "iconBorderTintEnable" then
                                -- Use the reusable factory for checkbox + swatch
                                local colorKey = (settingId == "iconBorderTintEnable") and "iconBorderTintColor" or "borderTintColor"
                                local initCb = CreateCheckboxWithSwatchInitializer(
                                    settingObj,
                                    label,
                                    function()
                                        local val = component.db[colorKey]
                                        if val == nil and component.settings and component.settings[colorKey] then
                                            val = component.settings[colorKey].default
                                        end
                                        return val or {1,1,1,1}
                                    end,
                                    function(r, g, b, a)
                                        component.db[colorKey] = { r, g, b, a }
                                        addon:ApplyStyles()
                                    end,
                                    8
                                )
                                initCb:AddShownPredicate(function()
                                    if not panel:IsSectionExpanded(component.id, sectionName) then return false end
                                    if settingId == "iconBorderTintEnable" then
                                        local db = component and component.db
                                        return db and db.iconBorderEnable
                                    end
                                    return true
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
                                -- Generic checkbox initializer (no inline swatch). The Settings list recycles frames,
                                -- so make sure any swatch/callbacks from prior rows are fully hidden/removed here.
                                local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", data)
                                if settingId == "visibilityMode" or settingId == "opacity" or settingId == "showTimer" or settingId == "showTooltip" or settingId == "hideWhenInactive" then
                                    -- Avoid recycler flicker: do not reinitialize the control when value changes
                                    initCb.reinitializeOnValueChanged = false
                                end
                                initCb:AddShownPredicate(function()
                                    return panel:IsSectionExpanded(component.id, sectionName)
                                end)
                                local baseInitFrame = initCb.InitFrame
                                initCb.InitFrame = function(self, frame)
                                    if baseInitFrame then baseInitFrame(self, frame) end
                                    -- Hide any stray inline swatch from a previously-recycled tint row
                                    if frame.ScooterInlineSwatch then
                                        frame.ScooterInlineSwatch:Hide()
                                    end
                                    -- Restore original value-change wrapper if a tint row replaced it earlier
                                    if frame.ScooterInlineSwatchWrapper and frame.OnSettingValueChanged == frame.ScooterInlineSwatchWrapper then
                                        frame.OnSettingValueChanged = frame.ScooterInlineSwatchBase
                                    end
                                    -- Detach swatch-specific checkbox callbacks so this row behaves like a normal checkbox
                                    local cb = frame.Checkbox or frame.CheckBox or frame.Control or frame
                                    if cb and cb.UnregisterCallback and SettingsCheckboxMixin and SettingsCheckboxMixin.Event and cb.ScooterInlineSwatchCallbackOwner then
                                        cb:UnregisterCallback(SettingsCheckboxMixin.Event.OnValueChanged, cb.ScooterInlineSwatchCallbackOwner)
                                        cb.ScooterInlineSwatchCallbackOwner = nil
                                    end
                                end
                                -- Avoid recycler-induced visual bounce on checkbox value change; we keep default false above
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

local function renderProfilesManage()
    local function scaleFont(fs, baseFont, scale)
        if not fs or not baseFont then return end
        local face, size, flags = baseFont:GetFont()
        if face and size then
            fs:SetFont(face, math.floor(size * (scale or 1.0) + 0.5), flags)
        end
    end

    local function render()
        local f = panel.frame
        if not f or not f.SettingsList then return end
        local settingsList = f.SettingsList
        settingsList.Header.Title:SetText("Manage Profiles")

        local init = {}
        local widgets = panel._profileWidgets or {}
        panel._profileWidgets = widgets

        local function buildLayoutEntries()
            if not addon.Profiles or not addon.Profiles.GetLayoutMenuEntries then
                return {}
            end
            return addon.Profiles:GetLayoutMenuEntries()
        end

        local function getActiveProfileKey()
            if addon.Profiles and addon.Profiles.GetActiveProfile then
                return addon.Profiles:GetActiveProfile()
            end
            if addon.db and addon.db.GetCurrentProfile then
                return addon.db:GetCurrentProfile()
            end
            return nil
        end

        local function refreshActiveDropdown(dropdown)
            if not dropdown then return end
            local activeKey = getActiveProfileKey()
            local entries = buildLayoutEntries()
            local activeText = nil
            UIDropDownMenu_Initialize(dropdown, function(self)
                for _, entry in ipairs(entries) do
                    local info = UIDropDownMenu_CreateInfo()
                    info.text = entry.text
                    info.value = entry.key
                    info.func = function()
                        if entry.preset then
                            CloseDropDownMenus()
                            local currentKey = getActiveProfileKey()
                            addon.Profiles:PromptClonePreset(entry.key, dropdown, entry.text, currentKey)
                            return
                        end
                        local key = entry.key
                        if addon.Profiles and addon.Profiles.SwitchToProfile then
                            addon.Profiles:SwitchToProfile(key, { reason = "ManageProfilesDropdown" })
                        end
                        UIDropDownMenu_SetSelectedValue(dropdown, key)
                        UIDropDownMenu_SetText(dropdown, entry.text)
                        if panel and panel.RefreshCurrentCategoryDeferred then
                            panel.RefreshCurrentCategoryDeferred()
                        end
                    end
                    info.checked = (activeKey == entry.key)
                    info.notCheckable = false
                    info.isNotRadio = false
                    info.keepShownOnClick = false
                    UIDropDownMenu_AddButton(info)
                    if activeKey == entry.key then
                        activeText = entry.text
                    end
                end
            end)
            UIDropDownMenu_SetWidth(dropdown, 220)
            UIDropDownMenu_SetSelectedValue(dropdown, activeKey)
            UIDropDownMenu_SetText(dropdown, activeText or activeKey or "Select a layout")
            addon.SettingsPanel._profileDropdown = dropdown
            if addon.SettingsPanel and addon.SettingsPanel.UpdateProfileActionButtons then
                addon.SettingsPanel.UpdateProfileActionButtons()
            end
        end

        local function refreshSpecDropdown(dropdown, specID)
            if not dropdown or not specID then return end
            local assigned = addon.Profiles and addon.Profiles.GetSpecAssignment and addon.Profiles:GetSpecAssignment(specID) or nil
            local entries = buildLayoutEntries()
            UIDropDownMenu_Initialize(dropdown, function(self)
                local info = UIDropDownMenu_CreateInfo()
                info.text = "Use active layout"
                info.value = ""
                info.func = function()
                    if addon.Profiles and addon.Profiles.SetSpecAssignment then
                        addon.Profiles:SetSpecAssignment(specID, nil)
                    end
                    UIDropDownMenu_SetSelectedValue(dropdown, "")
                    if addon.Profiles and addon.Profiles.IsSpecProfilesEnabled and addon.Profiles:IsSpecProfilesEnabled() then
                        if addon.Profiles.OnPlayerSpecChanged then
                            addon.Profiles:OnPlayerSpecChanged()
                        end
                    end
                    if panel and panel.RefreshCurrentCategoryDeferred then
                        panel.RefreshCurrentCategoryDeferred()
                    end
                end
                info.checked = assigned == nil
                info.notCheckable = false
                info.isNotRadio = false
                UIDropDownMenu_AddButton(info)

                for _, entry in ipairs(entries) do
                    local dropdownInfo = UIDropDownMenu_CreateInfo()
                    dropdownInfo.text = entry.text
                    dropdownInfo.value = entry.key
                    dropdownInfo.func = function()
                        local key = entry.key
                        if addon.Profiles and addon.Profiles.SetSpecAssignment then
                            addon.Profiles:SetSpecAssignment(specID, key)
                        end
                        UIDropDownMenu_SetSelectedValue(dropdown, key)
                        UIDropDownMenu_SetText(dropdown, entry.text)
                        if addon.Profiles and addon.Profiles.IsSpecProfilesEnabled and addon.Profiles:IsSpecProfilesEnabled() then
                            if addon.Profiles.OnPlayerSpecChanged then
                                addon.Profiles:OnPlayerSpecChanged()
                            end
                        end
                        if panel and panel.RefreshCurrentCategoryDeferred then
                            panel.RefreshCurrentCategoryDeferred()
                        end
                    end
                    dropdownInfo.checked = (assigned == entry.key)
                    dropdownInfo.notCheckable = false
                    dropdownInfo.isNotRadio = false
                    UIDropDownMenu_AddButton(dropdownInfo)
                end
            end)
            UIDropDownMenu_SetWidth(dropdown, 220)
            if assigned then
                local display = nil
                for _, entry in ipairs(entries) do
                    if entry.key == assigned then
                        display = entry.text
                        break
                    end
                end
                UIDropDownMenu_SetSelectedValue(dropdown, assigned)
                UIDropDownMenu_SetText(dropdown, display or assigned)
            else
                UIDropDownMenu_SetSelectedValue(dropdown, "")
                UIDropDownMenu_SetText(dropdown, "Use active layout")
            end
        end

        do
            local infoRow = Settings.CreateElementInitializer("SettingsListElementTemplate")
            infoRow.GetExtent = function() return 56 end
            infoRow.InitFrame = function(self, frame)
                EnsureCallbackContainer(frame)
                if frame.Text then frame.Text:Hide() end
                if not frame.InfoText then
                    local text = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
                    text:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, 4)
                    text:SetWidth(420)
                    text:SetJustifyH("LEFT")
                    text:SetJustifyV("TOP")
                    text:SetWordWrap(true)
                    text:SetText("ScooterMod profiles stay synchronized with Edit Mode layouts. Switch layouts here or via Edit Mode and ScooterMod will keep them in sync.")
                    scaleFont(text, GameFontHighlight, 1.2)
                    frame.InfoText = text
                end
            end
            table.insert(init, infoRow)
        end

		-- Section: Active Layout (expandable header like ActionBarsEnhanced)
		do
			local exp = Settings.CreateElementInitializer("ScooterExpandableSectionTemplate", {
				name = "Active Layout",
				sectionKey = "ActiveLayout",
				componentId = "profilesManage",
				expanded = panel:IsSectionExpanded("profilesManage", "ActiveLayout"),
			})
			exp.GetExtent = function() return 30 end
			table.insert(init, exp)
		end

		-- Active Layout content: dropdown on left, stacked Rename/Copy/Delete on right
		do
            -- Use a Scooter-specific list element template to keep a separate frame pool
            -- from other rows (prevents recycled widgets leaking across sections).
            local sectionRow = Settings.CreateElementInitializer("ScooterListElementTemplate")
            sectionRow.GetExtent = function() return 150 end
			sectionRow.InitFrame = function(self, frame)
				EnsureCallbackContainer(frame)
				if frame.Text then frame.Text:Hide() end
				if frame.ButtonContainer then frame.ButtonContainer:Hide() end
                -- Clean up recycled widgets from other initializers (e.g., Spec Profiles message row)
                if frame.MessageText then frame.MessageText:Hide() end
                if frame.SpecIcon then frame.SpecIcon:Hide() end
                if frame.SpecName then frame.SpecName:Hide() end
                if frame.SpecDropdown then frame.SpecDropdown:Hide() end
                -- mark so we can manage visibility reliably
                frame.IsScooterActiveLayoutRow = true

				-- Dropdown (left)
                if not frame.ActiveDropdown then
                    local dropdown = CreateFrame("Frame", nil, frame, "UIDropDownMenuTemplate")
                    dropdown:SetPoint("LEFT", frame, "LEFT", 16, 0)
                    dropdown.align = "LEFT"
                    dropdown:SetScale(1.5)
                    if UIDropDownMenu_SetWidth then UIDropDownMenu_SetWidth(dropdown, 170) end
                    if dropdown.SetWidth then dropdown:SetWidth(170) end
                    frame.ActiveDropdown = dropdown
                else
                    if UIDropDownMenu_SetWidth then UIDropDownMenu_SetWidth(frame.ActiveDropdown, 170) end
                    if frame.ActiveDropdown.SetWidth then frame.ActiveDropdown:SetWidth(170) end
                end
				refreshActiveDropdown(frame.ActiveDropdown)
				-- Keep a handle so we can force-hide on header collapse if needed
				local widgets = panel._profileWidgets or {}
				panel._profileWidgets = widgets
				widgets.ActiveLayoutRow = frame

				-- Right-side vertical buttons
				local function updateButtons()
					local current = getActiveProfileKey()
					local isPreset = current and addon.Profiles and addon.Profiles:IsPreset(current)
					if frame.RenameBtn then frame.RenameBtn:SetEnabled(not not current and not isPreset) end
					if frame.DeleteBtn then frame.DeleteBtn:SetEnabled(not not current and not isPreset) end
					if frame.CopyBtn then frame.CopyBtn:SetEnabled(not not current) end
				end

                local function scaleButton(btn)
                    if not btn then return end
                    local w, h = btn:GetSize()
                    btn:SetSize(math.floor(w * 1.25), math.floor(h * 1.25))
                    if btn.Text and btn.Text.GetFont then
                        local face, size, flags = btn.Text:GetFont()
                        if size then btn.Text:SetFont(face, math.floor(size * 1.25 + 0.5), flags) end
                    end
                end

                if not frame.RenameBtn then
					local btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
					btn:SetSize(120, 28)
					btn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -6)
					btn:SetText("Rename")
					btn:SetMotionScriptsWhileDisabled(true)
					btn:SetScript("OnClick", function()
						CloseDropDownMenus()
						local current = getActiveProfileKey()
						addon.Profiles:PromptRenameLayout(current, addon.SettingsPanel and addon.SettingsPanel._profileDropdown)
					end)
					frame.RenameBtn = btn
                    scaleButton(btn)
				end

				if not frame.CopyBtn then
					local btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
                    btn:SetSize(120, 28)
					btn:SetPoint("TOPRIGHT", frame.RenameBtn, "BOTTOMRIGHT", 0, -8)
					btn:SetText("Copy")
					btn:SetMotionScriptsWhileDisabled(true)
					btn:SetScript("OnClick", function()
						CloseDropDownMenus()
						local current = getActiveProfileKey()
						if not current then return end
						if addon.Profiles and addon.Profiles:IsPreset(current) then
							addon.Profiles:PromptClonePreset(current, addon.SettingsPanel and addon.SettingsPanel._profileDropdown, addon.Profiles:GetLayoutDisplayText(current), current)
						else
							addon.Profiles:PromptCopyLayout(current, addon.SettingsPanel and addon.SettingsPanel._profileDropdown)
						end
                    end)
                    frame.CopyBtn = btn
                    scaleButton(btn)
				end

				if not frame.DeleteBtn then
					local btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
                    btn:SetSize(120, 28)
					btn:SetPoint("TOPRIGHT", frame.CopyBtn, "BOTTOMRIGHT", 0, -8)
					btn:SetText(DELETE)
					btn:SetMotionScriptsWhileDisabled(true)
					btn:SetScript("OnClick", function()
						CloseDropDownMenus()
						local current = getActiveProfileKey()
						addon.Profiles:ConfirmDeleteLayout(current, addon.SettingsPanel and addon.SettingsPanel._profileDropdown)
					end)
                    frame.DeleteBtn = btn
                    scaleButton(btn)
				end

				function frame:UpdateButtons()
					updateButtons()
				end
				updateButtons()
				addon.SettingsPanel.UpdateProfileActionButtons = function()
					if frame and frame.UpdateButtons then frame:UpdateButtons() end
				end
			end
			sectionRow:AddShownPredicate(function()
				return panel:IsSectionExpanded("profilesManage", "ActiveLayout")
			end)
			table.insert(init, sectionRow)
		end

        -- Hide legacy active/actions rows (superseded by the section above)
        -- Intentionally removed from the initializer list

		-- Small spacer between sections
		do
			local spacer = Settings.CreateElementInitializer("SettingsListElementTemplate")
			spacer.GetExtent = function() return 12 end
			spacer.InitFrame = function(self, frame)
				EnsureCallbackContainer(frame)
				if frame.Text then frame.Text:Hide() end
			end
			table.insert(init, spacer)
		end

        do
            local buttonRow = Settings.CreateElementInitializer("SettingsListElementTemplate")
            buttonRow.GetExtent = function() return 0 end
            buttonRow.InitFrame = function(self, frame)
                EnsureCallbackContainer(frame)
                if frame.Text then frame.Text:Hide() end
                if frame.ButtonContainer then
                    frame.ButtonContainer:Hide()
                    frame.ButtonContainer:SetAlpha(0)
                    frame.ButtonContainer:EnableMouse(false)
                end
                frame:Hide()
            end
            buttonRow:AddShownPredicate(function() return false end)
            table.insert(init, buttonRow)
        end

		-- Section: Spec Profiles (expandable header)
		do
			local exp = Settings.CreateElementInitializer("ScooterExpandableSectionTemplate", {
				name = "Spec Profiles",
				sectionKey = "SpecProfiles",
				componentId = "profilesManage",
				expanded = panel:IsSectionExpanded("profilesManage", "SpecProfiles"),
			})
			exp.GetExtent = function() return 30 end
			table.insert(init, exp)
		end

        -- Remove old text header row; replaced by expandable header above

        do
            local messageRow = Settings.CreateElementInitializer("SettingsListElementTemplate")
            messageRow.GetExtent = function() return 32 end
            messageRow.InitFrame = function(self, frame)
                EnsureCallbackContainer(frame)
                if frame.Text then frame.Text:Hide() end
                -- Hide any Active Layout widgets if this frame was recycled
                if frame.ActiveDropdown then frame.ActiveDropdown:Hide() end
                if frame.RenameBtn then frame.RenameBtn:Hide() end
                if frame.CopyBtn then frame.CopyBtn:Hide() end
                if frame.DeleteBtn then frame.DeleteBtn:Hide() end
                if not frame.MessageText then
                    local text = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
                    text:SetPoint("LEFT", frame, "LEFT", 16, 0)
                    text:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
                    text:SetJustifyH("LEFT")
                    text:SetText("Spec profiles are coming soon.")
                    frame.MessageText = text
                else
                    frame.MessageText:Show()
                end
            end
            messageRow:AddShownPredicate(function()
                return panel:IsSectionExpanded("profilesManage", "SpecProfiles")
            end)
            table.insert(init, messageRow)
        end

        local specOptions = {} -- not implemented yet; render nothing for now
		for _, spec in ipairs(specOptions) do
            local specRow = Settings.CreateElementInitializer("SettingsListElementTemplate")
            specRow.GetExtent = function() return 42 end
            specRow.InitFrame = function(self, frame)
                EnsureCallbackContainer(frame)
                if frame.Text then frame.Text:Hide() end
                if not frame.SpecName then
                    local icon = frame:CreateTexture(nil, "ARTWORK")
                    icon:SetSize(28, 28)
                    icon:SetPoint("LEFT", frame, "LEFT", 16, 0)
                    frame.SpecIcon = icon

                    local name = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
                    name:SetPoint("LEFT", icon, "RIGHT", 8, 0)
                    scaleFont(name, GameFontNormal, 1.2)
                    frame.SpecName = name

                    local dropdown = CreateFrame("Frame", nil, frame, "UIDropDownMenuTemplate")
                    dropdown:SetPoint("LEFT", name, "RIGHT", 16, -2)
                    dropdown.align = "LEFT"
                    dropdown:SetScale(1.1)
                    frame.SpecDropdown = dropdown
                end
                if frame.SpecIcon then
                    if spec.icon then
                        frame.SpecIcon:SetTexture(spec.icon)
                        frame.SpecIcon:Show()
                    else
                        frame.SpecIcon:Hide()
                    end
                end
                if frame.SpecName then
                    frame.SpecName:SetText(spec.name or ("Spec " .. tostring(spec.specIndex)))
                end
                refreshSpecDropdown(frame.SpecDropdown, spec.specID)
            end
            specRow:AddShownPredicate(function() return false end)
            table.insert(init, specRow)
        end

        settingsList:Display(init)
        if settingsList.RepairDisplay then
            pcall(settingsList.RepairDisplay, settingsList, { EnumerateInitializers = function() return ipairs(init) end, GetInitializers = function() return init end })
        end
        settingsList:Show()
        if f.Canvas then
            f.Canvas:Hide()
        end
        if addon and addon.SettingsPanel and addon.SettingsPanel.UpdateProfilesSectionVisibility then
            addon.SettingsPanel:UpdateProfilesSectionVisibility()
        end

        -- Defensive: remove duplicate spec-enabled rows if recycling created extras
        do
            local seen = false
            if settingsList and settingsList.GetNumChildren then
                for i = 1, settingsList:GetNumChildren() do
                    local child = select(i, settingsList:GetChildren())
                    if child and child.IsScooterSpecEnabledRow then
                        if seen then
                            child:Hide(); child:SetParent(nil)
                        else
                            seen = true
                        end
                    end
                end
            end
        end
    end

    return { mode = "list", render = render, componentId = "profilesManage" }
end

local function renderProfilesPresets()
    local function render()
        local f = panel.frame
        if not f or not f.SettingsList then return end
        local settingsList = f.SettingsList
        settingsList.Header.Title:SetText("Presets")
        local init = {}
        local messageRow = Settings.CreateElementInitializer("SettingsListElementTemplate")
        messageRow.GetExtent = function() return 40 end
        messageRow.InitFrame = function(self, frame)
            EnsureCallbackContainer(frame)
            if not frame.MessageText then
                local text = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
                text:SetPoint("LEFT", frame, "LEFT", 16, 0)
                text:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
                text:SetJustifyH("LEFT")
                text:SetText("Preset collections are coming soon. For now, use Edit Mode to swap between Blizzard's Modern and Classic presets.")
                frame.MessageText = text
            end
        end
        table.insert(init, messageRow)

        settingsList:Display(init)
        if settingsList.RepairDisplay then
            pcall(settingsList.RepairDisplay, settingsList, { EnumerateInitializers = function() return ipairs(init) end, GetInitializers = function() return init end })
        end
        settingsList:Show()
        if f.Canvas then
            f.Canvas:Hide()
        end
    end
    return { mode = "list", render = render, componentId = "profilesPresets" }
end

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
    createCategory("Profiles", "Manage Profiles", 1, renderProfilesManage())
    createCategory("Profiles", "Presets", 2, renderProfilesPresets())
    createCategory("Cooldown Manager", "Essential Cooldowns", 11, renderEssentialCooldowns())
    createCategory("Cooldown Manager", "Utility Cooldowns", 12, renderUtilityCooldowns())
    -- Reorder: Tracked Buffs third, Tracked Bars last
    createCategory("Cooldown Manager", "Tracked Buffs", 13, renderTrackedBuffs())
    createCategory("Cooldown Manager", "Tracked Bars", 14, renderTrackedBars())
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
        -- Header Edit Mode button placed ~10% from right edge
        local headerEditBtn = CreateFrame("Button", nil, headerDrag, "UIPanelButtonTemplate")
        headerEditBtn:SetSize(140, 22)
        headerEditBtn.Text:SetText("Open Edit Mode")
        local function PositionHeaderEditBtn()
            local inset = math.floor((f:GetWidth() or 0) * 0.10)
            headerEditBtn:ClearAllPoints()
            headerEditBtn:SetPoint("RIGHT", headerDrag, "RIGHT", -inset, 0)
        end
        PositionHeaderEditBtn()
        f:HookScript("OnSizeChanged", function() PositionHeaderEditBtn() end)
        headerEditBtn:SetFrameLevel((headerDrag:GetFrameLevel() or 0) + 5)
        headerEditBtn:EnableMouse(true)
        headerEditBtn:SetScript("OnClick", function()
            if InCombatLockdown and InCombatLockdown() then
                if addon and addon.Print then addon:Print("Cannot open Edit Mode during combat.") end
                return
            end
            if SlashCmdList and SlashCmdList["EDITMODE"] then
                SlashCmdList["EDITMODE"]("")
            elseif RunBinding then
                RunBinding("TOGGLE_EDIT_MODE")
            else
                addon:Print("Use /editmode to open the layout manager.")
            end
            if panel and panel.frame and panel.frame:IsShown() then panel.frame:Hide() end
        end)
		-- Enable resizing via a bottom-right handle
		f:SetResizable(true)
		local resizeBtn = CreateFrame("Button", nil, f, "PanelResizeButtonTemplate")
		resizeBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 4)
		-- Reasonable bounds to keep layout sane
		resizeBtn:Init(f, 720, 480, 1600, 1200)
		resizeBtn:SetOnResizeCallback(function()
			-- Re-evaluate layout while dragging to keep list/canvas filling the area
			if panel and panel.RefreshCurrentCategory then panel.RefreshCurrentCategory() end
		end)
		resizeBtn:SetOnResizeStoppedCallback(function()
			if panel and panel.RefreshCurrentCategory then panel.RefreshCurrentCategory() end
		end)
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
                for _, key in ipairs({"Positioning","Sizing","Style","Border","Icon","Text","Misc","Visibility"}) do
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
    if panel.frame and panel.frame:IsShown() then
        panel._shouldReopenAfterCombat = false
        panel.frame:Hide()
        return
    end

    if ShouldBlockForCombat() then
        panel._shouldReopenAfterCombat = true
        NotifyCombatLocked()
        return
    end

    ShowPanel()
end

function panel:Open()
    if ShouldBlockForCombat() then
        panel._shouldReopenAfterCombat = true
        NotifyCombatLocked()
        return
    end
    ShowPanel()
end
