local addonName, addon = ...

addon.SettingsPanel = addon.SettingsPanel or {}
local panel = addon.SettingsPanel
panel.UnitFramesSections = panel.UnitFramesSections or {}

--------------------------------------------------------------------------------
-- TARGET OF TARGET SECTION BUILDERS
-- These sections only render for componentId == "ufToT"
-- ToT has no Edit Mode settings, so all positioning is addon-only.
--------------------------------------------------------------------------------

-- Helper to get/set UI scale conversion
local function getUiScale()
	return (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
end

local function pixelsToUiUnits(px)
	local s = getUiScale()
	if s == 0 then return 0 end
	return px / s
end

local function uiUnitsToPixels(u)
	local s = getUiScale()
	return math.floor((u * s) + 0.5)
end

-- Helper to ensure ToT database exists
local function ensureToTDB()
	local db = addon and addon.db and addon.db.profile
	if not db then return nil end
	db.unitFrames = db.unitFrames or {}
	db.unitFrames.TargetOfTarget = db.unitFrames.TargetOfTarget or {}
	return db.unitFrames.TargetOfTarget
end

-- Helper to get the ToT frame
local function getToTFrame()
	return _G["TargetFrameToT"]
end

-- Helper to apply ToT positioning from DB
local function applyToTPosition()
	local frame = getToTFrame()
	if not frame then return end
	
	local t = ensureToTDB()
	if not t then return end
	
	-- Skip if in combat
	if InCombatLockdown and InCombatLockdown() then
		-- Queue for after combat
		if C_Timer and C_Timer.After then
			C_Timer.After(0.1, applyToTPosition)
		end
		return
	end
	
	local offsetX = tonumber(t.offsetX) or 0
	local offsetY = tonumber(t.offsetY) or 0
	
	-- ToT is normally anchored to TargetFrame. We'll adjust relative to its default position.
	-- Capture original anchor if not already done
	if not frame._ScootOriginalAnchor then
		local point, relativeTo, relativePoint, xOfs, yOfs = frame:GetPoint(1)
		if point then
			frame._ScootOriginalAnchor = {
				point = point,
				relativeTo = relativeTo,
				relativePoint = relativePoint,
				xOfs = xOfs or 0,
				yOfs = yOfs or 0,
			}
		end
	end
	
	local orig = frame._ScootOriginalAnchor
	if orig then
		local ux = pixelsToUiUnits(offsetX)
		local uy = pixelsToUiUnits(offsetY)
		frame:ClearAllPoints()
		frame:SetPoint(orig.point, orig.relativeTo, orig.relativePoint, orig.xOfs + ux, orig.yOfs + uy)
	end
end

-- Expose the apply function globally for core styling to call
addon.ApplyToTPosition = applyToTPosition

-- Apply scale to the ToT frame (since ToT isn't in Edit Mode, we provide our own scale control)
local function applyToTScale()
	local frame = getToTFrame()
	if not frame then return end
	
	local t = ensureToTDB()
	if not t then return end
	
	-- Skip if in combat
	if InCombatLockdown and InCombatLockdown() then
		-- Queue for after combat
		if C_Timer and C_Timer.After then
			C_Timer.After(0.1, applyToTScale)
		end
		return
	end
	
	local scale = tonumber(t.scale) or 1.0
	-- Clamp scale to valid range
	if scale < 0.5 then scale = 0.5 end
	if scale > 2.0 then scale = 2.0 end
	
	if frame.SetScale then
		pcall(frame.SetScale, frame, scale)
	end
end

-- Expose the scale function globally
addon.ApplyToTScale = applyToTScale

-- Apply "Use Custom Borders" styling to ToT frame texture
local function applyToTCustomBorders()
	local tot = getToTFrame()
	if not tot then return end
	
	local t = ensureToTDB()
	local useCustom = t and t.useCustomBorders
	local frameTex = tot.FrameTexture
	
	if frameTex then
		if useCustom then
			if frameTex.SetAlpha then pcall(frameTex.SetAlpha, frameTex, 0) end
		else
			if frameTex.SetAlpha then pcall(frameTex.SetAlpha, frameTex, 1) end
		end
	end
end

-- Expose for core styling
addon.ApplyToTCustomBorders = applyToTCustomBorders

-- Apply "Hide Power Bar" setting to ToT ManaBar
local function applyToTPowerBarVisibility()
	local tot = getToTFrame()
	if not tot then return end
	
	local t = ensureToTDB()
	-- Use powerBarHidden (not hidePowerBar) to match bars.lua and other unit frames
	local hidePowerBar = t and t.powerBarHidden
	local manaBar = tot.ManaBar
	
	if manaBar then
		if hidePowerBar then
			if manaBar.SetAlpha then pcall(manaBar.SetAlpha, manaBar, 0) end
			-- Store flag for hook to re-enforce
			manaBar._ScooterToTPowerHidden = true
		else
			if manaBar.SetAlpha then pcall(manaBar.SetAlpha, manaBar, 1) end
			manaBar._ScooterToTPowerHidden = nil
		end
	end
end

-- Expose for UI and core
addon.ApplyToTPowerBarVisibility = applyToTPowerBarVisibility

--------------------------------------------------------------------------------
-- tot_root: Parent-level X/Y Offset sliders + Use Custom Borders (no collapsible section)
--------------------------------------------------------------------------------
local function buildTotRoot(ctx, init)
	local componentId = ctx.componentId
	
	-- Only render for ToT
	if componentId ~= "ufToT" then return end
	
	local panel = ctx.panel or panel
	local addon = ctx.addon or addon
	
	-- Debounce timer for position writes
	local _pendingWriteTimer
	
	local function writeOffsets(newX, newY)
		local t = ensureToTDB()
		if not t then return end
		
		if newX ~= nil then t.offsetX = math.floor(newX + 0.5) end
		if newY ~= nil then t.offsetY = math.floor(newY + 0.5) end
		
		-- Debounce the apply
		if _pendingWriteTimer and _pendingWriteTimer.Cancel then _pendingWriteTimer:Cancel() end
		_pendingWriteTimer = C_Timer.NewTimer(0.1, function()
			applyToTPosition()
		end)
	end
	
	-- X Offset (px)
	do
		local label = "X Offset (px)"
		local options = Settings.CreateSliderOptions(-150, 150, 1)
		options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return tostring(math.floor(v + 0.5)) end)
		local setting = CreateLocalSetting(label, "number",
			function() local t = ensureToTDB() or {}; return tonumber(t.offsetX) or 0 end,
			function(v) writeOffsets(v, nil) end,
			0)
		local row = Settings.CreateElementInitializer("SettingsSliderControlTemplate", { name = label, setting = setting, options = options, componentId = componentId })
		row.GetExtent = function() return 34 end
		do
			local base = row.InitFrame
			row.InitFrame = function(self, frame)
				if base then base(self, frame) end
				if panel and panel.ApplyControlTheme then panel.ApplyControlTheme(frame) end
				if panel and panel.ApplyRobotoWhite and frame and frame.Text then panel.ApplyRobotoWhite(frame.Text) end
				if panel and panel.ThemeSliderValue then panel.ThemeSliderValue(frame) end
			end
		end
		table.insert(init, row)
	end
	
	-- Y Offset (px)
	do
		local label = "Y Offset (px)"
		local options = Settings.CreateSliderOptions(-150, 150, 1)
		options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return tostring(math.floor(v + 0.5)) end)
		local setting = CreateLocalSetting(label, "number",
			function() local t = ensureToTDB() or {}; return tonumber(t.offsetY) or 0 end,
			function(v) writeOffsets(nil, v) end,
			0)
		local row = Settings.CreateElementInitializer("SettingsSliderControlTemplate", { name = label, setting = setting, options = options, componentId = componentId })
		row.GetExtent = function() return 34 end
		do
			local base = row.InitFrame
			row.InitFrame = function(self, frame)
				if base then base(self, frame) end
				if panel and panel.ApplyControlTheme then panel.ApplyControlTheme(frame) end
				if panel and panel.ApplyRobotoWhite and frame and frame.Text then panel.ApplyRobotoWhite(frame.Text) end
				if panel and panel.ThemeSliderValue then panel.ThemeSliderValue(frame) end
			end
		end
		table.insert(init, row)
	end
	
	-- Scale slider (scales the entire ToT frame, since ToT isn't in Edit Mode)
	do
		local label = "Scale"
		local options = Settings.CreateSliderOptions(0.5, 2.0, 0.05)
		options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return string.format("%.2f", v) end)
		local setting = CreateLocalSetting(label, "number",
			function() local t = ensureToTDB() or {}; return tonumber(t.scale) or 1.0 end,
			function(v)
				local t = ensureToTDB()
				if not t then return end
				t.scale = tonumber(v) or 1.0
				-- Debounce the scale application
				if _pendingWriteTimer and _pendingWriteTimer.Cancel then _pendingWriteTimer:Cancel() end
				_pendingWriteTimer = C_Timer.NewTimer(0.1, function()
					if addon and addon.ApplyToTScale then addon.ApplyToTScale() end
				end)
			end,
			1.0)
		local row = Settings.CreateElementInitializer("SettingsSliderControlTemplate", { name = label, setting = setting, options = options, componentId = componentId })
		row.GetExtent = function() return 34 end
		do
			local base = row.InitFrame
			row.InitFrame = function(self, frame)
				if base then base(self, frame) end
				if panel and panel.ApplyControlTheme then panel.ApplyControlTheme(frame) end
				if panel and panel.ApplyRobotoWhite and frame and frame.Text then panel.ApplyRobotoWhite(frame.Text) end
				if panel and panel.ThemeSliderValue then panel.ThemeSliderValue(frame) end
			end
		end
		table.insert(init, row)
	end
	
	-- Use Custom Borders checkbox (hides TargetFrameToT.FrameTexture when enabled)
	do
		local label = "Use Custom Borders"
		local setting = CreateLocalSetting(label, "boolean",
			function() local t = ensureToTDB() or {}; return not not t.useCustomBorders end,
			function(v)
				local t = ensureToTDB()
				if not t then return end
				t.useCustomBorders = not not v
				applyToTCustomBorders()
				-- Also reapply bar textures to enable/disable custom borders
				if addon and addon.ApplyUnitFrameBarTexturesFor then
					addon.ApplyUnitFrameBarTexturesFor("TargetOfTarget")
				end
			end,
			false)
		local row = Settings.CreateElementInitializer("SettingsCheckboxControlTemplate", { name = label, setting = setting, options = {}, componentId = componentId })
		row.GetExtent = function() return 34 end
		do
			local base = row.InitFrame
			row.InitFrame = function(self, frame)
				if base then base(self, frame) end
				if panel and panel.ApplyControlTheme then panel.ApplyControlTheme(frame) end
				if panel and panel.ApplyRobotoWhite then
					if frame and frame.Text then panel.ApplyRobotoWhite(frame.Text) end
					local cb = frame.Checkbox or frame.CheckBox or (frame.Control and frame.Control.Checkbox)
					if cb and cb.Text then panel.ApplyRobotoWhite(cb.Text) end
				end
			end
		end
		table.insert(init, row)
	end
