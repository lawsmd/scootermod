local addonName, addon = ...

addon.SettingsPanel = addon.SettingsPanel or {}
local panel = addon.SettingsPanel
panel.UnitFramesSections = panel.UnitFramesSections or {}

--------------------------------------------------------------------------------
-- BOSS FRAMES SECTION BUILDERS
-- These sections only render for componentId == "ufBoss"
--
-- Edit Mode system frame: BossTargetFrameContainer (Enum.EditModeUnitFrameSystemIndices.Boss)
-- Individual frames: Boss1TargetFrame ... Boss5TargetFrame
--------------------------------------------------------------------------------

local function getBossSystemFrame()
	local mgr = _G.EditModeManagerFrame
	local EM = _G.Enum and _G.Enum.EditModeUnitFrameSystemIndices
	local EMSys = _G.Enum and _G.Enum.EditModeSystem
	if not (mgr and EM and EMSys and mgr.GetRegisteredSystemFrame) then return nil end
	return mgr:GetRegisteredSystemFrame(EMSys.UnitFrame, EM.Boss)
end

local function ensureBossDB()
	local db = addon and addon.db and addon.db.profile
	if not db then return nil end
	db.unitFrames = db.unitFrames or {}
	db.unitFrames.Boss = db.unitFrames.Boss or {}
	return db.unitFrames.Boss
end

local function setRowEnabled(rowFrame, enabled)
	if not rowFrame then return end
	rowFrame:SetAlpha(enabled and 1 or 0.5)

	local control = rowFrame.Control or rowFrame
	local dropdown = control and control.Dropdown
	local slider = control and (control.Slider or control.slider or rowFrame.Slider)
	local checkbox = rowFrame.Checkbox or rowFrame.CheckBox or (control and control.Checkbox)

	if dropdown and dropdown.SetEnabled then
		pcall(dropdown.SetEnabled, dropdown, enabled)
	elseif dropdown and dropdown.EnableMouse then
		pcall(dropdown.EnableMouse, dropdown, enabled)
	end

	if slider and slider.SetEnabled then
		pcall(slider.SetEnabled, slider, enabled)
	elseif slider and slider.EnableMouse then
		pcall(slider.EnableMouse, slider, enabled)
	end

	if checkbox and checkbox.SetEnabled then
		pcall(checkbox.SetEnabled, checkbox, enabled)
	elseif checkbox and checkbox.EnableMouse then
		pcall(checkbox.EnableMouse, checkbox, enabled)
	end
end

-- Shared conditional enable/disable state for Boss Frames.
-- IMPORTANT: Do NOT clear these references on every render. Settings rows are recycled.
panel._ufBossConditionalFrames = panel._ufBossConditionalFrames or {}
local cond = panel._ufBossConditionalFrames

local function isUseLargerEnabled()
	local frameUF = getBossSystemFrame()
	local sidULF = _G.Enum and _G.Enum.EditModeUnitFrameSetting and _G.Enum.EditModeUnitFrameSetting.UseLargerFrame
	if frameUF and sidULF and addon and addon.EditMode and addon.EditMode.GetSetting then
		local v = addon.EditMode.GetSetting(frameUF, sidULF)
		return (v and v ~= 0) and true or false
	end
	return false
end

local function applyConditionalAvailability()
	-- Frame Size depends on Use Larger Frame
	if cond.frameSizeRow then
		setRowEnabled(cond.frameSizeRow, isUseLargerEnabled())
	end
end

