local addonName, addon = ...

addon.SettingsPanel = addon.SettingsPanel or {}
local panel = addon.SettingsPanel
panel.UnitFramesSections = panel.UnitFramesSections or {}

local function build(ctx, init)
	local componentId = ctx.componentId
	local title = ctx.title
	local panel = ctx.panel or panel
	local addon = ctx.addon or addon

	-- Skip for ToT - Player-only section
	if componentId == "ufToT" then return end

				-- Misc. collapsible section (Player only) - contains miscellaneous visibility/hide options
				if componentId == "ufPlayer" then
					local expInitializerMiscP = Settings.CreateElementInitializer("ScooterExpandableSectionTemplate", {
						name = "Misc.",
						sectionKey = "Misc.",
						componentId = componentId,
						expanded = panel:IsSectionExpanded(componentId, "Misc."),
					})
					expInitializerMiscP.GetExtent = function() return 30 end
					table.insert(init, expInitializerMiscP)
	
					-- Hide Player Role Icon checkbox (parent-level setting, no tabbed section)
					do
						local function ensureUFDB()
							local db = addon and addon.db and addon.db.profile
							if not db then return nil end
							db.unitFrames = db.unitFrames or {}
							db.unitFrames.Player = db.unitFrames.Player or {}
							db.unitFrames.Player.misc = db.unitFrames.Player.misc or {}
							return db.unitFrames.Player.misc
						end
	
						local function applyNow()
							if addon and addon.ApplyPlayerRoleIconVisibility then
								addon.ApplyPlayerRoleIconVisibility()
							end
						end
	
						local setting = CreateLocalSetting("Hide Player Role Icon", "boolean",
							function()
								local t = ensureUFDB() or {}
								return t.hideRoleIcon == true
							end,
							function(v)
								local t = ensureUFDB(); if not t then return end
								t.hideRoleIcon = (v == true)
								applyNow()
							end,
							false)
						local row = Settings.CreateElementInitializer("SettingsCheckboxControlTemplate", { name = "Hide Player Role Icon", setting = setting, options = {} })
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
	
					-- Hide Player Group Number checkbox (parent-level setting, no tabbed section)
					do
						local function ensureUFDB()
							local db = addon and addon.db and addon.db.profile
							if not db then return nil end
							db.unitFrames = db.unitFrames or {}
							db.unitFrames.Player = db.unitFrames.Player or {}
							db.unitFrames.Player.misc = db.unitFrames.Player.misc or {}
							return db.unitFrames.Player.misc
						end
	
						local function applyNow()
							if addon and addon.ApplyPlayerGroupNumberVisibility then
								addon.ApplyPlayerGroupNumberVisibility()
							end
						end
	
						local setting = CreateLocalSetting("Hide Player Group Number", "boolean",
							function()
								local t = ensureUFDB() or {}
								return t.hideGroupNumber == true
							end,
							function(v)
								local t = ensureUFDB(); if not t then return end
								t.hideGroupNumber = (v == true)
								applyNow()
							end,
							false)
						local row = Settings.CreateElementInitializer("SettingsCheckboxControlTemplate", { name = "Hide Player Group Number", setting = setting, options = {} })
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

					-- Allow Off-Screen Dragging (Player only)
					do
						local label = "Allow Off-Screen Dragging"
						local tooltipText = "We've added this checkbox so that we may move the Unit Frame closer to the edge of the screen than is normally allowed in Edit Mode for the purpose of our Steam Deck UI. On a normally-sized screen, you probably shouldn't use this setting."

						local function ensureUFDB()
							local db = addon and addon.db and addon.db.profile
							if not db then return nil end
							db.unitFrames = db.unitFrames or {}
							db.unitFrames.Player = db.unitFrames.Player or {}
							db.unitFrames.Player.misc = db.unitFrames.Player.misc or {}
							return db.unitFrames.Player.misc
						end

						local function applyNow()
							if addon and addon.ApplyUnitFrameOffscreenUnlockFor then
								addon.ApplyUnitFrameOffscreenUnlockFor("Player")
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
	end

panel.UnitFramesSections.misc_player = build

return build