local addonName, addon = ...

--------------------------------------------------------------------------------
-- Damage Meter V2 — Namespace, Component Registration, DB Structure
--------------------------------------------------------------------------------

addon.DamageMetersV2 = {}
local DM2 = addon.DamageMetersV2

DM2.MAX_WINDOWS = 5
DM2.MAX_COLUMNS = 5
DM2.MAX_POOL = 25

-- Runtime state (not persisted)
DM2._windows = {}       -- [1..5] = { frame, barRows, localPlayerRow, ... }
DM2._comp = nil          -- Component reference (set during registration)
DM2._initialized = false
DM2._inCombat = false
DM2._combatStartTime = 0
DM2._preCombatDuration = 0 -- duration before current combat started

-- Debug trace buffer
DM2._traceLog = {}
DM2._traceEnabled = false -- enable with /scoot debug dmv2 trace on

function DM2._Trace(msg)
    if not DM2._traceEnabled then return end
    local ts = string.format("%.1f", GetTime() % 1000)
    table.insert(DM2._traceLog, ts .. " " .. msg)
    -- Cap at 200 entries
    if #DM2._traceLog > 200 then
        table.remove(DM2._traceLog, 1)
    end
end

function addon.DebugDMV2Trace()
    if #DM2._traceLog == 0 then
        addon.DebugShowWindow("DMV2 Trace", "No trace entries. Fight something first.")
        return
    end
    addon.DebugShowWindow("DMV2 Trace", table.concat(DM2._traceLog, "\n"))
end

--------------------------------------------------------------------------------
-- Per-Window DB
--------------------------------------------------------------------------------

local WINDOW_DEFAULTS = {
    [1] = { enabled = true,  sessionType = 0, columns = { { format = "dps" } }, frameWidth = 350, frameHeight = 250, windowScale = 1.0 },
    [2] = { enabled = false, sessionType = 1, columns = { { format = "dps" } }, frameWidth = 350, frameHeight = 250, windowScale = 1.0 },
    [3] = { enabled = false, sessionType = 1, columns = { { format = "dps" } }, frameWidth = 350, frameHeight = 250, windowScale = 1.0 },
    [4] = { enabled = false, sessionType = 1, columns = { { format = "dps" } }, frameWidth = 350, frameHeight = 250, windowScale = 1.0 },
    [5] = { enabled = false, sessionType = 1, columns = { { format = "dps" } }, frameWidth = 350, frameHeight = 250, windowScale = 1.0 },
}

function DM2._EnsureWindowsDB()
    local profile = addon.db and addon.db.profile
    if not profile then return nil end
    if not profile.damageMeterV2Windows then
        profile.damageMeterV2Windows = {}
    end
    local wins = profile.damageMeterV2Windows
    for i = 1, DM2.MAX_WINDOWS do
        if not wins[i] then
            local def = WINDOW_DEFAULTS[i]
            wins[i] = {
                enabled = def.enabled,
                sessionType = def.sessionType,
                columns = {},
            }
            for j, col in ipairs(def.columns) do
                wins[i].columns[j] = { format = col.format }
            end
        end
        if not wins[i].columns or #wins[i].columns == 0 then
            wins[i].columns = { { format = "dps" } }
        end
        -- Ensure per-window sizing fields exist
        if not wins[i].frameWidth then wins[i].frameWidth = WINDOW_DEFAULTS[i].frameWidth end
        if not wins[i].frameHeight then wins[i].frameHeight = WINDOW_DEFAULTS[i].frameHeight end
        if not wins[i].windowScale then wins[i].windowScale = WINDOW_DEFAULTS[i].windowScale end
    end
    return wins
end

function DM2._GetWindowConfig(windowIndex)
    local wins = DM2._EnsureWindowsDB()
    return wins and wins[windowIndex]
end

--------------------------------------------------------------------------------
-- Component Registration
--------------------------------------------------------------------------------

