local addonName, addon = ...

addon.SettingsPanel = addon.SettingsPanel or {}
local panel = addon.SettingsPanel
panel.UnitFramesSections = panel.UnitFramesSections or {}

local function build(ctx, init)
	local componentId = ctx.componentId
	local title = ctx.title
	local panel = ctx.panel or panel
	local addon = ctx.addon or addon

	-- Skip for ToT - it has its own section builder (tot_root)
	if componentId == "ufToT" then return end

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
					local row = Settings.CreateElementInitializer("SettingsSliderControlTemplate", { name = label, setting = setting, options = options, componentId = componentId })
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
					local row = Settings.CreateElementInitializer("SettingsSliderControlTemplate", { name = label, setting = setting, options = options, componentId = componentId })
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
	
				-- Frame Size (all four) - Edit Mode controlled
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
						-- Invalidate scale multiplier baselines when Edit Mode scale changes
						if addon.InvalidateUnitFrameScaleMultBaselines then
							addon.InvalidateUnitFrameScaleMultBaselines()
						end
						-- Reapply scale multiplier after Edit Mode scale change
						local unitKey = (componentId == "ufPlayer" and "Player")
							or (componentId == "ufTarget" and "Target")
							or (componentId == "ufFocus" and "Focus")
							or (componentId == "ufPet" and "Pet")
						if unitKey and addon.ApplyUnitFrameScaleMultFor then
							C_Timer.After(0.3, function()
								addon.ApplyUnitFrameScaleMultFor(unitKey)
							end)
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
							-- Add info icon to the left of the label
							if frame and frame.Text and panel and panel.CreateInfoIcon and not frame.ScooterFrameSizeInfoIcon then
								local tooltipText = "This is Blizzard's Edit Mode scale setting (max 200%). If you need larger frames for handheld or accessibility use, the Scale Multiplier below can increase size beyond this limit."
								frame.ScooterFrameSizeInfoIcon = panel.CreateInfoIcon(frame, tooltipText, "RIGHT", "LEFT", -5, 0, 20)
								-- Position to the left of the label text
								C_Timer.After(0, function()
									if frame.ScooterFrameSizeInfoIcon and frame.Text then
										frame.ScooterFrameSizeInfoIcon:ClearAllPoints()
										frame.ScooterFrameSizeInfoIcon:SetPoint("RIGHT", frame.Text, "LEFT", -5, 0)
									end
								end)
							end
						end
					end
					table.insert(init, row)
				end
	
				-- Scale Multiplier (addon-only, layers on top of Edit Mode scale)
				do
					local label = "Scale Multiplier"
					local unitKey = (componentId == "ufPlayer" and "Player")
						or (componentId == "ufTarget" and "Target")
						or (componentId == "ufFocus" and "Focus")
						or (componentId == "ufPet" and "Pet")
					local function ensureUFDB()
						local db = addon and addon.db and addon.db.profile
						if not db then return nil end
						db.unitFrames = db.unitFrames or {}
						db.unitFrames[unitKey] = db.unitFrames[unitKey] or {}
						return db.unitFrames[unitKey]
					end
					local function fmtMult(v)
						local val = tonumber(v) or 1.0
						return string.format("%.1fx", val)
					end
					local options = Settings.CreateSliderOptions(1.0, 2.0, 0.1)
					options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, fmtMult)
					local function getter()
						local t = ensureUFDB()
						if not t then return 1.0 end
						return tonumber(t.scaleMult) or 1.0
					end
					local function setter(v)
						local t = ensureUFDB()
						if not t then return end
						local val = tonumber(v) or 1.0
						if val < 1.0 then val = 1.0 end
						if val > 2.0 then val = 2.0 end
						t.scaleMult = val
						-- Apply scale multiplier immediately
						if addon.ApplyUnitFrameScaleMultFor then
							addon.ApplyUnitFrameScaleMultFor(unitKey)
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
							-- Add info icon to the left of the label
							if frame and frame.Text and panel and panel.CreateInfoIcon and not frame.ScooterScaleMultInfoIcon then
								local tooltipText = "This addon-only multiplier layers on top of Edit Mode's scale. A 1.5x multiplier combined with Edit Mode's 200% produces an effective 300% scale. Use this for ScooterDeck or other large-UI needs."
								frame.ScooterScaleMultInfoIcon = panel.CreateInfoIcon(frame, tooltipText, "RIGHT", "LEFT", -5, 0, 20)
								-- Position to the left of the label text
								C_Timer.After(0, function()
									if frame.ScooterScaleMultInfoIcon and frame.Text then
										frame.ScooterScaleMultInfoIcon:ClearAllPoints()
										frame.ScooterScaleMultInfoIcon:SetPoint("RIGHT", frame.Text, "LEFT", -5, 0)
									end
								end)
							end
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
				local row = Settings.CreateElementInitializer("SettingsCheckboxControlTemplate", { name = label, setting = setting, options = {}, componentId = componentId })
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
							-- Theme the checkbox checkmark to green
							if cb and panel.ThemeCheckbox then panel.ThemeCheckbox(cb) end
						end
						-- Add info icon next to the label - ONLY for Unit Frame "Use Custom Borders" checkbox
						if frame and frame.Text then
							local labelText = frame.Text:GetText()
							if labelText == "Use Custom Borders" and (componentId == "ufPlayer" or componentId == "ufTarget" or componentId == "ufFocus" or componentId == "ufPet") then
								-- This is the Unit Frame checkbox - create/show the icon
								if panel and panel.CreateInfoIcon then
									if not frame.ScooterInfoIcon then
										local tooltipText = "Enables custom borders by disabling Blizzard's default frame art. Note: This also disables Aggro Glow and Reputation Colors—we're aiming to replace those features in a future update."
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
	
end

panel.UnitFramesSections.root = build

return build