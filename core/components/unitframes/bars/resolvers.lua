--------------------------------------------------------------------------------
-- bars/resolvers.lua
-- Frame resolver functions for unit frame bar styling
-- Uses deterministic paths from Framestack findings
--------------------------------------------------------------------------------

local addonName, addon = ...

-- Get utilities
local Utils = addon.BarsUtils

-- Create module namespace
addon.BarsResolvers = addon.BarsResolvers or {}
local Resolvers = addon.BarsResolvers

--------------------------------------------------------------------------------
-- Unit Frame Resolution
--------------------------------------------------------------------------------

-- Get the main unit frame for a given unit type
function Resolvers.getUnitFrameFor(unit)
    -- ToT is not an Edit Mode frame - resolve directly from TargetFrame
    if unit == "TargetOfTarget" then
        return _G.TargetFrameToT
    end
    local mgr = _G.EditModeManagerFrame
    local EM = _G.Enum and _G.Enum.EditModeUnitFrameSystemIndices
    local EMSys = _G.Enum and _G.Enum.EditModeSystem
    if not (mgr and EMSys and mgr.GetRegisteredSystemFrame) then
        if unit == "Pet" then return _G.PetFrame end
        return nil
    end
    local idx = nil
    if EM then
        idx = (unit == "Player" and EM.Player)
            or (unit == "Target" and EM.Target)
            or (unit == "Focus" and EM.Focus)
            or (unit == "Pet" and EM.Pet)
            or (unit == "Boss" and EM.Boss)
    end
    if idx then
        return mgr:GetRegisteredSystemFrame(EMSys.UnitFrame, idx)
    end
    if unit == "Pet" then return _G.PetFrame end
    -- Fallback for Boss if EM.Boss is unavailable
    if unit == "Boss" then return _G.Boss1TargetFrame end
    return nil
end

--------------------------------------------------------------------------------
-- Status Bar Resolution Helpers
--------------------------------------------------------------------------------

-- Find a StatusBar by name hints (fallback search)
local function findStatusBarByHints(root, hintsTbl, excludesTbl)
    if not root then return nil end
    local hints = hintsTbl or {}
    local excludes = excludesTbl or {}
    local found
    local function matchesName(obj)
        local nm = (obj and obj.GetName and obj:GetName()) or (obj and obj.GetDebugName and obj:GetDebugName()) or ""
        if type(nm) ~= "string" then return false end
        local lnm = string.lower(nm)
        for _, ex in ipairs(excludes) do
            if ex and string.find(lnm, string.lower(ex), 1, true) then
                return false
            end
        end
        for _, h in ipairs(hints) do
            if h and string.find(lnm, string.lower(h), 1, true) then
                return true
            end
        end
        return false
    end
    local function scan(obj)
        if not obj or found then return end
        if obj.GetObjectType and obj:GetObjectType() == "StatusBar" then
            if matchesName(obj) then
                found = obj; return
            end
        end
        if obj.GetChildren then
            local m = (obj.GetNumChildren and obj:GetNumChildren()) or 0
            for i = 1, m do
                local c = select(i, obj:GetChildren())
                scan(c)
                if found then return end
            end
        end
    end
    scan(root)
    return found
end

-- Safe nested table access
local function getNested(root, ...)
    local cur = root
    for i = 1, select('#', ...) do
        local key = select(i, ...)
        if not cur or type(cur) ~= "table" then return nil end
        cur = cur[key]
    end
    return cur
end

--------------------------------------------------------------------------------
-- Health Bar Resolution
--------------------------------------------------------------------------------

