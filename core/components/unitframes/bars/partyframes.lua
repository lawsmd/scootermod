--------------------------------------------------------------------------------
-- bars/partyframes.lua
-- Party frame health bar and text styling
--
-- Applies styling to CompactPartyFrameMember[1-5] frames.
-- Uses combat-safe overlay patterns for persistence during combat.
--------------------------------------------------------------------------------

local addonName, addon = ...

-- Get modules
local Utils = addon.BarsUtils
local Combat = addon.BarsCombat

-- Create module namespace
addon.BarsPartyFrames = addon.BarsPartyFrames or {}
local PartyFrames = addon.BarsPartyFrames

--------------------------------------------------------------------------------
-- Party Frame Detection
--------------------------------------------------------------------------------

function PartyFrames.isPartyFrame(frame)
    return Utils.isPartyFrame(frame)
end

function PartyFrames.isPartyHealthBar(frame)
    if not frame or not frame.healthBar then return false end
    return Utils.isPartyFrame(frame)
end

--------------------------------------------------------------------------------
-- Health Bar Collection
--------------------------------------------------------------------------------

local partyHealthBars = {}

function PartyFrames.collectHealthBars()
    partyHealthBars = {}
    for i = 1, 5 do
        local bar = _G["CompactPartyFrameMember" .. i .. "HealthBar"]
        if bar then
            table.insert(partyHealthBars, bar)
        end
    end
    return partyHealthBars
end

--------------------------------------------------------------------------------
-- Health Bar Styling
--------------------------------------------------------------------------------

function PartyFrames.applyToHealthBar(bar, cfg)
    if not bar or not cfg then return end

    local texKey = cfg.healthBarTexture or "default"
    local colorMode = cfg.healthBarColorMode or "default"
    local tint = cfg.healthBarTint
    local bgTexKey = cfg.healthBarBackgroundTexture or "default"
    local bgColorMode = cfg.healthBarBackgroundColorMode or "default"
    local bgTint = cfg.healthBarBackgroundTint
    local bgOpacity = cfg.healthBarBackgroundOpacity or 50

    if addon._ApplyToStatusBar then
        addon._ApplyToStatusBar(bar, texKey, colorMode, tint, nil, "health", nil)
    end

    if addon._ApplyBackgroundToStatusBar then
        addon._ApplyBackgroundToStatusBar(bar, bgTexKey, bgColorMode, bgTint, bgOpacity, "Party", "health")
    end
end

--------------------------------------------------------------------------------
-- Health Bar Overlay (Combat-Safe Persistence)
--------------------------------------------------------------------------------

-- Update overlay width based on health bar value
local function updateHealthOverlay(bar)
    if not bar or not bar.ScooterPartyHealthFill then return end
    if not bar._ScootPartyOverlayActive then
        bar.ScooterPartyHealthFill:Hide()
        return
    end

    local overlay = bar.ScooterPartyHealthFill
    local totalWidth = bar:GetWidth() or 0
    local minVal, maxVal = bar:GetMinMaxValues()
    local value = bar:GetValue() or minVal

    if not totalWidth or totalWidth <= 0 or not maxVal or maxVal <= minVal then
        overlay:Hide()
        return
    end

    local frac = (value - minVal) / (maxVal - minVal)
    if frac <= 0 then
        overlay:Hide()
        return
    end
    if frac > 1 then frac = 1 end

    overlay:Show()
    overlay:SetWidth(totalWidth * frac)
    overlay:ClearAllPoints()
    overlay:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    overlay:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
end

-- Style the overlay texture and color
local function styleHealthOverlay(bar, cfg)
    if not bar or not bar.ScooterPartyHealthFill or not cfg then return end

    local overlay = bar.ScooterPartyHealthFill
    local texKey = cfg.healthBarTexture or "default"
    local colorMode = cfg.healthBarColorMode or "default"
    local tint = cfg.healthBarTint

    local resolvedPath = addon.Media and addon.Media.ResolveBarTexturePath and addon.Media.ResolveBarTexturePath(texKey)

    if resolvedPath then
        overlay:SetTexture(resolvedPath)
    else
        local tex = bar:GetStatusBarTexture()
        local applied = false
        if tex then
            local okAtlas, atlasName = pcall(tex.GetAtlas, tex)
            if okAtlas and atlasName and atlasName ~= "" then
                if overlay.SetAtlas then
                    pcall(overlay.SetAtlas, overlay, atlasName, true)
                    applied = true
                end
            end
            if not applied then
                local okTex, texPath = pcall(tex.GetTexture, tex)
                if okTex and texPath then
                    if type(texPath) == "string" and texPath:match("^[A-Za-z]") and not texPath:match("\\") and not texPath:match("/") then
                        if overlay.SetAtlas then
                            pcall(overlay.SetAtlas, overlay, texPath, true)
                            applied = true
                        end
                    elseif type(texPath) == "number" or (type(texPath) == "string" and (texPath:match("\\") or texPath:match("/"))) then
                        pcall(overlay.SetTexture, overlay, texPath)
                        applied = true
                    end
                end
            end
        end
        if not applied then
            overlay:SetTexture("Interface\\Buttons\\WHITE8x8")
        end
    end

    local r, g, b, a = 1, 1, 1, 1
    if colorMode == "custom" and type(tint) == "table" then
        r, g, b, a = tint[1] or 1, tint[2] or 1, tint[3] or 1, tint[4] or 1
    elseif colorMode == "class" then
        r, g, b, a = 0, 1, 0, 1
    elseif colorMode == "texture" then
        r, g, b, a = 1, 1, 1, 1
    else
        local barR, barG, barB = bar:GetStatusBarColor()
        if barR then
            r, g, b = barR, barG, barB
        else
            r, g, b = 0, 1, 0
        end
    end
    overlay:SetVertexColor(r, g, b, a)
