local addonName, addon = ...
local Util = addon.ComponentsUtil
local ClampOpacity = Util.ClampOpacity

-- Unit Frames: Cast Bar positioning (Target/Focus only, addon-managed offsets)
do
	local function resolveCastBarFrame(unit)
		if unit == "Player" then
			return _G.PlayerCastingBarFrame
		end
		if unit == "Target" then
			return _G.TargetFrameSpellBar
		elseif unit == "Focus" then
			return _G.FocusFrameSpellBar
		end
		return nil
	end

	-- Helper to traverse nested keys safely (copied from bars.lua pattern)
	local function getNested(root, ...)
		if not root then return nil end
		local cur = root
		for i = 1, select("#", ...) do
			local key = select(i, ...)
			if type(cur) ~= "table" then return nil end
			cur = cur[key]
		end
		return cur
	end

	-- Resolve Health Bar for Target/Focus (deterministic paths from framestack findings)
	local function resolveHealthBar(unit)
		if unit == "Target" then
			local root = _G.TargetFrame
			return getNested(root, "TargetFrameContent", "TargetFrameContentMain", "HealthBarsContainer", "HealthBar")
		elseif unit == "Focus" then
			local root = _G.FocusFrame
			return getNested(root, "TargetFrameContent", "TargetFrameContentMain", "HealthBarsContainer", "HealthBar")
		end
		return nil
	end

	-- Resolve Power Bar (ManaBar) for Target/Focus (deterministic paths from framestack findings)
	local function resolvePowerBar(unit)
		if unit == "Target" then
			local root = _G.TargetFrame
			return getNested(root, "TargetFrameContent", "TargetFrameContentMain", "ManaBar")
		elseif unit == "Focus" then
			local root = _G.FocusFrame
			return getNested(root, "TargetFrameContent", "TargetFrameContentMain", "ManaBar")
		end
		return nil
	end

	-- Track which cast bars have custom anchor mode active, so the SetPoint hook knows when to re-apply
	local activeAnchorModes = {}
	-- Track scheduled re-apply timers to avoid duplicate scheduling
	local pendingReapply = {}

	-- Store original positions per frame so offsets are always relative to stock layout
	local originalPositions = {}
	-- Store original widths per frame for width-percent scaling
	local originalWidths = {}
	-- Store original icon anchors/sizes so padding and per-axis sizing are relative to stock layout
	local originalIconAnchors = {}
	local originalIconSizes = {}
	-- Store original spark vertex colors/alpha so "Default" can restore stock spark appearance
	local originalSparkVertexColor = {}
	local originalSparkAlpha = {}
	-- Baseline anchors for Cast Time text (Player only)
	addon._ufCastTimeTextBaselines = addon._ufCastTimeTextBaselines or {}
	-- Baseline anchors for Spell Name text (Player only)
	addon._ufCastSpellNameBaselines = addon._ufCastSpellNameBaselines or {}

	local function applyCastBarForUnit(unit)
		if unit ~= "Player" and unit ~= "Target" and unit ~= "Focus" then return end

		local db = addon and addon.db and addon.db.profile
		if not db then return end

		db.unitFrames = db.unitFrames or {}
		db.unitFrames[unit] = db.unitFrames[unit] or {}
		db.unitFrames[unit].castBar = db.unitFrames[unit].castBar or {}
		local cfg = db.unitFrames[unit].castBar

		local frame = resolveCastBarFrame(unit)
		if not frame then return end

		local isPlayer = (unit == "Player")

		-- For the Player cast bar, read the current Edit Mode "Lock to Player Frame" setting so
		-- we only override position when the bar is locked underneath the Player frame. When the
		-- bar is unlocked and freely positioned in Edit Mode, ScooterMod should not fight that.
		local isLockedToPlayerFrame = false
		if isPlayer and addon and addon.EditMode and addon.EditMode.GetSetting then
			local mgr = _G.EditModeManagerFrame
			local EMSys = _G.Enum and _G.Enum.EditModeSystem
			local sid = _G.Enum and _G.Enum.EditModeCastBarSetting and _G.Enum.EditModeCastBarSetting.LockToPlayerFrame
			if mgr and EMSys and mgr.GetRegisteredSystemFrame and sid then
				local emFrame = mgr:GetRegisteredSystemFrame(EMSys.CastBar, nil)
				if emFrame then
					local v = addon.EditMode.GetSetting(emFrame, sid)
					isLockedToPlayerFrame = (tonumber(v) or 0) ~= 0
				end
			end
		end

		-- Install lightweight hooks once to keep cast bar styling persistent when
		-- Blizzard updates the bar's texture/color (cast start/stop, etc.).
		if not frame._ScootCastHooksInstalled and _G.hooksecurefunc then
			frame._ScootCastHooksInstalled = true
			local hookUnit = unit
			_G.hooksecurefunc(frame, "SetStatusBarTexture", function(self, ...)
				-- Ignore ScooterMod's own internal texture writes
				if self._ScootUFInternalTextureWrite then return end
				if addon and addon.ApplyUnitFrameCastBarFor then
					-- Mark this as a visual-only refresh so we can safely reapply
					-- textures/colors in combat without re-anchoring secure frames.
					self._ScootCastVisualOnly = true
					addon.ApplyUnitFrameCastBarFor(hookUnit)
					self._ScootCastVisualOnly = nil
				end
			end)
			_G.hooksecurefunc(frame, "SetStatusBarColor", function(self, ...)
				if addon and addon.ApplyUnitFrameCastBarFor then
					self._ScootCastVisualOnly = true
					addon.ApplyUnitFrameCastBarFor(hookUnit)
					self._ScootCastVisualOnly = nil
				end
			end)
			-- Hook SetPoint to detect when Blizzard re-anchors the cast bar and re-apply
			-- our custom anchoring if we have a non-default anchor mode active.
			_G.hooksecurefunc(frame, "SetPoint", function(self, ...)
				-- Ignore our own SetPoint calls (flagged to prevent infinite loops)
				if self._ScootIgnoreSetPoint then return end
				-- Only re-apply if we have a custom anchor mode active for this unit
				local mode = activeAnchorModes[hookUnit]
				if mode and mode ~= "default" then
					-- Schedule a re-apply on the next frame to avoid recursive issues
					-- and to let Blizzard finish its update first
					if not pendingReapply[hookUnit] then
						pendingReapply[hookUnit] = true
						C_Timer.After(0, function()
							pendingReapply[hookUnit] = nil
							-- NOTE: Combat lockdown check removed for Target/Focus cast bars.
							-- TargetFrameSpellBar and FocusFrameSpellBar are visual StatusBars,
							-- not protected action frames. SetPoint on them does not taint
							-- secure execution, so we can safely reposition during combat.
							if addon and addon.ApplyUnitFrameCastBarFor then
								addon.ApplyUnitFrameCastBarFor(hookUnit)
							end
						end)
					end
				end
			end)

			-- Hook AdjustPosition (Target/Focus only) to immediately reapply custom anchoring
			-- after Blizzard repositions the cast bar (aura updates, ToT changes, etc.).
			-- This is the function that causes the flicker - it's called from UpdateAuras()
			-- on every UNIT_AURA event, which happens frequently during combat.
			if (hookUnit == "Target" or hookUnit == "Focus") and frame.AdjustPosition then
				_G.hooksecurefunc(frame, "AdjustPosition", function(self)
					-- Only re-apply if we have a custom anchor mode active
					local mode = activeAnchorModes[hookUnit]
					if mode and mode ~= "default" then
						-- Re-apply immediately (synchronously) to eliminate flicker.
						-- The _ScootIgnoreSetPoint flag prevents the SetPoint hook from re-triggering.
						-- Target/Focus cast bars are purely visual and do not taint secure execution.
						if addon and addon.ApplyUnitFrameCastBarFor then
							addon.ApplyUnitFrameCastBarFor(hookUnit)
						end
					end
				end)
			end
		end

		-- Capture baseline anchor:
		-- - Player: capture a baseline that represents the Edit Mode "under Player" layout,
		--   but avoid rebasing while ScooterMod offsets are non-zero so we don't compound
		--   offsets on every apply. This keeps slider behaviour linear.
		-- - Target/Focus: capture once so offsets remain relative to stock layout.
		if frame.GetPoint then
			local point, relativeTo, relativePoint, xOfs, yOfs = frame:GetPoint(1)
			if point then
				if isPlayer then
					local hasOffsets =
						(tonumber(cfg.offsetX) or 0) ~= 0 or
						(tonumber(cfg.offsetY) or 0) ~= 0
					-- When offsets are zero and the bar is locked to the Player frame, we
					-- treat the current layout as the new baseline. Otherwise, we keep the
					-- previous baseline so offset sliders remain stable.
					if (not hasOffsets and isLockedToPlayerFrame) or not originalPositions[frame] then
						originalPositions[frame] = {
							point = point,
							relativeTo = relativeTo,
							relativePoint = relativePoint,
							xOfs = xOfs or 0,
							yOfs = yOfs or 0,
						}
					end
				elseif not originalPositions[frame] then
					originalPositions[frame] = {
						point = point,
						relativeTo = relativeTo,
						relativePoint = relativePoint,
						xOfs = xOfs or 0,
						yOfs = yOfs or 0,
					}
				end
			end
		end

		local orig = originalPositions[frame]
		if not orig then return end

		-- Capture original width once
		if not originalWidths[frame] and frame.GetWidth then
			local ok, w = pcall(frame.GetWidth, frame)
			if ok and w then
				originalWidths[frame] = w
			end
		end

		local origWidth = originalWidths[frame]

		-- Capture original icon anchor/size once (per physical Icon texture)
		local iconFrame = frame.Icon
		if iconFrame then
			if not originalIconAnchors[iconFrame] and iconFrame.GetPoint then
				local p, relTo, rp, x, y = iconFrame:GetPoint(1)
				if p then
					originalIconAnchors[iconFrame] = {
						point = p,
						relativeTo = relTo,
						relativePoint = rp,
						xOfs = x or 0,
						yOfs = y or 0,
					}
				end
			end
			if not originalIconSizes[iconFrame] and iconFrame.GetWidth and iconFrame.GetHeight then
				local okW, w = pcall(iconFrame.GetWidth, iconFrame)
				local okH, h = pcall(iconFrame.GetHeight, iconFrame)
				if okW and okH and w and h then
					originalIconSizes[iconFrame] = { width = w, height = h }
				end
			end
		end

		-- Offsets:
		-- - Target/Focus always use addon-managed X/Y offsets (relative to stock layout or custom anchor).
		-- - Player uses offsets only when locked to the Player frame; when unlocked, Edit Mode
		--   owns the free position and ScooterMod must not re-anchor.
		local offsetX, offsetY = 0, 0
		if unit == "Target" or unit == "Focus" then
			offsetX = tonumber(cfg.offsetX) or 0
			offsetY = tonumber(cfg.offsetY) or 0
		elseif isPlayer and isLockedToPlayerFrame then
			offsetX = tonumber(cfg.offsetX) or 0
			offsetY = tonumber(cfg.offsetY) or 0
		end

		-- Anchor Mode (Target/Focus only): determines anchor point for cast bar positioning
		-- "default" = stock Blizzard position, "healthTop/healthBottom/powerTop/powerBottom" = custom anchors
		local anchorMode = (unit == "Target" or unit == "Focus") and (cfg.anchorMode or "default") or "default"

		-- Width percent (50–150%; 100 = stock width)
		local widthPct = tonumber(cfg.widthPct) or 100
		if widthPct < 50 then widthPct = 50 elseif widthPct > 150 then widthPct = 150 end

		-- Cast Bar Scale (addon-only, Target/Focus only; 50–150%; 100 = stock scale)
		local castBarScale = tonumber(cfg.castBarScale) or 100
		if castBarScale < 50 then castBarScale = 50 elseif castBarScale > 150 then castBarScale = 150 end

		-- Icon sizing, padding, and visibility relative to bar
		local iconWidth = tonumber(cfg.iconWidth)
		local iconHeight = tonumber(cfg.iconHeight)
		local iconBarPadding = tonumber(cfg.iconBarPadding) or 0
		local iconDisabled = cfg.iconDisabled == true

		local function apply()
			-- When we are being invoked from a SetStatusBarTexture/SetStatusBarColor hook
			-- during combat, treat this as a "visual-only" refresh: apply textures/colors
			-- but avoid re-anchoring secure frames or changing layout, which can taint.
			local inCombat = InCombatLockdown and InCombatLockdown()
			local visualOnly = inCombat and frame._ScootCastVisualOnly

			-- Layout (position/size/icon) is skipped for in-combat visual-only refreshes.
			if not visualOnly then
				if frame.ClearAllPoints and frame.SetPoint then
					-- Apply width scaling relative to original width (if available)
					if origWidth and frame.SetWidth then
						local scale = widthPct / 100.0
						pcall(frame.SetWidth, frame, origWidth * scale)
					end

					-- Anchor behaviour:
					-- - Player: only override anchors when locked to the Player frame so Edit Mode retains
					--   full control when the bar is unlocked and freely positioned.
					-- - Target/Focus: anchor based on anchorMode setting (default = stock baseline, or custom anchor to Health/Power bar).
					if isPlayer then
						if isLockedToPlayerFrame then
							frame._ScootIgnoreSetPoint = true
							frame:ClearAllPoints()
							frame:SetPoint(
								orig.point,
								orig.relativeTo,
								orig.relativePoint,
								(orig.xOfs or 0) + offsetX,
								(orig.yOfs or 0) + offsetY
							)
							frame._ScootIgnoreSetPoint = nil
						end
					else
						-- Target/Focus: check anchorMode for custom anchoring
						-- Track the active anchor mode so the SetPoint hook knows when to re-apply
						activeAnchorModes[unit] = anchorMode

						local anchorApplied = false
						if anchorMode ~= "default" then
							-- Resolve the target bar based on anchor mode
							local anchorBar
							local anchorEdge -- "top" or "bottom"
							if anchorMode == "healthTop" then
								anchorBar = resolveHealthBar(unit)
								anchorEdge = "top"
							elseif anchorMode == "healthBottom" then
								anchorBar = resolveHealthBar(unit)
								anchorEdge = "bottom"
							elseif anchorMode == "powerTop" then
								anchorBar = resolvePowerBar(unit)
								anchorEdge = "top"
							elseif anchorMode == "powerBottom" then
								anchorBar = resolvePowerBar(unit)
								anchorEdge = "bottom"
							end

							if anchorBar then
								-- Use direct relative anchoring to the Health/Power bar
								-- This automatically handles scale and position changes
								-- - For "top" edges: cast bar sits ABOVE the anchor bar (cast bar's BOTTOM to bar's TOP)
								-- - For "bottom" edges: cast bar sits BELOW the anchor bar (cast bar's TOP to bar's BOTTOM)
								local castBarPoint = (anchorEdge == "top") and "BOTTOM" or "TOP"
								local anchorPoint = (anchorEdge == "top") and "TOP" or "BOTTOM"

								-- Flag to prevent our SetPoint hook from triggering a re-apply loop
								frame._ScootIgnoreSetPoint = true
								frame:ClearAllPoints()
								frame:SetPoint(
									castBarPoint,
									anchorBar,
									anchorPoint,
									offsetX,
									offsetY
								)
								frame._ScootIgnoreSetPoint = nil
								anchorApplied = true
							end
						end

						-- Fallback to default (stock baseline) positioning if custom anchor not applied
						if not anchorApplied then
							frame._ScootIgnoreSetPoint = true
							frame:ClearAllPoints()
							frame:SetPoint(
								orig.point,
								orig.relativeTo,
								orig.relativePoint,
								(orig.xOfs or 0) + offsetX,
								(orig.yOfs or 0) + offsetY
							)
							frame._ScootIgnoreSetPoint = nil
						end
					end

					-- Apply icon visibility, size, and padding before bar styling
					local icon = frame.Icon
					if icon then
						-- Visibility: when disabled, hide the icon via alpha and clear any
						-- container-based borders so only the bar remains.
						if iconDisabled then
							if icon.SetAlpha then pcall(icon.SetAlpha, icon, 0) end
							if icon.ScooterIconBorderContainer and addon.Borders and addon.Borders.HideAll then
								addon.Borders.HideAll(icon.ScooterIconBorderContainer)
							end
						else
							if icon.SetAlpha then pcall(icon.SetAlpha, icon, 1) end

							local baseSize = originalIconSizes[icon]
							if iconWidth or iconHeight then
								local w = tonumber(iconWidth) or (baseSize and baseSize.width) or (icon.GetWidth and icon:GetWidth()) or 16
								local h = tonumber(iconHeight) or (baseSize and baseSize.height) or (icon.GetHeight and icon:GetHeight()) or 16
								-- Clamp to a reasonable range for cast bar icons
								w = math.max(8, math.min(64, w))
								h = math.max(8, math.min(64, h))
								pcall(icon.SetSize, icon, w, h)
								-- Ensure contained texture follows the resized frame
								if icon.Icon and icon.Icon.SetAllPoints then
									icon.Icon:SetAllPoints(icon)
								end
								if icon.IconMask and icon.IconMask.SetAllPoints then
									icon.IconMask:SetAllPoints(icon)
								end
							end

							-- Icon/Bar padding: adjust icon X offset relative to its original anchor
							local baseAnchor = originalIconAnchors[icon]
							if baseAnchor and icon.ClearAllPoints and icon.SetPoint then
								-- Positive padding increases the gap between icon (left) and bar by moving icon further left.
								local pad = tonumber(iconBarPadding) or 0
								local baseX = baseAnchor.xOfs or 0
								local baseY = baseAnchor.yOfs or 0
								local newX = baseX - pad
								icon:ClearAllPoints()
								icon:SetPoint(
									baseAnchor.point or "LEFT",
									baseAnchor.relativeTo or frame,
									baseAnchor.relativePoint or baseAnchor.point or "LEFT",
									newX,
									baseY
								)
							end
						end
					end

					-- Cast Bar Scale (addon-only, Target/Focus only)
					if (unit == "Target" or unit == "Focus") and frame.SetScale then
						local scale = castBarScale / 100.0
						pcall(frame.SetScale, frame, scale)
					end
				end

				-- Player Cast Bar: TextBorder visibility (only visible when unlocked)
				-- The TextBorder frame only exists on PlayerCastingBarFrame when it's not locked to the Player Frame.
				if isPlayer and not isLockedToPlayerFrame then
					local textBorder = frame.TextBorder
					if textBorder then
						local hideTextBorder = cfg.hideTextBorder == true
						if hideTextBorder then
							if textBorder.SetShown then
								pcall(textBorder.SetShown, textBorder, false)
							elseif textBorder.Hide then
								pcall(textBorder.Hide, textBorder)
							end
						else
							if textBorder.SetShown then
								pcall(textBorder.SetShown, textBorder, true)
							elseif textBorder.Show then
								pcall(textBorder.Show, textBorder)
							end
						end
					end
				end

				-- Player Cast Bar: ChannelShadow visibility
				-- The ChannelShadow is the shadow effect behind the cast bar during channeled spells.
				-- Use SetAlpha instead of SetShown/Hide to avoid fighting Blizzard's internal show/hide logic during channeling.
				if isPlayer then
					local channelShadow = frame.ChannelShadow
					if channelShadow then
						local hideChannelingShadow = cfg.hideChannelingShadow == true
						if channelShadow.SetAlpha then
							pcall(channelShadow.SetAlpha, channelShadow, hideChannelingShadow and 0 or 1)
						end
					end
				end
			end

			-- Apply foreground and background styling via shared bar helpers
			-- When visualOnly is true (combat + hook path from SetStatusBarTexture/SetStatusBarColor),
			-- we allow texture/color application so custom styling persists through Blizzard's updates.
			-- Layout changes are already skipped above when visualOnly is true.
			if (not inCombat or visualOnly) and (addon._ApplyToStatusBar or addon._ApplyBackgroundToStatusBar) then
				local db = addon and addon.db and addon.db.profile
				db.unitFrames = db.unitFrames or {}
				db.unitFrames[unit] = db.unitFrames[unit] or {}
				db.unitFrames[unit].castBar = db.unitFrames[unit].castBar or {}
				local cfgStyle = db.unitFrames[unit].castBar

				-- Foreground: texture + color
				if addon._ApplyToStatusBar and frame.GetStatusBarTexture then
					local texKey = cfgStyle.castBarTexture or "default"
					local colorMode = cfgStyle.castBarColorMode or "default"
					local tint = cfgStyle.castBarTint
					-- For class color, follow Health/Power bars and always use player's class
					local unitId = (unit == "Player" and "player") or (unit == "Target" and "target") or (unit == "Focus" and "focus") or (unit == "Pet" and "pet") or "player"
					addon._ApplyToStatusBar(frame, texKey, colorMode, tint, "player", "cast", unitId)
				end

				-- Background: texture + color + opacity
				if addon._ApplyBackgroundToStatusBar then
					local bgTexKey = cfgStyle.castBarBackgroundTexture or "default"
					local bgColorMode = cfgStyle.castBarBackgroundColorMode or "default"
					local bgOpacity = cfgStyle.castBarBackgroundOpacity or 50
					addon._ApplyBackgroundToStatusBar(frame, bgTexKey, bgColorMode, cfgStyle.castBarBackgroundTint, bgOpacity, unit, "cast")
				end
			end

			-- Spark visibility and color (per unit)
			do
				local spark = frame.Spark
				if spark then
					-- Capture the stock spark vertex color/alpha once so "Default" can restore it later.
					if not originalSparkVertexColor[spark] and spark.GetVertexColor then
						local ok, r, g, b, a = pcall(spark.GetVertexColor, spark)
						if not ok or not r or not g or not b then
							r, g, b, a = 1, 1, 1, 1
						end
						originalSparkVertexColor[spark] = { r or 1, g or 1, b or 1, a or 1 }
					end
					if not originalSparkAlpha[spark] and spark.GetAlpha then
						local ok, alpha = pcall(spark.GetAlpha, spark)
						originalSparkAlpha[spark] = (ok and alpha) or 1
					end

					local sparkHidden = cfg.castBarSparkHidden == true
					local colorMode = cfg.castBarSparkColorMode or "default"
					local tintTbl = type(cfg.castBarSparkTint) == "table" and cfg.castBarSparkTint or {1,1,1,1}

					-- Determine effective color from mode:
					-- - "default": use the stock vertex color we captured above.
					-- - "custom": apply the user tint (RGBA) on top of the spark.
					local base = originalSparkVertexColor[spark] or {1,1,1,1}
					local r, g, b, a = base[1] or 1, base[2] or 1, base[3] or 1, base[4] or 1
					if colorMode == "custom" then
						r = tintTbl[1] or r
						g = tintTbl[2] or g
						b = tintTbl[3] or b
						a = tintTbl[4] or a
					end

					if spark.SetVertexColor then
						pcall(spark.SetVertexColor, spark, r, g, b, a)
					end

					-- Visibility: hide the spark via alpha so we do not fight internal Show/Hide logic.
					if sparkHidden then
						if spark.SetAlpha then
							pcall(spark.SetAlpha, spark, 0)
						end
					else
						if spark.SetAlpha then
							local baseAlpha = originalSparkAlpha[spark] or a or 1
							pcall(spark.SetAlpha, spark, baseAlpha)
						end
					end
				end
			end

			-- Custom Cast Bar border (per unit, uses bar border system)
			do
				local enabled = not not cfg.castBarBorderEnable
				local styleKey = cfg.castBarBorderStyle or "square"
				local colorMode = cfg.castBarBorderColorMode or "default"
				local tintTbl = type(cfg.castBarBorderTintColor) == "table" and cfg.castBarBorderTintColor or {1,1,1,1}
				local tintColor = {
					tintTbl[1] or 1,
					tintTbl[2] or 1,
					tintTbl[3] or 1,
					tintTbl[4] or 1,
				}
				local thickness = tonumber(cfg.castBarBorderThickness) or 1
				if thickness < 1 then thickness = 1 elseif thickness > 16 then thickness = 16 end

				-- User-controlled inset plus a small thickness-derived term; we bias the Default (square)
				-- style outward slightly, with per-unit tuning.
				local userInset = tonumber(cfg.castBarBorderInset) or 0
				if userInset < -4 then userInset = -4 elseif userInset > 4 then userInset = 4 end
				local derivedInset = math.floor((thickness - 1) * 0.5)
				local baseInset = 0
				if styleKey == "square" then
					if unit == "Player" then
						-- Player cast bar: slightly outward, then user inset pulls in to an even frame.
						baseInset = -1
					elseif unit == "Target" then
						-- Target cast bar: a bit more outward to start; side/top nudges handled separately.
						baseInset = -2
					elseif unit == "Focus" then
						-- Focus cast bar: start closer in so the default inset=1 look is tighter on all sides.
						baseInset = 0
					else
						baseInset = -2
					end
				end
				local combinedInset = baseInset + userInset + derivedInset

				-- Clear any prior border when disabled
				if not enabled or styleKey == "none" then
					if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(frame) end
					if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(frame) end
				else
					-- Determine effective color from mode + style
					local styleDef = addon.BarBorders and addon.BarBorders.GetStyle and addon.BarBorders.GetStyle(styleKey)
					local color
					if colorMode == "custom" then
						color = tintColor
					elseif colorMode == "texture" then
						color = {1, 1, 1, 1}
					else -- "default"
						if styleDef and styleKey ~= "square" then
							color = {1, 1, 1, 1}
						else
							color = {0, 0, 0, 1}
						end
					end

					local handled = false
					if addon.BarBorders and addon.BarBorders.ApplyToBarFrame then
						if addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(frame) end

						-- Ensure cast bar borders are parented directly to the StatusBar so they
						-- inherit its visibility (hidden when no cast is active).
						frame._ScooterBorderContainerParentRef = nil

						-- Unit-specific per-side pad adjustments for Cast Bar:
						-- Player: symmetric (no extra nudges; baseInset handles feel).
						-- Target: top pulled down slightly, left/right pulled in a bit more, bottom unchanged.
						if enabled and unit == "Target" then
							frame._ScooterBorderPadAdjust = {
								left = -2,
								right = -2,
								top = -1,
								bottom = 0,
							}
						else
							frame._ScooterBorderPadAdjust = nil
						end

						handled = addon.BarBorders.ApplyToBarFrame(frame, styleKey, {
							color = color,
							thickness = thickness,
							levelOffset = 1,
							inset = combinedInset,
						})
					end

					if not handled then
						-- Fallback: pixel (square) border using generic square helper
						if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(frame) end
						if addon.Borders and addon.Borders.ApplySquare then
							local sqColor = (colorMode == "custom") and tintColor or {0, 0, 0, 1}
							local baseY = (thickness <= 1) and 0 or 1
							local baseX = 1
							local expandY = baseY - combinedInset
							local expandX = baseX - combinedInset
							if expandX < -6 then expandX = -6 elseif expandX > 6 then expandX = 6 end
							if expandY < -6 then expandY = -6 elseif expandY > 6 then expandY = 6 end

							-- Per-unit fine-tuning for the pixel fallback:
							-- Player: top/bottom/left are good; pull the right edge in slightly.
							-- Target: top pulled down a bit; left/right pulled in more; bottom remains aligned.
							local exLeft, exRight, exTop, exBottom = expandX, expandX, expandY, expandY
							local name = frame.GetName and frame:GetName()
							if name == "PlayerCastingBarFrame" then
								-- Reduce right-side expansion by 1px (clamped to >= 0)
								exRight = math.max(0, exRight - 1)
							elseif name == "TargetFrameSpellBar" then
								exLeft  = math.max(0, exLeft - 2)
								exRight = math.max(0, exRight - 2)
								exTop   = math.max(0, exTop - 1)
							end

							addon.Borders.ApplySquare(frame, {
								size = thickness,
								color = sqColor,
								layer = "OVERLAY",
								layerSublevel = 3,
								expandLeft = exLeft,
								expandRight = exRight,
								expandTop = exTop,
								expandBottom = exBottom,
							})
						end
					end
				end

				-- Hide Blizzard's stock cast bar border when custom borders are enabled (all units that expose .Border)
				local border = frame.Border
				if border then
					if border.SetShown then
						pcall(border.SetShown, border, not enabled)
					elseif border.SetAlpha then
						pcall(border.SetAlpha, border, enabled and 0 or 1)
					end
				end
			end

			-- Cast Bar Icon border (per unit; reuses icon border system from Cooldown Manager)
			do
				local icon = frame.Icon
				if icon then
					local iconBorderEnabled = not not cfg.iconBorderEnable
					local iconStyle = cfg.iconBorderStyle or "square"
					if iconStyle == "none" then
						iconStyle = "square"
						cfg.iconBorderStyle = iconStyle
					end
					local iconThicknessVal = tonumber(cfg.iconBorderThickness) or 1
					if iconThicknessVal < 1 then iconThicknessVal = 1 elseif iconThicknessVal > 16 then iconThicknessVal = 16 end
					local iconTintEnabled = not not cfg.iconBorderTintEnable
					local tintTbl = type(cfg.iconBorderTintColor) == "table" and cfg.iconBorderTintColor or {1,1,1,1}
					local iconTintColor = {
						tintTbl[1] or 1,
						tintTbl[2] or 1,
						tintTbl[3] or 1,
						tintTbl[4] or 1,
					}

					-- Never draw a border when the icon itself is disabled.
					if iconBorderEnabled and not iconDisabled then
						-- Defensive cleanup: if any legacy Scooter borders were drawn directly on the
						-- icon texture (pre-wrapper versions), hide them once so only the current
						-- wrapper/container-based border remains visible.
						if (icon.ScootAtlasBorder or icon.ScootTextureBorder or icon.ScootSquareBorderContainer or icon.ScootSquareBorderEdges)
							and addon.Borders and addon.Borders.HideAll then
							addon.Borders.HideAll(icon)
						end

						addon.ApplyIconBorderStyle(icon, iconStyle, {
							thickness = iconThicknessVal,
							color = iconTintEnabled and iconTintColor or nil,
							tintEnabled = iconTintEnabled,
							db = cfg,
							thicknessKey = "iconBorderThickness",
							tintColorKey = "iconBorderTintColor",
							defaultThickness = 1,
						})
					else
						-- Clear any existing icon border container when custom border is disabled
						-- or when the icon itself is disabled/hidden.
						if icon.ScooterIconBorderContainer and addon.Borders and addon.Borders.HideAll then
							addon.Borders.HideAll(icon.ScooterIconBorderContainer)
						elseif addon.Borders and addon.Borders.HideAll then
							addon.Borders.HideAll(icon)
						end
					end
				end
			end

			-- Spell Name Text styling (Player/Target/Focus)
			-- Targets: PlayerCastingBarFrame.Text, TargetFrameSpellBar.Text, FocusFrameSpellBar.Text
			-- Borders: PlayerCastingBarFrame.TextBorder, TargetFrameSpellBar.TextBorder, FocusFrameSpellBar.TextBorder
			do
				-- CastingBarFrameBaseTemplate exposes the spell-name FontString as .Text
				local spellFS = frame.Text
				if spellFS then
					-- Capture a stable baseline anchor once per session so offsets are relative.
					-- For the cast bar, we always treat the spell name as centered within the bar,
					-- regardless of whether the bar is locked to the Player frame or free-floating.
					local function ensureSpellBaseline(fs, key)
						addon._ufCastSpellNameBaselines[key] = addon._ufCastSpellNameBaselines[key] or {}
						local b = addon._ufCastSpellNameBaselines[key]
						if b.point == nil then
							-- Force a centered baseline: center of the cast bar frame.
							local parent = (fs and fs.GetParent and fs:GetParent()) or frame
							b.point, b.relTo, b.relPoint, b.x, b.y = "CENTER", parent, "CENTER", 0, 0
						end
						return b
					end

					-- Player has a "Disable Spell Name Text" toggle; Target/Focus do not
					local disabled = (unit == "Player") and (not not cfg.spellNameTextDisabled) or false

					-- Visibility: use alpha instead of Show/Hide to avoid fighting Blizzard logic
					if spellFS.SetAlpha then
						pcall(spellFS.SetAlpha, spellFS, disabled and 0 or 1)
					end

					-- Border/Backdrop behind the spell text
					-- Player: cfg.hideSpellNameBackdrop (TextBorder only visible when unlocked)
					-- Target/Focus: cfg.hideSpellNameBorder (TextBorder is always present)
					local hideBorder = false
					if unit == "Player" then
						hideBorder = not not cfg.hideSpellNameBackdrop
					else
						-- Target/Focus use hideSpellNameBorder
						hideBorder = not not cfg.hideSpellNameBorder
					end
					local border = frame.TextBorder
					if border and border.SetAlpha then
						pcall(border.SetAlpha, border, hideBorder and 0 or 1)
					elseif border and border.Hide and border.Show then
						if hideBorder then
							pcall(border.Hide, border)
						else
							pcall(border.Show, border)
						end
					end

					if not disabled then
						local styleCfg = cfg.spellNameText or {}
						-- Font / size / outline
						local face = addon.ResolveFontFace and addon.ResolveFontFace(styleCfg.fontFace or "FRIZQT__")
							or (select(1, _G.GameFontNormal:GetFont()))
						local size = tonumber(styleCfg.size) or 14
						local outline = tostring(styleCfg.style or "OUTLINE")
						if addon.ApplyFontStyle then
							addon.ApplyFontStyle(spellFS, face, size, outline)
						elseif spellFS.SetFont then
							pcall(spellFS.SetFont, spellFS, face, size, outline)
						end

						-- Color (simple RGBA, no mode for now)
						local c = styleCfg.color or {1, 1, 1, 1}
						if spellFS.SetTextColor then
							pcall(spellFS.SetTextColor, spellFS, c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
						end

						-- Offsets relative to baseline (centered)
						local ox = (styleCfg.offset and tonumber(styleCfg.offset.x)) or 0
						local oy = (styleCfg.offset and tonumber(styleCfg.offset.y)) or 0
						if spellFS.ClearAllPoints and spellFS.SetPoint then
							local b = ensureSpellBaseline(spellFS, unit .. ":spellName")
							spellFS:ClearAllPoints()
							-- Ensure horizontal alignment is centered so long and short strings both
							-- grow outwards from the middle of the bar.
							if spellFS.SetJustifyH then
								pcall(spellFS.SetJustifyH, spellFS, "CENTER")
							end
							spellFS:SetPoint(
								b.point or "CENTER",
								b.relTo or (spellFS.GetParent and spellFS:GetParent()) or frame,
								b.relPoint or b.point or "CENTER",
								(b.x or 0) + ox,
								(b.y or 0) + oy
							)
						end
					end
				end
			end

			-- Cast Time Text styling (Player only; Target/Focus Cast Bars do not have cast time display)
			if unit == "Player" then
				do
					local castTimeFS = frame.CastTimeText
					if castTimeFS then
						-- Capture a stable baseline anchor once per session so offsets are relative
						local function ensureCastTimeBaseline(fs, key)
							addon._ufCastTimeTextBaselines[key] = addon._ufCastTimeTextBaselines[key] or {}
							local b = addon._ufCastTimeTextBaselines[key]
							if b.point == nil then
								if fs and fs.GetPoint then
									local p, relTo, rp, x, y = fs:GetPoint(1)
									b.point = p or "CENTER"
									b.relTo = relTo or (fs.GetParent and fs:GetParent()) or frame
									b.relPoint = rp or b.point
									b.x = tonumber(x) or 0
									b.y = tonumber(y) or 0
								else
									b.point, b.relTo, b.relPoint, b.x, b.y =
										"CENTER", (fs and fs.GetParent and fs:GetParent()) or frame, "CENTER", 0, 0
								end
							end
							return b
						end

						local styleCfg = cfg.castTimeText or {}
						-- Font / size / outline
						local face = addon.ResolveFontFace and addon.ResolveFontFace(styleCfg.fontFace or "FRIZQT__")
							or (select(1, _G.GameFontNormal:GetFont()))
						local size = tonumber(styleCfg.size) or 14
						local outline = tostring(styleCfg.style or "OUTLINE")
						if addon.ApplyFontStyle then
							addon.ApplyFontStyle(castTimeFS, face, size, outline)
						elseif castTimeFS.SetFont then
							pcall(castTimeFS.SetFont, castTimeFS, face, size, outline)
						end

						-- Color (simple RGBA, no mode for now)
						local c = styleCfg.color or {1, 1, 1, 1}
						if castTimeFS.SetTextColor then
							pcall(castTimeFS.SetTextColor, castTimeFS, c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
						end

						-- Offsets relative to baseline
						local ox = (styleCfg.offset and tonumber(styleCfg.offset.x)) or 0
						local oy = (styleCfg.offset and tonumber(styleCfg.offset.y)) or 0
						if castTimeFS.ClearAllPoints and castTimeFS.SetPoint then
							local b = ensureCastTimeBaseline(castTimeFS, "Player:castTime")
							castTimeFS:ClearAllPoints()
							castTimeFS:SetPoint(
								b.point or "CENTER",
								b.relTo or (castTimeFS.GetParent and castTimeFS:GetParent()) or frame,
								b.relPoint or b.point or "CENTER",
								(b.x or 0) + ox,
								(b.y or 0) + oy
							)
						end
					end
				end
			end
		end

		local inCombat = InCombatLockdown and InCombatLockdown()
		-- For normal styling passes triggered by profile changes or /reload, we avoid
		-- touching secure cast bar anchors during combat and defer until combat ends.
		-- For visual-only refreshes triggered from SetStatusBarTexture/Color hooks,
		-- we allow apply() to run in combat so custom textures/colors remain active.
		if inCombat and not frame._ScootCastVisualOnly then
			if _G.C_Timer and _G.C_Timer.After then
				_G.C_Timer.After(0.1, function()
					if not (InCombatLockdown and InCombatLockdown()) then
						apply()
					end
				end)
			end
		else
			apply()
		end
	end

	function addon.ApplyUnitFrameCastBarFor(unit)
		applyCastBarForUnit(unit)
	end

	function addon.ApplyAllUnitFrameCastBars()
		applyCastBarForUnit("Player")
		applyCastBarForUnit("Target")
		applyCastBarForUnit("Focus")
	end
end