function Resolvers.resolveHealthBar(frame, unit)
    -- Deterministic paths from Framestack findings; fallback to conservative search only if missing
    if unit == "Pet" then return _G.PetFrameHealthBar end
    if unit == "TargetOfTarget" then
        local tot = _G.TargetFrameToT
        return tot and tot.HealthBar or nil
    end
    if unit == "Player" then
        local root = _G.PlayerFrame
        local hb = getNested(root, "PlayerFrameContent", "PlayerFrameContentMain", "HealthBarsContainer", "HealthBar")
        if hb then return hb end
    elseif unit == "Target" then
        local root = _G.TargetFrame
        local hb = getNested(root, "TargetFrameContent", "TargetFrameContentMain", "HealthBarsContainer", "HealthBar")
        if hb then return hb end
    elseif unit == "Focus" then
        local root = _G.FocusFrame
        local hb = getNested(root, "TargetFrameContent", "TargetFrameContentMain", "HealthBarsContainer", "HealthBar")
        if hb then return hb end
    elseif unit == "Boss" then
        -- Boss frames expose healthbar as a direct property (Boss1TargetFrame.healthbar),
        -- but we must verify it is actually the StatusBar (not a container frame).
        local hb = frame and frame.healthbar
        if hb and hb.GetObjectType and hb:GetObjectType() == "StatusBar" then
            return hb
        end

        -- Deterministic fallback path from Framestack findings.
        local explicit = getNested(frame, "TargetFrameContent", "TargetFrameContentMain", "HealthBarsContainer", "HealthBar")
        if explicit then return explicit end
    end
    -- Fallbacks
    if frame and frame.HealthBarsContainer and frame.HealthBarsContainer.HealthBar then return frame.HealthBarsContainer.HealthBar end
    return findStatusBarByHints(frame, {"HealthBarsContainer.HealthBar", ".HealthBar", "HealthBar"}, {"Prediction", "Absorb", "Mana"})
end

--------------------------------------------------------------------------------
-- Health Container Resolution
--------------------------------------------------------------------------------

function Resolvers.resolveHealthContainer(frame, unit)
    if unit == "Pet" then return _G.PetFrame and _G.PetFrame.HealthBarContainer end
    if unit == "Player" then
        local root = _G.PlayerFrame
        local c = getNested(root, "PlayerFrameContent", "PlayerFrameContentMain", "HealthBarsContainer")
        if c then return c end
    elseif unit == "Target" then
        local root = _G.TargetFrame
        local c = getNested(root, "TargetFrameContent", "TargetFrameContentMain", "HealthBarsContainer")
        if c then return c end
    elseif unit == "Focus" then
        local root = _G.FocusFrame
        local c = getNested(root, "TargetFrameContent", "TargetFrameContentMain", "HealthBarsContainer")
        if c then return c end
    end
    return frame and frame.HealthBarsContainer or nil
end

--------------------------------------------------------------------------------
-- Power Bar Resolution
--------------------------------------------------------------------------------

function Resolvers.resolvePowerBar(frame, unit)
    if unit == "Pet" then return _G.PetFrameManaBar end
    if unit == "TargetOfTarget" then
        local tot = _G.TargetFrameToT
        return tot and tot.ManaBar or nil
    end
    if unit == "Player" then
        local root = _G.PlayerFrame
        local mb = getNested(root, "PlayerFrameContent", "PlayerFrameContentMain", "ManaBarArea", "ManaBar")
        if mb then return mb end
    elseif unit == "Target" then
        local root = _G.TargetFrame
        local mb = getNested(root, "TargetFrameContent", "TargetFrameContentMain", "ManaBar")
        if mb then return mb end
    elseif unit == "Focus" then
        local root = _G.FocusFrame
        local mb = getNested(root, "TargetFrameContent", "TargetFrameContentMain", "ManaBar")
        if mb then return mb end
    elseif unit == "Boss" then
        -- Boss frames expose manabar as a direct property (Boss1TargetFrame.manabar),
        -- but we must verify it is actually the StatusBar (not a container frame).
        local mb = frame and frame.manabar
        if mb and mb.GetObjectType and mb:GetObjectType() == "StatusBar" then
            return mb
        end

        -- Deterministic fallback path from Framestack findings.
        local explicit = getNested(frame, "TargetFrameContent", "TargetFrameContentMain", "ManaBar")
        if explicit then return explicit end
    end
    if frame and frame.ManaBar then return frame.ManaBar end
    return findStatusBarByHints(frame, {"ManaBar", ".ManaBar", "PowerBar"}, {"Prediction"})
end

--------------------------------------------------------------------------------
-- Alternate Power Bar Resolution
--------------------------------------------------------------------------------

-- Resolve the global Alternate Power Bar for the Player frame
function Resolvers.resolveAlternatePowerBar()
    local bar = _G.AlternatePowerBar
    if bar and bar.GetObjectType and bar:GetObjectType() == "StatusBar" then
        return bar
    end
    return nil
end

--------------------------------------------------------------------------------
-- Mask Resolution
--------------------------------------------------------------------------------