end

-- Hide Blizzard's fill texture
local function hideBlizzardFill(bar)
    if not bar then return end
    local blizzFill = bar:GetStatusBarTexture()
    if not blizzFill then return end

    blizzFill._ScootHidden = true
    blizzFill:SetAlpha(0)

    if not blizzFill._ScootAlphaHooked and _G.hooksecurefunc then
        blizzFill._ScootAlphaHooked = true
        _G.hooksecurefunc(blizzFill, "SetAlpha", function(self, alpha)
            if alpha > 0 and self._ScootHidden then
                if _G.C_Timer and _G.C_Timer.After then
                    _G.C_Timer.After(0, function()
                        if self._ScootHidden then
                            self:SetAlpha(0)
                        end
                    end)
                end
            end
        end)
    end
end

-- Show Blizzard's fill texture
local function showBlizzardFill(bar)
    if not bar then return end
    local blizzFill = bar:GetStatusBarTexture()
    if blizzFill then
        blizzFill._ScootHidden = nil
        blizzFill:SetAlpha(1)
    end
end

-- Create or update the health overlay
function PartyFrames.ensureHealthOverlay(bar, cfg)
    if not bar then return end

    local hasCustom = cfg and (
        (cfg.healthBarTexture and cfg.healthBarTexture ~= "default") or
        (cfg.healthBarColorMode and cfg.healthBarColorMode ~= "default")
    )

    bar._ScootPartyOverlayActive = hasCustom

    if not hasCustom then
        if bar.ScooterPartyHealthFill then
            bar.ScooterPartyHealthFill:Hide()
        end
        showBlizzardFill(bar)
        return
    end

    if not bar.ScooterPartyHealthFill then
        local overlay = bar:CreateTexture(nil, "OVERLAY", nil, 2)
        overlay:SetVertTile(false)
        overlay:SetHorizTile(false)
        overlay:SetTexCoord(0, 1, 0, 1)
        bar.ScooterPartyHealthFill = overlay

        if _G.hooksecurefunc and not bar._ScootPartyOverlayHooksInstalled then
            bar._ScootPartyOverlayHooksInstalled = true
            _G.hooksecurefunc(bar, "SetValue", function(self)
                updateHealthOverlay(self)
            end)
            _G.hooksecurefunc(bar, "SetMinMaxValues", function(self)
                updateHealthOverlay(self)
            end)
            if bar.HookScript then
                bar:HookScript("OnSizeChanged", function(self)
                    updateHealthOverlay(self)
                end)
            end
        end
    end

    if not bar._ScootPartyTextureSwapHooked and _G.hooksecurefunc then
        bar._ScootPartyTextureSwapHooked = true
        _G.hooksecurefunc(bar, "SetStatusBarTexture", function(self)
            if self._ScootPartyOverlayActive then
                if _G.C_Timer and _G.C_Timer.After then
                    _G.C_Timer.After(0, function()
                        hideBlizzardFill(self)
                    end)
                end
            end
        end)
    end

    styleHealthOverlay(bar, cfg)
    hideBlizzardFill(bar)
    updateHealthOverlay(bar)
end

function PartyFrames.disableHealthOverlay(bar)
    if not bar then return end
    bar._ScootPartyOverlayActive = false
    if bar.ScooterPartyHealthFill then
        bar.ScooterPartyHealthFill:Hide()
    end
    showBlizzardFill(bar)
end

--------------------------------------------------------------------------------
-- Public API Functions
--------------------------------------------------------------------------------

-- Main entry point: Apply party frame health bar styling from DB settings
function addon.ApplyPartyFrameHealthBarStyle()
    local db = addon and addon.db and addon.db.profile
    if not db then return end

    local groupFrames = rawget(db, "groupFrames")
    local cfg = groupFrames and rawget(groupFrames, "party") or nil
    if not cfg then return end

    local hasCustom = (cfg.healthBarTexture and cfg.healthBarTexture ~= "default") or
                      (cfg.healthBarColorMode and cfg.healthBarColorMode ~= "default") or
                      (cfg.healthBarBackgroundTexture and cfg.healthBarBackgroundTexture ~= "default") or
                      (cfg.healthBarBackgroundColorMode and cfg.healthBarBackgroundColorMode ~= "default")
    if not hasCustom then return end

    if InCombatLockdown and InCombatLockdown() then
        Combat.queuePartyFrameReapply()
        return
    end

    PartyFrames.collectHealthBars()
    for _, bar in ipairs(partyHealthBars) do
        PartyFrames.applyToHealthBar(bar, cfg)
    end