end

panel.UnitFramesSections.tot_root = buildTotRoot

--------------------------------------------------------------------------------
-- tot_health: Health Bar section (tabbed: Sizing, Style, Border)
--------------------------------------------------------------------------------
local function buildTotHealth(ctx, init)
	local componentId = ctx.componentId
	
	-- Only render for ToT
	if componentId ~= "ufToT" then return end
	
	local panel = ctx.panel or panel
	local addon = ctx.addon or addon
	
	-- Helper to ensure health bar DB
	local function ensureHealthDB()
		local t = ensureToTDB()
		if not t then return nil end
		return t
	end
	
	local function applyNow()
		if addon and addon.ApplyUnitFrameBarTexturesFor then
			addon.ApplyUnitFrameBarTexturesFor("TargetOfTarget")
		end
	end
	
	-- Collapsible header
	local expInitializer = Settings.CreateElementInitializer("ScooterExpandableSectionTemplate", {
		name = "Health Bar",
		sectionKey = "Health Bar",
		componentId = componentId,
		expanded = panel:IsSectionExpanded(componentId, "Health Bar"),
	})
	expInitializer.GetExtent = function() return 30 end
	table.insert(init, expInitializer)
	
	-- Tabbed section: Style | Border (no Sizing tab - ToT bars cannot be resized)
	local tabs = { sectionTitle = "", tabAText = "Style", tabBText = "Border" }
	tabs.build = function(frame)
		local function fmtInt(v) return tostring(math.floor((tonumber(v) or 0) + 0.5)) end
		local function fmtDecimal(v) return string.format("%.1f", tonumber(v) or 0) end
		
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
		
		local function addSliderDecimal(parent, label, minV, maxV, step, getFunc, setFunc, yRef)
			local options = Settings.CreateSliderOptions(minV, maxV, step)
			options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return fmtDecimal(v) end)
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
			yRef.y = yRef.y - 34
			return f
		end
		
		-- PageA: Style
		do
			local y = { y = -50 }
			
			-- Foreground Texture
			local function textureOptions()
				if addon.BuildBarTextureOptionsContainer then
					return addon.BuildBarTextureOptionsContainer()
				end
				local c = Settings.CreateControlTextContainer()
				c:Add("default", "Default")
				return c:GetData()
			end
			
			local fgTexFrame = addDropdown(frame.PageA, "Foreground Texture", textureOptions,
				function() local t = ensureHealthDB() or {}; return t.healthBarTexture or "default" end,
				function(v) local t = ensureHealthDB(); if not t then return end; t.healthBarTexture = v or "default"; applyNow() end,
				y)
			if fgTexFrame and fgTexFrame.Control and addon.InitBarTextureDropdown then
				local setting = fgTexFrame.GetElementData and fgTexFrame:GetElementData() and fgTexFrame:GetElementData().data and fgTexFrame:GetElementData().data.setting
				if setting then addon.InitBarTextureDropdown(fgTexFrame.Control, setting) end
			end
			
			-- Foreground Color (dropdown + inline swatch)
			local function colorOpts()
				local c = Settings.CreateControlTextContainer()
				c:Add("default", "Default")
				c:Add("texture", "Texture Original")
				c:Add("class", "Class Color")
				c:Add("custom", "Custom")
				return c:GetData()
			end
			panel.DropdownWithInlineSwatch(frame.PageA, y, {
				label = "Foreground Color",
				getMode = function() local t = ensureHealthDB() or {}; return t.healthBarColorMode or "default" end,
				setMode = function(v) local t = ensureHealthDB(); if not t then return end; t.healthBarColorMode = v or "default"; applyNow() end,
				getColor = function() local t = ensureHealthDB() or {}; local c = t.healthBarTint or {1,1,1,1}; return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end,
				setColor = function(r,g,b,a) local t = ensureHealthDB(); if not t then return end; t.healthBarTint = {r or 1, g or 1, b or 1, a or 1}; applyNow() end,
				options = colorOpts,
				insideButton = true,
			})
			
			-- Background Texture
			local bgTexFrame = addDropdown(frame.PageA, "Background Texture", textureOptions,
				function() local t = ensureHealthDB() or {}; return t.healthBarBackgroundTexture or "default" end,
				function(v) local t = ensureHealthDB(); if not t then return end; t.healthBarBackgroundTexture = v or "default"; applyNow() end,
				y)
			if bgTexFrame and bgTexFrame.Control and addon.InitBarTextureDropdown then
				local setting = bgTexFrame.GetElementData and bgTexFrame:GetElementData() and bgTexFrame:GetElementData().data and bgTexFrame:GetElementData().data.setting
				if setting then addon.InitBarTextureDropdown(bgTexFrame.Control, setting) end
			end
			
			-- Background Color
			local function bgColorOpts()
				local c = Settings.CreateControlTextContainer()
				c:Add("default", "Default")
				c:Add("texture", "Texture Original")
				c:Add("custom", "Custom")
				return c:GetData()
			end
			panel.DropdownWithInlineSwatch(frame.PageA, y, {
				label = "Background Color",
				getMode = function() local t = ensureHealthDB() or {}; return t.healthBarBackgroundColorMode or "default" end,
				setMode = function(v) local t = ensureHealthDB(); if not t then return end; t.healthBarBackgroundColorMode = v or "default"; applyNow() end,
				getColor = function() local t = ensureHealthDB() or {}; local c = t.healthBarBackgroundTint or {0,0,0,1}; return c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1 end,
				setColor = function(r,g,b,a) local t = ensureHealthDB(); if not t then return end; t.healthBarBackgroundTint = {r or 0, g or 0, b or 0, a or 1}; applyNow() end,
				options = bgColorOpts,
				insideButton = true,
			})
			
			-- Background Opacity
			addSlider(frame.PageA, "Background Opacity", 0, 100, 1,
				function() local t = ensureHealthDB() or {}; return tonumber(t.healthBarBackgroundOpacity) or 50 end,
				function(v) local t = ensureHealthDB(); if not t then return end; t.healthBarBackgroundOpacity = tonumber(v) or 50; applyNow() end,
				y)
		end
		
		-- PageB: Border
		do
			local y = { y = -50 }
			
			-- Border Style
			local function borderOpts()
				if addon.BuildBorderStyleOptionsContainer then
					return addon.BuildBorderStyleOptionsContainer()
				end
				local c = Settings.CreateControlTextContainer()
				c:Add("default", "Default (Square)")
				return c:GetData()
			end
			addDropdown(frame.PageB, "Border Style", borderOpts,
				function() local t = ensureHealthDB() or {}; return t.healthBarBorderStyle or "default" end,
				function(v) local t = ensureHealthDB(); if not t then return end; t.healthBarBorderStyle = v or "default"; applyNow() end,
				y)
			
		-- Border Thickness
		addSliderDecimal(frame.PageB, "Border Thickness", 1, 8, 0.2,
			function() local t = ensureHealthDB() or {}; return tonumber(t.healthBarBorderThickness) or 1 end,
			function(v) local t = ensureHealthDB(); if not t then return end; t.healthBarBorderThickness = tonumber(v) or 1; applyNow() end,
			y)
		
		-- Border Inset
		addSliderDecimal(frame.PageB, "Border Inset", -4, 4, 0.2,
				function() local t = ensureHealthDB() or {}; return tonumber(t.healthBarBorderInset) or 0 end,
				function(v) local t = ensureHealthDB(); if not t then return end; t.healthBarBorderInset = tonumber(v) or 0; applyNow() end,
				y)
			
			-- Border Tint Enable checkbox
			do
				local setting = CreateLocalSetting("Enable Border Tint", "boolean",
					function() local t = ensureHealthDB() or {}; return not not t.healthBarBorderTintEnable end,
					function(v) local t = ensureHealthDB(); if not t then return end; t.healthBarBorderTintEnable = not not v; applyNow() end,
					false)
				local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = "Enable Border Tint", setting = setting, options = {} })
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
			
			-- Border Tint Color swatch
			do
				local f = CreateFrame("Frame", nil, frame.PageB, "SettingsListElementTemplate")
				f:SetHeight(26)
				f:SetPoint("TOPLEFT", 4, y.y)
				f:SetPoint("TOPRIGHT", -16, y.y)
				f.Text:SetText("Border Tint Color")
				if panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(f.Text) end
				local right = CreateFrame("Frame", nil, f)
				right:SetSize(250, 26)
				right:SetPoint("RIGHT", f, "RIGHT", -16, 0)
				f.Text:ClearAllPoints()
				f.Text:SetPoint("LEFT", f, "LEFT", 36.5, 0)
				f.Text:SetPoint("RIGHT", right, "LEFT", 0, 0)
				f.Text:SetJustifyH("LEFT")
				local function getColorTable()
					local t = ensureHealthDB() or {}
					local c = t.healthBarBorderTintColor or {1,1,1,1}
					return {c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1}
				end
				local function setColorTable(r, g, b, a)
					local t = ensureHealthDB()
					if not t then return end
					t.healthBarBorderTintColor = {r or 1, g or 1, b or 1, a or 1}
					applyNow()
				end
				local swatch = CreateColorSwatch(right, getColorTable, setColorTable, true)
				swatch:SetPoint("LEFT", right, "LEFT", 8, 0)
				y.y = y.y - 34
			end
		end
	end
	
	local tabInit = Settings.CreateElementInitializer("ScooterTabbedSectionTemplate", tabs)
	tabInit.GetExtent = function() return 270 end
	tabInit:AddShownPredicate(function()
		return panel:IsSectionExpanded(componentId, "Health Bar")
	end)
	table.insert(init, tabInit)
