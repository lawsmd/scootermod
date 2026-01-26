local addonName, addon = ...

addon.SettingsPanel = addon.SettingsPanel or {}
local panel = addon.SettingsPanel
panel.UnitFramesSections = panel.UnitFramesSections or {}

local function build(ctx, init)
	local componentId = ctx.componentId
	local title = ctx.title
	local panel = ctx.panel or panel
	local addon = ctx.addon or addon

	-- Skip for ToT - it has no class resource
	if componentId == "ufToT" then return end
	-- Skip for Boss - it has its own scaffolded sections
	if componentId == "ufBoss" then return end

	if componentId == "ufPlayer" then
		local function getClassResourceTitle()
			if addon and addon.UnitFrames_GetPlayerClassResourceTitle then
				return addon.UnitFrames_GetPlayerClassResourceTitle()
			end
			return "Class Resource"
		end

		local expInitializerCR = Settings.CreateElementInitializer("ScooterExpandableSectionTemplate", {
			name = getClassResourceTitle(),
			sectionKey = "Class Resource",
			componentId = componentId,
			expanded = panel:IsSectionExpanded(componentId, "Class Resource"),
		})
					expInitializerCR.GetExtent = function() return 30 end
					do
						local baseInitFrame = expInitializerCR.InitFrame
						expInitializerCR.InitFrame = function(self, frame)
							if baseInitFrame then baseInitFrame(self, frame) end
							local header = frame and frame.Button and frame.Button.Text
							if header and header.SetText then
								header:SetText(getClassResourceTitle())
							end
						end
					end
					table.insert(init, expInitializerCR)
	
					local crTabs = {
						sectionTitle = "",
						tabAText = "Positioning",
						tabBText = "Sizing",
						tabCText = "Visibility",
					}
					crTabs.build = function(frame)
						local function ensureCRDB()
							local db = addon and addon.db and addon.db.profile
							if not db then return nil end
							db.unitFrames = db.unitFrames or {}
							db.unitFrames.Player = db.unitFrames.Player or {}
							db.unitFrames.Player.classResource = db.unitFrames.Player.classResource or {}
							return db.unitFrames.Player.classResource
						end
	
						local function applyNow()
							if addon and addon.ApplyUnitFrameClassResource then
								addon.ApplyUnitFrameClassResource()
							elseif addon and addon.ApplyStyles then
								addon:ApplyStyles()
							end
						end
	
						local function addSlider(parent, label, minV, maxV, stepV, getter, setter, yRef)
							local options = Settings.CreateSliderOptions(minV, maxV, stepV)
							options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v)
								return tostring(math.floor((tonumber(v) or 0) + 0.5))
							end)
							local setting = CreateLocalSetting(label, "number", getter, setter, getter())
							local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = label, setting = setting, options = options })
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
	
						-- PageA: Positioning
						do
							local y = { y = -50 }

							addSlider(frame.PageA, "X Offset", -150, 150, 1,
								function()
									local cfg = ensureCRDB() or {}
									return tonumber(cfg.offsetX) or 0
								end,
								function(v)
									local cfg = ensureCRDB(); if not cfg then return end
									local nv = tonumber(v) or 0
									if nv < -150 then nv = -150 elseif nv > 150 then nv = 150 end
									cfg.offsetX = nv
									applyNow()
								end,
								y)

							addSlider(frame.PageA, "Y Offset", -150, 150, 1,
								function()
									local cfg = ensureCRDB() or {}
									return tonumber(cfg.offsetY) or 0
								end,
								function(v)
									local cfg = ensureCRDB(); if not cfg then return end
									local nv = tonumber(v) or 0
									if nv < -150 then nv = -150 elseif nv > 150 then nv = 150 end
									cfg.offsetY = nv
									applyNow()
								end,
								y)
						end
	
						-- PageB: Sizing
						do
							local y = { y = -50 }
							local function label()
								return string.format("%s Scale", getClassResourceTitle())
							end
							addSlider(frame.PageB, label(), 50, 150, 1,
								function()
									local cfg = ensureCRDB() or {}
									return tonumber(cfg.scale) or 100
								end,
								function(v)
									local cfg = ensureCRDB(); if not cfg then return end
									local nv = tonumber(v) or 100
									if nv < 50 then nv = 50 elseif nv > 150 then nv = 150 end
									cfg.scale = nv
									applyNow()
								end,
								y)
						end
	
						-- PageC: Visibility
						do
							local y = { y = -50 }
							local function label()
								return string.format("Hide %s", getClassResourceTitle())
							end
							local function getter()
								local cfg = ensureCRDB() or {}
								return cfg.hide == true
							end
							local function setter(v)
								local cfg = ensureCRDB(); if not cfg then return end
								cfg.hide = (v == true)
								applyNow()
							end
							local setting = CreateLocalSetting(label(), "boolean", getter, setter, getter())
							local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = label(), setting = setting, options = {} })
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
						end
					end
	
					local crInit = Settings.CreateElementInitializer("ScooterTabbedSectionTemplate", crTabs)
					-- Height for 2 sliders (X/Y Offset): 30 + (2 * 34) + 20 = 118px, rounded to 150px
					crInit.GetExtent = function() return 150 end
					crInit:AddShownPredicate(function()
						return panel:IsSectionExpanded(componentId, "Class Resource")
					end)
					table.insert(init, crInit)
				end
	
			-- Fourth collapsible section: Name & Level Text (all unit frames)
			local expInitializerNLT = Settings.CreateElementInitializer("ScooterExpandableSectionTemplate", {
				name = "Name & Level Text",
				sectionKey = "Name & Level Text",
				componentId = componentId,
				expanded = panel:IsSectionExpanded(componentId, "Name & Level Text"),
			})
			expInitializerNLT.GetExtent = function() return 30 end
			table.insert(init, expInitializerNLT)
	
		-- Name & Level Text tabs: Backdrop / Border / Name Text / Level Text
		local nltTabs = { sectionTitle = "", tabAText = "Backdrop", tabBText = "Border", tabCText = "Name Text", tabDText = "Level Text" }
		nltTabs.build = function(frame)
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
				return db.unitFrames[uk]
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
	
			-- Tab A: Backdrop
			do
				local function applyNow()
					if addon and addon.ApplyUnitFrameNameLevelTextFor then addon.ApplyUnitFrameNameLevelTextFor(unitKey()) end
					if addon and addon.ApplyStyles then addon:ApplyStyles() end
				end
				local y = { y = -50 }
				
				-- Enable Backdrop
				local function isBackdropEnabled()
					local t = ensureUFDB() or {}
					return not not t.nameBackdropEnabled
				end
				-- Hold refs to enable/disable dynamically
				local _bdTexFrame, _bdColorFrame, _bdOpacityFrame, _bdWidthFrame
				local function refreshBackdropEnabledState()
					local en = isBackdropEnabled()
					if _bdTexFrame and _bdTexFrame.Control and _bdTexFrame.Control.SetEnabled then _bdTexFrame.Control:SetEnabled(en) end
					do
						local lbl = _bdTexFrame and (_bdTexFrame.Text or _bdTexFrame.Label)
						if lbl and lbl.SetTextColor then lbl:SetTextColor(en and 1 or 0.6, en and 1 or 0.6, en and 1 or 0.6, 1) end
					end
					if _bdColorFrame and _bdColorFrame.Control and _bdColorFrame.Control.SetEnabled then _bdColorFrame.Control:SetEnabled(en) end
					do
						local lbl = _bdColorFrame and (_bdColorFrame.Text or _bdColorFrame.Label)
						if lbl and lbl.SetTextColor then lbl:SetTextColor(en and 1 or 0.6, en and 1 or 0.6, en and 1 or 0.6, 1) end
					end
					if _bdWidthFrame and _bdWidthFrame.Control and _bdWidthFrame.Control.SetEnabled then _bdWidthFrame.Control:SetEnabled(en) end
					if _bdWidthFrame and _bdWidthFrame.Text and _bdWidthFrame.Text.SetTextColor then _bdWidthFrame.Text:SetTextColor(en and 1 or 0.6, en and 1 or 0.6, en and 1 or 0.6, 1) end
					if _bdOpacityFrame and _bdOpacityFrame.Control and _bdOpacityFrame.Control.SetEnabled then _bdOpacityFrame.Control:SetEnabled(en) end
					if _bdOpacityFrame and _bdOpacityFrame.Text and _bdOpacityFrame.Text.SetTextColor then _bdOpacityFrame.Text:SetTextColor(en and 1 or 0.6, en and 1 or 0.6, en and 1 or 0.6, 1) end
					-- Note: Backdrop Color unified control handles its own enabled state via isEnabled callback
				end
				do
					local function getter()
						return isBackdropEnabled()
					end
					local function setter(v)
						local t = ensureUFDB(); if not t then return end
						t.nameBackdropEnabled = not not v
						applyNow()
						refreshBackdropEnabledState()
					end
					local setting = CreateLocalSetting("Enable Backdrop", "boolean", getter, setter, getter())
					local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = "Enable Backdrop", setting = setting, options = {} })
					local row = CreateFrame("Frame", nil, frame.PageA, "SettingsCheckboxControlTemplate")
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
				
				-- Backdrop Texture (no Default entry)
				do
					local function get()
						local t = ensureUFDB() or {}; return t.nameBackdropTexture or ""
					end
					local function set(v)
						local t = ensureUFDB(); if not t then return end
						t.nameBackdropTexture = v
						applyNow()
					end
					local function optsFiltered()
						local all = addon.BuildBarTextureOptionsContainer and addon.BuildBarTextureOptionsContainer() or {}
						local out = {}
						for _, o in ipairs(all) do
							if o.value ~= "default" then
								table.insert(out, o)
							end
						end
						return out
					end
					local f = addDropdown(frame.PageA, "Backdrop Texture", optsFiltered, get, set, y)
					-- Gray out when disabled
					do
						local en = isBackdropEnabled()
						if f and f.Control and f.Control.SetEnabled then f.Control:SetEnabled(en) end
						local lbl = f and (f.Text or f.Label)
						if lbl and lbl.SetTextColor then lbl:SetTextColor(en and 1 or 0.6, en and 1 or 0.6, en and 1 or 0.6, 1) end
					end
					_bdTexFrame = f
				end
				
				-- Backdrop Color mode (Default / Texture Original / Custom) with inline color swatch
				do
					local function getMode()
						local t = ensureUFDB() or {}; return t.nameBackdropColorMode or "default"
					end
					local function setMode(v)
						local t = ensureUFDB(); if not t then return end
						t.nameBackdropColorMode = v or "default"
						applyNow()
						refreshBackdropEnabledState()
					end
					local function getColor()
						local t = ensureUFDB() or {}; local c = t.nameBackdropTint or {1,1,1,1}; return c
					end
					local function setColor(r,g,b,a)
						local t = ensureUFDB(); if not t then return end
						t.nameBackdropTint = {r,g,b,a}
						applyNow()
					end
					local function colorOpts()
						local container = Settings.CreateControlTextContainer()
						container:Add("default", "Default")
						container:Add("texture", "Texture Original")
						container:Add("custom", "Custom")
						return container:GetData()
					end
					local f, swatch = panel.DropdownWithInlineSwatch(frame.PageA, y, {
						label = "Backdrop Color",
						getMode = getMode,
						setMode = setMode,
						getColor = getColor,
						setColor = setColor,
						options = colorOpts,
						isEnabled = function() return isBackdropEnabled() end,
						insideButton = true,
					})
					_bdColorFrame = f
				end
				
				-- Backdrop Width (% of baseline at 100%)
				do
					local function get()
						local t = ensureUFDB() or {}; local v = tonumber(t.nameBackdropWidthPct) or 100; if v < 25 then v = 25 elseif v > 300 then v = 300 end; return v
					end
					local function set(v)
						local t = ensureUFDB(); if not t then return end
						local nv = tonumber(v) or 100
						if nv < 25 then nv = 25 elseif nv > 300 then nv = 300 end
						t.nameBackdropWidthPct = nv
						applyNow()
						refreshBackdropEnabledState()
					end
					local sf = addSlider(frame.PageA, "Backdrop Width (%)", 25, 300, 1, get, set, y)
					do
						local en = isBackdropEnabled()
						if sf and sf.Control and sf.Control.SetEnabled then sf.Control:SetEnabled(en) end
						if sf and sf.Text and sf.Text.SetTextColor then sf.Text:SetTextColor(en and 1 or 0.6, en and 1 or 0.6, en and 1 or 0.6, 1) end
					end
					_bdWidthFrame = sf
				end
				
				-- Backdrop Opacity (0-100)
				do
					local function get()
						local t = ensureUFDB() or {}; local v = tonumber(t.nameBackdropOpacity) or 50; if v < 0 then v = 0 elseif v > 100 then v = 100 end; return v
					end
					local function set(v)
						local t = ensureUFDB(); if not t then return end
						local nv = tonumber(v) or 50
						if nv < 0 then nv = 0 elseif nv > 100 then nv = 100 end
						t.nameBackdropOpacity = nv
						applyNow()
						refreshBackdropEnabledState()
					end
					local sf = addSlider(frame.PageA, "Backdrop Opacity", 0, 100, 1, get, set, y)
					do
						local en = isBackdropEnabled()
						if sf and sf.Control and sf.Control.SetEnabled then sf.Control:SetEnabled(en) end
						if sf and sf.Text and sf.Text.SetTextColor then sf.Text:SetTextColor(en and 1 or 0.6, en and 1 or 0.6, en and 1 or 0.6, 1) end
					end
					_bdOpacityFrame = sf
				end
				refreshBackdropEnabledState()
			end
	
			-- Tab B: Border (Name Backdrop border)
			do
				local function applyNow()
					if addon and addon.ApplyUnitFrameNameLevelTextFor then addon.ApplyUnitFrameNameLevelTextFor(unitKey()) end
					if addon and addon.ApplyStyles then addon:ApplyStyles() end
				end
				-- Enable Border checkbox + gating combines with global Use Custom Borders
				local function isEnabled()
					local t = ensureUFDB() or {}
					local localEnabled = not not t.nameBackdropBorderEnabled
					local globalEnabled = not not t.useCustomBorders
					return localEnabled and globalEnabled
				end
				local y = { y = -50 }
				local _brStyleFrame, _brTintRow, _brTintSwatch, _brThickFrame, _brInsetFrame, _brTintLabel
				local function refreshBorderEnabledState()
					local en = isEnabled()
					if _brStyleFrame and _brStyleFrame.Control and _brStyleFrame.Control.SetEnabled then _brStyleFrame.Control:SetEnabled(en) end
					do
						local lbl = _brStyleFrame and (_brStyleFrame.Text or _brStyleFrame.Label)
						if lbl and lbl.SetTextColor then lbl:SetTextColor(en and 1 or 0.6, en and 1 or 0.6, en and 1 or 0.6, 1) end
					end
					if _brThickFrame and _brThickFrame.Control and _brThickFrame.Control.SetEnabled then _brThickFrame.Control:SetEnabled(en) end
					if _brThickFrame and _brThickFrame.Text and _brThickFrame.Text.SetTextColor then _brThickFrame.Text:SetTextColor(en and 1 or 0.6, en and 1 or 0.6, en and 1 or 0.6, 1) end
					if _brInsetFrame and _brInsetFrame.Control and _brInsetFrame.Control.SetEnabled then _brInsetFrame.Control:SetEnabled(en) end
					if _brInsetFrame and _brInsetFrame.Text and _brInsetFrame.Text.SetTextColor then _brInsetFrame.Text:SetTextColor(en and 1 or 0.6, en and 1 or 0.6, en and 1 or 0.6, 1) end
					if _brTintRow then
						local ctrl = _brTintRow.Checkbox or _brTintRow.CheckBox or (_brTintRow.Control and _brTintRow.Control.Checkbox) or _brTintRow.Control
						if ctrl and ctrl.SetEnabled then ctrl:SetEnabled(en) end
					end
					if _brTintSwatch and _brTintSwatch.EnableMouse then _brTintSwatch:EnableMouse(en) end
					if _brTintLabel and _brTintLabel.SetTextColor then _brTintLabel:SetTextColor(en and 1 or 0.6, en and 1 or 0.6, en and 1 or 0.6, 1) end
				end
				
				-- Enable Border
				do
					local function getter()
						local t = ensureUFDB() or {}; return not not t.nameBackdropBorderEnabled
					end
					local function setter(v)
						local t = ensureUFDB(); if not t then return end
						t.nameBackdropBorderEnabled = not not v
						applyNow()
						refreshBorderEnabledState()
					end
					local setting = CreateLocalSetting("Enable Border", "boolean", getter, setter, getter())
					local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = "Enable Border", setting = setting, options = {} })
					local row = CreateFrame("Frame", nil, frame.PageB, "SettingsCheckboxControlTemplate")
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
				
				-- Border Style
				do
					local function get()
						local t = ensureUFDB() or {}; return t.nameBackdropBorderStyle or "square"
					end
					local function set(v)
						local t = ensureUFDB(); if not t then return end
						t.nameBackdropBorderStyle = v or "square"
						applyNow()
						refreshBorderEnabledState()
					end
					local function opts()
						return addon.BuildBarBorderOptionsContainer and addon.BuildBarBorderOptionsContainer() or {
							{ value = "square", text = "Default (Square)" }
						}
					end
					local setting = CreateLocalSetting("Border Style", "string", get, set, get())
					local initDrop = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", { name = "Border Style", setting = setting, options = opts })
					local f = CreateFrame("Frame", nil, frame.PageB, "SettingsDropdownControlTemplate")
					f.GetElementData = function() return initDrop end
					f:SetPoint("TOPLEFT", 4, y.y)
					f:SetPoint("TOPRIGHT", -16, y.y)
					initDrop:InitFrame(f)
					local lbl = f and (f.Text or f.Label)
					if lbl and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(lbl) end
					if f.Control and panel.ThemeDropdownWithSteppers then panel.ThemeDropdownWithSteppers(f.Control) end
					local en = isEnabled()
					if f.Control and f.Control.SetEnabled then f.Control:SetEnabled(en) end
					if lbl and lbl.SetTextColor then lbl:SetTextColor(en and 1 or 0.6, en and 1 or 0.6, en and 1 or 0.6, 1) end
					y.y = y.y - 34
					_brStyleFrame = f
				end
				
				-- Border Tint (checkbox + swatch)
				do
					local function getTintEnabled()
						local t = ensureUFDB() or {}; return not not t.nameBackdropBorderTintEnable
					end
					local function setTintEnabled(b)
						local t = ensureUFDB(); if not t then return end
						t.nameBackdropBorderTintEnable = not not b
						applyNow()
					end
					local function getTint()
						local t = ensureUFDB() or {}
						local c = t.nameBackdropBorderTintColor or {1,1,1,1}
						return { c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 }
					end
					local function setTint(r,g,b,a)
						local t = ensureUFDB(); if not t then return end
						t.nameBackdropBorderTintColor = { r or 1, g or 1, b or 1, a or 1 }
						applyNow()
					end
					local tintSetting = CreateLocalSetting("Border Tint", "boolean", getTintEnabled, setTintEnabled, getTintEnabled())
					local initCb = CreateCheckboxWithSwatchInitializer(tintSetting, "Border Tint", getTint, setTint, 8)
					local row = CreateFrame("Frame", nil, frame.PageB, "SettingsCheckboxControlTemplate")
					row.GetElementData = function() return initCb end
					row:SetPoint("TOPLEFT", 4, y.y)
					row:SetPoint("TOPRIGHT", -16, y.y)
					initCb:InitFrame(row)
					local en = isEnabled()
					local ctrl = row.Checkbox or row.CheckBox or (row.Control and row.Control.Checkbox) or row.Control
					if ctrl and ctrl.SetEnabled then ctrl:SetEnabled(en) end
					if row.ScooterInlineSwatch and row.ScooterInlineSwatch.EnableMouse then
						row.ScooterInlineSwatch:EnableMouse(en)
						if row.ScooterInlineSwatch.SetAlpha then row.ScooterInlineSwatch:SetAlpha(en and 1 or 0.5) end
					end
					local labelFS = (ctrl and ctrl.Text) or row.Text
					if labelFS and labelFS.SetTextColor then
						if en then labelFS:SetTextColor(1, 1, 1, 1) else labelFS:SetTextColor(0.6, 0.6, 0.6, 1) end
					end
					y.y = y.y - 34
					_brTintRow = row
					_brTintSwatch = row.ScooterInlineSwatch
					_brTintLabel = labelFS
				end
				
				-- Border Thickness
				do
					local function get()
						local t = ensureUFDB() or {}; return tonumber(t.nameBackdropBorderThickness) or 1
					end
					local function set(v)
						local t = ensureUFDB(); if not t then return end
						local nv = tonumber(v) or 1
						if nv < 1 then nv = 1 elseif nv > 8 then nv = 8 end
						t.nameBackdropBorderThickness = nv
						applyNow()
					end
					local opts = Settings.CreateSliderOptions(1, 8, 0.2)
					opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return string.format("%.1f", v) end)
					local setting = CreateLocalSetting("Border Thickness", "number", get, set, get())
					local sf = CreateFrame("Frame", nil, frame.PageB, "SettingsSliderControlTemplate")
					local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = "Border Thickness", setting = setting, options = opts })
					sf.GetElementData = function() return initSlider end
					sf:SetPoint("TOPLEFT", 4, y.y)
					sf:SetPoint("TOPRIGHT", -16, y.y)
					initSlider:InitFrame(sf)
					if sf.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(sf.Text) end
					if panel and panel.ThemeSliderValue then panel.ThemeSliderValue(sf) end
					local en = isEnabled()
					if sf.Control and sf.Control.SetEnabled then sf.Control:SetEnabled(en) end
					if sf.Text and sf.Text.SetTextColor then sf.Text:SetTextColor(en and 1 or 0.6, en and 1 or 0.6, en and 1 or 0.6, 1) end
					y.y = y.y - 34
					_brThickFrame = sf
				end
				
				-- Border Inset
				do
					local function get()
						local t = ensureUFDB() or {}; return tonumber(t.nameBackdropBorderInset) or 0
					end
					local function set(v)
						local t = ensureUFDB(); if not t then return end
						local nv = tonumber(v) or 0
						if nv < -4 then nv = -4 elseif nv > 4 then nv = 4 end
						t.nameBackdropBorderInset = nv
						applyNow()
					end
					local opts = Settings.CreateSliderOptions(-4, 4, 1)
					opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return tostring(math.floor(v)) end)
					local setting = CreateLocalSetting("Border Inset", "number", get, set, get())
					local sf = CreateFrame("Frame", nil, frame.PageB, "SettingsSliderControlTemplate")
					local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = "Border Inset", setting = setting, options = opts })
					sf.GetElementData = function() return initSlider end
					sf:SetPoint("TOPLEFT", 4, y.y)
					sf:SetPoint("TOPRIGHT", -16, y.y)
					initSlider:InitFrame(sf)
					if sf.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(sf.Text) end
					if panel and panel.ThemeSliderValue then panel.ThemeSliderValue(sf) end
					local en = isEnabled()
					if sf.Control and sf.Control.SetEnabled then sf.Control:SetEnabled(en) end
					if sf.Text and sf.Text.SetTextColor then sf.Text:SetTextColor(en and 1 or 0.6, en and 1 or 0.6, en and 1 or 0.6, 1) end
					y.y = y.y - 34
					_brInsetFrame = sf
				end
				refreshBorderEnabledState()
			end
	
			-- Tab C: Name Text
			do
				local function applyNow()
					if addon and addon.ApplyUnitFrameNameLevelTextFor then addon.ApplyUnitFrameNameLevelTextFor(unitKey()) end
					if addon and addon.ApplyStyles then addon:ApplyStyles() end
				end
				local function fontOptions()
					return addon.BuildFontOptionsContainer()
				end
				local y = { y = -50 }
				
				-- Disable Name Text checkbox
				local label = "Disable Name Text"
				local function getter()
					local t = ensureUFDB(); return t and not not t.nameTextHidden or false
				end
				local function setter(v)
					local t = ensureUFDB(); if not t then return end
					t.nameTextHidden = (v and true) or false
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
				end
				y.y = y.y - 34
	
				-- Name Container Width (Target/Focus only)
				if componentId == "ufTarget" or componentId == "ufFocus" then
					local function getWidthPct()
						local t = ensureUFDB() or {}
						local s = t.textName or {}
						return tonumber(s.containerWidthPct) or 100
					end
					local function setWidthPct(v)
						local t = ensureUFDB(); if not t then return end
						t.textName = t.textName or {}
						t.textName.containerWidthPct = tonumber(v) or 100
						applyNow()
					end
					local widthRow = addSlider(
						frame.PageC,
						"Name Container Width",
						80, 150, 5,
						getWidthPct,
						setWidthPct,
						y
					)
	
					-- Info icon tooltip explaining purpose
					if panel and panel.CreateInfoIconForLabel and widthRow then
						local lbl = widthRow.Text or widthRow.Label
						if lbl then
							local icon = panel.CreateInfoIconForLabel(
								lbl,
								"Widen the name container to decrease the truncation of long names or with large name font sizes.",
								5,
								0,
								32
							)
							-- Defer repositioning so we can anchor precisely to the rendered label text.
							if icon and C_Timer and C_Timer.After then
								C_Timer.After(0, function()
									if not (icon:IsShown() and lbl:IsShown()) then return end
									local textWidth = lbl.GetStringWidth and lbl:GetStringWidth() or 0
									icon:ClearAllPoints()
									if textWidth and textWidth > 0 then
										icon:SetPoint("LEFT", lbl, "LEFT", textWidth + 5, 0)
									else
										icon:SetPoint("LEFT", lbl, "RIGHT", 5, 0)
									end
								end)
							end
						end
					end
				end
				
				-- Name Text Font
				addDropdown(frame.PageC, "Name Text Font", fontOptions,
					function() local t = ensureUFDB() or {}; local s = t.textName or {}; return s.fontFace or "FRIZQT__" end,
					function(v) local t = ensureUFDB(); if not t then return end; t.textName = t.textName or {}; t.textName.fontFace = v; applyNow() end,
					y)
				
				-- Name Text Style
				addStyle(frame.PageC, "Name Text Style",
					function() local t = ensureUFDB() or {}; local s = t.textName or {}; return s.style or "OUTLINE" end,
					function(v) local t = ensureUFDB(); if not t then return end; t.textName = t.textName or {}; t.textName.style = v; applyNow() end,
					y)
				
				-- Name Text Size
				addSlider(frame.PageC, "Name Text Size", 6, 48, 1,
					function() local t = ensureUFDB() or {}; local s = t.textName or {}; return tonumber(s.size) or 14 end,
					function(v) local t = ensureUFDB(); if not t then return end; t.textName = t.textName or {}; t.textName.size = tonumber(v) or 14; applyNow() end,
					y)
				
			-- Name Text Color (dropdown + inline swatch)
			do
				local function colorOpts()
					local c = Settings.CreateControlTextContainer()
					c:Add("default", "Default")
					-- Class Color option only available for Player (not Target/Focus/Pet)
					if componentId == "ufPlayer" then
						c:Add("class", "Class Color")
					end
					c:Add("custom", "Custom")
					return c:GetData()
				end
				local function getMode()
					local t = ensureUFDB() or {}; local s = t.textName or {}
					local mode = s.colorMode or "default"
					-- Reset "class" mode to "default" for Target/Focus/Pet (class option not available)
					if (componentId == "ufTarget" or componentId == "ufFocus" or componentId == "ufPet") and mode == "class" then
						mode = "default"
						-- Also update the stored value to prevent it from persisting
						if t then
							t.textName = t.textName or {}
							t.textName.colorMode = "default"
						end
					end
					return mode
				end
				local function setMode(v)
					local t = ensureUFDB(); if not t then return end
					-- Prevent setting "class" mode for Target/Focus/Pet (option not available)
					if (componentId == "ufTarget" or componentId == "ufFocus" or componentId == "ufPet") and v == "class" then
						v = "default"
					end
					t.textName = t.textName or {}; t.textName.colorMode = v or "default"; applyNow()
				end
				local function getColorTbl()
					local t = ensureUFDB() or {}; local s = t.textName or {}; local c = s.color or {1.0,0.82,0.0,1}
					return { c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 }
				end
				local function setColorTbl(r,g,b,a)
					local t = ensureUFDB(); if not t then return end
					t.textName = t.textName or {}; t.textName.color = { r or 1, g or 1, b or 1, a or 1 }; applyNow()
				end
				panel.DropdownWithInlineSwatch(frame.PageC, y, {
					label = "Name Text Color",
					getMode = getMode,
					setMode = setMode,
					getColor = getColorTbl,
					setColor = setColorTbl,
					options = colorOpts,
					insideButton = true,
				})
			end
	
				-- Name Text Alignment (Target/Focus only)
				if componentId == "ufTarget" or componentId == "ufFocus" then
					local function alignOpts()
						local c = Settings.CreateControlTextContainer()
						c:Add("LEFT", "Left")
						c:Add("CENTER", "Center")
						c:Add("RIGHT", "Right")
						return c:GetData()
					end
					addDropdown(frame.PageC, "Name Text Alignment", alignOpts,
						function() local t = ensureUFDB() or {}; local s = t.textName or {}; return s.alignment or "LEFT" end,
						function(v) local t = ensureUFDB(); if not t then return end; t.textName = t.textName or {}; t.textName.alignment = v or "LEFT"; applyNow() end,
						y)
				end
				
				-- Name Text Offset X
				addSlider(frame.PageC, "Name Text Offset X", -100, 100, 1,
					function() local t = ensureUFDB() or {}; local s = t.textName or {}; local o = s.offset or {}; return tonumber(o.x) or 0 end,
					function(v) local t = ensureUFDB(); if not t then return end; t.textName = t.textName or {}; t.textName.offset = t.textName.offset or {}; t.textName.offset.x = tonumber(v) or 0; applyNow() end,
					y)
				
				-- Name Text Offset Y
				addSlider(frame.PageC, "Name Text Offset Y", -100, 100, 1,
					function() local t = ensureUFDB() or {}; local s = t.textName or {}; local o = s.offset or {}; return tonumber(o.y) or 0 end,
					function(v) local t = ensureUFDB(); if not t then return end; t.textName = t.textName or {}; t.textName.offset = t.textName.offset or {}; t.textName.offset.y = tonumber(v) or 0; applyNow() end,
					y)
			end
	
			-- Tab D: Level Text
			do
				local function applyNow()
					if addon and addon.ApplyUnitFrameNameLevelTextFor then addon.ApplyUnitFrameNameLevelTextFor(unitKey()) end
					if addon and addon.ApplyStyles then addon:ApplyStyles() end
				end
				local function fontOptions()
					return addon.BuildFontOptionsContainer()
				end
				local y = { y = -50 }
				
				-- Disable Level Text checkbox
				local label = "Disable Level Text"
				local function getter()
					local t = ensureUFDB(); return t and not not t.levelTextHidden or false
				end
				local function setter(v)
					local t = ensureUFDB(); if not t then return end
					t.levelTextHidden = (v and true) or false
					applyNow()
				end
				local setting = CreateLocalSetting(label, "boolean", getter, setter, getter())
				local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = label, setting = setting, options = {} })
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
				
				-- Level Text Font
				addDropdown(frame.PageD, "Level Text Font", fontOptions,
					function() local t = ensureUFDB() or {}; local s = t.textLevel or {}; return s.fontFace or "FRIZQT__" end,
					function(v) local t = ensureUFDB(); if not t then return end; t.textLevel = t.textLevel or {}; t.textLevel.fontFace = v; applyNow() end,
					y)
				
				-- Level Text Style
				addStyle(frame.PageD, "Level Text Style",
					function() local t = ensureUFDB() or {}; local s = t.textLevel or {}; return s.style or "OUTLINE" end,
					function(v) local t = ensureUFDB(); if not t then return end; t.textLevel = t.textLevel or {}; t.textLevel.style = v; applyNow() end,
					y)
				
				-- Level Text Size
				addSlider(frame.PageD, "Level Text Size", 6, 48, 1,
					function() local t = ensureUFDB() or {}; local s = t.textLevel or {}; return tonumber(s.size) or 14 end,
					function(v) local t = ensureUFDB(); if not t then return end; t.textLevel = t.textLevel or {}; t.textLevel.size = tonumber(v) or 14; applyNow() end,
					y)
				
			-- Level Text Color (dropdown + inline swatch)
			do
				local function colorOpts()
					local c = Settings.CreateControlTextContainer()
					c:Add("default", "Default")
					c:Add("class", "Class Color")
					c:Add("custom", "Custom")
					return c:GetData()
				end
				local function getMode()
					local t = ensureUFDB() or {}; local s = t.textLevel or {}; return s.colorMode or "default"
				end
				local function setMode(v)
					local t = ensureUFDB(); if not t then return end
					t.textLevel = t.textLevel or {}; t.textLevel.colorMode = v or "default"; applyNow()
				end
				local function getColorTbl()
					local t = ensureUFDB() or {}; local s = t.textLevel or {}; local c = s.color or {1.0,0.82,0.0,1}
					return { c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 }
				end
				local function setColorTbl(r,g,b,a)
					local t = ensureUFDB(); if not t then return end
					t.textLevel = t.textLevel or {}; t.textLevel.color = { r or 1, g or 1, b or 1, a or 1 }; applyNow()
				end
				panel.DropdownWithInlineSwatch(frame.PageD, y, {
					label = "Level Text Color",
					getMode = getMode,
					setMode = setMode,
					getColor = getColorTbl,
					setColor = setColorTbl,
					options = colorOpts,
					insideButton = true,
				})
			end
				
				-- Level Text Offset X
				addSlider(frame.PageD, "Level Text Offset X", -100, 100, 1,
					function() local t = ensureUFDB() or {}; local s = t.textLevel or {}; local o = s.offset or {}; return tonumber(o.x) or 0 end,
					function(v) local t = ensureUFDB(); if not t then return end; t.textLevel = t.textLevel or {}; t.textLevel.offset = t.textLevel.offset or {}; t.textLevel.offset.x = tonumber(v) or 0; applyNow() end,
					y)
				
				-- Level Text Offset Y
				addSlider(frame.PageD, "Level Text Offset Y", -100, 100, 1,
					function() local t = ensureUFDB() or {}; local s = t.textLevel or {}; local o = s.offset or {}; return tonumber(o.y) or 0 end,
					function(v) local t = ensureUFDB(); if not t then return end; t.textLevel = t.textLevel or {}; t.textLevel.offset = t.textLevel.offset or {}; t.textLevel.offset.y = tonumber(v) or 0; applyNow() end,
					y)
			end
			end
	
			local nltInit = Settings.CreateElementInitializer("ScooterTabbedSectionTemplate", nltTabs)
			-- Static height for Name & Level Text tabs (Backdrop/Border/Name/Level).
			-- 300px was barely sufficient for 7 controls; with the 8th "Name Container Width"
			-- control on the Name Text tab we align with the 330px class used elsewhere
			-- for tabs with 7-8 settings (see TABBEDSECTIONS.md).
			nltInit.GetExtent = function() return 364 end
			nltInit:AddShownPredicate(function()
				return panel:IsSectionExpanded(componentId, "Name & Level Text")
			end)
			table.insert(init, nltInit)
	
end

panel.UnitFramesSections.classresource = build

return build