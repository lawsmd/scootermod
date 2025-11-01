local addonName, addon = ...

addon.SettingsPanel = addon.SettingsPanel or {}
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
        addon:Print("ScooterMod will open once combat ends.")
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

-- Header button visibility helper: hide "Collapse All" for non-component pages
function panel.UpdateCollapseButtonVisibility()
    local f = panel and panel.frame
    if not f or not f.SettingsList or not f.SettingsList.Header then return end
    local btn = f.SettingsList.Header.DefaultsButton
    if not btn then return end
    local hide = false
    local cat = f.CurrentCategory
    if cat and f.CatRenderers then
        local entry = f.CatRenderers[cat]
        -- Profiles pages do not have collapsible component sections
        if entry and (entry.componentId == "profilesManage" or entry.componentId == "profilesPresets") then
            hide = true
        end
        -- Manage visibility of the Cooldown Manager settings button (only on CDM component tabs)
        local cdmBtn = f.SettingsList.Header.ScooterCDMButton
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

-- Theming helpers moved to ui/panel/theme.lua

-- Collapsible section header (Keybindings-style) ---------------------------------
-- Expandable section mixin moved to ui/panel/mixins.lua

-- Tabbed section mixin moved to ui/panel/mixins.lua

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
    -- Prefer a previously captured percent (from a deferred request) to avoid
    -- double-refresh sequences snapping to the top.
    local percent = panel._desiredScrollPercent
    if percent == nil then
        if sb and sb.GetDerivedScrollPercentage then
            percent = sb:GetDerivedScrollPercentage()
        elseif sb and sb.GetScrollPercentage then
            percent = sb:GetScrollPercentage()
        end
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
    if percent ~= nil and sb and sb.SetScrollPercentage then
        C_Timer.After(0, function()
            if panel and panel.frame and panel.frame:IsShown() then
                pcall(sb.SetScrollPercentage, sb, percent)
                -- Clear the one-shot desired percent once applied
                panel._desiredScrollPercent = nil
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
    -- Capture current scroll percent immediately so we can restore it even if
    -- multiple deferred refreshes get queued.
    do
        local f = panel and panel.frame
        local settingsList = f and f.SettingsList
        local sb = settingsList and settingsList.ScrollBox
        local percent
        if sb and sb.GetDerivedScrollPercentage then
            percent = sb:GetDerivedScrollPercentage()
        elseif sb and sb.GetScrollPercentage then
            percent = sb:GetScrollPercentage()
        end
        if percent ~= nil then
            panel._desiredScrollPercent = percent
        end
    end
    C_Timer.After(0, function()
        if panel and not panel._suspendRefresh and panel.RefreshCurrentCategory then panel.RefreshCurrentCategory() end
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
                            -- If this is the Font dropdown, install font preview renderer
                            if type(label) == "string" and string.find(label, "Font") and f.Control and f.Control.Dropdown then
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
                            if panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(f.Text) end
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
                            addSlider(frame.PageB, labelB_Size, 6, 32, 1,
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
                                frame.EnableCustomTexturesRow = row
                                if row.Checkbox then
                                    row.Checkbox:SetHitRectInsets(0, -220, 0, 0)
                                end
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
                                    -- Avoid UI flicker by preferring single-setting writes + SaveOnly and coalesced ApplyChanges
                                    local function safeSaveOnly()
                                        if addon.EditMode and addon.EditMode.SaveOnly then addon.EditMode.SaveOnly() end
                                    end
                                    local function requestApply()
                                        if addon.EditMode and addon.EditMode.RequestApplyChanges then addon.EditMode.RequestApplyChanges(0.2) end
                                    end
                                    if settingId == "positionX" or settingId == "positionY" then
                                        if addon.EditMode and addon.EditMode.SyncComponentToEditMode then
                                            addon.EditMode.SyncComponentToEditMode(component)
                                            safeSaveOnly(); requestApply()
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
    createCategory("Profiles", "Manage Profiles", 1, addon.SettingsPanel.RenderProfilesManage())
    createCategory("Profiles", "Presets", 2, addon.SettingsPanel.RenderProfilesPresets())
    createCategory("Cooldown Manager", "Essential Cooldowns", 11, addon.SettingsPanel.RenderEssentialCooldowns())
    createCategory("Cooldown Manager", "Utility Cooldowns", 12, addon.SettingsPanel.RenderUtilityCooldowns())
    -- Reorder: Tracked Buffs third, Tracked Bars last
    createCategory("Cooldown Manager", "Tracked Buffs", 13, addon.SettingsPanel.RenderTrackedBuffs())
    createCategory("Cooldown Manager", "Tracked Bars", 14, addon.SettingsPanel.RenderTrackedBars())
    -- Action Bars group
    createCategory("Action Bars", "Action Bar 1", 21, addon.SettingsPanel.RenderActionBar1())
    createCategory("Action Bars", "Action Bar 2", 22, addon.SettingsPanel.RenderActionBar2())
    createCategory("Action Bars", "Action Bar 3", 23, addon.SettingsPanel.RenderActionBar3())
    createCategory("Action Bars", "Action Bar 4", 24, addon.SettingsPanel.RenderActionBar4())
    createCategory("Action Bars", "Action Bar 5", 25, addon.SettingsPanel.RenderActionBar5())
    createCategory("Action Bars", "Action Bar 6", 26, addon.SettingsPanel.RenderActionBar6())
    createCategory("Action Bars", "Action Bar 7", 27, addon.SettingsPanel.RenderActionBar7())
    createCategory("Action Bars", "Action Bar 8", 28, addon.SettingsPanel.RenderActionBar8())
    createCategory("Action Bars", "Stance Bar", 29, addon.SettingsPanel.RenderStanceBar())
    createCategory("Action Bars", "Micro Bar", 30, addon.SettingsPanel.RenderMicroBar())
    categoryList:RegisterCallback(SettingsCategoryListMixin.Event.OnCategorySelected, function(_, category)
        f.CurrentCategory = category
        local entry = catRenderers[category]
        if entry and entry.mode == "list" then
            entry.render()
            -- Ensure header button visibility matches the selected page
            if panel and panel.UpdateCollapseButtonVisibility then
                panel.UpdateCollapseButtonVisibility()
            end
            -- Some parts of the list evaluate shown predicates lazily; force a second pass like the user's second click
            if f.SettingsList and f.SettingsList.RepairDisplay then
                C_Timer.After(0, function()
                    if f and f:IsShown() then
                        pcall(f.SettingsList.RepairDisplay, f.SettingsList, { EnumerateInitializers = function() return ipairs(entry and entry._lastInitializers or {}) end, GetInitializers = function() return entry and entry._lastInitializers or {} end })
                    end
                end)
            end
        end
        -- Re-apply sidebar theming whenever selection changes (buttons are recycled)
        if panel and panel.SkinCategoryList then panel.SkinCategoryList(categoryList) end
    end, f)
    f.CategoriesBuilt, f.CatRenderers, f.CreatedCategories = true, catRenderers, createdCategories
    C_Timer.After(0, function()
        if createdCategories[1] then
            categoryList:SetCurrentCategory(createdCategories[1])
            if panel and panel.UpdateCollapseButtonVisibility then panel.UpdateCollapseButtonVisibility() end
            if panel and panel.SkinCategoryList then panel.SkinCategoryList(categoryList) end
        end
    end)
end

		local function ShowPanel()
	    if not panel.frame then
	        local f = CreateFrame("Frame", "ScooterSettingsPanel", UIParent, "SettingsFrameTemplate")
	        f:Hide(); f:SetSize(920, 724); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG")
            -- Allow closing the panel with the Escape key from anywhere in the menu
            if UISpecialFrames then
                tinsert(UISpecialFrames, "ScooterSettingsPanel")
            end
	        -- Remove default title text; we'll render a custom title area
	        if f.NineSlice and f.NineSlice.Text then f.NineSlice.Text:SetText("") end

	        -- Increase window background opacity with a subtle overlay (no true blur available in WoW UI API)
	        do
	            local bg = f:CreateTexture(nil, "BACKGROUND")
	            bg:SetColorTexture(0.3, 0.3, 0.3, 0.5) -- midpoint between original and lighter gray
	            -- Inset slightly so NineSlice borders remain visible
	            bg:SetPoint("TOPLEFT", f, "TOPLEFT", 3, -3)
	            bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -3, 3)
	            f._ScooterBgOverlay = bg
	        end

	        -- Custom title area: circular icon overlapping top-left + green "ScooterMod" label in Roboto Bold
	        do
	            local fonts = addon and addon.Fonts or nil
	            local titleRegion = CreateFrame("Frame", nil, f)
	            titleRegion:SetSize(400, 56)
	            titleRegion:SetPoint("TOPLEFT", f, "TOPLEFT", -6, 10) -- nudge outwards to overlap corner

	            -- Circular icon
            local icon = titleRegion:CreateTexture(nil, "OVERLAY")
	            icon:SetSize(56, 56)
	            icon:SetPoint("LEFT", titleRegion, "LEFT", 0, -6) -- drop a bit to straddle the title bar
	            -- Try multiple extensions so the asset can be provided as TGA/BLP/PNG; prefer TGA for production
            local function trySetIcon(base)
                -- Prefer PNG for header rendering to avoid conversion artifacts; fall back to TGA/BLP
                local candidates = { base .. ".png", base .. ".tga", base .. ".blp" }
	                for _, p in ipairs(candidates) do
	                    local ok = pcall(icon.SetTexture, icon, p)
	                    if ok and icon:GetTexture() then return true end
	                end
	            end
            trySetIcon("Interface\\AddOns\\ScooterMod\\Scooter")
            -- Use a circular alpha mask
            pcall(icon.SetMask, icon, "Interface\\CharacterFrame\\TempPortraitAlphaMask")

            -- No backdrop/band for the title per design

	            -- Title text
            local title = titleRegion:CreateFontString(nil, "OVERLAY")
            -- Start just to the right of the circular icon; lift to align with title bar
            title:SetPoint("LEFT", icon, "RIGHT", 2, 10)
	            title:SetJustifyH("LEFT")
	            -- Use bundled Roboto Bold if available, else fall back; set font BEFORE text
            if fonts and fonts.ROBOTO_BLD then
                title:SetFont(fonts.ROBOTO_BLD, 20, "THICKOUTLINE")
            else
                title:SetFont("Fonts\\ARIALN.TTF", 20, "THICKOUTLINE")
            end
            title:SetShadowColor(0, 0, 0, 1)
            title:SetShadowOffset(1, -1)
	            title:SetTextColor(0.2, 0.9, 0.3, 1)
	            title:SetText("ScooterMod")

            -- No backdrop sizing needed

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
        if panel and panel.ApplyButtonTheme then panel.ApplyButtonTheme(headerEditBtn) end
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
            if panel and panel.ApplyButtonTheme then panel.ApplyButtonTheme(btn) end
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
            -- Insert a new button to open Blizzard's Advanced Cooldown Settings to the LEFT of Collapse All
            do
                local cdmBtn = f.SettingsList.Header.ScooterCDMButton
                if not cdmBtn then
                    cdmBtn = CreateFrame("Button", nil, f.SettingsList.Header, "UIPanelButtonTemplate")
                    cdmBtn:SetSize(200, 22)
                    cdmBtn.Text:SetText("Cooldown Manager Settings")
                    cdmBtn:ClearAllPoints()
                    cdmBtn:SetPoint("RIGHT", btn, "LEFT", -8, 0)
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
                    f.SettingsList.Header.ScooterCDMButton = cdmBtn
                end
            end
            -- Evaluate initial visibility for the current page (manage/presets should hide)
            if panel and panel.UpdateCollapseButtonVisibility then
                panel.UpdateCollapseButtonVisibility()
            end
        end
        local canvas = CreateFrame("Frame", nil, container)
        canvas:SetAllPoints(container); canvas:SetClipsChildren(true); canvas:Hide()
        f.Canvas = canvas
        panel.frame = f

        -- Prevent unintended closure during Edit Mode ApplyChanges by restoring visibility when protected
        if not f._ScooterProtectHooked then
            f:HookScript("OnHide", function(frame)
                local pnl = addon and addon.SettingsPanel
                if pnl and pnl._protectVisibility then
                    pnl._protectVisibility = false
                    if pnl and pnl.frame and not pnl.frame:IsShown() then pnl.frame:Show() end
                end
            end)
            f._ScooterProtectHooked = true
        end
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