--------------------------------------------------------------------------------
-- boss_root: Parent-level settings (no collapsible header)
--------------------------------------------------------------------------------
local function buildBossRoot(ctx, init)
	local componentId = ctx.componentId
	local panel = ctx.panel or panel

	if componentId ~= "ufBoss" then return end

	-- 1) Hide Blizzard Frame Art & Animations (master switch; required for custom borders)
	do
		local label = "Hide Blizzard Frame Art & Animations"

		local function getter()
			local t = ensureBossDB(); if not t then return false end
			return not not t.useCustomBorders
		end

		local function setter(b)
			local t = ensureBossDB(); if not t then return end
			t.useCustomBorders = not not b
			if addon and addon.ApplyUnitFrameBarTexturesFor then
				addon.ApplyUnitFrameBarTexturesFor("Boss")
			end
		end

		local setting = CreateLocalSetting(label, "boolean", getter, setter, getter())
		local row = Settings.CreateElementInitializer("SettingsCheckboxControlTemplate", { name = label, setting = setting, options = {}, componentId = componentId })
		-- Taller row so the longer label can wrap instead of truncating.
		row.GetExtent = function() return 62 end
		do
			local base = row.InitFrame
			row.InitFrame = function(self, frame)
				if base then base(self, frame) end
				-- Mirror Unit Frames master checkbox behavior from `sections/root.lua`:
				-- - Aggressive cleanup for recycled frames (icons/swatches)
				-- - Emphasis layout (+25% font, +25% checkbox)
				-- - Consistent info icon placement

				-- Clean up Unit Frame info icons if this frame is being used for a different component
				if frame.ScooterInfoIcon and frame.ScooterInfoIcon._isUnitFrameIcon then
					local labelText = frame.Text and frame.Text:GetText() or ""
					local isUnitFrameComponent = (componentId == "ufPlayer" or componentId == "ufTarget" or componentId == "ufFocus" or componentId == "ufPet" or componentId == "ufBoss")
					local isUnitFrameCheckbox = (labelText == "Hide Blizzard Frame Art & Animations")
					if not (isUnitFrameComponent and isUnitFrameCheckbox) then
						frame.ScooterInfoIcon:Hide()
						frame.ScooterInfoIcon:SetParent(nil)
						frame.ScooterInfoIcon = nil
					end
				end
				-- Hide any stray inline swatch from a previously-recycled tint row
				if frame.ScooterInlineSwatch then
					frame.ScooterInlineSwatch:Hide()
				end
				-- Aggressively restore any swatch-wrapped handlers on recycled rows
				if frame.ScooterInlineSwatchWrapper then
					frame.OnSettingValueChanged = frame.ScooterInlineSwatchBase or frame.OnSettingValueChanged
					frame.ScooterInlineSwatchWrapper = nil
					frame.ScooterInlineSwatchBase = nil
				end
				-- Detach swatch-specific checkbox callbacks so this row behaves like a normal checkbox
				local cb = frame.Checkbox or frame.CheckBox or frame.Control or frame
				if cb and cb.UnregisterCallback and SettingsCheckboxMixin and SettingsCheckboxMixin.Event and cb.ScooterInlineSwatchCallbackOwner then
					cb:UnregisterCallback(SettingsCheckboxMixin.Event.OnValueChanged, cb.ScooterInlineSwatchCallbackOwner)
					cb.ScooterInlineSwatchCallbackOwner = nil
				end

				if panel and panel.ApplyControlTheme then panel.ApplyControlTheme(frame) end
				if panel and panel.ApplyRobotoWhite then
					if frame and frame.Text then panel.ApplyRobotoWhite(frame.Text) end
					local checkbox = frame.Checkbox or frame.CheckBox or (frame.Control and frame.Control.Checkbox)
					if checkbox and checkbox.Text then panel.ApplyRobotoWhite(checkbox.Text) end
					if checkbox and panel.ThemeCheckbox then panel.ThemeCheckbox(checkbox) end

					-- Layout + typography: long labels should wrap cleanly.
					local cbox = checkbox or frame.Checkbox or frame.CheckBox or frame.Control
					local labelFS = frame.Text or frame.Label
					local function layout()
						if not (frame and cbox and labelFS and cbox.SetPoint and cbox.ClearAllPoints and labelFS.SetPoint and labelFS.ClearAllPoints) then
							return
						end
						cbox:ClearAllPoints()
						cbox:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
						labelFS:ClearAllPoints()
						labelFS:SetPoint("LEFT", frame, "LEFT", 36.5, 0)
						labelFS:SetPoint("RIGHT", cbox, "LEFT", -10, 0)
						labelFS:SetJustifyH("LEFT")
						labelFS:SetJustifyV("MIDDLE")
						if labelFS.SetWordWrap then labelFS:SetWordWrap(true) end
						if labelFS.SetMaxLines then labelFS:SetMaxLines(3) end
					end

					-- Emphasis: +25% label font size.
					if labelFS then
						local fontSize = 18
						panel.ApplyRobotoWhite(labelFS, fontSize, "")
					end

					layout()
					if not frame._ScooterUFMasterLayoutHooked then
						frame._ScooterUFMasterLayoutHooked = true
						frame:HookScript("OnSizeChanged", function()
							layout()
						end)
					end
					if C_Timer and C_Timer.After then
						C_Timer.After(0, function()
							layout()
						end)
					end

					-- Emphasis: +25% checkbox size.
					if cbox and cbox.SetScale then
						cbox:SetScale(1.25)
					end
				end

				-- Add info icon to the LEFT of the setting label.
				if frame and frame.Text then
					local labelText = frame.Text:GetText()
					if labelText == "Hide Blizzard Frame Art & Animations" then
						if panel and panel.CreateInfoIcon then
							if not frame.ScooterInfoIcon then
								local tooltipText = "Hides Blizzard's default frame borders, overlays, and flash effects (aggro glow, reputation color, etc.). Required for ScooterMod's custom bar borders to display."
								frame.ScooterInfoIcon = panel.CreateInfoIcon(frame, tooltipText, "RIGHT", "LEFT", -6, 0, 32)
								frame.ScooterInfoIcon._isUnitFrameIcon = true
								frame.ScooterInfoIcon._componentId = componentId
							else
								frame.ScooterInfoIcon:Show()
							end
							frame.ScooterInfoIcon.TooltipText = "Hides Blizzard's default frame borders, overlays, and flash effects (aggro glow, reputation color, etc.). Required for ScooterMod's custom bar borders to display."
							if frame.ScooterInfoIcon.ClearAllPoints and frame.ScooterInfoIcon.SetPoint then
								frame.ScooterInfoIcon:ClearAllPoints()
								frame.ScooterInfoIcon:SetPoint("RIGHT", frame.Text, "LEFT", -8, 0)
							end
						end
					end
				end
			end
		end
		table.insert(init, row)
	end

	-- Divider under the master checkbox (matches other Unit Frames root section)
	do
		local divRow = Settings.CreateElementInitializer("SettingsListElementTemplate")
		divRow.GetExtent = function() return 18 end
		divRow.InitFrame = function(self, frame)
			local keysToHide = {
				"Text", "InfoText", "ButtonContainer", "MessageText", "ActiveDropdown",
				"SpecEnableCheck", "SpecIcon", "SpecName", "SpecDropdown", "RenameBtn",
				"CopyBtn", "DeleteBtn", "CreateBtn", "RuleCard", "EmptyText", "AddRuleBtn",
			}
			for _, key in ipairs(keysToHide) do
				if frame[key] then frame[key]:Hide() end
			end
			if frame.EnableMouse then frame:EnableMouse(false) end

			local divider = frame.ScooterDivider
			if not divider then
				divider = CreateFrame("Frame", nil, frame)
				frame.ScooterDivider = divider
				divider:SetHeight(12)

				local colorR, colorG, colorB, colorA = 0.20, 0.90, 0.30, 0.30

				local lineLeft = divider:CreateTexture(nil, "ARTWORK")
				lineLeft:SetColorTexture(colorR, colorG, colorB, colorA)
				lineLeft:SetHeight(1)
				lineLeft:SetPoint("LEFT", divider, "LEFT", 16, 0)
				lineLeft:SetPoint("RIGHT", divider, "CENTER", -10, 0)

				local lineRight = divider:CreateTexture(nil, "ARTWORK")
				lineRight:SetColorTexture(colorR, colorG, colorB, colorA)
				lineRight:SetHeight(1)
				lineRight:SetPoint("LEFT", divider, "CENTER", 10, 0)
				lineRight:SetPoint("RIGHT", divider, "RIGHT", -16, 0)

				local ornament = divider:CreateTexture(nil, "OVERLAY")
				ornament:SetColorTexture(0.20, 0.90, 0.30, 0.55)
				ornament:SetSize(6, 6)
				ornament:SetPoint("CENTER", divider, "CENTER", 0, 0)
				ornament:SetRotation(math.rad(45))

				divider._lineLeft = lineLeft
				divider._lineRight = lineRight
				divider._ornament = ornament
			end

			divider:ClearAllPoints()
			divider:SetPoint("LEFT", frame, "LEFT", 0, 0)
			divider:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
			divider:SetPoint("CENTER", frame, "CENTER", 0, 0)
			divider:Show()
		end
		table.insert(init, divRow)
	end

	-- 2) Use Larger Frame (Edit Mode)
	do
		local label = "Use Larger Frame"
		local function getter()
			return isUseLargerEnabled()
		end
		local function setter(b)
			local frameUF = getBossSystemFrame()
			local settingId = _G.Enum and _G.Enum.EditModeUnitFrameSetting and _G.Enum.EditModeUnitFrameSetting.UseLargerFrame
			local val = (b and true) and 1 or 0
			if frameUF and settingId and addon and addon.EditMode then
				if addon.EditMode.WriteSetting then
					addon.EditMode.WriteSetting(frameUF, settingId, val, {
						updaters        = { "UpdateSystemSettingUseLargerFrame", "UpdateSystemSettingFrameSize" },
						suspendDuration = 0.25,
					})
				elseif addon.EditMode.SetSetting then
					addon.EditMode.SetSetting(frameUF, settingId, val)
					if type(frameUF.UpdateSystemSettingUseLargerFrame) == "function" then pcall(frameUF.UpdateSystemSettingUseLargerFrame, frameUF) end
					if type(frameUF.UpdateSystemSettingFrameSize) == "function" then pcall(frameUF.UpdateSystemSettingFrameSize, frameUF) end
					if addon.EditMode.SaveOnly then addon.EditMode.SaveOnly() end
					if addon.EditMode.RequestApplyChanges then addon.EditMode.RequestApplyChanges(0.2) end
				end
			end

			-- Re-apply conditional enable/disable for Frame Size immediately after the write.
			if C_Timer and C_Timer.After then
				C_Timer.After(0, function()
					applyConditionalAvailability()
				end)
			else
				applyConditionalAvailability()
			end
		end
		local setting = CreateLocalSetting(label, "boolean", getter, setter, getter())
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

	-- 3) Frame Size slider (Edit Mode, 100%..200%, disabled unless Use Larger Frame is enabled)
	do
		local label = "Frame Size"
		local options = Settings.CreateSliderOptions(100, 200, 5)
		options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v)
			return tostring(math.floor((tonumber(v) or 0) + 0.5))
		end)

		local function getter()
			local frameUF = getBossSystemFrame()
			local settingId = _G.Enum and _G.Enum.EditModeUnitFrameSetting and _G.Enum.EditModeUnitFrameSetting.FrameSize
			if frameUF and settingId and addon and addon.EditMode and addon.EditMode.GetSetting then
				local v = addon.EditMode.GetSetting(frameUF, settingId)
				if v == nil then return 100 end
				-- Some clients can return index (0..20); normalize to 100..200.
				if v <= 20 then return 100 + (v * 5) end
				return math.max(100, math.min(200, v))
			end
			return 100
		end

		local function setter(raw)
			local frameUF = getBossSystemFrame()
			local settingId = _G.Enum and _G.Enum.EditModeUnitFrameSetting and _G.Enum.EditModeUnitFrameSetting.FrameSize
			local val = tonumber(raw) or 100
			val = math.max(100, math.min(200, val))
			if frameUF and settingId and addon and addon.EditMode then
				if addon.EditMode.WriteSetting then
					addon.EditMode.WriteSetting(frameUF, settingId, val, {
						updaters        = { "UpdateSystemSettingFrameSize" },
						suspendDuration = 0.25,
					})
				elseif addon.EditMode.SetSetting then
					addon.EditMode.SetSetting(frameUF, settingId, val)
					if type(frameUF.UpdateSystemSettingFrameSize) == "function" then pcall(frameUF.UpdateSystemSettingFrameSize, frameUF) end
					if addon.EditMode.SaveOnly then addon.EditMode.SaveOnly() end
					if addon.EditMode.RequestApplyChanges then addon.EditMode.RequestApplyChanges(0.2) end
				end
			end
		end

		local setting = CreateLocalSetting(label, "number", getter, setter, getter())
		local row = Settings.CreateElementInitializer("SettingsSliderControlTemplate", { name = label, setting = setting, options = options, componentId = componentId })
		row.GetExtent = function() return 34 end
		do
			local base = row.InitFrame
			row.InitFrame = function(self, frame)
				if base then base(self, frame) end
				if panel and panel.ApplyControlTheme then panel.ApplyControlTheme(frame) end
				if panel and panel.ApplyRobotoWhite and frame and frame.Text then panel.ApplyRobotoWhite(frame.Text) end
				if panel and panel.ThemeSliderValue then panel.ThemeSliderValue(frame) end

				-- Tooltip + placement: Info icon to the LEFT of the label explaining the dependency.
				if panel and panel.CreateInfoIcon and frame and not frame.ScooterBossFrameSizeInfoIcon then
					local tooltipText = "Requires 'Use Larger Frame' to be enabled."
					frame.ScooterBossFrameSizeInfoIcon = panel.CreateInfoIcon(frame, tooltipText, "LEFT", "LEFT", 8, 0, 32)
				end
				if frame and frame.ScooterBossFrameSizeInfoIcon and frame.Text then
					frame.ScooterBossFrameSizeInfoIcon:ClearAllPoints()
					frame.ScooterBossFrameSizeInfoIcon:SetPoint("LEFT", frame, "LEFT", 8, 0)

					local slider = (frame.Control and (frame.Control.Slider or frame.Control.slider)) or frame.Slider
					frame.Text:ClearAllPoints()
					frame.Text:SetPoint("LEFT", frame.ScooterBossFrameSizeInfoIcon, "RIGHT", 6, 0)
					if slider then
						frame.Text:SetPoint("RIGHT", slider, "LEFT", -8, 0)
					else
						frame.Text:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
					end
					frame.Text:SetJustifyH("LEFT")
				end

				-- Track this row for conditional enable/disable behavior.
				cond.frameSizeRow = frame
				applyConditionalAvailability()
			end
		end
		table.insert(init, row)
	end
