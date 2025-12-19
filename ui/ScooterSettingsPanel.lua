local addonName, addon = ...

addon.SettingsPanel = addon.SettingsPanel or {}
local panel = addon.SettingsPanel

-- Combat guard state: track whether to reopen panel when combat ends
panel._closedByCombat = false

local function IsPRDEnabled()
    return addon.FeatureToggles and addon.FeatureToggles.enablePRD
end

-- Base window background color/opacity for the ScooterMod settings frame.
-- You can tweak these values to taste:
--   r,g,b: 0 (black) to 1 (white)
--   a:     0 (fully transparent) to 1 (fully opaque)
-- Current defaults: slightly dark gray with medium-high opacity.
panel.WindowBackgroundColor = panel.WindowBackgroundColor or {
    r = 0.2,
    g = 0.2,
    b = 0.2,
    a = 0.8,
}

panel.UnitFrameCategoryToUnit = panel.UnitFrameCategoryToUnit or {
    ufPlayer = "Player",
    ufTarget = "Target",
    ufFocus  = "Focus",
    ufPet    = "Pet",
    ufToT    = "TargetOfTarget",
}

-- Optional refresh suspension to avoid flicker when visibility-related settings write to Edit Mode
panel._suspendRefresh = false
panel._queuedRefresh = false
function panel.SuspendRefresh(seconds)
    panel._suspendRefresh = true
    local delay = tonumber(seconds) or 0.2
    if C_Timer and C_Timer.After then
		C_Timer.After(delay, function()
			panel._suspendRefresh = false
			-- If a refresh was requested while suspended, run it now
			if panel._queuedRefresh and panel.RefreshCurrentCategory then
				panel._queuedRefresh = false
				panel.RefreshCurrentCategory()
			end
		end)
    else
		panel._suspendRefresh = false
		if panel._queuedRefresh and panel.RefreshCurrentCategory then
			panel._queuedRefresh = false
			panel.RefreshCurrentCategory()
		end
    end
end

-- Profiles section visibility helper (ensures section contents hide immediately even if
-- the Settings list doesn't re-evaluate predicates quickly enough)
function panel.UpdateProfilesSectionVisibility()
    local widgets = panel._profileWidgets
    if not widgets then return end

    -- Only actively manage visibility while the Manage Profiles page is the
    -- current category. When other categories are selected, we aggressively
    -- hide any cached rows so they cannot linger "behind" the panel or after
    -- the window is closed (e.g., Active Layout row floating in the world).
    local f = panel.frame
    local isProfilesManageActive = f and f.CurrentCategory == "profilesManage"

    if not isProfilesManageActive then
        -- Hide ALL frames that have ever been used for Active Layout widgets,
        -- not just the current reference (which may be stale due to recycling)
        if widgets.AllActiveLayoutFrames then
            for frameRef in pairs(widgets.AllActiveLayoutFrames) do
                if frameRef and type(frameRef.Hide) == "function" then
                    pcall(frameRef.Hide, frameRef)
                end
            end
        end
        if widgets.ActiveLayoutRow and widgets.ActiveLayoutRow:IsShown() then
            widgets.ActiveLayoutRow:Hide()
        end
        if widgets.SpecEnabledRow and widgets.SpecEnabledRow:IsShown() then
            widgets.SpecEnabledRow:Hide()
        end
        return
    end

    local showActive = panel:IsSectionExpanded("profilesManage", "ActiveLayout")
    if widgets.ActiveLayoutRow and widgets.ActiveLayoutRow:IsShown() ~= showActive then
        widgets.ActiveLayoutRow:SetShown(showActive)
    end

    local showSpec = panel:IsSectionExpanded("profilesManage", "SpecProfiles")
    if widgets.SpecEnabledRow and widgets.SpecEnabledRow:IsShown() ~= showSpec then
        widgets.SpecEnabledRow:SetShown(showSpec)
    end
end

panel.CategoryResetHandlers = panel.CategoryResetHandlers or {}
function panel.GetDefaultsHandlerForKey(key)
    if not key then
        return nil
    end

    if panel.CategoryResetHandlers and panel.CategoryResetHandlers[key] then
        return panel.CategoryResetHandlers[key]
    end

    local frame = panel and panel.frame
    local entry = frame and frame.CatRenderers and frame.CatRenderers[key]
    if entry and entry.componentId and addon and addon.ResetComponentToDefaults then
        local component = addon.Components and addon.Components[entry.componentId]
        if component then
            return function()
                return addon:ResetComponentToDefaults(entry.componentId)
            end
        end
    end

    if panel.UnitFrameCategoryToUnit and panel.UnitFrameCategoryToUnit[key] and addon and addon.ResetUnitFrameCategoryToDefaults then
        return function()
            return addon:ResetUnitFrameCategoryToDefaults(key)
        end
    end

    return nil
end

-- Header button visibility helper: hide "Collapse All" for non-component pages
function panel.UpdateCollapseButtonVisibility()
    local f = panel and panel.frame
    local header = f and f.RightPane and f.RightPane.Header
    if not header then return end
    local btn = header.CollapseAllButton
    if not btn then return end
    local hide = false
    local cat = f.CurrentCategory
    if cat and f.CatRenderers then
        local entry = f.CatRenderers[cat]
        -- Profiles pages and home page do not have collapsible component sections
        local compId = entry and entry.componentId
        local isApplyAll = compId and compId:match("^applyAll")
        if entry and (compId == "profilesManage" or compId == "profilesPresets" or compId == "profilesRules" or compId == "home" or isApplyAll) then
            hide = true
        end
        -- Manage visibility of the Cooldown Manager settings button (only on CDM component tabs)
        local cdmBtn = header.ScooterCDMButton
        if cdmBtn then
            local onCDMTab = false
            if entry and entry.componentId then
                local id = tostring(entry.componentId)
                if id == "essentialCooldowns" or id == "utilityCooldowns" or id == "trackedBuffs" or id == "trackedBars" then
                    onCDMTab = true
                end
            end
            cdmBtn:SetShown(onCDMTab and not hide)
        end
    end
    btn:SetShown(not hide)
end

function panel.UpdateDefaultsButtonState(key)
    local frame = panel and panel.frame
    local btn = frame and frame.DefaultsButton
    if not btn then return end

    key = key or (frame and frame.CurrentCategory)
    local handler = panel.GetDefaultsHandlerForKey and panel.GetDefaultsHandlerForKey(key) or nil
    btn.ScooterCurrentDefaultsHandler = handler
    btn.ScooterCurrentCategoryKey = key
    local shouldShow = handler ~= nil
    btn:SetShown(shouldShow)
    if btn.SetEnabled then
        btn:SetEnabled(shouldShow)
    end
end

panel._pendingComponentRefresh = panel._pendingComponentRefresh or {}

local function InvalidatePanelRightPane(pnl)
    if not pnl then
        return false
    end
    local rp = pnl.RightPane
    if rp and type(rp.Invalidate) == "function" then
        rp:Invalidate()
        return true
    end
    local frame = pnl.frame
    if frame and frame.RightPane and type(frame.RightPane.Invalidate) == "function" then
        frame.RightPane:Invalidate()
        return true
    end
    return false
end

function panel:HandleEditModeBackSync(componentId, settingId)
    if not componentId then
        return
    end

    self._pendingComponentRefresh = self._pendingComponentRefresh or {}
    self._pendingComponentRefresh[componentId] = true

    local frame = self.frame
    if not frame or not frame:IsShown() or not frame.CatRenderers then
        return
    end

    local currentKey = frame.CurrentCategory
    if not currentKey then
        return
    end

    local entry = frame.CatRenderers[currentKey]
    if not entry or entry.componentId ~= componentId then
        return
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if not panel or panel.frame ~= frame or not frame:IsShown() then
                return
            end
            if frame.CurrentCategory ~= currentKey then
                return
            end
            if panel.SelectCategory then
                panel.SelectCategory(currentKey)
            elseif panel.RefreshCurrentCategory then
                panel.RefreshCurrentCategory()
            else
                InvalidatePanelRightPane(panel)
                if entry and entry.render then
                    entry.render()
                end
            end
        end)
    else
        if self.SelectCategory then
            self.SelectCategory(currentKey)
        elseif self.RefreshCurrentCategory then
            self.RefreshCurrentCategory()
        else
            InvalidatePanelRightPane(self)
            if entry and entry.render then
                entry.render()
            end
        end
    end
end

-- Theming helpers moved to ui/panel/theme.lua

-- Collapsible section header (Keybindings-style) ---------------------------------
-- Expandable section mixin moved to ui/panel/mixins.lua

-- Tabbed section mixin moved to ui/panel/mixins.lua

-- Public: Re-render the currently selected category and preserve scroll position.
-- IMPORTANT (2025-11-17): This is a STRUCTURAL refresh only and should not be
-- used from per-control handlers (checkboxes, sliders, etc.) or from routine
-- Edit Mode save hooks. Those callers must instead update their own rows and
-- styling in place to avoid right-pane flicker.
function panel.RefreshCurrentCategory()
    local f = panel and panel.frame
    if not f or not f:IsShown() then
        panel._queuedRefresh = true
        return
    end
    panel._queuedRefresh = false
    if panel._suspendRefresh then return end
    local cat = f.CurrentCategory
    if not cat then return end
    if panel.SelectCategory then
        panel.SelectCategory(cat)
        return
    end
    if not f.CatRenderers then return end
    local entry = f.CatRenderers[cat]
    if not entry or not entry.render then return end
    entry.render()
end

function panel.RefreshCurrentCategoryDeferred()
    if panel._suspendRefresh then
        -- Queue a one-shot refresh to run when suspension ends.
        panel._queuedRefresh = true
        return
    end
    -- Check if panel is hidden BEFORE scheduling the deferred call
    -- to avoid any race conditions where the panel hides between
    -- scheduling and execution.
    if panel._panelClosing or (panel.frame and not panel.frame:IsShown()) then
        return
    end
    C_Timer.After(0, function()
        -- Double-check panel state when the deferred callback actually runs.
        -- This prevents orphaned UI elements when panel closes right after
        -- scheduling the callback.
        if panel._panelClosing then return end
        if panel and not panel._suspendRefresh and panel.RefreshCurrentCategory then
            -- RefreshCurrentCategory also checks IsShown() but we check again for safety
            if panel.frame and panel.frame:IsShown() then
                panel.RefreshCurrentCategory()
            end
        end
    end)
end

-- SetTitles moved to ui/panel/mixins.lua

-- EvaluateVisibility moved to ui/panel/mixins.lua

-- Roboto for tab text; selected=white, unselected=green
-- UpdateTabTheme moved to ui/panel/mixins.lua

-- Init moved to ui/panel/mixins.lua

