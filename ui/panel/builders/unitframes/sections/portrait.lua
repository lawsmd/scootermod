local addonName, addon = ...

addon.SettingsPanel = addon.SettingsPanel or {}
local panel = addon.SettingsPanel
panel.UnitFramesSections = panel.UnitFramesSections or {}

local function build(ctx, init)
	local componentId = ctx.componentId
	local title = ctx.title
	local panel = ctx.panel or panel
	local addon = ctx.addon or addon

			-- Fifth collapsible section: Portrait (all unit frames)
			local expInitializerPortrait = Settings.CreateElementInitializer("ScooterExpandableSectionTemplate", {
				name = "Portrait",
				sectionKey = "Portrait",
				componentId = componentId,
				expanded = panel:IsSectionExpanded(componentId, "Portrait"),
			})
			expInitializerPortrait.GetExtent = function() return 30 end
			table.insert(init, expInitializerPortrait)
	
			-- Portrait tabs: Positioning / Sizing / Mask / Border / Personal Text / Visibility
			-- Personal Text tab exists for Player and Pet frames (both have combat feedback text)
			-- Positioning tab disabled for Pet (PetFrame is a managed frame; moving portrait causes entire frame to move)
			local portraitTabs = { sectionTitle = "", tabAText = (componentId ~= "ufPet") and "Positioning" or nil, tabBText = "Sizing", tabCText = "Mask", tabDText = "Border", tabEText = (componentId == "ufPlayer" or componentId == "ufPet") and "Personal Text" or nil, tabFText = "Visibility" }
			portraitTabs.build = function(frame)
				-- Helper for unit key
				local function unitKey()
					if componentId == "ufPlayer" then return "Player" end
					if componentId == "ufTarget" then return "Target" end
					if componentId == "ufFocus" then return "Focus" end
					if componentId == "ufPet" then return "Pet" end
					return nil
				end
	
				-- Helper to ensure unit frame DB
				local function ensureUFDB()
					local db = addon and addon.db and addon.db.profile
					if not db then return nil end
					db.unitFrames = db.unitFrames or {}
					local uk = unitKey(); if not uk then return nil end
					db.unitFrames[uk] = db.unitFrames[uk] or {}
					db.unitFrames[uk].portrait = db.unitFrames[uk].portrait or {}
					return db.unitFrames[uk].portrait
				end
	
				-- Helper functions for controls
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
	
				-- PageA: Positioning (disabled for Pet - PetFrame is a managed frame; moving portrait causes entire frame to move)
				if componentId ~= "ufPet" then
					do
						local function applyNow()
							if addon and addon.ApplyUnitFramePortraitFor then addon.ApplyUnitFramePortraitFor(unitKey()) end
							if addon and addon.ApplyStyles then addon:ApplyStyles() end
						end
						local y = { y = -50 }
						
						-- X Offset slider
						addSlider(frame.PageA, "X Offset", -100, 100, 1,
							function() local t = ensureUFDB() or {}; return tonumber(t.offsetX) or 0 end,
							function(v) local t = ensureUFDB(); if not t then return end; t.offsetX = tonumber(v) or 0; applyNow() end,
							y)
						
						-- Y Offset slider
						addSlider(frame.PageA, "Y Offset", -100, 100, 1,
							function() local t = ensureUFDB() or {}; return tonumber(t.offsetY) or 0 end,
							function(v) local t = ensureUFDB(); if not t then return end; t.offsetY = tonumber(v) or 0; applyNow() end,
							y)
					end
				end
	
				-- PageB: Sizing
				do
					local function applyNow()
						if addon and addon.ApplyUnitFramePortraitFor then addon.ApplyUnitFramePortraitFor(unitKey()) end
						if addon and addon.ApplyStyles then addon:ApplyStyles() end
					end
					local y = { y = -50 }
					
					-- Portrait Size (Scale) slider
					addSlider(frame.PageB, "Portrait Size (Scale)", 50, 200, 1,
						function() local t = ensureUFDB() or {}; return tonumber(t.scale) or 100 end,
						function(v) local t = ensureUFDB(); if not t then return end; t.scale = tonumber(v) or 100; applyNow() end,
						y)
				end
	
				-- PageC: Mask
				do
					local function applyNow()
						if addon and addon.ApplyUnitFramePortraitFor then addon.ApplyUnitFramePortraitFor(unitKey()) end
						if addon and addon.ApplyStyles then addon:ApplyStyles() end
					end
					local y = { y = -50 }
					
					-- Portrait Zoom slider
					-- Note: Zoom out (< 100%) is not supported because portrait textures are already at full bounds (0,1,0,1).
					-- We cannot show pixels beyond the texture bounds. Zoom in (> 100%) works by cropping the edges.
					-- Range: 100-200% (zoom in only)
					addSlider(frame.PageC, "Portrait Zoom", 100, 200, 1,
						function() local t = ensureUFDB() or {}; return tonumber(t.zoom) or 100 end,
						function(v) local t = ensureUFDB(); if not t then return end; t.zoom = tonumber(v) or 100; applyNow() end,
						y)
					
					-- Use Full Circle Mask checkbox (Player only)
					if unitKey() == "Player" then
						do
							local setting = CreateLocalSetting("Use Full Circle Mask", "boolean",
								function() local t = ensureUFDB() or {}; return (t.useFullCircleMask == true) end,
								function(v) local t = ensureUFDB(); if not t then return end; t.useFullCircleMask = (v == true); applyNow() end,
								false)
							local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = "Use Full Circle Mask", setting = setting, options = {} })
							local row = CreateFrame("Frame", nil, frame.PageC, "SettingsCheckboxControlTemplate")
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
				end
	
				-- PageD: Border
				do
					local function applyNow()
						if addon and addon.ApplyUnitFramePortraitFor then addon.ApplyUnitFramePortraitFor(unitKey()) end
						if addon and addon.ApplyStyles then addon:ApplyStyles() end
					end
					local y = { y = -50 }
					
					-- Helper function to check if border is enabled
					local function isEnabled()
						local t = ensureUFDB() or {}
						return not not t.portraitBorderEnable
					end
					
					-- Use Custom Border checkbox
					do
						local setting = CreateLocalSetting("Use Custom Border", "boolean",
							function() local t = ensureUFDB() or {}; return (t.portraitBorderEnable == true) end,
							function(v) 
								local t = ensureUFDB(); if not t then return end
								t.portraitBorderEnable = (v == true)
								applyNow()
							end,
							false)
						local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = "Use Custom Border", setting = setting, options = {} })
						local row = CreateFrame("Frame", nil, frame.PageD, "SettingsCheckboxControlTemplate")
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
					
					-- Border Style dropdown
					do
						local function optionsStyle()
							local c = Settings.CreateControlTextContainer()
							c:Add("texture_c", "Circle")
							c:Add("texture_s", "Circle with Corner")
							c:Add("rare_c", "Rare (Circle)")
							-- Rare (Square) only available for Target and Focus
							if unitKey() == "Target" or unitKey() == "Focus" then
								c:Add("rare_s", "Rare (Square)")
							end
							return c:GetData()
						end
						local function getStyle()
							local t = ensureUFDB() or {}
							local current = t.portraitBorderStyle or "texture_c"
							-- If current style is "default" or "rare_s" for non-Target/Focus, reset to first option
							if current == "default" then
								return "texture_c"
							end
							if current == "rare_s" and unitKey() ~= "Target" and unitKey() ~= "Focus" then
								return "texture_c"
							end
							return current
						end
						local function setStyle(v)
							local t = ensureUFDB(); if not t then return end
							-- Don't allow "default" or "rare_s" for non-Target/Focus
							if v == "default" then
								v = "texture_c"
							end
							if v == "rare_s" and unitKey() ~= "Target" and unitKey() ~= "Focus" then
								v = "texture_c"
							end
							t.portraitBorderStyle = v or "texture_c"
							applyNow()
						end
						local styleSetting = CreateLocalSetting("Border Style", "string", getStyle, setStyle, getStyle())
						local initDrop = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", { name = "Border Style", setting = styleSetting, options = optionsStyle })
						local f = CreateFrame("Frame", nil, frame.PageD, "SettingsDropdownControlTemplate")
						f.GetElementData = function() return initDrop end
						f:SetPoint("TOPLEFT", 4, y.y)
						f:SetPoint("TOPRIGHT", -16, y.y)
						initDrop:InitFrame(f)
						local lbl = f and (f.Text or f.Label)
						if lbl and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(lbl) end
						if f.Control and panel.ThemeDropdownWithSteppers then panel.ThemeDropdownWithSteppers(f.Control) end
						-- Grey out when Use Custom Border is off
						local enabled = isEnabled()
						if f.Control and f.Control.SetEnabled then f.Control:SetEnabled(enabled) end
						if lbl and lbl.SetTextColor then
							if enabled then lbl:SetTextColor(1, 1, 1, 1) else lbl:SetTextColor(0.6, 0.6, 0.6, 1) end
						end
						y.y = y.y - 34
					end
					
					-- Border Inset slider (moved to directly after Border Style)
					do
						local function getInset()
							local t = ensureUFDB() or {}; return tonumber(t.portraitBorderThickness) or 1
						end
						local function setInset(v)
							local t = ensureUFDB(); if not t then return end
							local nv = tonumber(v) or 1
							if nv < 1 then nv = 1 elseif nv > 8 then nv = 8 end
							t.portraitBorderThickness = nv
							applyNow()
						end
						local opts = Settings.CreateSliderOptions(1, 8, 0.2)
						opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return string.format("%.1f", v) end)
						local insetSetting = CreateLocalSetting("Border Inset", "number", getInset, setInset, getInset())
						local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = "Border Inset", setting = insetSetting, options = opts })
						local sf = CreateFrame("Frame", nil, frame.PageD, "SettingsSliderControlTemplate")
						sf.GetElementData = function() return initSlider end
						sf:SetPoint("TOPLEFT", 4, y.y)
						sf:SetPoint("TOPRIGHT", -16, y.y)
						initSlider:InitFrame(sf)
						if sf.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(sf.Text) end
						if panel and panel.ThemeSliderValue then panel.ThemeSliderValue(sf) end
						-- Grey out when Use Custom Border is off
						local enabled = isEnabled()
						if sf.Control and sf.Control.SetEnabled then sf.Control:SetEnabled(enabled) end
						if sf.Text and sf.Text.SetTextColor then
							if enabled then sf.Text:SetTextColor(1, 1, 1, 1) else sf.Text:SetTextColor(0.6, 0.6, 0.6, 1) end
						end
						y.y = y.y - 34
					end
					
					-- Border Color (dropdown) + inline Custom Tint swatch (unified control)
					do
						local function colorOpts()
							local container = Settings.CreateControlTextContainer()
							container:Add("texture", "Texture Original")
							container:Add("class", "Class Color")
							container:Add("custom", "Custom")
							return container:GetData()
						end
						local function getColorMode()
							local t = ensureUFDB() or {}
							return t.portraitBorderColorMode or "texture"
						end
						local function setColorMode(v)
							local t = ensureUFDB(); if not t then return end
							t.portraitBorderColorMode = v or "texture"
							applyNow()
						end
						local function getTint()
							local t = ensureUFDB() or {}
							local c = t.portraitBorderTintColor or {1,1,1,1}
							return { c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 }
						end
						local function setTint(r, g, b, a)
							local t = ensureUFDB(); if not t then return end
							t.portraitBorderTintColor = { r or 1, g or 1, b or 1, a or 1 }
							applyNow()
						end
						panel.DropdownWithInlineSwatch(frame.PageD, y, {
							label = "Border Color",
							getMode = getColorMode,
							setMode = setColorMode,
							getColor = getTint,
							setColor = setTint,
							options = colorOpts,
							isEnabled = isEnabled,
							insideButton = true,
						})
					end
				end
	
				-- PageE: Personal Text (Player and Pet)
				do
					-- Only show this tab for Player and Pet frames (both have combat feedback text)
					local uk = unitKey()
					if uk ~= "Player" and uk ~= "Pet" then
						-- Empty page for non-Player/Pet frames
						local y = { y = -50 }
					else
						local function applyNow()
							if addon and addon.ApplyUnitFramePortraitFor then addon.ApplyUnitFramePortraitFor(unitKey()) end
							if addon and addon.ApplyStyles then addon:ApplyStyles() end
						end
						local function fontOptions()
							return addon.BuildFontOptionsContainer()
						end
						local y = { y = -50 }
						
						-- Helper function to check if personal text is disabled
						local function isDisabled()
							local t = ensureUFDB() or {}
							return not not t.damageTextDisabled
						end
						
						-- Store references to controls for gray-out logic
						local _dtFontFrame, _dtStyleFrame, _dtSizeFrame, _dtColorFrame, _dtOffsetXFrame, _dtOffsetYFrame
						
						-- Function to refresh gray-out state
						local function refreshPersonalTextDisabledState()
							local disabled = isDisabled()
							-- Gray out all controls when disabled
							if _dtFontFrame then
								if _dtFontFrame.Control and _dtFontFrame.Control.SetEnabled then _dtFontFrame.Control:SetEnabled(not disabled) end
								local lbl = _dtFontFrame.Text or _dtFontFrame.Label
								if lbl and lbl.SetTextColor then lbl:SetTextColor(disabled and 0.6 or 1, disabled and 0.6 or 1, disabled and 0.6 or 1, 1) end
							end
							if _dtStyleFrame then
								if _dtStyleFrame.Control and _dtStyleFrame.Control.SetEnabled then _dtStyleFrame.Control:SetEnabled(not disabled) end
								local lbl = _dtStyleFrame.Text or _dtStyleFrame.Label
								if lbl and lbl.SetTextColor then lbl:SetTextColor(disabled and 0.6 or 1, disabled and 0.6 or 1, disabled and 0.6 or 1, 1) end
							end
							if _dtSizeFrame then
								if _dtSizeFrame.Control and _dtSizeFrame.Control.SetEnabled then _dtSizeFrame.Control:SetEnabled(not disabled) end
								if _dtSizeFrame.Text and _dtSizeFrame.Text.SetTextColor then _dtSizeFrame.Text:SetTextColor(disabled and 0.6 or 1, disabled and 0.6 or 1, disabled and 0.6 or 1, 1) end
							end
							if _dtColorFrame then
								-- Color dropdown
								if _dtColorFrame.Control and _dtColorFrame.Control.SetEnabled then _dtColorFrame.Control:SetEnabled(not disabled) end
								local lbl = _dtColorFrame.Text or _dtColorFrame.Label
								if lbl and lbl.SetTextColor then lbl:SetTextColor(disabled and 0.6 or 1, disabled and 0.6 or 1, disabled and 0.6 or 1, 1) end
								-- Color swatch
								if _dtColorFrame.ScooterInlineSwatch and _dtColorFrame.ScooterInlineSwatch.EnableMouse then
									_dtColorFrame.ScooterInlineSwatch:EnableMouse(not disabled)
									if _dtColorFrame.ScooterInlineSwatch.SetAlpha then _dtColorFrame.ScooterInlineSwatch:SetAlpha(disabled and 0.5 or 1) end
								end
							end
							if _dtOffsetXFrame then
								if _dtOffsetXFrame.Control and _dtOffsetXFrame.Control.SetEnabled then _dtOffsetXFrame.Control:SetEnabled(not disabled) end
								if _dtOffsetXFrame.Text and _dtOffsetXFrame.Text.SetTextColor then _dtOffsetXFrame.Text:SetTextColor(disabled and 0.6 or 1, disabled and 0.6 or 1, disabled and 0.6 or 1, 1) end
							end
							if _dtOffsetYFrame then
								if _dtOffsetYFrame.Control and _dtOffsetYFrame.Control.SetEnabled then _dtOffsetYFrame.Control:SetEnabled(not disabled) end
								if _dtOffsetYFrame.Text and _dtOffsetYFrame.Text.SetTextColor then _dtOffsetYFrame.Text:SetTextColor(disabled and 0.6 or 1, disabled and 0.6 or 1, disabled and 0.6 or 1, 1) end
							end
						end
						
						-- Disable Personal Text checkbox
						local label = "Disable Personal Text"
						local function getter()
							local t = ensureUFDB(); return t and not not t.damageTextDisabled or false
						end
						local function setter(v)
							local t = ensureUFDB(); if not t then return end
							t.damageTextDisabled = (v and true) or false
							applyNow()
							refreshPersonalTextDisabledState()
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
						end
						-- Add info icon tooltip explaining Personal Text (adjust text for Pet vs Player)
						if panel and panel.CreateInfoIcon then
							local tooltipText
							if uk == "Pet" then
								tooltipText = "These settings control the floating combat text that appears over your pet's portrait when it takes damage or receives healing."
							else
								tooltipText = "These settings control the floating combat text that appears over your portrait when your character takes damage or receives healing."
							end
							local checkbox = row.Checkbox or row.CheckBox or (row.Control and row.Control.Checkbox)
							if checkbox then
								row.ScooterPersonalTextInfoIcon = panel.CreateInfoIcon(row, tooltipText, "LEFT", "RIGHT", 10, 0, 32)
								row.ScooterPersonalTextInfoIcon:ClearAllPoints()
								row.ScooterPersonalTextInfoIcon:SetPoint("LEFT", checkbox, "RIGHT", 10, 0)
							end
						end
						y.y = y.y - 34
						
						-- Personal Text Font
						_dtFontFrame = addDropdown(frame.PageE, "Font", fontOptions,
							function() local t = ensureUFDB() or {}; local s = t.damageText or {}; return s.fontFace or "FRIZQT__" end,
							function(v) local t = ensureUFDB(); if not t then return end; t.damageText = t.damageText or {}; t.damageText.fontFace = v; applyNow() end,
							y)
						
						-- Personal Text Style
						_dtStyleFrame = addStyle(frame.PageE, "Font Style",
							function() local t = ensureUFDB() or {}; local s = t.damageText or {}; return s.style or "OUTLINE" end,
							function(v) local t = ensureUFDB(); if not t then return end; t.damageText = t.damageText or {}; t.damageText.style = v; applyNow() end,
							y)
						
						-- Personal Text Size
						_dtSizeFrame = addSlider(frame.PageE, "Font Size", 6, 48, 1,
							function() local t = ensureUFDB() or {}; local s = t.damageText or {}; return tonumber(s.size) or 14 end,
							function(v) local t = ensureUFDB(); if not t then return end; t.damageText = t.damageText or {}; t.damageText.size = tonumber(v) or 14; applyNow() end,
							y)
						
						-- Personal Text Color (dropdown + inline swatch)
						do
							local function colorOpts()
								local c = Settings.CreateControlTextContainer()
								c:Add("default", "Default")
								c:Add("class", "Class Color")
								c:Add("custom", "Custom")
								return c:GetData()
							end
							local function getMode()
								local t = ensureUFDB() or {}; local s = t.damageText or {}; return s.colorMode or "default"
							end
							local function setMode(v)
								local t = ensureUFDB(); if not t then return end
								t.damageText = t.damageText or {}; t.damageText.colorMode = v or "default"; applyNow()
							end
							local function getColorTbl()
								local t = ensureUFDB() or {}; local s = t.damageText or {}; local c = s.color or {1.0,0.82,0.0,1}
								return { c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 }
							end
							local function setColorTbl(r,g,b,a)
								local t = ensureUFDB(); if not t then return end
								t.damageText = t.damageText or {}; t.damageText.color = { r or 1, g or 1, b or 1, a or 1 }; applyNow()
							end
							_dtColorFrame = panel.DropdownWithInlineSwatch(frame.PageE, y, {
								label = "Font Color",
								getMode = getMode,
								setMode = setMode,
								getColor = getColorTbl,
								setColor = setColorTbl,
								options = colorOpts,
								insideButton = true,
							})
						end
						
						-- Personal Text Offset X
						_dtOffsetXFrame = addSlider(frame.PageE, "Font X Offset", -100, 100, 1,
							function() local t = ensureUFDB() or {}; local s = t.damageText or {}; local o = s.offset or {}; return tonumber(o.x) or 0 end,
							function(v) local t = ensureUFDB(); if not t then return end; t.damageText = t.damageText or {}; t.damageText.offset = t.damageText.offset or {}; t.damageText.offset.x = tonumber(v) or 0; applyNow() end,
							y)
						
						-- Personal Text Offset Y
						_dtOffsetYFrame = addSlider(frame.PageE, "Font Y Offset", -100, 100, 1,
							function() local t = ensureUFDB() or {}; local s = t.damageText or {}; local o = s.offset or {}; return tonumber(o.y) or 0 end,
							function(v) local t = ensureUFDB(); if not t then return end; t.damageText = t.damageText or {}; t.damageText.offset = t.damageText.offset or {}; t.damageText.offset.y = tonumber(v) or 0; applyNow() end,
							y)
						
						-- Initialize gray-out state
						refreshPersonalTextDisabledState()
					end
				end
	
				-- PageF: Visibility
				do
					local function applyNow()
						if addon and addon.ApplyUnitFramePortraitFor then addon.ApplyUnitFramePortraitFor(unitKey()) end
						if addon and addon.ApplyStyles then addon:ApplyStyles() end
					end
					local y = { y = -50 }
					
					-- Hide Portrait checkbox
					do
						local setting = CreateLocalSetting("Hide Portrait", "boolean",
							function() local t = ensureUFDB() or {}; return (t.hidePortrait == true) end,
							function(v) local t = ensureUFDB(); if not t then return end; t.hidePortrait = (v == true); applyNow() end,
							false)
						local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = "Hide Portrait", setting = setting, options = {} })
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
					
					-- Hide Rest Loop/Animation checkbox (Player only)
					if unitKey() == "Player" then
						do
							local setting = CreateLocalSetting("Hide Rest Loop/Animation", "boolean",
								function() local t = ensureUFDB() or {}; return (t.hideRestLoop == true) end,
								function(v) local t = ensureUFDB(); if not t then return end; t.hideRestLoop = (v == true); applyNow() end,
								false)
							local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = "Hide Rest Loop/Animation", setting = setting, options = {} })
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
					end
					
					-- Hide Status Texture checkbox (Player only)
					if unitKey() == "Player" then
						do
							local setting = CreateLocalSetting("Hide Status Texture", "boolean",
								function() local t = ensureUFDB() or {}; return (t.hideStatusTexture == true) end,
								function(v) local t = ensureUFDB(); if not t then return end; t.hideStatusTexture = (v == true); applyNow() end,
								false)
							local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = "Hide Status Texture", setting = setting, options = {} })
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
					end
					
					-- Hide Corner Icon checkbox (Player only)
					if unitKey() == "Player" then
						do
							local setting = CreateLocalSetting("Hide Corner Icon", "boolean",
								function() local t = ensureUFDB() or {}; return (t.hideCornerIcon == true) end,
								function(v) local t = ensureUFDB(); if not t then return end; t.hideCornerIcon = (v == true); applyNow() end,
								false)
							local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = "Hide Corner Icon", setting = setting, options = {} })
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
					end
					
					-- Portrait Opacity slider (1-100%)
					addSlider(frame.PageF, "Portrait Opacity", 1, 100, 1,
						function() local t = ensureUFDB() or {}; return tonumber(t.opacity) or 100 end,
						function(v) local t = ensureUFDB(); if not t then return end; t.opacity = tonumber(v) or 100; applyNow() end,
						y)
				end
			end
	
			local portraitInit = Settings.CreateElementInitializer("ScooterTabbedSectionTemplate", portraitTabs)
			-- STATIC HEIGHT for tabbed sections with up to 7-8 settings per tab.
			-- Current: 330px provides comfortable spacing with 2px top gap and room at bottom.
			-- DO NOT reduce below 315px or settings will bleed past the bottom border.
			portraitInit.GetExtent = function() return 330 end
			portraitInit:AddShownPredicate(function()
				return panel:IsSectionExpanded(componentId, "Portrait")
			end)
			table.insert(init, portraitInit)
	
end

panel.UnitFramesSections.portrait = build

return build