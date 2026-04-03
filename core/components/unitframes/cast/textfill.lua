local addonName, addon = ...
local CB = addon.CastBars
local getProp = CB._getProp
local setProp = CB._setProp
local getState = CB._getState

-- =========================================================================
-- Text-Fill Cast Bar mode helpers
-- =========================================================================

-- Empowered cast tier colors (shared with styling.lua via CB namespace).
-- Brightened to compensate for vertex color multiplication on custom textures.
CB._TIER_COLORS_NORMAL = {
	{ 0.45, 0.95, 0.55 },  -- Tier 1: bright green
	{ 1.00, 0.90, 0.30 },  -- Tier 2: bright yellow
	{ 1.00, 0.55, 0.25 },  -- Tier 3: bright orange
	{ 1.00, 0.30, 0.20 },  -- Tier 4: bright red
}
CB._TIER_COLORS_DISABLED = {
	{ 0.18, 0.40, 0.22 },  -- ~40% of normal
	{ 0.40, 0.36, 0.12 },
	{ 0.40, 0.22, 0.10 },
	{ 0.40, 0.12, 0.08 },
}
local TIER_COLORS_NORMAL = CB._TIER_COLORS_NORMAL
local TIER_COLORS_DISABLED = CB._TIER_COLORS_DISABLED
local MAX_EMPOWERED_TIERS = 5

-- Resolve the fill color from cast bar color settings (mirrors bars/textures.lua logic)
-- frame: the cast bar frame (used to read interruptibility state for default color mode)
local function resolveBarFillColor(cfg, unit, frame)
	local colorMode = cfg.castBarColorMode or "default"
	local tint = cfg.castBarTint
	if colorMode == "custom" and type(tint) == "table" then
		return tint[1] or 1, tint[2] or 1, tint[3] or 1, tint[4] or 1
	elseif colorMode == "class" then
		if addon.GetClassColorRGB then
			local r, g, b = addon.GetClassColorRGB("player")
			return r or 1, g or 1, b or 1, 1
		end
	end
	-- "default": white for non-kickable casts, yellow/gold for kickable
	-- (castNotInterruptible is set by the SetStatusBarTexture hook when Blizzard
	-- switches to the "ui-castingbar-uninterruptable" atlas)
	if frame and getProp(frame, "castNotInterruptible") then
		return 1, 1, 1, 1
	end
	return 1, 0.7, 0, 1
end

-- Lazily create all text-fill visual elements for a cast bar frame
local function ensureTextFillElements(frame)
	local existing = getProp(frame, "textFillElements")
	if existing then return existing end

	-- Unfilled outline elements (behind unfilled content)
	local unfilledLineOL = frame:CreateTexture(nil, "BACKGROUND", nil, 0)
	local unfilledLeftCapOL = frame:CreateTexture(nil, "BACKGROUND", nil, 0)
	local unfilledRightCapOL = frame:CreateTexture(nil, "BACKGROUND", nil, 0)

	-- Unfilled elements (dimmed, on cast bar directly)
	local unfilledLine = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
	local unfilledLeftCap = frame:CreateTexture(nil, "ARTWORK", nil, 1)
	local unfilledRightCap = frame:CreateTexture(nil, "ARTWORK", nil, 1)

	-- Clip frame: children are clipped to its bounds for the progressive fill effect
	local clipFrame = CreateFrame("Frame", nil, frame)
	clipFrame:SetClipsChildren(true)
	-- Frame level auto-inherited from parent (frame) at C++ level,
	-- bypasses Lua secret value restrictions on tainted boss frames

	-- Filled line + outline on the PARENT frame (not clipFrame) so that the line
	-- renders below frame.Text (OVERLAY) within the same frame's layer stack.
	-- Progress tracking uses anchor-based sizing (RIGHT → fill texture) instead of clipping.
	local filledLineOL = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
	local filledLine = frame:CreateTexture(nil, "BACKGROUND", nil, 3)

	-- Filled cap outlines + caps remain in clipFrame for progressive reveal via clipping
	local filledLeftCapOL = clipFrame:CreateTexture(nil, "BACKGROUND", nil, 1)
	local filledRightCapOL = clipFrame:CreateTexture(nil, "BACKGROUND", nil, 1)
	local filledLeftCap = clipFrame:CreateTexture(nil, "ARTWORK", nil, 2)
	local filledRightCap = clipFrame:CreateTexture(nil, "ARTWORK", nil, 2)
	local filledText = clipFrame:CreateFontString(nil, "OVERLAY")
	-- Default font so filledText can render even if GetFont returns secrets
	filledText:SetFont("Fonts\\FRIZQT__.TTF", 12, "")

	-- Spark overlay frame (above clipFrame so spark renders in front of text)
	local sparkFrame = CreateFrame("Frame", nil, frame)
	sparkFrame:SetFrameLevel(clipFrame:GetFrameLevel() + 1)
	sparkFrame:SetAllPoints(frame)
	local sparkTex = sparkFrame:CreateTexture(nil, "OVERLAY", nil, 3)
	sparkTex:Hide()
	sparkFrame:Hide()

	-- Hide initially
	unfilledLineOL:Hide()
	unfilledLeftCapOL:Hide()
	unfilledRightCapOL:Hide()
	unfilledLine:Hide()
	unfilledLeftCap:Hide()
	unfilledRightCap:Hide()
	filledLine:Hide()
	filledLineOL:Hide()
	clipFrame:Hide()

	local elements = {
		unfilledLineOL = unfilledLineOL,
		unfilledLeftCapOL = unfilledLeftCapOL,
		unfilledRightCapOL = unfilledRightCapOL,
		unfilledLine = unfilledLine,
		unfilledLeftCap = unfilledLeftCap,
		unfilledRightCap = unfilledRightCap,
		filledLineOL = filledLineOL,
		filledLeftCapOL = filledLeftCapOL,
		filledRightCapOL = filledRightCapOL,
		clipFrame = clipFrame,
		filledLine = filledLine,
		filledLeftCap = filledLeftCap,
		filledRightCap = filledRightCap,
		filledText = filledText,
		sparkFrame = sparkFrame,
		sparkTex = sparkTex,
	}

	setProp(frame, "textFillElements", elements)
	return elements