-- Control helpers moved to ui/panel/controls.lua

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
                            if f.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(f.Text) end
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
                            local lbl = f and (f.Text or f.Label)
                            if lbl and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(lbl) end
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
                            -- If this is the Font dropdown (but not Font Style), install font preview renderer
                            if type(label) == "string" and string.find(label, "Font") and not string.find(label, "Style") and f.Control and f.Control.Dropdown then
                                if addon.InitFontDropdown then
                                    addon.InitFontDropdown(f.Control.Dropdown, setting, optsProvider)
                                end
                            end
							-- If this is the Font Style dropdown, normalize per-item rendering via a custom menu
							if type(label) == "string" and string.find(string.lower(label), "style", 1, true) and f.Control and f.Control.Dropdown then
								local dd = f.Control.Dropdown
								if dd and dd.SetupMenu then
									dd:SetupMenu(function(menu, root)
										local options = {
											{ key = "NONE", text = "Regular" },
											{ key = "OUTLINE", text = "Outline" },
											{ key = "THICKOUTLINE", text = "Thick Outline" },
											{ key = "HEAVYTHICKOUTLINE", text = "Heavy Thick Outline" },
											{ key = "SHADOW", text = "Shadow" },
											{ key = "SHADOWOUTLINE", text = "Shadow Outline" },
											{ key = "SHADOWTHICKOUTLINE", text = "Shadow Thick Outline" },
											{ key = "HEAVYSHADOWTHICKOUTLINE", text = "Heavy Shadow Thick Outline" },
										}
										for _, e in ipairs(options) do
											local desc = root:CreateRadio(e.text, function()
												return setting:GetValue() == e.key
											end, function()
												setting:SetValue(e.key)
											end)
											desc:AddInitializer(function(button)
												local face = (addon and addon.Fonts and (addon.Fonts.ROBOTO_MED or addon.Fonts.ROBOTO_REG)) or (select(1, GameFontNormal:GetFont()))
												if button and button.Text and button.Text.GetFont then
													local _, sz = button.Text:GetFont()
													button.Text:SetFont(face, sz or 12, "")
													if button.Text.SetTextColor then button.Text:SetTextColor(1, 1, 1, 1) end
												end
												if button and button.HookScript then
													button:HookScript("OnShow", function()
														if button.Text and button.Text.GetFont then
															local _, sz = button.Text:GetFont()
															button.Text:SetFont(face, sz or 12, "")
															if button.Text.SetTextColor then button.Text:SetTextColor(1, 1, 1, 1) end
														end
													end)
												end
												if C_Timer and C_Timer.After then C_Timer.After(0, function()
													if button and button.Text and button.Text.GetFont then
														local _, sz = button.Text:GetFont()
														button.Text:SetFont(face, sz or 12, "")
														if button.Text.SetTextColor then button.Text:SetTextColor(1, 1, 1, 1) end
													end
												end) end
											end)
										end
									end)
								end
							end
                            -- If this is a Bar Texture dropdown, attach a live preview swatch to the control row
                            if type(label) == "string" and string.find(string.lower(label), "texture", 1, true) and f.Control and f.Control.Dropdown then
                                if addon.InitBarTextureDropdown then
                                    addon.InitBarTextureDropdown(f.Control, setting)
                                end
                            end
                            if f.Control and panel.ThemeDropdownWithSteppers then panel.ThemeDropdownWithSteppers(f.Control) end
                            yRef.y = yRef.y - 34
                        end
                        local function addStyle(parent, label, getFunc, setFunc, yRef)
                            local function styleOptions()
                                local container = Settings.CreateControlTextContainer();
                                container:Add("NONE", "Regular");
                                container:Add("OUTLINE", "Outline");
                                container:Add("THICKOUTLINE", "Thick Outline");
                                container:Add("HEAVYTHICKOUTLINE", "Heavy Thick Outline");
                                container:Add("SHADOW", "Shadow");
                                container:Add("SHADOWOUTLINE", "Shadow Outline");
                                container:Add("SHADOWTHICKOUTLINE", "Shadow Thick Outline");
                                container:Add("HEAVYSHADOWTHICKOUTLINE", "Heavy Shadow Thick Outline");
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
                            if panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(f.Text) end
                            local right = CreateFrame("Frame", nil, f)
                            right:SetSize(250, 26)
                            right:SetPoint("RIGHT", f, "RIGHT", -16, 0)
                            f.Text:ClearAllPoints()
                            f.Text:SetPoint("LEFT", f, "LEFT", 36.5, 0)
                            f.Text:SetPoint("RIGHT", right, "LEFT", 0, 0)
                            f.Text:SetJustifyH("LEFT")
                            -- Use centralized color swatch factory
                            local function getColorTable()
                                local r, g, b, a = getFunc()
                                return {r or 1, g or 1, b or 1, a or 1}
                            end
                            local function setColorTable(r, g, b, a)
                                setFunc(r, g, b, a)
                            end
                            local swatch = CreateColorSwatch(right, getColorTable, setColorTable, hasAlpha)
                            swatch:SetPoint("LEFT", right, "LEFT", 8, 0)
                            yRef.y = yRef.y - 34
                        end

                        local tabAName, tabBName
                        if component and component.id == "trackedBuffs" then
                            tabAName, tabBName = "Stacks", "Cooldown"
                        elseif component and (component.id == "buffs" or component.id == "debuffs") then
                            tabAName, tabBName = "Stacks", "Duration"
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
                            if component and (component.id == "trackedBuffs" or component.id == "buffs" or component.id == "debuffs") then
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
                            addSlider(frame.PageA, labelA_Size, 6, 32, 1,
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
                            local isDurationTab = component and (component.id == "trackedBars" or component.id == "buffs" or component.id == "debuffs")
                            local textBKey = isDurationTab and "textDuration" or "textCooldown"
                            local labelBBase = isDurationTab and "Duration" or "Cooldown"
                            local labelB_Font = labelBBase .. " Font"
                            local labelB_Size = labelBBase .. " Font Size"
                            local labelB_Style = labelBBase .. " Style"
                            local labelB_Color = labelBBase .. " Color"
                            local labelB_OffsetX = labelBBase .. " Offset X"
                            local labelB_OffsetY = labelBBase .. " Offset Y"
                            local defaultBSize = (component and component.id == "trackedBars") and 14 or 16

                            addDropdown(frame.PageB, labelB_Font, fontOptions,
                                function()
                                    local cfg = db[textBKey]
                                    return (cfg and cfg.fontFace) or "FRIZQT__"
                                end,
                                function(v)
                                    db[textBKey] = db[textBKey] or {}
                                    db[textBKey].fontFace = v
                                    applyText()
                                end,
                                yB)
                            addSlider(frame.PageB, labelB_Size, 6, 32, 1,
                                function()
                                    local cfg = db[textBKey]
                                    return (cfg and cfg.size) or defaultBSize
                                end,
                                function(v)
                                    db[textBKey] = db[textBKey] or {}
                                    db[textBKey].size = tonumber(v) or defaultBSize
                                    applyText()
                                end,
                                yB)
                            addStyle(frame.PageB, labelB_Style,
                                function()
                                    local cfg = db[textBKey]
                                    return (cfg and cfg.style) or "OUTLINE"
                                end,
                                function(v)
                                    db[textBKey] = db[textBKey] or {}
                                    db[textBKey].style = v
                                    applyText()
                                end,
                                yB)
                            addColor(frame.PageB, labelB_Color, true,
                                function()
                                    local cfg = db[textBKey]
                                    local c = (cfg and cfg.color) or {1,1,1,1}
                                    return c[1], c[2], c[3], c[4]
                                end,
                                function(r,g,b,a)
                                    db[textBKey] = db[textBKey] or {}
                                    db[textBKey].color = { r, g, b, a }
                                    applyText()
                                end,
                                yB)
                            addSlider(frame.PageB, labelB_OffsetX, -50, 50, 1,
                                function()
                                    local cfg = db[textBKey]
                                    return (cfg and cfg.offset and cfg.offset.x) or 0
                                end,
                                function(v)
                                    db[textBKey] = db[textBKey] or {}
                                    db[textBKey].offset = db[textBKey].offset or {}
                                    db[textBKey].offset.x = tonumber(v) or 0
                                    applyText()
                                end,
                                yB)
                            addSlider(frame.PageB, labelB_OffsetY, -50, 50, 1,
                                function()
                                    local cfg = db[textBKey]
                                    return (cfg and cfg.offset and cfg.offset.y) or 0
                                end,
                                function(v)
                                    db[textBKey] = db[textBKey] or {}
                                    db[textBKey].offset = db[textBKey].offset or {}
                                    db[textBKey].offset.y = tonumber(v) or 0
                                    applyText()
                                end,
                                yB)
                        end
                        local initializer = Settings.CreateElementInitializer("ScooterTabbedSectionTemplate", data)
                        initializer.GetExtent = function() return 315 end
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
                row:SetHeight(26)
                frame.EnableCustomTexturesRow = row
            end
            row:Show()
            if row.SetFrameLevel then row:SetFrameLevel((frame:GetFrameLevel() or 1)) end
            if row.EnableMouse then row:EnableMouse(false) end
            if row.Checkbox then
                row.Checkbox:EnableMouse(true)
                if row.Checkbox.SetHitRectInsets then row.Checkbox:SetHitRectInsets(0, 0, 0, 0) end
            end

                            if row.Text then
                                row.Text:SetText("Enable Custom Textures")
                                if panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(row.Text) end
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
                            -- Use centralized color swatch factory with refresh callback
                            local function getColorTable()
                                local r, g, b, a = getFunc()
                                return {r or 1, g or 1, b or 1, a or 1}
                            end
                            local function setColorTable(r, g, b, a)
                                setFunc(r, g, b, a)
                                refresh()
                            end
                            local swatch = CreateColorSwatch(right, getColorTable, setColorTable, true)
                            swatch:SetPoint("LEFT", right, "LEFT", 8, 0)
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
                                    -- Avoid UI flicker by preferring single-setting writes + SaveOnly and coalesced ApplyChanges
                                    local function safeSaveOnly()
                                        if addon.EditMode and addon.EditMode.SaveOnly then addon.EditMode.SaveOnly() end
                                    end
                                    local function requestApply()
                                        if addon.EditMode and addon.EditMode.RequestApplyChanges then addon.EditMode.RequestApplyChanges(0.2) end
                                    end
                                    if settingId == "positionX" or settingId == "positionY" then
                                        -- Use position-only sync to avoid cascade of syncing all Edit Mode settings.
                                        -- The new SyncComponentPositionToEditMode handles Save/Apply internally,
                                        -- so we do NOT call safeSaveOnly()/requestApply() here to avoid double calls.
                                        if addon.EditMode and addon.EditMode.SyncComponentPositionToEditMode then
                                            -- Mark this as a recent position write so the back-sync layer
                                            -- can skip immediately re-writing the same offsets back into
                                            -- the DB. This prevents a second Settings row rebuild that
                                            -- would otherwise steal focus from the numeric text input.
                                            component._recentPositionWrite = component._recentPositionWrite or {}
                                            if type(GetTime) == "function" then
                                                component._recentPositionWrite.time = GetTime()
                                            else
                                                component._recentPositionWrite.time = nil
                                            end
                                            component._recentPositionWrite.x = component.db.positionX
                                            component._recentPositionWrite.y = component.db.positionY

                                            addon.EditMode.SyncComponentPositionToEditMode(component)
                                            -- NOTE: Do NOT call safeSaveOnly()/requestApply() here!
                                            -- SyncComponentPositionToEditMode handles Save/Apply internally.
                                        end
                                    elseif settingId == "opacity" then
                                        if addon.SettingsPanel and addon.SettingsPanel.SuspendRefresh then addon.SettingsPanel.SuspendRefresh(0.25) end
                                        if addon.EditMode and addon.EditMode.SyncComponentSettingToEditMode then
                                            addon.EditMode.SyncComponentSettingToEditMode(component, "opacity")
                                            safeSaveOnly(); requestApply()
                                        end
                                    elseif settingId == "showTimer" or settingId == "showTooltip" or settingId == "hideWhenInactive" then
                                        if addon.SettingsPanel and addon.SettingsPanel.SuspendRefresh then addon.SettingsPanel.SuspendRefresh(0.25) end
                                        if addon.EditMode and addon.EditMode.SyncComponentSettingToEditMode then
                                            addon.EditMode.SyncComponentSettingToEditMode(component, settingId)
                                            safeSaveOnly(); requestApply()
                                        end
                                    elseif settingId == "visibilityMode" or settingId == "displayMode" then
                                        if addon.SettingsPanel and addon.SettingsPanel.SuspendRefresh then addon.SettingsPanel.SuspendRefresh(0.25) end
                                        if addon.EditMode and addon.EditMode.SyncComponentSettingToEditMode then
                                            addon.EditMode.SyncComponentSettingToEditMode(component, settingId)
                                            safeSaveOnly(); requestApply()
                                        end
                                    else
                                        -- For other Edit Mode settings, write just this setting + SaveOnly, then coalesce ApplyChanges
                                        if addon.EditMode and addon.EditMode.SyncComponentSettingToEditMode then
                                            addon.EditMode.SyncComponentSettingToEditMode(component, settingId)
                                            safeSaveOnly(); requestApply()
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
                            elseif settingId == "borderThickness" or settingId == "iconBorderThickness" then
                                options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v)
                                    return string.format("%.1f", v)
                                end)
                            else
                                options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return tostring(math.floor(v + 0.5)) end)
                            end
                            local data = {
                                setting = settingObj,
                                options = options,
                                name = label,
                                -- Metadata consumed by shared helpers (e.g., numeric text inputs)
                                -- so that position sliders can participate in focus-retention
                                -- logic after Settings list reinitialization.
                                componentId = component.id,
                                settingId = settingId,
                            }
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
                            if settingId == "positionX" or settingId == "positionY" then
                                local disableTextInput = setting and setting.ui and setting.ui.disableTextInput
                                if not disableTextInput then
                                    ConvertSliderInitializerToTextInput(initSlider)
                                end
                            end
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
                                    if panel and panel.ApplyControlTheme then panel.ApplyControlTheme(frame) end
                                end
                            end
                            -- Always apply control theming after any previous InitFrame logic
                            do
                                local prev = initSlider.InitFrame
                                initSlider.InitFrame = function(self, frame)
                                    if prev then prev(self, frame) end
                                    if panel and panel.ApplyControlTheme then panel.ApplyControlTheme(frame) end
                                    -- Force label to white for readability
                                    local lbl = frame and (frame.Text or frame.Label)
                                    if not lbl then
                                        -- Fallback: find a left-anchored FontString
                                        if frame and frame.GetRegions then
                                            local regions = { frame:GetRegions() }
                                            for i = 1, #regions do
                                                local r = regions[i]
                                                if r and r.IsObjectType and r:IsObjectType("FontString") then
                                                    lbl = r; break
                                                end
                                            end
                                        end
                                    end
                                    if lbl and lbl.SetTextColor then panel.ApplyRobotoWhite(lbl) end
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
                            -- Keep dropdown visuals default, but set label to Roboto + white
                            do
                                local prev = initDrop.InitFrame
                                initDrop.InitFrame = function(self, frame)
                                    if prev then prev(self, frame) end
                                    local lbl = frame and (frame.Text or frame.Label)
                                    if lbl and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(lbl) end
                                end
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
                                    -- Force label to Roboto + white
                                    if cb and cb.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(cb.Text) end
                                    if frame and frame.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(frame.Text) end
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