end

panel.UnitFramesSections.tot_health = buildTotHealth

--------------------------------------------------------------------------------
-- tot_power: Power Bar section (tabbed: Style, Border, Visibility)
--------------------------------------------------------------------------------
local function buildTotPower(ctx, init)
	local componentId = ctx.componentId
	
	-- Only render for ToT
	if componentId ~= "ufToT" then return end
	
	local panel = ctx.panel or panel
	local addon = ctx.addon or addon
	
	-- Helper to ensure power bar DB
	local function ensurePowerDB()
		local t = ensureToTDB()
		if not t then return nil end
		return t
	end
	
	local function applyNow()
		if addon and addon.ApplyUnitFrameBarTexturesFor then
			addon.ApplyUnitFrameBarTexturesFor("TargetOfTarget")
		end
	end
	
	local function applyPowerBarVisibility()
		if addon and addon.ApplyToTPowerBarVisibility then
			addon.ApplyToTPowerBarVisibility()
		end
	end
	
	-- Collapsible header
	local expInitializer = Settings.CreateElementInitializer("ScooterExpandableSectionTemplate", {
		name = "Power Bar",
		sectionKey = "Power Bar",
		componentId = componentId,
		expanded = panel:IsSectionExpanded(componentId, "Power Bar"),
	})
	expInitializer.GetExtent = function() return 30 end
	table.insert(init, expInitializer)
	
	-- Tabbed section: Style | Border | Visibility (no Sizing - ToT bars cannot be resized)
	local tabs = { sectionTitle = "", tabAText = "Style", tabBText = "Border", tabCText = "Visibility" }
	tabs.build = function(frame)
		local function fmtInt(v) return tostring(math.floor((tonumber(v) or 0) + 0.5)) end
		local function fmtDecimal(v) return string.format("%.1f", tonumber(v) or 0) end
		
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
		
		local function addSliderDecimal(parent, label, minV, maxV, step, getFunc, setFunc, yRef)
			local options = Settings.CreateSliderOptions(minV, maxV, step)
			options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return fmtDecimal(v) end)
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
			yRef.y = yRef.y - 34
			return f
		end
		
		-- PageA: Style
		do
			local y = { y = -50 }
			
			-- Foreground Texture
			local function textureOptions()
				if addon.BuildBarTextureOptionsContainer then
					return addon.BuildBarTextureOptionsContainer()
				end
				local c = Settings.CreateControlTextContainer()
				c:Add("default", "Default")
				return c:GetData()
			end
			
			local fgTexFrame = addDropdown(frame.PageA, "Foreground Texture", textureOptions,
				function() local t = ensurePowerDB() or {}; return t.powerBarTexture or "default" end,
				function(v) local t = ensurePowerDB(); if not t then return end; t.powerBarTexture = v or "default"; applyNow() end,
				y)
			if fgTexFrame and fgTexFrame.Control and addon.InitBarTextureDropdown then
				local setting = fgTexFrame.GetElementData and fgTexFrame:GetElementData() and fgTexFrame:GetElementData().data and fgTexFrame:GetElementData().data.setting
				if setting then addon.InitBarTextureDropdown(fgTexFrame.Control, setting) end
			end
			
			-- Foreground Color (dropdown + inline swatch)
			local function colorOpts()
				local c = Settings.CreateControlTextContainer()
				c:Add("default", "Default")
				c:Add("texture", "Texture Original")
				c:Add("power", "Power Color")
				c:Add("custom", "Custom")
				return c:GetData()
			end
			panel.DropdownWithInlineSwatch(frame.PageA, y, {
				label = "Foreground Color",
				getMode = function() local t = ensurePowerDB() or {}; return t.powerBarColorMode or "default" end,
				setMode = function(v) local t = ensurePowerDB(); if not t then return end; t.powerBarColorMode = v or "default"; applyNow() end,
				getColor = function() local t = ensurePowerDB() or {}; local c = t.powerBarTint or {1,1,1,1}; return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end,
				setColor = function(r,g,b,a) local t = ensurePowerDB(); if not t then return end; t.powerBarTint = {r or 1, g or 1, b or 1, a or 1}; applyNow() end,
				options = colorOpts,
				insideButton = true,
			})
			
			-- Background Texture
			local bgTexFrame = addDropdown(frame.PageA, "Background Texture", textureOptions,
				function() local t = ensurePowerDB() or {}; return t.powerBarBackgroundTexture or "default" end,
				function(v) local t = ensurePowerDB(); if not t then return end; t.powerBarBackgroundTexture = v or "default"; applyNow() end,
				y)
			if bgTexFrame and bgTexFrame.Control and addon.InitBarTextureDropdown then
				local setting = bgTexFrame.GetElementData and bgTexFrame:GetElementData() and bgTexFrame:GetElementData().data and bgTexFrame:GetElementData().data.setting
				if setting then addon.InitBarTextureDropdown(bgTexFrame.Control, setting) end
			end
			
			-- Background Color
			local function bgColorOpts()
				local c = Settings.CreateControlTextContainer()
				c:Add("default", "Default")
				c:Add("texture", "Texture Original")
				c:Add("custom", "Custom")
				return c:GetData()
			end
			panel.DropdownWithInlineSwatch(frame.PageA, y, {
				label = "Background Color",
				getMode = function() local t = ensurePowerDB() or {}; return t.powerBarBackgroundColorMode or "default" end,
				setMode = function(v) local t = ensurePowerDB(); if not t then return end; t.powerBarBackgroundColorMode = v or "default"; applyNow() end,
				getColor = function() local t = ensurePowerDB() or {}; local c = t.powerBarBackgroundTint or {0,0,0,1}; return c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1 end,
				setColor = function(r,g,b,a) local t = ensurePowerDB(); if not t then return end; t.powerBarBackgroundTint = {r or 0, g or 0, b or 0, a or 1}; applyNow() end,
				options = bgColorOpts,
				insideButton = true,
			})
			
			-- Background Opacity
			addSlider(frame.PageA, "Background Opacity", 0, 100, 1,
				function() local t = ensurePowerDB() or {}; return tonumber(t.powerBarBackgroundOpacity) or 50 end,
				function(v) local t = ensurePowerDB(); if not t then return end; t.powerBarBackgroundOpacity = tonumber(v) or 50; applyNow() end,
				y)
		end
		
		-- PageB: Border
		do
			local y = { y = -50 }
			
			-- Border Style
			local function borderOpts()
				if addon.BuildBorderStyleOptionsContainer then
					return addon.BuildBorderStyleOptionsContainer()
				end
				local c = Settings.CreateControlTextContainer()
				c:Add("default", "Default (Square)")
				return c:GetData()
			end
			addDropdown(frame.PageB, "Border Style", borderOpts,
				function() local t = ensurePowerDB() or {}; return t.powerBarBorderStyle or "default" end,
				function(v) local t = ensurePowerDB(); if not t then return end; t.powerBarBorderStyle = v or "default"; applyNow() end,
				y)
			
		-- Border Thickness
		addSliderDecimal(frame.PageB, "Border Thickness", 1, 8, 0.2,
			function() local t = ensurePowerDB() or {}; return tonumber(t.powerBarBorderThickness) or 1 end,
			function(v) local t = ensurePowerDB(); if not t then return end; t.powerBarBorderThickness = tonumber(v) or 1; applyNow() end,
			y)
		
		-- Border Inset
		addSliderDecimal(frame.PageB, "Border Inset", -4, 4, 0.2,
			function() local t = ensurePowerDB() or {}; return tonumber(t.powerBarBorderInset) or 0 end,
			function(v) local t = ensurePowerDB(); if not t then return end; t.powerBarBorderInset = tonumber(v) or 0; applyNow() end,
			y)
			
			-- Border Tint Enable checkbox
			do
				local setting = CreateLocalSetting("Enable Border Tint", "boolean",
					function() local t = ensurePowerDB() or {}; return not not t.powerBarBorderTintEnable end,
					function(v) local t = ensurePowerDB(); if not t then return end; t.powerBarBorderTintEnable = not not v; applyNow() end,
					false)
				local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = "Enable Border Tint", setting = setting, options = {} })
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
			
			-- Border Tint Color swatch
			do
				local f = CreateFrame("Frame", nil, frame.PageB, "SettingsListElementTemplate")
				f:SetHeight(26)
				f:SetPoint("TOPLEFT", 4, y.y)
				f:SetPoint("TOPRIGHT", -16, y.y)
				f.Text:SetText("Border Tint Color")
				if panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(f.Text) end
				local right = CreateFrame("Frame", nil, f)
				right:SetSize(250, 26)
				right:SetPoint("RIGHT", f, "RIGHT", -16, 0)
				f.Text:ClearAllPoints()
				f.Text:SetPoint("LEFT", f, "LEFT", 36.5, 0)
				f.Text:SetPoint("RIGHT", right, "LEFT", 0, 0)
				f.Text:SetJustifyH("LEFT")
				local function getColorTable()
					local t = ensurePowerDB() or {}
					local c = t.powerBarBorderTintColor or {1,1,1,1}
					return {c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1}
				end
				local function setColorTable(r, g, b, a)
					local t = ensurePowerDB()
					if not t then return end
					t.powerBarBorderTintColor = {r or 1, g or 1, b or 1, a or 1}
					applyNow()
				end
				local swatch = CreateColorSwatch(right, getColorTable, setColorTable, true)
				swatch:SetPoint("LEFT", right, "LEFT", 8, 0)
				y.y = y.y - 34
			end
		end
		
		-- PageC: Visibility
		do
			local y = { y = -50 }
			
			-- Hide Power Bar checkbox
			-- Use powerBarHidden (not hidePowerBar) to match bars.lua and other unit frames
			do
				local setting = CreateLocalSetting("Hide Power Bar", "boolean",
					function() local t = ensurePowerDB() or {}; return not not t.powerBarHidden end,
					function(v)
						local t = ensurePowerDB()
						if not t then return end
						t.powerBarHidden = not not v
						applyPowerBarVisibility()
					end,
					false)
				local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = "Hide Power Bar", setting = setting, options = {} })
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
	
	local tabInit = Settings.CreateElementInitializer("ScooterTabbedSectionTemplate", tabs)
	tabInit.GetExtent = function() return 270 end
	tabInit:AddShownPredicate(function()
		return panel:IsSectionExpanded(componentId, "Power Bar")
	end)
	table.insert(init, tabInit)