end

-- Lazily create empowered text-fill elements (tier-colored line segments + pip dividers).
-- Reuses the existing clipFrame from the base text-fill elements. Created once per frame,
-- reused across empowered casts. Elements are hidden initially.
local function ensureEmpoweredTextFillElements(frame, elements)
	if elements.empowered then return elements.empowered end

	local clipFrame = elements.clipFrame
	local emp = {
		filledSegs = {},
		unfilledSegs = {},
		pipDividers = {},
		numActive = 0,
		active = false,
	}

	for i = 1, MAX_EMPOWERED_TIERS do
		-- Unfilled segments: on bar frame, same sublayer as unfilledLine (BACKGROUND:1)
		emp.unfilledSegs[i] = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
		emp.unfilledSegs[i]:Hide()

		-- Filled segments: in clipFrame, same sublayer as filledLine (BACKGROUND:2)
		emp.filledSegs[i] = clipFrame:CreateTexture(nil, "BACKGROUND", nil, 2)
		emp.filledSegs[i]:Hide()
	end

	-- Pip dividers: on bar frame, above caps (ARTWORK:3) so they're visible on both portions
	for i = 1, MAX_EMPOWERED_TIERS - 1 do
		local pip = frame:CreateTexture(nil, "ARTWORK", nil, 3)
		pip:SetColorTexture(0, 0, 0, 1)
		pip:Hide()
		emp.pipDividers[i] = pip
	end

	elements.empowered = emp
	return emp
end

-- One-time install of Show() hooks on decorative textures that Blizzard actively
-- re-shows during casts (ShowSpark, FinishSpell, StandardFinish OnPlay, etc.).
-- Instead of fighting the animation state machine with Stop(), we let animations
-- play through (so OnFinished callbacks fire) but keep their target textures hidden.
local function installTextFillShowGuards(frame)
	if getProp(frame, "textFillShowGuarded") then return end
	setProp(frame, "textFillShowGuarded", true)

	local guardTextures = {
		frame.Spark,          -- ShowSpark() → self.Spark:Show()
		frame.StandardGlow,   -- ShowSpark() → sparkFx:SetShown(true)
		frame.CraftGlow,      -- ShowSpark() → sparkFx:SetShown(true)
		frame.ChannelShadow,  -- ShowSpark() → sparkFx:SetShown(true)
		frame.Flash,          -- FinishSpell() → self.Flash:Show()
		frame.EnergyGlow,     -- StandardFinish:OnPlay → SetTargetsShown(true)
		frame.Flakes01,       -- StandardFinish:OnPlay → SetTargetsShown(true)
		frame.Flakes02,       -- StandardFinish:OnPlay → SetTargetsShown(true)
		frame.Flakes03,       -- StandardFinish:OnPlay → SetTargetsShown(true)
		-- InterruptGlow intentionally excluded — controlled by hideInterruptGlow toggle independently
	}
	for _, texture in ipairs(guardTextures) do
		if texture and texture.Show then
			hooksecurefunc(texture, "Show", function(self)
				if getProp(frame, "textFillActive") then
					pcall(self.Hide, self)
				end
			end)
		end
	end
end

