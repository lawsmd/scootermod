--------------------------------------------------------------------------------
-- groupauras/icons.lua
-- Icon frame pool, styling, sizing, and positioning for aura tracking icons
--
-- Depends on groupauras/core.lua (HA namespace, rainbow engine, state tables)
--------------------------------------------------------------------------------

local addonName, addon = ...

local HA = addon.AuraTracking
if not HA then return end

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local POOL_PREALLOC = 40
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
    icon:SetFrameStrata("HIGH")
    icon:SetFrameLevel(20)

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
    -- Never SetParent to Blizzard frames — causes taint propagation.
    -- Icons stay parented to UIParent; anchored to group frames via SetPoint.
    return icon
end

function HA.ReleaseIcon(icon)
    if not icon then return end
    icon:Hide()
    icon:ClearAllPoints()
    icon:SetParent(UIParent)
    icon.spellId = nil

    -- Detach animation controller
    HA.DetachAnimation(icon)

    -- Remove from rainbow tracking
    if icon._isRainbow and icon.Icon then
        HA.UnregisterRainbowIcon(icon.Icon)
        icon._isRainbow = false
    end

    -- Reset cooldown and swipe state
    if icon.Cooldown then
        icon.Cooldown:Clear()
        icon.Cooldown:SetDrawSwipe(true)
        icon.Cooldown:SetReverse(true)
        icon.Cooldown:SetSwipeColor(0, 0, 0, 0.85)
        icon.Cooldown:SetDrawEdge(false)
        icon.Cooldown:SetDrawBling(false)
        pcall(function()
            icon.Cooldown:SetTexCoordRange({ x = 0, y = 0 }, { x = 1, y = 1 })
        end)
    end

    -- Reset stack text
    if icon.CountText then
        icon.CountText:Hide()
        icon.CountText:SetText("")
    end

    -- Reset icon texture and anchoring
    if icon.Icon then
        icon.Icon:SetDesaturated(false)
        icon.Icon:SetVertexColor(1, 1, 1, 1)
        icon.Icon:ClearAllPoints()
        icon.Icon:SetAllPoints()
    end

    -- Reset border backing
    if icon.BorderTex then
        icon.BorderTex:Hide()
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
    local ha = gf and gf.auraTracking
    local spells = ha and ha.spells
    if not spells or not spells[configId] then
        return HA.SPELL_DEFAULTS
    end
    return setmetatable(spells[configId], { __index = HA.SPELL_DEFAULTS })
end

