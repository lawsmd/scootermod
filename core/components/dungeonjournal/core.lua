-- dungeonjournal/core.lua - Per-character ledger of received loot, surfaced as
-- left-side checkboxes on Encounter Journal loot rows. Char-scope storage
-- persists across profile switches. The feature's only enable gate is the
-- emphasized toggle on the QoL > Dungeon Journal settings page (see
-- DungeonJournalRenderer.lua); this overlay never writes to Blizzard frames,
-- so the module-toggle layer in core/modules.lua isn't required here.
local addonName, addon = ...

addon.DungeonJournal = addon.DungeonJournal or {}
local DJ = addon.DungeonJournal

--------------------------------------------------------------------------------
-- Char-scope ledger
--------------------------------------------------------------------------------

-- AceDB char scope is keyed on "<character> - <realm>" and is independent of
-- the active profile. Switching profiles on the same character preserves marks.
function DJ.EnsureCharDB()
    local db = addon.db
    if not db or not db.char then return nil end
    if not rawget(db.char, "dungeonJournal") then
        db.char.dungeonJournal = { receivedLoot = {} }
    elseif not rawget(db.char.dungeonJournal, "receivedLoot") then
        db.char.dungeonJournal.receivedLoot = {}
    end
    return db.char.dungeonJournal
end

local function getLedger()
    local cdb = DJ.EnsureCharDB()
    return cdb and cdb.receivedLoot or nil
end

--------------------------------------------------------------------------------
-- Master enable accessor — read-only (zero-touch: do not materialize qol{}).
-- The settings renderer is the only writer; it materializes lazily on toggle.
--------------------------------------------------------------------------------

function DJ.IsEnabled()
    local profile = addon.db and addon.db.profile
    if not profile then return false end
    local qol = rawget(profile, "qol")
    if not qol then return false end
    return rawget(qol, "dungeonJournalEnabled") == true
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function DJ.IsItemChecked(itemID)
    if type(itemID) ~= "number" then return false end
    local l = getLedger()
    return l and l[itemID] ~= nil or false
end

function DJ.MarkItem(itemID)
    if type(itemID) ~= "number" then return end
    local l = getLedger()
    if not l then return end
    l[itemID] = time()
    if DJ.RefreshAllVisible then DJ.RefreshAllVisible() end
end

function DJ.UnmarkItem(itemID)
    if type(itemID) ~= "number" then return end
    local l = getLedger()
    if not l then return end
    l[itemID] = nil
    if DJ.RefreshAllVisible then DJ.RefreshAllVisible() end
end

function DJ.ResetAllMarks()
    local cdb = DJ.EnsureCharDB()
    if not cdb then return end
    cdb.receivedLoot = {}
    if DJ.RefreshAllVisible then DJ.RefreshAllVisible() end
end

function DJ.CountMarks()
    local l = getLedger()
    if not l then return 0 end
    local n = 0
    for _ in pairs(l) do n = n + 1 end
    return n
end