-- Activate empowered text-fill: replace single-color line with tier-colored segments
-- anchored between Blizzard's StagePip frames. Deferred because AddStages creates
-- StagePips after the cast starts. Uses anchor-based positioning (secret-safe).
local function activateEmpoweredTextFill(frame, elements, cfg, unit)
	local emp = ensureEmpoweredTextFillElements(frame, elements)

	-- Hide single-color line elements (keep outlines visible — they frame the full bar)
	elements.unfilledLine:Hide()
	elements.filledLine:Hide()

	-- Mark empowered mode on frame for the stage updater in styling.lua
	setProp(frame, "textFillEmpowered", true)

	-- Read text-fill settings
	local lineHeight = math.max(1, math.min(10, tonumber(cfg.textFillLineHeight) or 2))
	local capSize = math.max(2, math.min(20, tonumber(cfg.textFillEndCapSize) or 6))

	-- Resolve foreground texture
	local texKey = cfg.castBarTexture or "default"
	local texturePath = addon.Media and addon.Media.ResolveBarTexturePath
		and addon.Media.ResolveBarTexturePath(texKey)

	-- Defer to ensure Blizzard's AddStages has created StagePips
	C_Timer.After(0, function()
		-- Guard: empowered text-fill may have been deactivated before this fires
		if not getProp(frame, "textFillActive") then return end
		if not getProp(frame, "textFillEmpowered") then return end

		-- Read StagePips with secret guard
		local pips = frame.StagePips
		if not pips or (issecretvalue and issecretvalue(pips)) then
			-- Fallback: re-show single-color lines
			elements.unfilledLine:Show()
			elements.filledLine:Show()
			setProp(frame, "textFillEmpowered", nil)
			return
		end
		local numPips = #pips
		if numPips == 0 then
			elements.unfilledLine:Show()
			elements.filledLine:Show()
			setProp(frame, "textFillEmpowered", nil)
			return
		end

		local numSegments = numPips + 1  -- one more segment than pips
		if numSegments > MAX_EMPOWERED_TIERS then numSegments = MAX_EMPOWERED_TIERS end
		emp.numActive = numSegments

		-- Configure and show segments
		for i = 1, numSegments do
			local nColor = TIER_COLORS_NORMAL[i] or TIER_COLORS_NORMAL[#TIER_COLORS_NORMAL]
			local dColor = TIER_COLORS_DISABLED[i] or TIER_COLORS_DISABLED[#TIER_COLORS_DISABLED]

			-- Unfilled segment (on bar frame)
			local uSeg = emp.unfilledSegs[i]
			uSeg:ClearAllPoints()
			uSeg:SetHeight(lineHeight)
			if i == 1 then
				uSeg:SetPoint("LEFT", frame, "LEFT", 0, 0)
			else
				uSeg:SetPoint("LEFT", pips[i - 1], "CENTER", 0, 0)
			end
			if i <= numPips then
				uSeg:SetPoint("RIGHT", pips[i], "CENTER", 0, 0)
			else
				uSeg:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
			end
			uSeg:SetColorTexture(dColor[1], dColor[2], dColor[3], 1)
			uSeg:Show()

			-- Filled segment (in clipFrame, anchored to bar frame — clipped by clip bounds)
			local fSeg = emp.filledSegs[i]
			fSeg:ClearAllPoints()
			fSeg:SetHeight(lineHeight)
			if i == 1 then
				fSeg:SetPoint("LEFT", frame, "LEFT", 0, 0)
			else
				fSeg:SetPoint("LEFT", pips[i - 1], "CENTER", 0, 0)
			end
			if i <= numPips then
				fSeg:SetPoint("RIGHT", pips[i], "CENTER", 0, 0)
			else
				fSeg:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
			end
			if texturePath then
				fSeg:SetTexture(texturePath)
				fSeg:SetVertexColor(nColor[1], nColor[2], nColor[3], 1)
			else
				fSeg:SetColorTexture(nColor[1], nColor[2], nColor[3], 1)
			end
			fSeg:Show()
		end

		-- Hide unused segments
		for i = numSegments + 1, MAX_EMPOWERED_TIERS do
			emp.unfilledSegs[i]:Hide()
			emp.filledSegs[i]:Hide()
		end

		-- Configure and show pip dividers at stage boundaries
		for i = 1, math.min(numPips, MAX_EMPOWERED_TIERS - 1) do
			local div = emp.pipDividers[i]
			div:ClearAllPoints()
			div:SetSize(1, capSize)
			div:SetPoint("CENTER", pips[i], "CENTER", 0, 0)
			div:Show()
		end
		for i = numPips + 1, MAX_EMPOWERED_TIERS - 1 do
			emp.pipDividers[i]:Hide()
		end

		-- Color end caps to match tier colors
		local firstD = TIER_COLORS_DISABLED[1]
		local firstN = TIER_COLORS_NORMAL[1]
		local lastD = TIER_COLORS_DISABLED[numSegments] or TIER_COLORS_DISABLED[#TIER_COLORS_DISABLED]
		local lastN = TIER_COLORS_NORMAL[numSegments] or TIER_COLORS_NORMAL[#TIER_COLORS_NORMAL]

		-- Unfilled caps: disabled tier colors
		elements.unfilledLeftCap:SetColorTexture(firstD[1], firstD[2], firstD[3], 1)
		elements.unfilledRightCap:SetColorTexture(lastD[1], lastD[2], lastD[3], 1)

		-- Filled caps: bright tier colors (with texture support)
		if texturePath then
			elements.filledLeftCap:SetTexture(texturePath)
			elements.filledLeftCap:SetVertexColor(firstN[1], firstN[2], firstN[3], 1)
			elements.filledRightCap:SetTexture(texturePath)
			elements.filledRightCap:SetVertexColor(lastN[1], lastN[2], lastN[3], 1)
		else
			elements.filledLeftCap:SetColorTexture(firstN[1], firstN[2], firstN[3], 1)
			elements.filledRightCap:SetColorTexture(lastN[1], lastN[2], lastN[3], 1)
		end

		-- Set filled text color to tier 1 (green) — stage updater will advance this
		elements.filledText:SetTextColor(firstN[1], firstN[2], firstN[3], 1)

		-- Hide Blizzard StageTier visuals (keep frames for potential reference)
		local tiers = frame.StageTiers
		if tiers and not (issecretvalue and issecretvalue(tiers)) then
			for _, tier in ipairs(tiers) do
				if tier and not (tier.IsForbidden and tier:IsForbidden()) then
					if tier.Normal then pcall(tier.Normal.SetAlpha, tier.Normal, 0) end
					if tier.Disabled then pcall(tier.Disabled.SetAlpha, tier.Disabled, 0) end
					if tier.Glow then pcall(tier.Glow.SetAlpha, tier.Glow, 0) end
				end
			end

			-- One-time Play() hooks on StageTier animation groups.
			-- FinishAnim plays on cast completion (PlayFinishAnim), forces Glow alpha
			-- to 1 via C++ animation, bypassing our SetAlpha(0). No OnFinished — safe to Stop().
			-- FlashAnim has setToFinalAlpha="true", no OnFinished — safe to Stop().
			if not getProp(frame, "textFillStageTierAnimsHooked") then
				setProp(frame, "textFillStageTierAnimsHooked", true)
				for _, tier in ipairs(tiers) do
					if tier and not (tier.IsForbidden and tier:IsForbidden()) then
						local animGroups = { tier.FinishAnim, tier.FlashAnim }
						for _, ag in ipairs(animGroups) do
							if ag and ag.Play and ag.Stop then
								local agRef, stopFn = ag, ag.Stop
								hooksecurefunc(ag, "Play", function()
									if getProp(frame, "textFillActive") then
										pcall(stopFn, agRef)
									end
								end)
							end
						end
					end
				end
			end

			-- One-time Show() guards on StageTier textures (Normal, Disabled, Glow).
			-- UpdateStage() calls Normal:SetShown(true) on completed tiers — guard
			-- re-hides them immediately when text-fill mode is active.
			if not getProp(frame, "textFillStageTierShowGuarded") then
				setProp(frame, "textFillStageTierShowGuarded", true)
				for _, tier in ipairs(tiers) do
					if tier and not (tier.IsForbidden and tier:IsForbidden()) then
						local tierTextures = { tier.Normal, tier.Disabled, tier.Glow }
						for _, tex in ipairs(tierTextures) do
							if tex and tex.Show then
								hooksecurefunc(tex, "Show", function(self)
									if getProp(frame, "textFillActive") then
										pcall(self.Hide, self)
									end
								end)
							end
						end
					end
				end
			end
		end

		-- Hide Blizzard StagePip visuals (keep frames positioned for anchoring)
		for _, pip in ipairs(pips) do
			if pip and not (pip.IsForbidden and pip:IsForbidden()) then
				if pip.BasePip then pcall(pip.BasePip.SetAlpha, pip.BasePip, 0) end
				if pip.PipFlare then pcall(pip.PipFlare.SetAlpha, pip.PipFlare, 0) end
			end
		end

		emp.active = true
	end)
end

-- Deactivate empowered text-fill: hide tier segments, optionally restore Blizzard alphas.
-- restoreBlizzardAlphas: when true (full teardown via hideTextFillElements), restores
-- StageTier/StagePip alphas to 1 for non-text-fill use. When false/nil (empowered cast
-- ending via EMPOWER_STOP), alphas stay at 0 to prevent a visual flash during the cast
-- bar's fade-out animation. Blizzard's AddStages resets everything for the next cast.
local function deactivateEmpoweredTextFill(frame, elements, restoreBlizzardAlphas)
	local emp = elements and elements.empowered
	if not emp then return end

	-- Hide all empowered segments and pip dividers
	for i = 1, MAX_EMPOWERED_TIERS do
		if emp.unfilledSegs[i] then emp.unfilledSegs[i]:Hide() end
		if emp.filledSegs[i] then emp.filledSegs[i]:Hide() end
	end
	for i = 1, MAX_EMPOWERED_TIERS - 1 do
		if emp.pipDividers[i] then emp.pipDividers[i]:Hide() end
	end

	emp.numActive = 0
	emp.active = false

	-- Clear empowered flag
	setProp(frame, "textFillEmpowered", nil)

	if restoreBlizzardAlphas then
		-- Restore Blizzard StageTier alphas (full teardown only)
		local tiers = frame.StageTiers
		if tiers and not (issecretvalue and issecretvalue(tiers)) then
			for _, tier in ipairs(tiers) do
				if tier and not (tier.IsForbidden and tier:IsForbidden()) then
					if tier.Normal then pcall(tier.Normal.SetAlpha, tier.Normal, 1) end
					if tier.Disabled then pcall(tier.Disabled.SetAlpha, tier.Disabled, 1) end
					if tier.Glow then pcall(tier.Glow.SetAlpha, tier.Glow, 1) end
				end
			end
		end

		-- Restore Blizzard StagePip alphas
		local pips = frame.StagePips
		if pips and not (issecretvalue and issecretvalue(pips)) then
			for _, pip in ipairs(pips) do
				if pip and not (pip.IsForbidden and pip:IsForbidden()) then
					if pip.BasePip then pcall(pip.BasePip.SetAlpha, pip.BasePip, 1) end
					if pip.PipFlare then pcall(pip.PipFlare.SetAlpha, pip.PipFlare, 1) end
				end
			end
		end
	end
end

-- Apply text-fill mode visuals to a cast bar frame.
-- empowered: boolean — when true, replaces single-color line with tier-colored segments.
local function applyTextFillMode(frame, cfg, unit, empowered)
	local elements = ensureTextFillElements(frame)

	-- Resolve fill color from cast bar color settings
	local r, g, b, a = resolveBarFillColor(cfg, unit, frame)

	-- Resolve foreground texture (user's selected bar texture)
	local texKey = cfg.castBarTexture or "default"
	local texturePath = addon.Media and addon.Media.ResolveBarTexturePath
		and addon.Media.ResolveBarTexturePath(texKey)

	-- Read text-fill settings
	local lineHeight = math.max(1, math.min(10, tonumber(cfg.textFillLineHeight) or 2))
	local capSize = math.max(2, math.min(20, tonumber(cfg.textFillEndCapSize) or 6))

	-- Hide StatusBar fill texture (bar continues functioning for spark positioning)
	local fillTex = frame:GetStatusBarTexture()
	if fillTex and fillTex.SetAlpha then
		pcall(fillTex.SetAlpha, fillTex, 0)
	end

	-- Hide custom background (ScootBG)
	local scootBG = getProp(frame, "ScootBG")
	if scootBG and scootBG.SetAlpha then
		pcall(scootBG.SetAlpha, scootBG, 0)
	end
	-- Hide Blizzard stock background
	if frame.Background and frame.Background.SetAlpha then
		pcall(frame.Background.SetAlpha, frame.Background, 0)
	end

	-- InterruptGlow is NOT hidden in text-fill mode — controlled by hideInterruptGlow toggle independently

	-- Hide Blizzard bar border in text-fill mode
	local border = frame.Border
	if border and border.SetAlpha then
		pcall(border.SetAlpha, border, 0)
	end

	-- Hide all decorative chrome textures (animations play invisibly, callbacks still fire)
	local chromeTextures = {
		frame.Spark, frame.Flash,
		frame.StandardGlow, frame.CraftGlow, frame.ChannelShadow,
		frame.EnergyGlow, frame.Flakes01, frame.Flakes02, frame.Flakes03,
		frame.BaseGlow, frame.WispGlow, frame.Sparkles01, frame.Sparkles02,
		frame.Shine, frame.ChargeFlash, frame.ChargeGlow,
	}
	for _, tex in ipairs(chromeTextures) do
		if tex and tex.Hide then pcall(tex.Hide, tex) end
	end

	-- Flag for Show() guards and shake hook to check
	setProp(frame, "textFillActive", true)

	-- Install one-time Show() hooks so Blizzard can't re-show hidden chrome textures
	installTextFillShowGuards(frame)

	-- One-time hook on InterruptShakeAnim only (frame shake has no critical callbacks
	-- and would visually shake text-fill elements; other animations play through
	-- harmlessly since their target textures are hidden via Show() guards)
	if not getProp(frame, "textFillShakeHooked") then
		setProp(frame, "textFillShakeHooked", true)
		local ag = frame.InterruptShakeAnim
		if ag and ag.Play and ag.Stop then
			local stopFn = ag.Stop
			local agRef = ag
			hooksecurefunc(ag, "Play", function()
				if getProp(frame, "textFillActive") then
					pcall(stopFn, agRef)
				end
			end)
		end
	end

	-- One-time hooks on animation groups whose setToFinalAlpha="true" overrides
	-- our SetAlpha(0) at the C++ level during playback.  Stop them immediately.
	-- FlashAnim: no OnFinished callbacks in XML — safe.
	-- StandardFinish: OnFinished calls SetTargetsShown(false), which hides targets — desired.
	-- InterruptGlowAnim: excluded — handled by hideInterruptGlow Play() hook instead.
	if not getProp(frame, "textFillAnimsHooked") then
		setProp(frame, "textFillAnimsHooked", true)
		local animGroups = { frame.FlashAnim, frame.StandardFinish }
		for _, ag in ipairs(animGroups) do
			if ag and ag.Play and ag.Stop then
				local agRef, stopFn = ag, ag.Stop
				hooksecurefunc(ag, "Play", function()
					if getProp(frame, "textFillActive") then
						pcall(stopFn, agRef)
					end
				end)
			end
		end
	end

	-- Hide our custom spark overlay when Blizzard calls HideSpark (cast complete / interrupt)
	-- Also lock clipFrame to full width so filledText stays visible above unfilled elements
	-- during the FadeOutAnim (prevents collapse when fill texture atlas changes in FinishSpell)
	if not getProp(frame, "textFillHideSparkHooked") then
		setProp(frame, "textFillHideSparkHooked", true)
		hooksecurefunc(frame, "HideSpark", function(self)
			if getProp(self, "textFillActive") then
				local els = getProp(self, "textFillElements")
				if els then
					if els.sparkTex then els.sparkTex:Hide() end
					if els.sparkFrame then els.sparkFrame:Hide() end
					-- Lock clipFrame to full width for clean fade-out
					if els.clipFrame and els.clipFrame:IsShown() then
						els.clipFrame:ClearAllPoints()
						local textOverflow = 20
						els.clipFrame:SetPoint("TOPLEFT", self, "TOPLEFT", 0, textOverflow)
						els.clipFrame:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, -textOverflow)
					end
					-- Lock filledLine to full bar width (no longer clipped by clipFrame)
					if els.filledLine then
						els.filledLine:ClearAllPoints()
						els.filledLine:SetPoint("LEFT", self, "LEFT", 0, 0)
						els.filledLine:SetPoint("RIGHT", self, "RIGHT", 0, 0)
						els.filledLine:SetHeight(els.lineHeight or 2)
					end
				end
				-- Re-hide fill texture: FinishSpell calls SetStatusBarTexture(full)
				-- before HideSpark, replacing it with a new texture at alpha 1.
				-- The SetStatusBarTexture hook early-returns during empowered casts,
				-- so the new fill texture is never re-hidden by the normal pipeline.
				local ft = self:GetStatusBarTexture()
				if ft and ft.SetAlpha then
					pcall(ft.SetAlpha, ft, 0)
				end
			end
		end)
	end

	-- Re-show our custom spark when Blizzard starts a new cast (ShowSpark)
	if not getProp(frame, "textFillShowSparkHooked") then
		setProp(frame, "textFillShowSparkHooked", true)
		hooksecurefunc(frame, "ShowSpark", function(self)
			if getProp(self, "textFillActive") then
				local els = getProp(self, "textFillElements")
				if els then
					if els.sparkTex then pcall(els.sparkTex.Show, els.sparkTex) end
					if els.sparkFrame then pcall(els.sparkFrame.Show, els.sparkFrame) end
				end
			end
		end)
	end

	-- End cap dimensions (tick style: narrow width, full height)
	local capW = math.max(2, capSize * 0.3)
	local capH = capSize

	-- Gray color for unfilled elements (solid, no opacity reduction)
	local grayR, grayG, grayB = 0.5, 0.5, 0.5

	-- Unfilled line: full width, centered vertically
	local el = elements.unfilledLine
	el:ClearAllPoints()
	el:SetPoint("LEFT", frame, "LEFT", 0, 0)
	el:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
	el:SetHeight(lineHeight)
	el:SetColorTexture(grayR, grayG, grayB, 1)
	el:Show()

	-- Unfilled line outline (1px expansion around content)
	el = elements.unfilledLineOL
	el:ClearAllPoints()
	el:SetPoint("TOPLEFT", elements.unfilledLine, "TOPLEFT", -1, 1)
	el:SetPoint("BOTTOMRIGHT", elements.unfilledLine, "BOTTOMRIGHT", 1, -1)
	el:SetColorTexture(0, 0, 0, 1)
	el:Show()

	-- Unfilled left cap
	el = elements.unfilledLeftCap
	el:ClearAllPoints()
	el:SetPoint("LEFT", frame, "LEFT", 0, 0)
	el:SetSize(capW, capH)
	el:SetColorTexture(grayR, grayG, grayB, 1)
	el:Show()

	-- Unfilled left cap outline
	el = elements.unfilledLeftCapOL
	el:ClearAllPoints()
	el:SetPoint("TOPLEFT", elements.unfilledLeftCap, "TOPLEFT", -1, 1)
	el:SetPoint("BOTTOMRIGHT", elements.unfilledLeftCap, "BOTTOMRIGHT", 1, -1)
	el:SetColorTexture(0, 0, 0, 1)
	el:Show()

	-- Unfilled right cap
	el = elements.unfilledRightCap
	el:ClearAllPoints()
	el:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
	el:SetSize(capW, capH)
	el:SetColorTexture(grayR, grayG, grayB, 1)
	el:Show()

	-- Unfilled right cap outline
	el = elements.unfilledRightCapOL
	el:ClearAllPoints()
	el:SetPoint("TOPLEFT", elements.unfilledRightCap, "TOPLEFT", -1, 1)
	el:SetPoint("BOTTOMRIGHT", elements.unfilledRightCap, "BOTTOMRIGHT", 1, -1)
	el:SetColorTexture(0, 0, 0, 1)
	el:Show()

	-- Clip frame: LEFT-anchored, RIGHT edge tracks fill texture (secret-safe in 12.0)
	local clipFrame = elements.clipFrame

	-- clipFrame auto-inherits level from parent (frame) — no explicit set needed.
	-- Only refresh sparkFrame relative to clipFrame (safe to read, it's our frame).
	if elements.sparkFrame then
		elements.sparkFrame:SetFrameLevel(clipFrame:GetFrameLevel() + 1)
	end
	clipFrame:ClearAllPoints()
	-- Anchor vertically to bar frame with overflow for text taller than bar.
	-- Uses anchor-based height (secret-safe) instead of SetHeight(GetHeight()).
	local textOverflow = 20
	clipFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, textOverflow)
	if fillTex then
		clipFrame:SetPoint("BOTTOMRIGHT", fillTex, "BOTTOMRIGHT", 0, -textOverflow)
	else
		clipFrame:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, -textOverflow)
		clipFrame:SetWidth(0.1)
	end
	clipFrame:Show()

	-- Filled line (on parent frame, RIGHT anchored to fill texture for progress tracking)
	el = elements.filledLine
	el:ClearAllPoints()
	el:SetPoint("LEFT", frame, "LEFT", 0, 0)
	if fillTex then
		el:SetPoint("RIGHT", fillTex, "RIGHT", 0, 0)
	else
		el:SetPoint("RIGHT", frame, "LEFT", 0, 0)  -- zero width fallback
	end
	el:SetHeight(lineHeight)
	if texturePath then
		el:SetTexture(texturePath)
		el:SetVertexColor(r, g, b, a)
	else
		el:SetColorTexture(r, g, b, a)
	end
	el:Show()

	-- Filled line outline (auto-follows filledLine via anchors)
	el = elements.filledLineOL
	el:ClearAllPoints()
	el:SetPoint("TOPLEFT", elements.filledLine, "TOPLEFT", -1, 1)
	el:SetPoint("BOTTOMRIGHT", elements.filledLine, "BOTTOMRIGHT", 1, -1)
	el:SetColorTexture(0, 0, 0, 1)
	el:Show()

	-- Filled left cap
	el = elements.filledLeftCap
	el:ClearAllPoints()
	el:SetPoint("LEFT", frame, "LEFT", 0, 0)
	el:SetSize(capW, capH)
	if texturePath then
		el:SetTexture(texturePath)
		el:SetVertexColor(r, g, b, a)
	else
		el:SetColorTexture(r, g, b, a)
	end
	el:Show()

	-- Filled left cap outline
	el = elements.filledLeftCapOL
	el:ClearAllPoints()
	el:SetPoint("TOPLEFT", elements.filledLeftCap, "TOPLEFT", -1, 1)
	el:SetPoint("BOTTOMRIGHT", elements.filledLeftCap, "BOTTOMRIGHT", 1, -1)
	el:SetColorTexture(0, 0, 0, 1)
	el:Show()

	-- Filled right cap
	el = elements.filledRightCap
	el:ClearAllPoints()
	el:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
	el:SetSize(capW, capH)
	if texturePath then
		el:SetTexture(texturePath)
		el:SetVertexColor(r, g, b, a)
	else
		el:SetColorTexture(r, g, b, a)
	end
	el:Show()

	-- Filled right cap outline
	el = elements.filledRightCapOL
	el:ClearAllPoints()
	el:SetPoint("TOPLEFT", elements.filledRightCap, "TOPLEFT", -1, 1)
	el:SetPoint("BOTTOMRIGHT", elements.filledRightCap, "BOTTOMRIGHT", 1, -1)
	el:SetColorTexture(0, 0, 0, 1)
	el:Show()

	-- Filled text color: use spell name font color (not bar fill color).
	-- Bar fill color (r, g, b, a) continues to drive line and cap textures only.
	-- During empowered casts, skip — activateEmpoweredTextFill sets tier colors instead.
	if not empowered then
		local sc = (cfg.spellNameText or {}).color or {1, 1, 1, 1}
		elements.filledText:SetTextColor(sc[1] or 1, sc[2] or 1, sc[3] or 1, sc[4] or 1)
	end
	elements.filledText:Show()

	-- Custom spark overlay for text-fill mode
	do
		local spark = frame.Spark
		local sparkTex = elements.sparkTex
		local sparkFrame = elements.sparkFrame
		if spark and sparkTex and sparkFrame then
			-- Always use the standard yellow pip atlas (avoids stale red atlas after interrupts)
			sparkTex:SetAtlas("ui-castingbar-pip")

			-- Read spark settings (same keys the normal spark block uses)
			local sparkHidden = cfg.castBarSparkHidden == true
			-- isEmpoweredCast not available here; styling.lua handles empowered override before calling
			-- text-fill, so we trust the passed-in cfg state

			if sparkHidden then
				sparkTex:Hide()
				sparkFrame:Hide()
			else
				-- Spark color
				local sparkColorMode = cfg.castBarSparkColorMode or "default"
				local sparkTint = type(cfg.castBarSparkTint) == "table" and cfg.castBarSparkTint
				if sparkColorMode == "custom" and sparkTint then
					sparkTex:SetVertexColor(sparkTint[1] or 1, sparkTint[2] or 1,
						sparkTint[3] or 1, sparkTint[4] or 1)
				else
					sparkTex:SetVertexColor(1, 1, 1, 1)
				end

				-- Initial position anchored to fill texture edge (secret-safe)
				local ok_sw, raw_sw = pcall(spark.GetWidth, spark)
				local sparkW = (ok_sw and type(raw_sw) == "number") and raw_sw or 8
				sparkTex:SetSize(sparkW, lineHeight)
				sparkTex:ClearAllPoints()
				if fillTex then
					sparkTex:SetPoint("CENTER", fillTex, "RIGHT", 0, 0)
				else
					sparkTex:SetPoint("CENTER", frame, "LEFT", 0, 0)
				end
				sparkTex:Show()
				sparkFrame:Show()
			end

			-- Store dimensions for SetValue hook
			elements.lineHeight = lineHeight
			local ok_sw2, raw_sw2 = pcall(spark.GetWidth, spark)
		elements.sparkWidth = (ok_sw2 and type(raw_sw2) == "number") and raw_sw2 or 8
		end
	end

	-- Install SetValue hook once for dynamic spark height
	-- (clip frame width auto-tracks via anchor to fill texture — no arithmetic needed)
	if not getProp(frame, "textFillSetValueHooked") then
		setProp(frame, "textFillSetValueHooked", true)
		hooksecurefunc(frame, "SetValue", function(self, value)
			pcall(function()
				local els = getProp(self, "textFillElements")
				if not els or not els.clipFrame:IsShown() then return end
				-- Dynamic spark height only (clip frame + spark position auto-track via anchors)
				local sparkTex = els.sparkTex
				if sparkTex and els.sparkFrame and els.sparkFrame:IsShown() then
					local ft = self:GetStatusBarTexture()
					local ok_fw, raw_fw = pcall(ft.GetWidth, ft)
					local sparkX = (ok_fw and type(raw_fw) == "number"
						and not (issecretvalue and issecretvalue(raw_fw))) and raw_fw or nil
					local h = els.lineHeight or 2
					local tl = els.textLeftEdge
					local tr = els.textRightEdge
					if sparkX and tl and tr then
						if sparkX >= tl and sparkX <= tr then
							h = els.effectiveTextHeight or h
						end
					elseif els.effectiveTextHeight then
						h = els.effectiveTextHeight
					end
					sparkTex:SetHeight(h)
				end
			end)
		end)
	end

	-- Install SetText hook once for text content sync
	local spellFS = frame.Text
	if spellFS and not getProp(frame, "textFillSetTextHooked") then
		setProp(frame, "textFillSetTextHooked", true)
		hooksecurefunc(spellFS, "SetText", function(self, text)
			if CB._rampApplying then return end  -- Skip during gradient re-application
			pcall(function()
				-- Always store captured text for syncTextFillText fallback
				-- (GetText may return secrets on tainted target/boss frames)
				if type(text) == "string" then
					setProp(frame, "textFillCapturedText", text)
				end
				local els = getProp(frame, "textFillElements")
				if els and els.filledText and els.clipFrame:IsShown() then
					els.filledText:SetText(text or "")
				end
			end)
		end)
	end

	-- Empowered cast: replace single-color line with tier-colored segments
	if empowered then
		activateEmpoweredTextFill(frame, elements, cfg, unit)
	elseif elements.empowered and elements.empowered.active then
		-- Was empowered, now not — deactivate empowered elements
		deactivateEmpoweredTextFill(frame, elements)
		-- Re-show single-color lines (hidden by activateEmpoweredTextFill)
		elements.unfilledLine:Show()
		elements.filledLine:Show()
	end
end

-- Hide text-fill elements (when switching back to default mode)
local function hideTextFillElements(frame)
	local elements = getProp(frame, "textFillElements")
	if not elements then return end

	-- Deactivate empowered text-fill if active (full teardown: restore Blizzard alphas)
	if elements.empowered and elements.empowered.active then
		deactivateEmpoweredTextFill(frame, elements, true)
	end

	elements.unfilledLineOL:Hide()
	elements.unfilledLeftCapOL:Hide()
	elements.unfilledRightCapOL:Hide()
	elements.unfilledLine:Hide()
	elements.unfilledLeftCap:Hide()
	elements.unfilledRightCap:Hide()
	-- filledLine/filledLineOL are on the parent frame (not clipFrame), hide explicitly
	elements.filledLine:Hide()
	elements.filledLineOL:Hide()
	elements.clipFrame:Hide()
	if elements.sparkFrame then elements.sparkFrame:Hide() end
	if elements.sparkTex then elements.sparkTex:Hide() end
	-- Clear stored dimensions
	elements.lineHeight = nil
	elements.effectiveTextHeight = nil
	elements.textLeftEdge = nil
	elements.textRightEdge = nil
	-- Restore fill texture alpha
	local fillTex = frame:GetStatusBarTexture()
	if fillTex and fillTex.SetAlpha then
		pcall(fillTex.SetAlpha, fillTex, 1)
	end
	-- Restore backgrounds (normal pipeline will re-apply correct opacity)
	if frame.Background and frame.Background.SetAlpha then
		pcall(frame.Background.SetAlpha, frame.Background, 1)
	end
	-- Restore InterruptGlow (default alpha is 0, animations will show it when needed)
	local interruptGlow = frame.InterruptGlow
	if interruptGlow and interruptGlow.SetAlpha then
		pcall(interruptGlow.SetAlpha, interruptGlow, 0)  -- restore to default (hidden until animated)
	end
	-- Restore Blizzard bar border
	local border = frame.Border
	if border and border.SetAlpha then
		pcall(border.SetAlpha, border, 1)
	end
	-- Restore original text visibility (spell name styling block will re-apply on next cycle)
	if frame.Text and frame.Text.SetAlpha then
		pcall(frame.Text.SetAlpha, frame.Text, 1)
	end
	-- Clear text-fill flag so Show() guards and shake hook become inactive
	setProp(frame, "textFillActive", nil)

	-- Re-show Spark if mid-cast (ShowSpark won't be called again for current cast)
	if (frame.casting or frame.channeling) and frame.Spark then
		pcall(frame.Spark.Show, frame.Spark)
	end
end

-- Sync filled text to match original spell name (called after spell name styling in apply())
local function syncTextFillText(frame, cfg)
	local elements = getProp(frame, "textFillElements")
	if not elements or not elements.filledText then return end
	local spellFS = frame.Text
	if not spellFS then return end

	-- Copy font properties from styled original text (guard against secrets on tainted frames)
	local ok_gf, face, size, flags = pcall(spellFS.GetFont, spellFS)
	if not ok_gf then face = nil end
	if face and (issecretvalue and issecretvalue(face)) then face = nil end
	if size and (issecretvalue and issecretvalue(size)) then size = nil end
	if flags and (issecretvalue and issecretvalue(flags)) then flags = nil end
	if face then pcall(elements.filledText.SetFont, elements.filledText, face, size or 12, flags) end
	-- Copy shadow properties so filled text has identical visual bounds
	do
		local ok_sc, sr, sg, sb, sa = pcall(spellFS.GetShadowColor, spellFS)
		if ok_sc and type(sr) == "number" and not (issecretvalue and issecretvalue(sr)) then
			pcall(elements.filledText.SetShadowColor, elements.filledText, sr, sg, sb, sa or 1)
		end
		local ok_so, sx, sy = pcall(spellFS.GetShadowOffset, spellFS)
		if ok_so and type(sx) == "number" and not (issecretvalue and issecretvalue(sx)) then
			pcall(elements.filledText.SetShadowOffset, elements.filledText, sx, sy)
		end
	end
	-- Copy text content — use cached raw text to avoid copying gradient |cff codes
	local rawText = getProp(spellFS, "_rampRawText")
	if not rawText then
		local ok_rt, rt = pcall(spellFS.GetText, spellFS)
		if ok_rt and type(rt) == "string" and not issecretvalue(rt) then
			rawText = rt
		end
	end
	-- Fallback to hook-captured text when GetText returns secrets (tainted target/boss frames)
	if not rawText or rawText == "" then
		rawText = getProp(frame, "textFillCapturedText") or ""
	end
	-- Store unfilled text color on frame state for gradient hook access
	setProp(frame, "textFillUnfilledColor", cfg.textFillUnfilledTextColor or {0.5, 0.5, 0.5})
	-- During empowered text-fill, skip gradient coloring — stage updater manages filled text color.
	-- Use plain text so SetTextColor from the stage updater is the sole color source.
	local isEmpoweredTF = elements.empowered and elements.empowered.active
	local styleCfg_tf = cfg.spellNameText or {}
	local colorMode_tf = styleCfg_tf.colorMode or "default"
	if not isEmpoweredTF and (colorMode_tf == "classGradient" or colorMode_tf == "specGradient" or colorMode_tf == "customGradient") and addon.BuildColorRampString then
		local r1, g1, b1, r2, g2, b2 = CB._resolveGradientColors(colorMode_tf, styleCfg_tf)
		elements.filledText:SetText(addon.BuildColorRampString(rawText, r1, g1, b1, r2, g2, b2))
		-- Apply matching per-character codes to frame.Text so both strings have identical
		-- |cff escape code structure, ensuring consistent truncation rendering (pitfall #25)
		local uc = cfg.textFillUnfilledTextColor or {0.5, 0.5, 0.5}
		CB._rampApplying = true
		pcall(spellFS.SetText, spellFS, addon.BuildColorRampString(rawText, uc[1], uc[2], uc[3], uc[1], uc[2], uc[3]))
		CB._rampApplying = false
	else
		elements.filledText:SetText(rawText)
		-- Ensure frame.Text has raw text (no inline |cff codes) so unfilled color works
		if rawText and getProp(spellFS, "_rampRawText") then
			local ok_gt, currentText = pcall(spellFS.GetText, spellFS)
			if ok_gt and type(currentText) == "string" and not issecretvalue(currentText) and currentText:find("|cff") then
				CB._rampApplying = true
				pcall(spellFS.SetText, spellFS, rawText)
				CB._rampApplying = false
			end
		end
	end
	-- Match alignment
	if elements.filledText.SetJustifyH then elements.filledText:SetJustifyH("CENTER") end
	-- Position to match original text (read from config, not from current anchor)
	elements.filledText:ClearAllPoints()
	local styleCfg = cfg.spellNameText or {}
	local ox = (styleCfg.offset and tonumber(styleCfg.offset.x)) or 0
	local oy = (styleCfg.offset and tonumber(styleCfg.offset.y)) or 0
	elements.filledText:SetPoint("CENTER", frame, "CENTER", ox, oy)
	-- Expand clip frame height to contain text taller than the bar
	local clipFrame = elements.clipFrame
	if clipFrame then
		local ok_th, raw_th = pcall(elements.filledText.GetStringHeight, elements.filledText)
		local textH = (ok_th and type(raw_th) == "number") and raw_th or nil
		if (not textH or textH <= 0) and size then
			textH = size * 1.15
		end
		elements.effectiveTextHeight = textH
	end
	-- Constrain to bar width so both texts truncate identically (prevents clip-frame edge clipping)
	local ok_bw, raw_bw = pcall(frame.GetWidth, frame)
	local bw = (ok_bw and type(raw_bw) == "number" and not (issecretvalue and issecretvalue(raw_bw))) and raw_bw or 0
	if bw > 0 then
		elements.filledText:SetWidth(bw)
		elements.filledText:SetWordWrap(false)
		-- Match original text width so it truncates at the same point
		if spellFS.SetWidth then
			pcall(spellFS.SetWidth, spellFS, bw)
			if spellFS.SetWordWrap then pcall(spellFS.SetWordWrap, spellFS, false) end
		end
	end
	-- Store text horizontal bounds for spark height calculation
	local ok_sw, raw_sw = pcall(elements.filledText.GetStringWidth, elements.filledText)
	local sw = (ok_sw and type(raw_sw) == "number") and raw_sw or 0
	if sw > 0 then
		-- Cap to bar width (text is truncated by SetWidth above)
		if bw > 0 and sw > bw then sw = bw end
		local cx = (bw > 0 and bw or 0) / 2 + ox
		elements.textLeftEdge = cx - sw / 2
		elements.textRightEdge = cx + sw / 2
	end
	-- Visibility follows spell name hidden state
	if cfg.castBarSpellNameHidden then
		elements.filledText:Hide()
	else
		elements.filledText:Show()
	end
	-- frame.Text stays visible as the unfilled text — spell name styling block manages its alpha
	-- Override frame.Text color to the unfilled text color setting.
	-- Runs AFTER spell name styling has set frame.Text color, so this takes precedence.
	if spellFS and spellFS.SetTextColor then
		local uc = cfg.textFillUnfilledTextColor or {0.5, 0.5, 0.5, 1}
		pcall(spellFS.SetTextColor, spellFS, uc[1] or 0.5, uc[2] or 0.5, uc[3] or 0.5, uc[4] or 1)
	end
end

-- Export text-fill helpers to namespace for styling.lua and boss.lua
CB._applyTextFillMode = applyTextFillMode
CB._hideTextFillElements = hideTextFillElements
CB._syncTextFillText = syncTextFillText
CB._deactivateEmpoweredTextFill = deactivateEmpoweredTextFill
