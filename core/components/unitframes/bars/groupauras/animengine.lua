--------------------------------------------------------------------------------
-- groupauras/animengine.lua
-- Shared OnUpdate engine, animation controller pool, and definition registry
-- for code-driven animated aura icons.
--
-- Depends on groupauras/core.lua (HA namespace, HSVtoRGB)
--------------------------------------------------------------------------------

local addonName, addon = ...

local HA = addon.AuraTracking
if not HA then return end

HA.AnimEngine = {}
local AE = HA.AnimEngine

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local MAX_TEXTURES = 12          -- Fading Ring uses the most (10-12 dots)
local POOL_PREALLOC = 12
local RAINBOW_CYCLE_PERIOD = 3.0 -- Match existing rainbow engine
local WHITE8X8 = "Interface\\BUTTONS\\WHITE8X8"

-- Shrink: icon scales from 100% → 25% as duration depletes
local SHRINK_MIN_SCALE = 0.25

--------------------------------------------------------------------------------
-- Duration Mode Helper
--------------------------------------------------------------------------------

local function GetAnimDurationMode()
    local db = addon.db and addon.db.profile
    local gf = db and db.groupFrames
    local ha = gf and gf.auraTracking
    return (ha and ha.animDurationMode) or "shrink"
end

--------------------------------------------------------------------------------
-- Animation Definition Registry
--------------------------------------------------------------------------------

local animDefs = {}
local animOrder = {}  -- ordered array of def ids for picker display

function AE.RegisterAnim(def)
    if not def or not def.id then return end
    animDefs[def.id] = def
    table.insert(animOrder, def.id)
end

function AE.GetDef(animId)
    return animDefs[animId]
end

function AE.GetAllDefs()
    local result = {}
    for _, id in ipairs(animOrder) do
        local def = animDefs[id]
        if def then
            table.insert(result, def)
        end
    end
    return result
end

--------------------------------------------------------------------------------
-- Controller Metatable
--------------------------------------------------------------------------------

local controllerMT = {}
controllerMT.__index = controllerMT

function controllerMT:Configure(animId, size)
    local def = animDefs[animId]
    if not def then return end

    self.animId = animId
    self.size = size or 28
    self.period = def.period or 1.0
    self.progress = 0

    -- Show only the textures this animation needs, hide the rest
    local needed = def.numTextures or 1
    for i = 1, MAX_TEXTURES do
        local tex = self.textures[i]
        if i <= needed then
            tex:SetTexture(WHITE8X8)
            tex:SetRotation(0)
            tex:ClearAllPoints()
            tex:Show()
        else
            tex:Hide()
        end
    end

    -- Size the container frame; center-anchor for easy offset adjustments
    self.frame:SetScale(1)
    self.frame:SetSize(size, size)
    self.frame:ClearAllPoints()
    self.frame:SetPoint("CENTER", self.frame:GetParent(), "CENTER", 0, 0)

    -- Let the definition position its textures
    if def.setup then
        def.setup(self, size)
    end
end

function controllerMT:SetColor(r, g, b, a)
    self.colorR = r or 1
    self.colorG = g or 1
    self.colorB = b or 1
    self.colorA = a or 1
    self.rainbowMode = false

    local def = animDefs[self.animId]
    if def and def.applyColor then
        def.applyColor(self, self.colorR, self.colorG, self.colorB, self.colorA)
    end
end

function controllerMT:SetSize(size)
    if self.size == size then return end
    self.size = size
    self.frame:SetSize(size, size)

    local def = animDefs[self.animId]
    if def and def.setup then
        def.setup(self, size)
    end
end

function controllerMT:Play()
    self.playing = true
    self.frame:Show()
end

function controllerMT:Stop()
    self.playing = false
    self.frame:Hide()
end

--- Wire aura duration data into the controller for animated duration display.
-- @param dObj DurationObject from C_UnitAuras.GetAuraDuration (unused, kept for API compat)
-- @param startTime number fallback start time (expirationTime - duration)
-- @param totalDuration number fallback total duration in seconds
-- @param frameHeight number height of the group frame (cached, for descend/ascend travel distance)
function controllerMT:SetDuration(dObj, startTime, totalDuration, frameHeight)
    self.durationStart = startTime or 0
    self.durationTotal = totalDuration or 0
    self.durationActive = (totalDuration and totalDuration > 0) and true or false
    self.durationFrameHeight = frameHeight or 36
end

function controllerMT:Recycle()
    self.playing = false
    self.animId = nil
    self.progress = 0
    self.rainbowMode = false
    self.colorR, self.colorG, self.colorB, self.colorA = 1, 1, 1, 1

    -- Reset duration visual state
    self.frame:SetScale(1)
    self.frame:Hide()
    self.frame:ClearAllPoints()
    self.durationStart = 0
    self.durationTotal = 0
    self.durationActive = false
    self.durationFrameHeight = 36
    self._durationDirty = false

    for i = 1, MAX_TEXTURES do
        local tex = self.textures[i]
        tex:Hide()
        tex:ClearAllPoints()
        tex:SetRotation(0)
        tex:SetVertexColor(1, 1, 1, 1)
        tex:SetSize(1, 1)
    end
end

--------------------------------------------------------------------------------
-- Controller Creation
--------------------------------------------------------------------------------