function HA.StyleIcon(iconFrame, spellId, auraData, groupFrame, unit)
    if not iconFrame or not spellId then return end

    local config = GetSpellConfig(spellId)
    iconFrame.spellId = spellId

    -- Parse prefix variants (border:, wide:)
    local style = config.iconStyle
    local isBordered = style:sub(1, 7) == "border:"
    local isWide = style:sub(1, 5) == "wide:"
    local effectiveStyle = style
    if isBordered then
        effectiveStyle = style:sub(8)
    elseif isWide then
        effectiveStyle = style:sub(6)
    end

    -- Set icon texture
    local tex = iconFrame.Icon
    local isAnimated = effectiveStyle:sub(1, 5) == "anim:"
    if isAnimated then
        -- Animated icon: hide standard texture, use animation controller
        tex:Hide()
    elseif effectiveStyle == "spell" then
        -- Try runtime API first (most accurate), static textureId as fallback
        tex:Show()
        HA.DetachAnimation(iconFrame)
        local spellTex
        local ok = pcall(function()
            spellTex = C_Spell.GetSpellTexture(spellId)
        end)
        if ok and spellTex then
            tex:SetTexture(spellTex)
        else
            -- Fallback to static textureId (works when API fails, e.g. secrets)
            local registryEntry = HA.SPELL_REGISTRY_BY_ID and HA.SPELL_REGISTRY_BY_ID[spellId]
            local staticTex = registryEntry and registryEntry.textureId
            if staticTex then
                tex:SetTexture(staticTex)
            else
                tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            end
        end
    elseif effectiveStyle:sub(1, 5) == "file:" then
        -- File-based custom texture
        tex:Show()
        HA.DetachAnimation(iconFrame)
        local path = effectiveStyle:sub(6)
        tex:SetTexture(path)
    else
        -- Atlas-based icon
        tex:Show()
        HA.DetachAnimation(iconFrame)
        local atlasOk = pcall(tex.SetAtlas, tex, effectiveStyle)
        if not atlasOk then
            tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        end
    end

    -- Border variant: same-shape black backing with 1px inset
    if isBordered then
        if not iconFrame.BorderTex then
            local bt = iconFrame:CreateTexture(nil, "BACKGROUND", nil, 0)
            bt:SetAllPoints()
            iconFrame.BorderTex = bt
        end
        -- Use the same atlas shape colored black for a matching silhouette border
        local borderAtlasOk = pcall(iconFrame.BorderTex.SetAtlas, iconFrame.BorderTex, effectiveStyle)
        if not borderAtlasOk then
            iconFrame.BorderTex:SetColorTexture(0, 0, 0, 1)
        end
        iconFrame.BorderTex:SetDesaturated(true)
        iconFrame.BorderTex:SetVertexColor(0, 0, 0, 1)
        iconFrame.BorderTex:Show()
        tex:ClearAllPoints()
        tex:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", 1, -1)
        tex:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", -1, 1)
    else
        if iconFrame.BorderTex then
            iconFrame.BorderTex:Hide()
        end
        tex:ClearAllPoints()
        tex:SetAllPoints()
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
    -- Use OOC-cached height to avoid tainted GetHeight() reads in combat
    local frameHeight = 36
    if groupFrame then
        local state = HA._getState and HA._getState(groupFrame)
        if state and state.cachedHeight and state.cachedHeight > 0 then
            frameHeight = state.cachedHeight
        elseif not InCombatLockdown() then
            local ok, h = pcall(groupFrame.GetHeight, groupFrame)
            if ok and type(h) == "number" and h > 0 then
                frameHeight = h
            end
        end
    end
    local baseSize = math.max(MIN_ICON_SIZE, frameHeight * BASE_SIZE_RATIO)
    local userScale = (config.iconScale or 100) / 100
    local finalSize = math.min(MAX_ICON_SIZE, math.max(MIN_ICON_SIZE, baseSize * userScale))
    -- Wide variant: 3x width
    if isWide then
        iconFrame:SetSize(finalSize * 3, finalSize)
    else
        iconFrame:SetSize(finalSize, finalSize)
    end

    -- Position the icon
    HA.PositionIcon(iconFrame, config, groupFrame)

    -- Attach animated icon controller (after sizing is finalized)
    if isAnimated then
        local animId = effectiveStyle:sub(6)
        HA.AttachAnimation(iconFrame, animId, config, finalSize)
    end

    -- Duration display configuration
    local showDuration = config.showDuration
    if showDuration == nil then showDuration = true end

    if showDuration and not isAnimated then
        -- Configure drain swipe: icon "drains" to dark as duration expires
        iconFrame.Cooldown:SetDrawSwipe(true)
        iconFrame.Cooldown:SetSwipeColor(0, 0, 0, 0.85)
        iconFrame.Cooldown:SetReverse(true)
        iconFrame.Cooldown:SetDrawEdge(false)
        iconFrame.Cooldown:SetDrawBling(false)

        -- Set swipe texture to match the icon for a shaped drain effect
        if effectiveStyle == "spell" then
            local swipeTex
            pcall(function() swipeTex = C_Spell.GetSpellTexture(spellId) end)
            if not swipeTex then
                local entry = HA.SPELL_REGISTRY_BY_ID and HA.SPELL_REGISTRY_BY_ID[spellId]
                swipeTex = entry and entry.textureId
            end
            if swipeTex then
                iconFrame.Cooldown:SetSwipeTexture(swipeTex)
            end
        elseif effectiveStyle:sub(1, 5) == "file:" then
            iconFrame.Cooldown:SetSwipeTexture(effectiveStyle:sub(6))
        else
            -- Atlas-based: resolve to file + tex coords for swipe texture
            local atlasKey = effectiveStyle
            if isBordered then atlasKey = effectiveStyle end
            local atlasInfo = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlasKey)
            if atlasInfo and (atlasInfo.file or atlasInfo.filename) then
                iconFrame.Cooldown:SetSwipeTexture(atlasInfo.file or atlasInfo.filename)
                pcall(function()
                    iconFrame.Cooldown:SetTexCoordRange(
                        { x = atlasInfo.leftTexCoord, y = atlasInfo.topTexCoord },
                        { x = atlasInfo.rightTexCoord, y = atlasInfo.bottomTexCoord }
                    )
                end)
            end
        end
    else
        -- No drain: disable swipe (animated icons handle duration separately)
        iconFrame.Cooldown:SetDrawSwipe(false)
    end

    -- Cooldown sweep timing (DurationObject pattern — matches ClassAuras, secret-safe)
    local cdSet = false
    if auraData and auraData.auraInstanceID and unit
       and C_UnitAuras and C_UnitAuras.GetAuraDuration then
        local dOk, dObj = pcall(C_UnitAuras.GetAuraDuration, unit, auraData.auraInstanceID)
        if dOk and dObj then
            pcall(iconFrame.Cooldown.SetCooldownFromDurationObject, iconFrame.Cooldown, dObj)
            iconFrame.Cooldown:Show()
            cdSet = true
        end
    end
    if not cdSet then
        -- Fallback to legacy arithmetic (non-secret values only)
        if auraData and auraData.expirationTime and auraData.expirationTime > 0
           and auraData.duration and auraData.duration > 0 then
            local startTime = auraData.expirationTime - auraData.duration
            iconFrame.Cooldown:SetCooldown(startTime, auraData.duration)
            iconFrame.Cooldown:Show()
        else
            iconFrame.Cooldown:Clear()
        end
    end

    -- Wire duration data to animated icon controller
    if isAnimated then
        local AE = HA.AnimEngine
        local ctrl = AE and AE.GetActive(iconFrame)
        if ctrl and ctrl.SetDuration then
            local dObj = nil
            local fallbackStart = 0
            local fallbackTotal = 0
            if auraData and auraData.auraInstanceID and unit
               and C_UnitAuras and C_UnitAuras.GetAuraDuration then
                local dOk, d = pcall(C_UnitAuras.GetAuraDuration, unit, auraData.auraInstanceID)
                if dOk and d then dObj = d end
            end
            if auraData and auraData.expirationTime and auraData.expirationTime > 0
               and auraData.duration and auraData.duration > 0 then
                fallbackStart = auraData.expirationTime - auraData.duration
                fallbackTotal = auraData.duration
            end
            -- Pass cached group frame height for descend/ascend travel distance
            ctrl:SetDuration(dObj, fallbackStart, fallbackTotal, frameHeight)
        end
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

