--------------------------------------------------------------------------------
-- groupauras/icons.lua
-- Icon frame pool, styling, sizing, and positioning for healer aura icons
--
-- Depends on groupauras/core.lua (HA namespace, rainbow engine, state tables)
--------------------------------------------------------------------------------

local addonName, addon = ...

local HA = addon.HealerAuras
if not HA then return end

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local POOL_PREALLOC = 20
local BASE_SIZE_RATIO = 0.45  -- Icon base size as ratio of group frame height
local MIN_ICON_SIZE = 10
local MAX_ICON_SIZE = 64

--------------------------------------------------------------------------------
-- Anchor Maps
--------------------------------------------------------------------------------

-- Inside frame: icon anchors to matching point on the group frame
HA.INSIDE_ANCHOR_VALUES = {
    TOPLEFT = "Top-Left", TOP = "Top", TOPRIGHT = "Top-Right",
    LEFT = "Left", CENTER = "Center", RIGHT = "Right",
    BOTTOMLEFT = "Bottom-Left", BOTTOM = "Bottom", BOTTOMRIGHT = "Bottom-Right",
}
HA.INSIDE_ANCHOR_ORDER = {
    "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT",
}

-- Outside frame: icon anchors outside the group frame edge
HA.OUTSIDE_ANCHOR_VALUES = {
    TOPLEFT = "Top-Left", TOP = "Top", TOPRIGHT = "Top-Right",
    RIGHT = "Right", BOTTOMRIGHT = "Bottom-Right",
    BOTTOM = "Bottom", BOTTOMLEFT = "Bottom-Left", LEFT = "Left",
}
HA.OUTSIDE_ANCHOR_ORDER = {
    "TOPLEFT", "TOP", "TOPRIGHT", "RIGHT", "BOTTOMRIGHT", "BOTTOM", "BOTTOMLEFT", "LEFT",
}

-- Maps outside anchor keys to SetPoint arguments
local OUTSIDE_ANCHOR_MAP = {
    TOPLEFT     = { point = "BOTTOMRIGHT", relPoint = "TOPLEFT" },
    TOP         = { point = "BOTTOM",      relPoint = "TOP" },
    TOPRIGHT    = { point = "BOTTOMLEFT",  relPoint = "TOPRIGHT" },
    RIGHT       = { point = "LEFT",        relPoint = "RIGHT" },
    BOTTOMRIGHT = { point = "TOPLEFT",     relPoint = "BOTTOMRIGHT" },
    BOTTOM      = { point = "TOP",         relPoint = "BOTTOM" },
    BOTTOMLEFT  = { point = "TOPRIGHT",    relPoint = "BOTTOMLEFT" },
    LEFT        = { point = "RIGHT",       relPoint = "LEFT" },
}

--------------------------------------------------------------------------------
-- Icon Frame Pool
--------------------------------------------------------------------------------

local iconPool = {}

local function CreateIconFrame()
    local icon = CreateFrame("Frame", nil, UIParent)
    icon:SetSize(16, 16)
    icon:SetFrameStrata("MEDIUM")
    icon:SetFrameLevel(10)

    -- Icon texture
    local tex = icon:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    icon.Icon = tex

    -- Cooldown sweep
    local cd = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    cd:SetAllPoints(icon)
    cd:SetDrawEdge(false)
    cd:SetDrawSwipe(false)
    cd:SetHideCountdownNumbers(true)
    icon.Cooldown = cd

    -- Stack count text
    local count = icon:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    count:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -1, 1)
    count:Hide()
    icon.CountText = count

    -- Tracking fields
    icon.spellId = nil
    icon._isRainbow = false

    icon:Hide()
    return icon
end

-- Pre-allocate pool
local function PreallocatePool()
    for i = 1, POOL_PREALLOC do
        local icon = CreateIconFrame()
        table.insert(iconPool, icon)
    end
end

function HA.AcquireIcon(parent)
    local icon = table.remove(iconPool)
    if not icon then
        if InCombatLockdown() then
            -- Cannot create frames during combat; defer
            return nil
        end
        icon = CreateIconFrame()
    end
    icon:SetParent(parent)
    return icon
end

function HA.ReleaseIcon(icon)
    if not icon then return end
    icon:Hide()
    icon:ClearAllPoints()
    icon.spellId = nil

    -- Remove from rainbow tracking
    if icon._isRainbow and icon.Icon then
        HA.UnregisterRainbowIcon(icon.Icon)
        icon._isRainbow = false
    end

    -- Reset cooldown
    if icon.Cooldown then
        icon.Cooldown:Clear()
    end

    -- Reset stack text
    if icon.CountText then
        icon.CountText:Hide()
        icon.CountText:SetText("")
    end

    -- Reset icon texture
    if icon.Icon then
        icon.Icon:SetDesaturated(false)
        icon.Icon:SetVertexColor(1, 1, 1, 1)
    end

    table.insert(iconPool, icon)
