local addonName, addon = ...
local Util = addon.ComponentsUtil
local ClampOpacity = Util.ClampOpacity

-- Reference to FrameState module for safe property storage (avoids writing to Blizzard frames)
local FS = nil
local function ensureFS()
    if not FS then FS = addon.FrameState end
    return FS
end

local function getState(frame)
    local fs = ensureFS()
    return fs and fs.Get(frame) or nil
end

local function getProp(frame, key)
    local st = getState(frame)
    return st and st[key] or nil
end

local function setProp(frame, key, value)
    local st = getState(frame)
    if st then
        st[key] = value
    end
end

local function getIconBorderContainer(frame)
    local st = getState(frame)
    return st and st.ScootIconBorderContainer or nil
end

-- =========================================================================
-- Gradient text helpers (spell name color ramp)
-- =========================================================================

local SPELL_LIGHTEN_RATIO = 0.45

local function resolveGradientColors(colorMode, styleCfg)
    local r1, g1, b1
    if colorMode == "classGradient" and addon.GetClassColorRGB then
        r1, g1, b1 = addon.GetClassColorRGB("player")
        r1, g1, b1 = r1 or 1, g1 or 1, b1 or 1
        -- Curated per-class endpoints with darkened start for richer gradients
        local _, classToken = UnitClass("player")
        local endpoints = classToken and addon.CLASS_GRADIENT_ENDPOINTS and addon.CLASS_GRADIENT_ENDPOINTS[classToken]
        if endpoints then
            local dr, dg, db = addon.DarkenColor(r1, g1, b1, 0.25)
            local er, eg, eb = addon.LightenColor(endpoints[1], endpoints[2], endpoints[3], 0.10)
            return dr, dg, db, er, eg, eb
        end
        -- Fallback: generic lighten formula
        local r2, g2, b2 = addon.LightenColor(r1, g1, b1, SPELL_LIGHTEN_RATIO)
        return r1, g1, b1, r2, g2, b2
    end
    if colorMode == "specGradient" then
        local specIndex = GetSpecialization and GetSpecialization()
        local specID = specIndex and GetSpecializationInfo and select(1, GetSpecializationInfo(specIndex))
        local specData = specID and addon.SPEC_GRADIENT_COLORS and addon.SPEC_GRADIENT_COLORS[specID]
        if specData then
            local dr, dg, db = addon.DarkenColor(specData.base[1], specData.base[2], specData.base[3], 0.25)
            local er, eg, eb = addon.LightenColor(specData.endpoint[1], specData.endpoint[2], specData.endpoint[3], 0.10)
            return dr, dg, db, er, eg, eb
        end
        -- Fallback: use class gradient if spec not found
        if addon.GetClassColorRGB then
            r1, g1, b1 = addon.GetClassColorRGB("player")
            r1, g1, b1 = r1 or 1, g1 or 1, b1 or 1
            local r2, g2, b2 = addon.LightenColor(r1, g1, b1, SPELL_LIGHTEN_RATIO)
            return r1, g1, b1, r2, g2, b2
        end
    end
    if colorMode == "customGradient" then
        local c = styleCfg.color or {1, 1, 1, 1}
        r1, g1, b1 = c[1] or 1, c[2] or 1, c[3] or 1
    end
    r1, g1, b1 = r1 or 1, g1 or 1, b1 or 1
    local r2, g2, b2 = addon.LightenColor(r1, g1, b1, SPELL_LIGHTEN_RATIO)
    return r1, g1, b1, r2, g2, b2
end

-- File-level guard for re-entrant SetText during gradient application
local _rampApplying = false

-- Install a SetText hook on a spell name FontString for live gradient updates.
-- cfgResolver: function() returning the spellNameText sub-table (or nil).
-- parentFrame: the cast bar frame (for text-fill mode awareness).
local function installGradientHook(spellFS, cfgResolver, parentFrame)
    if not spellFS or getProp(spellFS, "_rampHooked") then return end
    hooksecurefunc(spellFS, "SetText", function(self, text)
        if _rampApplying then return end
        if type(text) ~= "string" then return end
        -- Cache the raw (uncolored) text for re-application on settings change
        setProp(self, "_rampRawText", text)
        local styleCfg = cfgResolver()
        if not styleCfg then return end
        local mode = styleCfg.colorMode
        if mode ~= "classGradient" and mode ~= "specGradient" and mode ~= "customGradient" then return end
        if not addon.BuildColorRampString then return end
        local r1, g1, b1, r2, g2, b2 = resolveGradientColors(mode, styleCfg)
        -- Text-fill mode: apply gradient to filledText only, leave frame.Text as raw text
        if parentFrame and getProp(parentFrame, "textFillActive") then
            local els = getProp(parentFrame, "textFillElements")
            if els and els.filledText then
                pcall(els.filledText.SetText, els.filledText, addon.BuildColorRampString(text, r1, g1, b1, r2, g2, b2))
            end
            return  -- Do NOT modify frame.Text with gradient codes
        end
        -- Normal mode: apply gradient to frame.Text
        _rampApplying = true
        pcall(self.SetText, self, addon.BuildColorRampString(text, r1, g1, b1, r2, g2, b2))
        _rampApplying = false
    end)
    setProp(spellFS, "_rampHooked", true)
end

