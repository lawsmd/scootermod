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
				end
	end

panel.UnitFramesSections.misc_player = build

return build