end

--------------------------------------------------------------------------------
-- boss_health: Health Bar section scaffold
--------------------------------------------------------------------------------
local function buildBossHealth(ctx, init)
	local componentId = ctx.componentId
	if componentId ~= "ufBoss" then return end

	local exp = Settings.CreateElementInitializer("ScooterExpandableSectionTemplate", {
		name = "Health Bar",
		sectionKey = "Health Bar",
		componentId = componentId,
		expanded = panel:IsSectionExpanded(componentId, "Health Bar"),
	})
	exp.GetExtent = function() return 30 end
	table.insert(init, exp)

	local tabs = {
		sectionTitle = "",
		-- Boss frames match Target/Focus feature set, except we do NOT offer a Direction tab.
		-- Tabs ordered by Unit Frames tab priority: Style/Texture > Border > Text Elements.
		tabAText = "Style",
		tabBText = "Border",
		tabCText = "% Text",
		tabDText = "Value Text",
		build = function(frame) end,
	}
	tabs.build = function(frame)
		local function unitKey() return "Boss" end
		local function ensureUFDB()
			return ensureBossDB()
		end

		-- Local UI helpers (mirrors `sections/health.lua`)
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

		-- PageA: Style
		do
			local function applyNow()
				if addon and addon.ApplyStyles then addon:ApplyStyles() end
			end
			local y = { y = -50 }
			local function opts() return addon.BuildBarTextureOptionsContainer() end

			-- Foreground Texture dropdown
			local function getTex() local t = ensureUFDB() or {}; return t.healthBarTexture or "default" end
			local function setTex(v) local t = ensureUFDB(); if not t then return end; t.healthBarTexture = v; applyNow() end
			local texSetting = CreateLocalSetting("Foreground Texture", "string", getTex, setTex, getTex())
			local initDrop = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", { name = "Foreground Texture", setting = texSetting, options = opts })
			local f = CreateFrame("Frame", nil, frame.PageA, "SettingsDropdownControlTemplate")
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
			local function setColorMode(v) local t = ensureUFDB(); if not t then return end; t.healthBarColorMode = v or "default"; applyNow() end
			local function getTintTbl()
				local t = ensureUFDB() or {}; local c = t.healthBarTint or {1,1,1,1}
				return { c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 }
			end
			local function setTintTbl(r,g,b,a)
				local t = ensureUFDB(); if not t then return end
				t.healthBarTint = { r or 1, g or 1, b or 1, a or 1 }
				applyNow()
			end
			panel.DropdownWithInlineSwatch(frame.PageA, y, {
				label = "Foreground Color",
				getMode = getColorMode,
				setMode = setColorMode,
				getColor = getTintTbl,
				setColor = setTintTbl,
				options = colorOpts,
				insideButton = true,
			})

			-- Spacer row
			do
				local spacer = CreateFrame("Frame", nil, frame.PageA, "SettingsListElementTemplate")
				spacer:SetHeight(20)
				spacer:SetPoint("TOPLEFT", 4, y.y)
				spacer:SetPoint("TOPRIGHT", -16, y.y)
				if spacer.Text then spacer.Text:SetText("") end
				y.y = y.y - 24
			end

			-- Background Texture dropdown
			local function getBgTex() local t = ensureUFDB() or {}; return t.healthBarBackgroundTexture or "default" end
			local function setBgTex(v) local t = ensureUFDB(); if not t then return end; t.healthBarBackgroundTexture = v; applyNow() end
			local bgTexSetting = CreateLocalSetting("Background Texture", "string", getBgTex, setBgTex, getBgTex())
			local initBgDrop = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", { name = "Background Texture", setting = bgTexSetting, options = opts })
			local fbg = CreateFrame("Frame", nil, frame.PageA, "SettingsDropdownControlTemplate")
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
			local function setBgColorMode(v) local t = ensureUFDB(); if not t then return end; t.healthBarBackgroundColorMode = v or "default"; applyNow() end
			local function getBgTintTbl()
				local t = ensureUFDB() or {}; local c = t.healthBarBackgroundTint or {0,0,0,1}
				return { c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1 }
			end
			local function setBgTintTbl(r,g,b,a)
				local t = ensureUFDB(); if not t then return end
				t.healthBarBackgroundTint = { r or 0, g or 0, b or 0, a or 1 }
				applyNow()
			end
			panel.DropdownWithInlineSwatch(frame.PageA, y, {
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
			local fOpa = CreateFrame("Frame", nil, frame.PageA, "SettingsSliderControlTemplate")
			fOpa.GetElementData = function() return bgOpacityInit end
			fOpa:SetPoint("TOPLEFT", 4, y.y)
			fOpa:SetPoint("TOPRIGHT", -16, y.y)
			bgOpacityInit:InitFrame(fOpa)
			if panel and panel.ApplyControlTheme then panel.ApplyControlTheme(fOpa) end
			if panel and panel.ApplyRobotoWhite and fOpa.Text then panel.ApplyRobotoWhite(fOpa.Text) end
			y.y = y.y - 48
		end

		-- PageB: Border
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
				local t = ensureUFDB() or {}; return t.healthBarBorderStyle or "square"
			end
			local function setStyle(v)
				local t = ensureUFDB(); if not t then return end
				t.healthBarBorderStyle = v or "square"
				applyNow()
			end
			local styleSetting = CreateLocalSetting("Border Style", "string", getStyle, setStyle, getStyle())
			local initDrop = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", { name = "Border Style", setting = styleSetting, options = optionsBorder })
			local f = CreateFrame("Frame", nil, frame.PageB, "SettingsDropdownControlTemplate")
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
				local row = CreateFrame("Frame", nil, frame.PageB, "SettingsCheckboxControlTemplate")
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
				local sf = CreateFrame("Frame", nil, frame.PageB, "SettingsSliderControlTemplate")
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
				local sf = CreateFrame("Frame", nil, frame.PageB, "SettingsSliderControlTemplate")
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

		-- PageC: % Text
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
				local t = ensureUFDB()
				return t and not not t.healthPercentHidden or false
			end
			local function setter(v)
				local t = ensureUFDB(); if not t then return end
				t.healthPercentHidden = (v and true) or false
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
				if cb and panel.ThemeCheckbox then panel.ThemeCheckbox(cb) end
			end
			y.y = y.y - 34

			addDropdown(frame.PageC, "% Text Font", fontOptions,
				function() local t = ensureUFDB() or {}; local s = t.textHealthPercent or {}; return s.fontFace or "FRIZQT__" end,
				function(v) local t = ensureUFDB(); if not t then return end; t.textHealthPercent = t.textHealthPercent or {}; t.textHealthPercent.fontFace = v; applyNow() end,
				y)
			addStyle(frame.PageC, "% Text Style",
				function() local t = ensureUFDB() or {}; local s = t.textHealthPercent or {}; return s.style or "OUTLINE" end,
				function(v) local t = ensureUFDB(); if not t then return end; t.textHealthPercent = t.textHealthPercent or {}; t.textHealthPercent.style = v; applyNow() end,
				y)
			addSlider(frame.PageC, "% Text Size", 6, 48, 1,
				function() local t = ensureUFDB() or {}; local s = t.textHealthPercent or {}; return tonumber(s.size) or 14 end,
				function(v) local t = ensureUFDB(); if not t then return end; t.textHealthPercent = t.textHealthPercent or {}; t.textHealthPercent.size = tonumber(v) or 14; applyNow() end,
				y)
			addColor(frame.PageC, "% Text Color", true,
				function() local t = ensureUFDB() or {}; local s = t.textHealthPercent or {}; local c = s.color or {1,1,1,1}; return c[1], c[2], c[3], c[4] end,
				function(r,g,b,a) local t = ensureUFDB(); if not t then return end; t.textHealthPercent = t.textHealthPercent or {}; t.textHealthPercent.color = {r,g,b,a}; applyNow() end,
				y)
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
				local setting2 = CreateLocalSetting("% Text Alignment", "string", getAlign, setAlign, getAlign())
				local initDrop = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", { name = "% Text Alignment", setting = setting2, options = alignOpts })
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
				y.y = y.y - 34
			end
			addSlider(frame.PageC, "% Text Offset X", -100, 100, 1,
				function() local t = ensureUFDB() or {}; local s = t.textHealthPercent or {}; local o = s.offset or {}; return tonumber(o.x) or 0 end,
				function(v) local t = ensureUFDB(); if not t then return end; t.textHealthPercent = t.textHealthPercent or {}; t.textHealthPercent.offset = t.textHealthPercent.offset or {}; t.textHealthPercent.offset.x = tonumber(v) or 0; applyNow() end,
				y)
			addSlider(frame.PageC, "% Text Offset Y", -100, 100, 1,
				function() local t = ensureUFDB() or {}; local s = t.textHealthPercent or {}; local o = s.offset or {}; return tonumber(o.y) or 0 end,
				function(v) local t = ensureUFDB(); if not t then return end; t.textHealthPercent = t.textHealthPercent or {}; t.textHealthPercent.offset = t.textHealthPercent.offset or {}; t.textHealthPercent.offset.y = tonumber(v) or 0; applyNow() end,
				y)
		end

		-- PageD: Value Text
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
				local t = ensureUFDB()
				return t and not not t.healthValueHidden or false
			end
			local function setter(v)
				local t = ensureUFDB(); if not t then return end
				t.healthValueHidden = (v and true) or false
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
				if cb and panel.ThemeCheckbox then panel.ThemeCheckbox(cb) end
			end
			y.y = y.y - 34
			addDropdown(frame.PageD, "Value Text Font", fontOptions,
				function() local t = ensureUFDB() or {}; local s = t.textHealthValue or {}; return s.fontFace or "FRIZQT__" end,
				function(v) local t = ensureUFDB(); if not t then return end; t.textHealthValue = t.textHealthValue or {}; t.textHealthValue.fontFace = v; applyNow() end,
				y)
			addStyle(frame.PageD, "Value Text Style",
				function() local t = ensureUFDB() or {}; local s = t.textHealthValue or {}; return s.style or "OUTLINE" end,
				function(v) local t = ensureUFDB(); if not t then return end; t.textHealthValue = t.textHealthValue or {}; t.textHealthValue.style = v; applyNow() end,
				y)
			addSlider(frame.PageD, "Value Text Size", 6, 48, 1,
				function() local t = ensureUFDB() or {}; local s = t.textHealthValue or {}; return tonumber(s.size) or 14 end,
				function(v) local t = ensureUFDB(); if not t then return end; t.textHealthValue = t.textHealthValue or {}; t.textHealthValue.size = tonumber(v) or 14; applyNow() end,
				y)
			addColor(frame.PageD, "Value Text Color", true,
				function() local t = ensureUFDB() or {}; local s = t.textHealthValue or {}; local c = s.color or {1,1,1,1}; return c[1], c[2], c[3], c[4] end,
				function(r,g,b,a) local t = ensureUFDB(); if not t then return end; t.textHealthValue = t.textHealthValue or {}; t.textHealthValue.color = {r,g,b,a}; applyNow() end,
				y)
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
				local setting2 = CreateLocalSetting("Value Text Alignment", "string", getAlign, setAlign, getAlign())
				local initDrop = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", { name = "Value Text Alignment", setting = setting2, options = alignOpts })
				local f = CreateFrame("Frame", nil, frame.PageD, "SettingsDropdownControlTemplate")
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
			addSlider(frame.PageD, "Value Text Offset X", -100, 100, 1,
				function() local t = ensureUFDB() or {}; local s = t.textHealthValue or {}; local o = s.offset or {}; return tonumber(o.x) or 0 end,
				function(v) local t = ensureUFDB(); if not t then return end; t.textHealthValue = t.textHealthValue or {}; t.textHealthValue.offset = t.textHealthValue.offset or {}; t.textHealthValue.offset.x = tonumber(v) or 0; applyNow() end,
				y)
			addSlider(frame.PageD, "Value Text Offset Y", -100, 100, 1,
				function() local t = ensureUFDB() or {}; local s = t.textHealthValue or {}; local o = s.offset or {}; return tonumber(o.y) or 0 end,
				function(v) local t = ensureUFDB(); if not t then return end; t.textHealthValue = t.textHealthValue or {}; t.textHealthValue.offset = t.textHealthValue.offset or {}; t.textHealthValue.offset.y = tonumber(v) or 0; applyNow() end,
				y)
		end

		-- Apply current visibility once when building
		if addon and addon.ApplyUnitFrameHealthTextVisibilityFor then addon.ApplyUnitFrameHealthTextVisibilityFor(unitKey()) end
	end
	local tInit = Settings.CreateElementInitializer("ScooterTabbedSectionTemplate", tabs)
	tInit.GetExtent = function() return 364 end
	tInit:AddShownPredicate(function() return panel:IsSectionExpanded(componentId, "Health Bar") end)
	table.insert(init, tInit)
end

--------------------------------------------------------------------------------
-- boss_power: Power Bar section scaffold
--------------------------------------------------------------------------------
local function buildBossPower(ctx, init)
	local componentId = ctx.componentId
	if componentId ~= "ufBoss" then return end

	local exp = Settings.CreateElementInitializer("ScooterExpandableSectionTemplate", {
		name = "Power Bar",
		sectionKey = "Power Bar",
		componentId = componentId,
		expanded = panel:IsSectionExpanded(componentId, "Power Bar"),
	})
	exp.GetExtent = function() return 30 end
	table.insert(init, exp)

	local tabs = {
		sectionTitle = "",
		-- Boss frames match Target/Focus feature set, except we do NOT offer custom Positioning/Sizing/Direction for Power.
		-- Tabs ordered by Unit Frames tab priority: Style/Texture > Border > Visibility.
		tabAText = "Style",
		tabBText = "Border",
		tabCText = "Visibility",
		build = function(frame) end,
	}
	tabs.build = function(frame)
		local function unitKey() return "Boss" end
		local function ensureUFDB()
			return ensureBossDB()
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

		-- PageA: Style (Power Bar foreground/background texture + color)
		do
			local function applyNow()
				if addon and addon.ApplyStyles then addon:ApplyStyles() end
			end
			local y = { y = -50 }
			local function opts() return addon.BuildBarTextureOptionsContainer() end

			-- Foreground Texture dropdown
			local function getTex() local t = ensureUFDB() or {}; return t.powerBarTexture or "default" end
			local function setTex(v) local t = ensureUFDB(); if not t then return end; t.powerBarTexture = v; applyNow() end
			local texSetting = CreateLocalSetting("Foreground Texture", "string", getTex, setTex, getTex())
			local initDrop = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", { name = "Foreground Texture", setting = texSetting, options = opts })
			local f = CreateFrame("Frame", nil, frame.PageA, "SettingsDropdownControlTemplate")
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
			local function setColorMode(v) local t = ensureUFDB(); if not t then return end; t.powerBarColorMode = v or "default"; applyNow() end
			local function getTintTbl()
				local t = ensureUFDB() or {}; local c = t.powerBarTint or {1,1,1,1}
				return { c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 }
			end
			local function setTintTbl(r,g,b,a)
				local t = ensureUFDB(); if not t then return end
				t.powerBarTint = { r or 1, g or 1, b or 1, a or 1 }
				applyNow()
			end
			panel.DropdownWithInlineSwatch(frame.PageA, y, {
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
				local spacer = CreateFrame("Frame", nil, frame.PageA, "SettingsListElementTemplate")
				spacer:SetHeight(20)
				spacer:SetPoint("TOPLEFT", 4, y.y)
				spacer:SetPoint("TOPRIGHT", -16, y.y)
				if spacer.Text then spacer.Text:SetText("") end
				y.y = y.y - 24
			end

			-- Background Texture dropdown
			local function getBgTex() local t = ensureUFDB() or {}; return t.powerBarBackgroundTexture or "default" end
			local function setBgTex(v) local t = ensureUFDB(); if not t then return end; t.powerBarBackgroundTexture = v; applyNow() end
			local bgTexSetting = CreateLocalSetting("Background Texture", "string", getBgTex, setBgTex, getBgTex())
			local initBgDrop = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", { name = "Background Texture", setting = bgTexSetting, options = opts })
			local fbg = CreateFrame("Frame", nil, frame.PageA, "SettingsDropdownControlTemplate")
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
			local function setBgColorMode(v) local t = ensureUFDB(); if not t then return end; t.powerBarBackgroundColorMode = v or "default"; applyNow() end
			local function getBgTintTbl()
				local t = ensureUFDB() or {}; local c = t.powerBarBackgroundTint or {0,0,0,1}
				return { c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1 }
			end
			local function setBgTintTbl(r,g,b,a)
				local t = ensureUFDB(); if not t then return end
				t.powerBarBackgroundTint = { r or 0, g or 0, b or 0, a or 1 }
				applyNow()
			end
			panel.DropdownWithInlineSwatch(frame.PageA, y, {
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
			local fOpa = CreateFrame("Frame", nil, frame.PageA, "SettingsSliderControlTemplate")
			fOpa.GetElementData = function() return bgOpacityInit end
			fOpa:SetPoint("TOPLEFT", 4, y.y)
			fOpa:SetPoint("TOPRIGHT", -16, y.y)
			bgOpacityInit:InitFrame(fOpa)
			if panel and panel.ApplyControlTheme then panel.ApplyControlTheme(fOpa) end
			if panel and panel.ApplyRobotoWhite and fOpa.Text then panel.ApplyRobotoWhite(fOpa.Text) end
			y.y = y.y - 48
		end

		-- PageB: Border (Power Bar)
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
			local function getStyle() local t = ensureUFDB() or {}; return t.powerBarBorderStyle or "square" end
			local function setStyle(v) local t = ensureUFDB(); if not t then return end; t.powerBarBorderStyle = v or "square"; applyNow() end

			local styleSetting = CreateLocalSetting("Border Style", "string", getStyle, setStyle, getStyle())
			local initDrop = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", { name = "Border Style", setting = styleSetting, options = optionsBorder })
			local f = CreateFrame("Frame", nil, frame.PageB, "SettingsDropdownControlTemplate")
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
				local function getTintEnabled() local t = ensureUFDB() or {}; return not not t.powerBarBorderTintEnable end
				local function setTintEnabled(b) local t = ensureUFDB(); if not t then return end; t.powerBarBorderTintEnable = not not b; applyNow() end
				local function getTint()
					local t = ensureUFDB() or {}; local c = t.powerBarBorderTintColor or {1,1,1,1}
					return { c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 }
				end
				local function setTint(r,g,b,a) local t = ensureUFDB(); if not t then return end; t.powerBarBorderTintColor = { r or 1, g or 1, b or 1, a or 1 }; applyNow() end
				local tintSetting = CreateLocalSetting("Border Tint", "boolean", getTintEnabled, setTintEnabled, getTintEnabled())
				local initCb = CreateCheckboxWithSwatchInitializer(tintSetting, "Border Tint", getTint, setTint, 8)
				local row = CreateFrame("Frame", nil, frame.PageB, "SettingsCheckboxControlTemplate")
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
				local function getThk() local t = ensureUFDB() or {}; return tonumber(t.powerBarBorderThickness) or 1 end
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
				local sf = CreateFrame("Frame", nil, frame.PageB, "SettingsSliderControlTemplate")
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
				local function getInset() local t = ensureUFDB() or {}; return tonumber(t.powerBarBorderInset) or 0 end
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
				local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = "Border Inset", setting = insetSetting, options = opts })
				local sf = CreateFrame("Frame", nil, frame.PageB, "SettingsSliderControlTemplate")
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

		-- PageC: Visibility
		do
			local function applyNow()
				local uk = unitKey()
				if uk and addon and addon.ApplyUnitFrameBarTexturesFor then addon.ApplyUnitFrameBarTexturesFor(uk) end
				if uk and addon and addon.ApplyUnitFramePowerTextVisibilityFor then addon.ApplyUnitFramePowerTextVisibilityFor(uk) end
			end

			local y = { y = -50 }

			-- Hide Power Bar
			do
				local label = "Hide Power Bar"
				local function getter()
					local t = ensureUFDB()
					return t and not not t.powerBarHidden or false
				end
				local function setter(v)
					local t = ensureUFDB(); if not t then return end
					t.powerBarHidden = (v and true) or false
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
					if cb and panel.ThemeCheckbox then panel.ThemeCheckbox(cb) end
				end
				y.y = y.y - 34
			end

			-- Hide only the Bar Texture (number-only display)
			do
				local label = "Hide only the Bar Texture"
				local function getter()
					local t = ensureUFDB()
					return t and not not t.powerBarHideTextureOnly or false
				end
				local function setter(v)
					local t = ensureUFDB(); if not t then return end
					t.powerBarHideTextureOnly = (v and true) or false
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
					if cb and panel.ThemeCheckbox then panel.ThemeCheckbox(cb) end
				end
				y.y = y.y - 34
			end
		end

		-- NOTE: Boss power bars do not display text (Blizzard never wires up SetBarText() for Boss ManaBar),
		-- so we intentionally do not expose %/Value Text controls here.
	end
	local tInit = Settings.CreateElementInitializer("ScooterTabbedSectionTemplate", tabs)
	tInit.GetExtent = function() return 364 end
	tInit:AddShownPredicate(function() return panel:IsSectionExpanded(componentId, "Power Bar") end)
	table.insert(init, tInit)
end

--------------------------------------------------------------------------------
-- boss_nametext: Name Text section scaffold
--------------------------------------------------------------------------------
local function buildBossNameText(ctx, init)
	local componentId = ctx.componentId
	if componentId ~= "ufBoss" then return end

	local exp = Settings.CreateElementInitializer("ScooterExpandableSectionTemplate", {
		name = "Name Text",
		sectionKey = "Name Text",
		componentId = componentId,
		expanded = panel:IsSectionExpanded(componentId, "Name Text"),
	})
	exp.GetExtent = function() return 30 end
	table.insert(init, exp)

	local tabs = {
		sectionTitle = "",
		tabAText = "Backdrop",
		tabBText = "Border",
		tabCText = "Name Text",
	}

	tabs.build = function(frame)
		-- DB helper (Boss is a unitFrames table entry like Player/Target/Focus/etc.)
		local function ensureUFDB()
			return ensureBossDB()
		end

		local function applyNow()
			if addon and addon.ApplyUnitFrameNameLevelTextFor then
				addon.ApplyUnitFrameNameLevelTextFor("Boss")
			end
			if addon and addon.ApplyStyles then
				addon:ApplyStyles()
			end
		end

		-- Local UI helpers (mirrors `sections/classresource.lua` Name & Level Text)
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
			if type(label) == "string" and string.find(label, "Font") and not string.find(label, "Style")
				and f.Control and f.Control.Dropdown and addon and addon.InitFontDropdown then
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
			addDropdown(parent, label, styleOptions, getFunc, setFunc, yRef)
		end

		--------------------------------------------------------------------
		-- Tab A: Backdrop (Name Backdrop strip + color/opacity/width)
		--------------------------------------------------------------------
		do
			local y = { y = -50 }

			local function isBackdropEnabled()
				local t = ensureUFDB() or {}
				return not not t.nameBackdropEnabled
			end

			local _bdTexFrame, _bdWidthFrame, _bdOpacityFrame, _bdColorFrame
			local function refreshBackdropEnabledState()
				local en = isBackdropEnabled()
				if _bdTexFrame and _bdTexFrame.Control and _bdTexFrame.Control.SetEnabled then _bdTexFrame.Control:SetEnabled(en) end
				do
					local lbl = _bdTexFrame and (_bdTexFrame.Text or _bdTexFrame.Label)
					if lbl and lbl.SetTextColor then lbl:SetTextColor(en and 1 or 0.6, en and 1 or 0.6, en and 1 or 0.6, 1) end
				end
				if _bdWidthFrame and _bdWidthFrame.Control and _bdWidthFrame.Control.SetEnabled then _bdWidthFrame.Control:SetEnabled(en) end
				if _bdWidthFrame and _bdWidthFrame.Text and _bdWidthFrame.Text.SetTextColor then _bdWidthFrame.Text:SetTextColor(en and 1 or 0.6, en and 1 or 0.6, en and 1 or 0.6, 1) end
				if _bdOpacityFrame and _bdOpacityFrame.Control and _bdOpacityFrame.Control.SetEnabled then _bdOpacityFrame.Control:SetEnabled(en) end
				if _bdOpacityFrame and _bdOpacityFrame.Text and _bdOpacityFrame.Text.SetTextColor then _bdOpacityFrame.Text:SetTextColor(en and 1 or 0.6, en and 1 or 0.6, en and 1 or 0.6, 1) end
				-- _bdColorFrame (inline swatch dropdown) handles enabled state via callback.
			end

			-- Enable Backdrop
			do
				local label = "Enable Backdrop"
				local function getter()
					return isBackdropEnabled()
				end
				local function setter(v)
					local t = ensureUFDB(); if not t then return end
					t.nameBackdropEnabled = not not v
					applyNow()
					refreshBackdropEnabledState()
				end
				local setting = CreateLocalSetting(label, "boolean", getter, setter, getter())
				local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = label, setting = setting, options = {} })
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

			-- Backdrop Texture (no "Default" entry)
			do
				local function get()
					local t = ensureUFDB() or {}
					return t.nameBackdropTexture or ""
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
				do
					local en = isBackdropEnabled()
					if f and f.Control and f.Control.SetEnabled then f.Control:SetEnabled(en) end
					local lbl = f and (f.Text or f.Label)
					if lbl and lbl.SetTextColor then lbl:SetTextColor(en and 1 or 0.6, en and 1 or 0.6, en and 1 or 0.6, 1) end
				end
				_bdTexFrame = f
			end

			-- Backdrop Color mode (Default / Texture Original / Custom) + inline swatch
			do
				local function getMode()
					local t = ensureUFDB() or {}
					return t.nameBackdropColorMode or "default"
				end
				local function setMode(v)
					local t = ensureUFDB(); if not t then return end
					t.nameBackdropColorMode = v or "default"
					applyNow()
					refreshBackdropEnabledState()
				end
				local function getColor()
					local t = ensureUFDB() or {}
					local c = t.nameBackdropTint or { 1, 1, 1, 1 }
					return c
				end
				local function setColor(r, g, b, a)
					local t = ensureUFDB(); if not t then return end
					t.nameBackdropTint = { r, g, b, a }
					applyNow()
				end
				local function colorOpts()
					local container = Settings.CreateControlTextContainer()
					container:Add("default", "Default")
					container:Add("texture", "Texture Original")
					container:Add("custom", "Custom")
					return container:GetData()
				end
				local f = panel.DropdownWithInlineSwatch(frame.PageA, y, {
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
					local t = ensureUFDB() or {}
					local v = tonumber(t.nameBackdropWidthPct) or 100
					if v < 25 then v = 25 elseif v > 300 then v = 300 end
					return v
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
					local t = ensureUFDB() or {}
					local v = tonumber(t.nameBackdropOpacity) or 50
					if v < 0 then v = 0 elseif v > 100 then v = 100 end
					return v
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

		--------------------------------------------------------------------
		-- Tab B: Border (Name Backdrop border)
		--------------------------------------------------------------------
		do
			local y = { y = -50 }

			local function isEnabled()
				local t = ensureUFDB() or {}
				local localEnabled = not not t.nameBackdropBorderEnabled
				local globalEnabled = not not t.useCustomBorders
				return localEnabled and globalEnabled
			end

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
				local label = "Enable Border"
				local function getter()
					local t = ensureUFDB() or {}
					return not not t.nameBackdropBorderEnabled
				end
				local function setter(v)
					local t = ensureUFDB(); if not t then return end
					t.nameBackdropBorderEnabled = not not v
					applyNow()
					refreshBorderEnabledState()
				end
				local setting = CreateLocalSetting(label, "boolean", getter, setter, getter())
				local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = label, setting = setting, options = {} })
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
				local function getStyle()
					local t = ensureUFDB() or {}
					return t.nameBackdropBorderStyle or "square"
				end
				local function setStyle(v)
					local t = ensureUFDB(); if not t then return end
					t.nameBackdropBorderStyle = v or "square"
					applyNow()
					refreshBorderEnabledState()
				end
				local function optionsBorder()
					return addon.BuildBarBorderOptionsContainer and addon.BuildBarBorderOptionsContainer() or {
						{ value = "square", text = "Default (Square)" }
					}
				end
				local styleSetting = CreateLocalSetting("Border Style", "string", getStyle, setStyle, getStyle())
				local initDrop = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", { name = "Border Style", setting = styleSetting, options = optionsBorder })
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
					local t = ensureUFDB() or {}
					return not not t.nameBackdropBorderTintEnable
				end
				local function setTintEnabled(b)
					local t = ensureUFDB(); if not t then return end
					t.nameBackdropBorderTintEnable = not not b
					applyNow()
				end
				local function getTint()
					local t = ensureUFDB() or {}
					local c = t.nameBackdropBorderTintColor or { 1, 1, 1, 1 }
					return { c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 }
				end
				local function setTint(r, g, b, a)
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
				local function getThk()
					local t = ensureUFDB() or {}
					return tonumber(t.nameBackdropBorderThickness) or 1
				end
				local function setThk(v)
					local t = ensureUFDB(); if not t then return end
					local nv = tonumber(v) or 1
					if nv < 1 then nv = 1 elseif nv > 8 then nv = 8 end
					t.nameBackdropBorderThickness = nv
					applyNow()
				end
				local opts = Settings.CreateSliderOptions(1, 8, 0.2)
				opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return string.format("%.1f", v) end)
				local thkSetting = CreateLocalSetting("Border Thickness", "number", getThk, setThk, getThk())
				local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = "Border Thickness", setting = thkSetting, options = opts })
				local sf = CreateFrame("Frame", nil, frame.PageB, "SettingsSliderControlTemplate")
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
				local function getInset()
					local t = ensureUFDB() or {}
					return tonumber(t.nameBackdropBorderInset) or 0
				end
				local function setInset(v)
					local t = ensureUFDB(); if not t then return end
					local nv = tonumber(v) or 0
					if nv < -4 then nv = -4 elseif nv > 4 then nv = 4 end
					t.nameBackdropBorderInset = nv
					applyNow()
				end
				local opts = Settings.CreateSliderOptions(-4, 4, 1)
				opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return tostring(math.floor(v)) end)
				local insetSetting = CreateLocalSetting("Border Inset", "number", getInset, setInset, getInset())
				local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = "Border Inset", setting = insetSetting, options = opts })
				local sf = CreateFrame("Frame", nil, frame.PageB, "SettingsSliderControlTemplate")
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

		--------------------------------------------------------------------
		-- Tab C: Name Text (font/style/size/color/offset + visibility)
		--------------------------------------------------------------------
		do
			local y = { y = -50 }

			-- Disable Name Text checkbox
			do
				local label = "Disable Name Text"
				local function getter()
					local t = ensureUFDB()
					return t and not not t.nameTextHidden or false
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
			end

			local function fontOptions()
				return addon.BuildFontOptionsContainer()
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
					c:Add("custom", "Custom")
					return c:GetData()
				end
				local function getMode()
					local t = ensureUFDB() or {}
					local s = t.textName or {}
					local mode = s.colorMode or "default"
					-- Boss frames have no class; normalize any stray "class" setting to default.
					if mode == "class" then
						mode = "default"
						if t then
							t.textName = t.textName or {}
							t.textName.colorMode = "default"
						end
					end
					return mode
				end
				local function setMode(v)
					local t = ensureUFDB(); if not t then return end
					if v == "class" then v = "default" end
					t.textName = t.textName or {}
					t.textName.colorMode = v or "default"
					applyNow()
				end
				local function getColorTbl()
					local t = ensureUFDB() or {}
					local s = t.textName or {}
					local c = s.color or { 1.0, 0.82, 0.0, 1 }
					return { c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 }
				end
				local function setColorTbl(r, g, b, a)
					local t = ensureUFDB(); if not t then return end
					t.textName = t.textName or {}
					t.textName.color = { r or 1, g or 1, b or 1, a or 1 }
					applyNow()
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
	end

	local tInit = Settings.CreateElementInitializer("ScooterTabbedSectionTemplate", tabs)
	tInit.GetExtent = function() return 364 end
	tInit:AddShownPredicate(function() return panel:IsSectionExpanded(componentId, "Name Text") end)
	table.insert(init, tInit)