-- renderProfilesManage moved to ui/panel/profiles_manage.lua

-- renderProfilesPresets moved to ui/panel/profiles_presets.lua

--------------------------------------------------------------------------------
-- Home Page Renderer
-- Displays an enlarged logo and title as the landing page for ScooterMod.
-- The top-left logo/title is hidden when on this page to avoid redundancy.
--------------------------------------------------------------------------------
function panel.RenderHome()
    return {
        mode = "list",
        componentId = "home",
        title = "Home",
        render = function()
            local f = panel.frame
            if not f or not panel.RightPane then return end

            -- Set the header title (empty for home page since we have our own)
            panel.RightPane:SetTitle("")

            -- Hide the header controls on home page
            local header = panel.RightPane.Header
            if header then
                if header.CollapseAllButton then header.CollapseAllButton:Hide() end
                if header.ScooterCDMButton then header.ScooterCDMButton:Hide() end
                if header.ScooterCopyFromLabel then header.ScooterCopyFromLabel:Hide() end
                if header.ScooterCopyFromDropdown then header.ScooterCopyFromDropdown:Hide() end
            end

            -- Hide the defaults button on home page
            if f.DefaultsButton then f.DefaultsButton:Hide() end

            -- Create (or reuse) the home page content frame
            local content = panel.RightPane.Content
            if not content then return end

            -- Clear any existing rows from other categories
            panel.RightPane:Invalidate()

            -- Create home content container if needed
            local homeFrame = content._ScooterHomeContent
            if not homeFrame then
                homeFrame = CreateFrame("Frame", nil, content)
                content._ScooterHomeContent = homeFrame
            end
            homeFrame:SetAllPoints(content)
            homeFrame:Show()

            -- Calculate center positioning based on content size
            local fonts = addon and addon.Fonts or nil

            -- Create or reuse the logo
            local logo = homeFrame._logo
            if not logo then
                logo = homeFrame:CreateTexture(nil, "ARTWORK")
                homeFrame._logo = logo
            end
            local logoSize = 180  -- 50% larger than previous 120px
            logo:SetSize(logoSize, logoSize)
            -- Try multiple extensions for the logo
            local function trySetIcon(tex, base)
                local candidates = { base .. ".png", base .. ".tga", base .. ".blp" }
                for _, p in ipairs(candidates) do
                    local ok = pcall(tex.SetTexture, tex, p)
                    if ok and tex:GetTexture() then return true end
                end
            end
            trySetIcon(logo, "Interface\\AddOns\\ScooterMod\\Scooter")
            pcall(logo.SetMask, logo, "Interface\\CharacterFrame\\TempPortraitAlphaMask")
            logo:Show()

            -- Create or reuse the "Welcome to" text (above the title)
            local welcomeText = homeFrame._welcomeText
            if not welcomeText then
                welcomeText = homeFrame:CreateFontString(nil, "OVERLAY")
                homeFrame._welcomeText = welcomeText
            end
            welcomeText:SetJustifyH("CENTER")
            -- White Roboto at 1/3 of title size (63 / 3 = 21)
            if fonts and fonts.ROBOTO then
                welcomeText:SetFont(fonts.ROBOTO, 21, "OUTLINE")
            elseif fonts and fonts.ROBOTO_BLD then
                welcomeText:SetFont(fonts.ROBOTO_BLD, 21, "OUTLINE")
            else
                welcomeText:SetFont("Fonts\\ARIALN.TTF", 21, "OUTLINE")
            end
            welcomeText:SetShadowColor(0, 0, 0, 1)
            welcomeText:SetShadowOffset(1, -1)
            welcomeText:SetTextColor(1, 1, 1, 1)  -- White
            welcomeText:SetText("Welcome to")
            welcomeText:Show()

            -- Create or reuse the title text
            local title = homeFrame._title
            if not title then
                title = homeFrame:CreateFontString(nil, "OVERLAY")
                homeFrame._title = title
            end
            title:SetJustifyH("LEFT")
            -- Use Roboto Bold at 50% larger size (42 * 1.5 = 63)
            if fonts and fonts.ROBOTO_BLD then
                title:SetFont(fonts.ROBOTO_BLD, 63, "THICKOUTLINE")
            else
                title:SetFont("Fonts\\ARIALN.TTF", 63, "THICKOUTLINE")
            end
            title:SetShadowColor(0, 0, 0, 1)
            title:SetShadowOffset(2, -2)
            title:SetTextColor(0.2, 0.9, 0.3, 1)  -- ScooterMod green
            title:SetText("ScooterMod")
            title:Show()

            -- Position logo and title together, centered horizontally in the content area
            -- Layout: [Logo] [Welcome to / Title stacked] centered as a group
            local titleWidth = title:GetStringWidth() or 300
            local spacing = 20  -- Gap between logo and title text block
            local totalWidth = logoSize + spacing + titleWidth
            
            -- Calculate left offset to center the group
            local function UpdateHomeLayout()
                local contentWidth = content:GetWidth() or 400
                local contentHeight = content:GetHeight() or 600
                local leftOffset = (contentWidth - totalWidth) / 2
                local verticalCenter = -contentHeight / 3  -- Position in upper-third for visual balance
                
                logo:ClearAllPoints()
                logo:SetPoint("TOPLEFT", homeFrame, "TOPLEFT", math.max(0, leftOffset), verticalCenter)
                
                -- Title positioned to the right of the logo, vertically centered with it
                title:ClearAllPoints()
                title:SetPoint("LEFT", logo, "RIGHT", spacing, -10)
                
                -- "Welcome to" centered above the title
                welcomeText:ClearAllPoints()
                welcomeText:SetPoint("BOTTOM", title, "TOP", 0, 4)
                welcomeText:SetPoint("LEFT", title, "LEFT", 0, 0)
            end
            UpdateHomeLayout()

            -- Update layout on resize
            if not homeFrame._layoutHooked then
                content:HookScript("OnSizeChanged", function()
                    if homeFrame:IsShown() then
                        UpdateHomeLayout()
                    end
                end)
                homeFrame._layoutHooked = true
            end

            -- Set content height for scrolling (though home page doesn't need scrolling)
            content:SetHeight(400)
        end,
    }
end

--------------------------------------------------------------------------------
-- Interface Placeholder Renderers
--------------------------------------------------------------------------------
local function createInterfaceInfoRow(message)
    local row = Settings.CreateElementInitializer("SettingsListElementTemplate")
    row.GetExtent = function() return 96 end
    row.InitFrame = function(self, frame)
        EnsureCallbackContainer(frame)
        if frame.Text then frame.Text:Hide() end
        if frame.ButtonContainer then frame.ButtonContainer:Hide(); frame.ButtonContainer:SetAlpha(0); frame.ButtonContainer:EnableMouse(false) end
        if frame.InfoText then frame.InfoText:Hide() end

        if not frame.ScooterInterfaceInfoText then
            local info = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
            info:SetPoint("TOPLEFT", frame, "TOPLEFT", 24, -6)
            info:SetPoint("RIGHT", frame, "RIGHT", -24, 0)
            info:SetJustifyH("LEFT")
            info:SetJustifyV("TOP")
            info:SetWordWrap(true)
            if panel.ApplyRobotoWhite then
                panel.ApplyRobotoWhite(info, 16, "")
            end
            frame.ScooterInterfaceInfoText = info
        end

        frame.ScooterInterfaceInfoText:SetText(message or "")
        frame.ScooterInterfaceInfoText:Show()
        local textHeight = frame.ScooterInterfaceInfoText:GetStringHeight() or 0
        frame:SetHeight(math.max(70, textHeight + 32))
    end
    return row
end

local function createComingSoonRenderer(componentId, title)
    local function render()
        local f = panel.frame
        local right = f and f.RightPane
        if not f or not right or not right.Display then
            return
        end
        if right.SetTitle then
            right:SetTitle(title or componentId)
        end

        local init = {}
        table.insert(init, createInterfaceInfoRow("Coming soon..."))
        right:Display(init)
    end

    return { mode = "list", render = render, componentId = componentId }
end

function panel.RenderMinimap()
    return createComingSoonRenderer("minimap", "Minimap")
end

function panel.RenderQuestLog()
    return createComingSoonRenderer("questLog", "Quest Log")
end

local function BuildCategories()
	local f = panel.frame
	if f.CategoriesBuilt then return end

	-- Persist sidebar expanded state per parent name within this session
	panel._sidebarExpanded = panel._sidebarExpanded or {}

	-- Build renderers mapping keyed by stable string keys
	local catRenderers = {}

	local function addEntry(key, renderer)
		catRenderers[key] = renderer
	end

	-- Home page (landing page)
	addEntry("home", addon.SettingsPanel.RenderHome())

	-- Profiles / Apply All children
	addEntry("profilesManage", addon.SettingsPanel.RenderProfilesManage())
	addEntry("profilesPresets", addon.SettingsPanel.RenderProfilesPresets())
	addEntry("profilesRules", addon.SettingsPanel.RenderProfilesRules())
	addEntry("applyAllFonts", addon.SettingsPanel.RenderApplyAllFonts())
	addEntry("applyAllTextures", addon.SettingsPanel.RenderApplyAllTextures())

	-- Cooldown Manager children
	addEntry("essentialCooldowns", addon.SettingsPanel.RenderEssentialCooldowns())
	addEntry("utilityCooldowns", addon.SettingsPanel.RenderUtilityCooldowns())
	addEntry("trackedBuffs", addon.SettingsPanel.RenderTrackedBuffs())
	addEntry("trackedBars", addon.SettingsPanel.RenderTrackedBars())
    addEntry("sctDamage", addon.SettingsPanel.RenderSCTDamage())
    addEntry("sctHealing", addon.SettingsPanel.RenderSCTHealing())
    if IsPRDEnabled() then
        addEntry("prdGlobal", addon.SettingsPanel.RenderPRDGlobal())
        addEntry("prdHealth", addon.SettingsPanel.RenderPRDHealth())
        addEntry("prdPower", addon.SettingsPanel.RenderPRDPower())
        addEntry("prdClassResource", addon.SettingsPanel.RenderPRDClassResource())
    end
	addEntry("nameplatesUnit", addon.SettingsPanel.RenderNameplatesUnit())

	-- Action Bars children
	addEntry("actionBar1", addon.SettingsPanel.RenderActionBar1())
	-- Unit Frames children
	addEntry("ufPlayer", addon.SettingsPanel.RenderUFPlayer())
	addEntry("ufTarget", addon.SettingsPanel.RenderUFTarget())
	addEntry("ufFocus",  addon.SettingsPanel.RenderUFFocus())
	addEntry("ufPet",    addon.SettingsPanel.RenderUFPet())
	addEntry("ufToT",    addon.SettingsPanel.RenderUFToT())
	-- Group Frames children
	addEntry("gfParty", addon.SettingsPanel.RenderGFParty())
	addEntry("gfRaid",  addon.SettingsPanel.RenderGFRaid())
    -- Buffs/Debuffs children (scaffolded)
    addEntry("buffs",   addon.SettingsPanel.RenderBuffs())
    addEntry("debuffs", addon.SettingsPanel.RenderDebuffs())
	addEntry("actionBar2", addon.SettingsPanel.RenderActionBar2())
	addEntry("actionBar3", addon.SettingsPanel.RenderActionBar3())
	addEntry("actionBar4", addon.SettingsPanel.RenderActionBar4())
	addEntry("actionBar5", addon.SettingsPanel.RenderActionBar5())
	addEntry("actionBar6", addon.SettingsPanel.RenderActionBar6())
	addEntry("actionBar7", addon.SettingsPanel.RenderActionBar7())
	addEntry("actionBar8", addon.SettingsPanel.RenderActionBar8())
	addEntry("petBar", addon.SettingsPanel.RenderPetBar())
	addEntry("stanceBar", addon.SettingsPanel.RenderStanceBar())
	addEntry("microBar", addon.SettingsPanel.RenderMicroBar())

	-- Interface children
	addEntry("tooltip", addon.SettingsPanel.RenderTooltip())
    addEntry("minimap", addon.SettingsPanel.RenderMinimap())
    addEntry("questLog", addon.SettingsPanel.RenderQuestLog())

	-- Build nav model (parents + children). Parents: Profiles, CDM, Action Bars, Unit Frames
	local navModel = {
		{ type = "parent", key = "Profiles", label = "Profiles", collapsible = true, children = {
			{ type = "child", key = "profilesManage", label = "Manage Profiles" },
			{ type = "child", key = "profilesPresets", label = "Presets" },
			{ type = "child", key = "profilesRules", label = "Rules" },
		}},
		{ type = "parent", key = "ApplyAll", label = "Apply All", collapsible = true, children = {
			{ type = "child", key = "applyAllFonts", label = "Fonts" },
			{ type = "child", key = "applyAllTextures", label = "Bar Textures" },
		}},
        { type = "parent", key = "Interface", label = "Interface", collapsible = true, children = {
            { type = "child", key = "tooltip", label = "Tooltip" },
            { type = "child", key = "minimap", label = "Minimap" },
            { type = "child", key = "questLog", label = "Quest Log" },
        }},
		{ type = "parent", key = "Cooldown Manager", label = "Cooldown Manager", collapsible = true, children = {
			{ type = "child", key = "essentialCooldowns", label = "Essential Cooldowns" },
			{ type = "child", key = "utilityCooldowns", label = "Utility Cooldowns" },
			{ type = "child", key = "trackedBuffs", label = "Tracked Buffs" },
			{ type = "child", key = "trackedBars", label = "Tracked Bars" },
		}},
		{ type = "parent", key = "Action Bars", label = "Action Bars", collapsible = true, children = {
			{ type = "child", key = "actionBar1", label = "Action Bar 1" },
			{ type = "child", key = "actionBar2", label = "Action Bar 2" },
			{ type = "child", key = "actionBar3", label = "Action Bar 3" },
			{ type = "child", key = "actionBar4", label = "Action Bar 4" },
			{ type = "child", key = "actionBar5", label = "Action Bar 5" },
			{ type = "child", key = "actionBar6", label = "Action Bar 6" },
			{ type = "child", key = "actionBar7", label = "Action Bar 7" },
			{ type = "child", key = "actionBar8", label = "Action Bar 8" },
			{ type = "child", key = "petBar", label = "Pet Bar" },
			{ type = "child", key = "stanceBar", label = "Stance Bar" },
			{ type = "child", key = "microBar", label = "Micro Bar" },
		}},
		{ type = "parent", key = "Unit Frames", label = "Unit Frames", collapsible = true, children = {
			{ type = "child", key = "ufPlayer", label = "Player" },
			{ type = "child", key = "ufTarget", label = "Target" },
			{ type = "child", key = "ufFocus",  label = "Focus"  },
			{ type = "child", key = "ufPet",    label = "Pet"    },
			{ type = "child", key = "ufToT",    label = "Target of Target" },
		}},
		{ type = "parent", key = "Group Frames", label = "Group Frames", collapsible = true, children = {
			{ type = "child", key = "gfParty", label = "Party Frames" },
			{ type = "child", key = "gfRaid",  label = "Raid Frames"  },
		}},
		{ type = "parent", key = "Nameplates", label = "Nameplates", collapsible = true, children = {
			{ type = "child", key = "nameplatesUnit", label = "Unit Nameplates" },
		}},
        { type = "parent", key = "Buffs/Debuffs", label = "Buffs/Debuffs", collapsible = true, children = {
            { type = "child", key = "buffs",   label = "Buffs"   },
            { type = "child", key = "debuffs", label = "Debuffs" },
        }},
	}
    if IsPRDEnabled() then
        table.insert(navModel, {
            type = "parent",
            key = "Personal Resource Display",
            label = "Personal Resource Display",
            collapsible = true,
            children = {
                { type = "child", key = "prdGlobal", label = "Global" },
                { type = "child", key = "prdHealth", label = "Health Bar" },
                { type = "child", key = "prdPower", label = "Power Bar" },
                { type = "child", key = "prdClassResource", label = "Class Resource" },
            },
        })
    end
    table.insert(navModel, {
        type = "parent",
        key = "Scrolling Combat Text",
        label = "Scrolling Combat Text",
        collapsible = true,
        children = {
            { type = "child", key = "sctDamage", label = "Damage Numbers" },
        },
    })

	-- Initialize expand state defaults (all collapsible sections start collapsed)
    for _, parent in ipairs(navModel) do
        if parent.type == "parent" then
            local key = parent.key
            if panel._sidebarExpanded[key] == nil then
                -- Default: non-collapsible parents expanded; collapsible parents start collapsed
                panel._sidebarExpanded[key] = (parent.collapsible ~= true)
            end
        end
    end

	-- Row factory helpers ------------------------------------------------------
	local function styleLabel(fs, isHeader)
		if not fs then return end
		if isHeader then
			if panel and panel.ApplyGreenRoboto then panel.ApplyGreenRoboto(fs, 14, "OUTLINE") end
		else
			if panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(fs, 12, "") end
		end
	end

		local function createParentRow(parentFrame, parentNode)
		local row = CreateFrame("Button", nil, parentFrame)
			row:SetHeight(panel.NavLayout.parentRowHeight or 24)
		row:SetPoint("LEFT", parentFrame, "LEFT", 0, 0)
		row:SetPoint("RIGHT", parentFrame, "RIGHT", 0, 0)
			-- Dark backdrop for header rows to contrast the green label
			if not row.Bg then
				local bg = row:CreateTexture(nil, "BACKGROUND")
				bg:SetAllPoints(row)
				bg:SetColorTexture(0.10, 0.10, 0.10, 0.85)
				row.Bg = bg
			end
			local label = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		label:SetPoint("LEFT", row, "LEFT", 10, 0)
		label:SetJustifyH("LEFT")
			label:SetText(parentNode.label or parentNode.key)
		styleLabel(label, true)
		row.Label = label
		local glyph = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		glyph:SetPoint("RIGHT", row, "RIGHT", -6, 0)
		styleLabel(glyph, true)
		row.Glyph = glyph
			row.NodeKey = parentNode.key
			row.IsParent = true
			row.Collapsible = parentNode.collapsible and true or false
			if not row._clickHooked then
				row:SetScript("OnClick", function(self)
					if self.Collapsible then
						panel._sidebarExpanded[self.NodeKey] = not not (not panel._sidebarExpanded[self.NodeKey])
						panel.RebuildNav()
					end
				end)
				row._clickHooked = true
			end
			row.UpdateState = function(self)
				local expanded = panel._sidebarExpanded[self.NodeKey]
				self.Glyph:SetText(self.Collapsible and (expanded and "−" or "+") or " ")
			end
		row:UpdateState()
		return row
	end

		local function createChildRow(parentFrame, childNode)
		local row = CreateFrame("Button", nil, parentFrame)
			row:SetHeight(panel.NavLayout.childRowHeight or 20)
		row:SetPoint("LEFT", parentFrame, "LEFT", 0, 0)
		row:SetPoint("RIGHT", parentFrame, "RIGHT", 0, 0)
			local label = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		label:SetPoint("LEFT", row, "LEFT", 22, 0)
		label:SetJustifyH("LEFT")
			label:SetText(childNode.label or childNode.key)
		styleLabel(label, false)
		row.Label = label
			row.NodeKey = childNode.key
		row.IsParent = false
		row.Highlight = row:CreateTexture(nil, "BACKGROUND")
		row.Highlight:SetAllPoints(row)
		row.Highlight:SetColorTexture(0.2, 0.9, 0.3, 0.15)
		row.Highlight:Hide()
			if not row._clickHooked then
				row:SetScript("OnClick", function(self)
					panel.SelectCategory(self.NodeKey)
				end)
				row._clickHooked = true
			end
			row.UpdateSelected = function(self)
				local selected = (panel._selectedCategory == self.NodeKey)
				self.Highlight:SetShown(selected)
			end
		row:UpdateSelected()
		return row
	end

	-- Build nav content once; reuse rows and toggle visibility -----------------
	local function ensureNav()
		if f.Nav and f.NavScroll and f.NavContent then return end
		-- Container created in ShowPanel
		-- Guard if ShowPanel created them already
	end

	panel.RebuildNav = function()
		ensureNav()
		local container = f.NavContent
		container._rows = container._rows or {}
		local y = -2
		local rowIndex = 1
		local function acquireRow()
			local r = container._rows[rowIndex]
			if not r then
				r = {}
				container._rows[rowIndex] = r
			end
			rowIndex = rowIndex + 1
			return r
		end
		-- Hide all existing rows (we will re-show as we lay out)
		for i = 1, #container._rows do
			local r = container._rows[i]
			if r.Parent then r.Parent:Hide() end
			if r.Child then r.Child:Hide() end
		end
		-- Lay out parents and visible children
		for _, parent in ipairs(navModel) do
			local slot = acquireRow()
			if not slot.Parent then slot.Parent = createParentRow(container, parent) end
			-- Reinitialize parent row properties on reuse
			slot.Parent.NodeKey = parent.key
			slot.Parent.Collapsible = parent.collapsible and true or false
			slot.Parent.Label:SetText(parent.label or parent.key)
			slot.Parent:ClearAllPoints(); slot.Parent:SetPoint("TOPLEFT", container, "TOPLEFT", 0, y)
			slot.Parent:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, y)
			slot.Parent:Show(); slot.Parent:UpdateState()
			y = y - (panel.NavLayout.parentRowHeight or 24)
			local expanded = panel._sidebarExpanded[parent.key]
			if expanded then
				-- Optional gap between header and first child
				y = y - (panel.NavLayout.headerToFirstChildGap or 6)
				for _, child in ipairs(parent.children or {}) do
					local cslot = acquireRow()
					if not cslot.Child then cslot.Child = createChildRow(container, child) end
					-- Reinitialize child row properties on reuse
					cslot.Child.NodeKey = child.key
					cslot.Child.Label:SetText(child.label or child.key)
					cslot.Child:ClearAllPoints(); cslot.Child:SetPoint("TOPLEFT", container, "TOPLEFT", 0, y)
					cslot.Child:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, y)
					cslot.Child:Show(); cslot.Child:UpdateSelected()
					y = y - (panel.NavLayout.childRowHeight or 20)
				end
			end
			-- Spacer under each parent to control gaps; adjustable via NavLayout
			local gapExp = panel.NavLayout.gapAfterExpanded or 10
			local gapCol = panel.NavLayout.gapAfterCollapsed or 4
			y = y - (expanded and gapExp or gapCol)
		end
		container:SetHeight(math.max(0, -y + 4))
		-- No heavy rebuild; the scroll frame will just update content extents
		if f.NavScroll and f.NavScroll.UpdateScrollChildRect then f.NavScroll:UpdateScrollChildRect() end
	end

	panel.SelectCategory = function(key)
		-- Track previous category to detect home->other transitions
		local previousCategory = panel._selectedCategory
		local wasOnHome = (previousCategory == "home")
		panel._selectedCategory = key

		-- Determine if we're on the home page
		local isHome = (key == "home")

		-- Show/hide the top-left title region based on whether we're on home
		-- When on home, hide it (the home page shows an enlarged version)
		-- When on any other category, show it as usual
		if f._ScooterTitleRegion then
			if isHome then
				-- Hide immediately when going TO home
				f._ScooterTitleRegion:Hide()
			else
				-- When leaving home, animate the title reveal
				-- Otherwise just show it normally
				local titleRegion = f._ScooterTitleRegion
				local logoBtn = f.LogoButton
				local titleText = titleRegion and titleRegion._titleText
				
				if panel.AnimateTitleReveal then
					panel.AnimateTitleReveal(titleRegion, logoBtn, titleText, wasOnHome)
				else
					-- Fallback if animations module not loaded
					titleRegion:Show()
				end
			end
		end

		-- Hide the home content frame if navigating away from home
		if panel.RightPane and panel.RightPane.Content then
			local homeFrame = panel.RightPane.Content._ScooterHomeContent
			if homeFrame and not isHome then
				homeFrame:Hide()
			end
		end

		-- Update sidebar selection highlights
		-- On home page, no sidebar item should be highlighted
		if f.NavContent and f.NavContent._rows then
			for _, slot in ipairs(f.NavContent._rows) do
				if slot.Child and slot.Child.UpdateSelected then slot.Child:UpdateSelected() end
			end
		end
		f.CurrentCategory = key
		local entry = catRenderers[key]
		if entry and entry.mode == "list" and entry.render then
			local needsInvalidate = false
			if panel._pendingComponentRefresh and entry.componentId then
				needsInvalidate = panel._pendingComponentRefresh[entry.componentId] and true or false
			end
			if needsInvalidate then
				InvalidatePanelRightPane(panel)
			end
			if panel._renderingCategory == key then
				return
			end
			panel._renderingCategory = key
			local ok, err = pcall(entry.render)
			panel._renderingCategory = nil
			if not ok then
				error(err)
			end
			if needsInvalidate and entry.componentId then
				panel._pendingComponentRefresh[entry.componentId] = nil
			end
			-- After rendering, configure the shared header "Copy from" controls for this category
			if panel and panel.ConfigureHeaderCopyFromForKey then panel.ConfigureHeaderCopyFromForKey(key) end
			if panel and panel.UpdateCollapseButtonVisibility then panel.UpdateCollapseButtonVisibility() end
			if panel and panel.UpdateDefaultsButtonState then panel.UpdateDefaultsButtonState(key) end
		end
	end

	-- Expose mapping for rest of panel
	f.CategoriesBuilt, f.CatRenderers = true, catRenderers
	-- Initial selection: home page (landing page on first open per session)
	C_Timer.After(0, function()
		panel.RebuildNav()
		panel.SelectCategory("home")
	end)
