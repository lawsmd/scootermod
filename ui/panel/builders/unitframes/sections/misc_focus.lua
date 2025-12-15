local addonName, addon = ...

addon.SettingsPanel = addon.SettingsPanel or {}
local panel = addon.SettingsPanel
panel.UnitFramesSections = panel.UnitFramesSections or {}

local function build(ctx, init)
	local componentId = ctx.componentId
	local title = ctx.title
	local panel = ctx.panel or panel
	local addon = ctx.addon or addon

	-- Skip for ToT - Focus-only section
	if componentId == "ufToT" then return end

				-- Misc. collapsible section (Focus only) - contains miscellaneous visibility/hide options
				if componentId == "ufFocus" then
					local expInitializerMiscF = Settings.CreateElementInitializer("ScooterExpandableSectionTemplate", {
						name = "Misc.",
						sectionKey = "Misc.",
						componentId = componentId,
						expanded = panel:IsSectionExpanded(componentId, "Misc."),
					})
					expInitializerMiscF.GetExtent = function() return 30 end
					table.insert(init, expInitializerMiscF)
	
					-- Hide Threat Meter checkbox (parent-level setting, no tabbed section)
					do
						local function ensureUFDB()
							local db = addon and addon.db and addon.db.profile
							if not db then return nil end
							db.unitFrames = db.unitFrames or {}
							db.unitFrames.Focus = db.unitFrames.Focus or {}
							db.unitFrames.Focus.misc = db.unitFrames.Focus.misc or {}
							return db.unitFrames.Focus.misc
						end
	
						local function applyNow()
							if addon and addon.ApplyFocusThreatMeterVisibility then
								addon.ApplyFocusThreatMeterVisibility()
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
				end
	
end

panel.UnitFramesSections.misc_focus = build

return build