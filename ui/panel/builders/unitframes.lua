local addonName, addon = ...

addon.SettingsPanel = addon.SettingsPanel or {}
local panel = addon.SettingsPanel

-- Unit Frames placeholder renderers -------------------------------------------
local function createUFRenderer(componentId, title)
        local render = function()
            local f = panel.frame
            local right = f and f.RightPane
            if not f or not right or not right.Display then return end

            local init = {}

			-- Top-level Parent Frame rows (no collapsible or tabs)
			-- Shared helpers for the four unit frames
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
			local function getUnitFrame()
				local mgr = _G.EditModeManagerFrame
				local EM = _G.Enum and _G.Enum.EditModeUnitFrameSystemIndices
				local EMSys = _G.Enum and _G.Enum.EditModeSystem
				if not (mgr and EM and EMSys and mgr.GetRegisteredSystemFrame) then return nil end
				local idx = (componentId == "ufPlayer" and EM.Player)
					or (componentId == "ufTarget" and EM.Target)
					or (componentId == "ufFocus" and EM.Focus)
					or (componentId == "ufPet" and EM.Pet)
					or nil
				if not idx then return nil end
				return mgr:GetRegisteredSystemFrame(EMSys.UnitFrame, idx)
			end
			local function readOffsets()
				local fUF = getUnitFrame()
				if not fUF then return 0, 0 end
				if fUF.GetPoint then
					local p, relTo, rp, ox, oy = fUF:GetPoint(1)
					if p == "CENTER" and rp == "CENTER" and relTo == UIParent and type(ox) == "number" and type(oy) == "number" then
						return uiUnitsToPixels(ox), uiUnitsToPixels(oy)
					end
				end
				if not (fUF.GetCenter and UIParent and UIParent.GetCenter) then return 0, 0 end
				local fx, fy = fUF:GetCenter()
				local px, py = UIParent:GetCenter()
				if not (fx and fy and px and py) then return 0, 0 end
				return math.floor((fx - px) + 0.5), math.floor((fy - py) + 0.5)
			end
			local _pendingPxX, _pendingPxY, _pendingWriteTimer
			local function writeOffsets(newX, newY)
				local fUF = getUnitFrame()
				if not fUF then return end
				local curPxX, curPxY = readOffsets()
				_pendingPxX = (newX ~= nil) and clampPositionValue(roundPositionValue(newX)) or curPxX
				_pendingPxY = (newY ~= nil) and clampPositionValue(roundPositionValue(newY)) or curPxY
				if _pendingWriteTimer and _pendingWriteTimer.Cancel then _pendingWriteTimer:Cancel() end
				_pendingWriteTimer = C_Timer.NewTimer(0.1, function()
					local pxX = clampPositionValue(roundPositionValue(_pendingPxX or 0))
					local pxY = clampPositionValue(roundPositionValue(_pendingPxY or 0))
					local ux = pixelsToUiUnits(pxX)
					local uy = pixelsToUiUnits(pxY)
					-- Normalize anchor once if needed
					if fUF.GetPoint then
						local p, relTo, rp = fUF:GetPoint(1)
						if not (p == "CENTER" and rp == "CENTER" and relTo == UIParent) then
							if fUF.GetCenter and UIParent and UIParent.GetCenter then
								local fx, fy = fUF:GetCenter(); local cx, cy = UIParent:GetCenter()
								if fx and fy and cx and cy then
									local curUx = pixelsToUiUnits((fx - cx))
									local curUy = pixelsToUiUnits((fy - cy))
									if addon and addon.EditMode and addon.EditMode.ReanchorFrame then
										addon.EditMode.ReanchorFrame(fUF, "CENTER", UIParent, "CENTER", curUx, curUy)
										if addon.EditMode.SaveOnly then addon.EditMode.SaveOnly() end
									end
								end
							end
						end
					end
					if addon and addon.EditMode and addon.EditMode.ReanchorFrame then
						addon.EditMode.ReanchorFrame(fUF, "CENTER", UIParent, "CENTER", ux, uy)
						if addon.EditMode.SaveOnly then addon.EditMode.SaveOnly() end
						if fUF and fUF.ClearAllPoints and fUF.SetPoint then
							fUF:ClearAllPoints()
							fUF:SetPoint("CENTER", UIParent, "CENTER", ux, uy)
						end
					end
				end)
			end

			-- X Position (px)
			do
				local label = "X Position (px)"
				local options = Settings.CreateSliderOptions(-1000, 1000, 1)
				options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return tostring(roundPositionValue(v)) end)
				local setting = CreateLocalSetting(label, "number",
					function() local x = readOffsets(); return x end,
					function(v) writeOffsets(v, nil) end,
					0)
				local row = Settings.CreateElementInitializer("SettingsSliderControlTemplate", { name = label, setting = setting, options = options })
				row.GetExtent = function() return 34 end
				-- Present as numeric text input (previous behavior), not a slider
				if ConvertSliderInitializerToTextInput then ConvertSliderInitializerToTextInput(row) end
				do
					local base = row.InitFrame
					row.InitFrame = function(self, frame)
						if base then base(self, frame) end
						if panel and panel.ApplyControlTheme then panel.ApplyControlTheme(frame) end
						if panel and panel.ApplyRobotoWhite and frame and frame.Text then panel.ApplyRobotoWhite(frame.Text) end
					end
				end
				table.insert(init, row)
			end

			-- Y Position (px)
			do
				local label = "Y Position (px)"
				local options = Settings.CreateSliderOptions(-1000, 1000, 1)
				options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return tostring(roundPositionValue(v)) end)
				local setting = CreateLocalSetting(label, "number",
					function() local _, y = readOffsets(); return y end,
					function(v) writeOffsets(nil, v) end,
					0)
				local row = Settings.CreateElementInitializer("SettingsSliderControlTemplate", { name = label, setting = setting, options = options })
				row.GetExtent = function() return 34 end
				-- Present as numeric text input (previous behavior), not a slider
				if ConvertSliderInitializerToTextInput then ConvertSliderInitializerToTextInput(row) end
				do
					local base = row.InitFrame
					row.InitFrame = function(self, frame)
						if base then base(self, frame) end
						if panel and panel.ApplyControlTheme then panel.ApplyControlTheme(frame) end
						if panel and panel.ApplyRobotoWhite and frame and frame.Text then panel.ApplyRobotoWhite(frame.Text) end
					end
				end
				table.insert(init, row)
			end

			-- Focus-only: Use Larger Frame
			if componentId == "ufFocus" then
				local label = "Use Larger Frame"
				local function getUF() return getUnitFrame() end
				local function getter()
					local frameUF = getUF()
					local settingId = _G.Enum and _G.Enum.EditModeUnitFrameSetting and _G.Enum.EditModeUnitFrameSetting.UseLargerFrame
					if frameUF and settingId and addon and addon.EditMode and addon.EditMode.GetSetting then
						local v = addon.EditMode.GetSetting(frameUF, settingId)
						return (v and v ~= 0) and true or false
					end
					return false
				end
				local function setter(b)
					local frameUF = getUF()
					local settingId = _G.Enum and _G.Enum.EditModeUnitFrameSetting and _G.Enum.EditModeUnitFrameSetting.UseLargerFrame
					local val = (b and true) and 1 or 0
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
				local setting = CreateLocalSetting(label, "boolean", getter, setter, getter())
				local row = Settings.CreateElementInitializer("SettingsCheckboxControlTemplate", { name = label, setting = setting, options = {} })
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

			-- Frame Size (all four)
			do
				local label = "Frame Size (Scale)"
				local function getUF() return getUnitFrame() end
				local function fmtInt(v) return tostring(math.floor((tonumber(v) or 0) + 0.5)) end
				local options = Settings.CreateSliderOptions(100, 200, 5)
				options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return fmtInt(v) end)
				local function getter()
					local frameUF = getUF()
					local settingId = _G.Enum and _G.Enum.EditModeUnitFrameSetting and _G.Enum.EditModeUnitFrameSetting.FrameSize
					if frameUF and settingId and addon and addon.EditMode and addon.EditMode.GetSetting then
						local v = addon.EditMode.GetSetting(frameUF, settingId)
						if v == nil then return 100 end
						if v <= 20 then return 100 + (v * 5) end
						return math.max(100, math.min(200, v))
					end
					return 100
				end
				local function setter(raw)
					local frameUF = getUF()
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
				local row = Settings.CreateElementInitializer("SettingsSliderControlTemplate", { name = label, setting = setting, options = options })
				row.GetExtent = function() return 34 end
				do
					local base = row.InitFrame
					row.InitFrame = function(self, frame)
						if base then base(self, frame) end
						if panel and panel.ApplyControlTheme then panel.ApplyControlTheme(frame) end
						if panel and panel.ApplyRobotoWhite and frame and frame.Text then panel.ApplyRobotoWhite(frame.Text) end
					end
				end
				table.insert(init, row)
			end

		-- Use Custom Borders (hide stock frame art to allow custom bar-only borders)
		if componentId == "ufPlayer" or componentId == "ufTarget" or componentId == "ufFocus" or componentId == "ufPet" then
			local unitKey
			if componentId == "ufPlayer" then unitKey = "Player"
			elseif componentId == "ufTarget" then unitKey = "Target"
			elseif componentId == "ufFocus" then unitKey = "Focus"
			elseif componentId == "ufPet" then unitKey = "Pet"
			end

			local label = "Use Custom Borders"
			local function ensureUFDB()
				local db = addon and addon.db and addon.db.profile
				if not db then return nil end
				db.unitFrames = db.unitFrames or {}
				db.unitFrames[unitKey] = db.unitFrames[unitKey] or {}
				return db.unitFrames[unitKey]
			end
			local function getter()
				local t = ensureUFDB(); if not t then return false end
				return not not t.useCustomBorders
			end
			local function setter(b)
				local t = ensureUFDB(); if not t then return end
				local wasEnabled = not not t.useCustomBorders
				t.useCustomBorders = not not b
				-- Clear legacy per-health-bar hide flag when disabling custom borders so stock art restores
				if not b then t.healthBarHideBorder = false end
				-- Reset bar height to 100% when disabling Use Custom Borders
				if wasEnabled and not b then
					t.powerBarHeightPct = 100
				end
				if addon and addon.ApplyUnitFrameBarTexturesFor then addon.ApplyUnitFrameBarTexturesFor(unitKey) end
				-- NOTE: Border tab controls and Bar Height sliders are updated in-place by their
				-- own InitFrame/OnSettingValueChanged handlers; no structural re-render here.
			end
			local setting = CreateLocalSetting(label, "boolean", getter, setter, getter())
			local row = Settings.CreateElementInitializer("SettingsCheckboxControlTemplate", { name = label, setting = setting, options = {} })
			row.GetExtent = function() return 34 end
			do
				local base = row.InitFrame
				row.InitFrame = function(self, frame)
					if base then base(self, frame) end
					-- FIRST: Clean up Unit Frame info icons if this frame is being used for a different component
					-- This must happen before any other logic to prevent icon from appearing on recycled frames
					-- Only destroy icons that were created for Unit Frames, allowing other components to have their own icons
					if frame.ScooterInfoIcon and frame.ScooterInfoIcon._isUnitFrameIcon then
						local labelText = frame.Text and frame.Text:GetText() or ""
						local isUnitFrameComponent = (componentId == "ufPlayer" or componentId == "ufTarget" or componentId == "ufFocus" or componentId == "ufPet")
						local isUnitFrameCheckbox = (labelText == "Use Custom Borders")
						if not (isUnitFrameComponent and isUnitFrameCheckbox) then
							-- This is NOT a Unit Frame checkbox - hide and destroy the Unit Frame icon
							-- Other components can have their own icons without interference
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
						local cb = frame.Checkbox or frame.CheckBox or (frame.Control and frame.Control.Checkbox)
						if cb and cb.Text then panel.ApplyRobotoWhite(cb.Text) end
					end
					-- Add info icon next to the label - ONLY for Unit Frame "Use Custom Borders" checkbox
					if frame and frame.Text then
						local labelText = frame.Text:GetText()
						if labelText == "Use Custom Borders" and (componentId == "ufPlayer" or componentId == "ufTarget" or componentId == "ufFocus" or componentId == "ufPet") then
							-- This is the Unit Frame checkbox - create/show the icon
							if panel and panel.CreateInfoIcon then
								if not frame.ScooterInfoIcon then
									local tooltipText = "Enables custom borders by disabling Blizzard's default frame art. Note: This also temporarily disables Aggro Glow and Reputation Colors—we'll restore those features in a future update."
									-- Icon size is 32 (double the original 16) for better visibility
									-- Position icon to the right of the checkbox to ensure no overlap
									local checkbox = frame.Checkbox or frame.CheckBox or (frame.Control and frame.Control.Checkbox)
									if checkbox then
										-- Position icon to the right of the checkbox with spacing
										frame.ScooterInfoIcon = panel.CreateInfoIcon(frame, tooltipText, "LEFT", "RIGHT", 10, 0, 32)
										frame.ScooterInfoIcon:ClearAllPoints()
										frame.ScooterInfoIcon:SetPoint("LEFT", checkbox, "RIGHT", 10, 0)
									else
										-- Fallback: position relative to label if checkbox not found
										frame.ScooterInfoIcon = panel.CreateInfoIcon(frame, tooltipText, "LEFT", "RIGHT", 10, 0, 32)
										if frame.Text then
											frame.ScooterInfoIcon:ClearAllPoints()
											-- Use larger offset to avoid checkbox area (checkbox is ~80px from left, 30px wide)
											frame.ScooterInfoIcon:SetPoint("LEFT", frame.Text, "RIGHT", 40, 0)
										end
									end
									-- Store metadata to identify this as a Unit Frame icon
									frame.ScooterInfoIcon._isUnitFrameIcon = true
									frame.ScooterInfoIcon._componentId = componentId
								else
									-- Icon already exists, ensure it's visible
									frame.ScooterInfoIcon:Show()
								end
							end
						end
					end
				end
			end
			table.insert(init, row)
		end

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
		local isTargetOrFocusHB = (componentId == "ufTarget" or componentId == "ufFocus")
		local hbTabs = { sectionTitle = "" }
		if isTargetOrFocusHB then
			hbTabs.tabAText = "Direction"
			hbTabs.tabBText = "Style"
			hbTabs.tabCText = "Border"
			hbTabs.tabDText = "% Text"
			hbTabs.tabEText = "Value Text"
		else
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
					if type(label) == "string" and string.find(label, "Font") and f.Control and f.Control.Dropdown and addon and addon.InitFontDropdown then
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

				-- PageC: % Text (or PageB if no Direction tab)
				local percentTextPage = isTargetOrFocusHB and frame.PageD or frame.PageC
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
					addSlider(percentTextPage, "% Text Offset X", -100, 100, 1,
						function() local t = ensureUFDB() or {}; local s = t.textHealthPercent or {}; local o = s.offset or {}; return tonumber(o.x) or 0 end,
						function(v) local t = ensureUFDB(); if not t then return end; t.textHealthPercent = t.textHealthPercent or {}; t.textHealthPercent.offset = t.textHealthPercent.offset or {}; t.textHealthPercent.offset.x = tonumber(v) or 0; applyNow() end,
						y)
					addSlider(percentTextPage, "% Text Offset Y", -100, 100, 1,
						function() local t = ensureUFDB() or {}; local s = t.textHealthPercent or {}; local o = s.offset or {}; return tonumber(o.y) or 0 end,
						function(v) local t = ensureUFDB(); if not t then return end; t.textHealthPercent = t.textHealthPercent or {}; t.textHealthPercent.offset = t.textHealthPercent.offset or {}; t.textHealthPercent.offset.y = tonumber(v) or 0; applyNow() end,
						y)
				end

				-- PageD: Value Text (or PageD if no Direction tab)
				local valueTextPage = isTargetOrFocusHB and frame.PageE or frame.PageD
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
							if nv < 1 then nv = 1 elseif nv > 16 then nv = 16 end
							t.healthBarBorderThickness = nv
							applyNow()
						end
						local opts = Settings.CreateSliderOptions(1, 16, 1)
						opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return tostring(math.floor(v)) end)
						local thkSetting = CreateLocalSetting("Border Thickness", "number", getThk, setThk, getThk())
						local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = "Border Thickness", setting = thkSetting, options = opts })
						local sf = CreateFrame("Frame", nil, borderPage, "SettingsSliderControlTemplate")
						sf.GetElementData = function() return initSlider end
						sf:SetPoint("TOPLEFT", 4, y.y)
						sf:SetPoint("TOPRIGHT", -16, y.y)
						initSlider:InitFrame(sf)
						if sf.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(sf.Text) end
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
						local enabled = isEnabled()
						if sf.Control and sf.Control.SetEnabled then sf.Control:SetEnabled(enabled) end
						if sf.Text and sf.Text.SetTextColor then
							if enabled then sf.Text:SetTextColor(1, 1, 1, 1) else sf.Text:SetTextColor(0.6, 0.6, 0.6, 1) end
						end
						y.y = y.y - 34
					end
				end

				-- Apply current visibility once when building
				if addon and addon.ApplyUnitFrameHealthTextVisibilityFor then addon.ApplyUnitFrameHealthTextVisibilityFor(unitKey()) end
			end
			local hbInit = Settings.CreateElementInitializer("ScooterTabbedSectionTemplate", hbTabs)
			-- STATIC HEIGHT for tabbed sections with up to 7-8 settings per tab.
			-- Current: 330px provides comfortable spacing with 2px top gap and room at bottom.
			-- DO NOT reduce below 315px or settings will bleed past the bottom border.
			hbInit.GetExtent = function() return 330 end
			hbInit:AddShownPredicate(function()
				return panel:IsSectionExpanded(componentId, "Health Bar")
			end)
			table.insert(init, hbInit)

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
					if type(label) == "string" and string.find(label, "Font") and f.Control and f.Control.Dropdown and addon and addon.InitFontDropdown then
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
					local function fmtInt(v) return tostring(math.floor((tonumber(v) or 0) + 0.5)) end
					
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
					local heightLabel = "Bar Height (%)"
					local heightOptions = Settings.CreateSliderOptions(50, 200, 1)
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
						val = math.max(50, math.min(200, val))
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
						local tooltipText = "Bar Height customization requires 'Use Custom Borders' to be enabled. This setting allows you to adjust the vertical size of the power bar."
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
								local tooltipText = "Bar Height customization requires 'Use Custom Borders' to be enabled. This setting allows you to adjust the vertical size of the power bar."
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
					addColor(frame.PageF, "% Text Color", true,
						function() local t = ensureUFDB() or {}; local s = t.textPowerPercent or {}; local c = s.color or {1,1,1,1}; return c[1], c[2], c[3], c[4] end,
						function(r,g,b,a) local t = ensureUFDB(); if not t then return end; t.textPowerPercent = t.textPowerPercent or {}; t.textPowerPercent.color = {r,g,b,a}; applyNow() end,
						y)
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
					end
					y.y = y.y - 34
					addDropdown(frame.PageF, "Value Text Font", fontOptions,
						function() local t = ensureUFDB() or {}; local s = t.textPowerValue or {}; return s.fontFace or "FRIZQT__" end,
						function(v) local t = ensureUFDB(); if not t then return end; t.textPowerValue = t.textPowerValue or {}; t.textPowerValue.fontFace = v; applyNow() end,
						y)
					addStyle(frame.PageF, "Value Text Style",
						function() local t = ensureUFDB() or {}; local s = t.textPowerValue or {}; return s.style or "OUTLINE" end,
						function(v) local t = ensureUFDB(); if not t then return end; t.textPowerValue = t.textPowerValue or {}; t.textPowerValue.style = v; applyNow() end,
						y)
					addSlider(frame.PageF, "Value Text Size", 6, 48, 1,
						function() local t = ensureUFDB() or {}; local s = t.textPowerValue or {}; return tonumber(s.size) or 14 end,
						function(v) local t = ensureUFDB(); if not t then return end; t.textPowerValue = t.textPowerValue or {}; t.textPowerValue.size = tonumber(v) or 14; applyNow() end,
						y)
					addColor(frame.PageF, "Value Text Color", true,
						function() local t = ensureUFDB() or {}; local s = t.textPowerValue or {}; local c = s.color or {1,1,1,1}; return c[1], c[2], c[3], c[4] end,
						function(r,g,b,a) local t = ensureUFDB(); if not t then return end; t.textPowerValue = t.textPowerValue or {}; t.textPowerValue.color = {r,g,b,a}; applyNow() end,
						y)
					addSlider(frame.PageF, "Value Text Offset X", -100, 100, 1,
						function() local t = ensureUFDB() or {}; local s = t.textPowerValue or {}; local o = s.offset or {}; return tonumber(o.x) or 0 end,
						function(v) local t = ensureUFDB(); if not t then return end; t.textPowerValue = t.textPowerValue or {}; t.textPowerValue.offset = t.textPowerValue.offset or {}; t.textPowerValue.offset.x = tonumber(v) or 0; applyNow() end,
						y)
					addSlider(frame.PageF, "Value Text Offset Y", -100, 100, 1,
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
                            if nv < 1 then nv = 1 elseif nv > 16 then nv = 16 end
                            t.powerBarBorderThickness = nv
                            applyNow()
                        end
                        local opts = Settings.CreateSliderOptions(1, 16, 1)
                        opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return tostring(math.floor(v)) end)
                        local thkSetting = CreateLocalSetting("Border Thickness", "number", getThk, setThk, getThk())
                        local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = "Border Thickness", setting = thkSetting, options = opts })
                        local sf = CreateFrame("Frame", nil, frame.PageD, "SettingsSliderControlTemplate")
                        sf.GetElementData = function() return initSlider end
                        sf:SetPoint("TOPLEFT", 4, y.y)
                        sf:SetPoint("TOPRIGHT", -16, y.y)
                        initSlider:InitFrame(sf)
                        if sf.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(sf.Text) end
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
			-- STATIC HEIGHT for tabbed sections with up to 7-8 settings per tab.
			-- Current: 330px provides comfortable spacing with 2px top gap and room at bottom.
			-- DO NOT reduce below 315px or settings will bleed past the bottom border.
			pbInit.GetExtent = function() return 330 end
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
						if type(label) == "string" and string.find(label, "Font") and f.Control and f.Control.Dropdown and addon and addon.InitFontDropdown then
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
						addSlider(frame.PageB, "Bar Height (%)", 50, 200, 1,
							function() local t = ensureUFDB() or {}; return tonumber(t.heightPct) or 100 end,
							function(v)
								local t = ensureUFDB(); if not t then return end
								local val = tonumber(v) or 100
								if val < 50 then val = 50 elseif val > 200 then val = 200 end
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
								if nv < 1 then nv = 1 elseif nv > 16 then nv = 16 end
								t.borderThickness = nv
								applyNow()
							end
							local opts = Settings.CreateSliderOptions(1, 16, 1)
							opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return tostring(math.floor(v)) end)
							local thkSetting = CreateLocalSetting("Border Thickness", "number", getThk, setThk, getThk())
							local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = "Border Thickness", setting = thkSetting, options = opts })
							local sf = CreateFrame("Frame", nil, frame.PageD, "SettingsSliderControlTemplate")
							sf.GetElementData = function() return initSlider end
							sf:SetPoint("TOPLEFT", 4, y.y)
							sf:SetPoint("TOPRIGHT", -16, y.y)
							initSlider:InitFrame(sf)
							if sf.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(sf.Text) end
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
				apbInit.GetExtent = function() return 330 end
				apbInit:AddShownPredicate(function()
					return panel:IsSectionExpanded(componentId, "Alternate Power Bar")
				end)
				table.insert(init, apbInit)
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
			if type(label) == "string" and string.find(label, "Font") and f.Control and f.Control.Dropdown and addon and addon.InitFontDropdown then
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
					if nv < 1 then nv = 1 elseif nv > 16 then nv = 16 end
					t.nameBackdropBorderThickness = nv
					applyNow()
				end
				local opts = Settings.CreateSliderOptions(1, 16, 1)
				opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return tostring(math.floor(v)) end)
				local setting = CreateLocalSetting("Border Thickness", "number", get, set, get())
				local sf = CreateFrame("Frame", nil, frame.PageB, "SettingsSliderControlTemplate")
				local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = "Border Thickness", setting = setting, options = opts })
				sf.GetElementData = function() return initSlider end
				sf:SetPoint("TOPLEFT", 4, y.y)
				sf:SetPoint("TOPRIGHT", -16, y.y)
				initSlider:InitFrame(sf)
				if sf.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(sf.Text) end
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
		nltInit.GetExtent = function() return 330 end
		nltInit:AddShownPredicate(function()
			return panel:IsSectionExpanded(componentId, "Name & Level Text")
		end)
		table.insert(init, nltInit)

		-- Fifth collapsible section: Portrait (all unit frames)
		local expInitializerPortrait = Settings.CreateElementInitializer("ScooterExpandableSectionTemplate", {
			name = "Portrait",
			sectionKey = "Portrait",
			componentId = componentId,
			expanded = panel:IsSectionExpanded(componentId, "Portrait"),
		})
		expInitializerPortrait.GetExtent = function() return 30 end
		table.insert(init, expInitializerPortrait)

		-- Portrait tabs: Positioning / Sizing / Mask / Border / Damage Text / Visibility
		-- Damage Text tab only exists for Player frame
		-- Positioning tab disabled for Pet (PetFrame is a managed frame; moving portrait causes entire frame to move)
		local portraitTabs = { sectionTitle = "", tabAText = (componentId ~= "ufPet") and "Positioning" or nil, tabBText = "Sizing", tabCText = "Mask", tabDText = "Border", tabEText = (componentId == "ufPlayer") and "Damage Text" or nil, tabFText = "Visibility" }
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
				if type(label) == "string" and string.find(label, "Font") and f.Control and f.Control.Dropdown and addon and addon.InitFontDropdown then
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
						if nv < 1 then nv = 1 elseif nv > 16 then nv = 16 end
						t.portraitBorderThickness = nv
						applyNow()
					end
					local opts = Settings.CreateSliderOptions(1, 16, 1)
					opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return tostring(math.floor(v)) end)
					local insetSetting = CreateLocalSetting("Border Inset", "number", getInset, setInset, getInset())
					local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = "Border Inset", setting = insetSetting, options = opts })
					local sf = CreateFrame("Frame", nil, frame.PageD, "SettingsSliderControlTemplate")
					sf.GetElementData = function() return initSlider end
					sf:SetPoint("TOPLEFT", 4, y.y)
					sf:SetPoint("TOPRIGHT", -16, y.y)
					initSlider:InitFrame(sf)
					if sf.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(sf.Text) end
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

			-- PageE: Damage Text (Player only)
			do
				-- Only show this tab for Player frame
				if unitKey() ~= "Player" then
					-- Empty page for non-Player frames
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
					
					-- Helper function to check if damage text is disabled
					local function isDisabled()
						local t = ensureUFDB() or {}
						return not not t.damageTextDisabled
					end
					
					-- Store references to controls for gray-out logic
					local _dtFontFrame, _dtStyleFrame, _dtSizeFrame, _dtColorFrame, _dtOffsetXFrame, _dtOffsetYFrame
					
					-- Function to refresh gray-out state
					local function refreshDamageTextDisabledState()
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
					
					-- Disable Damage Text checkbox
					local label = "Disable Damage Text"
					local function getter()
						local t = ensureUFDB(); return t and not not t.damageTextDisabled or false
					end
					local function setter(v)
						local t = ensureUFDB(); if not t then return end
						t.damageTextDisabled = (v and true) or false
						applyNow()
						refreshDamageTextDisabledState()
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
					y.y = y.y - 34
					
					-- Damage Text Font
					_dtFontFrame = addDropdown(frame.PageE, "Font", fontOptions,
						function() local t = ensureUFDB() or {}; local s = t.damageText or {}; return s.fontFace or "FRIZQT__" end,
						function(v) local t = ensureUFDB(); if not t then return end; t.damageText = t.damageText or {}; t.damageText.fontFace = v; applyNow() end,
						y)
					
					-- Damage Text Style
					_dtStyleFrame = addStyle(frame.PageE, "Font Style",
						function() local t = ensureUFDB() or {}; local s = t.damageText or {}; return s.style or "OUTLINE" end,
						function(v) local t = ensureUFDB(); if not t then return end; t.damageText = t.damageText or {}; t.damageText.style = v; applyNow() end,
						y)
					
					-- Damage Text Size
					_dtSizeFrame = addSlider(frame.PageE, "Font Size", 6, 48, 1,
						function() local t = ensureUFDB() or {}; local s = t.damageText or {}; return tonumber(s.size) or 14 end,
						function(v) local t = ensureUFDB(); if not t then return end; t.damageText = t.damageText or {}; t.damageText.size = tonumber(v) or 14; applyNow() end,
						y)
					
					-- Damage Text Color (dropdown + inline swatch)
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
					
					-- Damage Text Offset X
					_dtOffsetXFrame = addSlider(frame.PageE, "Font X Offset", -100, 100, 1,
						function() local t = ensureUFDB() or {}; local s = t.damageText or {}; local o = s.offset or {}; return tonumber(o.x) or 0 end,
						function(v) local t = ensureUFDB(); if not t then return end; t.damageText = t.damageText or {}; t.damageText.offset = t.damageText.offset or {}; t.damageText.offset.x = tonumber(v) or 0; applyNow() end,
						y)
					
					-- Damage Text Offset Y
					_dtOffsetYFrame = addSlider(frame.PageE, "Font Y Offset", -100, 100, 1,
						function() local t = ensureUFDB() or {}; local s = t.damageText or {}; local o = s.offset or {}; return tonumber(o.y) or 0 end,
						function(v) local t = ensureUFDB(); if not t then return end; t.damageText = t.damageText or {}; t.damageText.offset = t.damageText.offset or {}; t.damageText.offset.y = tonumber(v) or 0; applyNow() end,
						y)
					
					-- Initialize gray-out state
					refreshDamageTextDisabledState()
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
				-- Tabs (in order): Positioning, Sizing, Style, Border, Icon, Spell Name Text, Cast Time Text, Spark
				local cbData = {
					sectionTitle = "",
					tabAText = "Positioning",
					tabBText = "Sizing",
					tabCText = "Style",
					tabDText = "Border",
					tabEText = "Icon",
					tabFText = "Spell Name Text",
					tabGText = "Cast Time Text",
					tabHText = "Spark",
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
						-- When the label mentions "Font", initialize the font dropdown wrapper
						if type(label) == "string" and string.find(label, "Font") and f.Control and f.Control.Dropdown and addon and addon.InitFontDropdown then
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
								if nv < 1 then nv = 1 elseif nv > 16 then nv = 16 end
								t.castBarBorderThickness = nv
								applyNow()
							end
							local opts = Settings.CreateSliderOptions(1, 16, 1)
							opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return tostring(math.floor(v)) end)
							local setting = CreateLocalSetting("Border Thickness", "number", getThk, setThk, getThk())
							local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = "Border Thickness", setting = setting, options = opts })
							local sf = CreateFrame("Frame", nil, borderPage, "SettingsSliderControlTemplate")
							sf.GetElementData = function() return initSlider end
							sf:SetPoint("TOPLEFT", 4, y.y)
							sf:SetPoint("TOPRIGHT", -16, y.y)
							initSlider:InitFrame(sf)
							if sf.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(sf.Text) end
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
								if nv < 1 then nv = 1 elseif nv > 16 then nv = 16 end
								t.iconBorderThickness = nv
								applyNow()
							end
							local opts = Settings.CreateSliderOptions(1, 16, 1)
							opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return tostring(math.floor((tonumber(v) or 0) + 0.5)) end)
							local setting = CreateLocalSetting("Icon Border Thickness", "number", getThk, setThk, getThk())
							local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = "Icon Border Thickness", setting = setting, options = opts })
							local f = CreateFrame("Frame", nil, iconPage, "SettingsSliderControlTemplate")
							f.GetElementData = function() return initSlider end
							f:SetPoint("TOPLEFT", 4, y.y)
							f:SetPoint("TOPRIGHT", -16, y.y)
							initSlider:InitFrame(f)
							if f.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(f.Text) end
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

					-- Shared Spark tab (PageH): Hide Spark + Spark Color (Player/Target/Focus)
					-- NOTE: Defined outside the Player-only branch so it is available for Target/Focus
					-- as well. This prevents nil-function errors when we call buildSparkTab() for all
					-- Unit Frames with a Cast Bar.
					local function buildSparkTab()
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

						local function isSparkEnabled()
							local t = ensureCastBarDB() or {}
							-- When the user checks "Hide Cast Bar Spark", we treat spark as disabled.
							return not not (not t.castBarSparkHidden)
						end

						local sparkPage = frame.PageH
						if not sparkPage then
							-- Defensive guard: if the template ever omits PageH, fail safely.
							return
						end

						local y = { y = -50 }

						-- Local reference so we can gray-out the color row without rebuilding the category
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

						-- Hide Cast Bar Spark checkbox
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
							local row = CreateFrame("Frame", nil, sparkPage, "SettingsCheckboxControlTemplate")
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

						-- Cast Bar Spark Color (dropdown + inline swatch)
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
							_sparkColorFrame = panel.DropdownWithInlineSwatch(sparkPage, y, {
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
					end

					-- Spell Name Text tab (PageF): Disable Spell Name Text + styling (Player only)
					do
						-- Only meaningful for the Player cast bar; leave PageF empty for Target/Focus
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
							-- PageA: Positioning (X/Y offsets)
							do
								local y = { y = -50 }
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

							-- PageB: Sizing (Bar Width %)
							do
								local y = { y = -50 }
								local function fmtInt(v) return tostring(math.floor((tonumber(v) or 0) + 0.5)) end
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
							end
						end
					end

					-- Build Style, Border, Icon, and Spark tabs for any unit with a Cast Bar (Player/Target/Focus)
					buildStyleTab()
					buildBorderTab()
					buildIconTab()
					buildSparkTab()
				end

				local tabCBC = Settings.CreateElementInitializer("ScooterTabbedSectionTemplate", cbData)
				-- STATIC HEIGHT: Cast Bar tabs now have multiple controls (Style, Icon, text, etc.).
				-- Bump slightly above 330px to accommodate one additional row (Disable Icon) while
				-- keeping spacing consistent with other Unit Frame tabbed sections.
				tabCBC.GetExtent = function() return 364 end
				tabCBC:AddShownPredicate(function() return panel:IsSectionExpanded(componentId, "Cast Bar") end)
				table.insert(init, tabCBC)
			end

			-- Fifth collapsible section: Buffs & Debuffs (Target only)
			if componentId == "ufTarget" then
				local expInitializerBD = Settings.CreateElementInitializer("ScooterExpandableSectionTemplate", {
					name = "Buffs & Debuffs",
					sectionKey = "Buffs & Debuffs",
					componentId = componentId,
					expanded = panel:IsSectionExpanded(componentId, "Buffs & Debuffs"),
				})
				expInitializerBD.GetExtent = function() return 30 end
				table.insert(init, expInitializerBD)

				-- Tabbed section within Buffs & Debuffs:
				-- Tabs (in order): Positioning, Sizing, Border, Text, Visibility
				local bdData = {
					sectionTitle = "",
					tabAText = "Positioning",
					tabBText = "Sizing",
					tabCText = "Border",
					tabDText = "Text",
					tabEText = "Visibility",
				}
				bdData.build = function(frame)
					-- Helper: map componentId -> unit key (Target only for this block)
					local function unitKey()
						return "Target"
					end

					-- Helper: ensure Unit Frame Buffs & Debuffs DB namespace
					local function ensureUFDB()
						local db = addon and addon.db and addon.db.profile
						if not db then return nil end
						db.unitFrames = db.unitFrames or {}
						local uk = unitKey()
						db.unitFrames[uk] = db.unitFrames[uk] or {}
						db.unitFrames[uk].buffsDebuffs = db.unitFrames[uk].buffsDebuffs or {}
						return db.unitFrames[uk].buffsDebuffs
					end

					-- Small slider helper (integer labels)
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
						return f
					end

					local function applyBuffsNow()
						local uk = unitKey()
						if addon and addon.ApplyUnitFrameBuffsDebuffsFor then
							addon.ApplyUnitFrameBuffsDebuffsFor(uk)
						end
						if addon and addon.ApplyStyles then
							addon:ApplyStyles()
						end
					end

					-- PageA: Positioning tab (Buffs on Top only; no addon-side X/Y offsets)
					do
						local y = { y = -50 }

						-- "Buffs on Top" checkbox wired to Edit Mode
						local function getUnitFrame()
							local mgr = _G.EditModeManagerFrame
							local EM = _G.Enum and _G.Enum.EditModeUnitFrameSystemIndices
							local EMSys = _G.Enum and _G.Enum.EditModeSystem
							if not (mgr and EM and EMSys and mgr.GetRegisteredSystemFrame) then return nil end
							local idx = EM.Target
							return mgr:GetRegisteredSystemFrame(EMSys.UnitFrame, idx)
						end
						local label = "Buffs on Top"
						local function getter()
							local frameUF = getUnitFrame()
							local sid = _G.Enum and _G.Enum.EditModeUnitFrameSetting and _G.Enum.EditModeUnitFrameSetting.BuffsOnTop
							if frameUF and sid and addon and addon.EditMode and addon.EditMode.GetSetting then
								local v = addon.EditMode.GetSetting(frameUF, sid)
								return (tonumber(v) or 0) == 1
							end
							return false
						end
						local function setter(b)
							local frameUF = getUnitFrame()
							local sid = _G.Enum and _G.Enum.EditModeUnitFrameSetting and _G.Enum.EditModeUnitFrameSetting.BuffsOnTop
							local val = (b and true) and 1 or 0
							if frameUF and sid and addon and addon.EditMode then
								if addon.EditMode.WriteSetting then
									addon.EditMode.WriteSetting(frameUF, sid, val, {
										updaters        = { "UpdateSystemSettingBuffsOnTop" },
										suspendDuration = 0.25,
									})
								elseif addon.EditMode.SetSetting then
									addon.EditMode.SetSetting(frameUF, sid, val)
									-- Nudge visuals; call specific updater if present, else coalesced apply
									if type(frameUF.UpdateSystemSettingBuffsOnTop) == "function" then pcall(frameUF.UpdateSystemSettingBuffsOnTop, frameUF) end
									if addon.EditMode.SaveOnly then addon.EditMode.SaveOnly() end
									if addon.EditMode.RequestApplyChanges then addon.EditMode.RequestApplyChanges(0.2) end
								end
							end
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

					-- PageB: Sizing tab (Scale + Icon Width/Height)
					do
						local y = { y = -50 }

						-- Icon Scale slider (50–150%). Applies a uniform scale to all aura frames
						-- after Blizzard has laid them out, so we can shrink/grow icons without
						-- fighting the internal row/column layout math.
						addSlider(frame.PageB, "Icon Scale (%)", 50, 150, 1,
							function()
								local t = ensureUFDB() or {}
								return tonumber(t.iconScale) or 100
							end,
							function(v)
								local t = ensureUFDB(); if not t then return end
								local val = tonumber(v) or 100
								if val < 50 then val = 50 elseif val > 150 then val = 150 end
								t.iconScale = val
								applyBuffsNow()
							end,
							y)

						-- Icon Width slider (24..48 px). Defaults are seeded from Blizzard's
						-- stock aura size on first apply; the 44 fallback here is only used
						-- if we have no prior DB value yet.
						addSlider(frame.PageB, "Icon Width", 24, 48, 1,
							function()
								local t = ensureUFDB() or {}
								return tonumber(t.iconWidth) or 44
							end,
							function(v)
								local t = ensureUFDB(); if not t then return end
								local val = tonumber(v) or 44
								if val < 24 then val = 24 elseif val > 48 then val = 48 end
								t.iconWidth = val
								applyBuffsNow()
							end,
							y)

						-- Icon Height slider (24..48 px). Defaults are seeded from Blizzard's
						-- stock aura size on first apply; the 44 fallback here is only used
						-- if we have no prior DB value yet.
						addSlider(frame.PageB, "Icon Height", 24, 48, 1,
							function()
								local t = ensureUFDB() or {}
								return tonumber(t.iconHeight) or 44
							end,
							function(v)
								local t = ensureUFDB(); if not t then return end
								local val = tonumber(v) or 44
								if val < 24 then val = 24 elseif val > 48 then val = 48 end
								t.iconHeight = val
								applyBuffsNow()
							end,
							y)
					end

					-- PageC: Border tab (Use Custom Border + Style/Tint/Thickness, matching Essential Cooldowns)
					do
						local y = { y = -50 }

						local function applyNow()
							local uk = unitKey()
							if addon and addon.ApplyUnitFrameBuffsDebuffsFor then
								addon.ApplyUnitFrameBuffsDebuffsFor(uk)
							end
							if addon and addon.ApplyStyles then
								addon:ApplyStyles()
							end
						end

						local function isEnabled()
							local t = ensureUFDB() or {}
							return not not t.borderEnable
						end

						local _styleFrame, _tintRow, _thkFrame
						local function refreshBorderEnabledState()
							local enabled = isEnabled()

							-- Style dropdown
							if _styleFrame then
								if _styleFrame.Control and _styleFrame.Control.SetEnabled then
									_styleFrame.Control:SetEnabled(enabled)
								end
								local lbl = _styleFrame.Text or _styleFrame.Label
								if lbl and lbl.SetTextColor then
									lbl:SetTextColor(enabled and 1 or 0.6, enabled and 1 or 0.6, enabled and 1 or 0.6, 1)
								end
							end

							-- Tint checkbox + swatch
							if _tintRow then
								local ctrl = _tintRow.Checkbox or _tintRow.CheckBox or (_tintRow.Control and _tintRow.Control.Checkbox) or _tintRow.Control
								if ctrl and ctrl.SetEnabled then ctrl:SetEnabled(enabled) end
								if _tintRow.ScooterInlineSwatch and _tintRow.ScooterInlineSwatch.EnableMouse then
									_tintRow.ScooterInlineSwatch:EnableMouse(enabled)
									if _tintRow.ScooterInlineSwatch.SetAlpha then
										_tintRow.ScooterInlineSwatch:SetAlpha(enabled and 1 or 0.5)
									end
								end
								local labelFS = (ctrl and ctrl.Text) or _tintRow.Text
								if labelFS and labelFS.SetTextColor then
									labelFS:SetTextColor(enabled and 1 or 0.6, enabled and 1 or 0.6, enabled and 1 or 0.6, 1)
								end
							end

							-- Thickness slider
							if _thkFrame then
								if _thkFrame.Control and _thkFrame.Control.SetEnabled then
									_thkFrame.Control:SetEnabled(enabled)
								end
								local lbl = _thkFrame.Text or _thkFrame.Label
								if lbl and lbl.SetTextColor then
									lbl:SetTextColor(enabled and 1 or 0.6, enabled and 1 or 0.6, enabled and 1 or 0.6, 1)
								end
							end
						end

						-- Use Custom Border checkbox
						do
							local setting = CreateLocalSetting("Use Custom Border", "boolean",
								function()
									local t = ensureUFDB() or {}
									return t.borderEnable == true
								end,
								function(v)
									local t = ensureUFDB(); if not t then return end
									t.borderEnable = (v == true)
									applyNow()
									refreshBorderEnabledState()
								end,
								false)
							local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = "Use Custom Border", setting = setting, options = {} })
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

						-- Border Style dropdown (shares options with Essential Cooldowns / IconBorders)
						do
							local function styleOptions()
								if addon.BuildIconBorderOptionsContainer then
									return addon.BuildIconBorderOptionsContainer()
								end
								local c = Settings.CreateControlTextContainer()
								c:Add("square", "Default")
								c:Add("blizzard", "Blizzard Default")
								return c:GetData()
							end
							local function getStyle()
								local t = ensureUFDB() or {}
								return t.borderStyle or "square"
							end
							local function setStyle(v)
								local t = ensureUFDB(); if not t then return end
								t.borderStyle = v or "square"
								applyNow()
							end
							local styleSetting = CreateLocalSetting("Border Style", "string", getStyle, setStyle, getStyle())
							local initDrop = Settings.CreateSettingInitializer("SettingsDropdownControlTemplate", { name = "Border Style", setting = styleSetting, options = styleOptions })
							local f = CreateFrame("Frame", nil, frame.PageC, "SettingsDropdownControlTemplate")
							_styleFrame = f
							f.GetElementData = function() return initDrop end
							f:SetPoint("TOPLEFT", 4, y.y)
							f:SetPoint("TOPRIGHT", -16, y.y)
							initDrop:InitFrame(f)
							local lbl = f and (f.Text or f.Label)
							if lbl and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(lbl) end
							y.y = y.y - 34
						end

						-- Border Tint (checkbox + swatch)
						do
							local function getTintEnabled()
								local t = ensureUFDB() or {}
								return not not t.borderTintEnable
							end
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
							local function setTint(r, g, b, a)
								local t = ensureUFDB(); if not t then return end
								t.borderTintColor = { r or 1, g or 1, b or 1, a or 1 }
								applyNow()
							end
							local tintSetting = CreateLocalSetting("Border Tint", "boolean", getTintEnabled, setTintEnabled, getTintEnabled())
							local initCb = CreateCheckboxWithSwatchInitializer(tintSetting, "Border Tint", getTint, setTint, 8)
							local row = CreateFrame("Frame", nil, frame.PageC, "SettingsCheckboxControlTemplate")
							_tintRow = row
							row.GetElementData = function() return initCb end
							row:SetPoint("TOPLEFT", 4, y.y)
							row:SetPoint("TOPRIGHT", -16, y.y)
							initCb:InitFrame(row)
							y.y = y.y - 34
						end

						-- Border Thickness slider
						do
							local function getThk()
								local t = ensureUFDB() or {}
								return tonumber(t.borderThickness) or 1
							end
							local function setThk(v)
								local t = ensureUFDB(); if not t then return end
								local nv = tonumber(v) or 1
								if nv < 1 then nv = 1 elseif nv > 16 then nv = 16 end
								t.borderThickness = nv
								applyNow()
							end
							local opts = Settings.CreateSliderOptions(1, 16, 1)
							opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return tostring(math.floor(v)) end)
							local thkSetting = CreateLocalSetting("Border Thickness", "number", getThk, setThk, getThk())
							local sf = CreateFrame("Frame", nil, frame.PageC, "SettingsSliderControlTemplate")
							_thkFrame = sf
							local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = "Border Thickness", setting = thkSetting, options = opts })
							sf.GetElementData = function() return initSlider end
							sf:SetPoint("TOPLEFT", 4, y.y)
							sf:SetPoint("TOPRIGHT", -16, y.y)
							initSlider:InitFrame(sf)
							if sf.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(sf.Text) end
							y.y = y.y - 34
						end

						-- Initial gray-out state
						refreshBorderEnabledState()
					end

					-- Tabs D/E (Text, Visibility) are present for layout consistency and will be
					-- populated in a later phase. For now they intentionally remain empty.
				end

				local tabBD = Settings.CreateElementInitializer("ScooterTabbedSectionTemplate", bdData)
				-- STATIC HEIGHT: Buffs & Debuffs tabs now host multiple controls per tab (Scale, Width/Height,
				-- Border options, and upcoming Text settings). Match the standard Unit Frame tabbed height (330px)
				-- used by Health/Power/Portrait text sections to accommodate up to ~7 controls per tab.
				tabBD.GetExtent = function() return 330 end
				tabBD:AddShownPredicate(function() return panel:IsSectionExpanded(componentId, "Buffs & Debuffs") end)
				table.insert(init, tabBD)
			end

			-- Sixth collapsible section: Buffs & Debuffs (Focus only)
			if componentId == "ufFocus" then
				local expInitializerBDF = Settings.CreateElementInitializer("ScooterExpandableSectionTemplate", {
					name = "Buffs & Debuffs",
					sectionKey = "Buffs & Debuffs",
					componentId = componentId,
					expanded = panel:IsSectionExpanded(componentId, "Buffs & Debuffs"),
				})
				expInitializerBDF.GetExtent = function() return 30 end
				table.insert(init, expInitializerBDF)

				-- Tabbed section within Buffs & Debuffs:
				-- Tabs (in order): Positioning, Sizing, Border, Text, Visibility
				local bdDataF = {
					sectionTitle = "",
					tabAText = "Positioning",
					tabBText = "Sizing",
					tabCText = "Border",
					tabDText = "Text",
					tabEText = "Visibility",
				}
				bdDataF.build = function(frame)
					-- Helper: map componentId -> unit key (Focus only for this block)
					local function unitKey()
						return "Focus"
					end

					-- Helper: ensure Unit Frame Buffs & Debuffs DB namespace
					local function ensureUFDB()
						local db = addon and addon.db and addon.db.profile
						if not db then return nil end
						db.unitFrames = db.unitFrames or {}
						local uk = unitKey()
						db.unitFrames[uk] = db.unitFrames[uk] or {}
						db.unitFrames[uk].buffsDebuffs = db.unitFrames[uk].buffsDebuffs or {}
						return db.unitFrames[uk].buffsDebuffs
					end

					-- Small slider helper (integer labels)
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
						return f
					end

					local function applyBuffsNow()
						local uk = unitKey()
						if addon and addon.ApplyUnitFrameBuffsDebuffsFor then
							addon.ApplyUnitFrameBuffsDebuffsFor(uk)
						end
						if addon and addon.ApplyStyles then
							addon:ApplyStyles()
						end
					end

					-- PageA: Positioning tab (Buffs on Top + X/Y offsets)
					do
						local y = { y = -50 }

						local function getUnitFrame()
							local mgr = _G.EditModeManagerFrame
							local EM = _G.Enum and _G.Enum.EditModeUnitFrameSystemIndices
							local EMSys = _G.Enum and _G.Enum.EditModeSystem
							if not (mgr and EM and EMSys and mgr.GetRegisteredSystemFrame) then return nil end
							local idx = EM.Focus
							return mgr:GetRegisteredSystemFrame(EMSys.UnitFrame, idx)
						end
						local function isUseLargerEnabled()
							local fUF = getUnitFrame()
							local sidULF = _G.Enum and _G.Enum.EditModeUnitFrameSetting and _G.Enum.EditModeUnitFrameSetting.UseLargerFrame
							if fUF and sidULF and addon and addon.EditMode and addon.EditMode.GetSetting then
								local v = addon.EditMode.GetSetting(fUF, sidULF)
								return (v and v ~= 0) and true or false
							end
							return false
						end
						local label = "Buffs on Top"
						local function getter()
							local frameUF = getUnitFrame()
							local sid = _G.Enum and _G.Enum.EditModeUnitFrameSetting and _G.Enum.EditModeUnitFrameSetting.BuffsOnTop
							if frameUF and sid and addon and addon.EditMode and addon.EditMode.GetSetting then
								local v = addon.EditMode.GetSetting(frameUF, sid)
								return (tonumber(v) or 0) == 1
							end
							return false
						end
						local function setter(b)
							-- Respect gating: if Use Larger Frame is not enabled, ignore writes
							if not isUseLargerEnabled() then return end
							local frameUF = getUnitFrame()
							local sid = _G.Enum and _G.Enum.EditModeUnitFrameSetting and _G.Enum.EditModeUnitFrameSetting.BuffsOnTop
							local val = (b and true) and 1 or 0
							if frameUF and sid and addon and addon.EditMode then
								if addon.EditMode.WriteSetting then
									addon.EditMode.WriteSetting(frameUF, sid, val, {
										updaters        = { "UpdateSystemSettingBuffsOnTop" },
										suspendDuration = 0.25,
									})
								elseif addon.EditMode.SetSetting then
									addon.EditMode.SetSetting(frameUF, sid, val)
									if type(frameUF.UpdateSystemSettingBuffsOnTop) == "function" then pcall(frameUF.UpdateSystemSettingBuffsOnTop, frameUF) end
									if addon.EditMode.SaveOnly then addon.EditMode.SaveOnly() end
									if addon.EditMode.RequestApplyChanges then addon.EditMode.RequestApplyChanges(0.2) end
								end
							end
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
						-- Gray out when Use Larger Frame is unchecked and show disclaimer
						local cb = row.Checkbox or row.CheckBox or (row.Control and row.Control.Checkbox)
						local disabled = not isUseLargerEnabled()
						if cb then if disabled then cb:Disable() else cb:Enable() end end
						local disclaimer = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
						disclaimer:SetText("Parent Frame > Sizing > 'Use Larger Frame' required")
						disclaimer:SetJustifyH("LEFT")
						if disclaimer.SetWordWrap then disclaimer:SetWordWrap(true) end
						if disclaimer.SetNonSpaceWrap then disclaimer:SetNonSpaceWrap(true) end
						local anchor = (cb and cb.Text) or row.Text or row
						disclaimer:ClearAllPoints()
						disclaimer:SetPoint("LEFT", anchor, "RIGHT", 42, 0)
						disclaimer:SetPoint("RIGHT", row, "RIGHT", -12, 0)
						disclaimer:SetShown(disabled)

						-- Expose a lightweight gating refresher to avoid full category rebuilds
						panel.RefreshFocusBuffsOnTopGating = function()
							local isDisabled = not isUseLargerEnabled()
							if cb then if isDisabled then cb:Disable() else cb:Enable() end end
							if disclaimer then disclaimer:SetShown(isDisabled) end
						end
						if panel.RefreshFocusBuffsOnTopGating then panel.RefreshFocusBuffsOnTopGating() end
						y.y = y.y - 34

						-- X Offset slider (-150..150 px)
						addSlider(frame.PageA, "X Offset", -150, 150, 1,
							function()
								local t = ensureUFDB() or {}
								return tonumber(t.offsetX) or 0
							end,
							function(v)
								local t = ensureUFDB(); if not t then return end
								t.offsetX = tonumber(v) or 0
								applyBuffsNow()
							end,
							y)

						-- Y Offset slider (-150..150 px)
						addSlider(frame.PageA, "Y Offset", -150, 150, 1,
							function()
								local t = ensureUFDB() or {}
								return tonumber(t.offsetY) or 0
							end,
							function(v)
								local t = ensureUFDB(); if not t then return end
								t.offsetY = tonumber(v) or 0
								applyBuffsNow()
							end,
							y)
					end

					-- PageB: Sizing tab (Scale + Icon Width/Height)
					do
						local y = { y = -50 }

						-- Icon Scale slider (50–150%). Applies a uniform scale to all aura frames
						-- after Blizzard has laid them out, so we can shrink/grow icons without
						-- fighting the internal row/column layout math.
						addSlider(frame.PageB, "Icon Scale (%)", 50, 150, 1,
							function()
								local t = ensureUFDB() or {}
								return tonumber(t.iconScale) or 100
							end,
							function(v)
								local t = ensureUFDB(); if not t then return end
								local val = tonumber(v) or 100
								if val < 50 then val = 50 elseif val > 150 then val = 150 end
								t.iconScale = val
								applyBuffsNow()
							end,
							y)

						-- Icon Width slider (24..48 px). Defaults are seeded from Blizzard's
						-- stock aura size on first apply; the 44 fallback here is only used
						-- if we have no prior DB value yet.
						addSlider(frame.PageB, "Icon Width", 24, 48, 1,
							function()
								local t = ensureUFDB() or {}
								return tonumber(t.iconWidth) or 44
							end,
							function(v)
								local t = ensureUFDB(); if not t then return end
								local val = tonumber(v) or 44
								if val < 24 then val = 24 elseif val > 48 then val = 48 end
								t.iconWidth = val
								applyBuffsNow()
							end,
							y)

						-- Icon Height slider (24..48 px). Defaults are seeded from Blizzard's
						-- stock aura size on first apply; the 44 fallback here is only used
						-- if we have no prior DB value yet.
						addSlider(frame.PageB, "Icon Height", 24, 48, 1,
							function()
								local t = ensureUFDB() or {}
								return tonumber(t.iconHeight) or 44
							end,
							function(v)
								local t = ensureUFDB(); if not t then return end
								local val = tonumber(v) or 44
								if val < 24 then val = 24 elseif val > 48 then val = 48 end
								t.iconHeight = val
								applyBuffsNow()
							end,
							y)
					end

					-- Tabs C/D/E (Border, Text, Visibility) are present for layout consistency and will be
					-- populated in a later phase. For now they intentionally remain empty.
				end

				local tabBDF = Settings.CreateElementInitializer("ScooterTabbedSectionTemplate", bdDataF)
				-- STATIC HEIGHT: align Focus Buffs & Debuffs tab height with Target/Health/Power/Portrait (330px)
				-- so the layout can comfortably display up to ~7 controls per tab without clipping.
				tabBDF.GetExtent = function() return 330 end
				tabBDF:AddShownPredicate(function() return panel:IsSectionExpanded(componentId, "Buffs & Debuffs") end)
				table.insert(init, tabBDF)
			end

			-- Final collapsible section: Visibility (overall opacity for this Unit Frame)
			-- Only meaningful for Player and Pet; Target/Focus visibility is owned by Cooldown Manager layouts.
			if componentId == "ufPlayer" or componentId == "ufPet" then
				local unitKey = (componentId == "ufPlayer") and "Player" or "Pet"

				local function ensureUFDB()
					local db = addon and addon.db and addon.db.profile
					if not db then return nil end
					db.unitFrames = db.unitFrames or {}
					db.unitFrames[unitKey] = db.unitFrames[unitKey] or {}
					return db.unitFrames[unitKey]
				end

				-- Collapsible header for Visibility
				local expInitializerVis = Settings.CreateElementInitializer("ScooterExpandableSectionTemplate", {
					name = "Visibility",
					sectionKey = "Visibility",
					componentId = componentId,
					expanded = panel:IsSectionExpanded(componentId, "Visibility"),
				})
				expInitializerVis.GetExtent = function() return 30 end
				table.insert(init, expInitializerVis)

				local function fmtInt(v) return tostring(math.floor((tonumber(v) or 0) + 0.5)) end
				local function addOpacitySlider(label, key, minV, maxV, defaultV, addPriorityTooltip)
					local options = Settings.CreateSliderOptions(minV, maxV, 1)
					options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return fmtInt(v) end)
					local setting = CreateLocalSetting(label, "number",
						function()
							local t = ensureUFDB() or {}
							local v = t[key]
							if v == nil then return defaultV end
							return tonumber(v) or defaultV
						end,
						function(v)
							local t = ensureUFDB(); if not t then return end
							t[key] = tonumber(v) or defaultV
							if addon and addon.ApplyUnitFrameVisibilityFor and unitKey then
								addon.ApplyUnitFrameVisibilityFor(unitKey)
							end
						end,
						defaultV
					)
					local row = Settings.CreateElementInitializer("SettingsSliderControlTemplate", { name = label, setting = setting, options = options })
					row.GetExtent = function() return 34 end
					row:AddShownPredicate(function()
						return panel:IsSectionExpanded(componentId, "Visibility")
					end)
					do
						local base = row.InitFrame
						row.InitFrame = function(self, frame)
							if base then base(self, frame) end
							if panel and panel.ApplyControlTheme then panel.ApplyControlTheme(frame) end
							if panel and panel.ApplyRobotoWhite and frame and frame.Text then panel.ApplyRobotoWhite(frame.Text) end
							-- Optional: add the same opacity-priority tooltip used by Cooldown Manager
							if addPriorityTooltip and panel and not frame.ScooterOpacityInfoIcon then
								local tooltipText = "Opacity priority: With Target takes precedence, then In Combat, then Out of Combat. The highest priority condition that applies determines the opacity."
								local labelWidget = frame.Text or frame.Label
								if labelWidget and panel.CreateInfoIconForLabel then
									-- Create icon using the helper, then defer repositioning based on actual text width
									frame.ScooterOpacityInfoIcon = panel.CreateInfoIconForLabel(labelWidget, tooltipText, 5, 0, 32)
									if frame.ScooterOpacityInfoIcon then
										frame.ScooterOpacityInfoIcon:Hide()
									end
									if C_Timer and C_Timer.After then
										C_Timer.After(0, function()
											if frame.ScooterOpacityInfoIcon and labelWidget then
												frame.ScooterOpacityInfoIcon:ClearAllPoints()
												local textWidth = labelWidget:GetStringWidth() or 0
												if textWidth > 0 then
													-- Position immediately after the label text
													frame.ScooterOpacityInfoIcon:SetPoint("LEFT", labelWidget, "LEFT", textWidth + 5, 0)
												else
													-- Fallback: anchor to the label's right edge
													frame.ScooterOpacityInfoIcon:SetPoint("LEFT", labelWidget, "RIGHT", 5, 0)
												end
												frame.ScooterOpacityInfoIcon:Show()
											end
										end)
									else
										frame.ScooterOpacityInfoIcon:ClearAllPoints()
										local textWidth = labelWidget:GetStringWidth() or 0
										if textWidth > 0 then
											frame.ScooterOpacityInfoIcon:SetPoint("LEFT", labelWidget, "LEFT", textWidth + 5, 0)
										else
											frame.ScooterOpacityInfoIcon:SetPoint("LEFT", labelWidget, "RIGHT", 5, 0)
										end
										frame.ScooterOpacityInfoIcon:Show()
									end
								elseif panel.CreateInfoIcon then
									-- Fallback: anchor to the whole frame if we don't have a label
									frame.ScooterOpacityInfoIcon = panel.CreateInfoIcon(frame, tooltipText, "LEFT", "LEFT", 10, 0, 32)
								end
							end
						end
					end
					table.insert(init, row)
				end

				-- Match Cooldown Manager semantics:
				-- - Base opacity 50–100 (in combat)
				-- - With-target and out-of-combat use 1–100 internally; slider shows 0–100 where 0/1 both behave as "fully hidden"
				-- Add the priority tooltip to the base Opacity in Combat slider so behavior is clearly documented.
				addOpacitySlider("Opacity in Combat", "opacity", 50, 100, 100, true)
				addOpacitySlider("Opacity With Target", "opacityWithTarget", 1, 100, 100, false)
				-- Allow the slider to reach 0 so it's clear that 0/1 both mean "invisible" in practice.
				addOpacitySlider("Opacity Out of Combat", "opacityOutOfCombat", 0, 100, 100, false)
			end

            if right.SetTitle then
                right:SetTitle(title or componentId)
            end
            right:Display(init)
        end
        return { mode = "list", render = render, componentId = componentId }
end

function panel.RenderUFPlayer() return createUFRenderer("ufPlayer", "Player") end
function panel.RenderUFTarget() return createUFRenderer("ufTarget", "Target") end
function panel.RenderUFFocus()  return createUFRenderer("ufFocus",  "Focus")  end
function panel.RenderUFPet()    return createUFRenderer("ufPet",    "Pet")    end