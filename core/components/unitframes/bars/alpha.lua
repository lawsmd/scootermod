--------------------------------------------------------------------------------
-- bars/alpha.lua
-- Alpha enforcement helpers for unit frame styling
-- 
-- IMPORTANT (taint): Avoid SetShown/Show/Hide and avoid SetScript overrides on Blizzard frames.
-- We enforce "hidden" visuals via SetAlpha(0/1) + a deferred Show hook. See DEBUG.md.
--------------------------------------------------------------------------------

local addonName, addon = ...

-- Create module namespace
addon.BarsAlpha = addon.BarsAlpha or {}
local Alpha = addon.BarsAlpha

--------------------------------------------------------------------------------
-- Alpha Application
--------------------------------------------------------------------------------

-- Apply alpha to a frame or texture (safe wrapper)
function Alpha.applyAlpha(frameOrTexture, alpha)
    if not frameOrTexture or not frameOrTexture.SetAlpha then return end
    pcall(frameOrTexture.SetAlpha, frameOrTexture, alpha)
end

--------------------------------------------------------------------------------
-- Alpha Enforcement via Hooks
--------------------------------------------------------------------------------

-- Install hooks to enforce a computed alpha value on a frame/texture
-- @param frameOrTexture: The frame or texture to enforce alpha on
-- @param computeAlpha: Function that returns the desired alpha value (0 or 1)
function Alpha.hookAlphaEnforcer(frameOrTexture, computeAlpha)
    if not frameOrTexture or not _G.hooksecurefunc or type(computeAlpha) ~= "function" then return end
    if frameOrTexture._ScootAlphaEnforcerHooked then return end
    frameOrTexture._ScootAlphaEnforcerHooked = true

    -- IMPORTANT (taint/combat): These enforcers only call SetAlpha, which is safe for visual-only
    -- regions/textures even in combat. Do NOT gate on InCombatLockdown(), otherwise Blizzard can
    -- Show()/SetAlpha() during combat and the element may remain visible after combat.
    local function enforce(obj)
        local desired = computeAlpha()
        if obj and obj.GetAlpha and type(obj.GetAlpha) == "function" then
            local ok, current = pcall(obj.GetAlpha, obj)
            if ok and current == desired then
                return
            end
        end
        Alpha.applyAlpha(obj, desired)
    end

    local function enforceNowAndDefer(obj)
        -- Immediate enforcement prevents visible pop-in.
        enforce(obj)
        -- One-tick backup in case a later same-frame update adjusts alpha again.
        if _G.C_Timer and _G.C_Timer.After then
            _G.C_Timer.After(0, function() enforce(obj) end)
        end
    end

    -- Re-assert when Blizzard shows the object.
    _G.hooksecurefunc(frameOrTexture, "Show", function(self)
        enforceNowAndDefer(self)
    end)

    -- Re-assert when Blizzard toggles visibility via SetShown (some UI paths never call Show directly).
    if frameOrTexture.SetShown then
        _G.hooksecurefunc(frameOrTexture, "SetShown", function(self)
            enforceNowAndDefer(self)
        end)
    end

    -- Re-assert when Blizzard adjusts alpha (e.g., fades, state transitions).
    if frameOrTexture.SetAlpha then
        _G.hooksecurefunc(frameOrTexture, "SetAlpha", function(self)
            enforce(self)
        end)
    end
end

--------------------------------------------------------------------------------
-- Vehicle Frame Texture Visibility Enforcement
--------------------------------------------------------------------------------

-- Enforce visibility for vehicle-related textures
function Alpha.EnforceVehicleFrameTextureVisibility()
    -- PlayerFrame's VehicleTexture overlay. This sits above the custom border layer and
    -- normally shows a vehicle-specific atlas when mounted. If useCustomBorders is true,
    -- we hide it so the user's custom border art is visible instead.
    local vehicleTex = _G.PlayerFrame
        and _G.PlayerFrame.PlayerFrameContainer
        and _G.PlayerFrame.PlayerFrameContainer.VehicleTexture
    if vehicleTex then
        local function computeVehicleAlpha()
            local db = addon and addon.db and addon.db.profile
            local unitFrames = db and rawget(db, "unitFrames") or nil
            local cfgPlayer = unitFrames and rawget(unitFrames, "Player") or nil
            return (cfgPlayer and cfgPlayer.useCustomBorders) and 0 or 1
        end
        Alpha.applyAlpha(vehicleTex, computeVehicleAlpha())
        Alpha.hookAlphaEnforcer(vehicleTex, computeVehicleAlpha)
    end
end

--------------------------------------------------------------------------------
-- Alternate Power Frame Texture Visibility Enforcement
--------------------------------------------------------------------------------

-- Enforce visibility for alternate power bar textures
function Alpha.EnforceAlternatePowerFrameTextureVisibility()
    -- PlayerFrameAlternatePowerBarFrame (Alternate Power/Stagger bar below Player frame).
    -- When useCustomBorders is true for Player frame, hide this overlay so the custom
    -- border appears cleanly.
    local altBar = _G.PlayerFrameAlternatePowerBarFrame
    if altBar then
        local altTex = altBar.TextureBorder or altBar.BorderTexture
        if altTex then
            local function computeAltAlpha()
                local db = addon and addon.db and addon.db.profile
                local unitFrames = db and rawget(db, "unitFrames") or nil
                local cfgPlayer = unitFrames and rawget(unitFrames, "Player") or nil
                return (cfgPlayer and cfgPlayer.useCustomBorders) and 0 or 1
            end
            Alpha.applyAlpha(altTex, computeAltAlpha())
            Alpha.hookAlphaEnforcer(altTex, computeAltAlpha)
        end
    end
end

return Alpha
