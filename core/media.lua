local addonName, addon = ...

addon.Media = addon.Media or {}

local BAR_MEDIA_PREFIX = "Interface\\AddOns\\ScooterMod\\media\\bar\\"

-- Registry of bar textures bundled with ScooterMod. Keys are stable identifiers.
local BAR_TEXTURES = {
	bevelled               = BAR_MEDIA_PREFIX .. "bevelled.png",
	bevelledGrey           = BAR_MEDIA_PREFIX .. "bevelled-grey.png",
	fadeTop                = BAR_MEDIA_PREFIX .. "fade-top.png",
	fadeBottom             = BAR_MEDIA_PREFIX .. "fade-bottom.png",
	fadeLeft               = BAR_MEDIA_PREFIX .. "fade-left.png",
	blizzardCastBar        = BAR_MEDIA_PREFIX .. "blizzard-cast-bar.png",
	-- Blizzard resource bar textures (from ElvUI_EltreumUI)
	blizzardEbonMight      = BAR_MEDIA_PREFIX .. "EvokerEbonMight.tga",
	blizzardEnergy         = BAR_MEDIA_PREFIX .. "BlizzardUnitframe1.tga",
	blizzardFocus          = BAR_MEDIA_PREFIX .. "BlizzardUnitframe2.tga",
	blizzardFury           = BAR_MEDIA_PREFIX .. "DemonHunterFury.tga",
	blizzardInsanity       = BAR_MEDIA_PREFIX .. "PriestInsanity1.tga",
	blizzardInsanity2      = BAR_MEDIA_PREFIX .. "PriestInsanity2.tga",
	blizzardLunarPower     = BAR_MEDIA_PREFIX .. "DruidStarPower.tga",
	blizzardMaelstrom      = BAR_MEDIA_PREFIX .. "ShamanMaelstrom.tga",
	blizzardMana           = BAR_MEDIA_PREFIX .. "BlizzardUnitframe3.tga",
	blizzardPain           = BAR_MEDIA_PREFIX .. "MonkStagger1.tga",
	blizzardPain2          = BAR_MEDIA_PREFIX .. "MonkStagger2.tga",
	blizzardPain3          = BAR_MEDIA_PREFIX .. "MonkStagger3.tga",
	blizzardRage           = BAR_MEDIA_PREFIX .. "BlizzardUnitframe4.tga",
	blizzardRaidBar        = BAR_MEDIA_PREFIX .. "BlizzardUnitframe5.tga",
	blizzardRunicPower     = BAR_MEDIA_PREFIX .. "BlizzardUnitframe6.tga",
	-- Additional Blizzard unitframe textures
	blizzardUnitframe7     = BAR_MEDIA_PREFIX .. "BlizzardUnitframe7.tga",
	blizzardUnitframe8     = BAR_MEDIA_PREFIX .. "BlizzardUnitframe8.tga",
	-- Blizzard experience bar textures
	blizzardExperience1   = BAR_MEDIA_PREFIX .. "BlizzardExperience1.tga",
	blizzardExperience2    = BAR_MEDIA_PREFIX .. "BlizzardExperience2.tga",
	blizzardExperience3   = BAR_MEDIA_PREFIX .. "BlizzardExperience3.tga",
	-- Blizzard labs textures
	blizzardLabs1          = BAR_MEDIA_PREFIX .. "BlizzardLabs1.tga",
	blizzardLabs2          = BAR_MEDIA_PREFIX .. "BlizzardLabs2.tga",
	-- Numbered series
	a1                     = BAR_MEDIA_PREFIX .. "a1.tga",
	a2                     = BAR_MEDIA_PREFIX .. "a2.tga",
	a3                     = BAR_MEDIA_PREFIX .. "a3.tga",
	a4                     = BAR_MEDIA_PREFIX .. "a4.tga",
	a5                     = BAR_MEDIA_PREFIX .. "a5.tga",
	a8                     = BAR_MEDIA_PREFIX .. "a8.tga",
	a9                     = BAR_MEDIA_PREFIX .. "a9.tga",
	a12                    = BAR_MEDIA_PREFIX .. "a12.tga",
	a13                    = BAR_MEDIA_PREFIX .. "a13.tga",
}