function Resolvers.resolveHealthMask(unit)
    if unit == "Player" then
        local root = _G.PlayerFrame
        return root and root.PlayerFrameContent and root.PlayerFrameContent.PlayerFrameContentMain
            and root.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer
            and root.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.HealthBarMask
    elseif unit == "Target" then
        local root = _G.TargetFrame
        return root and root.TargetFrameContent and root.TargetFrameContent.TargetFrameContentMain
            and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer
            and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBarMask
    elseif unit == "Focus" then
        local root = _G.FocusFrame
        return root and root.TargetFrameContent and root.TargetFrameContent.TargetFrameContentMain
            and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer
            and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBarMask
    elseif unit == "Pet" then
        return _G.PetFrameHealthBarMask
    elseif unit == "TargetOfTarget" then
        local tot = _G.TargetFrameToT
        return tot and tot.HealthBar and tot.HealthBar.HealthBarMask or nil
    end
    return nil
end

function Resolvers.resolvePowerMask(unit)
    if unit == "Player" then
        local root = _G.PlayerFrame
        return root and root.PlayerFrameContent and root.PlayerFrameContent.PlayerFrameContentMain
            and root.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea
            and root.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea.ManaBar
            and root.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea.ManaBar.ManaBarMask
    elseif unit == "Target" then
        local root = _G.TargetFrame
        return root and root.TargetFrameContent and root.TargetFrameContent.TargetFrameContentMain
            and root.TargetFrameContent.TargetFrameContentMain.ManaBar
            and root.TargetFrameContent.TargetFrameContentMain.ManaBar.ManaBarMask
    elseif unit == "Focus" then
        local root = _G.FocusFrame
        return root and root.TargetFrameContent and root.TargetFrameContent.TargetFrameContentMain
            and root.TargetFrameContent.TargetFrameContentMain.ManaBar
            and root.TargetFrameContent.TargetFrameContentMain.ManaBar.ManaBarMask
    elseif unit == "Pet" then
        return _G.PetFrameManaBarMask
    elseif unit == "TargetOfTarget" then
        local tot = _G.TargetFrameToT
        return tot and tot.ManaBar and tot.ManaBar.ManaBarMask or nil
    end
    return nil
end

--------------------------------------------------------------------------------
-- Content Main Resolution
--------------------------------------------------------------------------------

-- Parent container that holds both Health and Power areas (content main)
function Resolvers.resolveUFContentMain(unit)
    if unit == "Player" then
        local root = _G.PlayerFrame
        return root and root.PlayerFrameContent and root.PlayerFrameContent.PlayerFrameContentMain or nil
    elseif unit == "Target" then
        local root = _G.TargetFrame
        return root and root.TargetFrameContent and root.TargetFrameContent.TargetFrameContentMain or nil
    elseif unit == "Focus" then
        local root = _G.FocusFrame
        return root and root.TargetFrameContent and root.TargetFrameContent.TargetFrameContentMain or nil
    elseif unit == "Pet" then
        return _G.PetFrame
    elseif unit == "TargetOfTarget" then
        return _G.TargetFrameToT
    end
    return nil
end

--------------------------------------------------------------------------------
-- Frame Texture Resolution
--------------------------------------------------------------------------------

-- Resolve the stock unit frame frame art (the large atlas that includes the health bar border)
function Resolvers.resolveUnitFrameFrameTexture(unit)
    if unit == "Player" then
        local root = _G.PlayerFrame
        return root and root.PlayerFrameContainer and root.PlayerFrameContainer.FrameTexture or nil
    elseif unit == "Target" then
        local root = _G.TargetFrame
        return root and root.TargetFrameContainer and root.TargetFrameContainer.FrameTexture or nil
    elseif unit == "Focus" then
        local root = _G.FocusFrame
        return root and root.TargetFrameContainer and root.TargetFrameContainer.FrameTexture or nil
    elseif unit == "Boss" then
        local root = _G.Boss1TargetFrame
        return root and root.TargetFrameContainer and root.TargetFrameContainer.FrameTexture or nil
    elseif unit == "Pet" then
        return _G.PetFrameTexture
    elseif unit == "TargetOfTarget" then
        local tot = _G.TargetFrameToT
        return tot and tot.FrameTexture or nil
    end
    return nil
end

--------------------------------------------------------------------------------
-- Boss Frame Mask Resolution
--------------------------------------------------------------------------------

function Resolvers.resolveBossHealthMask(bossFrame)
    local hb = bossFrame and bossFrame.healthbar
    if hb then
        local parent = hb:GetParent()
        if parent and parent.HealthBarMask then return parent.HealthBarMask end
    end
    return nil
end

function Resolvers.resolveBossPowerMask(bossFrame)
    local mb = bossFrame and bossFrame.manabar
    if mb and mb.ManaBarMask then return mb.ManaBarMask end
    return nil
end

return Resolvers