addon:RegisterComponentInitializer(function(self)
    -- Gate: only register if V2 sub-toggle is enabled
    if not self:IsModuleEnabled("damageMeter", "damageMeterV2") then return end

    -- When V2 is active, ensure V1 sub-toggle is disabled.
    -- This handles the case where moduleEnabled.damageMeter is still a boolean
    -- (existing profiles before sub-toggles were added).
    if self.SetModuleEnabled then
        self:SetModuleEnabled("damageMeter", "damageMeter", false)
    end

    -- Pre-materialize component DB so the proxy system doesn't skip ApplyStyling.
    if self.db and self.db.profile then
        if not self.db.profile.components then
            self.db.profile.components = {}
        end
        if not self.db.profile.components["damageMeterV2"] then
            self.db.profile.components["damageMeterV2"] = {}
        end
    end

    local Component = addon.ComponentPrototype

    local comp = Component:New({
        id = "damageMeterV2",
        name = "Damage Meter V2",
        settings = {
            -- Layout
            windowScale     = { type = "addon", default = 1.0 },
            frameWidth      = { type = "addon", default = 350 },
            frameHeight     = { type = "addon", default = 250 },
            barHeight       = { type = "addon", default = 22 },
            barSpacing      = { type = "addon", default = 2 },

            -- Bars
            barTexture              = { type = "addon", default = "default" },
            barForegroundColorMode  = { type = "addon", default = "class" },
            barCustomColor          = { type = "addon", default = { 0.8, 0.7, 0.2, 1 } },
            barBackgroundColor      = { type = "addon", default = { 0.1, 0.1, 0.1, 0.8 } },
            barBorderStyle          = { type = "addon", default = "none" },
            barBorderTintEnable     = { type = "addon", default = false },
            barBorderTintColor      = { type = "addon", default = { 0, 0, 0, 1 } },
            barBorderThickness      = { type = "addon", default = 1 },
            barBorderInsetH         = { type = "addon", default = 0 },
            barBorderInsetV         = { type = "addon", default = 0 },
            showBars                = { type = "addon", default = true },
            hideRankNumbers         = { type = "addon", default = false },
            barBgTexture            = { type = "addon", default = "default" },
            barBgColorMode          = { type = "addon", default = "default" },
            barBgCustomColor        = { type = "addon", default = { 0.1, 0.1, 0.1, 0.8 } },
            barBackgroundOpacity    = { type = "addon", default = 80 },

            -- Icons
            showIcons           = { type = "addon", default = true },
            iconStyle           = { type = "addon", default = "default" }, -- "default" or JI style key
            jiberishIconsEnabled = { type = "addon", default = false },

            -- Text: Names
            textNames = { type = "addon", default = {
                fontFace = "ROBOTO_SEMICOND_BOLD", fontStyle = "OUTLINE", fontSize = 12,
                colorMode = "default", color = { 1, 1, 1, 1 },
            }},
            -- Text: Values
            textValues = { type = "addon", default = {
                fontFace = "ROBOTO_SEMICOND_BOLD", fontStyle = "OUTLINE", fontSize = 11,
                colorMode = "default", color = { 1, 1, 1, 1 },
            }},
            -- Text: Title
            textTitle = { type = "addon", default = {
                fontFace = "ROBOTO_SEMICOND_BOLD", fontStyle = "OUTLINE", fontSize = 13,
                colorMode = "default", color = { 1, 1, 1, 1 },
            }},
            -- Text: Timer
            textTimer = { type = "addon", default = {
                fontFace = "ROBOTO_SEMICOND_BOLD", fontStyle = "OUTLINE", fontSize = 13,
                colorMode = "default", color = { 1.0, 0.82, 0, 1 },
            }},
            -- Vertical title mode
            verticalTitleMode = { type = "addon", default = false },
            -- Text: Column Headers
            textHeaders = { type = "addon", default = {
                fontFace = "ROBOTO_SEMICOND_BOLD", fontStyle = "OUTLINE", fontSize = 10,
                colorMode = "default", color = { 0.8, 0.8, 0.8, 1 },
            }},

            -- Window
            showBackdrop            = { type = "addon", default = true },
            windowBackdropColor     = { type = "addon", default = { 0.06, 0.06, 0.08, 0.95 } },
            windowBackdropTexture   = { type = "addon", default = "solid" },
            windowBorderStyle       = { type = "addon", default = "none" },
            windowBorderColor       = { type = "addon", default = { 0, 0, 0, 1 } },
            windowBorderThickness   = { type = "addon", default = 1 },

            -- Visibility / Opacity
            opacity             = { type = "addon", default = 100 },
            opacityOutOfCombat  = { type = "addon", default = 100 },
            visibility          = { type = "addon", default = "always" },
            showLocalPlayer     = { type = "addon", default = true },

            -- QoL
            updateThrottle  = { type = "addon", default = 1.0 },
            autoResetData   = { type = "addon", default = "off" },
            autoResetPrompt = { type = "addon", default = true },

            -- Export
            exportEnabled       = { type = "addon", default = false },
            exportChatChannel   = { type = "addon", default = "PARTY" },
            exportChatLineCount = { type = "addon", default = 5 },

            -- Title
            titleMode           = { type = "addon", default = "auto" },
            customTitle         = { type = "addon", default = "" },
            showTitleBarBackdrop = { type = "addon", default = true },
        },

        ApplyStyling = function(self)
            DM2._ApplyStyling(self)
        end,

        RefreshOpacity = function(self)
            DM2._RefreshOpacity(self)
        end,
    })

    self:RegisterComponent(comp)
    DM2._comp = comp

    -- Bootstrap V2 on first PLAYER_ENTERING_WORLD.
    -- The component system's ApplyStyling gate may skip us (proxy/zero-touch),
    -- so we self-bootstrap after DB linking is complete.
    local bootstrapFrame = CreateFrame("Frame")
    bootstrapFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    bootstrapFrame:SetScript("OnEvent", function(f)
        f:UnregisterAllEvents()
        if comp.db then
            DM2._ApplyStyling(comp)
        end
    end)
end, "damageMeter")