end

panel.UnitFramesSections.tot_power = buildTotPower

--------------------------------------------------------------------------------
-- tot_portrait: Portrait section (tabbed: Positioning, Sizing, Mask, Border, Visibility)
--------------------------------------------------------------------------------
local function buildTotPortrait(ctx, init)
	local componentId = ctx.componentId
	
	-- Only render for ToT
	if componentId ~= "ufToT" then return end
	
	local panel = ctx.panel or panel
	local addon = ctx.addon or addon
	
	-- Helper to ensure portrait DB
	local function ensurePortraitDB()
		local t = ensureToTDB()
		if not t then return nil end
		t.portrait = t.portrait or {}
		return t.portrait
	end
	
	local function applyNow()
		if addon and addon.ApplyUnitFramePortraitFor then
			addon.ApplyUnitFramePortraitFor("TargetOfTarget")
		end
		if addon and addon.ApplyStyles then addon:ApplyStyles() end
	end
	
	-- Collapsible header
	local expInitializer = Settings.CreateElementInitializer("ScooterExpandableSectionTemplate", {
		name = "Portrait",
		sectionKey = "Portrait",
		componentId = componentId,
		expanded = panel:IsSectionExpanded(componentId, "Portrait"),
	})
	expInitializer.GetExtent = function() return 30 end
	table.insert(init, expInitializer)
	
	-- Tabbed section: Positioning | Sizing | Mask | Border | Visibility
	local tabs = { sectionTitle = "", tabAText = "Positioning", tabBText = "Sizing", tabCText = "Mask", tabDText = "Border", tabEText = "Visibility" }
	tabs.build = function(frame)
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
			yRef.y = yRef.y - 34
			return f
		end
		
		-- PageA: Positioning
		do
			local y = { y = -50 }
			
			addSlider(frame.PageA, "X Offset", -100, 100, 1,
				function() local t = ensurePortraitDB() or {}; return tonumber(t.offsetX) or 0 end,
				function(v) local t = ensurePortraitDB(); if not t then return end; t.offsetX = tonumber(v) or 0; applyNow() end,
				y)
			
			addSlider(frame.PageA, "Y Offset", -100, 100, 1,
				function() local t = ensurePortraitDB() or {}; return tonumber(t.offsetY) or 0 end,
				function(v) local t = ensurePortraitDB(); if not t then return end; t.offsetY = tonumber(v) or 0; applyNow() end,
				y)
		end
		
		-- PageB: Sizing
		do
			local y = { y = -50 }
			
			addSlider(frame.PageB, "Portrait Size (Scale)", 50, 200, 1,
				function() local t = ensurePortraitDB() or {}; return tonumber(t.scale) or 100 end,
				function(v) local t = ensurePortraitDB(); if not t then return end; t.scale = tonumber(v) or 100; applyNow() end,
				y)
		end
		
		-- PageC: Mask
		do
			local y = { y = -50 }
			
			addSlider(frame.PageC, "Portrait Zoom", 100, 200, 1,
				function() local t = ensurePortraitDB() or {}; return tonumber(t.zoom) or 100 end,
				function(v) local t = ensurePortraitDB(); if not t then return end; t.zoom = tonumber(v) or 100; applyNow() end,
				y)
		end
		
		-- PageD: Border
		do
			local y = { y = -50 }
			
			local function isEnabled()
				local t = ensurePortraitDB() or {}
				return not not t.portraitBorderEnable
			end
			
			-- Use Custom Border checkbox
			do
				local setting = CreateLocalSetting("Use Custom Border", "boolean",
					function() local t = ensurePortraitDB() or {}; return (t.portraitBorderEnable == true) end,
					function(v) local t = ensurePortraitDB(); if not t then return end; t.portraitBorderEnable = (v == true); applyNow() end,
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
					c:Add("rare_s", "Rare (Square)")
					return c:GetData()
				end
				local styleDrop = addDropdown(frame.PageD, "Border Style", optionsStyle,
					function() local t = ensurePortraitDB() or {}; return t.portraitBorderStyle or "texture_c" end,
					function(v) local t = ensurePortraitDB(); if not t then return end; t.portraitBorderStyle = v or "texture_c"; applyNow() end,
					y)
				-- Gray out when disabled
				local lbl = styleDrop and (styleDrop.Text or styleDrop.Label)
				local enabled = isEnabled()
				if styleDrop.Control and styleDrop.Control.SetEnabled then styleDrop.Control:SetEnabled(enabled) end
				if lbl and lbl.SetTextColor then lbl:SetTextColor(enabled and 1 or 0.6, enabled and 1 or 0.6, enabled and 1 or 0.6, 1) end
			end
			
			-- Border Inset slider
			do
				local opts = Settings.CreateSliderOptions(1, 8, 0.2)
				opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return string.format("%.1f", v) end)
				local insetSetting = CreateLocalSetting("Border Inset", "number",
					function() local t = ensurePortraitDB() or {}; return tonumber(t.portraitBorderThickness) or 1 end,
					function(v) local t = ensurePortraitDB(); if not t then return end; t.portraitBorderThickness = tonumber(v) or 1; applyNow() end,
					1)
				local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = "Border Inset", setting = insetSetting, options = opts })
				local sf = CreateFrame("Frame", nil, frame.PageD, "SettingsSliderControlTemplate")
				sf.GetElementData = function() return initSlider end
				sf:SetPoint("TOPLEFT", 4, y.y)
				sf:SetPoint("TOPRIGHT", -16, y.y)
				initSlider:InitFrame(sf)
				if sf.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(sf.Text) end
				if panel and panel.ThemeSliderValue then panel.ThemeSliderValue(sf) end
				-- Gray out when disabled
				local enabled = isEnabled()
				if sf.Control and sf.Control.SetEnabled then sf.Control:SetEnabled(enabled) end
				if sf.Text and sf.Text.SetTextColor then sf.Text:SetTextColor(enabled and 1 or 0.6, enabled and 1 or 0.6, enabled and 1 or 0.6, 1) end
				y.y = y.y - 34
			end
			
			-- Border Color (dropdown) + inline Custom Tint swatch
			do
				local function colorOpts()
					local container = Settings.CreateControlTextContainer()
					container:Add("texture", "Texture Original")
					container:Add("class", "Class Color")
					container:Add("custom", "Custom")
					return container:GetData()
				end
				panel.DropdownWithInlineSwatch(frame.PageD, y, {
					label = "Border Color",
					getMode = function() local t = ensurePortraitDB() or {}; return t.portraitBorderColorMode or "texture" end,
					setMode = function(v) local t = ensurePortraitDB(); if not t then return end; t.portraitBorderColorMode = v or "texture"; applyNow() end,
					getColor = function() local t = ensurePortraitDB() or {}; local c = t.portraitBorderTintColor or {1,1,1,1}; return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end,
					setColor = function(r,g,b,a) local t = ensurePortraitDB(); if not t then return end; t.portraitBorderTintColor = {r or 1, g or 1, b or 1, a or 1}; applyNow() end,
					options = colorOpts,
					isEnabled = isEnabled,
					insideButton = true,
				})
			end
		end
		
		-- PageE: Visibility
		do
			local y = { y = -50 }
			
			-- Hide Portrait checkbox
			do
				local setting = CreateLocalSetting("Hide Portrait", "boolean",
					function() local t = ensurePortraitDB() or {}; return (t.hidePortrait == true) end,
					function(v) local t = ensurePortraitDB(); if not t then return end; t.hidePortrait = (v == true); applyNow() end,
					false)
				local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = "Hide Portrait", setting = setting, options = {} })
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
			
			-- Portrait Opacity slider
			addSlider(frame.PageE, "Portrait Opacity", 1, 100, 1,
				function() local t = ensurePortraitDB() or {}; return tonumber(t.opacity) or 100 end,
				function(v) local t = ensurePortraitDB(); if not t then return end; t.opacity = tonumber(v) or 100; applyNow() end,
				y)
		end
	end
	
	local tabInit = Settings.CreateElementInitializer("ScooterTabbedSectionTemplate", tabs)
	tabInit.GetExtent = function() return 270 end
	tabInit:AddShownPredicate(function()
		return panel:IsSectionExpanded(componentId, "Portrait")
	end)
	table.insert(init, tabInit)
