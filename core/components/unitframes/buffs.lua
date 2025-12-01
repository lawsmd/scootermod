local addonName, addon = ...
local Util = addon.ComponentsUtil
local CleanupIconBorderAttachments = Util.CleanupIconBorderAttachments
local ClampOpacity = Util.ClampOpacity

-- Unit Frames: Buffs & Debuffs positioning and sizing (Target/Focus)
do
	-- Store original positions per aura frame so offsets remain relative to stock layout
	local originalAuraPositions = {}
	-- Store original sizes per aura frame so we can reason about defaults if needed
	local originalAuraSizes = {}

	local function resolveUnitFrame(unit)
		local mgr = _G.EditModeManagerFrame
		local EM = _G.Enum and _G.Enum.EditModeUnitFrameSystemIndices
		local EMSys = _G.Enum and _G.Enum.EditModeSystem
		if mgr and EM and EMSys and mgr.GetRegisteredSystemFrame then
			local idx = (unit == "Target" and EM.Target) or (unit == "Focus" and EM.Focus) or nil
			if idx then
				local frame = mgr:GetRegisteredSystemFrame(EMSys.UnitFrame, idx)
				if frame then
					return frame
				end
			end
		end
		-- Fallback to global frames if Edit Mode lookup is unavailable
		if unit == "Target" then
			return _G.TargetFrame
		elseif unit == "Focus" then
			return _G.FocusFrame
		end
		return nil
	end

	local function applyBuffsDebuffsForUnit(unit)
		if unit ~= "Target" and unit ~= "Focus" then return end

		local db = addon and addon.db and addon.db.profile
		if not db then return end

		db.unitFrames = db.unitFrames or {}
		db.unitFrames[unit] = db.unitFrames[unit] or {}
		db.unitFrames[unit].buffsDebuffs = db.unitFrames[unit].buffsDebuffs or {}
		local cfg = db.unitFrames[unit].buffsDebuffs

		local frame = resolveUnitFrame(unit)
		if not frame then return end

		local offsetX = tonumber(cfg.offsetX) or 0
		local offsetY = tonumber(cfg.offsetY) or 0
		local iconWidth = tonumber(cfg.iconWidth)
		local iconHeight = tonumber(cfg.iconHeight)
		local scalePct = tonumber(cfg.iconScale) or 100
		if scalePct < 50 then scalePct = 50 elseif scalePct > 150 then scalePct = 150 end
		local scaleMultiplier = scalePct / 100.0
		local hideBuffsDebuffs = cfg.hideBuffsDebuffs == true

		-- Helper: hide or show all aura frames in a pool
		local function setPoolVisibility(pool, hidden)
			if not pool or not pool.EnumerateActive then return end
			for auraFrame in pool:EnumerateActive() do
				if auraFrame then
					if hidden then
						auraFrame:SetAlpha(0)
						if auraFrame.EnableMouse then auraFrame:EnableMouse(false) end
					else
						auraFrame:SetAlpha(1)
						if auraFrame.EnableMouse then auraFrame:EnableMouse(true) end
					end
				end
			end
		end

		-- Apply visibility to all active aura frames in the pools
		local auraPools = frame.auraPools
		if auraPools and auraPools.GetPool then
			local buffPool = auraPools:GetPool("TargetBuffFrameTemplate")
			local debuffPool = auraPools:GetPool("TargetDebuffFrameTemplate")
			setPoolVisibility(buffPool, hideBuffsDebuffs)
			setPoolVisibility(debuffPool, hideBuffsDebuffs)
		end

		-- If hidden, skip all the detailed styling work (positioning, sizing, borders)
		if hideBuffsDebuffs then
			return
		end

		local function applyToPool(pool)
			if not pool or not pool.EnumerateActive then return end

			for auraFrame in pool:EnumerateActive() do
				-- Sizing: treat Blizzard's layout as the baseline and only grow/shrink
				-- relative to the stock size. We seed cfg.iconWidth/iconHeight from the
				-- first active aura we see so default sliders match Blizzard visuals.
				if auraFrame and auraFrame.SetSize then
					if not originalAuraSizes[auraFrame] then
						originalAuraSizes[auraFrame] = {
							width = auraFrame:GetWidth() or 21,
							height = auraFrame:GetHeight() or 21,
						}
					end

					-- Seed DB defaults from the first aura frame if not already set
					if not iconWidth or not iconHeight then
						local base = originalAuraSizes[auraFrame]
						if base then
							if not iconWidth then
								cfg.iconWidth = cfg.iconWidth or base.width
								iconWidth = tonumber(cfg.iconWidth) or base.width
							end
							if not iconHeight then
								cfg.iconHeight = cfg.iconHeight or base.height
								iconHeight = tonumber(cfg.iconHeight) or base.height
							end
						end
					end

					if iconWidth and iconHeight then
						local w = iconWidth
						local h = iconHeight
						-- Defensive clamp against absurdly small values
						if w < 8 then w = 8 end
						if h < 8 then h = 8 end
						auraFrame:SetSize(w, h)

						-- Keep icon/cooldown filling the aura frame
						local icon = auraFrame.Icon
						if icon and icon.SetAllPoints then
							icon:SetAllPoints(auraFrame)
						end
						local cd = auraFrame.Cooldown
						if cd and cd.SetAllPoints then
							cd:SetAllPoints(auraFrame)
						end

						-- Grow Blizzard's default debuff border alongside the icon so it continues
						-- to frame correctly when custom borders are disabled.
						local blizzBorder = auraFrame.Border
						if blizzBorder and blizzBorder.SetSize and (not cfg.borderEnable) then
							blizzBorder:SetSize(w + 2, h + 2)
						end
					end

					-- Apply uniform scale so we can shrink/grow icons without fighting
					-- Blizzard's internal aura-row math. This affects the visual size
					-- while leaving the logical layout width/height unchanged.
					if auraFrame.SetScale then
						auraFrame:SetScale(scaleMultiplier)
					end

					-- Custom icon border styling (Essential Cooldowns-style) when enabled
					local icon = auraFrame.Icon
					local blizzBorder = auraFrame.Border
					if icon then
						if cfg.borderEnable then
							-- Hide Blizzard's default debuff border so it doesn't compete visually
							if blizzBorder and blizzBorder.Hide then
								blizzBorder:Hide()
							elseif blizzBorder and blizzBorder.SetAlpha then
								blizzBorder:SetAlpha(0)
							end

							local styleKey = cfg.borderStyle or "square"
							local thickness = tonumber(cfg.borderThickness) or 1
							if thickness < 1 then thickness = 1 elseif thickness > 16 then thickness = 16 end
							local tintEnabled = cfg.borderTintEnable and type(cfg.borderTintColor) == "table"
							local tintColor
							if tintEnabled then
								local c = cfg.borderTintColor or {1,1,1,1}
								tintColor = { c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 }
							end

							-- Hard reset any existing ScooterMod borders on this icon and its wrapper
							-- before applying a new style to avoid any chance of layered leftovers.
							if addon.Borders and addon.Borders.HideAll then
								addon.Borders.HideAll(icon)
								local container = icon.ScooterIconBorderContainer
								if container then
									addon.Borders.HideAll(container)
								end
							end

							if addon.ApplyIconBorderStyle then
								addon.ApplyIconBorderStyle(icon, styleKey, {
									thickness = thickness,
									color = tintEnabled and tintColor or nil,
									tintEnabled = tintEnabled,
									db = cfg,
									thicknessKey = "borderThickness",
									tintColorKey = "borderTintColor",
									defaultThickness = 1,
								})
							end
						else
							-- Restore Blizzard's default border and hide any custom border textures
							if addon.Borders and addon.Borders.HideAll then
								addon.Borders.HideAll(icon)
								-- Also clear any borders attached to the icon's wrapper container created
								-- by ApplyIconBorderStyle when the icon is a Texture.
								local container = icon.ScooterIconBorderContainer
								if container then
									addon.Borders.HideAll(container)
								end
							end
							if blizzBorder then
								if blizzBorder.Show then
									blizzBorder:Show()
								elseif blizzBorder.SetAlpha then
									blizzBorder:SetAlpha(1)
								end
							end
						end
					end
				end
			end
		end

		if InCombatLockdown() then
			if _G.C_Timer and _G.C_Timer.After then
				local u = unit
				_G.C_Timer.After(0.1, function()
					if not InCombatLockdown() then
						applyBuffsDebuffsForUnit(u)
					end
				end)
			end
			return
		end

		-- Use Blizzard's aura pools to get the active Buff/Debuff frames.
		-- Target/Focus both inherit TargetFrameTemplate, which creates pools
		-- for "TargetBuffFrameTemplate" and "TargetDebuffFrameTemplate".
		local auraPools = frame.auraPools
		if auraPools and auraPools.GetPool then
			local buffPool = auraPools:GetPool("TargetBuffFrameTemplate")
			local debuffPool = auraPools:GetPool("TargetDebuffFrameTemplate")
			applyToPool(buffPool)
			applyToPool(debuffPool)
		end

		-- Positioning: nudge the shared Buffs/Debuffs containers so rows stay intact
		-- and all auras move together, regardless of row/column indexing.
		local contextual = frame.TargetFrameContent and frame.TargetFrameContent.TargetFrameContentContextual
		if contextual then
			local containers = { contextual.buffs, contextual.debuffs }
			for _, holder in ipairs(containers) do
				if holder and holder.GetPoint then
					if not originalAuraPositions[holder] then
						local p, relTo, relPoint, xOfs, yOfs = holder:GetPoint(1)
						if p then
							originalAuraPositions[holder] = {
								point = p,
								relativeTo = relTo,
								relativePoint = relPoint,
								xOfs = xOfs or 0,
								yOfs = yOfs or 0,
							}
						end
					end
					local orig = originalAuraPositions[holder]
					if orig then
						holder:ClearAllPoints()
						holder:SetPoint(
							orig.point or "CENTER",
							orig.relativeTo,
							orig.relativePoint or orig.point or "CENTER",
							(orig.xOfs or 0) + offsetX,
							(orig.yOfs or 0) + offsetY
						)
					end
				end
			end
		end
	end

	function addon.ApplyUnitFrameBuffsDebuffsFor(unit)
		applyBuffsDebuffsForUnit(unit)
	end

	function addon.ApplyAllUnitFrameBuffsDebuffs()
		applyBuffsDebuffsForUnit("Target")
		applyBuffsDebuffsForUnit("Focus")
	end

	-- Hook aura updates so ScooterMod re-applies offsets/sizing after Blizzard layouts
	if _G.TargetFrame and _G.TargetFrame.UpdateAuras and _G.hooksecurefunc then
		_G.hooksecurefunc(_G.TargetFrame, "UpdateAuras", function(self)
			if addon and addon.ApplyUnitFrameBuffsDebuffsFor then
				addon.ApplyUnitFrameBuffsDebuffsFor("Target")
			end
		end)
	end
	if _G.FocusFrame and _G.FocusFrame.UpdateAuras and _G.hooksecurefunc then
		_G.hooksecurefunc(_G.FocusFrame, "UpdateAuras", function(self)
			if addon and addon.ApplyUnitFrameBuffsDebuffsFor then
				addon.ApplyUnitFrameBuffsDebuffsFor("Focus")
			end
		end)
	end
end

