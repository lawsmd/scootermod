local addonName, addon = ...

addon.SettingsPanel = addon.SettingsPanel or {}
local panel = addon.SettingsPanel
panel.UnitFramesSections = panel.UnitFramesSections or {}

local function build(ctx, init)
	local componentId = ctx.componentId
	local title = ctx.title
	local panel = ctx.panel or panel
	local addon = ctx.addon or addon

	-- Skip for ToT - it has no cast bar
	if componentId == "ufToT" then return end

			-- Sixth collapsible section: Cast Bar (Player/Target/Focus)
				if componentId == "ufPlayer" or componentId == "ufTarget" or componentId == "ufFocus" then
					local expInitializerCB = Settings.CreateElementInitializer("ScooterExpandableSectionTemplate", {
						name = "Cast Bar",
						sectionKey = "Cast Bar",
						componentId = componentId,
						expanded = panel:IsSectionExpanded(componentId, "Cast Bar"),
					})
					expInitializerCB.GetExtent = function() return 30 end
					table.insert(init, expInitializerCB)
	
					-- Cast Bar tabbed section:
					-- Player tabs (8): Positioning, Sizing, Style, Border, Icon, Spell Name Text, Cast Time Text, Visibility
					-- Target/Focus tabs (7): Positioning, Sizing, Style, Border, Icon, Spell Name Text, Visibility
					-- (Cast Time Text is not supported on Target/Focus Cast Bars)
					local isPlayerCastBar = (componentId == "ufPlayer")
					local cbData = {
						sectionTitle = "",
						tabAText = "Positioning",
						tabBText = "Sizing",
						tabCText = "Style",
						tabDText = "Border",
						tabEText = "Icon",
						tabFText = "Spell Name Text",
						tabGText = isPlayerCastBar and "Cast Time Text" or "Visibility",
						tabHText = isPlayerCastBar and "Visibility" or nil,
					}
					cbData.build = function(frame)
						-- Helper: map componentId -> unit key
						local function unitKey()
							if componentId == "ufPlayer" then return "Player" end
							if componentId == "ufTarget" then return "Target" end
							if componentId == "ufFocus" then return "Focus" end
							return nil
						end
	
						-- Helper: ensure Unit Frame Cast Bar DB namespace
						local function ensureCastBarDB()
							local uk = unitKey()
							if not uk then return nil end
							local db = addon and addon.db and addon.db.profile
							if not db then return nil end
							db.unitFrames = db.unitFrames or {}
							db.unitFrames[uk] = db.unitFrames[uk] or {}
							db.unitFrames[uk].castBar = db.unitFrames[uk].castBar or {}
							return db.unitFrames[uk].castBar
						end
	
						-- Small slider helper (used for Target/Focus offsets, Cast Bar icon sizing, and text controls)
						local function addSlider(parent, label, minV, maxV, step, getFunc, setFunc, yRef)
							local options = Settings.CreateSliderOptions(minV, maxV, step)
							options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v)
								return tostring(math.floor((tonumber(v) or 0) + 0.5))
							end)
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
	
						-- Local dropdown/text helpers (mirror Unit Frame Health/Power helpers)
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
							-- When the label mentions "Font" (but not "Style"), initialize the font dropdown wrapper
							if type(label) == "string" and string.find(label, "Font") and not string.find(label, "Style") and f.Control and f.Control.Dropdown and addon and addon.InitFontDropdown then
								addon.InitFontDropdown(f.Control.Dropdown, setting, optsProvider)
							end
							yRef.y = yRef.y - 34
							return f
						end
	
						local function addStyle(parent, label, getFunc, setFunc, yRef)
							local function styleOptions()
								local container = Settings.CreateControlTextContainer()
								container:Add("NONE", "Regular")
								container:Add("OUTLINE", "Outline")
								container:Add("THICKOUTLINE", "Thick Outline")
								container:Add("HEAVYTHICKOUTLINE", "Heavy Thick Outline")
								container:Add("SHADOW", "Shadow")
								container:Add("SHADOWOUTLINE", "Shadow Outline")
								container:Add("SHADOWTHICKOUTLINE", "Shadow Thick Outline")
								container:Add("HEAVYSHADOWTHICKOUTLINE", "Heavy Shadow Thick Outline")
								return container:GetData()
							end
							return addDropdown(parent, label, styleOptions, getFunc, setFunc, yRef)
						end
	
						local function addColor(parent, label, hasAlpha, getFunc, setFunc, yRef)
							local f = CreateFrame("Frame", nil, parent, "SettingsListElementTemplate")
							f:SetHeight(26)
							f:SetPoint("TOPLEFT", 4, yRef.y)
							f:SetPoint("TOPRIGHT", -16, yRef.y)
							if f.Text then
								f.Text:SetText(label)
								if panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(f.Text) end
							end
							local right = CreateFrame("Frame", nil, f)
							right:SetSize(250, 26)
							right:SetPoint("RIGHT", f, "RIGHT", -16, 0)
							if f.Text then
								f.Text:ClearAllPoints()
								f.Text:SetPoint("LEFT", f, "LEFT", 36.5, 0)
								f.Text:SetPoint("RIGHT", right, "LEFT", 0, 0)
								f.Text:SetJustifyH("LEFT")
							end
							-- Use centralized color swatch factory
							local function getColorTable()
								local r, g, b, a = getFunc()
								return { r or 1, g or 1, b or 1, a or 1 }
							end
							local function setColorTable(r, g, b, a)
								setFunc(r, g, b, a)
							end
							local swatch = CreateColorSwatch(right, getColorTable, setColorTable, hasAlpha)
							swatch:SetPoint("LEFT", right, "LEFT", 8, 0)
							yRef.y = yRef.y - 34
							return f
						end
	
						-- Shared Style tab (all unit frames with a Cast Bar)
						local function buildStyleTab()
							local uk = unitKey()
							if not uk then return end
							local function applyNow()
								if addon and addon.ApplyUnitFrameCastBarFor then addon.ApplyUnitFrameCastBarFor(uk) end
								if addon and addon.ApplyStyles then addon:ApplyStyles() end
							end
	
							local stylePage = frame.PageC
							local y = { y = -50 }
	
							-- Foreground Texture dropdown
							do
								local function getTex()
									local t = ensureCastBarDB() or {}
									return t.castBarTexture or "default"
								end
								local function setTex(v)
									local t = ensureCastBarDB(); if not t then return end
									t.castBarTexture = v
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
							end
	
							-- Foreground Color (dropdown + inline swatch)
							do
								local function colorOpts()
									local container = Settings.CreateControlTextContainer()
									container:Add("default", "Default")
									container:Add("texture", "Texture Original")
									container:Add("class", "Class Color")
									container:Add("custom", "Custom")
									return container:GetData()
								end
								local function getMode()
									local t = ensureCastBarDB() or {}
									return t.castBarColorMode or "default"
								end
								local function setMode(v)
									local t = ensureCastBarDB(); if not t then return end
									t.castBarColorMode = v or "default"
									applyNow()
								end
								local function getTint()
									local t = ensureCastBarDB() or {}
									local c = t.castBarTint or {1,1,1,1}
									return { c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 }
								end
								local function setTint(r,g,b,a)
									local t = ensureCastBarDB(); if not t then return end
									t.castBarTint = { r or 1, g or 1, b or 1, a or 1 }
									applyNow()
								end
								panel.DropdownWithInlineSwatch(stylePage, y, {
									label = "Foreground Color",
									getMode = getMode,
									setMode = setMode,
									getColor = getTint,
									setColor = setTint,
									options = colorOpts,
									insideButton = true,
								})
							end
	
							-- Background Texture dropdown
							do
								local function getBgTex()
									local t = ensureCastBarDB() or {}
									return t.castBarBackgroundTexture or "default"
								end
								local function setBgTex(v)
									local t = ensureCastBarDB(); if not t then return end
									t.castBarBackgroundTexture = v
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
								local fbg = CreateFrame("Frame", nil, stylePage, "SettingsDropdownControlTemplate")
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
	
							-- Background Color (dropdown + inline swatch)
							do
								local function bgColorOpts()
									local container = Settings.CreateControlTextContainer()
									container:Add("default", "Default")
									container:Add("texture", "Texture Original")
									container:Add("custom", "Custom")
									return container:GetData()
								end
								local function getBgMode()
									local t = ensureCastBarDB() or {}
									return t.castBarBackgroundColorMode or "default"
								end
								local function setBgMode(v)
									local t = ensureCastBarDB(); if not t then return end
									t.castBarBackgroundColorMode = v or "default"
									applyNow()
								end
								local function getBgTint()
									local t = ensureCastBarDB() or {}
									local c = t.castBarBackgroundTint or {0,0,0,1}
									return { c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1 }
								end
								local function setBgTint(r,g,b,a)
									local t = ensureCastBarDB(); if not t then return end
									t.castBarBackgroundTint = { r or 0, g or 0, b or 0, a or 1 }
									applyNow()
								end
								panel.DropdownWithInlineSwatch(stylePage, y, {
									label = "Background Color",
									getMode = getBgMode,
									setMode = setBgMode,
									getColor = getBgTint,
									setColor = setBgTint,
									options = bgColorOpts,
									insideButton = true,
								})
							end
	
							-- Background Opacity slider (0–100%)
							do
								local function getBgOpacity()
									local t = ensureCastBarDB() or {}
									return tonumber(t.castBarBackgroundOpacity) or 50
								end
								local function setBgOpacity(v)
									local t = ensureCastBarDB(); if not t then return end
									local val = tonumber(v) or 50
									if val < 0 then val = 0 elseif val > 100 then val = 100 end
									t.castBarBackgroundOpacity = val
									applyNow()
								end
								local opts = Settings.CreateSliderOptions(0, 100, 1)
								opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v)
									return tostring(math.floor((tonumber(v) or 0) + 0.5))
								end)
								local setting = CreateLocalSetting("Background Opacity", "number", getBgOpacity, setBgOpacity, getBgOpacity())
								local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = "Background Opacity", setting = setting, options = opts })
								local f = CreateFrame("Frame", nil, stylePage, "SettingsSliderControlTemplate")
								f.GetElementData = function() return initSlider end
								f:SetPoint("TOPLEFT", 4, y.y)
								f:SetPoint("TOPRIGHT", -16, y.y)
								initSlider:InitFrame(f)
								if panel and panel.ApplyRobotoWhite and f.Text then panel.ApplyRobotoWhite(f.Text) end
								if panel and panel.ThemeSliderValue then panel.ThemeSliderValue(f) end
							end
						end
	
						-- Shared Border tab (all unit frames with a Cast Bar)
						local function buildBorderTab()
							local uk = unitKey()
							if not uk then return end
	
							local function applyNow()
								if addon and addon.ApplyUnitFrameCastBarFor then addon.ApplyUnitFrameCastBarFor(uk) end
								if addon and addon.ApplyStyles then addon:ApplyStyles() end
							end
	
							local borderPage = frame.PageD
							local y = { y = -50 }
	
							-- Ensure Cast Bar DB namespace
							local function ensureCastBarDB()
								local db = addon and addon.db and addon.db.profile
								if not db then return nil end
								db.unitFrames = db.unitFrames or {}
								db.unitFrames[uk] = db.unitFrames[uk] or {}
								db.unitFrames[uk].castBar = db.unitFrames[uk].castBar or {}
								return db.unitFrames[uk].castBar
							end
	
							local function isEnabled()
								local t = ensureCastBarDB() or {}
								return not not t.castBarBorderEnable
							end
	
							-- Local references so we can gray-out rows without rebuilding the category (avoids flicker)
							local _styleFrame, _colorFrame, _thickFrame, _insetFrame
							local function refreshBorderEnabledState()
								local enabled = isEnabled()
	
								-- Border Style
								if _styleFrame then
									if _styleFrame.Control and _styleFrame.Control.SetEnabled then
										_styleFrame.Control:SetEnabled(enabled)
									end
									local lbl = _styleFrame.Text or _styleFrame.Label
									if lbl and lbl.SetTextColor then
										if enabled then lbl:SetTextColor(1, 1, 1, 1) else lbl:SetTextColor(0.6, 0.6, 0.6, 1) end
									end
								end
	
								-- Border Color dropdown + swatch
								if _colorFrame then
									if _colorFrame.Control and _colorFrame.Control.SetEnabled then
										_colorFrame.Control:SetEnabled(enabled)
									end
									local lbl = _colorFrame.Text or _colorFrame.Label
									if lbl and lbl.SetTextColor then
										if enabled then lbl:SetTextColor(1, 1, 1, 1) else lbl:SetTextColor(0.6, 0.6, 0.6, 1) end
									end
									if _colorFrame.ScooterInlineSwatch and _colorFrame.ScooterInlineSwatch.EnableMouse then
										_colorFrame.ScooterInlineSwatch:EnableMouse(enabled)
										if _colorFrame.ScooterInlineSwatch.SetAlpha then
											_colorFrame.ScooterInlineSwatch:SetAlpha(enabled and 1 or 0.5)
										end
									end
								end
	
								-- Border Thickness
								if _thickFrame then
									if _thickFrame.Control and _thickFrame.Control.SetEnabled then
										_thickFrame.Control:SetEnabled(enabled)
									end
									if _thickFrame.Text and _thickFrame.Text.SetTextColor then
										if enabled then _thickFrame.Text:SetTextColor(1, 1, 1, 1) else _thickFrame.Text:SetTextColor(0.6, 0.6, 0.6, 1) end
									end
								end
	
								-- Border Inset
								if _insetFrame then
									if _insetFrame.Control and _insetFrame.Control.SetEnabled then
										_insetFrame.Control:SetEnabled(enabled)
									end
									if _insetFrame.Text and _insetFrame.Text.SetTextColor then
										if enabled then _insetFrame.Text:SetTextColor(1, 1, 1, 1) else _insetFrame.Text:SetTextColor(0.6, 0.6, 0.6, 1) end
									end
								end
							end
	
							-- Enable Custom Border checkbox
							do
								local label = "Enable Custom Border"
								local function getter()
									local t = ensureCastBarDB() or {}
									return not not t.castBarBorderEnable
								end
								local function setter(v)
									local t = ensureCastBarDB(); if not t then return end
									t.castBarBorderEnable = (v == true)
									applyNow()
									-- Update gray-out state in-place to avoid panel flicker
									refreshBorderEnabledState()
								end
								local setting = CreateLocalSetting(label, "boolean", getter, setter, getter())
								local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = label, setting = setting, options = {} })
								local row = CreateFrame("Frame", nil, borderPage, "SettingsCheckboxControlTemplate")
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
								local function optionsBorder()
									if addon.BuildBarBorderOptionsContainer then
										return addon.BuildBarBorderOptionsContainer()
									end
									local c = Settings.CreateControlTextContainer()
									c:Add("square", "Default (Square)")
									return c:GetData()
								end
								local function getStyle()
									local t = ensureCastBarDB() or {}
									return t.castBarBorderStyle or "square"
								end
								local function setStyle(v)
									local t = ensureCastBarDB(); if not t then return end
									t.castBarBorderStyle = v or "square"
									applyNow()
								end
								local setting = CreateLocalSetting("Border Style", "string", getStyle, setStyle, getStyle())
								local initDrop = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", { name = "Border Style", setting = setting, options = optionsBorder })
								local f = CreateFrame("Frame", nil, borderPage, "SettingsDropdownControlTemplate")
								f.GetElementData = function() return initDrop end
								f:SetPoint("TOPLEFT", 4, y.y)
								f:SetPoint("TOPRIGHT", -16, y.y)
								initDrop:InitFrame(f)
								local lbl = f and (f.Text or f.Label)
								if lbl and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(lbl) end
								if f.Control and panel.ThemeDropdownWithSteppers then panel.ThemeDropdownWithSteppers(f.Control) end
								_styleFrame = f
								y.y = y.y - 34
							end
	
							-- Border Color (dropdown + inline swatch)
							do
								local function colorOpts()
									local c = Settings.CreateControlTextContainer()
									c:Add("default", "Default")
									c:Add("texture", "Texture Original")
									c:Add("custom", "Custom")
									return c:GetData()
								end
								local function getMode()
									local t = ensureCastBarDB() or {}
									return t.castBarBorderColorMode or "default"
								end
								local function setMode(v)
									local t = ensureCastBarDB(); if not t then return end
									t.castBarBorderColorMode = v or "default"
									applyNow()
								end
								local function getTint()
									local t = ensureCastBarDB() or {}
									local c = t.castBarBorderTintColor or {1,1,1,1}
									return { c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 }
								end
								local function setTint(r,g,b,a)
									local t = ensureCastBarDB(); if not t then return end
									t.castBarBorderTintColor = { r or 1, g or 1, b or 1, a or 1 }
									applyNow()
								end
								_colorFrame = panel.DropdownWithInlineSwatch(borderPage, y, {
									label = "Border Color",
									getMode = getMode,
									setMode = setMode,
									getColor = getTint,
									setColor = setTint,
									options = colorOpts,
									isEnabled = isEnabled,
									insideButton = true,
								})
							end
	
							-- Border Thickness slider
							do
								local function getThk()
									local t = ensureCastBarDB() or {}
									return tonumber(t.castBarBorderThickness) or 1
								end
								local function setThk(v)
									local t = ensureCastBarDB(); if not t then return end
									local nv = tonumber(v) or 1
									if nv < 1 then nv = 1 elseif nv > 8 then nv = 8 end
									t.castBarBorderThickness = nv
									applyNow()
								end
								local opts = Settings.CreateSliderOptions(1, 8, 0.2)
								opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return string.format("%.1f", v) end)
								local setting = CreateLocalSetting("Border Thickness", "number", getThk, setThk, getThk())
								local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = "Border Thickness", setting = setting, options = opts })
								local sf = CreateFrame("Frame", nil, borderPage, "SettingsSliderControlTemplate")
								sf.GetElementData = function() return initSlider end
								sf:SetPoint("TOPLEFT", 4, y.y)
								sf:SetPoint("TOPRIGHT", -16, y.y)
								initSlider:InitFrame(sf)
								if sf.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(sf.Text) end
								if panel and panel.ThemeSliderValue then panel.ThemeSliderValue(sf) end
								_thickFrame = sf
								y.y = y.y - 34
							end
							
							-- Border Inset slider (fine adjustment: negative = push outward, positive = pull inward)
							do
								local function getInset()
									local t = ensureCastBarDB() or {}
									return tonumber(t.castBarBorderInset) or 1
								end
								local function setInset(v)
									local t = ensureCastBarDB(); if not t then return end
									local nv = tonumber(v) or 0
									if nv < -4 then nv = -4 elseif nv > 4 then nv = 4 end
									t.castBarBorderInset = nv
									applyNow()
								end
								local opts = Settings.CreateSliderOptions(-4, 4, 1)
								opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return tostring(math.floor(v)) end)
								local setting = CreateLocalSetting("Border Inset", "number", getInset, setInset, getInset())
								local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = "Border Inset", setting = setting, options = opts })
								local sf = CreateFrame("Frame", nil, borderPage, "SettingsSliderControlTemplate")
								sf.GetElementData = function() return initSlider end
								sf:SetPoint("TOPLEFT", 4, y.y)
								sf:SetPoint("TOPRIGHT", -16, y.y)
								initSlider:InitFrame(sf)
								if sf.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(sf.Text) end
								if panel and panel.ThemeSliderValue then panel.ThemeSliderValue(sf) end
								_insetFrame = sf
								y.y = y.y - 34
							end
	
							-- Initialize gray-out state once when building
							refreshBorderEnabledState()
						end
	
						-- Shared Icon tab (all unit frames with a Cast Bar)
						local function buildIconTab()
							local uk = unitKey()
							if not uk then return end
	
						local function applyNow()
							if addon and addon.ApplyUnitFrameCastBarFor then addon.ApplyUnitFrameCastBarFor(uk) end
							if addon and addon.ApplyStyles then addon:ApplyStyles() end
						end
	
						local function ensureCastBarDB()
							local db = addon and addon.db and addon.db.profile
							if not db then return nil end
							db.unitFrames = db.unitFrames or {}
							db.unitFrames[uk] = db.unitFrames[uk] or {}
							db.unitFrames[uk].castBar = db.unitFrames[uk].castBar or {}
							return db.unitFrames[uk].castBar
						end
	
						local iconPage = frame.PageE
						local y = { y = -50 }
	
						-- Local references so we can gray-out rows without rebuilding the category
						local _iconHeightFrame, _iconWidthFrame, _iconPadFrame
						local _iconBorderEnableFrame, _iconBorderStyleFrame, _iconBorderThickFrame, _iconBorderTintFrame
	
						local function refreshIconEnabledState()
							local t = ensureCastBarDB() or {}
							local enabled = not not (not t.iconDisabled)
	
							local function setFrameEnabled(row, enabledFlag)
								if not row then return end
								if row.Control and row.Control.SetEnabled then
									row.Control:SetEnabled(enabledFlag)
								end
								local lbl = row.Text or row.Label
								if lbl and lbl.SetTextColor then
									if enabledFlag then lbl:SetTextColor(1, 1, 1, 1) else lbl:SetTextColor(0.6, 0.6, 0.6, 1) end
								end
							end
	
							setFrameEnabled(_iconHeightFrame, enabled)
							setFrameEnabled(_iconWidthFrame, enabled)
							setFrameEnabled(_iconPadFrame, enabled)
							setFrameEnabled(_iconBorderEnableFrame, enabled)
							setFrameEnabled(_iconBorderStyleFrame, enabled)
							setFrameEnabled(_iconBorderThickFrame, enabled)
							setFrameEnabled(_iconBorderTintFrame, enabled)
	
							-- Also dim the tint swatch itself
							if _iconBorderTintFrame and _iconBorderTintFrame.ScooterInlineSwatch then
								local sw = _iconBorderTintFrame.ScooterInlineSwatch
								if sw.EnableMouse then sw:EnableMouse(enabled) end
								if sw.SetAlpha then sw:SetAlpha(enabled and 1 or 0.5) end
							end
						end
	
						-- Disable Icon checkbox (DB-backed; affects icon + border visibility)
						do
							local label = "Disable Icon"
							local function getter()
								local t = ensureCastBarDB() or {}
								return not not t.iconDisabled
							end
							local function setter(v)
								local t = ensureCastBarDB(); if not t then return end
								t.iconDisabled = (v == true)
								applyNow()
								refreshIconEnabledState()
							end
							local setting = CreateLocalSetting(label, "boolean", getter, setter, getter())
							local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = label, setting = setting, options = {} })
							local row = CreateFrame("Frame", nil, iconPage, "SettingsCheckboxControlTemplate")
							row.GetElementData = function() return initCb end
							row:SetPoint("TOPLEFT", 4, y.y)
							row:SetPoint("TOPRIGHT", -16, y.y)
							initCb:InitFrame(row)
							if panel and panel.ApplyRobotoWhite then
								if row.Text then panel.ApplyRobotoWhite(row.Text) end
								local cb = row.Checkbox or row.CheckBox or (row.Control and row.Control.Checkbox)
								if cb and cb.Text then panel.ApplyRobotoWhite(cb.Text) end
							end
							-- Player-only: add info icon explaining why the icon is unavailable when unlocked
							if componentId == "ufPlayer" and panel and panel.CreateInfoIconForLabel and row.Text then
								if not row.ScooterInfoIcon then
									local tip = "The Player Cast Bar only has an icon when Positioning > \"Lock to Player Frame\" is enabled."
									local label = row.Text
									row.ScooterInfoIcon = panel.CreateInfoIconForLabel(label, tip, 5, 0, 24)
									-- Defer precise placement so we can anchor just after the label text, not over the checkbox
									if _G.C_Timer and _G.C_Timer.After then
										_G.C_Timer.After(0, function()
											local icon = row.ScooterInfoIcon
											if not (icon and label) then return end
											icon:ClearAllPoints()
											local textWidth = label.GetStringWidth and label:GetStringWidth() or 0
											if textWidth and textWidth > 0 then
												icon:SetPoint("LEFT", label, "LEFT", textWidth + 5, 0)
											else
												icon:SetPoint("LEFT", label, "RIGHT", 5, 0)
											end
										end)
									end
								end
							end
							y.y = y.y - 34
						end
	
							-- Icon Height (vertical size of the cast bar icon)
							do
								local function getH()
									local t = ensureCastBarDB() or {}
									return tonumber(t.iconHeight) or 16
								end
								local function setH(v)
									local t = ensureCastBarDB(); if not t then return end
									local val = tonumber(v) or 16
									if val < 8 then val = 8 elseif val > 64 then val = 64 end
									t.iconHeight = val
									applyNow()
								end
								local opts = Settings.CreateSliderOptions(8, 64, 1)
								opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v)
									return tostring(math.floor((tonumber(v) or 0) + 0.5))
								end)
								local setting = CreateLocalSetting("Icon Height", "number", getH, setH, getH())
								local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = "Icon Height", setting = setting, options = opts })
								local f = CreateFrame("Frame", nil, iconPage, "SettingsSliderControlTemplate")
								f.GetElementData = function() return initSlider end
								f:SetPoint("TOPLEFT", 4, y.y)
								f:SetPoint("TOPRIGHT", -16, y.y)
								initSlider:InitFrame(f)
								if f.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(f.Text) end
								if panel and panel.ThemeSliderValue then panel.ThemeSliderValue(f) end
								_iconHeightFrame = f
								y.y = y.y - 34
							end
	
							-- Icon Width (horizontal size of the cast bar icon)
							do
								local function getW()
									local t = ensureCastBarDB() or {}
									return tonumber(t.iconWidth) or 16
								end
								local function setW(v)
									local t = ensureCastBarDB(); if not t then return end
									local val = tonumber(v) or 16
									if val < 8 then val = 8 elseif val > 64 then val = 64 end
									t.iconWidth = val
									applyNow()
								end
								local opts = Settings.CreateSliderOptions(8, 64, 1)
								opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v)
									return tostring(math.floor((tonumber(v) or 0) + 0.5))
								end)
								local setting = CreateLocalSetting("Icon Width", "number", getW, setW, getW())
								local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = "Icon Width", setting = setting, options = opts })
								local f = CreateFrame("Frame", nil, iconPage, "SettingsSliderControlTemplate")
								f.GetElementData = function() return initSlider end
								f:SetPoint("TOPLEFT", 4, y.y)
								f:SetPoint("TOPRIGHT", -16, y.y)
								initSlider:InitFrame(f)
								if f.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(f.Text) end
								if panel and panel.ThemeSliderValue then panel.ThemeSliderValue(f) end
								_iconWidthFrame = f
								y.y = y.y - 34
							end
	
							-- Icon/Bar Padding (distance between icon and bar)
							do
								local function getPad()
									local t = ensureCastBarDB() or {}
									return tonumber(t.iconBarPadding) or 0
								end
								local function setPad(v)
									local t = ensureCastBarDB(); if not t then return end
									local val = tonumber(v) or 0
									if val < -20 then val = -20 elseif val > 80 then val = 80 end
									t.iconBarPadding = val
									applyNow()
								end
								local opts = Settings.CreateSliderOptions(-20, 80, 1)
								opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v)
									return tostring(math.floor((tonumber(v) or 0) + 0.5))
								end)
								local setting = CreateLocalSetting("Icon/Bar Padding", "number", getPad, setPad, getPad())
								local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = "Icon/Bar Padding", setting = setting, options = opts })
								local f = CreateFrame("Frame", nil, iconPage, "SettingsSliderControlTemplate")
								f.GetElementData = function() return initSlider end
								f:SetPoint("TOPLEFT", 4, y.y)
								f:SetPoint("TOPRIGHT", -16, y.y)
								initSlider:InitFrame(f)
								if f.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(f.Text) end
								if panel and panel.ThemeSliderValue then panel.ThemeSliderValue(f) end
								_iconPadFrame = f
								y.y = y.y - 34
							end
	
							-- Use Custom Icon Border checkbox
							do
								local label = "Use Custom Icon Border"
								local function getter()
									local t = ensureCastBarDB() or {}
									return not not t.iconBorderEnable
								end
								local function setter(v)
									local t = ensureCastBarDB(); if not t then return end
									t.iconBorderEnable = (v == true)
									applyNow()
								end
								local setting = CreateLocalSetting(label, "boolean", getter, setter, getter())
								local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = label, setting = setting, options = {} })
								local row = CreateFrame("Frame", nil, iconPage, "SettingsCheckboxControlTemplate")
								row.GetElementData = function() return initCb end
								row:SetPoint("TOPLEFT", 4, y.y)
								row:SetPoint("TOPRIGHT", -16, y.y)
								initCb:InitFrame(row)
								if panel and panel.ApplyRobotoWhite then
									if row.Text then panel.ApplyRobotoWhite(row.Text) end
									local cb = row.Checkbox or row.CheckBox or (row.Control and row.Control.Checkbox)
									if cb and cb.Text then panel.ApplyRobotoWhite(cb.Text) end
								end
								_iconBorderEnableFrame = row
								y.y = y.y - 34
							end
	
							-- Icon Border Style dropdown (all icon border library entries)
							do
								local function optionsIconBorder()
									if addon.BuildIconBorderOptionsContainer then
										return addon.BuildIconBorderOptionsContainer()
									end
									local c = Settings.CreateControlTextContainer()
									c:Add("square", "Default")
									return c:GetData()
								end
								local function getStyle()
									local t = ensureCastBarDB() or {}
									return t.iconBorderStyle or "square"
								end
								local function setStyle(v)
									local t = ensureCastBarDB(); if not t then return end
									t.iconBorderStyle = v or "square"
									applyNow()
								end
								local setting = CreateLocalSetting("Icon Border", "string", getStyle, setStyle, getStyle())
								local initDrop = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", { name = "Icon Border", setting = setting, options = optionsIconBorder })
								local f = CreateFrame("Frame", nil, iconPage, "SettingsDropdownControlTemplate")
								f.GetElementData = function() return initDrop end
								f:SetPoint("TOPLEFT", 4, y.y)
								f:SetPoint("TOPRIGHT", -16, y.y)
								initDrop:InitFrame(f)
								local lbl = f and (f.Text or f.Label)
								if lbl and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(lbl) end
								if f.Control and panel.ThemeDropdownWithSteppers then panel.ThemeDropdownWithSteppers(f.Control) end
								_iconBorderStyleFrame = f
								y.y = y.y - 34
							end
	
							-- Icon Border Thickness slider
							do
								local function getThk()
									local t = ensureCastBarDB() or {}
									return tonumber(t.iconBorderThickness) or 1
								end
								local function setThk(v)
									local t = ensureCastBarDB(); if not t then return end
									local nv = tonumber(v) or 1
									if nv < 1 then nv = 1 elseif nv > 8 then nv = 8 end
									t.iconBorderThickness = nv
									applyNow()
								end
								local opts = Settings.CreateSliderOptions(1, 8, 0.2)
								opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return string.format("%.1f", v) end)
								local setting = CreateLocalSetting("Icon Border Thickness", "number", getThk, setThk, getThk())
								local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = "Icon Border Thickness", setting = setting, options = opts })
								local f = CreateFrame("Frame", nil, iconPage, "SettingsSliderControlTemplate")
								f.GetElementData = function() return initSlider end
								f:SetPoint("TOPLEFT", 4, y.y)
								f:SetPoint("TOPRIGHT", -16, y.y)
								initSlider:InitFrame(f)
								if f.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(f.Text) end
								if panel and panel.ThemeSliderValue then panel.ThemeSliderValue(f) end
								_iconBorderThickFrame = f
								y.y = y.y - 34
							end
	
							-- Icon Border Tint (checkbox + inline color swatch)
							do
								local label = "Icon Border Tint"
								local function getTintEnabled()
									local t = ensureCastBarDB() or {}
									return not not t.iconBorderTintEnable
								end
								local function setTintEnabled(v)
									local t = ensureCastBarDB(); if not t then return end
									t.iconBorderTintEnable = (v == true)
									applyNow()
								end
								local function getTintColor()
									local t = ensureCastBarDB() or {}
									local c = t.iconBorderTintColor or {1,1,1,1}
									return { c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 }
								end
								local function setTintColor(r, g, b, a)
									local t = ensureCastBarDB(); if not t then return end
									t.iconBorderTintColor = { r or 1, g or 1, b or 1, a or 1 }
									applyNow()
								end
	
								local setting = CreateLocalSetting(label, "boolean", getTintEnabled, setTintEnabled, getTintEnabled())
								local initCb = CreateCheckboxWithSwatchInitializer(setting, label, getTintColor, setTintColor, 8)
								local row = CreateFrame("Frame", nil, iconPage, "SettingsCheckboxControlTemplate")
								row.GetElementData = function() return initCb end
								row:SetPoint("TOPLEFT", 4, y.y)
								row:SetPoint("TOPRIGHT", -16, y.y)
								initCb:InitFrame(row)
								if panel and panel.ApplyRobotoWhite then
									if row.Text then panel.ApplyRobotoWhite(row.Text) end
									local cb = row.Checkbox or row.CheckBox or (row.Control and row.Control.Checkbox)
									if cb and cb.Text then panel.ApplyRobotoWhite(cb.Text) end
								end
								_iconBorderTintFrame = row
							end
	
						-- Initialize gray-out state once when building
							refreshIconEnabledState()
						end
	
						-- Shared Spark tab: Hide Spark + Spark Color (Player/Target/Focus)
						-- NOTE: Defined outside the Player-only branch so it is available for Target/Focus
						-- Visibility tab builder (all Cast Bar units: Player, Target, Focus)
						-- Contains Spark visibility/color controls for all units, plus TextBorder control for Player only
						-- Visibility tab is on PageH for Player, PageG for Target/Focus (since they lack Cast Time Text tab)
						local function buildVisibilityTab()
							local uk = unitKey()
							if not uk then return end
	
							local isPlayer = (componentId == "ufPlayer")
	
							local function applyNow()
								if addon and addon.ApplyUnitFrameCastBarFor then addon.ApplyUnitFrameCastBarFor(uk) end
								if addon and addon.ApplyStyles then addon:ApplyStyles() end
							end
	
							local function ensureCastBarDB()
								local db = addon and addon.db and addon.db.profile
								if not db then return nil end
								db.unitFrames = db.unitFrames or {}
								db.unitFrames[uk] = db.unitFrames[uk] or {}
								db.unitFrames[uk].castBar = db.unitFrames[uk].castBar or {}
								return db.unitFrames[uk].castBar
							end
	
							local function isSparkEnabled()
								local t = ensureCastBarDB() or {}
								-- When the user checks "Hide Cast Bar Spark", we treat spark as disabled.
								return not not (not t.castBarSparkHidden)
							end
	
							-- Visibility tab is PageH for Player (8 tabs), PageG for Target/Focus (7 tabs)
							local visPage = isPlayer and frame.PageH or frame.PageG
							if not visPage then
								-- Defensive guard: if the template ever omits the page, fail safely.
								return
							end
	
							local y = { y = -50 }
	
							-- Local reference so we can gray-out the spark color row without rebuilding the category
							local _sparkColorFrame
							local function refreshSparkEnabledState()
								local enabled = isSparkEnabled()
	
								if _sparkColorFrame then
									if _sparkColorFrame.Control and _sparkColorFrame.Control.SetEnabled then
										_sparkColorFrame.Control:SetEnabled(enabled)
									end
									local lbl = _sparkColorFrame.Text or _sparkColorFrame.Label
									if lbl and lbl.SetTextColor then
										if enabled then lbl:SetTextColor(1, 1, 1, 1) else lbl:SetTextColor(0.6, 0.6, 0.6, 1) end
									end
									if _sparkColorFrame.ScooterInlineSwatch then
										local sw = _sparkColorFrame.ScooterInlineSwatch
										if sw.EnableMouse then sw:EnableMouse(enabled) end
										if sw.SetAlpha then sw:SetAlpha(enabled and 1 or 0.5) end
									end
								end
							end
	
							-- Hide Cast Bar Spark checkbox (all units)
							do
								local label = "Hide Cast Bar Spark"
								local function getter()
									local t = ensureCastBarDB() or {}
									return not not t.castBarSparkHidden
								end
								local function setter(v)
									local t = ensureCastBarDB(); if not t then return end
									t.castBarSparkHidden = (v == true)
									applyNow()
									-- Update gray-out state in-place to avoid panel flicker
									refreshSparkEnabledState()
								end
								local setting = CreateLocalSetting(label, "boolean", getter, setter, getter())
								local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = label, setting = setting, options = {} })
								local row = CreateFrame("Frame", nil, visPage, "SettingsCheckboxControlTemplate")
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
	
							-- Cast Bar Spark Color (dropdown + inline swatch, all units)
							do
								local function colorOpts()
									local c = Settings.CreateControlTextContainer()
									c:Add("default", "Default")
									c:Add("custom", "Custom")
									return c:GetData()
								end
								local function getMode()
									local t = ensureCastBarDB() or {}
									return t.castBarSparkColorMode or "default"
								end
								local function setMode(v)
									local t = ensureCastBarDB(); if not t then return end
									t.castBarSparkColorMode = v or "default"
									applyNow()
								end
								local function getTint()
									local t = ensureCastBarDB() or {}
									local c = t.castBarSparkTint or {1,1,1,1}
									return { c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 }
								end
								local function setTint(r,g,b,a)
									local t = ensureCastBarDB(); if not t then return end
									t.castBarSparkTint = { r or 1, g or 1, b or 1, a or 1 }
									applyNow()
								end
								_sparkColorFrame = panel.DropdownWithInlineSwatch(visPage, y, {
									label = "Cast Bar Spark Color",
									getMode = getMode,
									setMode = setMode,
									getColor = getTint,
									setColor = setTint,
									options = colorOpts,
									isEnabled = isSparkEnabled,
									insideButton = true,
								})
							end
	
							-- Initialize gray-out state once when building
							refreshSparkEnabledState()
	
							-- Hide Cast Bar Text Border checkbox (Player only - TextBorder only exists on unlocked Player Cast Bar)
							if isPlayer then
								local label = "Hide Cast Bar Text Border"
								local function getter()
									local t = ensureCastBarDB() or {}
									return not not t.hideTextBorder
								end
								local function setter(v)
									local t = ensureCastBarDB(); if not t then return end
									t.hideTextBorder = (v == true)
									applyNow()
								end
								local setting = CreateLocalSetting(label, "boolean", getter, setter, getter())
								local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = label, setting = setting, options = {} })
								local row = CreateFrame("Frame", nil, visPage, "SettingsCheckboxControlTemplate")
								row.GetElementData = function() return initCb end
								row:SetPoint("TOPLEFT", 4, y.y)
								row:SetPoint("TOPRIGHT", -16, y.y)
								initCb:InitFrame(row)
								if panel and panel.ApplyRobotoWhite then
									if row.Text then panel.ApplyRobotoWhite(row.Text) end
									local cb = row.Checkbox or row.CheckBox or (row.Control and row.Control.Checkbox)
									if cb and cb.Text then panel.ApplyRobotoWhite(cb.Text) end
								end
	
								-- Add info icon tooltip to the left of the label
								if panel and panel.CreateInfoIcon and row.Text then
									local tooltipText = "Hides the border frame around the cast bar text. This setting only takes effect when 'Lock to Player Frame' is unchecked (Cast Bar is freely positioned), as the text border only appears in that mode."
									if not row.ScooterTextBorderInfoIcon then
										row.ScooterTextBorderInfoIcon = panel.CreateInfoIcon(row, tooltipText, "RIGHT", "LEFT", -5, 0, 20)
										-- Position to the left of the label text
										C_Timer.After(0, function()
											if row.ScooterTextBorderInfoIcon and row.Text then
												row.ScooterTextBorderInfoIcon:ClearAllPoints()
												row.ScooterTextBorderInfoIcon:SetPoint("RIGHT", row.Text, "LEFT", -5, 0)
											end
										end)
									end
								end
	
								y.y = y.y - 34
							end
	
							-- Hide Channeling Shadow checkbox (Player only - ChannelShadow only exists on Player Cast Bar)
							if isPlayer then
								local label = "Hide Channeling Shadow"
								local function getter()
									local t = ensureCastBarDB() or {}
									return not not t.hideChannelingShadow
								end
								local function setter(v)
									local t = ensureCastBarDB(); if not t then return end
									t.hideChannelingShadow = (v == true)
									applyNow()
								end
								local setting = CreateLocalSetting(label, "boolean", getter, setter, getter())
								local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = label, setting = setting, options = {} })
								local row = CreateFrame("Frame", nil, visPage, "SettingsCheckboxControlTemplate")
								row.GetElementData = function() return initCb end
								row:SetPoint("TOPLEFT", 4, y.y)
								row:SetPoint("TOPRIGHT", -16, y.y)
								initCb:InitFrame(row)
								if panel and panel.ApplyRobotoWhite then
									if row.Text then panel.ApplyRobotoWhite(row.Text) end
									local cb = row.Checkbox or row.CheckBox or (row.Control and row.Control.Checkbox)
									if cb and cb.Text then panel.ApplyRobotoWhite(cb.Text) end
								end
	
								-- Add info icon tooltip to the left of the label
								if panel and panel.CreateInfoIcon and row.Text then
									local tooltipText = "Hides the shadow effect that appears behind the cast bar during channeled spells."
									if not row.ScooterChannelShadowInfoIcon then
										row.ScooterChannelShadowInfoIcon = panel.CreateInfoIcon(row, tooltipText, "RIGHT", "LEFT", -5, 0, 20)
										C_Timer.After(0, function()
											if row.ScooterChannelShadowInfoIcon and row.Text then
												row.ScooterChannelShadowInfoIcon:ClearAllPoints()
												row.ScooterChannelShadowInfoIcon:SetPoint("RIGHT", row.Text, "LEFT", -5, 0)
											end
										end)
									end
								end
	
								y.y = y.y - 34
							end
						end
	
						-- PLAYER CAST BAR (Edit Mode–managed)
						if componentId == "ufPlayer" then
							-- Utilities reused from Parent Frame positioning
							local function getUiScale() return (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1 end
							local function uiUnitsToPixels(u) local s = getUiScale(); return math.floor((u * s) + 0.5) end
							local function pixelsToUiUnits(px) local s = getUiScale(); if s == 0 then return 0 end; return px / s end
	
							local function getCastBar()
								local mgr = _G.EditModeManagerFrame
								local EMSys = _G.Enum and _G.Enum.EditModeSystem
								if not (mgr and EMSys and mgr.GetRegisteredSystemFrame) then return nil end
								return mgr:GetRegisteredSystemFrame(EMSys.CastBar, nil)
							end
	
							-- Positioning tab content (PageA)
							local yA = { y = -50 }
	
							-- Local refs so we can gray-out the offset sliders based on the lock state
							local _offsetXFrame, _offsetYFrame
							-- Local ref for Spell Name Backdrop checkbox (Player-only, Spell Name Text tab)
							local _snBackdropFrame
	
							local lockSetting -- forward-declared so isLocked/refresh can see it
							local function isLocked()
								return (lockSetting and lockSetting.GetValue and lockSetting:GetValue()) and true or false
							end
	
							local function refreshOffsetEnabledState()
								local enabled = isLocked()
								local function applyToRow(row)
									if not row then return end
									if row.Control and row.Control.SetEnabled then
										row.Control:SetEnabled(enabled)
									end
									local lbl = row.Text or row.Label
									if lbl and lbl.SetTextColor then
										lbl:SetTextColor(enabled and 1 or 0.6, enabled and 1 or 0.6, enabled and 1 or 0.6, 1)
									end
								end
								applyToRow(_offsetXFrame)
								applyToRow(_offsetYFrame)
							end
	
							-- Player-only: grey out the Spell Name Backdrop checkbox when the cast bar
							-- is locked to the Player frame (the backdrop only appears when unlocked).
							local function refreshBackdropLockState()
								if not _snBackdropFrame then return end
								local locked = isLocked()
								local enabled = not locked
								local cb = _snBackdropFrame.Checkbox or _snBackdropFrame.CheckBox or (_snBackdropFrame.Control and _snBackdropFrame.Control.Checkbox)
								if cb and cb.SetEnabled then
									cb:SetEnabled(enabled)
								elseif cb and cb.Enable and cb.Disable then
									if enabled then cb:Enable() else cb:Disable() end
								end
								local lbl = _snBackdropFrame.Text or _snBackdropFrame.Label or (cb and cb.Text)
								if lbl and lbl.SetTextColor then
									lbl:SetTextColor(enabled and 1 or 0.6, enabled and 1 or 0.6, enabled and 1 or 0.6, 1)
								end
							end
	
							local function addCheckboxLock()
								local label = "Lock to Player Frame"
								local function getter()
									local frame = getCastBar()
									local sid = _G.Enum and _G.Enum.EditModeCastBarSetting and _G.Enum.EditModeCastBarSetting.LockToPlayerFrame
									if frame and sid and addon and addon.EditMode and addon.EditMode.GetSetting then
										local v = addon.EditMode.GetSetting(frame, sid)
										return (v and v ~= 0) and true or false
									end
									return false
								end
								local function setter(b)
									local val = (b and true) and 1 or 0
									-- Fix note (2025-11-06): Keep Cast Bar <-> Unit Frame in lockstep by writing to
									-- Cast Bar [LockToPlayerFrame] and mirroring to Player Unit Frame [CastBarUnderneath].
									-- Use the centralized WriteSetting helper so SaveOnly/ApplyChanges and panel suppression
									-- behave consistently for all Edit Mode–controlled settings.
									-- Write to Cast Bar system
									do
										local frame = getCastBar()
										local sid = _G.Enum and _G.Enum.EditModeCastBarSetting and _G.Enum.EditModeCastBarSetting.LockToPlayerFrame
										if frame and sid and addon and addon.EditMode then
											if addon.EditMode.WriteSetting then
												-- Let the centralized WriteSetting helper perform SaveOnly + a coalesced
												-- ApplyChanges so Edit Mode's own UI stays in sync with ScooterMod. The
												-- custom right pane prevents the earlier flicker we saw when applying.
												addon.EditMode.WriteSetting(frame, sid, val, {
													updaters        = { "UpdateSystemSettingLockToPlayerFrame", "UpdateSystem", "RefreshLayout" },
													suspendDuration = 0.4,
												})
											elseif addon.EditMode.SetSetting then
												addon.EditMode.SetSetting(frame, sid, val)
												if type(frame.UpdateSystemSettingLockToPlayerFrame) == "function" then pcall(frame.UpdateSystemSettingLockToPlayerFrame, frame) end
												if type(frame.UpdateSystem) == "function" then pcall(frame.UpdateSystem, frame) end
												if type(frame.RefreshLayout) == "function" then pcall(frame.RefreshLayout, frame) end
												if addon.EditMode.SaveOnly then addon.EditMode.SaveOnly() end
												-- Avoid triggering ApplyChanges here; the targeted updaters above are sufficient.
											end
										end
									end
									-- Mirror to Player Unit Frame setting [Cast Bar Underneath] to keep both UIs in sync
									do
										local mgr = _G.EditModeManagerFrame
										local EMSys = _G.Enum and _G.Enum.EditModeSystem
										local EMUF = _G.Enum and _G.Enum.EditModeUnitFrameSystemIndices
										local frameUF = (mgr and EMSys and EMUF and mgr.GetRegisteredSystemFrame) and mgr:GetRegisteredSystemFrame(EMSys.UnitFrame, EMUF.Player) or nil
										local UFSetting = _G.Enum and _G.Enum.EditModeUnitFrameSetting
										local sidUF = UFSetting and UFSetting.CastBarUnderneath or 1
										if frameUF and sidUF and addon and addon.EditMode then
											if addon.EditMode.WriteSetting then
												-- Mirror Player Unit Frame's CastBarUnderneath setting as a normal
												-- Edit Mode write so both UIs share the same persisted state.
												addon.EditMode.WriteSetting(frameUF, sidUF, val, {
													updaters = { "UpdateSystem", "RefreshLayout" },
												})
											elseif addon.EditMode.SetSetting then
												addon.EditMode.SetSetting(frameUF, sidUF, val)
												if type(frameUF.UpdateSystem) == "function" then pcall(frameUF.UpdateSystem, frameUF) end
												if type(frameUF.RefreshLayout) == "function" then pcall(frameUF.RefreshLayout, frameUF) end
											end
										end
									end
	
									-- When unlocking the Player Cast Bar (val == 0), enforce Disable Icon in
									-- ScooterMod's DB so our icon border logic does not draw when Blizzard
									-- hides the icon in free-floating mode.
									do
										local db = addon and addon.db and addon.db.profile
										if db then
											db.unitFrames = db.unitFrames or {}
											db.unitFrames.Player = db.unitFrames.Player or {}
											db.unitFrames.Player.castBar = db.unitFrames.Player.castBar or {}
											if val == 0 then
												db.unitFrames.Player.castBar.iconDisabled = true
											end
										end
									end
	
									-- Re-style immediately so icon visibility/borders and offsets match the new lock state.
									-- Limit this to the Player cast bar only to avoid triggering broader panel refresh
									-- machinery that can cause visible flicker in the settings list.
									if addon and addon.ApplyUnitFrameCastBarFor then
										addon.ApplyUnitFrameCastBarFor("Player")
									end
	
									-- Update offset slider enabled state to reflect the new lock mode without
									-- forcing a full category rebuild (which can cause visible flicker).
									if refreshOffsetEnabledState then
										refreshOffsetEnabledState()
									end
									-- Update Spell Name Backdrop checkbox enabled state so it is only interactive
									-- when the cast bar is unlocked (backdrop visible).
									if refreshBackdropLockState then
										refreshBackdropLockState()
									end
								end
								local setting = CreateLocalSetting(label, "boolean", getter, setter, getter())
								local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = label, setting = setting, options = {} })
								local row = CreateFrame("Frame", nil, frame.PageA, "SettingsCheckboxControlTemplate")
								row.GetElementData = function() return initCb end
								row:SetPoint("TOPLEFT", 4, yA.y)
								row:SetPoint("TOPRIGHT", -16, yA.y)
								initCb:InitFrame(row)
								if panel and panel.ApplyRobotoWhite then
									if row.Text then panel.ApplyRobotoWhite(row.Text) end
									local cb = row.Checkbox or row.CheckBox or (row.Control and row.Control.Checkbox)
									if cb and cb.Text then panel.ApplyRobotoWhite(cb.Text) end
								end
								yA.y = yA.y - 34
								return setting
							end
	
							lockSetting = addCheckboxLock()
	
							-- X/Y Offset sliders (only applied when locked; greyed out when unlocked)
							do
								local function applyNow()
									if addon and addon.ApplyUnitFrameCastBarFor then addon.ApplyUnitFrameCastBarFor("Player") end
									if addon and addon.ApplyStyles then addon:ApplyStyles() end
								end
	
								_offsetXFrame = addSlider(
									frame.PageA,
									"X Offset",
									-150,
									150,
									1,
									function()
										local t = ensureCastBarDB() or {}
										return tonumber(t.offsetX) or 0
									end,
									function(v)
										local t = ensureCastBarDB(); if not t then return end
										t.offsetX = tonumber(v) or 0
										applyNow()
									end,
									yA
								)
	
								_offsetYFrame = addSlider(
									frame.PageA,
									"Y Offset",
									-150,
									150,
									1,
									function()
										local t = ensureCastBarDB() or {}
										return tonumber(t.offsetY) or 0
									end,
									function(v)
										local t = ensureCastBarDB(); if not t then return end
										t.offsetY = tonumber(v) or 0
										applyNow()
									end,
									yA
								)
	
								-- Initialize grey-out state once when building
								if refreshOffsetEnabledState then
									refreshOffsetEnabledState()
								end
							end
	
						-- Sizing tab (PageB): Bar Size (Scale) 100..150 step 10
						do
							local y = { y = -50 }
							local function fmtInt(v) return tostring(math.floor((tonumber(v) or 0) + 0.5)) end
							local options = Settings.CreateSliderOptions(100, 150, 10)
							options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return fmtInt(v) end)
							local label = "Bar Size (Scale)"
							local function getCastBar()
								local mgr = _G.EditModeManagerFrame
								local EMSys = _G.Enum and _G.Enum.EditModeSystem
								if not (mgr and EMSys and mgr.GetRegisteredSystemFrame) then return nil end
								return mgr:GetRegisteredSystemFrame(EMSys.CastBar, nil)
							end
							local function getter()
								local frame = getCastBar()
								local sid = _G.Enum and _G.Enum.EditModeCastBarSetting and _G.Enum.EditModeCastBarSetting.BarSize
								if frame and sid and addon and addon.EditMode and addon.EditMode.GetSetting then
									local v = addon.EditMode.GetSetting(frame, sid)
									if v == nil then return 100 end
									return math.max(100, math.min(150, v))
								end
								return 100
							end
							local function setter(raw)
								local frame = getCastBar()
								local sid = _G.Enum and _G.Enum.EditModeCastBarSetting and _G.Enum.EditModeCastBarSetting.BarSize
								local val = tonumber(raw) or 100
								val = math.floor(math.max(100, math.min(150, val)) / 10 + 0.5) * 10
								if frame and sid and addon and addon.EditMode then
									if addon.EditMode.WriteSetting then
										addon.EditMode.WriteSetting(frame, sid, val, {
											updaters        = { "UpdateSystemSettingBarSize" },
											suspendDuration = 0.25,
										})
									elseif addon.EditMode.SetSetting then
										addon.EditMode.SetSetting(frame, sid, val)
										if type(frame.UpdateSystemSettingBarSize) == "function" then pcall(frame.UpdateSystemSettingBarSize, frame) end
										if addon.EditMode.SaveOnly then addon.EditMode.SaveOnly() end
										if addon.EditMode.RequestApplyChanges then addon.EditMode.RequestApplyChanges(0.2) end
									end
								end
							end
							local setting = CreateLocalSetting(label, "number", getter, setter, getter())
							local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = label, setting = setting, options = options })
							local f = CreateFrame("Frame", nil, frame.PageB, "SettingsSliderControlTemplate")
							f.GetElementData = function() return initSlider end
							f:SetPoint("TOPLEFT", 4, y.y)
							f:SetPoint("TOPRIGHT", -16, y.y)
							initSlider:InitFrame(f)
							if f.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(f.Text) end
							if panel and panel.ThemeSliderValue then panel.ThemeSliderValue(f) end
							y.y = y.y - 34
						end
	
						-- Bar Width slider (Player only for now, percent of original width)
						do
							local y = { y = -90 } -- place just below Bar Size (Scale)
							local function fmtInt(v) return tostring(math.floor((tonumber(v) or 0) + 0.5)) end
							local options = Settings.CreateSliderOptions(50, 150, 1)
							options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return fmtInt(v) end)
	
							local label = "Bar Width (%)"
							local function getter()
								local db = addon and addon.db and addon.db.profile
								if not db then return 100 end
								db.unitFrames = db.unitFrames or {}
								db.unitFrames.Player = db.unitFrames.Player or {}
								db.unitFrames.Player.castBar = db.unitFrames.Player.castBar or {}
								local t = db.unitFrames.Player.castBar
								return tonumber(t.widthPct) or 100
							end
							local function setter(v)
								local db = addon and addon.db and addon.db.profile
								if not db then return end
								db.unitFrames = db.unitFrames or {}
								db.unitFrames.Player = db.unitFrames.Player or {}
								db.unitFrames.Player.castBar = db.unitFrames.Player.castBar or {}
								local t = db.unitFrames.Player.castBar
								local val = tonumber(v) or 100
								if val < 50 then val = 50 elseif val > 150 then val = 150 end
								t.widthPct = val
								if addon and addon.ApplyUnitFrameCastBarFor then addon.ApplyUnitFrameCastBarFor("Player") end
								if addon and addon.ApplyStyles then addon:ApplyStyles() end
							end
	
							local setting = CreateLocalSetting(label, "number", getter, setter, getter())
							local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = label, setting = setting, options = options })
							local f = CreateFrame("Frame", nil, frame.PageB, "SettingsSliderControlTemplate")
							f.GetElementData = function() return initSlider end
							f:SetPoint("TOPLEFT", 4, y.y)
							f:SetPoint("TOPRIGHT", -16, y.y)
							initSlider:InitFrame(f)
							if f.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(f.Text) end
							if panel and panel.ThemeSliderValue then panel.ThemeSliderValue(f) end
						end
	
						-- Spell Name Text tab (PageF): styling controls
						-- Player: Disable Spell Name Text + Hide Backdrop + full styling
						-- Target/Focus: Hide Border + full styling (implemented in the else branch below)
						do
							if unitKey() == "Player" then
								local function applyNow()
									if addon and addon.ApplyUnitFrameCastBarFor then addon.ApplyUnitFrameCastBarFor("Player") end
									if addon and addon.ApplyStyles then addon:ApplyStyles() end
								end
								local function fontOptions()
									return addon.BuildFontOptionsContainer()
								end
								local y = { y = -50 }
	
								local function isDisabled()
									local t = ensureCastBarDB() or {}
									return not not t.spellNameTextDisabled
								end
	
								-- Local references so we can gray-out rows without rebuilding the category
								local _snFontFrame, _snStyleFrame, _snSizeFrame, _snColorFrame, _snOffsetXFrame, _snOffsetYFrame
	
								local function refreshSpellNameDisabledState()
									local disabled = isDisabled()
	
									-- Font
									if _snFontFrame then
										if _snFontFrame.Control and _snFontFrame.Control.SetEnabled then
											_snFontFrame.Control:SetEnabled(not disabled)
										end
										local lbl = _snFontFrame.Text or _snFontFrame.Label
										if lbl and lbl.SetTextColor then
											lbl:SetTextColor(disabled and 0.6 or 1, disabled and 0.6 or 1, disabled and 0.6 or 1, 1)
										end
									end
	
									-- Font Style
									if _snStyleFrame then
										if _snStyleFrame.Control and _snStyleFrame.Control.SetEnabled then
											_snStyleFrame.Control:SetEnabled(not disabled)
										end
										local lbl = _snStyleFrame.Text or _snStyleFrame.Label
										if lbl and lbl.SetTextColor then
											lbl:SetTextColor(disabled and 0.6 or 1, disabled and 0.6 or 1, disabled and 0.6 or 1, 1)
										end
									end
	
									-- Font Size
									if _snSizeFrame then
										if _snSizeFrame.Control and _snSizeFrame.Control.SetEnabled then
											_snSizeFrame.Control:SetEnabled(not disabled)
										end
										if _snSizeFrame.Text and _snSizeFrame.Text.SetTextColor then
											_snSizeFrame.Text:SetTextColor(disabled and 0.6 or 1, disabled and 0.6 or 1, disabled and 0.6 or 1, 1)
										end
									end
	
									-- Font Color (dropdown + inline swatch)
									if _snColorFrame then
										if _snColorFrame.Control and _snColorFrame.Control.SetEnabled then
											_snColorFrame.Control:SetEnabled(not disabled)
										end
										local lbl = _snColorFrame.Text or _snColorFrame.Label
										if lbl and lbl.SetTextColor then
											lbl:SetTextColor(disabled and 0.6 or 1, disabled and 0.6 or 1, disabled and 0.6 or 1, 1)
										end
										if _snColorFrame.ScooterInlineSwatch and _snColorFrame.ScooterInlineSwatch.EnableMouse then
											_snColorFrame.ScooterInlineSwatch:EnableMouse(not disabled)
											if _snColorFrame.ScooterInlineSwatch.SetAlpha then
												_snColorFrame.ScooterInlineSwatch:SetAlpha(disabled and 0.5 or 1)
											end
										end
									end
	
									-- X Offset
									if _snOffsetXFrame then
										if _snOffsetXFrame.Control and _snOffsetXFrame.Control.SetEnabled then
											_snOffsetXFrame.Control:SetEnabled(not disabled)
										end
										if _snOffsetXFrame.Text and _snOffsetXFrame.Text.SetTextColor then
											_snOffsetXFrame.Text:SetTextColor(disabled and 0.6 or 1, disabled and 0.6 or 1, disabled and 0.6 or 1, 1)
										end
									end
	
									-- Y Offset
									if _snOffsetYFrame then
										if _snOffsetYFrame.Control and _snOffsetYFrame.Control.SetEnabled then
											_snOffsetYFrame.Control:SetEnabled(not disabled)
										end
										if _snOffsetYFrame.Text and _snOffsetYFrame.Text.SetTextColor then
											_snOffsetYFrame.Text:SetTextColor(disabled and 0.6 or 1, disabled and 0.6 or 1, disabled and 0.6 or 1, 1)
										end
									end
								end
	
								-- Disable Spell Name Text checkbox
								do
									local label = "Disable Spell Name Text"
									local function getter()
										local t = ensureCastBarDB() or {}
										return not not t.spellNameTextDisabled
									end
									local function setter(v)
										local t = ensureCastBarDB(); if not t then return end
										t.spellNameTextDisabled = (v == true)
										applyNow()
										refreshSpellNameDisabledState()
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
									end
									y.y = y.y - 34
								end
	
								-- Hide Spell Name Backdrop checkbox (Player cast bar only)
								do
									local label = "Hide Spell Name Backdrop"
									local function getter()
										local t = ensureCastBarDB() or {}
										return not not t.hideSpellNameBackdrop
									end
									local function setter(v)
										local t = ensureCastBarDB(); if not t then return end
										t.hideSpellNameBackdrop = (v == true)
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
									end
	
									-- Attach a contextual info icon to the label explaining when the backdrop exists.
									if panel and panel.CreateInfoIconForLabel then
										local cb = row.Checkbox or row.CheckBox or (row.Control and row.Control.Checkbox)
										local labelFS = (cb and cb.Text) or row.Text
										if labelFS then
											local tooltipText = "When \'Lock to Player Frame\' is un-checked in the Cast Bar > Positioning tab, Blizzard shows a decorative strip behind the spell name. Enable this to hide that backdrop."
											local icon = panel.CreateInfoIconForLabel(labelFS, tooltipText, 5, 0, 32)
											if _G.C_Timer and _G.C_Timer.After then
												_G.C_Timer.After(0, function()
													if not icon or not labelFS then return end
													icon:ClearAllPoints()
													local textWidth = labelFS.GetStringWidth and labelFS:GetStringWidth() or 0
													-- Nudge slightly closer to the label text so it sits comfortably
													-- between the label and the checkbox without crowding the checkbox.
													if textWidth and textWidth > 0 then
														icon:SetPoint("LEFT", labelFS, "LEFT", textWidth + 2, 0)
													else
														icon:SetPoint("LEFT", labelFS, "RIGHT", 2, 0)
													end
												end)
											end
										end
									end
	
									_snBackdropFrame = row
									-- Initial lock-based enable/disable state; this does NOT depend on the
									-- Disable Spell Name Text checkbox and should remain independent.
									if refreshBackdropLockState then
										refreshBackdropLockState()
									end
	
									y.y = y.y - 34
								end
	
								-- Spell Name Font
								_snFontFrame = addDropdown(frame.PageF, "Spell Name Font", fontOptions,
									function()
										local t = ensureCastBarDB() or {}
										local s = t.spellNameText or {}
										return s.fontFace or "FRIZQT__"
									end,
									function(v)
										local t = ensureCastBarDB(); if not t then return end
										t.spellNameText = t.spellNameText or {}
										t.spellNameText.fontFace = v
										applyNow()
									end,
									y)
	
								-- Spell Name Font Style
								_snStyleFrame = addStyle(frame.PageF, "Spell Name Font Style",
									function()
										local t = ensureCastBarDB() or {}
										local s = t.spellNameText or {}
										return s.style or "OUTLINE"
									end,
									function(v)
										local t = ensureCastBarDB(); if not t then return end
										t.spellNameText = t.spellNameText or {}
										t.spellNameText.style = v
										applyNow()
									end,
									y)
	
								-- Spell Name Font Size
								_snSizeFrame = addSlider(frame.PageF, "Spell Name Font Size", 6, 48, 1,
									function()
										local t = ensureCastBarDB() or {}
										local s = t.spellNameText or {}
										return tonumber(s.size) or 14
									end,
									function(v)
										local t = ensureCastBarDB(); if not t then return end
										t.spellNameText = t.spellNameText or {}
										t.spellNameText.size = tonumber(v) or 14
										applyNow()
									end,
									y)
	
								-- Spell Name Font Color
								_snColorFrame = addColor(frame.PageF, "Spell Name Font Color", true,
									function()
										local t = ensureCastBarDB() or {}
										local s = t.spellNameText or {}
										local c = s.color or {1,1,1,1}
										return c[1], c[2], c[3], c[4]
									end,
									function(r,g,b,a)
										local t = ensureCastBarDB(); if not t then return end
										t.spellNameText = t.spellNameText or {}
										t.spellNameText.color = {r or 1, g or 1, b or 1, a or 1}
										applyNow()
									end,
									y)
	
								-- Spell Name X Offset
								_snOffsetXFrame = addSlider(frame.PageF, "Spell Name X Offset", -100, 100, 1,
									function()
										local t = ensureCastBarDB() or {}
										local s = t.spellNameText or {}
										local o = s.offset or {}
										return tonumber(o.x) or 0
									end,
									function(v)
										local t = ensureCastBarDB(); if not t then return end
										t.spellNameText = t.spellNameText or {}
										t.spellNameText.offset = t.spellNameText.offset or {}
										t.spellNameText.offset.x = tonumber(v) or 0
										applyNow()
									end,
									y)
	
								-- Spell Name Y Offset
								_snOffsetYFrame = addSlider(frame.PageF, "Spell Name Y Offset", -100, 100, 1,
									function()
										local t = ensureCastBarDB() or {}
										local s = t.spellNameText or {}
										local o = s.offset or {}
										return tonumber(o.y) or 0
									end,
									function(v)
										local t = ensureCastBarDB(); if not t then return end
										t.spellNameText = t.spellNameText or {}
										t.spellNameText.offset = t.spellNameText.offset or {}
										t.spellNameText.offset.y = tonumber(v) or 0
										applyNow()
									end,
									y)
	
								-- Initialize gray-out state
								refreshSpellNameDisabledState()
							end
						end
	
						-- Cast Time Text tab (PageG): Show Cast Time checkbox + styling (Player only)
						do
							local y = { y = -50 }
							local function applyNow()
								if addon and addon.ApplyUnitFrameCastBarFor then addon.ApplyUnitFrameCastBarFor("Player") end
								if addon and addon.ApplyStyles then addon:ApplyStyles() end
							end
							local label = "Show Cast Time"
							local function getCastBar()
								local mgr = _G.EditModeManagerFrame
								local EMSys = _G.Enum and _G.Enum.EditModeSystem
								if not (mgr and EMSys and mgr.GetRegisteredSystemFrame) then return nil end
								return mgr:GetRegisteredSystemFrame(EMSys.CastBar, nil)
							end
							local function getter()
								local frameCB = getCastBar()
								local sid = _G.Enum and _G.Enum.EditModeCastBarSetting and _G.Enum.EditModeCastBarSetting.ShowCastTime
								if frameCB and sid and addon and addon.EditMode and addon.EditMode.GetSetting then
									local v = addon.EditMode.GetSetting(frameCB, sid)
									return (tonumber(v) or 0) == 1
								end
								return false
							end
							local function setter(b)
								local frameCB = getCastBar()
								local sid = _G.Enum and _G.Enum.EditModeCastBarSetting and _G.Enum.EditModeCastBarSetting.ShowCastTime
								local val = (b and true) and 1 or 0
								if frameCB and sid and addon and addon.EditMode then
									if addon.EditMode.WriteSetting then
										addon.EditMode.WriteSetting(frameCB, sid, val, {
											updaters        = { "UpdateSystemSettingShowCastTime" },
											suspendDuration = 0.25,
										})
									elseif addon.EditMode.SetSetting then
										addon.EditMode.SetSetting(frameCB, sid, val)
										if type(frameCB.UpdateSystemSettingShowCastTime) == "function" then pcall(frameCB.UpdateSystemSettingShowCastTime, frameCB) end
										if addon.EditMode.SaveOnly then addon.EditMode.SaveOnly() end
										if addon.EditMode.RequestApplyChanges then addon.EditMode.RequestApplyChanges(0.2) end
									end
									-- Reapply Scooter styling so Cast Time text reflects current settings immediately
									applyNow()
								end
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
							end
							y.y = y.y - 34
	
							-- Cast Time Font
							local function fontOptions()
								return addon.BuildFontOptionsContainer()
							end
							addDropdown(frame.PageG, "Cast Time Font", fontOptions,
								function()
									local t = ensureCastBarDB() or {}
									local s = t.castTimeText or {}
									return s.fontFace or "FRIZQT__"
								end,
								function(v)
									local t = ensureCastBarDB(); if not t then return end
									t.castTimeText = t.castTimeText or {}
									t.castTimeText.fontFace = v
									applyNow()
								end,
								y)
	
							-- Cast Time Font Style
							addStyle(frame.PageG, "Cast Time Font Style",
								function()
									local t = ensureCastBarDB() or {}
									local s = t.castTimeText or {}
									return s.style or "OUTLINE"
								end,
								function(v)
									local t = ensureCastBarDB(); if not t then return end
									t.castTimeText = t.castTimeText or {}
									t.castTimeText.style = v
									applyNow()
								end,
								y)
	
							-- Cast Time Font Size
							addSlider(frame.PageG, "Cast Time Font Size", 6, 48, 1,
								function()
									local t = ensureCastBarDB() or {}
									local s = t.castTimeText or {}
									return tonumber(s.size) or 14
								end,
								function(v)
									local t = ensureCastBarDB(); if not t then return end
									t.castTimeText = t.castTimeText or {}
									t.castTimeText.size = tonumber(v) or 14
									applyNow()
								end,
								y)
	
							-- Cast Time Font Color
							addColor(frame.PageG, "Cast Time Font Color", true,
								function()
									local t = ensureCastBarDB() or {}
									local s = t.castTimeText or {}
									local c = s.color or {1,1,1,1}
									return c[1], c[2], c[3], c[4]
								end,
								function(r,g,b,a)
									local t = ensureCastBarDB(); if not t then return end
									t.castTimeText = t.castTimeText or {}
									t.castTimeText.color = {r or 1, g or 1, b or 1, a or 1}
									applyNow()
								end,
								y)
	
							-- Cast Time X Offset
							addSlider(frame.PageG, "Cast Time X Offset", -100, 100, 1,
								function()
									local t = ensureCastBarDB() or {}
									local s = t.castTimeText or {}
									local o = s.offset or {}
									return tonumber(o.x) or 0
								end,
								function(v)
									local t = ensureCastBarDB(); if not t then return end
									t.castTimeText = t.castTimeText or {}
									t.castTimeText.offset = t.castTimeText.offset or {}
									t.castTimeText.offset.x = tonumber(v) or 0
									applyNow()
								end,
								y)
	
								-- Cast Time Y Offset
							addSlider(frame.PageG, "Cast Time Y Offset", -100, 100, 1,
								function()
									local t = ensureCastBarDB() or {}
									local s = t.castTimeText or {}
									local o = s.offset or {}
									return tonumber(o.y) or 0
								end,
								function(v)
									local t = ensureCastBarDB(); if not t then return end
									t.castTimeText = t.castTimeText or {}
									t.castTimeText.offset = t.castTimeText.offset or {}
									t.castTimeText.offset.y = tonumber(v) or 0
									applyNow()
								end,
								y)
						end
	
						-- TARGET/FOCUS CAST BAR (addon-only X/Y offsets + width)
						else
							local uk = unitKey()
							if uk == "Target" or uk == "Focus" then
								local function applyNow()
									if addon and addon.ApplyUnitFrameCastBarFor then addon.ApplyUnitFrameCastBarFor(uk) end
									if addon and addon.ApplyStyles then addon:ApplyStyles() end
								end
								-- PageA: Positioning (Anchor Mode dropdown + X/Y offsets)
								do
									local y = { y = -50 }
	
									-- Anchor Position to... dropdown
									do
										local label = "Anchor Position to..."
										local function anchorModeOptions()
											local container = Settings.CreateControlTextContainer()
											container:Add("default", "Default")
											container:Add("healthTop", "Health Bar (Top)")
											container:Add("healthBottom", "Health Bar (Bottom)")
											container:Add("powerTop", "Power Bar (Top)")
											container:Add("powerBottom", "Power Bar (Bottom)")
											return container:GetData()
										end
										local function getter()
											local t = ensureCastBarDB() or {}
											return t.anchorMode or "default"
										end
										local function setter(v)
											local t = ensureCastBarDB(); if not t then return end
											t.anchorMode = v or "default"
											applyNow()
										end
										addDropdown(frame.PageA, label, anchorModeOptions, getter, setter, y)
									end
	
									-- X Offset slider (-150..150 px)
									addSlider(frame.PageA, "X Offset", -150, 150, 1,
										function()
											local t = ensureCastBarDB() or {}
											return tonumber(t.offsetX) or 0
										end,
										function(v)
											local t = ensureCastBarDB(); if not t then return end
											t.offsetX = tonumber(v) or 0
											applyNow()
										end,
										y)
	
									-- Y Offset slider (-150..150 px)
									addSlider(frame.PageA, "Y Offset", -150, 150, 1,
										function()
											local t = ensureCastBarDB() or {}
											return tonumber(t.offsetY) or 0
										end,
										function(v)
											local t = ensureCastBarDB(); if not t then return end
											t.offsetY = tonumber(v) or 0
											applyNow()
										end,
										y)
								end
	
								-- PageB: Sizing (Cast Bar Scale + Bar Width %)
								do
									local y = { y = -50 }
									local function fmtInt(v) return tostring(math.floor((tonumber(v) or 0) + 0.5)) end
	
									-- Cast Bar Scale slider (50-150%)
									do
										local options = Settings.CreateSliderOptions(50, 150, 1)
										options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return fmtInt(v) end)
	
										local label = "Cast Bar Scale (%)"
										local function getter()
											local t = ensureCastBarDB() or {}
											return tonumber(t.castBarScale) or 100
										end
										local function setter(v)
											local t = ensureCastBarDB(); if not t then return end
											local val = tonumber(v) or 100
											if val < 50 then val = 50 elseif val > 150 then val = 150 end
											t.castBarScale = val
											applyNow()
										end
	
										local setting = CreateLocalSetting(label, "number", getter, setter, getter())
										local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = label, setting = setting, options = options })
										local f = CreateFrame("Frame", nil, frame.PageB, "SettingsSliderControlTemplate")
										f.GetElementData = function() return initSlider end
										f:SetPoint("TOPLEFT", 4, y.y)
										f:SetPoint("TOPRIGHT", -16, y.y)
										initSlider:InitFrame(f)
										if f.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(f.Text) end
										if panel and panel.ThemeSliderValue then panel.ThemeSliderValue(f) end
										y.y = y.y - 34
									end
	
									-- Bar Width slider (50-150%)
									do
										local options = Settings.CreateSliderOptions(50, 150, 1)
										options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return fmtInt(v) end)
	
										local label = "Bar Width (%)"
										local function getter()
											local t = ensureCastBarDB() or {}
											return tonumber(t.widthPct) or 100
										end
										local function setter(v)
											local t = ensureCastBarDB(); if not t then return end
											local val = tonumber(v) or 100
											if val < 50 then val = 50 elseif val > 150 then val = 150 end
											t.widthPct = val
											applyNow()
										end
	
										local setting = CreateLocalSetting(label, "number", getter, setter, getter())
										local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = label, setting = setting, options = options })
										local f = CreateFrame("Frame", nil, frame.PageB, "SettingsSliderControlTemplate")
										f.GetElementData = function() return initSlider end
										f:SetPoint("TOPLEFT", 4, y.y)
										f:SetPoint("TOPRIGHT", -16, y.y)
										initSlider:InitFrame(f)
										if f.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(f.Text) end
										if panel and panel.ThemeSliderValue then panel.ThemeSliderValue(f) end
									end
								end
	
								-- PageF: Spell Name Text (Target/Focus Cast Bars)
								-- Targets: TargetFrameSpellBar.Text / FocusFrameSpellBar.Text
								-- Border: TargetFrameSpellBar.TextBorder / FocusFrameSpellBar.TextBorder
								do
									local function fontOptions()
										return addon.BuildFontOptionsContainer()
									end
									local y = { y = -50 }
	
									-- Hide Spell Name Border checkbox (first control)
									do
										local label = "Hide Spell Name Border"
										local function getter()
											local t = ensureCastBarDB() or {}
											return not not t.hideSpellNameBorder
										end
										local function setter(v)
											local t = ensureCastBarDB(); if not t then return end
											t.hideSpellNameBorder = (v == true)
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
										end
										y.y = y.y - 34
									end
	
									-- Spell Name Font
									addDropdown(frame.PageF, "Spell Name Font", fontOptions,
										function()
											local t = ensureCastBarDB() or {}
											local s = t.spellNameText or {}
											return s.fontFace or "FRIZQT__"
										end,
										function(v)
											local t = ensureCastBarDB(); if not t then return end
											t.spellNameText = t.spellNameText or {}
											t.spellNameText.fontFace = v
											applyNow()
										end,
										y)
	
									-- Spell Name Font Style
									addStyle(frame.PageF, "Spell Name Font Style",
										function()
											local t = ensureCastBarDB() or {}
											local s = t.spellNameText or {}
											return s.style or "OUTLINE"
										end,
										function(v)
											local t = ensureCastBarDB(); if not t then return end
											t.spellNameText = t.spellNameText or {}
											t.spellNameText.style = v
											applyNow()
										end,
										y)
	
									-- Spell Name Font Size
									addSlider(frame.PageF, "Spell Name Font Size", 6, 48, 1,
										function()
											local t = ensureCastBarDB() or {}
											local s = t.spellNameText or {}
											return tonumber(s.size) or 14
										end,
										function(v)
											local t = ensureCastBarDB(); if not t then return end
											t.spellNameText = t.spellNameText or {}
											t.spellNameText.size = tonumber(v) or 14
											applyNow()
										end,
										y)
	
									-- Spell Name Font Color
									addColor(frame.PageF, "Spell Name Font Color", true,
										function()
											local t = ensureCastBarDB() or {}
											local s = t.spellNameText or {}
											local c = s.color or {1,1,1,1}
											return c[1], c[2], c[3], c[4]
										end,
										function(r,g,b,a)
											local t = ensureCastBarDB(); if not t then return end
											t.spellNameText = t.spellNameText or {}
											t.spellNameText.color = {r or 1, g or 1, b or 1, a or 1}
											applyNow()
										end,
										y)
	
									-- Spell Name X Offset
									addSlider(frame.PageF, "Spell Name X Offset", -100, 100, 1,
										function()
											local t = ensureCastBarDB() or {}
											local s = t.spellNameText or {}
											local o = s.offset or {}
											return tonumber(o.x) or 0
										end,
										function(v)
											local t = ensureCastBarDB(); if not t then return end
											t.spellNameText = t.spellNameText or {}
											t.spellNameText.offset = t.spellNameText.offset or {}
											t.spellNameText.offset.x = tonumber(v) or 0
											applyNow()
										end,
										y)
	
									-- Spell Name Y Offset
									addSlider(frame.PageF, "Spell Name Y Offset", -100, 100, 1,
										function()
											local t = ensureCastBarDB() or {}
											local s = t.spellNameText or {}
											local o = s.offset or {}
											return tonumber(o.y) or 0
										end,
										function(v)
											local t = ensureCastBarDB(); if not t then return end
											t.spellNameText = t.spellNameText or {}
											t.spellNameText.offset = t.spellNameText.offset or {}
											t.spellNameText.offset.y = tonumber(v) or 0
											applyNow()
										end,
										y)
								end
							end
						end
	
						-- Build Style, Border, Icon, and Visibility tabs for any unit with a Cast Bar (Player/Target/Focus)
						buildStyleTab()
						buildBorderTab()
						buildIconTab()
						buildVisibilityTab() -- All units (Spark settings) + Player-only (TextBorder)
					end
	
					local tabCBC = Settings.CreateElementInitializer("ScooterTabbedSectionTemplate", cbData)
					-- STATIC HEIGHT: Cast Bar tabs now have multiple controls (Style, Icon, text, etc.).
					-- Bump slightly above 330px to accommodate one additional row (Disable Icon) while
					-- keeping spacing consistent with other Unit Frame tabbed sections.
					tabCBC.GetExtent = function() return 364 end
					tabCBC:AddShownPredicate(function() return panel:IsSectionExpanded(componentId, "Cast Bar") end)
					table.insert(init, tabCBC)
				end
	
end

panel.UnitFramesSections.cast = build

return build