-- dkrunes.lua - DK Rune Pixel-Art Texture Overlay System
-- Replaces Blizzard rune visuals with spec-colored pixel skull textures when enabled.
local addonName, addon = ...

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

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local RUNE_MEDIA_PREFIX = "Interface\\AddOns\\ScooterMod\\media\\runes\\pixel-skull-"

local SPEC_TEXTURES = {
	[1] = RUNE_MEDIA_PREFIX .. "blood",
	[2] = RUNE_MEDIA_PREFIX .. "frost",
	[3] = RUNE_MEDIA_PREFIX .. "unholy",
}
local DEFAULT_TEXTURE = RUNE_MEDIA_PREFIX .. "base"

-- Blizzard texture region keys to suppress (set alpha 0)
local BLIZZARD_TEXTURE_KEYS = {
	"BG_Shadow", "BG_Inactive", "BG_Active",
	"Rune_Inactive", "Rune_Grad", "Rune_Lines",
	"Rune_Active", "Rune_Mid", "Rune_Eyes",
	"Glow", "Glow2", "Smoke",
}

-- Blizzard animation group keys to stop
local BLIZZARD_ANIM_KEYS = {
	"CooldownFillAnim", "CooldownEndingAnim", "EmptyAnim",
}

--------------------------------------------------------------------------------
-- Config Accessors
--------------------------------------------------------------------------------

local function getUFConfig()
	local db = addon and addon.db and addon.db.profile
	if not db then return nil end
	local cfg = db.unitFrames and db.unitFrames.Player and db.unitFrames.Player.classResource
	return cfg
end

local function getPRDConfig()
	local comp = addon.Components and addon.Components.prdClassResource
	if comp and comp.db then
		return comp.db
	end
	return nil
end

--------------------------------------------------------------------------------
-- Per-RuneButton Overlay Creation
--------------------------------------------------------------------------------

local function getSpecTexture(specIndex)
	return SPEC_TEXTURES[specIndex] or DEFAULT_TEXTURE
end

local function createRuneOverlay(runeButton)
	local existing = getProp(runeButton, "scooterRuneOverlay")
	if existing then return existing end

	local overlay = CreateFrame("Frame", nil, runeButton)
	overlay:SetAllPoints(runeButton)
	overlay:SetFrameLevel(runeButton:GetFrameLevel() + 10)

	local skull = overlay:CreateTexture(nil, "OVERLAY")
	skull:SetSize(24, 24)
	skull:SetPoint("CENTER", overlay, "CENTER", 0, 0)
	skull:SetTexelSnappingBias(0)
	skull:SetSnapToPixelGrid(false)
	overlay.skull = skull

	local cooldown = CreateFrame("Cooldown", nil, overlay, "CooldownFrameTemplate")
	cooldown:SetAllPoints(skull)
	cooldown:SetReverse(false)
	cooldown:SetDrawBling(false)
	cooldown:SetDrawEdge(false)
	cooldown:SetHideCountdownNumbers(true)
	cooldown:SetSwipeColor(0, 0, 0, 0.7)
	overlay.cooldown = cooldown

	overlay:Hide()
	setProp(runeButton, "scooterRuneOverlay", overlay)
	return overlay
end

--------------------------------------------------------------------------------
-- Blizzard Visual Suppression / Restore
--------------------------------------------------------------------------------

local function suppressBlizzardVisuals(runeButton)
	-- Stop all animation groups (prevents them from re-setting alpha)
	for _, animKey in ipairs(BLIZZARD_ANIM_KEYS) do
		local anim = runeButton[animKey]
		if anim and anim.Stop then
			pcall(anim.Stop, anim)
		end
	end

	-- Set all texture regions to alpha 0
	for _, texKey in ipairs(BLIZZARD_TEXTURE_KEYS) do
		local tex = runeButton[texKey]
		if tex and tex.SetAlpha then
			pcall(tex.SetAlpha, tex, 0)
		end
	end

	-- Hide DepleteVisuals frame and stop its animation
	local deplete = runeButton.DepleteVisuals
	if deplete then
		if deplete.DepleteAnim and deplete.DepleteAnim.Stop then
			pcall(deplete.DepleteAnim.Stop, deplete.DepleteAnim)
		end
		pcall(deplete.Hide, deplete)
	end

	-- Hide Blizzard's Cooldown child
	local blizzCD = runeButton.Cooldown
	if blizzCD and blizzCD.SetAlpha then
		pcall(blizzCD.SetAlpha, blizzCD, 0)
	end
end

local function restoreBlizzardVisuals(runeButton)
	-- Restore Blizzard Cooldown alpha
	local blizzCD = runeButton.Cooldown
	if blizzCD and blizzCD.SetAlpha then
		pcall(blizzCD.SetAlpha, blizzCD, 1)
	end

	-- Restore DepleteVisuals
	local deplete = runeButton.DepleteVisuals
	if deplete then
		pcall(deplete.Show, deplete)
		if deplete.SetAlpha then
			pcall(deplete.SetAlpha, deplete, 1)
		end
	end

	-- Clear visual state tracking and let Blizzard re-animate
	setProp(runeButton, "scooterRuneVisualState", nil)
	if runeButton.UpdateState then
		pcall(runeButton.UpdateState, runeButton)
	end
end

--------------------------------------------------------------------------------
-- State Update
--------------------------------------------------------------------------------