end

panel.UnitFramesSections.tot_portrait = buildTotPortrait

--------------------------------------------------------------------------------
-- tot_nametext: Name Text section (NON-TABBED - individual row initializers under header)
--------------------------------------------------------------------------------
local function buildTotNameText(ctx, init)
	local componentId = ctx.componentId
	
	-- Only render for ToT
	if componentId ~= "ufToT" then return end
	
	local panel = ctx.panel or panel
	local addon = ctx.addon or addon
	
	-- Helper to ensure name text DB
	local function ensureNameTextDB()
		local t = ensureToTDB()
		if not t then return nil end
		t.textName = t.textName or {}
		return t
	end
	
	local function applyNow()
		if addon and addon.ApplyToTNameText then
			addon.ApplyToTNameText()
		end
		if addon and addon.ApplyStyles then addon:ApplyStyles() end
	end
	
	-- Collapsible header
	local expInitializer = Settings.CreateElementInitializer("ScooterExpandableSectionTemplate", {
		name = "Name Text",
		sectionKey = "Name Text",
		componentId = componentId,
		expanded = panel:IsSectionExpanded(componentId, "Name Text"),
	})
	expInitializer.GetExtent = function() return 30 end
	table.insert(init, expInitializer)
	
	-- ShownPredicate for all controls
	local function isExpanded()
		return panel:IsSectionExpanded(componentId, "Name Text")
	end
	
	-- Helper: Format int
	local function fmtInt(v) return tostring(math.floor((tonumber(v) or 0) + 0.5)) end
	
	-- Helper: Font options
	local function fontOptions()
		if addon.BuildFontOptionsContainer then
			return addon.BuildFontOptionsContainer()
		end
		local c = Settings.CreateControlTextContainer()
		c:Add("FRIZQT__", "Friz Quadrata")
		return c:GetData()
	end
	
	-- Helper: Style options
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
	
	-- 1. Disable Name Text checkbox
	do
		local setting = CreateLocalSetting("Disable Name Text", "boolean",
			function() local t = ensureNameTextDB() or {}; return not not t.nameTextHidden end,
			function(v) local t = ensureNameTextDB(); if not t then return end; t.nameTextHidden = not not v; applyNow() end,
			false)
		local row = Settings.CreateElementInitializer("SettingsCheckboxControlTemplate", { name = "Disable Name Text", setting = setting, options = {}, componentId = componentId })
		row.GetExtent = function() return 34 end
		row:AddShownPredicate(isExpanded)
		do
			local base = row.InitFrame
			row.InitFrame = function(self, frame)
				if base then base(self, frame) end
				if panel and panel.ApplyControlTheme then panel.ApplyControlTheme(frame) end
				if panel and panel.ApplyRobotoWhite then
					if frame and frame.Text then panel.ApplyRobotoWhite(frame.Text) end
					local cb = frame.Checkbox or frame.CheckBox or (frame.Control and frame.Control.Checkbox)
					if cb and cb.Text then panel.ApplyRobotoWhite(cb.Text) end
				end
			end
		end
		table.insert(init, row)
	end
	
	-- 2. Name Text Font dropdown
	do
		local setting = CreateLocalSetting("Name Text Font", "string",
			function() local t = ensureNameTextDB() or {}; return t.textName and t.textName.fontFace or "FRIZQT__" end,
			function(v) local t = ensureNameTextDB(); if not t then return end; t.textName = t.textName or {}; t.textName.fontFace = v or "FRIZQT__"; applyNow() end,
			"FRIZQT__")
		local row = Settings.CreateElementInitializer("SettingsDropdownControlTemplate", { name = "Name Text Font", setting = setting, options = fontOptions, componentId = componentId })
		row.GetExtent = function() return 34 end
		row:AddShownPredicate(isExpanded)
		do
			local base = row.InitFrame
			row.InitFrame = function(self, frame)
				if base then base(self, frame) end
				if panel and panel.ApplyControlTheme then panel.ApplyControlTheme(frame) end
				local lbl = frame and (frame.Text or frame.Label)
				if lbl and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(lbl) end
				if frame.Control and panel.ThemeDropdownWithSteppers then panel.ThemeDropdownWithSteppers(frame.Control) end
				-- Initialize font preview dropdown if available
				if frame.Control and frame.Control.Dropdown and addon and addon.InitFontDropdown then
					addon.InitFontDropdown(frame.Control.Dropdown, setting, fontOptions)
				end
			end
		end
		table.insert(init, row)
	end
	
	-- 3. Name Text Style dropdown
	do
		local setting = CreateLocalSetting("Name Text Style", "string",
			function() local t = ensureNameTextDB() or {}; return t.textName and t.textName.style or "OUTLINE" end,
			function(v) local t = ensureNameTextDB(); if not t then return end; t.textName = t.textName or {}; t.textName.style = v or "OUTLINE"; applyNow() end,
			"OUTLINE")
		local row = Settings.CreateElementInitializer("SettingsDropdownControlTemplate", { name = "Name Text Style", setting = setting, options = styleOptions, componentId = componentId })
		row.GetExtent = function() return 34 end
		row:AddShownPredicate(isExpanded)
		do
			local base = row.InitFrame
			row.InitFrame = function(self, frame)
				if base then base(self, frame) end
				if panel and panel.ApplyControlTheme then panel.ApplyControlTheme(frame) end
				local lbl = frame and (frame.Text or frame.Label)
				if lbl and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(lbl) end
				if frame.Control and panel.ThemeDropdownWithSteppers then panel.ThemeDropdownWithSteppers(frame.Control) end
			end
		end
		table.insert(init, row)
	end
	
	-- 4. Name Text Size slider
	do
		local options = Settings.CreateSliderOptions(6, 24, 1)
		options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, fmtInt)
		local setting = CreateLocalSetting("Name Text Size", "number",
			function() local t = ensureNameTextDB() or {}; return tonumber(t.textName and t.textName.size) or 10 end,
			function(v) local t = ensureNameTextDB(); if not t then return end; t.textName = t.textName or {}; t.textName.size = tonumber(v) or 10; applyNow() end,
			10)
		local row = Settings.CreateElementInitializer("SettingsSliderControlTemplate", { name = "Name Text Size", setting = setting, options = options, componentId = componentId })
		row.GetExtent = function() return 34 end
		row:AddShownPredicate(isExpanded)
		do
			local base = row.InitFrame
			row.InitFrame = function(self, frame)
				if base then base(self, frame) end
				if panel and panel.ApplyControlTheme then panel.ApplyControlTheme(frame) end
				if frame and frame.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(frame.Text) end
				if panel and panel.ThemeSliderValue then panel.ThemeSliderValue(frame) end
			end
		end
		table.insert(init, row)
	end
	
	-- 5. Name Text Color (using panel.DropdownWithInlineSwatch inside a container frame)
	do
		-- Create a container row that hosts the DropdownWithInlineSwatch
		local colorRow = Settings.CreateElementInitializer("SettingsListElementTemplate")
		colorRow.GetExtent = function() return 34 end
		colorRow:AddShownPredicate(isExpanded)
		colorRow.InitFrame = function(self, frame)
			-- Only build UI once
			if frame._ScooterNameTextColorBuilt then
				-- Update swatch visibility on re-init
				if frame._ScooterRefreshSwatch then frame._ScooterRefreshSwatch() end
				return
			end
			frame._ScooterNameTextColorBuilt = true
			
			-- Hide the default label from SettingsListElementTemplate
			if frame.Text then frame.Text:Hide() end
			
			-- Create inner container for the dropdown+swatch
			local container = CreateFrame("Frame", nil, frame)
			container:SetAllPoints(frame)
			
			-- Color mode dropdown options
			local function colorOpts()
				local c = Settings.CreateControlTextContainer()
				c:Add("default", "Default")
				c:Add("class", "Class Color")
				c:Add("custom", "Custom")
				return c:GetData()
			end
			
			-- Use panel.DropdownWithInlineSwatch which handles all the complexity
			local yRef = { y = 0 }
			panel.DropdownWithInlineSwatch(container, yRef, {
				label = "Name Text Color",
				getMode = function() local t = ensureNameTextDB() or {}; return t.textName and t.textName.colorMode or "default" end,
				setMode = function(v) local t = ensureNameTextDB(); if not t then return end; t.textName = t.textName or {}; t.textName.colorMode = v or "default"; applyNow() end,
				getColor = function() local t = ensureNameTextDB() or {}; local c = t.textName and t.textName.color or {1,1,1,1}; return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end,
				setColor = function(r,g,b,a) local t = ensureNameTextDB(); if not t then return end; t.textName = t.textName or {}; t.textName.color = {r or 1, g or 1, b or 1, a or 1}; applyNow() end,
				options = colorOpts,
				insideButton = true,
			})
			
			-- Store refresh function if the DropdownWithInlineSwatch stored one
			frame._ScooterRefreshSwatch = function()
				-- The swatch refreshes itself via the getMode/getColor callbacks
			end
		end
		table.insert(init, colorRow)
	end
	
	-- 6. Name Text Alignment dropdown
	do
		local function alignOpts()
			local c = Settings.CreateControlTextContainer()
			c:Add("LEFT", "Left")
			c:Add("CENTER", "Center")
			c:Add("RIGHT", "Right")
			return c:GetData()
		end
		local setting = CreateLocalSetting("Name Text Alignment", "string",
			function() local t = ensureNameTextDB() or {}; return t.textName and t.textName.alignment or "LEFT" end,
			function(v) local t = ensureNameTextDB(); if not t then return end; t.textName = t.textName or {}; t.textName.alignment = v or "LEFT"; applyNow() end,
			"LEFT")
		local row = Settings.CreateElementInitializer("SettingsDropdownControlTemplate", { name = "Name Text Alignment", setting = setting, options = alignOpts, componentId = componentId })
		row.GetExtent = function() return 34 end
		row:AddShownPredicate(isExpanded)
		do
			local base = row.InitFrame
			row.InitFrame = function(self, frame)
				if base then base(self, frame) end
				if panel and panel.ApplyControlTheme then panel.ApplyControlTheme(frame) end
				local lbl = frame and (frame.Text or frame.Label)
				if lbl and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(lbl) end
				if frame.Control and panel.ThemeDropdownWithSteppers then panel.ThemeDropdownWithSteppers(frame.Control) end
			end
		end
		table.insert(init, row)
	end
	
	-- 7. Name Text X Offset slider
	do
		local options = Settings.CreateSliderOptions(-100, 100, 1)
		options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, fmtInt)
		local setting = CreateLocalSetting("Name Text X Offset", "number",
			function() local t = ensureNameTextDB() or {}; return tonumber(t.textName and t.textName.offset and t.textName.offset.x) or 0 end,
			function(v) local t = ensureNameTextDB(); if not t then return end; t.textName = t.textName or {}; t.textName.offset = t.textName.offset or {}; t.textName.offset.x = tonumber(v) or 0; applyNow() end,
			0)
		local row = Settings.CreateElementInitializer("SettingsSliderControlTemplate", { name = "Name Text X Offset", setting = setting, options = options, componentId = componentId })
		row.GetExtent = function() return 34 end
		row:AddShownPredicate(isExpanded)
		do
			local base = row.InitFrame
			row.InitFrame = function(self, frame)
				if base then base(self, frame) end
				if panel and panel.ApplyControlTheme then panel.ApplyControlTheme(frame) end
				if frame and frame.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(frame.Text) end
				if panel and panel.ThemeSliderValue then panel.ThemeSliderValue(frame) end
			end
		end
		table.insert(init, row)
	end
	
	-- 8. Name Text Y Offset slider
	do
		local options = Settings.CreateSliderOptions(-100, 100, 1)
		options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, fmtInt)
		local setting = CreateLocalSetting("Name Text Y Offset", "number",
			function() local t = ensureNameTextDB() or {}; return tonumber(t.textName and t.textName.offset and t.textName.offset.y) or 0 end,
			function(v) local t = ensureNameTextDB(); if not t then return end; t.textName = t.textName or {}; t.textName.offset = t.textName.offset or {}; t.textName.offset.y = tonumber(v) or 0; applyNow() end,
			0)
		local row = Settings.CreateElementInitializer("SettingsSliderControlTemplate", { name = "Name Text Y Offset", setting = setting, options = options, componentId = componentId })
		row.GetExtent = function() return 34 end
		row:AddShownPredicate(isExpanded)
		do
			local base = row.InitFrame
			row.InitFrame = function(self, frame)
				if base then base(self, frame) end
				if panel and panel.ApplyControlTheme then panel.ApplyControlTheme(frame) end
				if frame and frame.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(frame.Text) end
				if panel and panel.ThemeSliderValue then panel.ThemeSliderValue(frame) end
			end
		end
		table.insert(init, row)
	end
