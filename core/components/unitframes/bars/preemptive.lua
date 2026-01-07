--------------------------------------------------------------------------------
-- bars/preemptive.lua
-- Pre-emptive hiding functions and early hook installation
--
-- These functions hide elements BEFORE Blizzard's Update runs, preventing
-- visual "flashes" that occur when relying solely on post-update hooks.
--------------------------------------------------------------------------------

local addonName, addon = ...

-- Get modules
local Resolvers = addon.BarsResolvers
local Alpha = addon.BarsAlpha

-- Create module namespace
addon.BarsPreemptive = addon.BarsPreemptive or {}
local Preemptive = addon.BarsPreemptive

--------------------------------------------------------------------------------
-- Pre-emptive Hiding for Target/Focus Frame Elements
--------------------------------------------------------------------------------
-- Called SYNCHRONOUSLY from PLAYER_TARGET_CHANGED and PLAYER_FOCUS_CHANGED
-- event handlers. Hides elements BEFORE Blizzard's TargetFrame_Update runs.

-- Pre-emptive hide for Target frame elements (ReputationColor, FrameTexture, Flash)
function Preemptive.hideTargetElements()
    local db = addon and addon.db and addon.db.profile
    local unitFrames = db and rawget(db, "unitFrames")
    local cfg = unitFrames and rawget(unitFrames, "Target")
    if not cfg then return end

    -- Only hide if useCustomBorders is enabled
    if cfg.useCustomBorders then
        -- Hide ReputationColor immediately
        local repColor = _G.TargetFrame and _G.TargetFrame.TargetFrameContent
            and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain
            and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
        if repColor and repColor.SetAlpha then
            pcall(repColor.SetAlpha, repColor, 0)
        end

        -- Hide frame texture immediately
        local ft = Resolvers.resolveUnitFrameFrameTexture("Target")
        if ft and ft.SetAlpha then
            pcall(ft.SetAlpha, ft, 0)
        end

        -- Hide Flash (aggro/threat glow) immediately
        local targetFlash = _G.TargetFrame and _G.TargetFrame.TargetFrameContainer
            and _G.TargetFrame.TargetFrameContainer.Flash
        if targetFlash and targetFlash.SetAlpha then
            pcall(targetFlash.SetAlpha, targetFlash, 0)
        end
    end

    -- Hide frame texture if healthBarHideBorder is enabled (separate from useCustomBorders)
    if cfg.healthBarHideBorder then
        local ft = Resolvers.resolveUnitFrameFrameTexture("Target")
        if ft and ft.SetAlpha then
            pcall(ft.SetAlpha, ft, 0)
        end
    end
end

-- Pre-emptive hide for Focus frame elements (ReputationColor, FrameTexture, Flash)
function Preemptive.hideFocusElements()
    local db = addon and addon.db and addon.db.profile
    local unitFrames = db and rawget(db, "unitFrames")
    local cfg = unitFrames and rawget(unitFrames, "Focus")
    if not cfg then return end

    -- Only hide if useCustomBorders is enabled
    if cfg.useCustomBorders then
        -- Hide ReputationColor immediately
        local repColor = _G.FocusFrame and _G.FocusFrame.TargetFrameContent
            and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain
            and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
        if repColor and repColor.SetAlpha then
            pcall(repColor.SetAlpha, repColor, 0)
        end

        -- Hide frame texture immediately
        local ft = Resolvers.resolveUnitFrameFrameTexture("Focus")
        if ft and ft.SetAlpha then
            pcall(ft.SetAlpha, ft, 0)
        end

        -- Hide Flash (aggro/threat glow) immediately
        local focusFlash = _G.FocusFrame and _G.FocusFrame.TargetFrameContainer
            and _G.FocusFrame.TargetFrameContainer.Flash
        if focusFlash and focusFlash.SetAlpha then
            pcall(focusFlash.SetAlpha, focusFlash, 0)
        end
    end

    -- Hide frame texture if healthBarHideBorder is enabled (separate from useCustomBorders)
    if cfg.healthBarHideBorder then
        local ft = Resolvers.resolveUnitFrameFrameTexture("Focus")
        if ft and ft.SetAlpha then
            pcall(ft.SetAlpha, ft, 0)
        end
    end
