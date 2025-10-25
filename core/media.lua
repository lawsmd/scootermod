local addonName, addon = ...

addon.Media = addon.Media or {}

-- Registry of bar textures bundled with ScooterMod. Keys are stable identifiers.
-- File paths use WoW UI paths so they load regardless of OS.
local BAR_TEXTURES = {
	bevelled               = "Interface\\AddOns\\ScooterMod\\media\\bar\\bevelled.png",
	bevelledGrey           = "Interface\\AddOns\\ScooterMod\\media\\bar\\bevelled-grey.png",
	fadeTop                = "Interface\\AddOns\\ScooterMod\\media\\bar\\fade-top.png",
	fadeBottom             = "Interface\\AddOns\\ScooterMod\\media\\bar\\fade-bottom.png",
	fadeLeft               = "Interface\\AddOns\\ScooterMod\\media\\bar\\fade-left.png",
	powerSoftActive        = "Interface\\AddOns\\ScooterMod\\media\\bar\\power-soft-active.png",
	powerSoftInactive      = "Interface\\AddOns\\ScooterMod\\media\\bar\\power-soft-inactive.png",
	powerGradientActive    = "Interface\\AddOns\\ScooterMod\\media\\bar\\power-gradient-active.png",
	powerGradientInactive  = "Interface\\AddOns\\ScooterMod\\media\\bar\\power-gradient-inactive.png",
	blizzardCastBar        = "Interface\\AddOns\\ScooterMod\\media\\bar\\blizzard-cast-bar.png",
}

local BAR_DISPLAY_NAMES = {
	bevelled = "Bevelled",
	bevelledGrey = "Bevelled Grey",
	fadeTop = "Fade Top",
	fadeBottom = "Fade Bottom",
	fadeLeft = "Fade Left",
	powerSoftActive = "Soft (Active)",
	powerSoftInactive = "Soft (Inactive)",
	powerGradientActive = "Gradient (Active)",
	powerGradientInactive = "Gradient (Inactive)",
	blizzardCastBar = "Blizzard Cast Bar",
}

-- Public: build a Settings container for dropdowns listing bar textures
function addon.BuildBarTextureOptionsContainer()
    local container = Settings.CreateControlTextContainer()
    local function add(key, label)
        local path = BAR_TEXTURES[key]
        if path then
            -- Menu entry shows preview only (no name)
            local previewOnly = string.format("|T%s:%d:%d|t", path, 12, 180)
            container:Add(key, previewOnly)
        end
    end
    add("bevelled", "Bevelled")
    add("bevelledGrey", "Bevelled Grey")
    add("fadeTop", "Fade Top")
    add("fadeBottom", "Fade Bottom")
    add("fadeLeft", "Fade Left")
    add("powerSoftActive", "Soft (Active)")
    add("powerSoftInactive", "Soft (Inactive)")
    add("powerGradientActive", "Gradient (Active)")
    add("powerGradientInactive", "Gradient (Inactive)")
    add("blizzardCastBar", "Blizzard Cast Bar")
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
	local order = { "bevelled", "bevelledGrey", "fadeTop", "fadeBottom", "fadeLeft", "powerSoftActive", "powerSoftInactive", "powerGradientActive", "powerGradientInactive", "blizzardCastBar" }
	local entries = {}
	for _, key in ipairs(order) do
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


