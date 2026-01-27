local addonName, addon = ...

addon.SettingsPanel = addon.SettingsPanel or {}
local panel = addon.SettingsPanel
panel.UnitFramesSections = panel.UnitFramesSections or {}

local function build(ctx, init)
	local componentId = ctx.componentId
	local title = ctx.title
	local panel = ctx.panel or panel
	local addon = ctx.addon or addon

	-- Skip for ToT - it has its own section builder (tot_health)
	if componentId == "ufToT" then return end
	-- Skip for Boss - it has its own section builder (boss_health)
	if componentId == "ufBoss" then return end

				-- Second collapsible section: Health Bar (blank for now)
				local expInitializerHB = Settings.CreateElementInitializer("ScooterExpandableSectionTemplate", {
					name = "Health Bar",
					sectionKey = "Health Bar",
					componentId = componentId,
					expanded = panel:IsSectionExpanded(componentId, "Health Bar"),
				})
				expInitializerHB.GetExtent = function() return 30 end
			table.insert(init, expInitializerHB)
	
			--[[
				UNIT FRAMES TABBED SECTION TAB PRIORITY ORDER (all Player/Target/Focus/Pet sections):
				1. Positioning
				2. Sizing
				3. Style/Texture (corresponds to "Style" tabs)
				4. Border
				5. Visibility
				6. Text Elements (e.g., "% Text", "Value Text")
				
				When adding or reordering tabs in Unit Frames tabbed sections, follow this priority.
			]]--
			-- Health Bar tabs (Direction for Target/Focus, then Style, Border, Text variants)
			-- Player/Pet now has Visibility tab: Style(A), Border(B), Visibility(C), % Text(D), Value Text(E)
			local isTargetOrFocusHB = (componentId == "ufTarget" or componentId == "ufFocus")
			local isPlayerHB = (componentId == "ufPlayer")
			local hbTabs = { sectionTitle = "" }
			if isTargetOrFocusHB then
				hbTabs.tabAText = "Direction"
				hbTabs.tabBText = "Style"
				hbTabs.tabCText = "Border"
				hbTabs.tabDText = "% Text"
				hbTabs.tabEText = "Value Text"
			elseif isPlayerHB then
				-- Player gets Visibility tab between Border and Text tabs
				hbTabs.tabAText = "Style"
				hbTabs.tabBText = "Border"
				hbTabs.tabCText = "Visibility"
				hbTabs.tabDText = "% Text"
				hbTabs.tabEText = "Value Text"
			else
				-- Pet keeps original 4-tab layout
				hbTabs.tabAText = "Style"
				hbTabs.tabBText = "Border"
				hbTabs.tabCText = "% Text"
				hbTabs.tabDText = "Value Text"
			end
				hbTabs.build = function(frame)
					local function unitKey()
						if componentId == "ufPlayer" then return "Player" end
						if componentId == "ufTarget" then return "Target" end
						if componentId == "ufFocus" then return "Focus" end
						if componentId == "ufPet" then return "Pet" end
						return nil
					end
					local function ensureUFDB()
						local db = addon and addon.db and addon.db.profile
						if not db then return nil end
						db.unitFrames = db.unitFrames or {}
						local uk = unitKey(); if not uk then return nil end
						db.unitFrames[uk] = db.unitFrames[uk] or {}
						return db.unitFrames[uk]
					end
	
					-- Local UI helpers (mirror Action Bar Text helpers)
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
						if panel and panel.ThemeSliderValue then panel.ThemeSliderValue(f) end
						yRef.y = yRef.y - 34
						return f
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
						if f.Control and panel.ThemeDropdownWithSteppers then panel.ThemeDropdownWithSteppers(f.Control) end
						if type(label) == "string" and string.find(label, "Font") and not string.find(label, "Style") and f.Control and f.Control.Dropdown and addon and addon.InitFontDropdown then
							addon.InitFontDropdown(f.Control.Dropdown, setting, optsProvider)
						end
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
	
					local function addTextInput(parent, label, minV, maxV, getFunc, setFunc, yRef, settingId)
						local options = Settings.CreateSliderOptions(minV, maxV, 1)
						options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v)
							return tostring(roundPositionValue(v))
						end)
						local setting = CreateLocalSetting(label, "number", getFunc, setFunc, getFunc())
						local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = label, setting = setting, options = options })
						initSlider.data = initSlider.data or {}
						initSlider.data.settingId = settingId
						initSlider.data.componentId = componentId
						if ConvertSliderInitializerToTextInput then
							ConvertSliderInitializerToTextInput(initSlider)
						end
						local row = CreateFrame("Frame", nil, parent, "SettingsSliderControlTemplate")
						row.GetElementData = function() return initSlider end
						row:SetPoint("TOPLEFT", 4, yRef.y)
						row:SetPoint("TOPRIGHT", -16, yRef.y)
						initSlider:InitFrame(row)
						if row.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(row.Text) end
						if panel and panel.ThemeSliderValue then panel.ThemeSliderValue(row) end
						yRef.y = yRef.y - 34
						return row
					end
	
					local function setRowEnabled(row, enabled)
						if not row then return end
						local alpha = enabled and 1 or 0.4
						local label = row.Text or row.Label
						if label and label.SetTextColor then
							label:SetTextColor(enabled and 1 or 0.6, enabled and 1 or 0.6, enabled and 1 or 0.6, 1)
						end
						if row.ScooterTextInput then
							row.ScooterTextInput:SetEnabled(enabled)
							row.ScooterTextInput:SetAlpha(alpha)
						end
						local controls = {
							row.Control,
							row.SliderWithSteppers,
							row.Slider,
						}
						for _, ctrl in ipairs(controls) do
							if ctrl then
								if ctrl.SetEnabled then ctrl:SetEnabled(enabled) end
								if ctrl.EnableMouse then ctrl:EnableMouse(enabled) end
								if enabled and ctrl.Enable then ctrl:Enable() end
								if not enabled and ctrl.Disable then ctrl:Disable() end
								if ctrl.SetAlpha then ctrl:SetAlpha(alpha) end
							end
						end
						if row.EnableMouse then row:EnableMouse(enabled) end
						row:SetAlpha(alpha)
					end
	
					local function clampScreenInput(value)
						local v = roundPositionValue(value or 0)
						if v > 2000 then v = 2000 elseif v < -2000 then v = -2000 end
						return v
					end
	
					local customPositionRows = {}
					local function refreshPowerPositionState()
						local enabled = customPositionRows.isEnabled and customPositionRows.isEnabled()
						setRowEnabled(customPositionRows.customX, enabled)
						setRowEnabled(customPositionRows.customY, enabled)
						setRowEnabled(customPositionRows.offsetX, not enabled)
						setRowEnabled(customPositionRows.offsetY, not enabled)
					end
	
					-- PageA: Direction (Target/Focus only)
					if isTargetOrFocusHB then
						do
							local function applyNow()
								if addon and addon.ApplyStyles then addon:ApplyStyles() end
							end
							local y = { y = -50 }
	
							-- Bar Fill Direction dropdown (Target/Focus only)
							local label = "Bar Fill Direction"
							local function fillDirOptions()
								local container = Settings.CreateControlTextContainer()
								container:Add("default", "Left to Right (Default)")
								container:Add("reverse", "Right to Left (Mirrored)")
								return container:GetData()
							end
							local function getter()
								local t = ensureUFDB() or {}
								return t.healthBarReverseFill and "reverse" or "default"
							end
							local function setter(v)
								local t = ensureUFDB(); if not t then return end
								t.healthBarReverseFill = (v == "reverse")
								applyNow()
							end
							addDropdown(frame.PageA, label, fillDirOptions, getter, setter, y)
						end
					end
	
					-- % Text page: PageD for Target/Focus and Player (both have extra tabs before it), PageC for Pet
					local percentTextPage = (isTargetOrFocusHB or isPlayerHB) and frame.PageD or frame.PageC
					do
						local function applyNow()
							if addon and addon.ApplyUnitFrameHealthTextVisibilityFor then addon.ApplyUnitFrameHealthTextVisibilityFor(unitKey()) end
							if addon and addon.ApplyStyles then addon:ApplyStyles() end
						end
						local function fontOptions()
							return addon.BuildFontOptionsContainer()
						end
						local y = { y = -50 }
						local label = "Disable % Text"
						local function getter()
							local t = ensureUFDB(); return t and not not t.healthPercentHidden or false
						end
						local function setter(v)
							local t = ensureUFDB(); if not t then return end
							t.healthPercentHidden = (v and true) or false
							applyNow()
						end
						local setting = CreateLocalSetting(label, "boolean", getter, setter, getter())
						local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = label, setting = setting, options = {} })
						local row = CreateFrame("Frame", nil, percentTextPage, "SettingsCheckboxControlTemplate")
						row.GetElementData = function() return initCb end
						row:SetPoint("TOPLEFT", 4, y.y)
						row:SetPoint("TOPRIGHT", -16, y.y)
						initCb:InitFrame(row)
						if panel and panel.ApplyRobotoWhite then
							if row.Text then panel.ApplyRobotoWhite(row.Text) end
							local cb = row.Checkbox or row.CheckBox or (row.Control and row.Control.Checkbox)
							if cb and cb.Text then panel.ApplyRobotoWhite(cb.Text) end
							-- Theme the checkbox checkmark to green
							if cb and panel.ThemeCheckbox then panel.ThemeCheckbox(cb) end
						end
						y.y = y.y - 34
						-- Font controls for % Text
						addDropdown(percentTextPage, "% Text Font", fontOptions,
							function() local t = ensureUFDB() or {}; local s = t.textHealthPercent or {}; return s.fontFace or "FRIZQT__" end,
							function(v) local t = ensureUFDB(); if not t then return end; t.textHealthPercent = t.textHealthPercent or {}; t.textHealthPercent.fontFace = v; applyNow() end,
							y)
						addStyle(percentTextPage, "% Text Style",
							function() local t = ensureUFDB() or {}; local s = t.textHealthPercent or {}; return s.style or "OUTLINE" end,
							function(v) local t = ensureUFDB(); if not t then return end; t.textHealthPercent = t.textHealthPercent or {}; t.textHealthPercent.style = v; applyNow() end,
							y)
						addSlider(percentTextPage, "% Text Size", 6, 48, 1,
							function() local t = ensureUFDB() or {}; local s = t.textHealthPercent or {}; return tonumber(s.size) or 14 end,
							function(v) local t = ensureUFDB(); if not t then return end; t.textHealthPercent = t.textHealthPercent or {}; t.textHealthPercent.size = tonumber(v) or 14; applyNow() end,
							y)
						addColor(percentTextPage, "% Text Color", true,
							function() local t = ensureUFDB() or {}; local s = t.textHealthPercent or {}; local c = s.color or {1,1,1,1}; return c[1], c[2], c[3], c[4] end,
							function(r,g,b,a) local t = ensureUFDB(); if not t then return end; t.textHealthPercent = t.textHealthPercent or {}; t.textHealthPercent.color = {r,g,b,a}; applyNow() end,
							y)
						-- % Text Alignment dropdown
						do
							local function alignOpts()
								local c = Settings.CreateControlTextContainer()
								c:Add("LEFT", "Left")
								c:Add("CENTER", "Center")
								c:Add("RIGHT", "Right")
								return c:GetData()
							end
							local function getAlign()
								local t = ensureUFDB() or {}; local s = t.textHealthPercent or {}; return s.alignment or "LEFT"
							end
							local function setAlign(v)
								local t = ensureUFDB(); if not t then return end
								t.textHealthPercent = t.textHealthPercent or {}
								t.textHealthPercent.alignment = v or "LEFT"
								applyNow()
							end
							local setting = CreateLocalSetting("% Text Alignment", "string", getAlign, setAlign, getAlign())
							local initDrop = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", { name = "% Text Alignment", setting = setting, options = alignOpts })
							local f = CreateFrame("Frame", nil, percentTextPage, "SettingsDropdownControlTemplate")
							f.GetElementData = function() return initDrop end
							f:SetPoint("TOPLEFT", 4, y.y)
							f:SetPoint("TOPRIGHT", -16, y.y)
							initDrop:InitFrame(f)
							if panel and panel.ApplyRobotoWhite then
								local lbl = f and (f.Text or f.Label)
								if lbl then panel.ApplyRobotoWhite(lbl) end
							end
							if f.Control and panel.ThemeDropdownWithSteppers then panel.ThemeDropdownWithSteppers(f.Control) end
							y.y = y.y - 34
						end
						addSlider(percentTextPage, "% Text Offset X", -100, 100, 1,
							function() local t = ensureUFDB() or {}; local s = t.textHealthPercent or {}; local o = s.offset or {}; return tonumber(o.x) or 0 end,
							function(v) local t = ensureUFDB(); if not t then return end; t.textHealthPercent = t.textHealthPercent or {}; t.textHealthPercent.offset = t.textHealthPercent.offset or {}; t.textHealthPercent.offset.x = tonumber(v) or 0; applyNow() end,
							y)
						addSlider(percentTextPage, "% Text Offset Y", -100, 100, 1,
							function() local t = ensureUFDB() or {}; local s = t.textHealthPercent or {}; local o = s.offset or {}; return tonumber(o.y) or 0 end,
							function(v) local t = ensureUFDB(); if not t then return end; t.textHealthPercent = t.textHealthPercent or {}; t.textHealthPercent.offset = t.textHealthPercent.offset or {}; t.textHealthPercent.offset.y = tonumber(v) or 0; applyNow() end,
							y)
					end
	
					-- Value Text page: PageE for Target/Focus and Player (both have extra tabs before it), PageD for Pet
					local valueTextPage = (isTargetOrFocusHB or isPlayerHB) and frame.PageE or frame.PageD
					do
						local function applyNow()
							if addon and addon.ApplyUnitFrameHealthTextVisibilityFor then addon.ApplyUnitFrameHealthTextVisibilityFor(unitKey()) end
							if addon and addon.ApplyStyles then addon:ApplyStyles() end
						end
						local function fontOptions()
							return addon.BuildFontOptionsContainer()
						end
						local y = { y = -50 }
						local label = "Disable Value Text"
						local function getter()
							local t = ensureUFDB(); return t and not not t.healthValueHidden or false
						end
						local function setter(v)
							local t = ensureUFDB(); if not t then return end
							t.healthValueHidden = (v and true) or false
							applyNow()
						end
						local setting = CreateLocalSetting(label, "boolean", getter, setter, getter())
						local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = label, setting = setting, options = {} })
						local row = CreateFrame("Frame", nil, valueTextPage, "SettingsCheckboxControlTemplate")
						row.GetElementData = function() return initCb end
						row:SetPoint("TOPLEFT", 4, y.y)
						row:SetPoint("TOPRIGHT", -16, y.y)
						initCb:InitFrame(row)
						if panel and panel.ApplyRobotoWhite then
							if row.Text then panel.ApplyRobotoWhite(row.Text) end
							local cb = row.Checkbox or row.CheckBox or (row.Control and row.Control.Checkbox)
							if cb and cb.Text then panel.ApplyRobotoWhite(cb.Text) end
							-- Theme the checkbox checkmark to green
							if cb and panel.ThemeCheckbox then panel.ThemeCheckbox(cb) end
						end
						-- Match % Text layout: drop the cursor after the checkbox row
						y.y = y.y - 34
						-- Font controls for Value Text
						addDropdown(valueTextPage, "Value Text Font", fontOptions,
							function() local t = ensureUFDB() or {}; local s = t.textHealthValue or {}; return s.fontFace or "FRIZQT__" end,
							function(v) local t = ensureUFDB(); if not t then return end; t.textHealthValue = t.textHealthValue or {}; t.textHealthValue.fontFace = v; applyNow() end,
							y)
						addStyle(valueTextPage, "Value Text Style",
							function() local t = ensureUFDB() or {}; local s = t.textHealthValue or {}; return s.style or "OUTLINE" end,
							function(v) local t = ensureUFDB(); if not t then return end; t.textHealthValue = t.textHealthValue or {}; t.textHealthValue.style = v; applyNow() end,
							y)
						addSlider(valueTextPage, "Value Text Size", 6, 48, 1,
							function() local t = ensureUFDB() or {}; local s = t.textHealthValue or {}; return tonumber(s.size) or 14 end,
							function(v) local t = ensureUFDB(); if not t then return end; t.textHealthValue = t.textHealthValue or {}; t.textHealthValue.size = tonumber(v) or 14; applyNow() end,
							y)
						addColor(valueTextPage, "Value Text Color", true,
							function() local t = ensureUFDB() or {}; local s = t.textHealthValue or {}; local c = s.color or {1,1,1,1}; return c[1], c[2], c[3], c[4] end,
							function(r,g,b,a) local t = ensureUFDB(); if not t then return end; t.textHealthValue = t.textHealthValue or {}; t.textHealthValue.color = {r,g,b,a}; applyNow() end,
							y)
						-- Value Text Alignment dropdown
						do
							local function alignOpts()
								local c = Settings.CreateControlTextContainer()
								c:Add("LEFT", "Left")
								c:Add("CENTER", "Center")
								c:Add("RIGHT", "Right")
								return c:GetData()
							end
							local function getAlign()
								local t = ensureUFDB() or {}; local s = t.textHealthValue or {}; return s.alignment or "RIGHT"
							end
							local function setAlign(v)
								local t = ensureUFDB(); if not t then return end
								t.textHealthValue = t.textHealthValue or {}
								t.textHealthValue.alignment = v or "RIGHT"
								applyNow()
							end
							local setting = CreateLocalSetting("Value Text Alignment", "string", getAlign, setAlign, getAlign())
							local initDrop = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", { name = "Value Text Alignment", setting = setting, options = alignOpts })
							local f = CreateFrame("Frame", nil, valueTextPage, "SettingsDropdownControlTemplate")
							f.GetElementData = function() return initDrop end
							f:SetPoint("TOPLEFT", 4, y.y)
							f:SetPoint("TOPRIGHT", -16, y.y)
							initDrop:InitFrame(f)
							if panel and panel.ApplyRobotoWhite then
								local lbl = f and (f.Text or f.Label)
								if lbl then panel.ApplyRobotoWhite(lbl) end
							end
							if f.Control and panel.ThemeDropdownWithSteppers then panel.ThemeDropdownWithSteppers(f.Control) end
							y.y = y.y - 34
						end
						addSlider(valueTextPage, "Value Text Offset X", -100, 100, 1,
							function() local t = ensureUFDB() or {}; local s = t.textHealthValue or {}; local o = s.offset or {}; return tonumber(o.x) or 0 end,
							function(v) local t = ensureUFDB(); if not t then return end; t.textHealthValue = t.textHealthValue or {}; t.textHealthValue.offset = t.textHealthValue.offset or {}; t.textHealthValue.offset.x = tonumber(v) or 0; applyNow() end,
							y)
						addSlider(valueTextPage, "Value Text Offset Y", -100, 100, 1,
							function() local t = ensureUFDB() or {}; local s = t.textHealthValue or {}; local o = s.offset or {}; return tonumber(o.y) or 0 end,
							function(v) local t = ensureUFDB(); if not t then return end; t.textHealthValue = t.textHealthValue or {}; t.textHealthValue.offset = t.textHealthValue.offset or {}; t.textHealthValue.offset.y = tonumber(v) or 0; applyNow() end,
							y)
					end
	
					-- PageA/PageB: Foreground/Background Texture + Color (PageB for Target/Focus, PageA for Player/Pet)
					local stylePage = isTargetOrFocusHB and frame.PageB or frame.PageA
					do
						local function applyNow()
							if addon and addon.ApplyStyles then addon:ApplyStyles() end
						end
						local y = { y = -50 }
						-- Foreground Texture dropdown
						local function opts() return addon.BuildBarTextureOptionsContainer() end
						local function getTex() local t = ensureUFDB() or {}; return t.healthBarTexture or "default" end
						local function setTex(v) local t = ensureUFDB(); if not t then return end; t.healthBarTexture = v; applyNow() end
						local texSetting = CreateLocalSetting("Foreground Texture", "string", getTex, setTex, getTex())
						local initDrop = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", { name = "Foreground Texture", setting = texSetting, options = opts })
						local f = CreateFrame("Frame", nil, stylePage, "SettingsDropdownControlTemplate")
						f.GetElementData = function() return initDrop end
						f:SetPoint("TOPLEFT", 4, y.y)
						f:SetPoint("TOPRIGHT", -16, y.y)
	                    initDrop:InitFrame(f)
	                    if panel and panel.ApplyRobotoWhite then
	                        local lbl = f and (f.Text or f.Label)
	                        if lbl then panel.ApplyRobotoWhite(lbl) end
	                    end
	                    if f.Control and panel.ThemeDropdownWithSteppers then panel.ThemeDropdownWithSteppers(f.Control) end
	                    if f.Control and addon.InitBarTextureDropdown then addon.InitBarTextureDropdown(f.Control, texSetting) end
						y.y = y.y - 34
	
						-- Foreground Color (dropdown + inline swatch)
	                    local function colorOpts()
							local container = Settings.CreateControlTextContainer()
	                        container:Add("default", "Default")
	                        container:Add("texture", "Texture Original")
	                        container:Add("class", "Class Color")
	                        container:Add("custom", "Custom")
							return container:GetData()
						end
						local function getColorMode() local t = ensureUFDB() or {}; return t.healthBarColorMode or "default" end
						local function setColorMode(v)
							local t = ensureUFDB(); if not t then return end; t.healthBarColorMode = v or "default"; applyNow()
						end
						local function getTintTbl()
							local t = ensureUFDB() or {}; local c = t.healthBarTint or {1,1,1,1}; return { c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 }
						end
						local function setTintTbl(r,g,b,a)
							local t = ensureUFDB(); if not t then return end; t.healthBarTint = { r or 1, g or 1, b or 1, a or 1 }; applyNow()
						end
						panel.DropdownWithInlineSwatch(stylePage, y, {
							label = "Foreground Color",
							getMode = getColorMode,
							setMode = setColorMode,
							getColor = getTintTbl,
							setColor = setTintTbl,
							options = colorOpts,
							insideButton = true,
						})
	
						-- Spacer row between Foreground and Background settings
						do
							local spacer = CreateFrame("Frame", nil, stylePage, "SettingsListElementTemplate")
							spacer:SetHeight(20)
							spacer:SetPoint("TOPLEFT", 4, y.y)
							spacer:SetPoint("TOPRIGHT", -16, y.y)
							if spacer.Text then
								spacer.Text:SetText("")
							end
							y.y = y.y - 24
						end
	
						-- Background Texture dropdown
						local function getBgTex() local t = ensureUFDB() or {}; return t.healthBarBackgroundTexture or "default" end
						local function setBgTex(v) local t = ensureUFDB(); if not t then return end; t.healthBarBackgroundTexture = v; applyNow() end
						local bgTexSetting = CreateLocalSetting("Background Texture", "string", getBgTex, setBgTex, getBgTex())
						local initBgDrop = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", { name = "Background Texture", setting = bgTexSetting, options = opts })
						local fbg = CreateFrame("Frame", nil, stylePage, "SettingsDropdownControlTemplate")
						fbg.GetElementData = function() return initBgDrop end
						fbg:SetPoint("TOPLEFT", 4, y.y)
						fbg:SetPoint("TOPRIGHT", -16, y.y)
	                    initBgDrop:InitFrame(fbg)
	                    if panel and panel.ApplyRobotoWhite then
	                        local lbl = fbg and (fbg.Text or fbg.Label)
	                        if lbl then panel.ApplyRobotoWhite(lbl) end
	                    end
	                    if fbg.Control and panel.ThemeDropdownWithSteppers then panel.ThemeDropdownWithSteppers(fbg.Control) end
	                    if fbg.Control and addon.InitBarTextureDropdown then addon.InitBarTextureDropdown(fbg.Control, bgTexSetting) end
						y.y = y.y - 34
	
						-- Background Color (dropdown + inline swatch)
	                    local function bgColorOpts()
							local container = Settings.CreateControlTextContainer()
	                        container:Add("default", "Default")
	                        container:Add("texture", "Texture Original")
	                        container:Add("custom", "Custom")
							return container:GetData()
						end
						local function getBgColorMode() local t = ensureUFDB() or {}; return t.healthBarBackgroundColorMode or "default" end
						local function setBgColorMode(v)
							local t = ensureUFDB(); if not t then return end; t.healthBarBackgroundColorMode = v or "default"; applyNow()
						end
						local function getBgTintTbl()
							local t = ensureUFDB() or {}; local c = t.healthBarBackgroundTint or {0,0,0,1}; return { c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1 }
						end
						local function setBgTintTbl(r,g,b,a)
							local t = ensureUFDB(); if not t then return end; t.healthBarBackgroundTint = { r or 0, g or 0, b or 0, a or 1 }; applyNow()
						end
						panel.DropdownWithInlineSwatch(stylePage, y, {
							label = "Background Color",
							getMode = getBgColorMode,
							setMode = setBgColorMode,
							getColor = getBgTintTbl,
							setColor = setBgTintTbl,
							options = bgColorOpts,
							insideButton = true,
						})
	
						-- Background Opacity slider
						local function getBgOpacity() local t = ensureUFDB() or {}; return t.healthBarBackgroundOpacity or 50 end
						local function setBgOpacity(v) local t = ensureUFDB(); if not t then return end; t.healthBarBackgroundOpacity = tonumber(v) or 50; applyNow() end
						local bgOpacitySetting = CreateLocalSetting("Background Opacity", "number", getBgOpacity, setBgOpacity, getBgOpacity())
						local bgOpacityOpts = Settings.CreateSliderOptions(0, 100, 1)
						bgOpacityOpts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return tostring(math.floor(v + 0.5)) end)
						local bgOpacityInit = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = "Background Opacity", setting = bgOpacitySetting, options = bgOpacityOpts })
						local fOpa = CreateFrame("Frame", nil, stylePage, "SettingsSliderControlTemplate")
						fOpa.GetElementData = function() return bgOpacityInit end
						fOpa:SetPoint("TOPLEFT", 4, y.y)
						fOpa:SetPoint("TOPRIGHT", -16, y.y)
						bgOpacityInit:InitFrame(fOpa)
						if panel and panel.ApplyControlTheme then panel.ApplyControlTheme(fOpa) end
						if panel and panel.ApplyRobotoWhite and fOpa.Text then panel.ApplyRobotoWhite(fOpa.Text) end
						y.y = y.y - 48
					end
	
					-- PageB/PageC: Border (Health Bar only) (PageC for Target/Focus, PageB for Player/Pet)
					local borderPage = isTargetOrFocusHB and frame.PageC or frame.PageB
					do
						local y = { y = -50 }
						local function optionsBorder()
							-- Start with "None", then append all standard bar border styles from the shared provider
							local c = Settings.CreateControlTextContainer()
							c:Add("none", "None")
							if addon and addon.BuildBarBorderOptionsContainer then
								local base = addon.BuildBarBorderOptionsContainer()
								-- Append all entries as-is so future additions appear automatically
								if type(base) == "table" then
									for _, entry in ipairs(base) do
										if entry and entry.value and entry.text then
											c:Add(entry.value, entry.text)
										end
									end
								end
							else
								-- Fallback: ensure at least Default exists
								c:Add("square", "Default (Square)")
							end
							return c:GetData()
						end
						local function isEnabled()
							local t = ensureUFDB() or {}
							return not not t.useCustomBorders
						end
						local function applyNow()
							local uk = unitKey()
							if addon and uk and addon.ApplyUnitFrameBarTexturesFor then addon.ApplyUnitFrameBarTexturesFor(uk) end
						end
						local function getStyle()
							local t = ensureUFDB() or {}; return t.healthBarBorderStyle or "square"
						end
						local function setStyle(v)
							local t = ensureUFDB(); if not t then return end
							t.healthBarBorderStyle = v or "square"
							applyNow()
						end
						local styleSetting = CreateLocalSetting("Border Style", "string", getStyle, setStyle, getStyle())
						local initDrop = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", { name = "Border Style", setting = styleSetting, options = optionsBorder })
						local f = CreateFrame("Frame", nil, borderPage, "SettingsDropdownControlTemplate")
						f.GetElementData = function() return initDrop end
						f:SetPoint("TOPLEFT", 4, y.y)
						f:SetPoint("TOPRIGHT", -16, y.y)
						initDrop:InitFrame(f)
						local lbl = f and (f.Text or f.Label)
						if lbl and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(lbl) end
						if f.Control and panel.ThemeDropdownWithSteppers then panel.ThemeDropdownWithSteppers(f.Control) end
						-- Grey out when Use Custom Borders is off
						local enabled = isEnabled()
						if f.Control and f.Control.SetEnabled then f.Control:SetEnabled(enabled) end
						if lbl and lbl.SetTextColor then
							if enabled then lbl:SetTextColor(1, 1, 1, 1) else lbl:SetTextColor(0.6, 0.6, 0.6, 1) end
						end
						y.y = y.y - 34
	
						-- Border Tint (checkbox + swatch)
						do
							local function getTintEnabled()
								local t = ensureUFDB() or {}; return not not t.healthBarBorderTintEnable
							end
							local function setTintEnabled(b)
								local t = ensureUFDB(); if not t then return end
								t.healthBarBorderTintEnable = not not b
								applyNow()
							end
							local function getTint()
								local t = ensureUFDB() or {}
								local c = t.healthBarBorderTintColor or {1,1,1,1}
								return { c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 }
							end
							local function setTint(r, g, b, a)
								local t = ensureUFDB(); if not t then return end
								t.healthBarBorderTintColor = { r or 1, g or 1, b or 1, a or 1 }
								applyNow()
							end
							local tintSetting = CreateLocalSetting("Border Tint", "boolean", getTintEnabled, setTintEnabled, getTintEnabled())
							local initCb = CreateCheckboxWithSwatchInitializer(tintSetting, "Border Tint", getTint, setTint, 8)
							local row = CreateFrame("Frame", nil, borderPage, "SettingsCheckboxControlTemplate")
							row.GetElementData = function() return initCb end
							row:SetPoint("TOPLEFT", 4, y.y)
							row:SetPoint("TOPRIGHT", -16, y.y)
							initCb:InitFrame(row)
							-- Grey out when Use Custom Borders is off
							local enabled = isEnabled()
							local ctrl = row.Checkbox or row.CheckBox or (row.Control and row.Control.Checkbox) or row.Control
							if ctrl and ctrl.SetEnabled then ctrl:SetEnabled(enabled) end
							if row.ScooterInlineSwatch and row.ScooterInlineSwatch.EnableMouse then
								row.ScooterInlineSwatch:EnableMouse(enabled)
								if row.ScooterInlineSwatch.SetAlpha then row.ScooterInlineSwatch:SetAlpha(enabled and 1 or 0.5) end
							end
							local labelFS = (ctrl and ctrl.Text) or row.Text
							if labelFS and labelFS.SetTextColor then
								if enabled then labelFS:SetTextColor(1, 1, 1, 1) else labelFS:SetTextColor(0.6, 0.6, 0.6, 1) end
							end
							y.y = y.y - 34
						end
	
						-- Border Thickness
						do
							local function getThk()
								local t = ensureUFDB() or {}; return tonumber(t.healthBarBorderThickness) or 1
							end
							local function setThk(v)
								local t = ensureUFDB(); if not t then return end
								local nv = tonumber(v) or 1
								if nv < 1 then nv = 1 elseif nv > 8 then nv = 8 end
								t.healthBarBorderThickness = nv
								applyNow()
							end
							local opts = Settings.CreateSliderOptions(1, 8, 0.2)
							opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return string.format("%.1f", v) end)
							local thkSetting = CreateLocalSetting("Border Thickness", "number", getThk, setThk, getThk())
							local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = "Border Thickness", setting = thkSetting, options = opts })
							local sf = CreateFrame("Frame", nil, borderPage, "SettingsSliderControlTemplate")
							sf.GetElementData = function() return initSlider end
							sf:SetPoint("TOPLEFT", 4, y.y)
							sf:SetPoint("TOPRIGHT", -16, y.y)
							initSlider:InitFrame(sf)
							if sf.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(sf.Text) end
							if panel and panel.ThemeSliderValue then panel.ThemeSliderValue(sf) end
							-- Grey out when Use Custom Borders is off
							local enabled = isEnabled()
							if sf.Control and sf.Control.SetEnabled then sf.Control:SetEnabled(enabled) end
							if sf.Text and sf.Text.SetTextColor then
								if enabled then sf.Text:SetTextColor(1, 1, 1, 1) else sf.Text:SetTextColor(0.6, 0.6, 0.6, 1) end
							end
							y.y = y.y - 34
						end
	
						-- Border Inset (fine adjustments)
						do
							local function getInset()
								local t = ensureUFDB() or {}; return tonumber(t.healthBarBorderInset) or 0
							end
							local function setInset(v)
								local t = ensureUFDB(); if not t then return end
								local nv = tonumber(v) or 0
								if nv < -4 then nv = -4 elseif nv > 4 then nv = 4 end
								t.healthBarBorderInset = nv
								applyNow()
							end
							local opts = Settings.CreateSliderOptions(-4, 4, 1)
							opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return tostring(math.floor(v)) end)
							local insetSetting = CreateLocalSetting("Border Inset", "number", getInset, setInset, getInset())
							local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = "Border Inset", setting = insetSetting, options = opts })
							local sf = CreateFrame("Frame", nil, borderPage, "SettingsSliderControlTemplate")
							sf.GetElementData = function() return initSlider end
							sf:SetPoint("TOPLEFT", 4, y.y)
							sf:SetPoint("TOPRIGHT", -16, y.y)
							initSlider:InitFrame(sf)
							if sf.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(sf.Text) end
							if panel and panel.ThemeSliderValue then panel.ThemeSliderValue(sf) end
							local enabled = isEnabled()
							if sf.Control and sf.Control.SetEnabled then sf.Control:SetEnabled(enabled) end
							if sf.Text and sf.Text.SetTextColor then
								if enabled then sf.Text:SetTextColor(1, 1, 1, 1) else sf.Text:SetTextColor(0.6, 0.6, 0.6, 1) end
							end
							y.y = y.y - 34
						end
					end
	
					-- PageC: Visibility (Player Health Bar only)
					if isPlayerHB then
						do
							local function applyNow()
								local uk = unitKey()
								if uk and addon and addon.ApplyUnitFrameBarTexturesFor then
									addon.ApplyUnitFrameBarTexturesFor(uk)
								end
							end
	
							local y = { y = -50 }
	
							-- Hide Over Absorb Glow checkbox
							local label = "Hide Over Absorb Glow"
							local function getter()
								local t = ensureUFDB()
								return t and not not t.healthBarHideOverAbsorbGlow or false
							end
							local function setter(v)
								local t = ensureUFDB(); if not t then return end
								t.healthBarHideOverAbsorbGlow = (v and true) or false
								applyNow()
							end
	
							local setting = CreateLocalSetting(label, "boolean", getter, setter, getter())
							local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = label, setting = setting, options = {} })
							local row = CreateFrame("Frame", nil, frame.PageC, "SettingsCheckboxControlTemplate")
							row.GetElementData = function() return initCb end
							row:SetPoint("TOPLEFT", 4, y.y)
							row:SetPoint("TOPRIGHT", -16, y.y)
							initCb:InitFrame(row)
							if panel and panel.ApplyRobotoWhite then
								if row.Text then panel.ApplyRobotoWhite(row.Text) end
								local cb = row.Checkbox or row.CheckBox or (row.Control and row.Control.Checkbox)
								if cb and cb.Text then panel.ApplyRobotoWhite(cb.Text) end
								-- Theme the checkbox checkmark to green
								if cb and panel.ThemeCheckbox then panel.ThemeCheckbox(cb) end
							end
	
							-- Add info icon to the LEFT of the checkbox label
							if panel and panel.CreateInfoIconForLabel then
								local tooltipText = "Hides the glow effect on the edge of your health bar that appears when you have an absorb shield providing effective health in excess of your maximum health."
								local targetLabel = row.Text or (row.Checkbox and row.Checkbox.Text)
								if targetLabel and not row.ScooterOverAbsorbGlowInfoIcon then
									row.ScooterOverAbsorbGlowInfoIcon = panel.CreateInfoIconForLabel(targetLabel, tooltipText, 5, 0, 32)
									if row.ScooterOverAbsorbGlowInfoIcon then
										local function reposition()
											local icon = row.ScooterOverAbsorbGlowInfoIcon
											local lbl = row.Text or (row.Checkbox and row.Checkbox.Text)
											if icon and lbl then
												icon:ClearAllPoints()
												icon:SetPoint("RIGHT", lbl, "LEFT", -6, 0)
											end
										end
										if C_Timer and C_Timer.After then
											C_Timer.After(0, reposition)
										else
											reposition()
										end
									end
								end
							end
	
							y.y = y.y - 34

						-- Hide Heal Prediction checkbox
						local labelHP = "Hide Heal Prediction"
						local function getterHP()
							local t = ensureUFDB()
							return t and not not t.healthBarHideHealPrediction or false
						end
						local function setterHP(v)
							local t = ensureUFDB(); if not t then return end
							t.healthBarHideHealPrediction = (v and true) or false
							applyNow()
						end

						local settingHP = CreateLocalSetting(labelHP, "boolean", getterHP, setterHP, getterHP())
						local initCbHP = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = labelHP, setting = settingHP, options = {} })
						local rowHP = CreateFrame("Frame", nil, frame.PageC, "SettingsCheckboxControlTemplate")
						rowHP.GetElementData = function() return initCbHP end
						rowHP:SetPoint("TOPLEFT", 4, y.y)
						rowHP:SetPoint("TOPRIGHT", -16, y.y)
						initCbHP:InitFrame(rowHP)
						if panel and panel.ApplyRobotoWhite then
							if rowHP.Text then panel.ApplyRobotoWhite(rowHP.Text) end
							local cbHP = rowHP.Checkbox or rowHP.CheckBox or (rowHP.Control and rowHP.Control.Checkbox)
							if cbHP and cbHP.Text then panel.ApplyRobotoWhite(cbHP.Text) end
							if cbHP and panel.ThemeCheckbox then panel.ThemeCheckbox(cbHP) end
						end

						-- Add info icon to the LEFT of the checkbox label
						if panel and panel.CreateInfoIconForLabel then
							local tooltipTextHP = "Hides the green heal prediction bar that appears on your health bar when you or a party member is casting a heal on you."
							local targetLabelHP = rowHP.Text or (rowHP.Checkbox and rowHP.Checkbox.Text)
							if targetLabelHP and not rowHP.ScooterHealPredictionInfoIcon then
								rowHP.ScooterHealPredictionInfoIcon = panel.CreateInfoIconForLabel(targetLabelHP, tooltipTextHP, 5, 0, 32)
								if rowHP.ScooterHealPredictionInfoIcon then
									local function repositionHP()
										local icon = rowHP.ScooterHealPredictionInfoIcon
										local lbl = rowHP.Text or (rowHP.Checkbox and rowHP.Checkbox.Text)
										if icon and lbl then
											icon:ClearAllPoints()
											icon:SetPoint("RIGHT", lbl, "LEFT", -6, 0)
										end
									end
									if C_Timer and C_Timer.After then
										C_Timer.After(0, repositionHP)
									else
										repositionHP()
									end
								end
							end
						end

						y.y = y.y - 34
						end
					end
	
					-- Apply current visibility once when building
					if addon and addon.ApplyUnitFrameHealthTextVisibilityFor then addon.ApplyUnitFrameHealthTextVisibilityFor(unitKey()) end
				end
				local hbInit = Settings.CreateElementInitializer("ScooterTabbedSectionTemplate", hbTabs)
				-- STATIC HEIGHT for tabbed sections with up to 8 settings per tab.
				-- Current: 364px provides comfortable spacing for 8 controls (including alignment dropdown).
				-- DO NOT reduce below 350px or settings will bleed past the bottom border.
				hbInit.GetExtent = function() return 364 end
				hbInit:AddShownPredicate(function()
					return panel:IsSectionExpanded(componentId, "Health Bar")
				end)
				table.insert(init, hbInit)
	
end

panel.UnitFramesSections.health = build

return build