end

--------------------------------------------------------------------------------
-- Early Alpha Hook Installation
--------------------------------------------------------------------------------
-- Install alpha enforcement hooks on Target/Focus frame elements during
-- PLAYER_ENTERING_WORLD, BEFORE the first target is acquired.

function Preemptive.installEarlyAlphaHooks()
    -- Helper to compute alpha based on useCustomBorders setting
    local function makeComputeAlpha(unit)
        return function()
            local db2 = addon and addon.db and addon.db.profile
            local unitFrames2 = db2 and rawget(db2, "unitFrames")
            local cfg2 = unitFrames2 and rawget(unitFrames2, unit)
            return (cfg2 and cfg2.useCustomBorders) and 0 or 1
        end
    end

    local function makeComputeAlphaWithBorder(unit)
        return function()
            local db2 = addon and addon.db and addon.db.profile
            local unitFrames2 = db2 and rawget(db2, "unitFrames")
            local cfg2 = unitFrames2 and rawget(unitFrames2, unit)
            local hide = cfg2 and (cfg2.useCustomBorders or cfg2.healthBarHideBorder)
            return hide and 0 or 1
        end
    end

    -- Target frame elements
    do
        -- ReputationColor
        local targetRepColor = _G.TargetFrame and _G.TargetFrame.TargetFrameContent
            and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain
            and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
        if targetRepColor and not targetRepColor._ScootAlphaEnforcerHooked then
            Alpha.hookAlphaEnforcer(targetRepColor, makeComputeAlpha("Target"))
        end

        -- FrameTexture
        local targetFT = Resolvers.resolveUnitFrameFrameTexture("Target")
        if targetFT and not targetFT._ScootAlphaEnforcerHooked then
            Alpha.hookAlphaEnforcer(targetFT, makeComputeAlphaWithBorder("Target"))
        end

        -- Flash (aggro/threat glow)
        local targetFlash = _G.TargetFrame and _G.TargetFrame.TargetFrameContainer
            and _G.TargetFrame.TargetFrameContainer.Flash
        if targetFlash and not targetFlash._ScootAlphaEnforcerHooked then
            Alpha.hookAlphaEnforcer(targetFlash, makeComputeAlpha("Target"))
        end
    end

    -- Focus frame elements
    do
        -- ReputationColor
        local focusRepColor = _G.FocusFrame and _G.FocusFrame.TargetFrameContent
            and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain
            and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
        if focusRepColor and not focusRepColor._ScootAlphaEnforcerHooked then
            Alpha.hookAlphaEnforcer(focusRepColor, makeComputeAlpha("Focus"))
        end

        -- FrameTexture
        local focusFT = Resolvers.resolveUnitFrameFrameTexture("Focus")
        if focusFT and not focusFT._ScootAlphaEnforcerHooked then
            Alpha.hookAlphaEnforcer(focusFT, makeComputeAlphaWithBorder("Focus"))
        end

        -- Flash (aggro/threat glow)
        local focusFlash = _G.FocusFrame and _G.FocusFrame.TargetFrameContainer
            and _G.FocusFrame.TargetFrameContainer.Flash
        if focusFlash and not focusFlash._ScootAlphaEnforcerHooked then
            Alpha.hookAlphaEnforcer(focusFlash, makeComputeAlpha("Focus"))
        end
    end

    -- Also do initial hide pass for currently configured settings
    Preemptive.hideTargetElements()
    Preemptive.hideFocusElements()
end

-- Expose to addon namespace for backwards compatibility
addon.PreemptiveHideTargetElements = Preemptive.hideTargetElements
addon.PreemptiveHideFocusElements = Preemptive.hideFocusElements
addon.InstallEarlyUnitFrameAlphaHooks = Preemptive.installEarlyAlphaHooks

return Preemptive