local function updateOverlayState(runeButton, specIndex)
	local overlay = getProp(runeButton, "scooterRuneOverlay")
	if not overlay then return end

	local start, duration, runeReady = GetRuneCooldown(runeButton.runeIndex)
	local texturePath = getSpecTexture(specIndex)

	if runeReady then
		-- Ready state: bright skull, no cooldown
		overlay:Show()
		overlay.skull:SetTexture(texturePath)
		overlay.skull:SetAlpha(1.0)
		overlay.cooldown:Clear()
	elseif start and duration and duration > 0 then
		-- On cooldown: skull visible, dark swipe gradually reveals it
		overlay:Show()
		overlay.skull:SetTexture(texturePath)
		overlay.skull:SetAlpha(1.0)
		overlay.cooldown:SetCooldown(start, duration)
	else
		-- Empty state: fully transparent
		overlay:Hide()
	end
end

--------------------------------------------------------------------------------
-- Context Resolution
--------------------------------------------------------------------------------

local function resolveRuneContext(runeButton)
	-- Walk parent chain to determine if this is UF or PRD
	local parent = runeButton:GetParent()
	if not parent then return nil, nil end

	local parentName = parent:GetName()

	-- UF RuneFrame is named "RuneFrame"
	if parentName == "RuneFrame" then
		return "uf", parent
	end

	-- PRD: the rune frame is inside PersonalResourceDisplayFrame.ClassFrameContainer
	-- Check up a few levels for the PRD hierarchy
	local grandparent = parent:GetParent()
	if grandparent then
		local gpName = grandparent:GetName()
		if gpName and gpName:find("PersonalResourceDisplay") then
			return "prd", parent
		end
		-- One more level up
		local greatGrandparent = grandparent:GetParent()
		if greatGrandparent then
			local ggpName = greatGrandparent:GetName()
			if ggpName and ggpName:find("PersonalResourceDisplay") then
				return "prd", parent
			end
		end
	end

	-- Fallback: check parent's parent chain more broadly
	-- The PRD class nameplate bar is a child of ClassFrameContainer
	if parentName and parentName:find("DeathKnight") then
		return "prd", parent
	end

	return nil, nil
end

local function getConfigForContext(context)
	if context == "uf" then
		return getUFConfig()
	elseif context == "prd" then
		return getPRDConfig()
	end
	return nil
end

--------------------------------------------------------------------------------
-- Hook Installation (per-runeFrame)
--------------------------------------------------------------------------------

local function installRuneHooks(runeFrame)
	if not runeFrame or not runeFrame.Runes then return end
	if getProp(runeFrame, "dkRuneHooksInstalled") then return end

	for i = 1, #runeFrame.Runes do
		local runeButton = runeFrame.Runes[i]
		if runeButton then
			-- Hook UpdateState
			if runeButton.UpdateState then
				hooksecurefunc(runeButton, "UpdateState", function(self)
					local ctx, _ = resolveRuneContext(self)
					local cfg = getConfigForContext(ctx)
					if not cfg or cfg.textureStyle ~= "pixel" then return end
					suppressBlizzardVisuals(self)
					local specIndex = GetSpecialization and GetSpecialization() or nil
					updateOverlayState(self, specIndex)
				end)
			end

			-- Hook UpdateSpec
			if runeButton.UpdateSpec then
				hooksecurefunc(runeButton, "UpdateSpec", function(self, specIndex)
					local ctx, _ = resolveRuneContext(self)
					local cfg = getConfigForContext(ctx)
					if not cfg or cfg.textureStyle ~= "pixel" then return end
					local overlay = getProp(self, "scooterRuneOverlay")
					if overlay and overlay.skull then
						overlay.skull:SetTexture(getSpecTexture(specIndex))
					end
				end)
			end
		end
	end

	setProp(runeFrame, "dkRuneHooksInstalled", true)
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function addon.ApplyDKRuneTextures(context)
	-- Only applies to Death Knights
	local _, playerClass = UnitClass("player")
	if playerClass ~= "DEATHKNIGHT" then return end

	-- Combat guard
	if InCombatLockdown and InCombatLockdown() then return end

	local runeFrame
	local cfg

	if context == "uf" then
		runeFrame = _G.RuneFrame
		cfg = getUFConfig()
	elseif context == "prd" then
		local prd = PersonalResourceDisplayFrame
		if prd and prd.ClassFrameContainer then
			local child = prd.ClassFrameContainer.GetChildren and prd.ClassFrameContainer:GetChildren()
			if child and child.Runes then
				runeFrame = child
			end
		end
		cfg = getPRDConfig()
	end

	if not runeFrame or not runeFrame.Runes then return end
	if not cfg then return end

	local textureStyle = cfg.textureStyle or "default"

	if textureStyle == "pixel" then
		-- Install hooks (idempotent)
		installRuneHooks(runeFrame)

		local specIndex = GetSpecialization and GetSpecialization() or nil

		for i = 1, #runeFrame.Runes do
			local runeButton = runeFrame.Runes[i]
			if runeButton then
				-- Create/get overlay
				createRuneOverlay(runeButton)
				-- Suppress Blizzard visuals
				suppressBlizzardVisuals(runeButton)
				-- Update overlay state
				updateOverlayState(runeButton, specIndex)
			end
		end
	else
		-- Default mode: hide overlays, restore Blizzard visuals
		for i = 1, #runeFrame.Runes do
			local runeButton = runeFrame.Runes[i]
			if runeButton then
				local overlay = getProp(runeButton, "scooterRuneOverlay")
				if overlay then
					overlay:Hide()
				end
				restoreBlizzardVisuals(runeButton)
			end
		end
	end
end