end

-- Ensure and configure the shared header "Copy from" controls based on a category key
panel.ConfigureHeaderCopyFromForKey = function(key)
    local f = panel.frame
    local header = f and f.RightPane and f.RightPane.Header
    if not header then return end
    -- Helper functions for copy confirmation dialogs
    -- (Uses ScooterMod's custom dialog system to avoid tainting StaticPopupDialogs)
    if not panel._copyDialogHandlersRegistered then
        panel._copyDialogHandlersRegistered = true
        
        -- Unit Frame copy handler
        panel._handleUFCopyConfirm = function(data)
            if data and addon and addon.CopyUnitFrameSettings then
                if panel and panel.SuspendRefresh then panel.SuspendRefresh(0.35) end
                local ok, err = addon.CopyUnitFrameSettings(data.sourceUnit, data.destUnit)
                if ok then
                    if data.dropdown then
                        data.dropdown._ScooterSelectedId = data.sourceId or data.sourceUnit
                        if data.dropdown.SetText and data.sourceLabel then
                            data.dropdown:SetText(data.sourceLabel)
                        end
                    end
                    local destComponentId = data.destId
                    if destComponentId then
                        panel._pendingComponentRefresh = panel._pendingComponentRefresh or {}
                        panel._pendingComponentRefresh[destComponentId] = true
                    end
                    InvalidatePanelRightPane(panel)
                    if panel and panel.RefreshCurrentCategoryDeferred then
                        panel.RefreshCurrentCategoryDeferred()
                    end
                else
                    local msg
                    if err == "focus_requires_larger" then
                        msg = "Cannot copy to Focus unless 'Use Larger Frame' is enabled."
                    elseif err == "invalid_unit" then
                        msg = "Copy failed. Unsupported unit selection."
                    elseif err == "same_unit" then
                        msg = "Copy failed. Choose a different source frame."
                    elseif err == "db_unavailable" then
                        msg = "Copy failed. Profile database unavailable."
                    else
                        msg = "Copy failed. Please try again."
                    end
                    if addon.Dialogs and addon.Dialogs.Show then
                        addon.Dialogs:Show("SCOOTERMOD_COPY_UF_ERROR", { formatArgs = { msg } })
                    end
                end
            end
        end
        
        -- Action Bar copy handler
        panel._handleActionBarCopyConfirm = function(data)
            if data and addon and addon.CopyActionBarSettings then
                if panel and panel.SuspendRefresh then panel.SuspendRefresh(0.35) end
                addon.CopyActionBarSettings(data.sourceId, data.destId)
                if data.dropdown then
                    data.dropdown._ScooterSelectedId = data.sourceId
                    if data.dropdown.SetText and data.sourceName then data.dropdown:SetText(data.sourceName) end
                end
                local destComponentId = data.destId
                if destComponentId then
                    panel._pendingComponentRefresh = panel._pendingComponentRefresh or {}
                    panel._pendingComponentRefresh[destComponentId] = true
                end
                InvalidatePanelRightPane(panel)
                if panel and panel.RefreshCurrentCategoryDeferred then
                    panel.RefreshCurrentCategoryDeferred()
                end
            end
        end
    end
    -- Create once
    if not header.ScooterCopyFromLabel then
        local lbl = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetText("Copy from:")
        if panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(lbl) end
        header.ScooterCopyFromLabel = lbl
    end
    if not header.ScooterCopyFromDropdown then
        local dd = CreateFrame("DropdownButton", nil, header, "WowStyle1DropdownTemplate")
        dd:SetSize(180, 22)
        header.ScooterCopyFromDropdown = dd
    end
    local lbl = header.ScooterCopyFromLabel
    local dd  = header.ScooterCopyFromDropdown
    -- Anchor to the left of the Collapse/Defaults button when available; fallback to top-right
    dd:ClearAllPoints()
    local collapseBtn = header.CollapseAllButton or header.CollapseButton or header.DefaultsButton
    if collapseBtn then
        dd:SetPoint("RIGHT", collapseBtn, "LEFT", -24, 0)
    else
        dd:SetPoint("TOPRIGHT", header, "TOPRIGHT", -24, 0)
    end
    lbl:ClearAllPoints(); lbl:SetPoint("RIGHT", dd, "LEFT", -8, 0)

    local isAB = type(key) == "string" and (key:match("^actionBar%d$") or key == "petBar")
    local isUF = (key == "ufPlayer") or (key == "ufTarget") or (key == "ufFocus") or (key == "ufPet") or (key == "ufToT")

    -- Reset any previous selection text to avoid stale prompts between categories
    dd._ScooterSelectedId = nil

    if isAB and dd and dd.SetupMenu then
        local currentId = key
        local isPetBar = (currentId == "petBar")
        dd:SetupMenu(function(menu, root)
            -- Always show Action Bars 1-8 as sources; Pet Bar is destination-only
            for i = 1, 8 do
                local id = "actionBar" .. tostring(i)
                -- For actionBar pages, exclude self; for petBar, show all 8
                if id ~= currentId then
                    local comp = addon and addon.Components and addon.Components[id]
                    local text = (comp and comp.name) or ("Action Bar " .. tostring(i))
                    root:CreateRadio(text, function() return dd._ScooterSelectedId == id end, function()
                        -- Defer callback execution to break taint chain from menu system
                        C_Timer.After(0, function()
                            local destName = (addon and addon.Components and addon.Components[currentId] and addon.Components[currentId].name) or currentId
                            local data = { sourceId = id, destId = currentId, sourceName = text, destName = destName, dropdown = dd }
                            -- Use ScooterMod custom dialog to avoid tainting StaticPopupDialogs
                            if addon.Dialogs and addon.Dialogs.Show then
                                addon.Dialogs:Show("SCOOTERMOD_COPY_ACTIONBAR_CONFIRM", {
                                    formatArgs = { text, destName },
                                    data = data,
                                    onAccept = function() panel._handleActionBarCopyConfirm(data) end,
                                })
                            elseif addon and addon.CopyActionBarSettings then
                                -- Fallback if dialogs not loaded
                                panel._handleActionBarCopyConfirm(data)
                            end
                        end)
                    end)
                end
            end
        end)
		local function setPromptBar()
			local s = "Select a bar..."
			if dd.SetText then dd:SetText(s) end
			if dd.Text and dd.Text.SetText then dd.Text:SetText(s) end
		end
		setPromptBar()
		if C_Timer and C_Timer.After then C_Timer.After(0, setPromptBar) end
    elseif isUF and dd and dd.SetupMenu then
        local function unitLabelFor(id)
            if id == "ufPlayer" then return "Player" end
            if id == "ufTarget" then return "Target" end
            if id == "ufFocus"  then return "Focus" end
            if id == "ufPet"    then return "Pet" end
            if id == "ufToT"    then return "Target of Target" end
            return id
        end
        local function unitKeyFor(id)
            if id == "ufPlayer" then return "Player" end
            if id == "ufTarget" then return "Target" end
            if id == "ufFocus"  then return "Focus" end
            if id == "ufPet"    then return "Pet" end
            if id == "ufToT"    then return "TargetOfTarget" end
            return nil
        end
        local currentId = key
        dd:SetupMenu(function(menu, root)
            -- Pet and ToT can be destinations but not sources (too different from other frames)
            local candidates = { "ufPlayer", "ufTarget", "ufFocus" }
            for _, id in ipairs(candidates) do
                if id ~= currentId then
                    local text = unitLabelFor(id)
                    root:CreateRadio(text, function() return dd._ScooterSelectedId == id end, function()
                        local destLabel = unitLabelFor(currentId)
                        local data = {
                            sourceUnit = unitKeyFor(id),
                            destUnit = unitKeyFor(currentId),
                            sourceLabel = text,
                            destLabel = destLabel,
                            dropdown = dd,
                            sourceId = id,
                            destId = currentId,
                        }
                        -- Use ScooterMod custom dialog to avoid tainting StaticPopupDialogs
                        if addon.Dialogs and addon.Dialogs.Show then
                            addon.Dialogs:Show("SCOOTERMOD_COPY_UF_CONFIRM", {
                                formatArgs = { text, destLabel },
                                data = data,
                                onAccept = function() panel._handleUFCopyConfirm(data) end,
                            })
                        elseif addon and addon.CopyUnitFrameSettings then
                            -- Fallback if dialogs not loaded
                            panel._handleUFCopyConfirm(data)
                        end
                    end)
                end
            end
        end)
		local function setPromptFrame()
			local s = "Select a frame..."
			if dd.SetText then dd:SetText(s) end
			if dd.Text and dd.Text.SetText then dd.Text:SetText(s) end
		end
		setPromptFrame()
		if C_Timer and C_Timer.After then C_Timer.After(0, setPromptFrame) end
    end

    if lbl then lbl:SetShown(isAB or isUF) end
    if dd then dd:SetShown(isAB or isUF) end
end

		local function ShowPanel()
	    -- Clear the closing flag immediately when panel opens to allow deferred operations
	    panel._panelClosing = false
	    
	    -- When the ScooterMod panel opens, ensure Edit Mode–driven state (notably Aura
	    -- Frame Icon Size for Buffs) is reconciled back into AceDB before or shortly
	    -- after we render categories. This mirrors the up-to-date behavior users see
	    -- after switching tabs via the left navigation, without requiring a manual tab
	    -- change just to see fresh values.
	    if addon and addon.EditMode and addon.EditMode.RefreshSyncAndNotify then
	        addon.EditMode.RefreshSyncAndNotify("OpenPanel")
	    end
	    if not panel.frame then
	        local f = CreateFrame("Frame", "ScooterSettingsPanel", UIParent, "SettingsFrameTemplate")
        f:Hide(); f:SetSize(920, 724); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG")
            -- Allow closing the panel with the Escape key from anywhere in the menu
            if UISpecialFrames then
                tinsert(UISpecialFrames, "ScooterSettingsPanel")
            end
	        -- Remove default title text; we'll render a custom title area
	        if f.NineSlice and f.NineSlice.Text then f.NineSlice.Text:SetText("") end
        -- Override the template's close button to avoid calling protected HideUIPanel in combat
        if f.ClosePanelButton then
            f.ClosePanelButton:SetScript("OnClick", function()
                if PlaySound and SOUNDKIT and SOUNDKIT.IG_MAINMENU_CLOSE then
                    PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE)
                end
                f:Hide()
            end)
        end
            -- Increase window background opacity with a subtle overlay (no true blur available in WoW UI API)
            do
                local bg = f:CreateTexture(nil, "BACKGROUND")
                local c = panel.WindowBackgroundColor or { r = 0.27, g = 0.27, b = 0.27, a = 0.625 }
                bg:SetColorTexture(c.r or 0.27, c.g or 0.27, c.b or 0.27, c.a or 0.625)
                -- Inset slightly so NineSlice borders remain visible
                bg:SetPoint("TOPLEFT", f, "TOPLEFT", 3, -3)
                bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -3, 3)
                f._ScooterBgOverlay = bg
            end

	        -- Custom title area: circular logo (clickable home button) + green "ScooterMod" label in Roboto Bold
	        do
	            local fonts = addon and addon.Fonts or nil
	            local titleRegion = CreateFrame("Frame", nil, f)
	            titleRegion:SetSize(400, 56)
	            titleRegion:SetPoint("TOPLEFT", f, "TOPLEFT", -6, 10) -- nudge outwards to overlap corner

	            -- Logo button (circular icon that navigates to home page on click)
	            local logoBtn = CreateFrame("Button", nil, titleRegion)
	            logoBtn:SetSize(56, 56)
	            logoBtn:SetPoint("LEFT", titleRegion, "LEFT", 0, -6) -- drop a bit to straddle the title bar

	            -- Green hover ring (hidden by default, shown on hover)
	            -- Uses ScooterMod's circular portrait border texture, tinted green
	            local hoverRing = logoBtn:CreateTexture(nil, "OVERLAY")
	            hoverRing:SetTexture("Interface\\AddOns\\ScooterMod\\media\\portraitborder\\texture_c.tga")
	            hoverRing:SetVertexColor(0.2, 0.9, 0.3, 1)
	            -- === TWEAK THESE VALUES ===
	            local ringSize = 78      -- Size of the ring (width and height)
	            local ringOffsetX = 0    -- Positive = right, negative = left
	            local ringOffsetY = 0    -- Positive = up, negative = down
	            -- ==========================
	            hoverRing:SetSize(ringSize, ringSize)
	            hoverRing:SetPoint("CENTER", logoBtn, "CENTER", ringOffsetX, ringOffsetY)
	            hoverRing:Hide()
	            logoBtn.HoverRing = hoverRing

	            -- Main logo icon texture
	            local icon = logoBtn:CreateTexture(nil, "ARTWORK")
	            icon:SetAllPoints(logoBtn)
	            -- Try multiple extensions so the asset can be provided as TGA/BLP/PNG; prefer PNG for production
	            local function trySetIcon(tex, base)
	                local candidates = { base .. ".png", base .. ".tga", base .. ".blp" }
	                for _, p in ipairs(candidates) do
	                    local ok = pcall(tex.SetTexture, tex, p)
	                    if ok and tex:GetTexture() then return true end
	                end
	            end
	            trySetIcon(icon, "Interface\\AddOns\\ScooterMod\\Scooter")
	            -- Use a circular alpha mask
	            pcall(icon.SetMask, icon, "Interface\\CharacterFrame\\TempPortraitAlphaMask")
	            logoBtn.Icon = icon

	            -- Hover: show green ring
	            logoBtn:SetScript("OnEnter", function(self)
	                self.HoverRing:Show()
	            end)
	            logoBtn:SetScript("OnLeave", function(self)
	                self.HoverRing:Hide()
	            end)

	            -- Click: navigate to home page
	            logoBtn:SetScript("OnClick", function(self)
	                -- Navigate to home page (placeholder key "home" for future implementation)
	                if panel and panel.SelectCategory then
	                    panel.SelectCategory("home")
	                end
	            end)

	            f.LogoButton = logoBtn

	            -- Title text
	            local title = titleRegion:CreateFontString(nil, "OVERLAY")
	            -- Start just to the right of the circular logo; lift to align with title bar
	            title:SetPoint("LEFT", logoBtn, "RIGHT", 2, 10)
	            title:SetJustifyH("LEFT")
	            -- Use bundled Roboto Bold if available, else fall back; set font BEFORE text
	            if fonts and fonts.ROBOTO_BLD then
	                title:SetFont(fonts.ROBOTO_BLD, 25, "THICKOUTLINE")
	            else
	                title:SetFont("Fonts\\ARIALN.TTF", 25, "THICKOUTLINE")
	            end
	            title:SetShadowColor(0, 0, 0, 1)
	            title:SetShadowOffset(1, -1)
	            title:SetTextColor(0.2, 0.9, 0.3, 1)
	            title:SetText("ScooterMod")

	            -- Store reference to title FontString for animations
	            titleRegion._titleText = title

	            -- Keep region above header drag area for clicks to pass through appropriately
	            titleRegion:SetFrameLevel((f:GetFrameLevel() or 0) + 10)
	            f._ScooterTitleRegion = titleRegion
	        end
	        f:SetMovable(true); f:SetClampedToScreen(true)
        local headerDrag = CreateFrame("Frame", nil, f)
        headerDrag:SetPoint("TOPLEFT", 7, -2); headerDrag:SetPoint("TOPRIGHT", -3, -2); headerDrag:SetHeight(25)
        headerDrag:EnableMouse(true); headerDrag:RegisterForDrag("LeftButton")
        headerDrag:SetScript("OnDragStart", function() f:StartMoving() end)
        headerDrag:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
        local closeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        closeBtn:SetSize(96, 22)
        closeBtn:SetPoint("BOTTOMRIGHT", -16, 16)
        closeBtn:SetText(SETTINGS_CLOSE or CLOSE or "Close")
        if panel and panel.ApplyButtonTheme then
            panel.ApplyButtonTheme(closeBtn)
        end
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
        if panel and panel.ApplyButtonTheme then panel.ApplyButtonTheme(headerEditBtn) end
        f:HookScript("OnSizeChanged", function() PositionHeaderEditBtn() end)
        headerEditBtn:SetFrameLevel((headerDrag:GetFrameLevel() or 0) + 5)
        headerEditBtn:EnableMouse(true)
        headerEditBtn:SetScript("OnClick", function()
            -- Note: Blizzard allows opening Edit Mode during combat, and ScooterMod's
            -- edit mode sync system properly handles combat by using SaveOnly() instead
            -- of ApplyChanges() during combat, then applying changes when combat ends.
            if SlashCmdList and SlashCmdList["EDITMODE"] then
                SlashCmdList["EDITMODE"]("")
            elseif RunBinding then
                RunBinding("TOGGLE_EDIT_MODE")
            else
                addon:Print("Use /editmode to open the layout manager.")
            end
        end)
				-- Enable resizing via a bottom-right handle
				f:SetResizable(true)
				-- Set a slightly larger minimum size to avoid extreme recycling artifacts
				if f.SetMinResize then f:SetMinResize(820, 560) end
		local resizeBtn = CreateFrame("Button", nil, f, "PanelResizeButtonTemplate")
		resizeBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 4)
				-- Reasonable bounds to keep layout sane (min increased)
				resizeBtn:Init(f, 820, 560, 1600, 1200)
		resizeBtn:SetOnResizeCallback(function()
			-- Re-evaluate layout while dragging to keep list/canvas filling the area
			if panel and panel.RefreshCurrentCategory then panel.RefreshCurrentCategory() end
		end)
		resizeBtn:SetOnResizeStoppedCallback(function()
			if panel and panel.RefreshCurrentCategory then panel.RefreshCurrentCategory() end
		end)
		-- Layout knobs for the nav and right pane spacing (tweak as desired)
		-- NOTE: navWidth sized to fit longest header ("Personal Resource Display") without truncation
		panel.NavLayout = panel.NavLayout or {
			-- Width of the left navigation pane (increase if adding longer section headers)
			navWidth = 240,
			-- Horizontal gap between the nav (including its scrollbar) and the right-side content area
			rightPaneLeftOffset = 36,
			-- Row heights
			parentRowHeight = 24,
			childRowHeight = 20,
			-- Extra vertical space between a section header and its first child when expanded
			headerToFirstChildGap = 8,
			-- Vertical gap after a group: larger gap when the group is expanded vs collapsed
			gapAfterExpanded = 18,
			gapAfterCollapsed = 8,
		}
		-- Custom left navigation (pure-visibility model, no data-provider rebuilds)
		local navWidth = panel.NavLayout.navWidth or 240
		local nav = CreateFrame("Frame", nil, f)
		nav:SetSize(navWidth, 569)
		nav:SetPoint("TOPLEFT", 18, -76)
		nav:SetPoint("BOTTOMLEFT", 18, 46)
		f.Nav = nav
		local navScroll = CreateFrame("ScrollFrame", nil, nav, "UIPanelScrollFrameTemplate")
		navScroll:SetAllPoints(nav)
		f.NavScroll = navScroll
		local navContent = CreateFrame("Frame", nil, navScroll)
		navContent:SetPoint("TOPLEFT", navScroll, "TOPLEFT", 0, 0)
		navContent:SetHeight(10)
		navScroll:SetScrollChild(navContent)
		f.NavContent = navContent
		local function UpdateNavContentWidth()
			local w = (nav:GetWidth() or navWidth) - 24
			if w < 80 then w = 80 end
			navContent:SetWidth(w)
			if navScroll and navScroll.UpdateScrollChildRect then navScroll:UpdateScrollChildRect() end
		end
		UpdateNavContentWidth()
		nav:SetScript("OnSizeChanged", function()
			UpdateNavContentWidth()
		end)

        local container = CreateFrame("Frame", nil, f)
        container:ClearAllPoints()
        container:SetPoint("TOPLEFT", nav, "TOPRIGHT", panel.NavLayout.rightPaneLeftOffset or 24, 0)
        container:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -22, 46)
        f.Container = container

        local function performDefaultsReset(categoryKey, handler)
            if not categoryKey or not handler then
                return
            end
            if panel and panel.SuspendRefresh then panel.SuspendRefresh(0.35) end
            local ok, err = handler()
            if ok == false and err and addon and addon.Print then
                addon:Print("Unable to reset defaults: " .. tostring(err))
            end

            local frameRef = panel and panel.frame
            if panel and panel.RefreshCurrentCategory then
                panel.RefreshCurrentCategory()
            elseif frameRef and frameRef.CatRenderers then
                local entry = frameRef.CatRenderers[categoryKey]
                if entry and entry.render then
                    entry.render()
                end
            end
            if panel and panel.UpdateDefaultsButtonState then
                panel.UpdateDefaultsButtonState(categoryKey)
            end
        end

        local defaultsBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        defaultsBtn:SetSize(110, 22)
        defaultsBtn:SetText(DEFAULTS or "Defaults")
        defaultsBtn:ClearAllPoints()
        defaultsBtn:SetPoint("LEFT", container, "LEFT", 0, 0)
        defaultsBtn:SetPoint("BOTTOM", closeBtn, "BOTTOM", 0, 0)
        if panel and panel.ApplyButtonTheme then panel.ApplyButtonTheme(defaultsBtn) end
        defaultsBtn:SetScript("OnClick", function()
            local frameRef = panel and panel.frame
            if not frameRef then return end
            local currentKey = defaultsBtn.ScooterCurrentCategoryKey or frameRef.CurrentCategory
            if not currentKey then return end
            local handler = defaultsBtn.ScooterCurrentDefaultsHandler
            if (not handler) and panel.GetDefaultsHandlerForKey then
                handler = panel.GetDefaultsHandlerForKey(currentKey)
            end
            if not handler then return end

            local displayName = ""
            do
                local entry = frameRef.CatRenderers and frameRef.CatRenderers[currentKey]
                if entry and entry.componentId then
                    local component = addon and addon.Components and addon.Components[entry.componentId]
                    displayName = (component and component.name) or entry.componentId or ""
                else
                    displayName = entry and entry.title or ""
                end
                if displayName == "" then
                    displayName = tostring(currentKey)
                end
            end

            -- Use ScooterMod custom dialog to avoid tainting StaticPopupDialogs
            if addon.Dialogs and addon.Dialogs.Show then
                local data = { handler = handler, key = currentKey }
                addon.Dialogs:Show("SCOOTERMOD_RESET_DEFAULTS", {
                    formatArgs = { displayName },
                    data = data,
                    onAccept = function()
                        performDefaultsReset(currentKey, handler)
                    end,
                })
                return
            end

            performDefaultsReset(currentKey, handler)
        end)
        defaultsBtn:Hide()
        f.DefaultsButton = defaultsBtn

        -- Initialize the custom Scooter-owned right pane (header + scrollframe).
        if panel.RightPane and panel.RightPane.Init then
            panel.RightPane:Init(f, container)
            f.RightPane = panel.RightPane
        end

        -- Insert a button in the header to open Blizzard's Advanced Cooldown
        -- Manager settings, anchored to the left of the Collapse All button.
        do
            local header = panel.RightPane and panel.RightPane.Header
            local collapseBtn = header and header.CollapseAllButton
            if header and collapseBtn then
                local cdmBtn = header.ScooterCDMButton
                if not cdmBtn then
                    cdmBtn = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
                    cdmBtn:SetSize(200, 22)
                    cdmBtn.Text:SetText("Cooldown Manager Settings")
                    cdmBtn:ClearAllPoints()
                    cdmBtn:SetPoint("RIGHT", collapseBtn, "LEFT", -8, 0)
                    if panel and panel.ApplyButtonTheme then panel.ApplyButtonTheme(cdmBtn) end
                    cdmBtn:SetScript("OnClick", function()
                        if InCombatLockdown and InCombatLockdown() then
                            if addon and addon.Print then addon:Print("Cannot open Settings during combat.") end
                            return
                        end
                        local opened = false
                        -- Prefer opening the dedicated Cooldown Viewer Settings frame directly
                        do
                            if _G and _G.CooldownViewerSettings == nil then
                                if C_AddOns and C_AddOns.LoadAddOn then
                                    pcall(C_AddOns.LoadAddOn, "Blizzard_CooldownManager")
                                    pcall(C_AddOns.LoadAddOn, "Blizzard_CooldownViewer")
                                end
                            end
                            local frame = _G and _G.CooldownViewerSettings
                            if frame then
                                if frame.TogglePanel then
                                    opened = pcall(frame.TogglePanel, frame) or opened
                                end
                                if not opened and type(ShowUIPanel) == "function" then
                                    opened = pcall(ShowUIPanel, frame) or opened
                                end
                                if not opened and frame.Show then
                                    opened = pcall(frame.Show, frame) or opened
                                end
                            end
                        end
                        if not opened then
                            -- Final fallback: open Blizzard Settings to a broad search for "Cooldown"
                            local S = _G and _G.Settings
                            if _G.SettingsPanel and _G.SettingsPanel.Open then pcall(_G.SettingsPanel.Open, _G.SettingsPanel) end
                            if S and S.OpenToSearch then pcall(S.OpenToSearch, S, "Cooldown") end
                        end
                        if panel and panel.frame and panel.frame:IsShown() then panel.frame:Hide() end
                    end)
                    header.ScooterCDMButton = cdmBtn
                end
            end
        end
        panel.frame = f

        -- Prevent unintended closure during Edit Mode ApplyChanges by restoring visibility when protected
        if not f._ScooterProtectHooked then
            f:HookScript("OnHide", function(frame)
                local pnl = addon and addon.SettingsPanel
                -- Set flag immediately to block any deferred callbacks from running
                -- during the hide transition. This prevents race conditions where
                -- RefreshCurrentCategoryDeferred runs after panel starts hiding.
                if pnl then pnl._panelClosing = true end
                
                if pnl and pnl._protectVisibility then
                    pnl._protectVisibility = false
                    if pnl then pnl._panelClosing = false end -- Panel is reopening
                    if pnl and pnl.frame and not pnl.frame:IsShown() then pnl.frame:Show() end
                end
                -- Stop any running title reveal animations when panel closes
                if pnl and pnl.StopTitleAnimation and frame._ScooterTitleRegion then
                    local titleRegion = frame._ScooterTitleRegion
                    pnl.StopTitleAnimation(frame.LogoButton, titleRegion._titleText)
                end
                -- Close any open dropdown menus to prevent lingering UI
                if CloseDropDownMenus then
                    pcall(CloseDropDownMenus)
                end
                -- Explicitly hide profile widgets to prevent them lingering on screen
                -- after deferred callbacks from profile switching or action bar copy.
                -- CRITICAL: We must hide ALL frames that have ever had profile widgets
                -- created on them, not just the current ActiveLayoutRow reference.
                -- The SettingsList recycles frames, so the reference can become stale
                -- while the actual frame with visible buttons is a different one.
                local widgets = pnl and pnl._profileWidgets
                if widgets then
                    -- Hide all frames that have ever been used for Active Layout widgets
                    if widgets.AllActiveLayoutFrames then
                        for frameRef in pairs(widgets.AllActiveLayoutFrames) do
                            if frameRef and type(frameRef.Hide) == "function" then
                                pcall(frameRef.Hide, frameRef)
                            end
                            -- Also explicitly hide the child widgets in case the frame
                            -- itself is somehow not responding to Hide
                            if frameRef then
                                if frameRef.ActiveDropdown then pcall(function() frameRef.ActiveDropdown:Hide() end) end
                                if frameRef.CreateBtn then pcall(function() frameRef.CreateBtn:Hide() end) end
                                if frameRef.RenameBtn then pcall(function() frameRef.RenameBtn:Hide() end) end
                                if frameRef.CopyBtn then pcall(function() frameRef.CopyBtn:Hide() end) end
                                if frameRef.DeleteBtn then pcall(function() frameRef.DeleteBtn:Hide() end) end
                            end
                        end
                    end
                    -- Also try the direct reference as a fallback
                    if widgets.ActiveLayoutRow then
                        pcall(function() widgets.ActiveLayoutRow:Hide() end)
                    end
                    if widgets.SpecEnabledRow then
                        pcall(function() widgets.SpecEnabledRow:Hide() end)
                    end
                end
                
                -- Schedule a delayed cleanup to catch any widgets that might be shown
                -- by deferred callbacks that run after this OnHide handler completes.
                -- This is a belt-and-suspenders safeguard for timing edge cases.
                if C_Timer and C_Timer.After then
                    C_Timer.After(0.1, function()
                        -- Only clean up if the panel is still closed
                        if pnl and pnl._panelClosing and pnl._profileWidgets then
                            local w = pnl._profileWidgets
                            if w.AllActiveLayoutFrames then
                                for frameRef in pairs(w.AllActiveLayoutFrames) do
                                    if frameRef then
                                        pcall(function() frameRef:Hide() end)
                                        if frameRef.ActiveDropdown then pcall(function() frameRef.ActiveDropdown:Hide() end) end
                                        if frameRef.CreateBtn then pcall(function() frameRef.CreateBtn:Hide() end) end
                                        if frameRef.RenameBtn then pcall(function() frameRef.RenameBtn:Hide() end) end
                                        if frameRef.CopyBtn then pcall(function() frameRef.CopyBtn:Hide() end) end
                                        if frameRef.DeleteBtn then pcall(function() frameRef.DeleteBtn:Hide() end) end
                                    end
                                end
                            end
                        end
                    end)
                end
            end)
            f._ScooterProtectHooked = true
        end
        C_Timer.After(0, BuildCategories)
    else
        -- For reopening the panel, we need to handle Buffs/Debuffs differently to avoid a race condition
        -- where the UI renders before the Aura backfill updates the DB.
        local cat = panel.frame.CurrentCategory
        local isAuraTab = (cat == "buffs" or cat == "debuffs")
        
        -- For non-Aura tabs, render immediately as before
        if not isAuraTab and cat and panel.frame.CatRenderers and panel.frame.CatRenderers[cat] and panel.frame.CatRenderers[cat].render then
            C_Timer.After(0, function()
                if panel.frame and panel.frame:IsShown() then
                    local entry = panel.frame.CatRenderers[cat]
                    local needsDeferred = false
                    if entry and entry.componentId and panel._pendingComponentRefresh and panel._pendingComponentRefresh[entry.componentId] then
                        needsDeferred = true
                    end
                    if entry and entry.render and not needsDeferred then
                        entry.render()
                        -- Reconfigure shared header "Copy from" controls on reopen to restore placeholder prompts
                        if panel and panel.ConfigureHeaderCopyFromForKey and cat then
                            panel.ConfigureHeaderCopyFromForKey(cat)
                            if C_Timer and C_Timer.After then
                                C_Timer.After(0, function()
                                    if panel and panel.ConfigureHeaderCopyFromForKey and panel.frame and panel.frame:IsShown() then
                                        panel.ConfigureHeaderCopyFromForKey(cat)
                                    end
                                end)
                            end
                        end
                    end
                end
            end)
        end
        -- For Buffs/Debuffs tabs, skip the immediate render and let the delayed SelectCategory handle it below
    end
    panel.frame:Show()
    
    -- Buffs/Debuffs: schedule a targeted Aura Frame Icon Size backfill based on the live
    -- AuraContainer.iconScale BEFORE we render the category, so the UI reflects
    -- the correct Edit Mode value immediately on panel open.
    local needsBackfill = false
    if addon and addon.EditMode and addon.EditMode.QueueAuraIconSizeBackfill then
        local current = panel.frame.CurrentCategory
        if current == "buffs" or current == "debuffs" then
            needsBackfill = true
            -- Run the backfill immediately (delay=0) before SelectCategory
            addon.EditMode.QueueAuraIconSizeBackfill(current, {
                origin = "OpenPanel",
                delay = 0,
                retryDelays = { 0.2, 0.5, 1.0 },
            })
        end
    end
    
    -- Delay the SelectCategory call slightly to allow the immediate backfill to complete first.
    -- For Buffs/Debuffs, this is the ONLY render on panel reopen (we skipped the immediate render above).
    -- For non-Aura categories, use immediate timing (no change in behavior).
    local selectDelay = needsBackfill and 0.15 or 0
    C_Timer.After(selectDelay, function()
        if not panel.frame or not panel.frame:IsShown() then return end
        local current = panel.frame.CurrentCategory
        if current and panel.SelectCategory then
            panel.SelectCategory(current)
        elseif panel.RefreshCurrentCategory then
            panel.RefreshCurrentCategory()
        end
    end)