local BAR_DISPLAY_NAMES = {
	bevelled = "Bevelled",
	bevelledGrey = "Bevelled Grey",
	fadeTop = "Fade Top",
	fadeBottom = "Fade Bottom",
	fadeLeft = "Fade Left",
	blizzardCastBar = "Blizzard Cast Bar",
	-- Blizzard resource bar textures
	blizzardEbonMight = "Blizzard Ebon Might",
	blizzardEnergy = "Blizzard Energy",
	blizzardFocus = "Blizzard Focus",
	blizzardFury = "Blizzard Fury",
	blizzardInsanity = "Blizzard Insanity",
	blizzardInsanity2 = "Blizzard Insanity 2",
	blizzardLunarPower = "Blizzard Lunar Power",
	blizzardMaelstrom = "Blizzard Maelstrom",
	blizzardMana = "Blizzard Mana",
	blizzardPain = "Blizzard Pain",
	blizzardPain2 = "Blizzard Pain 2",
	blizzardPain3 = "Blizzard Pain 3",
	blizzardRage = "Blizzard Rage",
	blizzardRaidBar = "Blizzard Raid Bar",
	blizzardRunicPower = "Blizzard Runic Power",
	-- Additional Blizzard unitframe textures
	blizzardUnitframe7 = "Blizzard Unitframe 7",
	blizzardUnitframe8 = "Blizzard Unitframe 8",
	-- Blizzard experience bar textures
	blizzardExperience1 = "Blizzard Experience 1",
	blizzardExperience2 = "Blizzard Experience 2",
	blizzardExperience3 = "Blizzard Experience 3",
	-- Blizzard labs textures
	blizzardLabs1 = "Blizzard Labs 1",
	blizzardLabs2 = "Blizzard Labs 2",
	-- Numbered series
	a1 = "A1",
	a2 = "A2",
	a3 = "A3",
	a4 = "A4",
	a5 = "A5",
	a8 = "A8",
	a9 = "A9",
	a12 = "A12",
	a13 = "A13",
}

local BAR_TEXTURE_ORDER = {
	"bevelled",
	"bevelledGrey",
	"fadeTop",
	"fadeBottom",
	"fadeLeft",
	"blizzardCastBar",
	-- Blizzard resource bar textures (grouped together)
	"blizzardEbonMight",
	"blizzardEnergy",
	"blizzardFocus",
	"blizzardFury",
	"blizzardInsanity",
	"blizzardInsanity2",
	"blizzardLunarPower",
	"blizzardMaelstrom",
	"blizzardMana",
	"blizzardPain",
	"blizzardPain2",
	"blizzardPain3",
	"blizzardRage",
	"blizzardRaidBar",
	"blizzardRunicPower",
	"blizzardUnitframe7",
	"blizzardUnitframe8",
	"blizzardExperience1",
	"blizzardExperience2",
	"blizzardExperience3",
	"blizzardLabs1",
	"blizzardLabs2",
	-- Numbered series
	"a1",
	"a2",
	"a3",
	"a4",
	"a5",
	"a8",
	"a9",
	"a12",
	"a13",
}

