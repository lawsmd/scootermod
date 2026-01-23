local addonName, addon = ...

addon.SettingsPanel = addon.SettingsPanel or {}
local panel = addon.SettingsPanel
panel.UnitFramesSections = panel.UnitFramesSections or {}

local function build(ctx, init)
	local componentId = ctx.componentId
	local title = ctx.title
	local panel = ctx.panel or panel
	local addon = ctx.addon or addon

	-- Skip for ToT - it has its own debuff system (future section)
	if componentId == "ufToT" then return end
	-- Skip for Boss - it has its own scaffolded sections
	if componentId == "ufBoss" then return end

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
							if panel and panel.ThemeSliderValue then panel.ThemeSliderValue(f) end
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
											skipApply       = true,  -- Avoid taint from RequestApplyChanges
										})
									elseif addon.EditMode.SetSetting then
										addon.EditMode.SetSetting(frameUF, sid, val)
										-- Nudge visuals; call specific updater if present
										if type(frameUF.UpdateSystemSettingBuffsOnTop) == "function" then pcall(frameUF.UpdateSystemSettingBuffsOnTop, frameUF) end
										if addon.EditMode.SaveOnly then addon.EditMode.SaveOnly() end
										-- Skip RequestApplyChanges to avoid taint
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
								if f.Control and panel.ThemeDropdownWithSteppers then panel.ThemeDropdownWithSteppers(f.Control) end
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
									if nv < 1 then nv = 1 elseif nv > 8 then nv = 8 end
									t.borderThickness = nv
									applyNow()
								end
								local opts = Settings.CreateSliderOptions(1, 8, 0.2)
								opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return string.format("%.1f", v) end)
								local thkSetting = CreateLocalSetting("Border Thickness", "number", getThk, setThk, getThk())
								local sf = CreateFrame("Frame", nil, frame.PageC, "SettingsSliderControlTemplate")
								_thkFrame = sf
								local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = "Border Thickness", setting = thkSetting, options = opts })
								sf.GetElementData = function() return initSlider end
								sf:SetPoint("TOPLEFT", 4, y.y)
								sf:SetPoint("TOPRIGHT", -16, y.y)
								initSlider:InitFrame(sf)
								if sf.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(sf.Text) end
								if panel and panel.ThemeSliderValue then panel.ThemeSliderValue(sf) end
								y.y = y.y - 34
							end
	
							-- Initial gray-out state
							refreshBorderEnabledState()
						end
	
						-- Tab D (Text) is present for layout consistency and will be
						-- populated in a later phase. For now it intentionally remains empty.
	
						-- PageE: Visibility tab (Hide Buffs & Debuffs)
						do
							local y = { y = -50 }
	
							local function applyNow()
								local uk = unitKey()
								if addon and addon.ApplyUnitFrameBuffsDebuffsFor then
									addon.ApplyUnitFrameBuffsDebuffsFor(uk)
								end
							end
	
							-- Hide Buffs & Debuffs checkbox
							do
								local setting = CreateLocalSetting("Hide Buffs & Debuffs", "boolean",
									function()
										local t = ensureUFDB() or {}
										return t.hideBuffsDebuffs == true
									end,
									function(v)
										local t = ensureUFDB(); if not t then return end
										t.hideBuffsDebuffs = (v == true)
										applyNow()
									end,
									false)
								local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = "Hide Buffs & Debuffs", setting = setting, options = {} })
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
					end
	
					local tabBD = Settings.CreateElementInitializer("ScooterTabbedSectionTemplate", bdData)
					-- STATIC HEIGHT: Buffs & Debuffs tabs now host multiple controls per tab (Scale, Width/Height,
					-- Border options, and upcoming Text settings). Match the standard Unit Frame tabbed height (330px)
					-- used by Health/Power/Portrait text sections to accommodate up to ~7 controls per tab.
					tabBD.GetExtent = function() return 330 end
					tabBD:AddShownPredicate(function() return panel:IsSectionExpanded(componentId, "Buffs & Debuffs") end)
					table.insert(init, tabBD)
				end
	
				-- Misc. collapsible section (Target only) - contains miscellaneous visibility/hide options
				if componentId == "ufTarget" then
					local expInitializerMisc = Settings.CreateElementInitializer("ScooterExpandableSectionTemplate", {
						name = "Misc.",
						sectionKey = "Misc.",
						componentId = componentId,
						expanded = panel:IsSectionExpanded(componentId, "Misc."),
					})
					expInitializerMisc.GetExtent = function() return 30 end
					table.insert(init, expInitializerMisc)
	
					-- Hide Threat Meter checkbox (parent-level setting, no tabbed section)
					do
						local function ensureUFDB()
							local db = addon and addon.db and addon.db.profile
							if not db then return nil end
							db.unitFrames = db.unitFrames or {}
							db.unitFrames.Target = db.unitFrames.Target or {}
							db.unitFrames.Target.misc = db.unitFrames.Target.misc or {}
							return db.unitFrames.Target.misc
						end
	
						local function applyNow()
							if addon and addon.ApplyTargetThreatMeterVisibility then
								addon.ApplyTargetThreatMeterVisibility()
							end
						end
	
						local setting = CreateLocalSetting("Hide Threat Meter", "boolean",
							function()
								local t = ensureUFDB() or {}
								return t.hideThreatMeter == true
							end,
							function(v)
								local t = ensureUFDB(); if not t then return end
								t.hideThreatMeter = (v == true)
								applyNow()
							end,
							false)
						local row = Settings.CreateElementInitializer("SettingsCheckboxControlTemplate", { name = "Hide Threat Meter", setting = setting, options = {} })
						row.GetExtent = function() return 34 end
						row:AddShownPredicate(function()
							return panel:IsSectionExpanded(componentId, "Misc.")
						end)
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

					-- Hide Boss Icon checkbox (parent-level setting, no tabbed section)
					do
						local function ensureUFDB()
							local db = addon and addon.db and addon.db.profile
							if not db then return nil end
							db.unitFrames = db.unitFrames or {}
							db.unitFrames.Target = db.unitFrames.Target or {}
							db.unitFrames.Target.misc = db.unitFrames.Target.misc or {}
							return db.unitFrames.Target.misc
						end

						local function applyNow()
							if addon and addon.ApplyTargetBossIconVisibility then
								addon.ApplyTargetBossIconVisibility()
							end
						end

						local setting = CreateLocalSetting("Hide Boss Icon", "boolean",
							function()
								local t = ensureUFDB() or {}
								return t.hideBossIcon == true
							end,
							function(v)
								local t = ensureUFDB(); if not t then return end
								t.hideBossIcon = (v == true)
								applyNow()
							end,
							false)
						local row = Settings.CreateElementInitializer("SettingsCheckboxControlTemplate", { name = "Hide Boss Icon", setting = setting, options = {} })
						row.GetExtent = function() return 34 end
						row:AddShownPredicate(function()
							return panel:IsSectionExpanded(componentId, "Misc.")
						end)
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

					-- Allow Off-Screen Dragging (Target only)
					do
						local label = "Allow Off-Screen Dragging"
						local tooltipText = "We've added this checkbox so that we may move the Unit Frame closer to the edge of the screen than is normally allowed in Edit Mode for the purpose of our Steam Deck UI. On a normally-sized screen, you probably shouldn't use this setting."

						local function ensureUFDB()
							local db = addon and addon.db and addon.db.profile
							if not db then return nil end
							db.unitFrames = db.unitFrames or {}
							db.unitFrames.Target = db.unitFrames.Target or {}
							db.unitFrames.Target.misc = db.unitFrames.Target.misc or {}
							return db.unitFrames.Target.misc
						end

						local function applyNow()
							if addon and addon.ApplyUnitFrameOffscreenUnlockFor then
								addon.ApplyUnitFrameOffscreenUnlockFor("Target")
							end
						end

						local setting = CreateLocalSetting(label, "boolean",
							function()
								local t = ensureUFDB() or {}
								-- New checkbox key, with legacy fallback to the old slider value.
								if t.allowOffscreenDrag == true then return true end
								local legacy = tonumber(t.containerOffsetX) or 0
								return legacy ~= 0
							end,
							function(v)
								local t = ensureUFDB(); if not t then return end
								t.allowOffscreenDrag = (v == true)
								-- Clear legacy slider value to avoid drift on reload.
								t.containerOffsetX = nil
								applyNow()
							end,
							false)

						local row = Settings.CreateElementInitializer("SettingsCheckboxControlTemplate", { name = label, setting = setting, options = {}, componentId = componentId })
						row.GetExtent = function() return 34 end
						row:AddShownPredicate(function()
							return panel:IsSectionExpanded(componentId, "Misc.")
						end)
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

								-- ScooterMod info tooltip icon (see TOOLTIPSCOOT.md)
								-- Place icon to the LEFT of the checkbox label to avoid crowding long text.
								local cb = frame and (frame.Checkbox or frame.CheckBox or (frame.Control and frame.Control.Checkbox))
								local labelFS = (cb and cb.Text) or (frame and frame.Text)
								if labelFS and panel and panel.CreateInfoIcon then
									if not frame.ScooterOffscreenUnlockInfoIcon then
										frame.ScooterOffscreenUnlockInfoIcon = panel.CreateInfoIcon(frame, tooltipText, "RIGHT", "LEFT", -6, 0, 32)
									else
										frame.ScooterOffscreenUnlockInfoIcon.TooltipText = tooltipText
										frame.ScooterOffscreenUnlockInfoIcon:Show()
									end
									local icon = frame.ScooterOffscreenUnlockInfoIcon
									if icon and icon.ClearAllPoints and icon.SetPoint then
										icon:ClearAllPoints()
										icon:SetPoint("RIGHT", labelFS, "LEFT", -6, 0)
									end
								end
							end
						end
						table.insert(init, row)
					end
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
							if panel and panel.ThemeSliderValue then panel.ThemeSliderValue(f) end
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
											skipApply       = true,  -- Avoid taint from RequestApplyChanges
										})
									elseif addon.EditMode.SetSetting then
										addon.EditMode.SetSetting(frameUF, sid, val)
										if type(frameUF.UpdateSystemSettingBuffsOnTop) == "function" then pcall(frameUF.UpdateSystemSettingBuffsOnTop, frameUF) end
										if addon.EditMode.SaveOnly then addon.EditMode.SaveOnly() end
										-- Skip RequestApplyChanges to avoid taint
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
								if f.Control and panel.ThemeDropdownWithSteppers then panel.ThemeDropdownWithSteppers(f.Control) end
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
									if nv < 1 then nv = 1 elseif nv > 8 then nv = 8 end
									t.borderThickness = nv
									applyNow()
								end
								local opts = Settings.CreateSliderOptions(1, 8, 0.2)
								opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return string.format("%.1f", v) end)
								local thkSetting = CreateLocalSetting("Border Thickness", "number", getThk, setThk, getThk())
								local sf = CreateFrame("Frame", nil, frame.PageC, "SettingsSliderControlTemplate")
								_thkFrame = sf
								local initSlider = Settings.CreateSettingInitializer("SettingsSliderControlTemplate", { name = "Border Thickness", setting = thkSetting, options = opts })
								sf.GetElementData = function() return initSlider end
								sf:SetPoint("TOPLEFT", 4, y.y)
								sf:SetPoint("TOPRIGHT", -16, y.y)
								initSlider:InitFrame(sf)
								if sf.Text and panel and panel.ApplyRobotoWhite then panel.ApplyRobotoWhite(sf.Text) end
								if panel and panel.ThemeSliderValue then panel.ThemeSliderValue(sf) end
								y.y = y.y - 34
							end
	
							-- Initial gray-out state
							refreshBorderEnabledState()
						end
	
						-- Tab D (Text) is present for layout consistency and will be
						-- populated in a later phase. For now it intentionally remains empty.
	
						-- PageE: Visibility tab (Hide Buffs & Debuffs)
						do
							local y = { y = -50 }
	
							local function applyNow()
								local uk = unitKey()
								if addon and addon.ApplyUnitFrameBuffsDebuffsFor then
									addon.ApplyUnitFrameBuffsDebuffsFor(uk)
								end
							end
	
							-- Hide Buffs & Debuffs checkbox
							do
								local setting = CreateLocalSetting("Hide Buffs & Debuffs", "boolean",
									function()
										local t = ensureUFDB() or {}
										return t.hideBuffsDebuffs == true
									end,
									function(v)
										local t = ensureUFDB(); if not t then return end
										t.hideBuffsDebuffs = (v == true)
										applyNow()
									end,
									false)
								local initCb = Settings.CreateSettingInitializer("SettingsCheckboxControlTemplate", { name = "Hide Buffs & Debuffs", setting = setting, options = {} })
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
					end
	
					local tabBDF = Settings.CreateElementInitializer("ScooterTabbedSectionTemplate", bdDataF)
					-- STATIC HEIGHT: align Focus Buffs & Debuffs tab height with Target/Health/Power/Portrait (330px)
					-- so the layout can comfortably display up to ~7 controls per tab without clipping.
					tabBDF.GetExtent = function() return 330 end
					tabBDF:AddShownPredicate(function() return panel:IsSectionExpanded(componentId, "Buffs & Debuffs") end)
					table.insert(init, tabBDF)
				end
	
end

panel.UnitFramesSections.buffs = build

return build