--------------------------------------------------------------------------------
-- ApplyStyling / RefreshOpacity
--------------------------------------------------------------------------------

function DM2._ApplyStyling(comp)
    -- Initialize frames on first styling pass
    if not DM2._initialized then
        DM2._Initialize(comp)
    end

    -- Disable Blizzard meter via CVar when V2 is active
    if C_CVar and C_CVar.SetCVar and not InCombatLockdown() then
        pcall(C_CVar.SetCVar, "damageMeterEnabled", "0")
    end

    -- Show/hide and style each window
    for i = 1, DM2.MAX_WINDOWS do
        DM2._UpdateVisibility(i, comp)
        local win = DM2._windows[i]
        if win and win.frame:IsShown() then
            DM2._ApplyFullStyling(i, comp)
            DM2._UpdateSessionHeader(i, comp)
        end
    end

    -- Trigger a full data refresh
    if not DM2._inCombat then
        DM2._FullRefreshAllWindows()
    end

    -- Refresh opacity
    DM2._RefreshOpacity(comp)
end

function DM2._RefreshOpacity(comp)
    if not DM2._initialized then return end
    local db = comp.db
    local inCombat = InCombatLockdown()
    local alpha
    if inCombat then
        alpha = math.max(0.50, math.min(1.0, (tonumber(db.opacity) or 100) / 100))
    else
        alpha = math.max(0, math.min(1.0, (tonumber(db.opacityOutOfCombat) or 100) / 100))
    end
    for i = 1, DM2.MAX_WINDOWS do
        local win = DM2._windows[i]
        if win and win.frame:IsShown() then
            win.frame:SetAlpha(alpha)
        end
    end

    -- Update visibility for combat-based modes
    for i = 1, DM2.MAX_WINDOWS do
        DM2._UpdateVisibility(i, comp)
    end
end

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------

function DM2._Initialize(comp)
    if DM2._initialized then return end
    DM2._initialized = true

    DM2._EnsureWindowsDB()

    -- Create all window frames
    for i = 1, DM2.MAX_WINDOWS do
        DM2._CreateWindow(i, comp)
    end

    -- Initialize event handling
    DM2._InitializeEvents(comp)

    -- Initialize Edit Mode positioning
    DM2._InitializeEditMode()
end

--------------------------------------------------------------------------------
-- Session Labels
--------------------------------------------------------------------------------

local SESSION_LABELS = {
    [0] = "Overall",
    [1] = "Current",
    [2] = "Expired",
}

function DM2._GetSessionLabel(sessionType)
    return SESSION_LABELS[sessionType] or "Unknown"
end