-- Center-anchor compensation: shift icon CENTER inward (inside) or outward (outside)
-- so the icon sits fully within/outside the frame regardless of scale.
local INSIDE_CENTER_OFFSET = {
    TOPLEFT     = {  1, -1 },  -- push right and down
    TOP         = {  0, -1 },  -- push down
    TOPRIGHT    = { -1, -1 },  -- push left and down
    LEFT        = {  1,  0 },  -- push right
    CENTER      = {  0,  0 },
    RIGHT       = { -1,  0 },  -- push left
    BOTTOMLEFT  = {  1,  1 },  -- push right and up
    BOTTOM      = {  0,  1 },  -- push up
    BOTTOMRIGHT = { -1,  1 },  -- push left and up
}

local OUTSIDE_CENTER_OFFSET = {
    TOPLEFT     = { -1,  1 },  -- push left and up
    TOP         = {  0,  1 },  -- push up
    TOPRIGHT    = {  1,  1 },  -- push right and up
    RIGHT       = {  1,  0 },  -- push right
    BOTTOMRIGHT = {  1, -1 },  -- push right and down
    BOTTOM      = {  0, -1 },  -- push down
    BOTTOMLEFT  = { -1, -1 },  -- push left and down
    LEFT        = { -1,  0 },  -- push left
}

function HA.PositionIcon(iconFrame, config, groupFrame)
    if not iconFrame or not groupFrame then return end

    iconFrame:ClearAllPoints()

    local position = config.position or "inside"
    local anchor = config.anchor or "TOPRIGHT"
    local offsetX = config.offsetX or 0
    local offsetY = config.offsetY or 0

    local halfW = iconFrame:GetWidth() * 0.5
    local halfH = iconFrame:GetHeight() * 0.5

    if position == "outside" then
        local anchorInfo = OUTSIDE_ANCHOR_MAP[anchor]
        if anchorInfo then
            local comp = OUTSIDE_CENTER_OFFSET[anchor] or { 0, 0 }
            iconFrame:SetPoint("CENTER", groupFrame, anchorInfo.relPoint,
                offsetX + comp[1] * halfW, offsetY + comp[2] * halfH)
        else
            iconFrame:SetPoint("CENTER", groupFrame, "RIGHT", offsetX + halfW, offsetY)
        end
    else
        -- Inside: anchor icon center, compensated inward so icon stays within bounds
        local comp = INSIDE_CENTER_OFFSET[anchor] or { 0, 0 }
        iconFrame:SetPoint("CENTER", groupFrame, anchor,
            offsetX + comp[1] * halfW, offsetY + comp[2] * halfH)
    end
end

--------------------------------------------------------------------------------
-- Animation Helpers
--------------------------------------------------------------------------------

function HA.AttachAnimation(iconFrame, animId, config, size)
    local AE = HA.AnimEngine
    if not AE then return end

    -- If same animation is already attached, just update size/color
    local existing = AE.GetActive(iconFrame)
    if existing and existing.animId == animId then
        existing:SetSize(size)
        HA.ApplyAnimColor(existing, config)
        return
    end

    -- Release old, acquire new
    AE.Release(iconFrame)
    local ctrl = AE.Acquire(iconFrame, iconFrame)
    if not ctrl then return end
    ctrl:Configure(animId, size)
    HA.ApplyAnimColor(ctrl, config)
    ctrl:Play()
end

function HA.DetachAnimation(iconFrame)
    local AE = HA.AnimEngine
    if AE then AE.Release(iconFrame) end
end

function HA.ApplyAnimColor(ctrl, config)
    local mode = config.iconColor or "original"
    if mode == "custom" then
        local c = config.iconCustomColor or { 1, 1, 1, 1 }
        ctrl:SetColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
        ctrl.rainbowMode = false
    elseif mode == "rainbow" then
        ctrl.rainbowMode = true
    else
        ctrl:SetColor(1, 1, 1, 1)
        ctrl.rainbowMode = false
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