end

--------------------------------------------------------------------------------
-- Icon Styling
--------------------------------------------------------------------------------

local function GetSpellConfig(spellId)
    -- Resolve linked variants to their primary entry's config
    local configId = spellId
    if HA.LINKED_TO_PRIMARY and HA.LINKED_TO_PRIMARY[spellId] then
        configId = HA.LINKED_TO_PRIMARY[spellId]
    end

    local db = addon.db and addon.db.profile
    local gf = db and db.groupFrames
    local ha = gf and gf.healerAuras
    local spells = ha and ha.spells
    if not spells or not spells[configId] then
        return HA.SPELL_DEFAULTS
    end
    return setmetatable(spells[configId], { __index = HA.SPELL_DEFAULTS })
end

function HA.StyleIcon(iconFrame, spellId, auraData, groupFrame)
    if not iconFrame or not spellId then return end

    local config = GetSpellConfig(spellId)
    iconFrame.spellId = spellId

    -- Set icon texture
    local tex = iconFrame.Icon
    if config.iconStyle == "spell" then
        -- Use the spell's actual icon
        local spellTex
        local ok = pcall(function()
            spellTex = C_Spell.GetSpellTexture(spellId)
        end)
        if ok and spellTex then
            tex:SetTexture(spellTex)
        else
            tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        end
    elseif config.iconStyle:sub(1, 5) == "file:" then
        -- File-based custom texture
        local path = config.iconStyle:sub(6)
        tex:SetTexture(path)
    else
        -- Atlas-based icon
        local atlasOk = pcall(tex.SetAtlas, tex, config.iconStyle)
        if not atlasOk then
            tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        end
    end

    -- Apply desaturation and color
    local colorMode = config.iconColor or "original"
    -- Remove from rainbow if switching away
    if iconFrame._isRainbow then
        HA.UnregisterRainbowIcon(tex)
        iconFrame._isRainbow = false
    end

    if colorMode == "original" then
        tex:SetDesaturated(false)
        tex:SetVertexColor(1, 1, 1, 1)
    elseif colorMode == "rainbow" then
        tex:SetDesaturated(true)
        HA.RegisterRainbowIcon(tex)
        iconFrame._isRainbow = true
    elseif colorMode == "custom" then
        tex:SetDesaturated(true)
        local c = config.iconCustomColor or { 1, 1, 1, 1 }
        tex:SetVertexColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
    else
        tex:SetDesaturated(true)
        tex:SetVertexColor(1, 1, 1, 1)
    end

    -- Size based on group frame height + user scale
    local frameHeight = groupFrame and groupFrame:GetHeight() or 36
    local baseSize = math.max(MIN_ICON_SIZE, frameHeight * BASE_SIZE_RATIO)
    local userScale = (config.iconScale or 100) / 100
    local finalSize = math.min(MAX_ICON_SIZE, math.max(MIN_ICON_SIZE, baseSize * userScale))
    iconFrame:SetSize(finalSize, finalSize)

    -- Position the icon
    HA.PositionIcon(iconFrame, config, groupFrame)

    -- Cooldown sweep
    if auraData and auraData.expirationTime and auraData.expirationTime > 0
       and auraData.duration and auraData.duration > 0 then
        local startTime = auraData.expirationTime - auraData.duration
        iconFrame.Cooldown:SetCooldown(startTime, auraData.duration)
        iconFrame.Cooldown:Show()
    else
        iconFrame.Cooldown:Clear()
    end

    -- Stack count
    if auraData and auraData.applications and auraData.applications > 1 then
        iconFrame.CountText:SetText(tostring(auraData.applications))
        iconFrame.CountText:Show()
    else
        iconFrame.CountText:Hide()
    end

    iconFrame:Show()
end

--------------------------------------------------------------------------------
-- Icon Positioning
--------------------------------------------------------------------------------

function HA.PositionIcon(iconFrame, config, groupFrame)
    if not iconFrame or not groupFrame then return end

    iconFrame:ClearAllPoints()

    local position = config.position or "inside"
    local anchor = config.anchor or "TOPRIGHT"
    local offsetX = config.offsetX or 0
    local offsetY = config.offsetY or 0

    if position == "outside" then
        local anchorInfo = OUTSIDE_ANCHOR_MAP[anchor]
        if anchorInfo then
            iconFrame:SetPoint(anchorInfo.point, groupFrame, anchorInfo.relPoint, offsetX, offsetY)
        else
            -- Fallback
            iconFrame:SetPoint("LEFT", groupFrame, "RIGHT", offsetX, offsetY)
        end
    else
        -- Inside: anchor directly to the matching point
        iconFrame:SetPoint(anchor, groupFrame, anchor, offsetX, offsetY)
    end
end

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------

-- Pre-allocate icon pool after PLAYER_ENTERING_WORLD
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:SetScript("OnEvent", function(self)
    PreallocatePool()
    self:UnregisterAllEvents()
end)