end

--------------------------------------------------------------------------------
-- boss_cast: Cast Bar section scaffold (+ Cast Bar on Side setting in Positioning tab)
--------------------------------------------------------------------------------
local function buildBossCast(ctx, init)
	local componentId = ctx.componentId
	local panel = ctx.panel or panel
	if componentId ~= "ufBoss" then return end

	local exp = Settings.CreateElementInitializer("ScooterExpandableSectionTemplate", {
		name = "Cast Bar",
		sectionKey = "Cast Bar",
		componentId = componentId,
		expanded = panel:IsSectionExpanded(componentId, "Cast Bar"),
	})
	exp.GetExtent = function() return 30 end
	table.insert(init, exp)

	local tabs = {
		sectionTitle = "",
		tabAText = "Positioning",
		tabBText = "Sizing",
		tabCText = "Style",
		tabDText = "Border",
		tabEText = "Icon",
		tabFText = "Spell Name Text",
		tabGText = "Visibility",
	}

	tabs.build = function(frame)
		-- PageA: Positioning (only Cast Bar on Side for now)
		do
			local y = { y = -50 }
			local label = "Cast Bar on Side"
			local function getter()
				local frameUF = getBossSystemFrame()
				local settingId = _G.Enum and _G.Enum.EditModeUnitFrameSetting and _G.Enum.EditModeUnitFrameSetting.CastBarOnSide
				if frameUF and settingId and addon and addon.EditMode and addon.EditMode.GetSetting then
					local v = addon.EditMode.GetSetting(frameUF, settingId)
					return (v and v ~= 0) and true or false
				end
				return false
			end
			local function setter(b)
				local frameUF = getBossSystemFrame()
				local settingId = _G.Enum and _G.Enum.EditModeUnitFrameSetting and _G.Enum.EditModeUnitFrameSetting.CastBarOnSide
				local val = (b and true) and 1 or 0
				if frameUF and settingId and addon and addon.EditMode then
					if addon.EditMode.WriteSetting then
						addon.EditMode.WriteSetting(frameUF, settingId, val, {
							updaters        = { "UpdateSystemSettingCastBarOnSide" },
							suspendDuration = 0.25,
						})
					elseif addon.EditMode.SetSetting then
						addon.EditMode.SetSetting(frameUF, settingId, val)
						if type(frameUF.UpdateSystemSettingCastBarOnSide) == "function" then pcall(frameUF.UpdateSystemSettingCastBarOnSide, frameUF) end
						if addon.EditMode.SaveOnly then addon.EditMode.SaveOnly() end
						if addon.EditMode.RequestApplyChanges then addon.EditMode.RequestApplyChanges(0.2) end
					end
				end
			end
			local setting = CreateLocalSetting(label, "boolean", getter, setter, getter())
			local row = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = label, setting = setting, options = {} })
			local f = CreateFrame("Frame", nil, frame.PageA, "SettingsCheckboxControlTemplate")
			f.GetElementData = function() return row end
			f:SetPoint("TOPLEFT", 4, y.y)
			f:SetPoint("TOPRIGHT", -16, y.y)
			row:InitFrame(f)
			if panel and panel.ApplyRobotoWhite and f.Text then panel.ApplyRobotoWhite(f.Text) end
			if panel and panel.ApplyControlTheme then panel.ApplyControlTheme(f) end
			y.y = y.y - 34
		end
	end

	local tInit = Settings.CreateElementInitializer("ScooterTabbedSectionTemplate", tabs)
	tInit.GetExtent = function() return 364 end
	tInit:AddShownPredicate(function() return panel:IsSectionExpanded(componentId, "Cast Bar") end)
	table.insert(init, tInit)