end

function panel:Toggle()
    if panel.frame and panel.frame:IsShown() then
        panel.frame:Hide()
        return
    end

    -- Combat guard: prevent opening during combat
    if InCombatLockdown and InCombatLockdown() then
        panel._closedByCombat = true
        if addon and addon.Print then
            addon:Print("ScooterMod will open once combat ends.")
        end
        return
    end

    ShowPanel()
end

function panel:Open()
    -- Combat guard: prevent opening during combat
    if InCombatLockdown and InCombatLockdown() then
        panel._closedByCombat = true
        if addon and addon.Print then
            addon:Print("ScooterMod will open once combat ends.")
        end
        return
    end

    ShowPanel()
end

-- Combat event handling: close panel on combat start, reopen when combat ends
local combatWatcher = CreateFrame("Frame")
combatWatcher:RegisterEvent("PLAYER_REGEN_DISABLED")
combatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
combatWatcher:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_REGEN_DISABLED" then
        -- Combat started: close panel if open
        if panel.frame and panel.frame:IsShown() then
            panel._closedByCombat = true
            panel.frame:Hide()
            if addon and addon.Print then
                addon:Print("ScooterMod will reopen once combat ends.")
            end
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Combat ended: reopen panel if it was closed by combat
        if panel._closedByCombat then
            panel._closedByCombat = false
            -- Defer slightly to ensure combat lockdown is fully cleared
            if C_Timer and C_Timer.After then
                C_Timer.After(0.1, function()
                    if not InCombatLockdown() then
                        ShowPanel()
                    end
                end)
            else
                ShowPanel()
            end
        end
    end
end)