-- Public: build a Settings container for dropdowns listing bar textures
function addon.BuildBarTextureOptionsContainer()
    local create = Settings and Settings.CreateControlTextContainer
    if not create then
        local fallback = {}
        -- Insert a Default option that restores Blizzard's stock textures
        table.insert(fallback, { value = "default", text = "Default" })
        for _, key in ipairs(BAR_TEXTURE_ORDER) do
            fallback[#fallback + 1] = { value = key, text = addon.Media.GetBarTextureDisplayName(key) or key }
        end
        return fallback
    end

    local container = create()
    -- Add Default option at the top
    container:Add("default", "Default")
    for _, key in ipairs(BAR_TEXTURE_ORDER) do
        local path = BAR_TEXTURES[key]
        if path then
            local label = addon.Media.GetBarTextureDisplayName(key)
            local preview = string.format("%s  |T%s:%d:%d|t", label, path, 12, 180)
            container:Add(key, preview)
        end
    end
    return container:GetData()
end

function addon.Media.ResolveBarTexturePath(key)
	if type(key) ~= "string" or key == "" then return nil end
	if key == "default" then return nil end
	return BAR_TEXTURES[key]
end

function addon.Media.GetBarTextureDisplayName(key)
	return BAR_DISPLAY_NAMES[key] or key or ""
end

-- Build menu entries suitable for WowStyle dropdowns with inline preview in the menu items
function addon.Media.GetBarTextureMenuEntries()
	local entries = {}
	for _, key in ipairs(BAR_TEXTURE_ORDER) do
		local path = BAR_TEXTURES[key]
		if path then
			local label = addon.Media.GetBarTextureDisplayName(key)
			-- Horizontal preview 180x20 appended to label
			local withPreview = string.format("%s  |T%s:%d:%d|t", label, path, 180, 20)
			table.insert(entries, { text = withPreview, key = key })
		end
	end
	return entries
end

-- Apply ScooterMod bar textures to a StatusBar frame (foreground fill) and a background texture.
-- This does not rely on Blizzard parentKeys and is safe to call repeatedly.
function addon.Media.ApplyBarTexturesToBarFrame(barFrame, foregroundKey, backgroundKey, backgroundOpacity)
	if not barFrame or type(barFrame.GetObjectType) ~= "function" then return end
	if barFrame:GetObjectType() ~= "StatusBar" then return end

	local fgPath = addon.Media.ResolveBarTexturePath(foregroundKey)
	local bgPath = addon.Media.ResolveBarTexturePath(backgroundKey)
	
	-- If background is "default" or empty, use Blizzard's default cooldown manager bar atlas
	if not bgPath or backgroundKey == "default" or backgroundKey == "" then
		bgPath = "UI-HUD-CoolDownManager-Bar"
	end

	-- Foreground (status bar fill)
	-- Guard: Only apply texture if it's actually changing. This prevents flickering on
	-- StatusBars with no progress (e.g., infinite/timer-less buffs in Tracked Bars) when
	-- unrelated settings trigger ApplyStyles() and cause redundant SetStatusBarTexture calls.
	if barFrame.SetStatusBarTexture then
		if fgPath then
			local needsUpdate = (barFrame._ScooterModFGPath ~= fgPath)
			if needsUpdate then
				barFrame._ScooterModFGPath = fgPath
				pcall(barFrame.SetStatusBarTexture, barFrame, fgPath)
			end
			local tex = barFrame:GetStatusBarTexture()
			if tex and tex.SetDrawLayer then pcall(tex.SetDrawLayer, tex, "ARTWORK", 0) end
			if tex and tex.SetSnapToPixelGrid then pcall(tex.SetSnapToPixelGrid, tex, false) end
		elseif barFrame._ScooterModFGPath then
			-- Foreground key changed to "default" - clear our stored path so future
			-- custom textures will be applied correctly
			barFrame._ScooterModFGPath = nil
		end
	end

	-- Background: prefer our own background texture anchored to the bar
	if not barFrame.ScooterModBG then
		barFrame.ScooterModBG = barFrame:CreateTexture(nil, "BACKGROUND", nil, -1)
		barFrame.ScooterModBG:SetAllPoints(barFrame)
	end
	if bgPath then
		-- Guard: Only update background texture if it's actually changing
		local bgNeedsUpdate = (barFrame._ScooterModBGPath ~= bgPath)
		if bgNeedsUpdate then
			barFrame._ScooterModBGPath = bgPath
			-- Check if it's an atlas or a texture path
			local isAtlas = type(bgPath) == "string" and not bgPath:find("\\") and not bgPath:find("/")
			if isAtlas then
				pcall(barFrame.ScooterModBG.SetAtlas, barFrame.ScooterModBG, bgPath, true)
			else
				pcall(barFrame.ScooterModBG.SetTexture, barFrame.ScooterModBG, bgPath)
			end
		end
		-- Apply opacity (always check as this can change independently)
		local opacity = tonumber(backgroundOpacity) or 50
		opacity = math.max(0, math.min(100, opacity)) / 100
		pcall(barFrame.ScooterModBG.SetAlpha, barFrame.ScooterModBG, opacity)
		barFrame.ScooterModBG:Show()
	else
		-- If no background selected, hide our overlay and let stock show
		barFrame._ScooterModBGPath = nil
		barFrame.ScooterModBG:Hide()
	end

	-- Dim the stock XML background if present so our overlay is visible
	for _, region in ipairs({ barFrame:GetRegions() }) do
		if region and region.GetObjectType and region:GetObjectType() == "Texture" then
			pcall(region.SetAlpha, region, 0.15)
		end
	end
end