end

--------------------------------------------------------------------------------
-- boss_visibility: Visibility section scaffold
--------------------------------------------------------------------------------
local function buildBossVisibility(ctx, init)
	local componentId = ctx.componentId
	if componentId ~= "ufBoss" then return end

	local exp = Settings.CreateElementInitializer("ScooterExpandableSectionTemplate", {
		name = "Visibility",
		sectionKey = "Visibility",
		componentId = componentId,
		expanded = panel:IsSectionExpanded(componentId, "Visibility"),
	})
	exp.GetExtent = function() return 30 end
	table.insert(init, exp)
end

--------------------------------------------------------------------------------
-- boss_misc: Misc section scaffold
--------------------------------------------------------------------------------
local function buildBossMisc(ctx, init)
	local componentId = ctx.componentId
	if componentId ~= "ufBoss" then return end

	local exp = Settings.CreateElementInitializer("ScooterExpandableSectionTemplate", {
		name = "Misc",
		sectionKey = "Misc",
		componentId = componentId,
		expanded = panel:IsSectionExpanded(componentId, "Misc"),
	})
	exp.GetExtent = function() return 30 end
	table.insert(init, exp)
end

panel.UnitFramesSections.boss_root = buildBossRoot
panel.UnitFramesSections.boss_health = buildBossHealth
panel.UnitFramesSections.boss_power = buildBossPower
panel.UnitFramesSections.boss_nametext = buildBossNameText
panel.UnitFramesSections.boss_cast = buildBossCast
panel.UnitFramesSections.boss_visibility = buildBossVisibility
panel.UnitFramesSections.boss_misc = buildBossMisc

return {
	boss_root = buildBossRoot,
	boss_health = buildBossHealth,
	boss_power = buildBossPower,
	boss_nametext = buildBossNameText,
	boss_cast = buildBossCast,
	boss_visibility = buildBossVisibility,
	boss_misc = buildBossMisc,
}