end

-- Apply overlays to all party health bars
function addon.ApplyPartyFrameHealthOverlays()
    local db = addon and addon.db and addon.db.profile
    if not db then return end

    local groupFrames = rawget(db, "groupFrames")
    local cfg = groupFrames and rawget(groupFrames, "party") or nil

    local hasCustom = cfg and (
        (cfg.healthBarTexture and cfg.healthBarTexture ~= "default") or
        (cfg.healthBarColorMode and cfg.healthBarColorMode ~= "default")
    )

    for i = 1, 5 do
        local bar = _G["CompactPartyFrameMember" .. i .. "HealthBar"]
        if bar then
            if hasCustom then
                if not (InCombatLockdown and InCombatLockdown()) then
                    PartyFrames.ensureHealthOverlay(bar, cfg)
                elseif bar.ScooterPartyHealthFill then
                    styleHealthOverlay(bar, cfg)
                    updateHealthOverlay(bar)
                end
            else
                PartyFrames.disableHealthOverlay(bar)
            end
        end
    end
end

-- Restore all party health bars to stock appearance
function addon.RestorePartyFrameHealthOverlays()
    for i = 1, 5 do
        local bar = _G["CompactPartyFrameMember" .. i .. "HealthBar"]
        if bar then
            PartyFrames.disableHealthOverlay(bar)
        end
    end
end

--------------------------------------------------------------------------------
-- Hook Installation
--------------------------------------------------------------------------------

function PartyFrames.installHooks()
    if addon._PartyFrameHooksInstalled then return end
    addon._PartyFrameHooksInstalled = true

    -- Hook CompactUnitFrame_UpdateAll
    if _G.hooksecurefunc and _G.CompactUnitFrame_UpdateAll then
        _G.hooksecurefunc("CompactUnitFrame_UpdateAll", function(frame)
            if frame and frame.healthBar and Utils.isPartyFrame(frame) then
                local db = addon and addon.db and addon.db.profile
                local cfg = db and db.groupFrames and db.groupFrames.party or nil
                if cfg then
                    local hasCustom = (cfg.healthBarTexture and cfg.healthBarTexture ~= "default") or
                                      (cfg.healthBarColorMode and cfg.healthBarColorMode ~= "default") or
                                      (cfg.healthBarBackgroundTexture and cfg.healthBarBackgroundTexture ~= "default") or
                                      (cfg.healthBarBackgroundColorMode and cfg.healthBarBackgroundColorMode ~= "default")
                    if hasCustom then
                        local bar = frame.healthBar
                        local cfgRef = cfg
                        if _G.C_Timer and _G.C_Timer.After then
                            _G.C_Timer.After(0, function()
                                if InCombatLockdown and InCombatLockdown() then
                                    Combat.queuePartyFrameReapply()
                                    return
                                end
                                PartyFrames.applyToHealthBar(bar, cfgRef)
                            end)
                        else
                            if InCombatLockdown and InCombatLockdown() then
                                Combat.queuePartyFrameReapply()
                                return
                            end
                            PartyFrames.applyToHealthBar(bar, cfgRef)
                        end
                    end
                end
            end
        end)
    end

    -- Hook CompactUnitFrame_SetUnit
    if _G.hooksecurefunc and _G.CompactUnitFrame_SetUnit then
        _G.hooksecurefunc("CompactUnitFrame_SetUnit", function(frame, unit)
            if frame and frame.healthBar and unit and Utils.isPartyFrame(frame) then
                local db = addon and addon.db and addon.db.profile
                local cfg = db and db.groupFrames and db.groupFrames.party or nil
                if cfg then
                    local hasCustom = (cfg.healthBarTexture and cfg.healthBarTexture ~= "default") or
                                      (cfg.healthBarColorMode and cfg.healthBarColorMode ~= "default") or
                                      (cfg.healthBarBackgroundTexture and cfg.healthBarBackgroundTexture ~= "default") or
                                      (cfg.healthBarBackgroundColorMode and cfg.healthBarBackgroundColorMode ~= "default")
                    if hasCustom then
                        local bar = frame.healthBar
                        local cfgRef = cfg
                        if _G.C_Timer and _G.C_Timer.After then
                            _G.C_Timer.After(0, function()
                                if InCombatLockdown and InCombatLockdown() then
                                    Combat.queuePartyFrameReapply()
                                    return
                                end
                                PartyFrames.applyToHealthBar(bar, cfgRef)
                            end)
                        else
                            if InCombatLockdown and InCombatLockdown() then
                                Combat.queuePartyFrameReapply()
                                return
                            end
                            PartyFrames.applyToHealthBar(bar, cfgRef)
                        end
                    end
                end
            end
        end)
    end
end

-- Install hooks on load
PartyFrames.installHooks()

return PartyFrames