local function CreateController()
    local ctrl = setmetatable({}, controllerMT)

    ctrl.frame = CreateFrame("Frame")
    ctrl.frame:SetSize(28, 28)
    ctrl.frame:EnableMouse(false)
    ctrl.frame:Hide()

    ctrl.textures = {}
    for i = 1, MAX_TEXTURES do
        local tex = ctrl.frame:CreateTexture(nil, "OVERLAY", nil, 0)
        tex:SetTexture(WHITE8X8)
        tex:SetSize(1, 1)
        tex:Hide()
        ctrl.textures[i] = tex
    end

    ctrl.animId = nil
    ctrl.progress = 0
    ctrl.period = 1.0
    ctrl.playing = false
    ctrl.size = 28
    ctrl.colorR, ctrl.colorG, ctrl.colorB, ctrl.colorA = 1, 1, 1, 1
    ctrl.rainbowMode = false
    ctrl.rainbowHue = 0

    -- Duration tracking fields
    ctrl.durationStart = 0
    ctrl.durationTotal = 0
    ctrl.durationActive = false
    ctrl.durationFrameHeight = 36
    ctrl._durationDirty = false

    return ctrl
end

--------------------------------------------------------------------------------
-- Controller Pool
--------------------------------------------------------------------------------

local controllerPool = {}

local function PreallocatePool()
    for i = 1, POOL_PREALLOC do
        table.insert(controllerPool, CreateController())
    end
end

--------------------------------------------------------------------------------
-- Shared OnUpdate Engine
--------------------------------------------------------------------------------

local activeControllers = {}  -- owner -> ctrl (not weak-keyed: explicit release required)
local engineFrame = CreateFrame("Frame")
engineFrame:Hide()

engineFrame:SetScript("OnUpdate", function(self, elapsed)
    local hasActive = false
    local durationMode = GetAnimDurationMode()
    local useShrink = (durationMode == "shrink")
    local useDescend = (durationMode == "descend")
    local useAscend = (durationMode == "ascend")
    local needsTime = useShrink or useDescend or useAscend
    local now = needsTime and GetTime() or nil

    for owner, ctrl in pairs(activeControllers) do
        if not ctrl.playing then
            activeControllers[owner] = nil
        else
            hasActive = true
            ctrl.progress = (ctrl.progress + elapsed / ctrl.period) % 1

            local def = animDefs[ctrl.animId]
            if def and def.update then
                def.update(ctrl, ctrl.progress)
            end

            -- Rainbow color mode: cycle hue and apply
            if ctrl.rainbowMode and HA.HSVtoRGB then
                ctrl.rainbowHue = (ctrl.rainbowHue + elapsed / RAINBOW_CYCLE_PERIOD) % 1
                local r, g, b = HA.HSVtoRGB(ctrl.rainbowHue, 0.75, 1)
                if def and def.applyColor then
                    def.applyColor(ctrl, r, g, b, 1)
                end
            end

            -- Duration-based effects
            if ctrl.durationActive and ctrl.durationTotal > 0 and needsTime then
                now = now or GetTime()
                local remaining = (ctrl.durationStart + ctrl.durationTotal) - now
                local ratio = remaining / ctrl.durationTotal
                ratio = math.max(0, math.min(1, ratio))

                if useShrink then
                    -- Scale from 1.0 (full) → SHRINK_MIN_SCALE (expired)
                    local scale = SHRINK_MIN_SCALE + (1 - SHRINK_MIN_SCALE) * ratio
                    ctrl.frame:SetScale(scale)
                    ctrl._durationDirty = true

                elseif useDescend then
                    -- Move downward: 0 offset at full → -frameHeight at expired
                    local yOffset = -(1 - ratio) * ctrl.durationFrameHeight
                    ctrl.frame:ClearAllPoints()
                    ctrl.frame:SetPoint("CENTER", ctrl.frame:GetParent(), "CENTER", 0, yOffset)
                    ctrl._durationDirty = true

                elseif useAscend then
                    -- Move upward: 0 offset at full → +frameHeight at expired
                    local yOffset = (1 - ratio) * ctrl.durationFrameHeight
                    ctrl.frame:ClearAllPoints()
                    ctrl.frame:SetPoint("CENTER", ctrl.frame:GetParent(), "CENTER", 0, yOffset)
                    ctrl._durationDirty = true
                end

            elseif ctrl._durationDirty then
                -- Reset visual state when duration mode changes or no active duration
                ctrl.frame:SetScale(1)
                ctrl.frame:ClearAllPoints()
                ctrl.frame:SetPoint("CENTER", ctrl.frame:GetParent(), "CENTER", 0, 0)
                ctrl._durationDirty = false
            end
        end
    end
    if not hasActive then
        self:Hide()
    end
end)

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function AE.Acquire(owner, parentFrame)
    if not owner or not parentFrame then return nil end

    -- Don't create frames in combat
    local ctrl = table.remove(controllerPool)
    if not ctrl then
        if InCombatLockdown() then return nil end
        ctrl = CreateController()
    end

    ctrl.frame:SetParent(parentFrame)
    ctrl.frame:SetFrameLevel(parentFrame:GetFrameLevel() + 1)
    ctrl.frame:Show()

    activeControllers[owner] = ctrl
    engineFrame:Show()

    return ctrl
end

function AE.Release(owner)
    local ctrl = activeControllers[owner]
    if not ctrl then return end

    ctrl:Stop()
    ctrl:Recycle()
    activeControllers[owner] = nil
    table.insert(controllerPool, ctrl)
end

function AE.GetActive(owner)
    return activeControllers[owner]
end

--------------------------------------------------------------------------------
-- Init
--------------------------------------------------------------------------------

PreallocatePool()
