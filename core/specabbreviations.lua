-- specabbreviations.lua - Spec name to abbreviation mapping
local _, addon = ...

addon.SPEC_ABBREVIATIONS = {
    -- Death Knight
    ["Blood"]           = "BLOOD",
    ["Frost"]           = "FROST",
    ["Unholy"]          = "UNHLY",
    -- Demon Hunter
    ["Havoc"]           = "HAVOC",
    ["Vengeance"]       = "VENG",
    -- Druid
    ["Balance"]         = "BAL",
    ["Feral"]           = "FERAL",
    ["Guardian"]        = "GUARD",
    ["Restoration"]     = "RESTO",
    -- Evoker
    ["Augmentation"]    = "AUG",
    ["Devastation"]     = "DEVAS",
    ["Preservation"]    = "PRES",
    -- Hunter
    ["Beast Mastery"]   = "BM",
    ["Marksmanship"]    = "MM",
    ["Survival"]        = "SURV",
    -- Mage
    ["Arcane"]          = "ARC",
    ["Fire"]            = "FIRE",
    -- (Frost shared with DK)
    -- Monk
    ["Brewmaster"]      = "BREW",
    ["Mistweaver"]      = "MISTW",
    ["Windwalker"]      = "WW",
    -- Paladin
    ["Holy"]            = "HOLY",
    ["Protection"]      = "PROT",
    ["Retribution"]     = "RET",
    -- Priest
    ["Discipline"]      = "DISC",
    -- (Holy shared with Paladin)
    ["Shadow"]          = "SHDW",
    -- Rogue
    ["Assassination"]   = "ASSN",
    ["Outlaw"]          = "OUTLW",
    ["Subtlety"]        = "SUB",
    -- Shaman
    ["Elemental"]       = "ELE",
    ["Enhancement"]     = "ENH",
    -- (Restoration shared with Druid)
    -- Warlock
    ["Affliction"]      = "AFFL",
    ["Demonology"]      = "DEMO",
    ["Destruction"]     = "DESTR",
    -- Warrior
    ["Arms"]            = "ARMS",
    ["Fury"]            = "FURY",
    -- (Protection shared with Paladin)
}
