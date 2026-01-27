local addonName, addon = ...

addon.SettingsPanel = addon.SettingsPanel or {}
local panel = addon.SettingsPanel
panel.UnitFramesSections = panel.UnitFramesSections or {}

local function build(ctx, init)
	local componentId = ctx.componentId
	local title = ctx.title
	local panel = ctx.panel or panel
	local addon = ctx.addon or addon

	-- Skip for ToT - it has its own section builder (tot_power)
	if componentId == "ufToT" then return end
	-- Skip for Boss - it has its own section builder (boss_power)
	if componentId == "ufBoss" then return end

				-- Third collapsible section: Power Bar (blank for now)
				local expInitializerPB = Settings.CreateElementInitializer("ScooterExpandableSectionTemplate", {
					name = "Power Bar",
					sectionKey = "Power Bar",
					componentId = componentId,
					expanded = panel:IsSectionExpanded(componentId, "Power Bar"),
				})
				expInitializerPB.GetExtent = function() return 30 end
				table.insert(init, expInitializerPB)
	
	            -- Power Bar tabs (ordered by Unit Frames tab priority: Positioning > Sizing > Style/Texture > Border > Visibility > Text Elements)
	            -- Tab name is "Sizing/Direction" for Target/Focus (which support reverse fill), "Sizing" for Player/Pet
	            local isTargetOrFocusPB = (componentId == "ufTarget" or componentId == "ufFocus")
	            local sizingTabNamePB = isTargetOrFocusPB and "Sizing/Direction" or "Sizing"
	            -- Tabs: A=Positioning, B=Sizing/Direction, C=Style, D=Border, E=Visibility, F=% Text, G=Value Text
	            local pbTabs = {
	                sectionTitle = "",
	                tabAText = "Positioning",
	                tabBText = sizingTabNamePB,
	                tabCText = "Style",
	                tabDText = "Border",
	                tabEText = "Visibility",
	                tabFText = "% Text",
	                tabGText = "Value Text",
	            }
				pbTabs.build = function(frame)
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
	
					-- PageA: Positioning (Power Bar)
					do
						local function applyNow()
							if addon and addon.ApplyStyles then addon:ApplyStyles() end
						end
						local y = { y = -50 }

						-- X Offset slider
						addSlider(frame.PageA, "X Offset", -100, 100, 1,
							function() local t = ensureUFDB() or {}; return tonumber(t.powerBarOffsetX) or 0 end,
							function(v) local t = ensureUFDB(); if not t then return end; t.powerBarOffsetX = tonumber(v) or 0; applyNow() end,
							y)

						-- Y Offset slider
						addSlider(frame.PageA, "Y Offset", -100, 100, 1,
							function() local t = ensureUFDB() or {}; return tonumber(t.powerBarOffsetY) or 0 end,
							function(v) local t = ensureUFDB(); if not t then return end; t.powerBarOffsetY = tonumber(v) or 0; applyNow() end,
							y)
					end
	
					-- PageB: Sizing/Direction (Power Bar)
					do
						local function applyNow()
							if addon and addon.ApplyStyles then addon:ApplyStyles() end
						end
						local y = { y = -50 }
	
						-- Bar Fill Direction dropdown (Target/Focus only)
						if isTargetOrFocusPB then
							local label = "Bar Fill Direction"
							local function fillDirOptions()
								local container = Settings.CreateControlTextContainer()
								container:Add("default", "Left to Right (Default)")
								container:Add("reverse", "Right to Left (Mirrored)")
								return container:GetData()
							end
							local function getter()
								local t = ensureUFDB() or {}
								return t.powerBarReverseFill and "reverse" or "default"
							end
							local function setter(v)
								local t = ensureUFDB(); if not t then return end
								local wasReverse = not not t.powerBarReverseFill
								local willBeReverse = (v == "reverse")
								
								if wasReverse and not willBeReverse then
									-- Switching FROM reverse TO default: Save current width and force to 100
									local currentWidth = tonumber(t.powerBarWidthPct) or 100
									t.powerBarWidthPctSaved = currentWidth
									t.powerBarWidthPct = 100
								elseif not wasReverse and willBeReverse then
									-- Switching FROM default TO reverse: Restore saved width
									local savedWidth = tonumber(t.powerBarWidthPctSaved) or 100
									t.powerBarWidthPct = savedWidth
								end
								
								t.powerBarReverseFill = willBeReverse
								applyNow()
								-- Refresh the Bar Width slider state so the UI matches the new fill direction
								if frame and frame.PageB and frame.PageB.ScooterUpdateBarWidthState then
									frame.PageB.ScooterUpdateBarWidthState()
								end
								if C_Timer and C_Timer.After then
									C_Timer.After(0, function()
										if frame and frame.PageB and frame.PageB.ScooterUpdateBarWidthState then
											frame.PageB.ScooterUpdateBarWidthState()
										end
									end)
								end
							end
							addDropdown(frame.PageB, label, fillDirOptions, getter, setter, y)
						end
	
						-- Bar Width slider (only enabled for Target/Focus with reverse fill)
						local function fmtInt(v) return tostring(math.floor((tonumber(v) or 0) + 0.5)) end
						local label = "Bar Width (%)"
						local options = Settings.CreateSliderOptions(50, 150, 1)
						options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return fmtInt(v) end)
	
						-- Forward declarations so dependent setters can refresh state after DB writes
						local widthSlider
						local updateWidthSliderState
	
						-- Getter: Always return the actual stored value
						local function getter()
							local t = ensureUFDB() or {}
							return tonumber(t.powerBarWidthPct) or 100
						end
	
						-- Setter: Store value normally (only when slider is enabled)
						local function setter(v)
							local t = ensureUFDB(); if not t then return end
							-- For Target/Focus: prevent changes when reverse fill is disabled
							if isTargetOrFocusPB and not t.powerBarReverseFill then
								return -- Silently ignore changes when disabled
							end
							local val = tonumber(v) or 100
							val = math.max(50, math.min(150, val))
							t.powerBarWidthPct = val
							applyNow()
						end
	
						local setting = CreateLocalSetting(label, "number", getter, setter, getter())
						local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = label, setting = setting, options = options })
						widthSlider = CreateFrame("Frame", nil, frame.PageB, "SettingsSliderControlTemplate")
						widthSlider.GetElementData = function() return initSlider end
						widthSlider:SetPoint("TOPLEFT", 4, y.y)
						widthSlider:SetPoint("TOPRIGHT", -16, y.y)
						initSlider:InitFrame(widthSlider)
						if widthSlider.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(widthSlider.Text) end
						if panel and panel.ThemeSliderValue then panel.ThemeSliderValue(widthSlider) end
	
						-- Store reference for later updates
						widthSlider._scooterSetting = setting
	
						local function syncSliderToDB()
							if not widthSlider then return end
							local sliderWidget
							if widthSlider.Control and widthSlider.Control.Slider then
								sliderWidget = widthSlider.Control.Slider
							elseif widthSlider.SliderWithSteppers and widthSlider.SliderWithSteppers.Slider then
								sliderWidget = widthSlider.SliderWithSteppers.Slider
							elseif widthSlider.Slider then
								sliderWidget = widthSlider.Slider
							end
							if sliderWidget and sliderWidget.GetValue and sliderWidget.SetValue then
								local desired = getter()
								local current = sliderWidget:GetValue()
								if math.abs((current or 0) - desired) > 0.001 then
									sliderWidget:SetValue(desired)
								end
							end
						end
	
						updateWidthSliderState = function()
							if not widthSlider then return end
							local t = ensureUFDB() or {}
	
							local function ensureStaticRow()
								if widthSlider.ScooterBarWidthStatic then return widthSlider.ScooterBarWidthStatic end
								local static = CreateFrame("Frame", nil, frame.PageB, "SettingsListElementTemplate")
								static:SetHeight(26)
								static:SetPoint("TOPLEFT", widthSlider, "TOPLEFT", 0, 0)
								static:SetPoint("TOPRIGHT", widthSlider, "TOPRIGHT", 0, 0)
								local baseLabel = (widthSlider.Text and widthSlider.Text:GetText()) or "Bar Width (%)"
								static.Text:SetText(baseLabel .. " — 100%")
								if panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(static.Text) end
								static.Text:ClearAllPoints()
								static.Text:SetPoint("LEFT", static, "LEFT", 36.5, 0)
								static.Text:SetJustifyH("LEFT")
								widthSlider.ScooterBarWidthStatic = static
								return static
							end
	
							local function ensureInfoIcon()
								if not panel or not panel.CreateInfoIconForLabel then return end
								if widthSlider.ScooterBarWidthStaticInfo then return end
								local static = widthSlider.ScooterBarWidthStatic
								if not static or not static.Text then return end
								local tooltipText = "Bar Width scaling is only available when using 'Right to Left (mirrored)' fill direction."
								widthSlider.ScooterBarWidthStaticInfo = panel.CreateInfoIconForLabel(
									static.Text,
									tooltipText,
									5, 0, 32
								)
								if C_Timer and C_Timer.After then
									C_Timer.After(0, function()
										local icon = widthSlider.ScooterBarWidthStaticInfo
										local label = widthSlider.ScooterBarWidthStatic and widthSlider.ScooterBarWidthStatic.Text
										if icon and label then
											icon:ClearAllPoints()
											local textWidth = label:GetStringWidth() or 0
											if textWidth > 0 then
												icon:SetPoint("LEFT", label, "LEFT", textWidth + 5, 0)
											else
												icon:SetPoint("LEFT", label, "RIGHT", 5, 0)
											end
										end
									end)
								end
							end
	
							local function enableSlider()
								if widthSlider.Text then widthSlider.Text:SetAlpha(1.0) end
								if widthSlider.Label then widthSlider.Label:SetAlpha(1.0) end
								if widthSlider.Control then 
									widthSlider.Control:Show()
									widthSlider.Control:Enable()
									if widthSlider.Control.EnableMouse then widthSlider.Control:EnableMouse(true) end
									if widthSlider.Control.Slider then widthSlider.Control.Slider:Enable() end
									if widthSlider.Control.Slider and widthSlider.Control.Slider.EnableMouse then widthSlider.Control.Slider:EnableMouse(true) end
									widthSlider.Control:SetAlpha(1.0)
								end
								if widthSlider.Slider then widthSlider.Slider:Enable() end
								if widthSlider.Slider and widthSlider.Slider.EnableMouse then widthSlider.Slider:EnableMouse(true) end
								if widthSlider.SliderWithSteppers and widthSlider.SliderWithSteppers.Enable then
									widthSlider.SliderWithSteppers:Enable()
								end
								widthSlider:SetAlpha(1.0)
								widthSlider:Show()
								if widthSlider.ScooterBarWidthStatic then widthSlider.ScooterBarWidthStatic:Hide() end
								if widthSlider.ScooterBarWidthStaticInfo then widthSlider.ScooterBarWidthStaticInfo:Hide() end
								syncSliderToDB()
							end
	
							local function disableSlider()
								if widthSlider.Text then widthSlider.Text:SetAlpha(0.5) end
								if widthSlider.Label then widthSlider.Label:SetAlpha(0.5) end
								if widthSlider.Control then 
									widthSlider.Control:Disable()
									if widthSlider.Control.EnableMouse then widthSlider.Control:EnableMouse(false) end
									if widthSlider.Control.Slider then widthSlider.Control.Slider:Disable() end
									if widthSlider.Control.Slider and widthSlider.Control.Slider.EnableMouse then widthSlider.Control.Slider:EnableMouse(false) end
									widthSlider.Control:SetAlpha(0.5)
								end
								if widthSlider.Slider then widthSlider.Slider:Disable() end
								if widthSlider.Slider and widthSlider.Slider.EnableMouse then widthSlider.Slider:EnableMouse(false) end
								if widthSlider.SliderWithSteppers and widthSlider.SliderWithSteppers.Disable then
									widthSlider.SliderWithSteppers:Disable()
								end
								widthSlider:SetAlpha(0.5)
								widthSlider:Hide()
								local static = ensureStaticRow()
								if static and static.Text then
									local baseLabel = (widthSlider.Text and widthSlider.Text:GetText()) or "Bar Width (%)"
									static.Text:SetText(baseLabel .. " — 100%")
									static.Text:ClearAllPoints()
									static.Text:SetPoint("LEFT", static, "LEFT", 36.5, 0)
									static.Text:SetJustifyH("LEFT")
								end
								ensureInfoIcon()
								if widthSlider.ScooterBarWidthStatic then widthSlider.ScooterBarWidthStatic:Show() end
								if widthSlider.ScooterBarWidthStaticInfo then widthSlider.ScooterBarWidthStaticInfo:Show() end
								syncSliderToDB()
							end
	
							if isTargetOrFocusPB then
								local isReverse = not not t.powerBarReverseFill
								if isReverse then
									enableSlider()
								else
									disableSlider()
								end
							else
								enableSlider()
							end
						end
	
						-- Initial state update and export for external refreshes
						updateWidthSliderState()
						widthSlider._updateState = updateWidthSliderState
						if frame and frame.PageB then
							frame.PageB.ScooterUpdateBarWidthState = updateWidthSliderState
						end
	
						y.y = y.y - 34
						
						-- Bar Height slider (only enabled when Use Custom Borders is checked)
						-- NOTE: Max capped at 100 (default) because growing above default causes animation
						-- artifacts in combat. Shrinking below default is supported. See UNITFRAMES.md.
						local heightLabel = "Bar Height (%)"
						local heightOptions = Settings.CreateSliderOptions(50, 100, 1)
						heightOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return fmtInt(v) end)
						
						-- Getter: Always return the actual stored value
						local function heightGetter()
							local t = ensureUFDB() or {}
							return tonumber(t.powerBarHeightPct) or 100
						end
						
						-- Setter: Store value normally (only when slider is enabled)
						local function heightSetter(v)
							local t = ensureUFDB(); if not t then return end
							-- Prevent changes when Use Custom Borders is disabled
							if not t.useCustomBorders then
								return -- Silently ignore changes when disabled
							end
							local val = tonumber(v) or 100
							val = math.max(50, math.min(100, val))
							t.powerBarHeightPct = val
							applyNow()
						end
						
						local heightSetting = CreateLocalSetting(heightLabel, "number", heightGetter, heightSetter, heightGetter())
						local initHeightSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = heightLabel, setting = heightSetting, options = heightOptions })
						local heightSlider = CreateFrame("Frame", nil, frame.PageB, "SettingsSliderControlTemplate")
						heightSlider.GetElementData = function() return initHeightSlider end
						heightSlider:SetPoint("TOPLEFT", 4, y.y)
						heightSlider:SetPoint("TOPRIGHT", -16, y.y)
						initHeightSlider:InitFrame(heightSlider)
						if heightSlider.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(heightSlider.Text) end
						
						-- Add info icon to enabled slider explaining the requirement
						if panel and panel.CreateInfoIconForLabel then
							local tooltipText = "Bar Height customization requires 'Use Custom Borders' to be enabled. This slider allows shrinking the bar (50-100%). Growing above default is disabled due to animation artifacts in combat.\n\nIf you are using a custom Bar Height for this Power Bar, we recommend also hiding the 'Bar-Full Spike Animations' via the setting on the Visibility tab."
							local label = heightSlider.Text or heightSlider.Label
							if label and not heightSlider.ScooterBarHeightInfoIcon then
								heightSlider.ScooterBarHeightInfoIcon = panel.CreateInfoIconForLabel(label, tooltipText, 5, 0, 32)
								C_Timer.After(0, function()
									local icon = heightSlider.ScooterBarHeightInfoIcon
									local lbl = heightSlider.Text or heightSlider.Label
									if icon and lbl then
										icon:ClearAllPoints()
										local textWidth = lbl:GetStringWidth() or 0
										if textWidth > 0 then
											icon:SetPoint("LEFT", lbl, "LEFT", textWidth + 5, 0)
										else
											icon:SetPoint("LEFT", lbl, "RIGHT", 5, 0)
										end
									end
								end)
							end
						end
						
						-- Store reference for later updates
						heightSlider._scooterSetting = heightSetting
						
						-- Conditional enable/disable based on Use Custom Borders
						local function updateHeightSliderState()
							local t = ensureUFDB() or {}
							local isEnabled = not not t.useCustomBorders
							
							if isEnabled then
								-- Enabled state: full opacity for all elements
								if heightSlider.Text then heightSlider.Text:SetAlpha(1.0) end
								if heightSlider.Label then heightSlider.Label:SetAlpha(1.0) end
								if heightSlider.Control then 
									heightSlider.Control:Show()
									heightSlider.Control:Enable()
									if heightSlider.Control.EnableMouse then heightSlider.Control:EnableMouse(true) end
									if heightSlider.Control.Slider then heightSlider.Control.Slider:Enable() end
									if heightSlider.Control.Slider and heightSlider.Control.Slider.EnableMouse then heightSlider.Control.Slider:EnableMouse(true) end
									heightSlider.Control:SetAlpha(1.0)
								end
								if heightSlider.Slider then heightSlider.Slider:Enable() end
								if heightSlider.Slider and heightSlider.Slider.EnableMouse then heightSlider.Slider:EnableMouse(true) end
								heightSlider:Show()
								if heightSlider.ScooterBarHeightStatic then heightSlider.ScooterBarHeightStatic:Hide() end
								if heightSlider.ScooterBarHeightStaticInfo then heightSlider.ScooterBarHeightStaticInfo:Hide() end
								if heightSlider.ScooterBarHeightInfoIcon then heightSlider.ScooterBarHeightInfoIcon:Show() end
							else
								-- Disabled state: gray out all visual elements
								if heightSlider.Text then heightSlider.Text:SetAlpha(0.5) end
								if heightSlider.Label then heightSlider.Label:SetAlpha(0.5) end
								if heightSlider.Control then 
									heightSlider.Control:Hide()
									heightSlider.Control:Disable()
									if heightSlider.Control.EnableMouse then heightSlider.Control:EnableMouse(false) end
									if heightSlider.Control.Slider then heightSlider.Control.Slider:Disable() end
									if heightSlider.Control.Slider and heightSlider.Control.Slider.EnableMouse then heightSlider.Control.Slider:EnableMouse(false) end
									heightSlider.Control:SetAlpha(0.5)
								end
								if heightSlider.Slider then heightSlider.Slider:Disable() end
								if heightSlider.Slider and heightSlider.Slider.EnableMouse then heightSlider.Slider:EnableMouse(false) end
								heightSlider:SetAlpha(0.5)
								
								-- Create static replacement row if it doesn't exist
								if not heightSlider.ScooterBarHeightStatic then
									local static = CreateFrame("Frame", nil, frame.PageB, "SettingsListElementTemplate")
									static:SetHeight(26)
									static:SetPoint("TOPLEFT", 4, y.y)
									static:SetPoint("TOPRIGHT", -16, y.y)
									static.Text = static:CreateFontString(nil, "OVERLAY", "GameFontNormal")
									static.Text:SetPoint("LEFT", static, "LEFT", 36.5, 0)
									static.Text:SetJustifyH("LEFT")
									if panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(static.Text) end
									heightSlider.ScooterBarHeightStatic = static
								end
								local static = heightSlider.ScooterBarHeightStatic
								if static and static.Text then
									local baseLabel = (heightSlider.Text and heightSlider.Text:GetText()) or "Bar Height (%)"
									static.Text:SetText(baseLabel .. " — 100%")
									static.Text:ClearAllPoints()
									static.Text:SetPoint("LEFT", static, "LEFT", 36.5, 0)
									static.Text:SetJustifyH("LEFT")
								end
								-- Add info icon on the static row explaining why it's disabled
								if panel and panel.CreateInfoIconForLabel and not heightSlider.ScooterBarHeightStaticInfo then
									local tooltipText = "Bar Height customization requires 'Use Custom Borders' to be enabled. This slider allows shrinking the bar (50-100%). Growing above default is disabled due to animation artifacts in combat."
									heightSlider.ScooterBarHeightStaticInfo = panel.CreateInfoIconForLabel(
										heightSlider.ScooterBarHeightStatic.Text,
										tooltipText,
										5, 0, 32
									)
									C_Timer.After(0, function()
										local icon = heightSlider.ScooterBarHeightStaticInfo
										local label = heightSlider.ScooterBarHeightStatic and heightSlider.ScooterBarHeightStatic.Text
										if icon and label then
											icon:ClearAllPoints()
											local textWidth = label:GetStringWidth() or 0
											if textWidth > 0 then
												icon:SetPoint("LEFT", label, "LEFT", textWidth + 5, 0)
											else
												icon:SetPoint("LEFT", label, "RIGHT", 5, 0)
											end
										end
									end)
								end
								if heightSlider.ScooterBarHeightStatic then heightSlider.ScooterBarHeightStatic:Show() end
								if heightSlider.ScooterBarHeightStaticInfo then heightSlider.ScooterBarHeightStaticInfo:Show() end
								if heightSlider.ScooterBarHeightInfoIcon then heightSlider.ScooterBarHeightInfoIcon:Hide() end
								heightSlider:Hide()
							end
						end
						
						-- Initial state update
						updateHeightSliderState()
						
						-- Store update function for external calls (e.g., when Use Custom Borders changes)
						heightSlider._updateState = updateHeightSliderState
						
						y.y = y.y - 34
					end
	
					-- PageE: Visibility (Power Bar)
					do
						local function applyNow()
							local uk = unitKey()
							-- Reapply bar styling (includes hide/show logic) and text visibility when the toggle changes
							if uk and addon and addon.ApplyUnitFrameBarTexturesFor then
								addon.ApplyUnitFrameBarTexturesFor(uk)
							end
							if uk and addon and addon.ApplyUnitFramePowerTextVisibilityFor then
								addon.ApplyUnitFramePowerTextVisibilityFor(uk)
							end
						end

						-- Helper to check if either main hide option is enabled (used to disable sub-checkboxes)
						local function isBarOrTextureHidden()
							local t = ensureUFDB()
							return t and (t.powerBarHidden == true or t.powerBarHideTextureOnly == true)
						end

						-- References to sub-checkboxes that should be disabled when bar/texture is hidden
						local visualCheckboxRows = {}

						-- Function to update disabled state of visual sub-checkboxes
						local function updateVisualCheckboxState()
							local shouldDisable = isBarOrTextureHidden()
							for _, rowInfo in ipairs(visualCheckboxRows) do
								local rowFrame = rowInfo.row
								local cb = rowFrame.Checkbox or rowFrame.CheckBox or (rowFrame.Control and rowFrame.Control.Checkbox)
								if cb then
									if cb.SetEnabled then
										cb:SetEnabled(not shouldDisable)
									end
									-- Gray out the label when disabled
									if rowFrame.Text and rowFrame.Text.SetTextColor then
										if shouldDisable then
											rowFrame.Text:SetTextColor(0.5, 0.5, 0.5, 1)
										else
											rowFrame.Text:SetTextColor(1, 1, 1, 1)
										end
									end
									if cb.Text and cb.Text.SetTextColor then
										if shouldDisable then
											cb.Text:SetTextColor(0.5, 0.5, 0.5, 1)
										else
											cb.Text:SetTextColor(1, 1, 1, 1)
										end
									end
								end
							end
						end
	
						local y = { y = -50 }
						local label = "Hide Power Bar"
						local function getter()
							local t = ensureUFDB()
							return t and not not t.powerBarHidden or false
						end
						local function setter(v)
							local t = ensureUFDB(); if not t then return end
							t.powerBarHidden = (v and true) or false
							applyNow()
							updateVisualCheckboxState()
						end
	
						local setting = CreateLocalSetting(label, "boolean", getter, setter, getter())
						local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = label, setting = setting, options = {} })
						local row = CreateFrame("Frame", nil, frame.PageE, "SettingsCheckboxControlTemplate")
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

						-- Hide the Bar but not its Text checkbox (number-only display)
						local texOnlyLabel = "Hide the Bar but not its Text"
						local function texOnlyGetter()
							local t = ensureUFDB()
							return t and not not t.powerBarHideTextureOnly or false
						end
						local function texOnlySetter(v)
							local t = ensureUFDB(); if not t then return end
							t.powerBarHideTextureOnly = (v and true) or false
							applyNow()
							updateVisualCheckboxState()
						end

						local texOnlySetting = CreateLocalSetting(texOnlyLabel, "boolean", texOnlyGetter, texOnlySetter, texOnlyGetter())
						local texOnlyInit = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = texOnlyLabel, setting = texOnlySetting, options = {} })
						local texOnlyRow = CreateFrame("Frame", nil, frame.PageE, "SettingsCheckboxControlTemplate")
						texOnlyRow.GetElementData = function() return texOnlyInit end
						texOnlyRow:SetPoint("TOPLEFT", 4, y.y)
						texOnlyRow:SetPoint("TOPRIGHT", -16, y.y)
						texOnlyInit:InitFrame(texOnlyRow)
						if panel and panel.ApplyRobotoWhite then
							if texOnlyRow.Text then panel.ApplyRobotoWhite(texOnlyRow.Text) end
							local texCb = texOnlyRow.Checkbox or texOnlyRow.CheckBox or (texOnlyRow.Control and texOnlyRow.Control.Checkbox)
							if texCb and texCb.Text then panel.ApplyRobotoWhite(texCb.Text) end
							-- Theme the checkbox checkmark to green
							if texCb and panel.ThemeCheckbox then panel.ThemeCheckbox(texCb) end
						end

						-- Add info icon tooltip to the left of the label
						if panel and panel.CreateInfoIconForLabel then
							local texOnlyTooltip = "Used for having a number-only display of your Power Bar resource, just like the good old WeakAuras days."
							local texOnlyTargetLabel = texOnlyRow.Text or (texOnlyRow.Checkbox and texOnlyRow.Checkbox.Text)
							if texOnlyTargetLabel and not texOnlyRow.ScooterTexOnlyInfoIcon then
								texOnlyRow.ScooterTexOnlyInfoIcon = panel.CreateInfoIconForLabel(texOnlyTargetLabel, texOnlyTooltip, 5, 0, 32)
								if texOnlyRow.ScooterTexOnlyInfoIcon then
									local function repositionTexOnly()
										local icon = texOnlyRow.ScooterTexOnlyInfoIcon
										local lbl = texOnlyRow.Text or (texOnlyRow.Checkbox and texOnlyRow.Checkbox.Text)
										if icon and lbl then
											icon:ClearAllPoints()
											icon:SetPoint("RIGHT", lbl, "LEFT", -6, 0)
										end
									end
									if C_Timer and C_Timer.After then
										C_Timer.After(0, repositionTexOnly)
									else
										repositionTexOnly()
									end
								end
							end
						end

						y.y = y.y - 34
	
	                    if componentId == "ufPlayer" then
	                        local spikeLabel = "Hide Full Bar Animations"
							local function spikeGetter()
								local t = ensureUFDB()
								return t and not not t.powerBarHideFullSpikes or false
							end
							local function spikeSetter(v)
								local t = ensureUFDB(); if not t then return end
								t.powerBarHideFullSpikes = (v and true) or false
								applyNow()
							end
	
							local spikeSetting = CreateLocalSetting(spikeLabel, "boolean", spikeGetter, spikeSetter, spikeGetter())
							local spikeInit = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = spikeLabel, setting = spikeSetting, options = {} })
							local spikeRow = CreateFrame("Frame", nil, frame.PageE, "SettingsCheckboxControlTemplate")
							spikeRow.GetElementData = function() return spikeInit end
							spikeRow:SetPoint("TOPLEFT", 4, y.y)
							spikeRow:SetPoint("TOPRIGHT", -16, y.y)
	                        spikeInit:InitFrame(spikeRow)
	                        if panel and panel.ApplyRobotoWhite then
	                            if spikeRow.Text then panel.ApplyRobotoWhite(spikeRow.Text) end
	                            local cb = spikeRow.Checkbox or spikeRow.CheckBox or (spikeRow.Control and spikeRow.Control.Checkbox)
	                            if cb and cb.Text then panel.ApplyRobotoWhite(cb.Text) end
	                            -- Theme the checkbox checkmark to green
	                            if cb and panel.ThemeCheckbox then panel.ThemeCheckbox(cb) end
	                        end
	
	                        if panel and panel.CreateInfoIconForLabel then
	                            local tooltipText = "Disables Blizzard's full-bar celebration animations that play when the resource is full. These overlays can't be resized, so hiding them keeps custom bar heights consistent."
	                            local targetLabel = spikeRow.Text or (spikeRow.Checkbox and spikeRow.Checkbox.Text)
	                            if targetLabel and not spikeRow.ScooterFullBarAnimInfoIcon then
	                                spikeRow.ScooterFullBarAnimInfoIcon = panel.CreateInfoIconForLabel(targetLabel, tooltipText, 5, 0, 32)
	                                if spikeRow.ScooterFullBarAnimInfoIcon then
	                                    local function reposition()
	                                        local icon = spikeRow.ScooterFullBarAnimInfoIcon
	                                        local lbl = spikeRow.Text or (spikeRow.Checkbox and spikeRow.Checkbox.Text)
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

							-- Register for disable state management
							table.insert(visualCheckboxRows, { row = spikeRow })

							y.y = y.y - 34
	
	                        -- Hide Power Feedback checkbox (Player only)
	                        local feedbackLabel = "Hide Power Feedback"
	                        local function feedbackGetter()
	                            local t = ensureUFDB()
	                            return t and not not t.powerBarHideFeedback or false
	                        end
	                        local function feedbackSetter(v)
	                            local t = ensureUFDB(); if not t then return end
	                            t.powerBarHideFeedback = (v and true) or false
	                            applyNow()
	                        end
	
	                        local feedbackSetting = CreateLocalSetting(feedbackLabel, "boolean", feedbackGetter, feedbackSetter, feedbackGetter())
	                        local feedbackInit = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = feedbackLabel, setting = feedbackSetting, options = {} })
	                        local feedbackRow = CreateFrame("Frame", nil, frame.PageE, "SettingsCheckboxControlTemplate")
	                        feedbackRow.GetElementData = function() return feedbackInit end
	                        feedbackRow:SetPoint("TOPLEFT", 4, y.y)
	                        feedbackRow:SetPoint("TOPRIGHT", -16, y.y)
	                        feedbackInit:InitFrame(feedbackRow)
	                        if panel and panel.ApplyRobotoWhite then
	                            if feedbackRow.Text then panel.ApplyRobotoWhite(feedbackRow.Text) end
	                            local cb = feedbackRow.Checkbox or feedbackRow.CheckBox or (feedbackRow.Control and feedbackRow.Control.Checkbox)
	                            if cb and cb.Text then panel.ApplyRobotoWhite(cb.Text) end
	                            -- Theme the checkbox checkmark to green
	                            if cb and panel.ThemeCheckbox then panel.ThemeCheckbox(cb) end
	                        end
	
	                        if panel and panel.CreateInfoIconForLabel then
	                            local feedbackTooltip = "Disables the flash animation that plays when you spend or gain power (energy, mana, rage, etc.). This animation shows a quick highlight on the portion of the bar that changed."
	                            local feedbackTargetLabel = feedbackRow.Text or (feedbackRow.Checkbox and feedbackRow.Checkbox.Text)
	                            if feedbackTargetLabel and not feedbackRow.ScooterPowerFeedbackInfoIcon then
	                                feedbackRow.ScooterPowerFeedbackInfoIcon = panel.CreateInfoIconForLabel(feedbackTargetLabel, feedbackTooltip, 5, 0, 32)
	                                if feedbackRow.ScooterPowerFeedbackInfoIcon then
	                                    local function repositionFeedback()
	                                        local icon = feedbackRow.ScooterPowerFeedbackInfoIcon
	                                        local lbl = feedbackRow.Text or (feedbackRow.Checkbox and feedbackRow.Checkbox.Text)
	                                        if icon and lbl then
	                                            icon:ClearAllPoints()
	                                            icon:SetPoint("RIGHT", lbl, "LEFT", -6, 0)
	                                        end
	                                    end
	                                    if C_Timer and C_Timer.After then
	                                        C_Timer.After(0, repositionFeedback)
	                                    else
	                                        repositionFeedback()
	                                    end
	                                end
	                            end
	                        end

							-- Register for disable state management
							table.insert(visualCheckboxRows, { row = feedbackRow })
	
	                        y.y = y.y - 34
	
	                        -- Hide Power Bar Spark checkbox (Player only)
	                        local sparkLabel = "Hide Power Bar Spark"
	                        local function sparkGetter()
	                            local t = ensureUFDB()
	                            return t and not not t.powerBarHideSpark or false
	                        end
	                        local function sparkSetter(v)
	                            local t = ensureUFDB(); if not t then return end
	                            t.powerBarHideSpark = (v and true) or false
	                            applyNow()
	                        end
	
	                        local sparkSetting = CreateLocalSetting(sparkLabel, "boolean", sparkGetter, sparkSetter, sparkGetter())
	                        local sparkInit = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = sparkLabel, setting = sparkSetting, options = {} })
	                        local sparkRow = CreateFrame("Frame", nil, frame.PageE, "SettingsCheckboxControlTemplate")
	                        sparkRow.GetElementData = function() return sparkInit end
	                        sparkRow:SetPoint("TOPLEFT", 4, y.y)
	                        sparkRow:SetPoint("TOPRIGHT", -16, y.y)
	                        sparkInit:InitFrame(sparkRow)
	                        if panel and panel.ApplyRobotoWhite then
	                            if sparkRow.Text then panel.ApplyRobotoWhite(sparkRow.Text) end
	                            local cb = sparkRow.Checkbox or sparkRow.CheckBox or (sparkRow.Control and sparkRow.Control.Checkbox)
	                            if cb and cb.Text then panel.ApplyRobotoWhite(cb.Text) end
	                            -- Theme the checkbox checkmark to green
	                            if cb and panel.ThemeCheckbox then panel.ThemeCheckbox(cb) end
	                        end
	
	                        if panel and panel.CreateInfoIconForLabel then
	                            local sparkTooltip = "Hides the spark/glow indicator that appears at the current power level on certain classes (e.g., Elemental Shaman)."
	                            local sparkTargetLabel = sparkRow.Text or (sparkRow.Checkbox and sparkRow.Checkbox.Text)
	                            if sparkTargetLabel and not sparkRow.ScooterPowerSparkInfoIcon then
	                                sparkRow.ScooterPowerSparkInfoIcon = panel.CreateInfoIconForLabel(sparkTargetLabel, sparkTooltip, 5, 0, 32)
	                                if sparkRow.ScooterPowerSparkInfoIcon then
	                                    local function repositionSpark()
	                                        local icon = sparkRow.ScooterPowerSparkInfoIcon
	                                        local lbl = sparkRow.Text or (sparkRow.Checkbox and sparkRow.Checkbox.Text)
	                                        if icon and lbl then
	                                            icon:ClearAllPoints()
	                                            icon:SetPoint("RIGHT", lbl, "LEFT", -6, 0)
	                                        end
	                                    end
	                                    if C_Timer and C_Timer.After then
	                                        C_Timer.After(0, repositionSpark)
	                                    else
	                                        repositionSpark()
	                                    end
	                                end
	                            end
	                        end

							-- Register for disable state management
							table.insert(visualCheckboxRows, { row = sparkRow })

							-- Apply initial disabled state for all 3 visual checkboxes
							updateVisualCheckboxState()

	                        y.y = y.y - 34
						end
					end

					-- PageF: % Text (Power Percent)
					do
						local function applyNow()
							if addon and addon.ApplyUnitFramePowerTextVisibilityFor then addon.ApplyUnitFramePowerTextVisibilityFor(unitKey()) end
							if addon and addon.ApplyStyles then addon:ApplyStyles() end
						end
						local function fontOptions()
							return addon.BuildFontOptionsContainer()
						end
						local y = { y = -50 }
						local label = "Disable % Text"
						local function getter()
							local t = ensureUFDB(); return t and not not t.powerPercentHidden or false
						end
						local function setter(v)
							local t = ensureUFDB(); if not t then return end
							t.powerPercentHidden = (v and true) or false
							applyNow()
						end
						local setting = CreateLocalSetting(label, "boolean", getter, setter, getter())
						local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = label, setting = setting, options = {} })
						local row = CreateFrame("Frame", nil, frame.PageF, "SettingsCheckboxControlTemplate")
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
						addDropdown(frame.PageF, "% Text Font", fontOptions,
							function() local t = ensureUFDB() or {}; local s = t.textPowerPercent or {}; return s.fontFace or "FRIZQT__" end,
							function(v) local t = ensureUFDB(); if not t then return end; t.textPowerPercent = t.textPowerPercent or {}; t.textPowerPercent.fontFace = v; applyNow() end,
							y)
						addStyle(frame.PageF, "% Text Style",
							function() local t = ensureUFDB() or {}; local s = t.textPowerPercent or {}; return s.style or "OUTLINE" end,
							function(v) local t = ensureUFDB(); if not t then return end; t.textPowerPercent = t.textPowerPercent or {}; t.textPowerPercent.style = v; applyNow() end,
							y)
						addSlider(frame.PageF, "% Text Size", 6, 48, 1,
							function() local t = ensureUFDB() or {}; local s = t.textPowerPercent or {}; return tonumber(s.size) or 14 end,
							function(v) local t = ensureUFDB(); if not t then return end; t.textPowerPercent = t.textPowerPercent or {}; t.textPowerPercent.size = tonumber(v) or 14; applyNow() end,
							y)
						-- % Text Color: DropdownWithInlineSwatch with Default/Class Power Color/Custom options
						do
							local function colorOpts()
								local c = Settings.CreateControlTextContainer()
								c:Add("default", "Default")
								c:Add("classPower", "Class Power Color")
								c:Add("custom", "Custom")
								return c:GetData()
							end
							local function getMode()
								local t = ensureUFDB() or {}; local s = t.textPowerPercent or {}
								return s.colorMode or "default"
							end
							local function setMode(v)
								local t = ensureUFDB(); if not t then return end
								t.textPowerPercent = t.textPowerPercent or {}
								t.textPowerPercent.colorMode = v or "default"
								applyNow()
							end
							local function getColorTbl()
								local t = ensureUFDB() or {}; local s = t.textPowerPercent or {}; local c = s.color or {1,1,1,1}
								return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
							end
							local function setColorTbl(r,g,b,a)
								local t = ensureUFDB(); if not t then return end
								t.textPowerPercent = t.textPowerPercent or {}
								t.textPowerPercent.color = { r or 1, g or 1, b or 1, a or 1 }
								applyNow()
							end
							panel.DropdownWithInlineSwatch(frame.PageF, y, {
								label = "% Text Color",
								getMode = getMode,
								setMode = setMode,
								getColor = getColorTbl,
								setColor = setColorTbl,
								options = colorOpts,
								insideButton = true,
							})
						end
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
								local t = ensureUFDB() or {}; local s = t.textPowerPercent or {}; return s.alignment or "LEFT"
							end
							local function setAlign(v)
								local t = ensureUFDB(); if not t then return end
								t.textPowerPercent = t.textPowerPercent or {}
								t.textPowerPercent.alignment = v or "LEFT"
								applyNow()
							end
							local setting = CreateLocalSetting("% Text Alignment", "string", getAlign, setAlign, getAlign())
							local initDrop = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", { name = "% Text Alignment", setting = setting, options = alignOpts })
							local f = CreateFrame("Frame", nil, frame.PageF, "SettingsDropdownControlTemplate")
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
						addSlider(frame.PageF, "% Text Offset X", -100, 100, 1,
							function() local t = ensureUFDB() or {}; local s = t.textPowerPercent or {}; local o = s.offset or {}; return tonumber(o.x) or 0 end,
							function(v) local t = ensureUFDB(); if not t then return end; t.textPowerPercent = t.textPowerPercent or {}; t.textPowerPercent.offset = t.textPowerPercent.offset or {}; t.textPowerPercent.offset.x = tonumber(v) or 0; applyNow() end,
							y)
						addSlider(frame.PageF, "% Text Offset Y", -100, 100, 1,
							function() local t = ensureUFDB() or {}; local s = t.textPowerPercent or {}; local o = s.offset or {}; return tonumber(o.y) or 0 end,
							function(v) local t = ensureUFDB(); if not t then return end; t.textPowerPercent = t.textPowerPercent or {}; t.textPowerPercent.offset = t.textPowerPercent.offset or {}; t.textPowerPercent.offset.y = tonumber(v) or 0; applyNow() end,
							y)
					end
	
					-- PageG: Value Text (Power Value / RightText). May be a no-op on classes without a separate value element.
					do
						local function applyNow()
							if addon and addon.ApplyUnitFramePowerTextVisibilityFor then addon.ApplyUnitFramePowerTextVisibilityFor(unitKey()) end
							if addon and addon.ApplyStyles then addon:ApplyStyles() end
						end
						local function fontOptions()
							return addon.BuildFontOptionsContainer()
						end
						local y = { y = -50 }
						local label = "Disable Value Text"
						local function getter()
							local t = ensureUFDB(); return t and not not t.powerValueHidden or false
						end
						local function setter(v)
							local t = ensureUFDB(); if not t then return end
							t.powerValueHidden = (v and true) or false
							applyNow()
						end
						local setting = CreateLocalSetting(label, "boolean", getter, setter, getter())
						local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = label, setting = setting, options = {} })
						local row = CreateFrame("Frame", nil, frame.PageG, "SettingsCheckboxControlTemplate")
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
						addDropdown(frame.PageG, "Value Text Font", fontOptions,
							function() local t = ensureUFDB() or {}; local s = t.textPowerValue or {}; return s.fontFace or "FRIZQT__" end,
							function(v) local t = ensureUFDB(); if not t then return end; t.textPowerValue = t.textPowerValue or {}; t.textPowerValue.fontFace = v; applyNow() end,
							y)
						addStyle(frame.PageG, "Value Text Style",
							function() local t = ensureUFDB() or {}; local s = t.textPowerValue or {}; return s.style or "OUTLINE" end,
							function(v) local t = ensureUFDB(); if not t then return end; t.textPowerValue = t.textPowerValue or {}; t.textPowerValue.style = v; applyNow() end,
							y)
						addSlider(frame.PageG, "Value Text Size", 6, 48, 1,
							function() local t = ensureUFDB() or {}; local s = t.textPowerValue or {}; return tonumber(s.size) or 14 end,
							function(v) local t = ensureUFDB(); if not t then return end; t.textPowerValue = t.textPowerValue or {}; t.textPowerValue.size = tonumber(v) or 14; applyNow() end,
							y)
						-- Value Text Color: DropdownWithInlineSwatch with Default/Class Power Color/Custom options
						do
							local function colorOpts()
								local c = Settings.CreateControlTextContainer()
								c:Add("default", "Default")
								c:Add("classPower", "Class Power Color")
								c:Add("custom", "Custom")
								return c:GetData()
							end
							local function getMode()
								local t = ensureUFDB() or {}; local s = t.textPowerValue or {}
								return s.colorMode or "default"
							end
							local function setMode(v)
								local t = ensureUFDB(); if not t then return end
								t.textPowerValue = t.textPowerValue or {}
								t.textPowerValue.colorMode = v or "default"
								applyNow()
							end
							local function getColorTbl()
								local t = ensureUFDB() or {}; local s = t.textPowerValue or {}; local c = s.color or {1,1,1,1}
								return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
							end
							local function setColorTbl(r,g,b,a)
								local t = ensureUFDB(); if not t then return end
								t.textPowerValue = t.textPowerValue or {}
								t.textPowerValue.color = { r or 1, g or 1, b or 1, a or 1 }
								applyNow()
							end
							panel.DropdownWithInlineSwatch(frame.PageG, y, {
								label = "Value Text Color",
								getMode = getMode,
								setMode = setMode,
								getColor = getColorTbl,
								setColor = setColorTbl,
								options = colorOpts,
								insideButton = true,
							})
						end
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
								local t = ensureUFDB() or {}; local s = t.textPowerValue or {}; return s.alignment or "RIGHT"
							end
							local function setAlign(v)
								local t = ensureUFDB(); if not t then return end
								t.textPowerValue = t.textPowerValue or {}
								t.textPowerValue.alignment = v or "RIGHT"
								applyNow()
							end
							local setting = CreateLocalSetting("Value Text Alignment", "string", getAlign, setAlign, getAlign())
							local initDrop = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", { name = "Value Text Alignment", setting = setting, options = alignOpts })
							local f = CreateFrame("Frame", nil, frame.PageG, "SettingsDropdownControlTemplate")
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
						addSlider(frame.PageG, "Value Text Offset X", -100, 100, 1,
							function() local t = ensureUFDB() or {}; local s = t.textPowerValue or {}; local o = s.offset or {}; return tonumber(o.x) or 0 end,
							function(v) local t = ensureUFDB(); if not t then return end; t.textPowerValue = t.textPowerValue or {}; t.textPowerValue.offset = t.textPowerValue.offset or {}; t.textPowerValue.offset.x = tonumber(v) or 0; applyNow() end,
							y)
						addSlider(frame.PageG, "Value Text Offset Y", -100, 100, 1,
							function() local t = ensureUFDB() or {}; local s = t.textPowerValue or {}; local o = s.offset or {}; return tonumber(o.y) or 0 end,
							function(v) local t = ensureUFDB(); if not t then return end; t.textPowerValue = t.textPowerValue or {}; t.textPowerValue.offset = t.textPowerValue.offset or {}; t.textPowerValue.offset.y = tonumber(v) or 0; applyNow() end,
							y)
					end
	
	                -- PageC: Foreground/Background Texture + Color (Power Bar)
					do
						local function applyNow()
							if addon and addon.ApplyStyles then addon:ApplyStyles() end
						end
						local y = { y = -50 }
						-- Foreground Texture dropdown
						local function opts() return addon.BuildBarTextureOptionsContainer() end
						local function getTex() local t = ensureUFDB() or {}; return t.powerBarTexture or "default" end
						local function setTex(v) local t = ensureUFDB(); if not t then return end; t.powerBarTexture = v; applyNow() end
						local texSetting = CreateLocalSetting("Foreground Texture", "string", getTex, setTex, getTex())
						local initDrop = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", { name = "Foreground Texture", setting = texSetting, options = opts })
						local f = CreateFrame("Frame", nil, frame.PageC, "SettingsDropdownControlTemplate")
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
	                        container:Add("custom", "Custom")
							return container:GetData()
						end
						local function getColorMode() local t = ensureUFDB() or {}; return t.powerBarColorMode or "default" end
						local function setColorMode(v)
							local t = ensureUFDB(); if not t then return end; t.powerBarColorMode = v or "default"; applyNow()
						end
						local function getTintTbl()
							local t = ensureUFDB() or {}; local c = t.powerBarTint or {1,1,1,1}; return { c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 }
						end
						local function setTintTbl(r,g,b,a)
							local t = ensureUFDB(); if not t then return end; t.powerBarTint = { r or 1, g or 1, b or 1, a or 1 }; applyNow()
						end
						panel.DropdownWithInlineSwatch(frame.PageC, y, {
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
							local spacer = CreateFrame("Frame", nil, frame.PageC, "SettingsListElementTemplate")
							spacer:SetHeight(20)
							spacer:SetPoint("TOPLEFT", 4, y.y)
							spacer:SetPoint("TOPRIGHT", -16, y.y)
							if spacer.Text then
								spacer.Text:SetText("")
							end
							y.y = y.y - 24
						end
	
						-- Background Texture dropdown
						local function getBgTex() local t = ensureUFDB() or {}; return t.powerBarBackgroundTexture or "default" end
						local function setBgTex(v) local t = ensureUFDB(); if not t then return end; t.powerBarBackgroundTexture = v; applyNow() end
						local bgTexSetting = CreateLocalSetting("Background Texture", "string", getBgTex, setBgTex, getBgTex())
						local initBgDrop = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", { name = "Background Texture", setting = bgTexSetting, options = opts })
						local fbg = CreateFrame("Frame", nil, frame.PageC, "SettingsDropdownControlTemplate")
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
						local function getBgColorMode() local t = ensureUFDB() or {}; return t.powerBarBackgroundColorMode or "default" end
						local function setBgColorMode(v)
							local t = ensureUFDB(); if not t then return end; t.powerBarBackgroundColorMode = v or "default"; applyNow()
						end
						local function getBgTintTbl()
							local t = ensureUFDB() or {}; local c = t.powerBarBackgroundTint or {0,0,0,1}; return { c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1 }
						end
						local function setBgTintTbl(r,g,b,a)
							local t = ensureUFDB(); if not t then return end; t.powerBarBackgroundTint = { r or 0, g or 0, b or 0, a or 1 }; applyNow()
						end
						panel.DropdownWithInlineSwatch(frame.PageC, y, {
							label = "Background Color",
							getMode = getBgColorMode,
							setMode = setBgColorMode,
							getColor = getBgTintTbl,
							setColor = setBgTintTbl,
							options = bgColorOpts,
							insideButton = true,
						})
	
						-- Background Opacity slider
						local function getBgOpacity() local t = ensureUFDB() or {}; return t.powerBarBackgroundOpacity or 50 end
						local function setBgOpacity(v) local t = ensureUFDB(); if not t then return end; t.powerBarBackgroundOpacity = tonumber(v) or 50; applyNow() end
						local bgOpacitySetting = CreateLocalSetting("Background Opacity", "number", getBgOpacity, setBgOpacity, getBgOpacity())
						local bgOpacityOpts = Settings.CreateSliderOptions(0, 100, 1)
						bgOpacityOpts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return tostring(math.floor(v + 0.5)) end)
						local bgOpacityInit = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = "Background Opacity", setting = bgOpacitySetting, options = bgOpacityOpts })
						local fOpa = CreateFrame("Frame", nil, frame.PageC, "SettingsSliderControlTemplate")
						fOpa.GetElementData = function() return bgOpacityInit end
						fOpa:SetPoint("TOPLEFT", 4, y.y)
						fOpa:SetPoint("TOPRIGHT", -16, y.y)
						bgOpacityInit:InitFrame(fOpa)
						if panel and panel.ApplyControlTheme then panel.ApplyControlTheme(fOpa) end
						if panel and panel.ApplyRobotoWhite and fOpa.Text then panel.ApplyRobotoWhite(fOpa.Text) end
						y.y = y.y - 48
					end
	
	                -- PageD: Border (Power Bar)
	                do
	                    local y = { y = -50 }
	                    local function optionsBorder()
	                        local c = Settings.CreateControlTextContainer()
	                        c:Add("none", "None")
	                        if addon and addon.BuildBarBorderOptionsContainer then
	                            local base = addon.BuildBarBorderOptionsContainer()
	                            if type(base) == "table" then
	                                for _, entry in ipairs(base) do
	                                    if entry and entry.value and entry.text then
	                                        c:Add(entry.value, entry.text)
	                                    end
	                                end
	                            end
	                        else
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
	                        local t = ensureUFDB() or {}; return t.powerBarBorderStyle or "square"
	                    end
	                    local function setStyle(v)
	                        local t = ensureUFDB(); if not t then return end
	                        t.powerBarBorderStyle = v or "square"
	                        applyNow()
	                    end
	                    local styleSetting = CreateLocalSetting("Border Style", "string", getStyle, setStyle, getStyle())
	                    local initDrop = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", { name = "Border Style", setting = styleSetting, options = optionsBorder })
	                    local f = CreateFrame("Frame", nil, frame.PageD, "SettingsDropdownControlTemplate")
	                    f.GetElementData = function() return initDrop end
	                    f:SetPoint("TOPLEFT", 4, y.y)
	                    f:SetPoint("TOPRIGHT", -16, y.y)
	                    initDrop:InitFrame(f)
	                    local lbl = f and (f.Text or f.Label)
	                    if lbl and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(lbl) end
	                    if f.Control and panel.ThemeDropdownWithSteppers then panel.ThemeDropdownWithSteppers(f.Control) end
	                    local enabled = isEnabled()
	                    if f.Control and f.Control.SetEnabled then f.Control:SetEnabled(enabled) end
	                    if lbl and lbl.SetTextColor then
	                        if enabled then lbl:SetTextColor(1, 1, 1, 1) else lbl:SetTextColor(0.6, 0.6, 0.6, 1) end
	                    end
	                    y.y = y.y - 34
	
	                    -- Border Tint (checkbox + swatch)
	                    do
	                        local function getTintEnabled()
	                            local t = ensureUFDB() or {}; return not not t.powerBarBorderTintEnable
	                        end
	                        local function setTintEnabled(b)
	                            local t = ensureUFDB(); if not t then return end
	                            t.powerBarBorderTintEnable = not not b
	                            applyNow()
	                        end
	                        local function getTint()
	                            local t = ensureUFDB() or {}
	                            local c = t.powerBarBorderTintColor or {1,1,1,1}
	                            return { c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 }
	                        end
	                        local function setTint(r, g, b, a)
	                            local t = ensureUFDB(); if not t then return end
	                            t.powerBarBorderTintColor = { r or 1, g or 1, b or 1, a or 1 }
	                            applyNow()
	                        end
	                        local tintSetting = CreateLocalSetting("Border Tint", "boolean", getTintEnabled, setTintEnabled, getTintEnabled())
	                        local initCb = CreateCheckboxWithSwatchInitializer(tintSetting, "Border Tint", getTint, setTint, 8)
	                        local row = CreateFrame("Frame", nil, frame.PageD, "SettingsCheckboxControlTemplate")
	                        row.GetElementData = function() return initCb end
	                        row:SetPoint("TOPLEFT", 4, y.y)
	                        row:SetPoint("TOPRIGHT", -16, y.y)
	                        initCb:InitFrame(row)
	                        local enabled2 = isEnabled()
	                        local ctrl = row.Checkbox or row.CheckBox or (row.Control and row.Control.Checkbox) or row.Control
	                        if ctrl and ctrl.SetEnabled then ctrl:SetEnabled(enabled2) end
	                        if row.ScooterInlineSwatch and row.ScooterInlineSwatch.EnableMouse then
	                            row.ScooterInlineSwatch:EnableMouse(enabled2)
	                            if row.ScooterInlineSwatch.SetAlpha then row.ScooterInlineSwatch:SetAlpha(enabled2 and 1 or 0.5) end
	                        end
	                        local labelFS = (ctrl and ctrl.Text) or row.Text
	                        if labelFS and labelFS.SetTextColor then
	                            if enabled2 then labelFS:SetTextColor(1, 1, 1, 1) else labelFS:SetTextColor(0.6, 0.6, 0.6, 1) end
	                        end
	                        y.y = y.y - 34
	                    end
	
	                    -- Border Thickness
	                    do
	                        local function getThk()
	                            local t = ensureUFDB() or {}; return tonumber(t.powerBarBorderThickness) or 1
	                        end
	                        local function setThk(v)
	                            local t = ensureUFDB(); if not t then return end
	                            local nv = tonumber(v) or 1
	                            if nv < 1 then nv = 1 elseif nv > 8 then nv = 8 end
	                            t.powerBarBorderThickness = nv
	                            applyNow()
	                        end
	                        local opts = Settings.CreateSliderOptions(1, 8, 0.2)
	                        opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return string.format("%.1f", v) end)
	                        local thkSetting = CreateLocalSetting("Border Thickness", "number", getThk, setThk, getThk())
	                        local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = "Border Thickness", setting = thkSetting, options = opts })
	                        local sf = CreateFrame("Frame", nil, frame.PageD, "SettingsSliderControlTemplate")
	                        sf.GetElementData = function() return initSlider end
	                        sf:SetPoint("TOPLEFT", 4, y.y)
	                        sf:SetPoint("TOPRIGHT", -16, y.y)
	                        initSlider:InitFrame(sf)
	                        if sf.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(sf.Text) end
	                        if panel and panel.ThemeSliderValue then panel.ThemeSliderValue(sf) end
	                        local enabled3 = isEnabled()
	                        if sf.Control and sf.Control.SetEnabled then sf.Control:SetEnabled(enabled3) end
	                        if sf.Text and sf.Text.SetTextColor then
	                            if enabled3 then sf.Text:SetTextColor(1, 1, 1, 1) else sf.Text:SetTextColor(0.6, 0.6, 0.6, 1) end
	                        end
	                        y.y = y.y - 34
	                    end
	
	                    -- Border Inset
	                    do
	                        local function getInset()
	                            local t = ensureUFDB() or {}; return tonumber(t.powerBarBorderInset) or 0
	                        end
	                        local function setInset(v)
	                            local t = ensureUFDB(); if not t then return end
	                            local nv = tonumber(v) or 0
	                            if nv < -4 then nv = -4 elseif nv > 4 then nv = 4 end
	                            t.powerBarBorderInset = nv
	                            applyNow()
	                        end
	                        local opts = Settings.CreateSliderOptions(-4, 4, 1)
	                        opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return tostring(math.floor(v)) end)
	                        local insetSetting = CreateLocalSetting("Border Inset", "number", getInset, setInset, getInset())
	                        local sf = CreateFrame("Frame", nil, frame.PageD, "SettingsSliderControlTemplate")
	                        local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = "Border Inset", setting = insetSetting, options = opts })
	                        sf.GetElementData = function() return initSlider end
	                        sf:SetPoint("TOPLEFT", 4, y.y)
	                        sf:SetPoint("TOPRIGHT", -16, y.y)
	                        initSlider:InitFrame(sf)
	                        if sf.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(sf.Text) end
	                        if panel and panel.ThemeSliderValue then panel.ThemeSliderValue(sf) end
	                        local enabled4 = isEnabled()
	                        if sf.Control and sf.Control.SetEnabled then sf.Control:SetEnabled(enabled4) end
	                        if sf.Text and sf.Text.SetTextColor then
	                            if enabled4 then sf.Text:SetTextColor(1, 1, 1, 1) else sf.Text:SetTextColor(0.6, 0.6, 0.6, 1) end
	                        end
	                        y.y = y.y - 34
	                    end
	                end
	
					-- Apply current visibility once when building
					if addon and addon.ApplyUnitFramePowerTextVisibilityFor then addon.ApplyUnitFramePowerTextVisibilityFor(unitKey()) end
				end
	
				local pbInit = Settings.CreateElementInitializer("ScooterTabbedSectionTemplate", pbTabs)
				-- STATIC HEIGHT for tabbed sections with up to 8 settings per tab.
				-- Current: 364px provides comfortable spacing for 8 controls (including alignment dropdown).
				-- DO NOT reduce below 350px or settings will bleed past the bottom border.
				pbInit.GetExtent = function() return 364 end
				pbInit:AddShownPredicate(function()
					return panel:IsSectionExpanded(componentId, "Power Bar")
				end)
				table.insert(init, pbInit)
	
				-- Optional fourth collapsible section: Alternate Power Bar (Player-only, class/spec gated)
				if componentId == "ufPlayer" and addon and addon.UnitFrames_PlayerHasAlternatePowerBar and addon.UnitFrames_PlayerHasAlternatePowerBar() then
					local expInitializerAPB = Settings.CreateElementInitializer("ScooterExpandableSectionTemplate", {
						name = "Alternate Power Bar",
						sectionKey = "Alternate Power Bar",
						componentId = componentId,
						expanded = panel:IsSectionExpanded(componentId, "Alternate Power Bar"),
					})
					expInitializerAPB.GetExtent = function() return 30 end
					table.insert(init, expInitializerAPB)
	
					-- Alternate Power Bar tabs (mirrors Power Bar: Positioning, Sizing, Style, Border, Visibility, % Text, Value Text)
					local apbTabs = {
						sectionTitle = "",
						tabAText = "Positioning",
						tabBText = "Sizing",
						tabCText = "Style",
						tabDText = "Border",
						tabEText = "Visibility",
						tabFText = "% Text",
						tabGText = "Value Text",
					}
					apbTabs.build = function(frame)
						-- This section is Player-only.
						local function unitKey()
							return "Player"
						end
						local function ensureUFDB()
							local db = addon and addon.db and addon.db.profile
							if not db then return nil end
							db.unitFrames = db.unitFrames or {}
							db.unitFrames.Player = db.unitFrames.Player or {}
							db.unitFrames.Player.altPowerBar = db.unitFrames.Player.altPowerBar or {}
							return db.unitFrames.Player.altPowerBar
						end
	
						-- Font options provider for % Text / Value Text dropdowns.
						local function fontOptions()
							if addon and addon.BuildFontOptionsContainer then
								return addon.BuildFontOptionsContainer()
							end
							-- Fallback: minimal container when font helper is missing
							local container = Settings.CreateControlTextContainer()
							container:Add("FRIZQT__", "FRIZQT__")
							return container:GetData()
						end
	
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
							return f
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
							return addDropdown(parent, label, styleOptions, getFunc, setFunc, yRef)
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
							return f
						end
	
						-- PageA: Positioning (Alternate Power Bar)
						do
							local function applyNow()
								if addon and addon.ApplyStyles then addon:ApplyStyles() end
							end
							local y = { y = -50 }
	
							addSlider(frame.PageA, "X Offset", -100, 100, 1,
								function() local t = ensureUFDB() or {}; return tonumber(t.offsetX) or 0 end,
								function(v) local t = ensureUFDB(); if not t then return end; t.offsetX = tonumber(v) or 0; applyNow() end,
								y)
							addSlider(frame.PageA, "Y Offset", -100, 100, 1,
								function() local t = ensureUFDB() or {}; return tonumber(t.offsetY) or 0 end,
								function(v) local t = ensureUFDB(); if not t then return end; t.offsetY = tonumber(v) or 0; applyNow() end,
								y)
						end
	
						-- PageB: Sizing (Alternate Power Bar) – width/height scaling
						-- NOTE: Height max capped at 100 (default) because growing above default causes
						-- animation artifacts in combat. Shrinking below default is supported. See UNITFRAMES.md.
						do
							local function applyNow()
								if addon and addon.ApplyStyles then addon:ApplyStyles() end
							end
							local y = { y = -50 }
	
							-- Bar Width (%)
							addSlider(frame.PageB, "Bar Width (%)", 50, 150, 1,
								function() local t = ensureUFDB() or {}; return tonumber(t.widthPct) or 100 end,
								function(v)
									local t = ensureUFDB(); if not t then return end
									local val = tonumber(v) or 100
									if val < 50 then val = 50 elseif val > 150 then val = 150 end
									t.widthPct = val
									applyNow()
								end,
								y)
	
							-- Bar Height (%)
							addSlider(frame.PageB, "Bar Height (%)", 50, 100, 1,
								function() local t = ensureUFDB() or {}; return tonumber(t.heightPct) or 100 end,
								function(v)
									local t = ensureUFDB(); if not t then return end
									local val = tonumber(v) or 100
									if val < 50 then val = 50 elseif val > 100 then val = 100 end
									t.heightPct = val
									applyNow()
								end,
								y)
						end
	
						-- PageC: Style (Alternate Power Bar foreground/background texture & color)
						do
							local function applyNow()
								if addon and addon.ApplyStyles then addon:ApplyStyles() end
							end
							local y = { y = -50 }
	
							-- Foreground Texture
							do
								local function getTex()
									local t = ensureUFDB() or {}; return t.texture or "default" end
								local function setTex(v)
									local t = ensureUFDB(); if not t then return end
									t.texture = v
									applyNow()
								end
								local texSetting = CreateLocalSetting("Foreground Texture", "string", getTex, setTex, getTex())
								local function texOptions()
									if addon.BuildBarTextureOptionsContainer then
										return addon.BuildBarTextureOptionsContainer()
									end
									local container = Settings.CreateControlTextContainer()
									container:Add("default", "Default")
									return container:GetData()
								end
								local initDrop = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", { name = "Foreground Texture", setting = texSetting, options = texOptions })
								local f = CreateFrame("Frame", nil, frame.PageC, "SettingsDropdownControlTemplate")
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
							end
	
							-- Foreground Color (Default / Texture Original / Custom)
							do
								local function colorOpts()
									local container = Settings.CreateControlTextContainer()
									container:Add("default", "Default")
									container:Add("texture", "Texture Original")
									container:Add("custom", "Custom")
									return container:GetData()
								end
								local function getMode()
									local t = ensureUFDB() or {}; return t.colorMode or "default" end
								local function setMode(v)
									local t = ensureUFDB(); if not t then return end
									t.colorMode = v or "default"
									applyNow()
								end
								local function getTint()
									local t = ensureUFDB() or {}; local c = t.tint or {1,1,1,1}
									return { c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 }
								end
								local function setTint(r,g,b,a)
									local t = ensureUFDB(); if not t then return end
									t.tint = { r or 1, g or 1, b or 1, a or 1 }
									applyNow()
								end
								panel.DropdownWithInlineSwatch(frame.PageC, y, {
									label = "Foreground Color",
									getMode = getMode,
									setMode = setMode,
									getColor = getTint,
									setColor = setTint,
									options = colorOpts,
									insideButton = true,
								})
							end
	
							-- Background Texture
							do
								local function getBgTex()
									local t = ensureUFDB() or {}; return t.backgroundTexture or "default" end
								local function setBgTex(v)
									local t = ensureUFDB(); if not t then return end
									t.backgroundTexture = v
									applyNow()
								end
								local bgSetting = CreateLocalSetting("Background Texture", "string", getBgTex, setBgTex, getBgTex())
								local function bgOptions()
									if addon.BuildBarTextureOptionsContainer then
										return addon.BuildBarTextureOptionsContainer()
									end
									local container = Settings.CreateControlTextContainer()
									container:Add("default", "Default")
									return container:GetData()
								end
								local initBg = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", { name = "Background Texture", setting = bgSetting, options = bgOptions })
								local fbg = CreateFrame("Frame", nil, frame.PageC, "SettingsDropdownControlTemplate")
								fbg.GetElementData = function() return initBg end
								fbg:SetPoint("TOPLEFT", 4, y.y)
								fbg:SetPoint("TOPRIGHT", -16, y.y)
								initBg:InitFrame(fbg)
								if panel and panel.ApplyRobotoWhite then
									local lbl = fbg and (fbg.Text or fbg.Label)
									if lbl then panel.ApplyRobotoWhite(lbl) end
								end
								if fbg.Control and panel.ThemeDropdownWithSteppers then panel.ThemeDropdownWithSteppers(fbg.Control) end
								if fbg.Control and addon.InitBarTextureDropdown then addon.InitBarTextureDropdown(fbg.Control, bgSetting) end
								y.y = y.y - 34
							end
	
							-- Background Color (Default / Texture Original / Custom)
							do
								local function bgColorOpts()
									local container = Settings.CreateControlTextContainer()
									container:Add("default", "Default")
									container:Add("texture", "Texture Original")
									container:Add("custom", "Custom")
									return container:GetData()
								end
								local function getBgMode()
									local t = ensureUFDB() or {}; return t.backgroundColorMode or "default" end
								local function setBgMode(v)
									local t = ensureUFDB(); if not t then return end
									t.backgroundColorMode = v or "default"
									applyNow()
								end
								local function getBgTint()
									local t = ensureUFDB() or {}; local c = t.backgroundTint or {0,0,0,1}
									return { c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1 }
								end
								local function setBgTint(r,g,b,a)
									local t = ensureUFDB(); if not t then return end
									t.backgroundTint = { r or 0, g or 0, b or 0, a or 1 }
									applyNow()
								end
								panel.DropdownWithInlineSwatch(frame.PageC, y, {
									label = "Background Color",
									getMode = getBgMode,
									setMode = setBgMode,
									getColor = getBgTint,
									setColor = setBgTint,
									options = bgColorOpts,
									insideButton = true,
								})
							end
	
							-- Background Opacity
							addSlider(frame.PageC, "Background Opacity", 0, 100, 1,
								function() local t = ensureUFDB() or {}; return tonumber(t.backgroundOpacity) or 50 end,
								function(v)
									local t = ensureUFDB(); if not t then return end
									local val = tonumber(v) or 50
									if val < 0 then val = 0 elseif val > 100 then val = 100 end
									t.backgroundOpacity = val
									applyNow()
								end,
								y)
						end
	
						-- PageD: Border (mirrors Power Bar border options; gated by global Use Custom Border)
						do
							local function applyNow()
								if addon and addon.ApplyStyles then addon:ApplyStyles() end
							end
							local y = { y = -50 }
	
							-- Global Unit Frame "Use Custom Borders" toggle (shares with Health/Power bars)
							local function isEnabled()
								local db = addon and addon.db and addon.db.profile
								if not db then return false end
								db.unitFrames = db.unitFrames or {}
								local uf = db.unitFrames.Player or {}
								return not not uf.useCustomBorders
							end
	
							-- Border Style (same option list as Power Bar)
							do
								local function opts()
									local c = Settings.CreateControlTextContainer()
									c:Add("none", "None")
									if addon and addon.BuildBarBorderOptionsContainer then
										local base = addon.BuildBarBorderOptionsContainer()
										if type(base) == "table" then
											for _, entry in ipairs(base) do
												if entry and entry.value and entry.text then
													c:Add(entry.value, entry.text)
												end
											end
										end
									else
										c:Add("square", "Default (Square)")
									end
									return c:GetData()
								end
								local function getStyle()
									local t = ensureUFDB() or {}; return t.borderStyle or "none" end
								local function setStyle(v)
									local t = ensureUFDB(); if not t then return end
									t.borderStyle = v or "none"
									applyNow()
								end
								local setting = CreateLocalSetting("Border Style", "string", getStyle, setStyle, getStyle())
								local initDrop = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", { name = "Border Style", setting = setting, options = opts })
								local f = CreateFrame("Frame", nil, frame.PageD, "SettingsDropdownControlTemplate")
								f.GetElementData = function() return initDrop end
								f:SetPoint("TOPLEFT", 4, y.y)
								f:SetPoint("TOPRIGHT", -16, y.y)
								initDrop:InitFrame(f)
								local lbl = f and (f.Text or f.Label)
								if lbl and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(lbl) end
								if f.Control and panel.ThemeDropdownWithSteppers then panel.ThemeDropdownWithSteppers(f.Control) end
								local enabled = isEnabled()
								if f.Control and f.Control.SetEnabled then f.Control:SetEnabled(enabled) end
								if lbl and lbl.SetTextColor then
									if enabled then lbl:SetTextColor(1, 1, 1, 1) else lbl:SetTextColor(0.6, 0.6, 0.6, 1) end
								end
								y.y = y.y - 34
							end
	
							-- Border Tint (checkbox + swatch)
							do
								local function getTintEnabled()
									local t = ensureUFDB() or {}; return not not t.borderTintEnable end
								local function setTintEnabled(b)
									local t = ensureUFDB(); if not t then return end
									t.borderTintEnable = not not b
									applyNow()
								end
								local function getTint()
									local t = ensureUFDB() or {}
									local c = t.borderTintColor or {1,1,1,1}
									return { c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 }
								end
								local function setTint(r,g,b,a)
									local t = ensureUFDB(); if not t then return end
									t.borderTintColor = { r or 1, g or 1, b or 1, a or 1 }
									applyNow()
								end
								local tintSetting = CreateLocalSetting("Border Tint", "boolean", getTintEnabled, setTintEnabled, getTintEnabled())
								local initCb = CreateCheckboxWithSwatchInitializer(tintSetting, "Border Tint", getTint, setTint, 8)
								local row = CreateFrame("Frame", nil, frame.PageD, "SettingsCheckboxControlTemplate")
								row.GetElementData = function() return initCb end
								row:SetPoint("TOPLEFT", 4, y.y)
								row:SetPoint("TOPRIGHT", -16, y.y)
								initCb:InitFrame(row)
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
									local t = ensureUFDB() or {}; return tonumber(t.borderThickness) or 1 end
								local function setThk(v)
									local t = ensureUFDB(); if not t then return end
									local nv = tonumber(v) or 1
									if nv < 1 then nv = 1 elseif nv > 8 then nv = 8 end
									t.borderThickness = nv
									applyNow()
								end
								local opts = Settings.CreateSliderOptions(1, 8, 0.2)
								opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return string.format("%.1f", v) end)
								local thkSetting = CreateLocalSetting("Border Thickness", "number", getThk, setThk, getThk())
								local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = "Border Thickness", setting = thkSetting, options = opts })
								local sf = CreateFrame("Frame", nil, frame.PageD, "SettingsSliderControlTemplate")
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
	
							-- Border Inset
							do
								local function getInset()
									local t = ensureUFDB() or {}; return tonumber(t.borderInset) or 0 end
								local function setInset(v)
									local t = ensureUFDB(); if not t then return end
									local nv = tonumber(v) or 0
									if nv < -4 then nv = -4 elseif nv > 4 then nv = 4 end
									t.borderInset = nv
									applyNow()
								end
								local opts = Settings.CreateSliderOptions(-4, 4, 1)
								opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return tostring(math.floor(v)) end)
								local insetSetting = CreateLocalSetting("Border Inset", "number", getInset, setInset, getInset())
								local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = "Border Inset", setting = insetSetting, options = opts })
								local sf = CreateFrame("Frame", nil, frame.PageD, "SettingsSliderControlTemplate")
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
	
						-- PageE: Visibility (Hide bar + text toggles)
						do
							local function applyNow()
								if addon and addon.ApplyStyles then addon:ApplyStyles() end
							end
							local y = { y = -50 }
	
							-- Hide Alternate Power Bar
							do
								local setting = CreateLocalSetting("Hide Alternate Power Bar", "boolean",
									function() local t = ensureUFDB() or {}; return (t.hidden == true) end,
									function(v) local t = ensureUFDB(); if not t then return end; t.hidden = (v == true); applyNow() end,
									false)
								local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = "Hide Alternate Power Bar", setting = setting, options = {} })
								local row = CreateFrame("Frame", nil, frame.PageE, "SettingsCheckboxControlTemplate")
								row.GetElementData = function() return initCb end
								row:SetPoint("TOPLEFT", 4, y.y)
								row:SetPoint("TOPRIGHT", -16, y.y)
								initCb:InitFrame(row)
								if panel and panel.ApplyRobotoWhite then
									if row.Text then panel.ApplyRobotoWhite(row.Text) end
									local cb = row.Checkbox or row.CheckBox or (row.Control and row.Control.Checkbox)
									if cb and cb.Text then panel.ApplyRobotoWhite(cb.Text) end
								end
								y.y = y.y - 34
							end
						end
	
						-- PageF: % Text
						do
							local function applyNow()
								if addon and addon.ApplyStyles then addon:ApplyStyles() end
							end
							local y = { y = -50 }
	
							-- Hide % Text
							do
								local setting = CreateLocalSetting("Hide % Text", "boolean",
									function() local t = ensureUFDB() or {}; return (t.percentHidden == true) end,
									function(v) local t = ensureUFDB(); if not t then return end; t.percentHidden = (v == true); applyNow() end,
									false)
								local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = "Hide % Text", setting = setting, options = {} })
								local row = CreateFrame("Frame", nil, frame.PageF, "SettingsCheckboxControlTemplate")
								row.GetElementData = function() return initCb end
								row:SetPoint("TOPLEFT", 4, y.y)
								row:SetPoint("TOPRIGHT", -16, y.y)
								initCb:InitFrame(row)
								if panel and panel.ApplyRobotoWhite then
									if row.Text then panel.ApplyRobotoWhite(row.Text) end
									local cb = row.Checkbox or row.CheckBox or (row.Control and row.Control.Checkbox)
									if cb and cb.Text then panel.ApplyRobotoWhite(cb.Text) end
								end
								y.y = y.y - 34
							end
	
							-- % Text Font
							addDropdown(frame.PageF, "Font", fontOptions,
								function() local t = ensureUFDB() or {}; local s = t.textPercent or {}; return s.fontFace or "FRIZQT__" end,
								function(v) local t = ensureUFDB(); if not t then return end; t.textPercent = t.textPercent or {}; t.textPercent.fontFace = v; applyNow() end,
								y)
							-- % Text Style
							addStyle(frame.PageF, "Font Style",
								function() local t = ensureUFDB() or {}; local s = t.textPercent or {}; return s.style or "OUTLINE" end,
								function(v) local t = ensureUFDB(); if not t then return end; t.textPercent = t.textPercent or {}; t.textPercent.style = v; applyNow() end,
								y)
							-- % Text Size
							addSlider(frame.PageF, "Font Size", 6, 48, 1,
								function() local t = ensureUFDB() or {}; local s = t.textPercent or {}; return tonumber(s.size) or 14 end,
								function(v) local t = ensureUFDB(); if not t then return end; t.textPercent = t.textPercent or {}; t.textPercent.size = tonumber(v) or 14; applyNow() end,
								y)
							-- % Text Color
							addColor(frame.PageF, "Font Color", false,
								function()
									local t = ensureUFDB() or {}; local s = t.textPercent or {}; local c = s.color or {1,1,1,1}
									return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
								end,
								function(r,g,b,a)
									local t = ensureUFDB(); if not t then return end
									t.textPercent = t.textPercent or {}; t.textPercent.color = { r or 1, g or 1, b or 1, a or 1 }; applyNow()
								end,
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
									local t = ensureUFDB() or {}; local s = t.textPercent or {}; return s.alignment or "LEFT"
								end
								local function setAlign(v)
									local t = ensureUFDB(); if not t then return end
									t.textPercent = t.textPercent or {}
									t.textPercent.alignment = v or "LEFT"
									applyNow()
								end
								local setting = CreateLocalSetting("Alignment", "string", getAlign, setAlign, getAlign())
								local initDrop = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", { name = "Alignment", setting = setting, options = alignOpts })
								local f = CreateFrame("Frame", nil, frame.PageF, "SettingsDropdownControlTemplate")
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
							-- % Text Offset X/Y
							addSlider(frame.PageF, "Font X Offset", -100, 100, 1,
								function() local t = ensureUFDB() or {}; local s = t.textPercent or {}; local o = s.offset or {}; return tonumber(o.x) or 0 end,
								function(v) local t = ensureUFDB(); if not t then return end; t.textPercent = t.textPercent or {}; t.textPercent.offset = t.textPercent.offset or {}; t.textPercent.offset.x = tonumber(v) or 0; applyNow() end,
								y)
							addSlider(frame.PageF, "Font Y Offset", -100, 100, 1,
								function() local t = ensureUFDB() or {}; local s = t.textPercent or {}; local o = s.offset or {}; return tonumber(o.y) or 0 end,
								function(v) local t = ensureUFDB(); if not t then return end; t.textPercent = t.textPercent or {}; t.textPercent.offset = t.textPercent.offset or {}; t.textPercent.offset.y = tonumber(v) or 0; applyNow() end,
								y)
						end
	
						-- PageG: Value Text
						do
							local function applyNow()
								if addon and addon.ApplyStyles then addon:ApplyStyles() end
							end
							local y = { y = -50 }
	
							-- Hide Value Text
							do
								local setting = CreateLocalSetting("Hide Value Text", "boolean",
									function() local t = ensureUFDB() or {}; return (t.valueHidden == true) end,
									function(v) local t = ensureUFDB(); if not t then return end; t.valueHidden = (v == true); applyNow() end,
									false)
								local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = "Hide Value Text", setting = setting, options = {} })
								local row = CreateFrame("Frame", nil, frame.PageG, "SettingsCheckboxControlTemplate")
								row.GetElementData = function() return initCb end
								row:SetPoint("TOPLEFT", 4, y.y)
								row:SetPoint("TOPRIGHT", -16, y.y)
								initCb:InitFrame(row)
								if panel and panel.ApplyRobotoWhite then
									if row.Text then panel.ApplyRobotoWhite(row.Text) end
									local cb = row.Checkbox or row.CheckBox or (row.Control and row.Control.Checkbox)
									if cb and cb.Text then panel.ApplyRobotoWhite(cb.Text) end
								end
								y.y = y.y - 34
							end
	
							-- Value Text Font
							addDropdown(frame.PageG, "Font", fontOptions,
								function() local t = ensureUFDB() or {}; local s = t.textValue or {}; return s.fontFace or "FRIZQT__" end,
								function(v) local t = ensureUFDB(); if not t then return end; t.textValue = t.textValue or {}; t.textValue.fontFace = v; applyNow() end,
								y)
							-- Value Text Style
							addStyle(frame.PageG, "Font Style",
								function() local t = ensureUFDB() or {}; local s = t.textValue or {}; return s.style or "OUTLINE" end,
								function(v) local t = ensureUFDB(); if not t then return end; t.textValue = t.textValue or {}; t.textValue.style = v; applyNow() end,
								y)
							-- Value Text Size
							addSlider(frame.PageG, "Font Size", 6, 48, 1,
								function() local t = ensureUFDB() or {}; local s = t.textValue or {}; return tonumber(s.size) or 14 end,
								function(v) local t = ensureUFDB(); if not t then return end; t.textValue = t.textValue or {}; t.textValue.size = tonumber(v) or 14; applyNow() end,
								y)
							-- Value Text Color
							addColor(frame.PageG, "Font Color", false,
								function()
									local t = ensureUFDB() or {}; local s = t.textValue or {}; local c = s.color or {1,1,1,1}
									return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
								end,
								function(r,g,b,a)
									local t = ensureUFDB(); if not t then return end
									t.textValue = t.textValue or {}; t.textValue.color = { r or 1, g or 1, b or 1, a or 1 }; applyNow()
								end,
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
									local t = ensureUFDB() or {}; local s = t.textValue or {}; return s.alignment or "RIGHT"
								end
								local function setAlign(v)
									local t = ensureUFDB(); if not t then return end
									t.textValue = t.textValue or {}
									t.textValue.alignment = v or "RIGHT"
									applyNow()
								end
								local setting = CreateLocalSetting("Alignment", "string", getAlign, setAlign, getAlign())
								local initDrop = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", { name = "Alignment", setting = setting, options = alignOpts })
								local f = CreateFrame("Frame", nil, frame.PageG, "SettingsDropdownControlTemplate")
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
							-- Value Text Offset X/Y
							addSlider(frame.PageG, "Font X Offset", -100, 100, 1,
								function() local t = ensureUFDB() or {}; local s = t.textValue or {}; local o = s.offset or {}; return tonumber(o.x) or 0 end,
								function(v) local t = ensureUFDB(); if not t then return end; t.textValue = t.textValue or {}; t.textValue.offset = t.textValue.offset or {}; t.textValue.offset.x = tonumber(v) or 0; applyNow() end,
								y)
							addSlider(frame.PageG, "Font Y Offset", -100, 100, 1,
								function() local t = ensureUFDB() or {}; local s = t.textValue or {}; local o = s.offset or {}; return tonumber(o.y) or 0 end,
								function(v) local t = ensureUFDB(); if not t then return end; t.textValue = t.textValue or {}; t.textValue.offset = t.textValue.offset or {}; t.textValue.offset.y = tonumber(v) or 0; applyNow() end,
								y)
						end
					end
	
					local apbInit = Settings.CreateElementInitializer("ScooterTabbedSectionTemplate", apbTabs)
					-- STATIC HEIGHT for tabbed sections with up to 8 settings per tab.
					apbInit.GetExtent = function() return 364 end
					apbInit:AddShownPredicate(function()
						return panel:IsSectionExpanded(componentId, "Alternate Power Bar")
					end)
					table.insert(init, apbInit)
				end
	
	end

panel.UnitFramesSections.power = build

return build