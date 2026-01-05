local addonName, addon = ...

addon.SettingsPanel = addon.SettingsPanel or {}
local panel = addon.SettingsPanel
panel.UnitFramesSections = panel.UnitFramesSections or {}

local function build(ctx, init)
	local componentId = ctx.componentId
	local title = ctx.title
	local panel = ctx.panel or panel
	local addon = ctx.addon or addon

	-- Skip for ToT - Player/Pet only section
	if componentId == "ufToT" then return end
	-- Skip for Boss - it has its own scaffolded sections
	if componentId == "ufBoss" then return end

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
	
end

panel.UnitFramesSections.visibility = build

return build