end

panel.UnitFramesSections.tot_nametext = buildTotNameText

--------------------------------------------------------------------------------
-- Initialization: Apply ToT styling on load
--------------------------------------------------------------------------------
do
	local initFrame = CreateFrame("Frame")
	initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
	initFrame:SetScript("OnEvent", function(self, event)
		if event == "PLAYER_ENTERING_WORLD" then
			-- Defer to allow frames to initialize
			if C_Timer and C_Timer.After then
				C_Timer.After(0.5, function()
					applyToTPosition()
					applyToTScale()
					applyToTCustomBorders()
					applyToTPowerBarVisibility()
				end)
			end
		end
	end)
	
	-- Also hook ToT OnShow to reapply styling
	local function hookToTOnShow()
		local tot = getToTFrame()
		if tot and not tot._ScooterToTStyleHooked then
			tot._ScooterToTStyleHooked = true
			if tot.HookScript then
				tot:HookScript("OnShow", function()
					if C_Timer and C_Timer.After then
						C_Timer.After(0, function()
							applyToTPosition()
							applyToTScale()
							applyToTCustomBorders()
							applyToTPowerBarVisibility()
						end)
					end
				end)
			end
		end
		
		-- Hook ManaBar to re-enforce hidden state after Blizzard updates
		local manaBar = tot and tot.ManaBar
		if manaBar and not manaBar._ScooterToTPowerVisHooked then
			manaBar._ScooterToTPowerVisHooked = true
			if manaBar.HookScript then
				manaBar:HookScript("OnShow", function(self)
					if self._ScooterToTPowerHidden then
						if self.SetAlpha then pcall(self.SetAlpha, self, 0) end
					end
				end)
			end
		end
	end
	
	-- Try to hook immediately, and again after PLAYER_ENTERING_WORLD
	hookToTOnShow()
	initFrame:HookScript("OnEvent", function()
		hookToTOnShow()
	end)
end

return {
	tot_root = buildTotRoot,
	tot_health = buildTotHealth,
	tot_power = buildTotPower,
	tot_portrait = buildTotPortrait,
	tot_nametext = buildTotNameText,
}