-- Apply spell name color based on colorMode setting.
-- Handles: default, class, custom, classGradient, customGradient.
-- parentFrame: the cast bar frame (for text-fill mode awareness).
local function applySpellNameColor(spellFS, styleCfg, parentFrame)
    if not spellFS then return end
    local colorMode = styleCfg.colorMode or "default"
    local isTextFill = parentFrame and getProp(parentFrame, "textFillActive")

    if colorMode == "classGradient" or colorMode == "specGradient" or colorMode == "customGradient" then
        local cachedText = getProp(spellFS, "_rampRawText")
        if cachedText and addon.BuildColorRampString then
            local r1, g1, b1, r2, g2, b2 = resolveGradientColors(colorMode, styleCfg)
            local rampText = addon.BuildColorRampString(cachedText, r1, g1, b1, r2, g2, b2)
            if isTextFill then
                -- Text-fill: gradient goes to filledText; frame.Text stays raw
                local els = getProp(parentFrame, "textFillElements")
                if els and els.filledText then
                    pcall(els.filledText.SetText, els.filledText, rampText)
                end
                -- Ensure frame.Text has raw text (no |cff codes)
                _rampApplying = true
                pcall(spellFS.SetText, spellFS, cachedText)
                _rampApplying = false
                -- SetTextColor on frame.Text will be handled by syncTextFillText's
                -- unfilled text color override — don't set it here
            else
                -- Normal mode: gradient on frame.Text, white base color
                if spellFS.SetTextColor then
                    pcall(spellFS.SetTextColor, spellFS, 1, 1, 1, 1)
                end
                _rampApplying = true
                pcall(spellFS.SetText, spellFS, rampText)
                _rampApplying = false
            end
        end
    elseif colorMode == "class" then
        local cr, cg, cb
        if addon.GetClassColorRGB then
            cr, cg, cb = addon.GetClassColorRGB("player")
        end
        cr, cg, cb = cr or 1, cg or 1, cb or 1
        if spellFS.SetTextColor then
            pcall(spellFS.SetTextColor, spellFS, cr, cg, cb, 1)
        end
    elseif colorMode == "custom" then
        local c = styleCfg.color or {1, 1, 1, 1}
        if spellFS.SetTextColor then
            pcall(spellFS.SetTextColor, spellFS, c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
        end
    else -- "default"
        if spellFS.SetTextColor then
            pcall(spellFS.SetTextColor, spellFS, 1, 1, 1, 1)
        end
    end

    -- When switching FROM gradient to non-gradient, restore plain text
    if colorMode ~= "classGradient" and colorMode ~= "specGradient" and colorMode ~= "customGradient" then
        local cachedText = getProp(spellFS, "_rampRawText")
        if cachedText and spellFS.GetText then
            local ok, current = pcall(spellFS.GetText, spellFS)
            if ok and type(current) == "string" and not issecretvalue(current) and current:find("|cff") then
                _rampApplying = true
                pcall(spellFS.SetText, spellFS, cachedText)
                _rampApplying = false
            end
        end
    end
end

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

	-- Resolve Health Bar for Target/Focus (via deterministic paths)
	local function resolveHealthBar(unit)
		if unit == "Target" then
			local root = _G.TargetFrame
			return getNested(root, "TargetFrameContent", "TargetFrameContentMain", "HealthBarsContainer", "HealthBar")
		elseif unit == "Focus" then
			local root = _G.FocusFrame
			return getNested(root, "TargetFrameContent", "TargetFrameContentMain", "HealthBarsContainer", "HealthBar")
		end
	end

	-- Resolve Power Bar (ManaBar) for Target/Focus (via deterministic paths)
	local function resolvePowerBar(unit)
		if unit == "Target" then
			local root = _G.TargetFrame
			return getNested(root, "TargetFrameContent", "TargetFrameContentMain", "ManaBar")
		elseif unit == "Focus" then
			local root = _G.FocusFrame
			return getNested(root, "TargetFrameContent", "TargetFrameContentMain", "ManaBar")
		end
	end

	-- Resolve Name FontString for Target/Focus (anchor target for "Above Name")
	local function resolveNameFS(unit)
		if unit == "Target" then
			return getNested(_G.TargetFrame, "TargetFrameContent", "TargetFrameContentMain", "Name")
		elseif unit == "Focus" then
			return getNested(_G.FocusFrame, "TargetFrameContent", "TargetFrameContentMain", "Name")
		end
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

	-- Track units that were reanchored during combat and need a full re-apply after combat ends
	local pendingPostCombatRefresh = {}

	-- Empowered cast state per unit token ("player"/"target"/"focus")
	-- Set via events only — never reads Blizzard frame properties (no taint risk)
	local empoweredCastActive = {}

	local function isEmpoweredCast(unit)
		local token = (unit == "Player" and "player")
				  or (unit == "Target" and "target")
				  or (unit == "Focus" and "focus")
		return token and empoweredCastActive[token] or false
	end

	-- Lightweight reanchor: only corrects position (ClearAllPoints + SetPoint) without
	-- going through the full apply pipeline or its combat guard.  Target/Focus cast bars
	-- are visual StatusBars — repositioning them is safe during combat (no taint).
	local function reanchorCastBar(frame, unit)
		if unit ~= "Target" and unit ~= "Focus" then return end

		local db = addon and addon.db and addon.db.profile
		if not db then return end
		local cfg = db.unitFrames and db.unitFrames[unit] and db.unitFrames[unit].castBar
		if not cfg then return end

		local anchorMode = cfg.anchorMode or "default"
		-- Backward-compat: migrate old healthTop → nameTop
		if anchorMode == "healthTop" then
			anchorMode = "nameTop"
			cfg.anchorMode = "nameTop"
		end
		if anchorMode == "default" then return end

		local anchorBar, anchorEdge
		if anchorMode == "nameTop" then
			anchorBar = resolveNameFS(unit)
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

		if not anchorBar then return end

		local offsetX = tonumber(cfg.offsetX) or 0
		local offsetY = tonumber(cfg.offsetY) or 0
		local castBarPoint = (anchorEdge == "top") and "BOTTOM" or "TOP"
		local anchorPoint = (anchorEdge == "top") and "TOP" or "BOTTOM"

		setProp(frame, "ignoreSetPoint", true)
		frame:ClearAllPoints()
		frame:SetPoint(castBarPoint, anchorBar, anchorPoint, offsetX, offsetY)
		setProp(frame, "ignoreSetPoint", nil)

		-- Mark for full re-apply when combat ends
		pendingPostCombatRefresh[unit] = true
	end

	-- =========================================================================
	-- Text-Fill Cast Bar mode helpers
	-- =========================================================================

	-- Resolve the fill color from cast bar color settings (mirrors bars/textures.lua logic)
	local function resolveBarFillColor(cfg, unit)
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
		-- "default" / "textureOriginal": Blizzard's default gold cast bar color
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

		-- Filled outline elements (children of clipFrame, behind filled content)
		local filledLineOL = clipFrame:CreateTexture(nil, "BACKGROUND", nil, 1)
		local filledLeftCapOL = clipFrame:CreateTexture(nil, "BACKGROUND", nil, 1)
		local filledRightCapOL = clipFrame:CreateTexture(nil, "BACKGROUND", nil, 1)

		-- Filled elements (children of clip frame, anchored to cast bar for positioning)
		local filledLine = clipFrame:CreateTexture(nil, "BACKGROUND", nil, 2)
		local filledLeftCap = clipFrame:CreateTexture(nil, "ARTWORK", nil, 2)
		local filledRightCap = clipFrame:CreateTexture(nil, "ARTWORK", nil, 2)
		local filledText = clipFrame:CreateFontString(nil, "OVERLAY")

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

	-- Apply text-fill mode visuals to a cast bar frame
	local function applyTextFillMode(frame, cfg, unit)
		local elements = ensureTextFillElements(frame)

		-- Resolve fill color from cast bar color settings
		local r, g, b, a = resolveBarFillColor(cfg, unit)

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
		if not getProp(frame, "textFillHideSparkHooked") then
			setProp(frame, "textFillHideSparkHooked", true)
			hooksecurefunc(frame, "HideSpark", function(self)
				if getProp(self, "textFillActive") then
					local els = getProp(self, "textFillElements")
					if els then
						if els.sparkTex then els.sparkTex:Hide() end
						if els.sparkFrame then els.sparkFrame:Hide() end
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

		-- Filled line (anchored to cast bar, clipped by clip frame)
		el = elements.filledLine
		el:ClearAllPoints()
		el:SetPoint("LEFT", frame, "LEFT", 0, 0)
		el:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
		el:SetHeight(lineHeight)
		if texturePath then
			el:SetTexture(texturePath)
			el:SetVertexColor(r, g, b, a)
		else
			el:SetColorTexture(r, g, b, a)
		end
		el:Show()

		-- Filled line outline
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
		do
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
				if isEmpoweredCast(unit) then sparkHidden = false end

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
				pcall(function()
					local els = getProp(frame, "textFillElements")
					if els and els.filledText and els.clipFrame:IsShown() then
						els.filledText:SetText(text or "")
					end
				end)
			end)
		end
	end

	-- Hide text-fill elements (when switching back to default mode)
	local function hideTextFillElements(frame)
		local elements = getProp(frame, "textFillElements")
		if not elements then return end
		elements.unfilledLineOL:Hide()
		elements.unfilledLeftCapOL:Hide()
		elements.unfilledRightCapOL:Hide()
		elements.unfilledLine:Hide()
		elements.unfilledLeftCap:Hide()
		elements.unfilledRightCap:Hide()
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

		-- Copy font properties from styled original text
		local ok_gf, face, size, flags = pcall(spellFS.GetFont, spellFS)
		if not ok_gf then face = nil end
		if face then pcall(elements.filledText.SetFont, elements.filledText, face, size, flags) end
		-- Copy shadow properties so filled text has identical visual bounds
		do
			local ok_sc, sr, sg, sb, sa = pcall(spellFS.GetShadowColor, spellFS)
			if ok_sc and sr then
				pcall(elements.filledText.SetShadowColor, elements.filledText, sr, sg, sb, sa or 1)
			end
			local ok_so, sx, sy = pcall(spellFS.GetShadowOffset, spellFS)
			if ok_so and sx then
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
		rawText = rawText or ""
		local styleCfg_tf = cfg.spellNameText or {}
		local colorMode_tf = styleCfg_tf.colorMode or "default"
		if (colorMode_tf == "classGradient" or colorMode_tf == "specGradient" or colorMode_tf == "customGradient") and addon.BuildColorRampString then
			local r1, g1, b1, r2, g2, b2 = resolveGradientColors(colorMode_tf, styleCfg_tf)
			elements.filledText:SetText(addon.BuildColorRampString(rawText, r1, g1, b1, r2, g2, b2))
		else
			elements.filledText:SetText(rawText)
		end
		-- Ensure frame.Text has raw text (no inline |cff codes) so unfilled color works
		if rawText and getProp(spellFS, "_rampRawText") then
			local ok_gt, currentText = pcall(spellFS.GetText, spellFS)
			if ok_gt and type(currentText) == "string" and not issecretvalue(currentText) and currentText:find("|cff") then
				_rampApplying = true
				pcall(spellFS.SetText, spellFS, rawText)
				_rampApplying = false
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

	-- Export text-fill helpers for Boss cast bar section (separate do-block scope)
	addon._applyTextFillMode = applyTextFillMode
	addon._hideTextFillElements = hideTextFillElements
	addon._syncTextFillText = syncTextFillText

	-- Flush deferred full re-applies after combat ends
	function addon.FlushPendingCastBarRefresh()
		for unit in pairs(pendingPostCombatRefresh) do
			if addon.ApplyUnitFrameCastBarFor then
				addon.ApplyUnitFrameCastBarFor(unit)
			end
		end
		pendingPostCombatRefresh = {}
	end

	local function applyCastBarForUnit(unit)
		if unit ~= "Player" and unit ~= "Target" and unit ~= "Focus" then return end

		local db = addon and addon.db and addon.db.profile
		if not db then return end

		local unitFrames = rawget(db, "unitFrames")
		local unitCfg = unitFrames and rawget(unitFrames, unit) or nil
		if not unitCfg then return end
		local cfg = rawget(unitCfg, "castBar")
		if not cfg then return end
		-- Zero-Touch: skip empty tables (browsed settings but nothing configured)
		local hasConfig = false
		for k, v in pairs(cfg) do
			if v ~= nil then hasConfig = true; break end
		end
		if not hasConfig then return end

		local frame = resolveCastBarFrame(unit)
		if not frame then return end

		local isPlayer = (unit == "Player")

		-- For the Player cast bar, read the current Edit Mode "Lock to Player Frame" setting so
		-- only overrides position when the bar is locked underneath the Player frame. When the
		-- bar is unlocked and freely positioned in Edit Mode, Scoot should not fight that.
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
		if not getProp(frame, "castHooksInstalled") and _G.hooksecurefunc then
			setProp(frame, "castHooksInstalled", true)
			local hookUnit = unit
			_G.hooksecurefunc(frame, "SetStatusBarTexture", function(self, ...)
				-- Ignore Scoot's own internal texture writes
				if getProp(self, "ufInternalTextureWrite") then return end
				-- Don't re-apply foreground during empowered casts (tiers provide visuals)
				local token = (hookUnit == "Player" and "player") or (hookUnit == "Target" and "target") or (hookUnit == "Focus" and "focus")
				if token and empoweredCastActive[token] then return end
				if addon and addon.ApplyUnitFrameCastBarFor then
					-- Mark this as a visual-only refresh to safely reapply
					-- textures/colors in combat without re-anchoring secure frames.
					setProp(self, "castVisualOnly", true)
					addon.ApplyUnitFrameCastBarFor(hookUnit)
					setProp(self, "castVisualOnly", nil)
				end
			end)
			_G.hooksecurefunc(frame, "SetStatusBarColor", function(self, ...)
				-- Don't re-apply color during empowered casts (stage tiers provide visuals)
				local token = (hookUnit == "Player" and "player") or (hookUnit == "Target" and "target") or (hookUnit == "Focus" and "focus")
				if token and empoweredCastActive[token] then return end
				if addon and addon.ApplyUnitFrameCastBarFor then
					setProp(self, "castVisualOnly", true)
					addon.ApplyUnitFrameCastBarFor(hookUnit)
					setProp(self, "castVisualOnly", nil)
				end
			end)
			-- Hook SetPoint to detect when Blizzard re-anchors the cast bar and re-apply
			-- custom anchoring if there is a non-default anchor mode active.
			_G.hooksecurefunc(frame, "SetPoint", function(self, ...)
				-- Ignore Scoot's SetPoint calls (flagged to prevent infinite loops)
				if getProp(self, "ignoreSetPoint") then return end
				-- Only re-apply if a custom anchor exists mode active for this unit
				local mode = activeAnchorModes[hookUnit]
				if mode and mode ~= "default" then
					if InCombatLockdown and InCombatLockdown() then
						-- Lightweight reanchor during combat (position only, no full pipeline)
						reanchorCastBar(self, hookUnit)
					else
						-- Out of combat: schedule full re-apply on next frame
						if not pendingReapply[hookUnit] then
							pendingReapply[hookUnit] = true
							C_Timer.After(0, function()
								pendingReapply[hookUnit] = nil
								if addon and addon.ApplyUnitFrameCastBarFor then
									addon.ApplyUnitFrameCastBarFor(hookUnit)
								end
							end)
						end
					end
				end
			end)

			-- Hook AdjustPosition (Target/Focus only) to immediately reapply custom anchoring
			-- after Blizzard repositions the cast bar (aura updates, ToT changes, etc.).
			-- Causes the flicker - called from UpdateAuras()
			-- on every UNIT_AURA event, which happens frequently during combat.
			if (hookUnit == "Target" or hookUnit == "Focus") and frame.AdjustPosition then
				_G.hooksecurefunc(frame, "AdjustPosition", function(self)
					local mode = activeAnchorModes[hookUnit]
					if mode and mode ~= "default" then
						if InCombatLockdown and InCombatLockdown() then
							-- Lightweight reanchor during combat (position only)
							reanchorCastBar(self, hookUnit)
						else
							if addon and addon.ApplyUnitFrameCastBarFor then
								addon.ApplyUnitFrameCastBarFor(hookUnit)
							end
						end
					end
				end)
			end
		end

		-- Capture baseline anchor:
		-- - Player: capture a baseline that represents the Edit Mode "under Player" layout,
		--   but avoid rebasing while Scoot offsets are non-zero to avoid compounding
		--   offsets on every apply. This keeps slider behaviour linear.
		-- - Target/Focus: capture once so offsets remain relative to stock layout.
		if frame.GetPoint then
			local point, relativeTo, relativePoint, xOfs, yOfs = frame:GetPoint(1)
			if point then
				if isPlayer then
					local hasOffsets =
						(tonumber(cfg.offsetX) or 0) ~= 0 or
						(tonumber(cfg.offsetY) or 0) ~= 0
					-- When offsets are zero and the bar is locked to the Player frame,
					-- treats the current layout as the new baseline. Otherwise, keeps the
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
		--   owns the free position and Scoot must not re-anchor.
		local offsetX, offsetY = 0, 0
		if unit == "Target" or unit == "Focus" then
			offsetX = tonumber(cfg.offsetX) or 0
			offsetY = tonumber(cfg.offsetY) or 0
		elseif isPlayer and isLockedToPlayerFrame then
			offsetX = tonumber(cfg.offsetX) or 0
			offsetY = tonumber(cfg.offsetY) or 0
		end

		-- Anchor Mode (Target/Focus only): determines anchor point for cast bar positioning
		-- "default" = stock Blizzard position, "nameTop/healthBottom/powerTop/powerBottom" = custom anchors
		local anchorMode = (unit == "Target" or unit == "Focus") and (cfg.anchorMode or "default") or "default"
		-- Backward-compat: migrate old healthTop → nameTop
		if anchorMode == "healthTop" then
			anchorMode = "nameTop"
			if cfg then cfg.anchorMode = "nameTop" end
		end

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
			-- When this is invoked from a SetStatusBarTexture/SetStatusBarColor hook
			-- during combat, treat this as a "visual-only" refresh: apply textures/colors
			-- but avoid re-anchoring secure frames or changing layout, which can taint.
			local inCombat = InCombatLockdown and InCombatLockdown()
			local visualOnly = inCombat and getProp(frame, "castVisualOnly")

			-- Layout (position/size/icon) is skipped for in-combat visual-only refreshes.
			if not visualOnly then
				if frame.ClearAllPoints and frame.SetPoint then
					-- Apply width scaling relative to original width (Player only)
					if isPlayer and origWidth and frame.SetWidth then
						local scale = widthPct / 100.0
						pcall(frame.SetWidth, frame, origWidth * scale)
					end

					-- Anchor behaviour:
					-- - Player: only override anchors when locked to the Player frame so Edit Mode retains
					--   full control when the bar is unlocked and freely positioned.
					-- - Target/Focus: anchor based on anchorMode setting (default = stock baseline, or custom anchor to Health/Power bar).
					if isPlayer then
						if isLockedToPlayerFrame then
							setProp(frame, "ignoreSetPoint", true)
							frame:ClearAllPoints()
							frame:SetPoint(
								orig.point,
								orig.relativeTo,
								orig.relativePoint,
								(orig.xOfs or 0) + offsetX,
								(orig.yOfs or 0) + offsetY
							)
							setProp(frame, "ignoreSetPoint", nil)
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
							if anchorMode == "nameTop" then
								anchorBar = resolveNameFS(unit)
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

								-- Flag to prevent the SetPoint hook from triggering a re-apply loop
								setProp(frame, "ignoreSetPoint", true)
								frame:ClearAllPoints()
								frame:SetPoint(
									castBarPoint,
									anchorBar,
									anchorPoint,
									offsetX,
									offsetY
								)
								setProp(frame, "ignoreSetPoint", nil)
								anchorApplied = true
							end
						end

						-- Fallback to default (stock baseline) positioning if custom anchor not applied
						if not anchorApplied then
							setProp(frame, "ignoreSetPoint", true)
							frame:ClearAllPoints()
							frame:SetPoint(
								orig.point,
								orig.relativeTo,
								orig.relativePoint,
								(orig.xOfs or 0) + offsetX,
								(orig.yOfs or 0) + offsetY
							)
							setProp(frame, "ignoreSetPoint", nil)
						end
					end

					-- Apply icon visibility, size, and padding before bar styling
					local icon = frame.Icon
					if icon then
						-- Visibility: when disabled, hide the icon via alpha and clear any
						-- container-based borders so only the bar remains.
						if iconDisabled then
							if icon.SetAlpha then pcall(icon.SetAlpha, icon, 0) end
							local container = getIconBorderContainer(icon)
							if container and addon.Borders and addon.Borders.HideAll then
								addon.Borders.HideAll(container)
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

				-- Player Cast Bar: ChargeFlash / Shine / WispGlow visibility
				-- These are additive-blend effect textures that flash/glow at various cast moments.
				-- Use SetAlpha to avoid fighting Blizzard's animation-driven show/hide logic.
				if isPlayer then
					local chargeFlash = frame.ChargeFlash
					if chargeFlash and cfg.hideChargeFlash then
						if chargeFlash.SetAlpha then
							pcall(chargeFlash.SetAlpha, chargeFlash, 0)
						end
					end
					local shine = frame.Shine
					if shine and cfg.hideCastShine then
						if shine.SetAlpha then
							pcall(shine.SetAlpha, shine, 0)
						end
					end
					local wispGlow = frame.WispGlow
					if wispGlow and cfg.hideWispGlow then
						if wispGlow.SetAlpha then
							pcall(wispGlow.SetAlpha, wispGlow, 0)
						end
					end
					local standardGlow = frame.StandardGlow
					if standardGlow then
						local hide = not not cfg.hideStandardGlow
						if standardGlow.SetAlpha then
							pcall(standardGlow.SetAlpha, standardGlow, hide and 0 or 1)
						end
					end
					local craftGlow = frame.CraftGlow
					if craftGlow then
						local hide = not not cfg.hideStandardGlow
						if craftGlow.SetAlpha then
							pcall(craftGlow.SetAlpha, craftGlow, hide and 0 or 1)
						end
					end
					local sparkles01 = frame.Sparkles01
					if sparkles01 and cfg.hideChannelSparkles then
						if sparkles01.SetAlpha then
							pcall(sparkles01.SetAlpha, sparkles01, 0)
						end
					end
					local sparkles02 = frame.Sparkles02
					if sparkles02 and cfg.hideChannelSparkles then
						if sparkles02.SetAlpha then
							pcall(sparkles02.SetAlpha, sparkles02, 0)
						end
					end
					local baseGlow = frame.BaseGlow
					if baseGlow and cfg.hideBaseGlow then
						if baseGlow.SetAlpha then
							pcall(baseGlow.SetAlpha, baseGlow, 0)
						end
					end

					-- hideCastFlash: Flash (completion glow)
					if cfg.hideCastFlash then
						local flash = frame.Flash
						if flash and flash.SetAlpha then pcall(flash.SetAlpha, flash, 0) end
					end
					-- hideInterruptGlow: InterruptGlow (interrupt glow)
					if cfg.hideInterruptGlow then
						local intGlow = frame.InterruptGlow
						if intGlow and intGlow.SetAlpha then pcall(intGlow.SetAlpha, intGlow, 0) end
					end

					-- hideCompletionFlare: EnergyGlow + Flakes01-03 (upward animation on standard completion)
					if cfg.hideCompletionFlare then
						for _, tex in ipairs({ frame.EnergyGlow, frame.Flakes01, frame.Flakes02, frame.Flakes03 }) do
							if tex and tex.SetAlpha then pcall(tex.SetAlpha, tex, 0) end
						end
					end
				end

				-- One-time Play() hooks for default-mode cast flash / completion flare toggles.
				-- Reads live DB config per Play() so toggling takes effect immediately.
				-- textFillActive check prevents double-stopping with the text-fill hooks.
				if isPlayer and not getProp(frame, "castFlashAnimHooked") then
					setProp(frame, "castFlashAnimHooked", true)
					local hookUnit = unit
					local function getCastCfg()
						local db = addon and addon.db and addon.db.profile
						return db and db.unitFrames and db.unitFrames[hookUnit] and db.unitFrames[hookUnit].castBar
					end
					-- FlashAnim → hideCastFlash
					local flashAnim = frame.FlashAnim
					if flashAnim and flashAnim.Play and flashAnim.Stop then
						local agRef, stopFn = flashAnim, flashAnim.Stop
						hooksecurefunc(flashAnim, "Play", function()
							if not getProp(frame, "textFillActive") then
								local c = getCastCfg()
								if c and c.hideCastFlash then pcall(stopFn, agRef) end
							end
						end)
					end
					-- InterruptGlowAnim → hideInterruptGlow (works in both default and text-fill modes)
					local intGlowAnim = frame.InterruptGlowAnim
					if intGlowAnim and intGlowAnim.Play and intGlowAnim.Stop then
						local agRef, stopFn = intGlowAnim, intGlowAnim.Stop
						hooksecurefunc(intGlowAnim, "Play", function()
							local c = getCastCfg()
							if c and c.hideInterruptGlow then pcall(stopFn, agRef) end
						end)
					end
					-- StandardFinish → hideCompletionFlare
					local sf = frame.StandardFinish
					if sf and sf.Play and sf.Stop then
						local agRef, stopFn = sf, sf.Stop
						hooksecurefunc(sf, "Play", function()
							if not getProp(frame, "textFillActive") then
								local c = getCastCfg()
								if c and c.hideCompletionFlare then pcall(stopFn, agRef) end
							end
						end)
					end
				end
			end

			-- Text-Fill Cast Bar mode
			local castBarMode = cfg.castBarMode or "default"
			-- Empowered casts fall back to default (stage tiers incompatible with text-fill)
			if isEmpoweredCast(unit) then castBarMode = "default" end

			if castBarMode == "textFill" then
				pcall(applyTextFillMode, frame, cfg, unit)
			else
				hideTextFillElements(frame)
			end

			-- Apply foreground and background styling via shared bar helpers
			-- When visualOnly is true (combat + hook path from SetStatusBarTexture/SetStatusBarColor),
			-- texture/color is allowed so custom styling persists through Blizzard's updates.
			-- Layout changes are already skipped above when visualOnly is true.
			if castBarMode ~= "textFill" and (not inCombat or visualOnly) and (addon._ApplyToStatusBar or addon._ApplyBackgroundToStatusBar) then
				local db = addon and addon.db and addon.db.profile
				local _uf = db and rawget(db, "unitFrames") or nil
				local _uc = _uf and rawget(_uf, unit) or nil
				local cfgStyle = _uc and rawget(_uc, "castBar") or nil

				-- Foreground: texture + color
				-- Skip during empowered casts: Blizzard uses transparent fill with
				-- stage tiers at BACKGROUND sublevel 4-5. Custom texture hides them.
				if cfgStyle and not isEmpoweredCast(unit) and addon._ApplyToStatusBar and frame.GetStatusBarTexture then
					local texKey = cfgStyle.castBarTexture or "default"
					local colorMode = cfgStyle.castBarColorMode or "default"
					local tint = cfgStyle.castBarTint
					-- For class color, follow Health/Power bars and always use player's class
					local unitId = (unit == "Player" and "player") or (unit == "Target" and "target") or (unit == "Focus" and "focus") or (unit == "Pet" and "pet") or "player"
					-- Pass combatSafe=true only for visual-only refreshes triggered by cast bar hooks.
					-- Allows texture/color re-application in combat while layout operations remain skipped.
					addon._ApplyToStatusBar(frame, texKey, colorMode, tint, "player", "cast", unitId, visualOnly)
				end

				-- Background: texture + color + opacity
				-- Skip during empowered casts: the BG swap helpers handle hiding ScootBG
				-- and restoring stock Background so stage tiers render correctly.
				if cfgStyle and not isEmpoweredCast(unit) and addon._ApplyBackgroundToStatusBar then
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
					-- Empowered charge cursor is essential UX feedback — force-show during empowered casts
					if isEmpoweredCast(unit) then sparkHidden = false end
					local colorMode = cfg.castBarSparkColorMode or "default"
					local tintTbl = type(cfg.castBarSparkTint) == "table" and cfg.castBarSparkTint or {1,1,1,1}

					-- Determine effective color from mode:
					-- - "default": use the stock vertex color captured above.
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

					-- Visibility: hide the spark via alpha to avoid fighting internal Show/Hide logic.
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
			if castBarMode == "textFill" then
				if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(frame) end
				if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(frame) end
				if frame.Border and frame.Border.SetShown then pcall(frame.Border.SetShown, frame.Border, false) end
			else
			do
				local enabled = not not cfg.castBarBorderEnable
				local styleKey = cfg.castBarBorderStyle or "square"
				local hiddenEdges = cfg.castBarBorderHiddenEdges
				local tintEnabled = not not cfg.castBarBorderTintEnable
				local tintTbl = type(cfg.castBarBorderTintColor) == "table" and cfg.castBarBorderTintColor or {1,1,1,1}
				local tintColor = {
					tintTbl[1] or 1,
					tintTbl[2] or 1,
					tintTbl[3] or 1,
					tintTbl[4] or 1,
				}
				local thickness = tonumber(cfg.castBarBorderThickness) or 1
				if thickness < 1 then thickness = 1 elseif thickness > 16 then thickness = 16 end

				-- User-controlled inset plus a small thickness-derived term; biases the Default (square)
				-- style outward slightly, with per-unit tuning.
				local userInsetH = tonumber(cfg.castBarBorderInsetH) or tonumber(cfg.castBarBorderInset) or 0
				local userInsetV = tonumber(cfg.castBarBorderInsetV) or tonumber(cfg.castBarBorderInset) or 0
				if userInsetH < -4 then userInsetH = -4 elseif userInsetH > 4 then userInsetH = 4 end
				if userInsetV < -4 then userInsetV = -4 elseif userInsetV > 4 then userInsetV = 4 end
				local derivedInset = math.floor((thickness - 1) * 0.5)
				local baseInset = 0
				if styleKey == "square" then
					if unit == "Player" then
						baseInset = -1
					elseif unit == "Target" then
						baseInset = -2
					elseif unit == "Focus" then
						baseInset = 0
					else
						baseInset = -2
					end
				end
				local combinedInsetH = baseInset + userInsetH + derivedInset
				local combinedInsetV = baseInset + userInsetV + derivedInset

				-- Clear any prior border when disabled
				if not enabled or styleKey == "none" then
					if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(frame) end
					if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(frame) end
				else
					-- Determine effective color from mode + style
					local styleDef = addon.BarBorders and addon.BarBorders.GetStyle and addon.BarBorders.GetStyle(styleKey)
					local color
					if tintEnabled then
						color = tintColor
					else
						if styleDef then
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
						setProp(frame, "borderContainerParentRef", nil)

						-- Unit-specific per-side pad adjustments for Cast Bar:
						-- Player: symmetric (no extra nudges; baseInset handles feel).
						-- Target: top pulled down slightly, left/right pulled in slightly more, bottom unchanged.
						if enabled and unit == "Target" then
							setProp(frame, "borderPadAdjust", {
								left = -2,
								right = -2,
								top = -1,
								bottom = 0,
							})
						else
							setProp(frame, "borderPadAdjust", nil)
						end

						handled = addon.BarBorders.ApplyToBarFrame(frame, styleKey, {
							color = color,
							thickness = thickness,
							levelOffset = 1,
							insetH = combinedInsetH,
							insetV = combinedInsetV,
							hiddenEdges = hiddenEdges,
						})
					end

					if not handled then
						-- Fallback: pixel (square) border using generic square helper
						if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(frame) end
						if addon.Borders and addon.Borders.ApplySquare then
							local sqColor = tintEnabled and tintColor or {0, 0, 0, 1}
							local baseY = (thickness <= 1) and 0 or 1
							local baseX = 1
							local expandY = baseY - combinedInsetV
							local expandX = baseX - combinedInsetH
							if expandX < -6 then expandX = -6 elseif expandX > 6 then expandX = 6 end
							if expandY < -6 then expandY = -6 elseif expandY > 6 then expandY = 6 end

							-- Per-unit fine-tuning for the pixel fallback:
							-- Player: top/bottom/left are good; pull the right edge in slightly.
							-- Target: top pulled down slightly; left/right pulled in more; bottom remains aligned.
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
								hiddenEdges = hiddenEdges,
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
			end -- castBarMode ~= "textFill"

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
						-- Defensive cleanup: if any legacy Scoot borders were drawn directly on the
						-- icon texture (pre-wrapper versions), hide them once so only the current
						-- wrapper/container-based border remains visible.
						if ((addon.Borders.GetAtlasBorder and addon.Borders.GetAtlasBorder(icon)) or (addon.Borders.GetTextureBorder and addon.Borders.GetTextureBorder(icon)) or icon.ScootSquareBorderContainer or icon.ScootSquareBorderEdges)
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
					local container = getIconBorderContainer(icon)
					if container and addon.Borders and addon.Borders.HideAll then
						addon.Borders.HideAll(container)
					elseif addon.Borders and addon.Borders.HideAll then
							addon.Borders.HideAll(icon)
						end
					end
				end
			end

			-- Ensure cast bar text (spell name / cast time) renders above custom borders.
			-- BarBorders creates a holder frame at barLevel + levelOffset, which causes
			-- child FontStrings to render behind the border. We re-parent text to a thin
			-- overlay frame at a level above the border holder.
			do
				local borderEnabled = not not cfg.castBarBorderEnable
				local borderStyle = cfg.castBarBorderStyle or "square"
				local needsOverlay = castBarMode ~= "textFill" and borderEnabled and borderStyle ~= "none"

				if needsOverlay then
					local overlay = getProp(frame, "ScootCastTextOverlay")
					if not overlay then
						overlay = CreateFrame("Frame", nil, frame)
						overlay:SetAllPoints(frame)
						setProp(frame, "ScootCastTextOverlay", overlay)
					end
					-- Determine level above the border holder.  BarBorders uses
					-- barLevel + levelOffset (1 for cast bars); ApplySquare uses the
					-- bar's own level.  barLevel + 3 safely clears both paths.
					local barLevel = (frame.GetFrameLevel and frame:GetFrameLevel()) or 0
					overlay:SetFrameLevel(barLevel + 3)
					overlay:Show()

					if frame.Text and frame.Text.SetParent then
						pcall(frame.Text.SetParent, frame.Text, overlay)
					end
					if unit == "Player" and frame.CastTimeText and frame.CastTimeText.SetParent then
						pcall(frame.CastTimeText.SetParent, frame.CastTimeText, overlay)
					end
				else
					-- Borders disabled: restore text to bar frame
					local overlay = getProp(frame, "ScootCastTextOverlay")
					if overlay then
						if frame.Text and frame.Text.SetParent then
							pcall(frame.Text.SetParent, frame.Text, frame)
						end
						if unit == "Player" and frame.CastTimeText and frame.CastTimeText.SetParent then
							pcall(frame.CastTimeText.SetParent, frame.CastTimeText, frame)
						end
						overlay:Hide()
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
					-- For the cast bar, always treats the spell name as centered within the bar,
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

					-- All units use the same "Hide Spell Name" toggle key
					local disabled = not not cfg.castBarSpellNameHidden

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
						local size = tonumber(styleCfg.size) or 10
						local outline = tostring(styleCfg.style or "OUTLINE")
						if addon.ApplyFontStyle then
							addon.ApplyFontStyle(spellFS, face, size, outline)
						elseif spellFS.SetFont then
							pcall(spellFS.SetFont, spellFS, face, size, outline)
						end

						-- Install gradient SetText hook (once per FontString)
						local hookUnit = unit
						installGradientHook(spellFS, function()
							local d = addon and addon.db and addon.db.profile
							if not d then return nil end
							local uf = d.unitFrames and d.unitFrames[hookUnit]
							local cb = uf and uf.castBar
							return cb and cb.spellNameText
						end, frame)

						-- Color (mode-aware: default/class/custom/classGradient/customGradient)
						applySpellNameColor(spellFS, styleCfg, frame)

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

			-- Sync filled text in textFill mode (after spell name styling)
			if castBarMode == "textFill" then
				pcall(syncTextFillText, frame, cfg)
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
						local size = tonumber(styleCfg.size) or 10
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

		-- BorderShield visibility
		do
			local borderShield = frame.BorderShield
			if borderShield then
				local hideBorderShield = not not cfg.castBarBorderShieldHidden
				if hideBorderShield then
					if borderShield.SetAlpha then
						pcall(borderShield.SetAlpha, borderShield, 0)
					elseif borderShield.Hide then
						pcall(borderShield.Hide, borderShield)
					end
				else
					if borderShield.SetAlpha then
						pcall(borderShield.SetAlpha, borderShield, 1)
					elseif borderShield.Show then
						pcall(borderShield.Show, borderShield)
					end
				end
			end
		end

		local inCombat = InCombatLockdown and InCombatLockdown()
		-- For normal styling passes triggered by profile changes or /reload, avoids
		-- touching secure cast bar anchors during combat and defer until combat ends.
		-- For visual-only refreshes triggered from SetStatusBarTexture/Color hooks,
		-- allows apply() to run in combat so custom textures/colors remain active.
		if inCombat and not getProp(frame, "castVisualOnly") then
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

	-- Empowered cast event tracking + stage tier texture replacement
	do
		local ef = CreateFrame("Frame")
		ef:RegisterEvent("UNIT_SPELLCAST_EMPOWER_START")
		ef:RegisterEvent("UNIT_SPELLCAST_EMPOWER_STOP")
		ef:RegisterEvent("UNIT_SPELLCAST_STOP")
		ef:RegisterEvent("UNIT_SPELLCAST_FAILED")
		ef:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
		ef:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")

		local tokenToUnit = { player = "Player", target = "Target", focus = "Focus" }

		-- Background swap helpers: hide ScootBG and restore stock Background during
		-- empowered casts so stage tier textures (sublevel 4-5) render correctly.
		local function hideScootBGForEmpowered(unitToken)
			local titleUnit = tokenToUnit[unitToken]
			if not titleUnit then return end
			local frame = resolveCastBarFrame(titleUnit)
			if not frame then return end
			local scootBG = getProp(frame, "ScootBG")
			if scootBG and scootBG.SetAlpha then
				pcall(scootBG.SetAlpha, scootBG, 0)
			end
			if frame.Background and frame.Background.SetAlpha then
				pcall(frame.Background.SetAlpha, frame.Background, 1)
			end
			setProp(frame, "empoweredBGSwapped", true)
		end

		local function restoreScootBGAfterEmpowered(unitToken)
			local titleUnit = tokenToUnit[unitToken]
			if not titleUnit then return end
			local frame = resolveCastBarFrame(titleUnit)
			if not frame then return end
			if not getProp(frame, "empoweredBGSwapped") then return end
			setProp(frame, "empoweredBGSwapped", nil)
			C_Timer.After(0, function()
				-- Don't restore normal styling if a new empowered cast has started
				if empoweredCastActive[unitToken] then return end
				if addon and addon.ApplyUnitFrameCastBarFor then
					addon.ApplyUnitFrameCastBarFor(titleUnit)
				end
			end)
		end

		-- Weak-key table for Scoot-owned tier overlay textures (avoids writing to Blizzard frame tables)
		local tierOverlays = setmetatable({}, { __mode = "k" })
		local empoweredStageUpdater

		-- Brightened tier colors to compensate for vertex color multiplication on custom textures.
		-- Dominant channel pushed near 1.0 so the custom texture's own coloring doesn't dim them.
		local TIER_COLORS_NORMAL = {
			{ 0.45, 0.95, 0.55 },  -- Tier 1: bright green
			{ 1.00, 0.90, 0.30 },  -- Tier 2: bright yellow
			{ 1.00, 0.55, 0.25 },  -- Tier 3: bright orange
			{ 1.00, 0.30, 0.20 },  -- Tier 4: bright red
		}
		local TIER_COLORS_DISABLED = {
			{ 0.18, 0.40, 0.22 },  -- ~40% of normal
			{ 0.40, 0.36, 0.12 },
			{ 0.40, 0.22, 0.10 },
			{ 0.40, 0.12, 0.08 },
		}

		-- Replace stage tier atlas textures with Scoot-owned overlay textures + vertex colors
		-- that preserve the stage color progression (green→yellow→orange→red).
		-- SetTexture cannot visually override SetAtlas on Blizzard-owned textures, so we create
		-- our own textures at a higher sublevel and hide the originals behind them.
		local function applyScootTextureToTiers(unitToken)
			local titleUnit = tokenToUnit[unitToken]
			if not titleUnit then return end
			local frame = resolveCastBarFrame(titleUnit)
			if not frame then return end

			-- Read user's configured texture key
			local db = addon and addon.db and addon.db.profile
			if not db then return end
			local cfg = db.unitFrames and db.unitFrames[titleUnit] and db.unitFrames[titleUnit].castBar
			if not cfg then return end
			local texKey = cfg.castBarTexture or "default"
			if texKey == "default" then return end

			-- Resolve to a file path
			local texturePath = addon.Media and addon.Media.ResolveBarTexturePath and addon.Media.ResolveBarTexturePath(texKey)
			if not texturePath then return end

			-- Defer so Blizzard's AddStages has completed and StageTiers is populated
			C_Timer.After(0, function()
				-- Guard: empowered cast may have ended before this deferred callback fires
				if not empoweredCastActive[unitToken] then return end
				if not frame.StageTiers then return end
				-- Guard against secret values on the StageTiers table
				if issecretvalue and issecretvalue(frame.StageTiers) then return end

				for i, tier in ipairs(frame.StageTiers) do
					if tier and not (tier.IsForbidden and tier:IsForbidden()) then
						local nColor = TIER_COLORS_NORMAL[i] or TIER_COLORS_NORMAL[#TIER_COLORS_NORMAL]
						local dColor = TIER_COLORS_DISABLED[i] or TIER_COLORS_DISABLED[#TIER_COLORS_DISABLED]

						-- Get or create Scoot-owned overlay on this tier frame.
						-- Sublevel 7: renders above Normal/Disabled (4) and Glow (5).
						local overlay = tierOverlays[tier]
						if not overlay then
							overlay = tier:CreateTexture(nil, "BACKGROUND", nil, 7)
							overlay:SetAllPoints()
							tierOverlays[tier] = overlay
						end

						-- Apply custom texture + disabled color (all tiers start disabled)
						overlay:SetTexture(texturePath)
						overlay:SetTexCoord(0, 1, 0, 1)
						overlay:SetVertexColor(dColor[1], dColor[2], dColor[3], 1)
						overlay:Show()

						-- Store colors for stage progression (safe: overlay is Scoot-created)
						overlay._nColor = nColor
						overlay._dColor = dColor
						overlay._tierIndex = i

						-- Hide original Blizzard atlas textures behind our overlay
						pcall(tier.Normal.SetAlpha, tier.Normal, 0)
						pcall(tier.Disabled.SetAlpha, tier.Disabled, 0)
					end
				end

				-- Start stage progression tracker (transitions overlay colors disabled → normal)
				if not empoweredStageUpdater then
					empoweredStageUpdater = CreateFrame("Frame")
					empoweredStageUpdater:SetScript("OnUpdate", function(self)
						local f = self._castFrame
						if not f or not f.StageTiers then
							self:Hide()
							return
						end
						local stage = f.CurrSpellStage
						if stage and stage ~= self._lastStage and type(stage) == "number" then
							self._lastStage = stage
							for _, tier in ipairs(f.StageTiers) do
								local ov = tierOverlays[tier]
								if ov and ov._tierIndex then
									local active = (ov._tierIndex <= stage)
									local c = active and ov._nColor or ov._dColor
									if c then
										ov:SetVertexColor(c[1], c[2], c[3], 1)
									end
								end
							end
						end
					end)
				end
				empoweredStageUpdater._castFrame = frame
				empoweredStageUpdater._lastStage = nil
				empoweredStageUpdater:Show()

				-- Force the StatusBar fill texture to be invisible during empowered casts.
				-- Blizzard calls SetColorFill(0,0,0,0) but the texture from a prior normal cast
				-- (set by Scoot's _ApplyToStatusBar) may still render at BORDER layer, above the tiers.
				-- The fill auto-restores when the next normal cast starts (Blizzard's SetStatusBarTexture
				-- triggers Scoot's hook which re-applies the full foreground).
				local fill = frame:GetStatusBarTexture()
				if fill and not (issecretvalue and issecretvalue(fill)) then
					if fill.SetAlpha then pcall(fill.SetAlpha, fill, 0) end
				end
			end)
		end

		-- Hide overlay textures and restore original Blizzard tier textures
		local function cleanupTierOverlays(unitToken)
			if empoweredStageUpdater then
				empoweredStageUpdater:Hide()
			end
			local titleUnit = tokenToUnit[unitToken]
			if not titleUnit then return end
			local f = resolveCastBarFrame(titleUnit)
			if f and f.StageTiers then
				for _, tier in ipairs(f.StageTiers) do
					local ov = tierOverlays[tier]
					if ov then ov:Hide() end
					-- Restore original alpha so Blizzard manages visibility normally
					pcall(tier.Normal.SetAlpha, tier.Normal, 1)
					pcall(tier.Disabled.SetAlpha, tier.Disabled, 1)
				end
				-- Restore fill texture alpha (set to 0 by applyScootTextureToTiers)
				local fill = f:GetStatusBarTexture()
				if fill and not (issecretvalue and issecretvalue(fill)) then
					if fill.SetAlpha then pcall(fill.SetAlpha, fill, 1) end
				end
			end
		end

		ef:SetScript("OnEvent", function(self, event, unit, ...)
			if event == "UNIT_SPELLCAST_EMPOWER_START" then
				empoweredCastActive[unit] = true
				hideScootBGForEmpowered(unit)
				applyScootTextureToTiers(unit)
			elseif event == "UNIT_SPELLCAST_EMPOWER_STOP" then
				empoweredCastActive[unit] = nil
				cleanupTierOverlays(unit)
				restoreScootBGAfterEmpowered(unit)
			else
				-- Clear on any other cast event (failed, interrupted, new channel, etc.)
				if empoweredCastActive[unit] then
					empoweredCastActive[unit] = nil
					cleanupTierOverlays(unit)
					restoreScootBGAfterEmpowered(unit)
				end
			end
		end)
	end

	-- Zero‑Touch hook installation: install cast bar persistence hooks ONLY when the profile
	-- has explicit cast bar config. This is used to ensure hooks exist even if ApplyStyles()
	-- is deferred due to combat at login/reload.
	local function hasCastBarConfig(unit)
		local profile = addon and addon.db and addon.db.profile
		if not profile then return false end
		local unitFrames = rawget(profile, "unitFrames")
		local unitCfg = unitFrames and rawget(unitFrames, unit)
		return unitCfg and rawget(unitCfg, "castBar") ~= nil
	end

	local function ensureHooksForUnit(unit)
		if unit ~= "Player" and unit ~= "Target" and unit ~= "Focus" then return end
		if not hasCastBarConfig(unit) then return end
		local frame = resolveCastBarFrame(unit)
		if not frame then return end

		-- Reuse the same hook installation block used by applyCastBarForUnit().
		-- It is guarded by frame castHooksInstalled state so it is safe to call repeatedly.
		if not getProp(frame, "castHooksInstalled") and _G.hooksecurefunc then
			setProp(frame, "castHooksInstalled", true)
			local hookUnit = unit
			_G.hooksecurefunc(frame, "SetStatusBarTexture", function(self, ...)
				-- Ignore Scoot's own internal texture writes
				if getProp(self, "ufInternalTextureWrite") then return end
				-- Don't re-apply foreground during empowered casts (tiers provide visuals)
				local token = (hookUnit == "Player" and "player") or (hookUnit == "Target" and "target") or (hookUnit == "Focus" and "focus")
				if token and empoweredCastActive[token] then return end
				if addon and addon.ApplyUnitFrameCastBarFor then
					setProp(self, "castVisualOnly", true)
					addon.ApplyUnitFrameCastBarFor(hookUnit)
					setProp(self, "castVisualOnly", nil)
				end
			end)
			_G.hooksecurefunc(frame, "SetStatusBarColor", function(self, ...)
				-- Don't re-apply color during empowered casts (stage tiers provide visuals)
				local token = (hookUnit == "Player" and "player") or (hookUnit == "Target" and "target") or (hookUnit == "Focus" and "focus")
				if token and empoweredCastActive[token] then return end
				if addon and addon.ApplyUnitFrameCastBarFor then
					setProp(self, "castVisualOnly", true)
					addon.ApplyUnitFrameCastBarFor(hookUnit)
					setProp(self, "castVisualOnly", nil)
				end
			end)
			_G.hooksecurefunc(frame, "SetPoint", function(self, ...)
				if getProp(self, "ignoreSetPoint") then return end
				local mode = activeAnchorModes[hookUnit]
				if mode and mode ~= "default" then
					if InCombatLockdown and InCombatLockdown() then
						reanchorCastBar(self, hookUnit)
					else
						if not pendingReapply[hookUnit] then
							pendingReapply[hookUnit] = true
							C_Timer.After(0, function()
								pendingReapply[hookUnit] = nil
								if addon and addon.ApplyUnitFrameCastBarFor then
									addon.ApplyUnitFrameCastBarFor(hookUnit)
								end
							end)
						end
					end
				end
			end)
			if (hookUnit == "Target" or hookUnit == "Focus") and frame.AdjustPosition then
				_G.hooksecurefunc(frame, "AdjustPosition", function(self)
					local mode = activeAnchorModes[hookUnit]
					if mode and mode ~= "default" then
						if InCombatLockdown and InCombatLockdown() then
							reanchorCastBar(self, hookUnit)
						else
							if addon and addon.ApplyUnitFrameCastBarFor then
								addon.ApplyUnitFrameCastBarFor(hookUnit)
							end
						end
					end
				end)
			end
		end
	end

	function addon.EnsureAllUnitFrameCastBarHooks()
		ensureHooksForUnit("Player")
		ensureHooksForUnit("Target")
		ensureHooksForUnit("Focus")
	end
end

--------------------------------------------------------------------------------
-- Boss Cast Bars (Boss1TargetFrameSpellBar through Boss5TargetFrameSpellBar)
-- All 5 Boss frames share a single config table: db.unitFrames.Boss.castBar
--------------------------------------------------------------------------------
do
	-- Resolve Boss cast bar frame by index (1-5)
	local function resolveBossCastBarFrame(index)
		return _G["Boss" .. index .. "TargetFrameSpellBar"]
	end

	-- Store original widths/icon data per Boss frame for percent scaling
	local bossOriginalWidths = {}
	local bossOriginalIconAnchors = {}
	local bossOriginalIconSizes = {}
	local bossOriginalSparkVertexColor = {}
	local bossOriginalSparkAlpha = {}

	-- Store original cast bar anchors for custom anchor mode positioning
	local bossOriginalCastBarAnchors = {}

	-- Track active anchor modes for SetPoint hook re-application
	local bossActiveAnchorModes = {}
	local bossPendingReapply = {}

	-- Track Boss indices that were reanchored during combat and need a full re-apply after combat ends
	local pendingBossPostCombatRefresh = {}

	-- Lightweight reanchor: only corrects position (ClearAllPoints + SetPoint) without
	-- going through the full apply pipeline or its combat guard.  Boss cast bars are visual
	-- StatusBars — repositioning them is safe during combat (no taint).
	local function reanchorBossCastBar(frame, index)
		local db = addon and addon.db and addon.db.profile
		if not db then return end
		local cfg = db.unitFrames and db.unitFrames.Boss and db.unitFrames.Boss.castBar
		if not cfg then return end

		local anchorMode = cfg.anchorMode or "default"
		if anchorMode == "default" or anchorMode == "leftOfFrame" then return end

		local offsetX = tonumber(cfg.offsetX) or 0
		local offsetY = tonumber(cfg.offsetY) or 0

		if anchorMode == "centeredUnderPower" then
			local bossFrame = _G["Boss" .. index .. "TargetFrame"]
			local manaBar
			if addon.BarsResolvers and addon.BarsResolvers.resolveBossManaBar then
				manaBar = addon.BarsResolvers.resolveBossManaBar(bossFrame)
			end

			if manaBar then
				setProp(frame, "ignoreSetPoint", true)
				frame:ClearAllPoints()
				frame:SetPoint("TOP", manaBar, "BOTTOM", offsetX, -2 + offsetY)
				setProp(frame, "ignoreSetPoint", nil)
			end
		elseif anchorMode == "underBossName" then
			local bossFrame = _G["Boss" .. index .. "TargetFrame"]
			local nameFS
			if addon.ResolveBossNameFS then
				nameFS = addon.ResolveBossNameFS(bossFrame)
			end

			if nameFS then
				setProp(frame, "ignoreSetPoint", true)
				frame:ClearAllPoints()
				frame:SetPoint("TOPLEFT", nameFS, "BOTTOMLEFT", 27 + offsetX, -13 + offsetY)
				setProp(frame, "ignoreSetPoint", nil)
			end
		end

		-- Mark for full re-apply when combat ends
		pendingBossPostCombatRefresh[index] = true
	end

	-- Flush deferred full re-applies after combat ends
	function addon.FlushPendingBossCastBarRefresh()
		local any = false
		for _ in pairs(pendingBossPostCombatRefresh) do
			any = true
			break
		end
		if any then
			pendingBossPostCombatRefresh = {}
			if addon.ApplyBossCastBarFor then
				addon.ApplyBossCastBarFor()
			end
		end
	end

	-- Baseline anchors for Boss Spell Name text
	addon._ufBossCastSpellNameBaselines = addon._ufBossCastSpellNameBaselines or {}

	-- Apply styling to a single Boss cast bar frame
	local function applyBossCastBarToFrame(frame, index, cfg)
		if not frame then return end

		-- Install lightweight hooks once to keep cast bar styling persistent
		if not getProp(frame, "bossCastHooksInstalled") and _G.hooksecurefunc then
			setProp(frame, "bossCastHooksInstalled", true)
			local hookIndex = index
			_G.hooksecurefunc(frame, "SetStatusBarTexture", function(self, ...)
				if getProp(self, "ufInternalTextureWrite") then return end
				if addon and addon.ApplyBossCastBarFor then
					setProp(self, "castVisualOnly", true)
					addon.ApplyBossCastBarFor()
					setProp(self, "castVisualOnly", nil)
				end
			end)
			_G.hooksecurefunc(frame, "SetStatusBarColor", function(self, ...)
				if addon and addon.ApplyBossCastBarFor then
					setProp(self, "castVisualOnly", true)
					addon.ApplyBossCastBarFor()
					setProp(self, "castVisualOnly", nil)
				end
			end)
			-- Hook SetPoint to re-apply custom anchoring when Blizzard overrides it
			_G.hooksecurefunc(frame, "SetPoint", function(self, ...)
				-- Ignore Scoot's SetPoint calls (flagged to prevent infinite loops)
				if getProp(self, "ignoreSetPoint") then return end
				-- Only re-apply if a custom anchor mode is active for this Boss cast bar
				local mode = bossActiveAnchorModes[hookIndex]
				if mode and mode ~= "default" and mode ~= "leftOfFrame" then
					if InCombatLockdown and InCombatLockdown() then
						-- Lightweight reanchor during combat (position only)
						reanchorBossCastBar(self, hookIndex)
					else
						if not bossPendingReapply[hookIndex] then
							bossPendingReapply[hookIndex] = true
							C_Timer.After(0, function()
								bossPendingReapply[hookIndex] = nil
								if addon and addon.ApplyBossCastBarFor then
									addon.ApplyBossCastBarFor()
								end
							end)
						end
					end
				end
			end)
			-- Hook AdjustPosition to catch Blizzard layout resets (aura updates, powerBarAlt, OnShow)
			if frame.AdjustPosition then
				_G.hooksecurefunc(frame, "AdjustPosition", function(self)
					local mode = bossActiveAnchorModes[hookIndex]
					if mode and mode ~= "default" and mode ~= "leftOfFrame" then
						if InCombatLockdown and InCombatLockdown() then
							reanchorBossCastBar(self, hookIndex)
						else
							if addon and addon.ApplyBossCastBarFor then
								addon.ApplyBossCastBarFor()
							end
						end
					end
				end)
			end
		end

		-- Capture original width once
		if not bossOriginalWidths[frame] and frame.GetWidth then
			local ok, w = pcall(frame.GetWidth, frame)
			if ok and w then
				bossOriginalWidths[frame] = w
			end
		end

		local origWidth = bossOriginalWidths[frame]

		-- Capture original icon anchor/size once
		local iconFrame = frame.Icon
		if iconFrame then
			if not bossOriginalIconAnchors[iconFrame] and iconFrame.GetPoint then
				local p, relTo, rp, x, y = iconFrame:GetPoint(1)
				if p then
					bossOriginalIconAnchors[iconFrame] = {
						point = p,
						relativeTo = relTo,
						relativePoint = rp,
						xOfs = x or 0,
						yOfs = y or 0,
					}
				end
			end
			if not bossOriginalIconSizes[iconFrame] and iconFrame.GetWidth and iconFrame.GetHeight then
				local okW, w = pcall(iconFrame.GetWidth, iconFrame)
				local okH, h = pcall(iconFrame.GetHeight, iconFrame)
				if okW and okH and w and h then
					bossOriginalIconSizes[iconFrame] = { width = w, height = h }
				end
			end
		end

		-- Capture original cast bar anchor once (for default positioning restoration)
		if not bossOriginalCastBarAnchors[frame] and frame.GetPoint then
			local p, relTo, rp, x, y = frame:GetPoint(1)
			if p then
				bossOriginalCastBarAnchors[frame] = {
					point = p,
					relativeTo = relTo,
					relativePoint = rp,
					xOfs = x or 0,
					yOfs = y or 0,
				}
			end
		end

		-- Read anchor mode from config
		local anchorMode = cfg.anchorMode or "default"

		-- Programmatically sync Edit Mode "CastBarOnSide" setting to match anchor mode
		do
			local desiredOnSide = (anchorMode == "leftOfFrame") and 1 or 0
			local mgr = _G.EditModeManagerFrame
			local EMSys = _G.Enum and _G.Enum.EditModeSystem
			local idx = _G.Enum and _G.Enum.EditModeUnitFrameSystemIndices and _G.Enum.EditModeUnitFrameSystemIndices.Boss
			local settingId = _G.Enum and _G.Enum.EditModeUnitFrameSetting and _G.Enum.EditModeUnitFrameSetting.CastBarOnSide
			if mgr and EMSys and idx and mgr.GetRegisteredSystemFrame and settingId then
				local bossSystemFrame = mgr:GetRegisteredSystemFrame(EMSys.UnitFrame, idx)
				if bossSystemFrame and addon.EditMode then
					local currentVal = 0
					if addon.EditMode.GetSetting then
						local ok, v = pcall(addon.EditMode.GetSetting, bossSystemFrame, settingId)
						if ok and v then currentVal = v end
					end
					if currentVal ~= desiredOnSide and addon.EditMode.WriteSetting then
						addon.EditMode.WriteSetting(bossSystemFrame, settingId, desiredOnSide)
					end
				end
			end
		end

		-- Read settings from config
		local castBarScale = tonumber(cfg.castBarScale) or 100
		if castBarScale < 50 then castBarScale = 50 elseif castBarScale > 150 then castBarScale = 150 end

		local iconWidth = tonumber(cfg.iconWidth)
		local iconHeight = tonumber(cfg.iconHeight)
		local iconBarPadding = tonumber(cfg.iconBarPadding) or 0
		local iconDisabled = cfg.iconDisabled == true

		local function apply()
			local inCombat = InCombatLockdown and InCombatLockdown()
			local visualOnly = inCombat and getProp(frame, "castVisualOnly")

			-- Layout (size/scale/icon) is skipped for in-combat visual-only refreshes
			if not visualOnly then
				-- Apply cast bar scale
				if frame.SetScale then
					local scale = castBarScale / 100.0
					pcall(frame.SetScale, frame, scale)
				end

				-- Apply custom anchor positioning (only when anchorMode is not "default")
				-- Track the active anchor mode so the SetPoint hook knows when to re-apply
				bossActiveAnchorModes[index] = anchorMode

				if anchorMode ~= "default" and anchorMode ~= "leftOfFrame" then
					local anchorApplied = false
					local offsetX = tonumber(cfg.offsetX) or 0
					local offsetY = tonumber(cfg.offsetY) or 0

					if anchorMode == "centeredUnderPower" then
						local bossFrame = _G["Boss" .. index .. "TargetFrame"]
						local manaBar
						if addon.BarsResolvers and addon.BarsResolvers.resolveBossManaBar then
							manaBar = addon.BarsResolvers.resolveBossManaBar(bossFrame)
						end

						if manaBar then
							setProp(frame, "ignoreSetPoint", true)
							frame:ClearAllPoints()
							frame:SetPoint("TOP", manaBar, "BOTTOM", offsetX, -2 + offsetY)
							setProp(frame, "ignoreSetPoint", nil)
							anchorApplied = true
						end
					elseif anchorMode == "underBossName" then
						local bossFrame = _G["Boss" .. index .. "TargetFrame"]
						local nameFS
						if addon.ResolveBossNameFS then
							nameFS = addon.ResolveBossNameFS(bossFrame)
						end

						if nameFS then
							setProp(frame, "ignoreSetPoint", true)
							frame:ClearAllPoints()
							frame:SetPoint("TOPLEFT", nameFS, "BOTTOMLEFT", 27 + offsetX, -13 + offsetY)
							setProp(frame, "ignoreSetPoint", nil)
							anchorApplied = true
						end
					end

					-- If custom anchor failed, fall back to default positioning
					if not anchorApplied then
						local orig = bossOriginalCastBarAnchors[frame]
						if orig then
							setProp(frame, "ignoreSetPoint", true)
							frame:ClearAllPoints()
							frame:SetPoint(
								orig.point,
								orig.relativeTo,
								orig.relativePoint,
								orig.xOfs or 0,
								orig.yOfs or 0
							)
							setProp(frame, "ignoreSetPoint", nil)
						end
					end
				else
					-- Restore default positioning (original anchor)
					-- Only restore if it previously had a custom anchor mode active
					-- Prevents fighting with Blizzard's layout when user has "default" selected
					if getProp(frame, "hadCustomAnchor") then
						local orig = bossOriginalCastBarAnchors[frame]
						if orig then
							setProp(frame, "ignoreSetPoint", true)
							frame:ClearAllPoints()
							frame:SetPoint(
								orig.point,
								orig.relativeTo,
								orig.relativePoint,
								orig.xOfs or 0,
								orig.yOfs or 0
							)
							setProp(frame, "ignoreSetPoint", nil)
						end
						setProp(frame, "hadCustomAnchor", nil)
					end
				end

				-- Track that a custom anchor has been applied (for restoration when switching back to default)
				if anchorMode ~= "default" and anchorMode ~= "leftOfFrame" then
					setProp(frame, "hadCustomAnchor", true)
				end

				-- Apply icon visibility, size, and padding
				local icon = frame.Icon
				if icon then
					if iconDisabled then
						if icon.SetAlpha then pcall(icon.SetAlpha, icon, 0) end
						local container = getIconBorderContainer(icon)
						if container and addon.Borders and addon.Borders.HideAll then
							addon.Borders.HideAll(container)
						end
						local container = getIconBorderContainer(icon)
						if container and addon.Borders and addon.Borders.HideAll then
							addon.Borders.HideAll(container)
						end
						local container = getIconBorderContainer(icon)
						if container and addon.Borders and addon.Borders.HideAll then
							addon.Borders.HideAll(container)
						end
					else
						if icon.SetAlpha then pcall(icon.SetAlpha, icon, 1) end

						local baseSize = bossOriginalIconSizes[icon]
						if iconWidth or iconHeight then
							local w = tonumber(iconWidth) or (baseSize and baseSize.width) or (icon.GetWidth and icon:GetWidth()) or 16
							local h = tonumber(iconHeight) or (baseSize and baseSize.height) or (icon.GetHeight and icon:GetHeight()) or 16
							w = math.max(8, math.min(64, w))
							h = math.max(8, math.min(64, h))
							pcall(icon.SetSize, icon, w, h)
							if icon.Icon and icon.Icon.SetAllPoints then
								icon.Icon:SetAllPoints(icon)
							end
							if icon.IconMask and icon.IconMask.SetAllPoints then
								icon.IconMask:SetAllPoints(icon)
							end
						end

						-- Icon/Bar padding
						local baseAnchor = bossOriginalIconAnchors[icon]
						if baseAnchor and icon.ClearAllPoints and icon.SetPoint then
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
			end

			-- Text-Fill Cast Bar mode (Boss)
			local castBarMode = cfg.castBarMode or "default"

			if castBarMode == "textFill" then
				local ok, err = pcall(addon._applyTextFillMode, frame, cfg, "Boss")
			else
				addon._hideTextFillElements(frame)
			end

			-- Apply foreground and background styling
			if castBarMode ~= "textFill" and (not inCombat or visualOnly) and (addon._ApplyToStatusBar or addon._ApplyBackgroundToStatusBar) then
				-- Foreground: texture + color
				if addon._ApplyToStatusBar and frame.GetStatusBarTexture then
					local texKey = cfg.castBarTexture or "default"
					local colorMode = cfg.castBarColorMode or "default"
					local tint = cfg.castBarTint
					-- For Boss cast bars, use the boss unit for class color
					local unitId = "boss" .. index
					addon._ApplyToStatusBar(frame, texKey, colorMode, tint, "player", "cast", unitId, visualOnly)
				end

				-- Background: texture + color + opacity
				if addon._ApplyBackgroundToStatusBar then
					local bgTexKey = cfg.castBarBackgroundTexture or "default"
					local bgColorMode = cfg.castBarBackgroundColorMode or "default"
					local bgOpacity = cfg.castBarBackgroundOpacity or 50
					addon._ApplyBackgroundToStatusBar(frame, bgTexKey, bgColorMode, cfg.castBarBackgroundTint, bgOpacity, "Boss", "cast")
				end
			end

			-- Spark visibility and color
			do
				local spark = frame.Spark
				if spark then
					if not bossOriginalSparkVertexColor[spark] and spark.GetVertexColor then
						local ok, r, g, b, a = pcall(spark.GetVertexColor, spark)
						if not ok or not r or not g or not b then
							r, g, b, a = 1, 1, 1, 1
						end
						bossOriginalSparkVertexColor[spark] = { r or 1, g or 1, b or 1, a or 1 }
					end
					if not bossOriginalSparkAlpha[spark] and spark.GetAlpha then
						local ok, alpha = pcall(spark.GetAlpha, spark)
						bossOriginalSparkAlpha[spark] = (ok and alpha) or 1
					end

					local sparkHidden = cfg.castBarSparkHidden == true
					local colorMode = cfg.castBarSparkColorMode or "default"
					local tintTbl = type(cfg.castBarSparkTint) == "table" and cfg.castBarSparkTint or {1,1,1,1}

					local base = bossOriginalSparkVertexColor[spark] or {1,1,1,1}
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

					if sparkHidden then
						if spark.SetAlpha then
							pcall(spark.SetAlpha, spark, 0)
						end
					else
						if spark.SetAlpha then
							local baseAlpha = bossOriginalSparkAlpha[spark] or a or 1
							pcall(spark.SetAlpha, spark, baseAlpha)
						end
					end
				end
			end

			-- Custom Cast Bar border
			if castBarMode == "textFill" then
				if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(frame) end
				if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(frame) end
				if frame.Border and frame.Border.SetShown then pcall(frame.Border.SetShown, frame.Border, false) end
			else
			do
				local enabled = not not cfg.castBarBorderEnable
				local styleKey = cfg.castBarBorderStyle or "square"
				local hiddenEdges = cfg.castBarBorderHiddenEdges
				local tintEnabled = not not cfg.castBarBorderTintEnable
				local tintTbl = type(cfg.castBarBorderTintColor) == "table" and cfg.castBarBorderTintColor or {1,1,1,1}
				local tintColor = {
					tintTbl[1] or 1,
					tintTbl[2] or 1,
					tintTbl[3] or 1,
					tintTbl[4] or 1,
				}
				local thickness = tonumber(cfg.castBarBorderThickness) or 1
				if thickness < 1 then thickness = 1 elseif thickness > 16 then thickness = 16 end

				local userInsetH = tonumber(cfg.castBarBorderInsetH) or tonumber(cfg.castBarBorderInset) or 0
				local userInsetV = tonumber(cfg.castBarBorderInsetV) or tonumber(cfg.castBarBorderInset) or 0
				if userInsetH < -4 then userInsetH = -4 elseif userInsetH > 4 then userInsetH = 4 end
				if userInsetV < -4 then userInsetV = -4 elseif userInsetV > 4 then userInsetV = 4 end
				local derivedInset = math.floor((thickness - 1) * 0.5)
				local baseInset = (styleKey == "square") and -2 or 0
				local combinedInsetH = baseInset + userInsetH + derivedInset
				local combinedInsetV = baseInset + userInsetV + derivedInset

				if not enabled or styleKey == "none" then
					if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(frame) end
					if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(frame) end
				else
					local styleDef = addon.BarBorders and addon.BarBorders.GetStyle and addon.BarBorders.GetStyle(styleKey)
					local color
					if tintEnabled then
						color = tintColor
					else
						if styleDef then
							color = {1, 1, 1, 1}
						else
							color = {0, 0, 0, 1}
						end
					end

				local handled = false
				if addon.BarBorders and addon.BarBorders.ApplyToBarFrame then
					if addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(frame) end
					setProp(frame, "borderContainerParentRef", nil)

				-- Unit-specific per-side pad adjustments for Cast Bar:
				-- Boss: Similar to Target - StatusBar bounds extend beyond visible bar texture.
				-- Apply padding adjustments to pull border edges in to match the actual bar visual.
				if enabled then
					setProp(frame, "borderPadAdjust", {
						left = -2,
						right = -2,
						top = -1,
						bottom = -1,
					})
				else
					setProp(frame, "borderPadAdjust", nil)
				end

					handled = addon.BarBorders.ApplyToBarFrame(frame, styleKey, {
						color = color,
						thickness = thickness,
						levelOffset = 1,
						insetH = combinedInsetH,
						insetV = combinedInsetV,
						hiddenEdges = hiddenEdges,
					})
					end

				if not handled then
					if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(frame) end
					if addon.Borders and addon.Borders.ApplySquare then
						local sqColor = tintEnabled and tintColor or {0, 0, 0, 1}
						local baseY = (thickness <= 1) and 0 or 1
						local baseX = 1
						local expandY = baseY - combinedInsetV
						local expandX = baseX - combinedInsetH
						if expandX < -6 then expandX = -6 elseif expandX > 6 then expandX = 6 end
						if expandY < -6 then expandY = -6 elseif expandY > 6 then expandY = 6 end

					-- Per-unit fine-tuning for Boss cast bar pixel fallback:
					-- Boss: Similar to Target - StatusBar bounds extend beyond visible bar texture.
					-- Pull edges in to match the actual bar visual.
					local exLeft, exRight, exTop, exBottom = expandX, expandX, expandY, expandY
					local name = frame.GetName and frame:GetName()
					if name and name:match("^Boss%d+TargetFrameSpellBar$") then
						exLeft   = math.max(0, exLeft - 2)
						exRight  = math.max(0, exRight - 2)
						exTop    = math.max(0, exTop - 1)
						exBottom = math.max(0, exBottom - 1)
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
							hiddenEdges = hiddenEdges,
						})
					end
				end
				end

				-- Hide Blizzard's stock border when custom borders are enabled
				local border = frame.Border
				if border then
					if border.SetShown then
						pcall(border.SetShown, border, not enabled)
					elseif border.SetAlpha then
						pcall(border.SetAlpha, border, enabled and 0 or 1)
					end
				end
			end
			end -- castBarMode ~= "textFill" (Boss)

			-- Cast Bar Icon border
			do
				local icon = frame.Icon
				if icon then
					local iconBorderEnabled = not not cfg.iconBorderEnable
					local iconStyle = cfg.iconBorderStyle or "square"
					if iconStyle == "none" then
						iconStyle = "square"
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

					if iconBorderEnabled and not iconDisabled then
						if ((addon.Borders.GetAtlasBorder and addon.Borders.GetAtlasBorder(icon)) or (addon.Borders.GetTextureBorder and addon.Borders.GetTextureBorder(icon)) or icon.ScootSquareBorderContainer or icon.ScootSquareBorderEdges)
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
					local container = getIconBorderContainer(icon)
					if container and addon.Borders and addon.Borders.HideAll then
						addon.Borders.HideAll(container)
					elseif addon.Borders and addon.Borders.HideAll then
							addon.Borders.HideAll(icon)
						end
					end
				end
			end

			-- Ensure boss cast bar text renders above custom borders.
			-- Same pattern as Player/Target/Focus (see above).
			do
				local borderEnabled = not not cfg.castBarBorderEnable
				local borderStyle = cfg.castBarBorderStyle or "square"
				local needsOverlay = castBarMode ~= "textFill" and borderEnabled and borderStyle ~= "none"

				if needsOverlay then
					local overlay = getProp(frame, "ScootCastTextOverlay")
					if not overlay then
						overlay = CreateFrame("Frame", nil, frame)
						overlay:SetAllPoints(frame)
						setProp(frame, "ScootCastTextOverlay", overlay)
					end
					local barLevel = (frame.GetFrameLevel and frame:GetFrameLevel()) or 0
					overlay:SetFrameLevel(barLevel + 3)
					overlay:Show()

					if frame.Text and frame.Text.SetParent then
						pcall(frame.Text.SetParent, frame.Text, overlay)
					end
				else
					local overlay = getProp(frame, "ScootCastTextOverlay")
					if overlay then
						if frame.Text and frame.Text.SetParent then
							pcall(frame.Text.SetParent, frame.Text, frame)
						end
						overlay:Hide()
					end
				end
			end

			-- Spell Name Text styling
			do
				local spellFS = frame.Text
				if spellFS then
					local function ensureSpellBaseline(fs, key)
						addon._ufBossCastSpellNameBaselines[key] = addon._ufBossCastSpellNameBaselines[key] or {}
						local b = addon._ufBossCastSpellNameBaselines[key]
						if b.point == nil then
							local parent = (fs and fs.GetParent and fs:GetParent()) or frame
							b.point, b.relTo, b.relPoint, b.x, b.y = "CENTER", parent, "CENTER", 0, 0
						end
						return b
					end

					-- Hide spell name border if configured
					local hideBorder = not not cfg.hideSpellNameBorder
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

					local styleCfg = cfg.spellNameText or {}
					-- Font / size / outline
					local face = addon.ResolveFontFace and addon.ResolveFontFace(styleCfg.fontFace or "FRIZQT__")
						or (select(1, _G.GameFontNormal:GetFont()))
					local size = tonumber(styleCfg.size) or 10
					local outline = tostring(styleCfg.style or "OUTLINE")
					if addon.ApplyFontStyle then
						addon.ApplyFontStyle(spellFS, face, size, outline)
					elseif spellFS.SetFont then
						pcall(spellFS.SetFont, spellFS, face, size, outline)
					end

					-- Install gradient SetText hook (once per FontString)
					installGradientHook(spellFS, function()
						local d = addon and addon.db and addon.db.profile
						if not d then return nil end
						local uf = d.unitFrames and d.unitFrames.Boss
						local cb = uf and uf.castBar
						return cb and cb.spellNameText
					end, frame)

					-- Color (mode-aware: default/class/custom/classGradient/customGradient)
					applySpellNameColor(spellFS, styleCfg, frame)

					-- Offsets relative to baseline
					local ox = (styleCfg.offset and tonumber(styleCfg.offset.x)) or 0
					local oy = (styleCfg.offset and tonumber(styleCfg.offset.y)) or 0
					if spellFS.ClearAllPoints and spellFS.SetPoint then
						local b = ensureSpellBaseline(spellFS, "Boss" .. index .. ":spellName")
						spellFS:ClearAllPoints()
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

			-- Sync filled text in textFill mode (after Boss spell name styling)
			if castBarMode == "textFill" then
				pcall(addon._syncTextFillText, frame, cfg)
			end

			-- BorderShield visibility (Boss cast bars)
			do
				local borderShield = frame.BorderShield
				if borderShield then
					local hideBorderShield = not not cfg.castBarBorderShieldHidden
					if hideBorderShield then
						if borderShield.SetAlpha then
							pcall(borderShield.SetAlpha, borderShield, 0)
						elseif borderShield.Hide then
							pcall(borderShield.Hide, borderShield)
						end
					else
						if borderShield.SetAlpha then
							pcall(borderShield.SetAlpha, borderShield, 1)
						elseif borderShield.Show then
							pcall(borderShield.Show, borderShield)
						end
					end
				end
			end
		end

		local inCombat = InCombatLockdown and InCombatLockdown()
		if inCombat and not getProp(frame, "castVisualOnly") then
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

	-- Apply styling to all Boss cast bars (Boss1-5)
	local function applyAllBossCastBars()
		local db = addon and addon.db and addon.db.profile
		if not db then return end

		-- Boss cast bars share config under db.unitFrames.Boss.castBar
		local unitFrames = rawget(db, "unitFrames")
		local bossCfg = unitFrames and rawget(unitFrames, "Boss") or nil
		if not bossCfg then return end
		local cfg = rawget(bossCfg, "castBar")
		if not cfg then return end

		-- Check if there's any cast bar config; if not, skip (Zero-Touch policy)
		local hasConfig = false
		for k, v in pairs(cfg) do
			if v ~= nil then
				hasConfig = true
				break
			end
		end
		if not hasConfig then return end

		-- Apply to all 5 Boss cast bar frames
		for i = 1, 5 do
			local frame = resolveBossCastBarFrame(i)
			if frame then
				applyBossCastBarToFrame(frame, i, cfg)
			end
		end
	end

	function addon.ApplyBossCastBarFor()
		applyAllBossCastBars()
	end

	-- Update ApplyAllUnitFrameCastBars to include Boss
	local originalApplyAll = addon.ApplyAllUnitFrameCastBars
	function addon.ApplyAllUnitFrameCastBars()
		if originalApplyAll then
			originalApplyAll()
		end
		applyAllBossCastBars()
	end
end
