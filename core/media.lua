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
	mmtA1                  = BAR_MEDIA_PREFIX .. "a1.tga",
	mmtA2                  = BAR_MEDIA_PREFIX .. "a2.tga",
	mmtA3                  = BAR_MEDIA_PREFIX .. "a3.tga",
	mmtA4                  = BAR_MEDIA_PREFIX .. "a4.tga",
	mmtA5                  = BAR_MEDIA_PREFIX .. "a5.tga",
	mmtA6                  = BAR_MEDIA_PREFIX .. "a6.tga",
	mmtA7                  = BAR_MEDIA_PREFIX .. "a7.tga",
	mmtA8                  = BAR_MEDIA_PREFIX .. "a8.tga",
	mmtA9                  = BAR_MEDIA_PREFIX .. "a9.tga",
	mmtA10                 = BAR_MEDIA_PREFIX .. "a10.tga",
	mmtA11                 = BAR_MEDIA_PREFIX .. "a11.tga",
	mmtA12                 = BAR_MEDIA_PREFIX .. "a12.tga",
	mmtA13                 = BAR_MEDIA_PREFIX .. "a13.tga",
	mmtA14                 = BAR_MEDIA_PREFIX .. "a14.tga",
	mmtA15                 = BAR_MEDIA_PREFIX .. "a15.tga",
}

local BAR_DISPLAY_NAMES = {
	bevelled = "Bevelled",
	bevelledGrey = "Bevelled Grey",
	fadeTop = "Fade Top",
	fadeBottom = "Fade Bottom",
	fadeLeft = "Fade Left",
	blizzardCastBar = "Blizzard Cast Bar",
	mmtA1 = "mMediaTag A1",
	mmtA2 = "mMediaTag A2",
	mmtA3 = "mMediaTag A3",
	mmtA4 = "mMediaTag A4",
	mmtA5 = "mMediaTag A5",
	mmtA6 = "mMediaTag A6",
	mmtA7 = "mMediaTag A7",
	mmtA8 = "mMediaTag A8",
	mmtA9 = "mMediaTag A9",
	mmtA10 = "mMediaTag A10",
	mmtA11 = "mMediaTag A11",
	mmtA12 = "mMediaTag A12",
	mmtA13 = "mMediaTag A13",
	mmtA14 = "mMediaTag A14",
	mmtA15 = "mMediaTag A15",
}

local BAR_TEXTURE_ORDER = {
	"bevelled",
	"bevelledGrey",
	"fadeTop",
	"fadeBottom",
	"fadeLeft",
	"blizzardCastBar",
	"mmtA1",
	"mmtA2",
	"mmtA3",
	"mmtA4",
	"mmtA5",
	"mmtA6",
	"mmtA7",
	"mmtA8",
	"mmtA9",
	"mmtA10",
	"mmtA11",
	"mmtA12",
	"mmtA13",
	"mmtA14",
	"mmtA15",
}

-- Public: build a Settings container for dropdowns listing bar textures
function addon.BuildBarTextureOptionsContainer()
    local create = Settings and Settings.CreateControlTextContainer
    if not create then
        local fallback = {}
        for _, key in ipairs(BAR_TEXTURE_ORDER) do
            fallback[#fallback + 1] = { value = key, text = addon.Media.GetBarTextureDisplayName(key) or key }
        end
        return fallback
    end

    local container = create()
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
function addon.Media.ApplyBarTexturesToBarFrame(barFrame, foregroundKey, backgroundKey)
	if not barFrame or type(barFrame.GetObjectType) ~= "function" then return end
	if barFrame:GetObjectType() ~= "StatusBar" then return end

	local fgPath = addon.Media.ResolveBarTexturePath(foregroundKey)
	local bgPath = addon.Media.ResolveBarTexturePath(backgroundKey)

	-- Foreground (status bar fill)
	if fgPath and barFrame.SetStatusBarTexture then
		pcall(barFrame.SetStatusBarTexture, barFrame, fgPath)
		local tex = barFrame:GetStatusBarTexture()
		if tex and tex.SetDrawLayer then pcall(tex.SetDrawLayer, tex, "ARTWORK", 0) end
		if tex and tex.SetSnapToPixelGrid then pcall(tex.SetSnapToPixelGrid, tex, false) end
	end

	-- Background: prefer our own background texture anchored to the bar
	if not barFrame.ScooterModBG then
		barFrame.ScooterModBG = barFrame:CreateTexture(nil, "BACKGROUND", nil, -1)
		barFrame.ScooterModBG:SetAllPoints(barFrame)
	end
	if bgPath then
		pcall(barFrame.ScooterModBG.SetTexture, barFrame.ScooterModBG, bgPath)
		pcall(barFrame.ScooterModBG.SetAlpha, barFrame.ScooterModBG, 1.0)
		barFrame.ScooterModBG:Show()
	else
		-- If no background selected, hide our overlay and let stock show
		barFrame.ScooterModBG:Hide()
	end

	-- Dim the stock XML background if present so our overlay is visible
	for _, region in ipairs({ barFrame:GetRegions() }) do
		if region and region.GetObjectType and region:GetObjectType() == "Texture" then
			pcall(region.SetAlpha, region, 0.15)
		end
	end
end
