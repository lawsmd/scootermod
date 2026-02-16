local addonName, addon = ...

-- Tooltip Component: Manages GameTooltip text styling
-- The GameTooltip creates FontStrings dynamically on BOTH sides of each line:
-- - GameTooltipTextLeft1, GameTooltipTextLeft2, etc. (left side)
-- - GameTooltipTextRight1, GameTooltipTextRight2, etc. (right side)
-- TextLeft1/TextRight1 use GameTooltipHeaderText, others use GameTooltipText by default.
--
-- Right-side text is used for sell prices, armor types, weapon speeds, spell ranges/cooldowns, etc.
--
-- Money displays (sell prices) use MoneyFrames with special structure:
-- - GameTooltipMoneyFrame1, GameTooltipMoneyFrame2, etc.
-- - Each has PrefixText ("Sell Price:"), GoldButton.Text, SilverButton.Text, CopperButton.Text
--
-- NOTE: The following are intentionally NOT customized:
-- - Color: Tooltip text is dynamically colored by the game (item quality, spell schools, etc.)
-- - Position: Tooltip layout is static and repositioning text would break the layout
-- - Alignment: alignment requires width expansion which causes infinite
--   growth on spell/ability tooltips that update continuously for cooldowns/charges.
--
-- SUPPORTED CUSTOMIZATIONS:
-- - Font face (family)
-- - Font size
-- - Font style (OUTLINE, THICKOUTLINE, etc.)

local COMPARISON_TOOLTIP_NAMES = {
    ShoppingTooltip1 = true,
    ShoppingTooltip2 = true,
    ItemRefShoppingTooltip1 = true,
    ItemRefShoppingTooltip2 = true,
}

-- Helper: Apply font face/size/style to a FontString
local function ApplyFontSettings(fontString, config, defaultSize)
    if not fontString or not fontString.SetFont then return end

    config = config or {}
    local defaults = {
        size = defaultSize or 14,
        style = "OUTLINE",
        fontFace = "FRIZQT__",
    }

    -- Resolve font face
    local face = addon.ResolveFontFace and addon.ResolveFontFace(config.fontFace or defaults.fontFace)
        or (select(1, _G.GameFontNormal:GetFont()))

    -- Apply font attributes (font face, size, style only)
    local size = tonumber(config.size) or defaults.size
    local style = config.style or defaults.style
    pcall(fontString.SetFont, fontString, face, size, style)
end

local function CleanupTextConfig(cfg)
    if not cfg then return end
    cfg.color = nil
    cfg.offset = nil
    cfg.alignment = nil -- Removed feature (causes infinite tooltip growth)
end

local function ShallowCopyFontConfig(src)
    src = src or {}
    return {
        fontFace = src.fontFace,
        size = src.size,
        style = src.style,
    }
end

local function EnsureNewTooltipTextConfigs(db)
    if not db then return end

    -- Migration: use old Line 2 settings as the initial value for Everything Else.
    if db.textEverythingElse == nil then
        db.textEverythingElse = ShallowCopyFontConfig(db.textLine2 or {
            fontFace = "FRIZQT__",
            size = 12,
            style = "OUTLINE",
        })
    end

    if db.textComparison == nil then
        db.textComparison = {
            fontFace = "FRIZQT__",
            size = 12,
            style = "OUTLINE",
        }
    end

    CleanupTextConfig(db.textTitle)
    CleanupTextConfig(db.textEverythingElse)
    CleanupTextConfig(db.textComparison)
end

local function ApplyGameTooltipText(db)
    -- Title / name line (Left1 and Right1 both use title settings)
    local titleFS = _G["GameTooltipTextLeft1"]
    if titleFS then
        ApplyFontSettings(titleFS, db.textTitle or {}, 14)
    end
    local titleRightFS = _G["GameTooltipTextRight1"]
    if titleRightFS then
        ApplyFontSettings(titleRightFS, db.textTitle or {}, 14)
    end

    -- Everything else: lines 2..N (both Left and Right)
    local cfg = db.textEverythingElse or {}
    local i = 2
    while true do
        local leftFS = _G["GameTooltipTextLeft" .. i]
        local rightFS = _G["GameTooltipTextRight" .. i]
        if not leftFS and not rightFS then break end
        
        if leftFS then
            ApplyFontSettings(leftFS, cfg, 12)
        end
        if rightFS then
            ApplyFontSettings(rightFS, cfg, 12)
        end
        i = i + 1
    end

    -- Money frames: Sell Price and similar money displays
    -- GameTooltip can have multiple money frames (GameTooltipMoneyFrame1, GameTooltipMoneyFrame2, etc.)
    local moneyIdx = 1
    while true do
        local moneyFrame = _G["GameTooltipMoneyFrame" .. moneyIdx]
        if not moneyFrame then break end
        
        -- Style the "Sell Price:" prefix text
        local prefixText = moneyFrame.PrefixText or _G["GameTooltipMoneyFrame" .. moneyIdx .. "PrefixText"]
        if prefixText then
            ApplyFontSettings(prefixText, cfg, 12)
        end
        
        -- Style the gold/silver/copper text (they're ButtonText elements on the denomination buttons)
        if moneyFrame.GoldButton and moneyFrame.GoldButton.Text then
            ApplyFontSettings(moneyFrame.GoldButton.Text, cfg, 12)
        end
        if moneyFrame.SilverButton and moneyFrame.SilverButton.Text then
            ApplyFontSettings(moneyFrame.SilverButton.Text, cfg, 12)
        end
        if moneyFrame.CopperButton and moneyFrame.CopperButton.Text then
            ApplyFontSettings(moneyFrame.CopperButton.Text, cfg, 12)
        end
        
        moneyIdx = moneyIdx + 1
    end
end

local function ApplyComparisonTooltipText(tooltip, db)
    if not tooltip or not tooltip.GetName then return end
    local prefix = tooltip:GetName()
    if not prefix or prefix == "" then return end

    -- Line 1 uses Title settings, lines 2+ use Comparison settings
    local titleCfg = db.textTitle or {}
    local comparisonCfg = db.textComparison or {}
    
    local i = 1
    while true do
        local leftFS = _G[prefix .. "TextLeft" .. i]
        local rightFS = _G[prefix .. "TextRight" .. i]
        if not leftFS and not rightFS then break end
        
        -- Use Title settings for line 1, Comparison settings for everything else
        local cfg = (i == 1) and titleCfg or comparisonCfg
        local defaultSize = (i == 1) and 14 or 12
        
        if leftFS then
            ApplyFontSettings(leftFS, cfg, defaultSize)
        end
        if rightFS then
            ApplyFontSettings(rightFS, cfg, defaultSize)
        end
        i = i + 1
    end

    -- Money frames on comparison tooltips (e.g., ShoppingTooltip1MoneyFrame1)
    local moneyIdx = 1
    while true do
        local moneyFrame = _G[prefix .. "MoneyFrame" .. moneyIdx]
        if not moneyFrame then break end
        
        -- Style the prefix text (e.g., "Sell Price:")
        local prefixText = moneyFrame.PrefixText or _G[prefix .. "MoneyFrame" .. moneyIdx .. "PrefixText"]
        if prefixText then
            ApplyFontSettings(prefixText, comparisonCfg, 12)
        end
        
        -- Style the gold/silver/copper text
        if moneyFrame.GoldButton and moneyFrame.GoldButton.Text then
            ApplyFontSettings(moneyFrame.GoldButton.Text, comparisonCfg, 12)
        end
        if moneyFrame.SilverButton and moneyFrame.SilverButton.Text then
            ApplyFontSettings(moneyFrame.SilverButton.Text, comparisonCfg, 12)
        end
        if moneyFrame.CopperButton and moneyFrame.CopperButton.Text then
            ApplyFontSettings(moneyFrame.CopperButton.Text, comparisonCfg, 12)
        end
        
        moneyIdx = moneyIdx + 1
    end
end

local function ApplyBorderTint(tooltip, db)
    if not tooltip then return end
    local nineSlice = tooltip.NineSlice
    if not nineSlice or not nineSlice.SetBorderColor then return end
    if db.borderTintEnable then
        local c = db.borderTintColor or {1, 1, 1, 1}
        nineSlice:SetBorderColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
    else
        nineSlice:SetBorderColor(1, 1, 1, 1)
    end
end

-- Track whether the TooltipDataProcessor hook has been registered
local tooltipProcessorHooked = false

-- Register the TooltipDataProcessor post-call hook (runs after ALL tooltip data is processed)
local function RegisterTooltipPostProcessor()
    if tooltipProcessorHooked then return end
    if not TooltipDataProcessor or not TooltipDataProcessor.AddTooltipPostCall then
        -- Fallback: TooltipDataProcessor not available (unlikely in retail)
        return false
    end

    tooltipProcessorHooked = true

    -- Register for ALL tooltip types to catch every tooltip update
    TooltipDataProcessor.AddTooltipPostCall(TooltipDataProcessor.AllTypes, function(tooltip, tooltipData)
        local comp = addon.Components and addon.Components.tooltip
        if not comp or not comp.db then return end

        local db = comp.db
        EnsureNewTooltipTextConfigs(db)

        local tooltipName = tooltip and tooltip.GetName and tooltip:GetName()

        if tooltip == GameTooltip then
            ApplyGameTooltipText(db)

            -- Apply class color to player names if enabled
            if db.classColorPlayerNames then
                -- GetUnit() and UnitIsPlayer() can return/receive secret values
                -- Wrap everything in pcall to handle secrets safely
                local ok, _, unitToken = pcall(tooltip.GetUnit, tooltip)
                if ok and unitToken then
                    local isPlayerOk, isPlayer = pcall(UnitIsPlayer, unitToken)
                    if isPlayerOk and isPlayer then
                        local classOk, _, classToken = pcall(UnitClass, unitToken)
                        if classOk and classToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken] then
                            local classColor = RAID_CLASS_COLORS[classToken]
                            local titleFS = _G["GameTooltipTextLeft1"]
                            if titleFS and titleFS.SetTextColor then
                                pcall(titleFS.SetTextColor, titleFS, classColor.r, classColor.g, classColor.b, 1)
                            end
                        end
                    end
                end
            end
        elseif tooltipName and COMPARISON_TOOLTIP_NAMES[tooltipName] then
            ApplyComparisonTooltipText(tooltip, db)
        else
            return
        end

        -- Apply border tint
        ApplyBorderTint(tooltip, db)

        -- Hide health bar if setting is enabled (must be done on every tooltip show)
        if tooltip == GameTooltip and db.hideHealthBar then
            local statusBar = _G["GameTooltipStatusBar"]
            if statusBar then statusBar:Hide() end
            local statusBarTexture = _G["GameTooltipStatusBarTexture"]
            if statusBarTexture then statusBarTexture:Hide() end
        end
    end)

    return true
end

--------------------------------------------------------------------------------
-- Tooltip ID Display System
--------------------------------------------------------------------------------

local tooltipIDsInitialized = false

local function isTooltipIDsEnabled()
    local comp = addon.Components and addon.Components.tooltip
    if not comp or not comp.db then return false end
    return comp.db.showTooltipIDs or false
end

-- ID type labels for display
local ID_LABELS = {
    SpellID = "Spell ID",
    ItemID = "Item ID",
    QuestID = "Quest ID",
    AchievementID = "Achievement ID",
    CurrencyID = "Currency ID",
    ArtifactPowerID = "Artifact Power ID",
    AzeriteEssenceID = "Azerite Essence ID",
    MountID = "Mount ID",
    CompanionPetID = "Pet ID",
    MacroID = "Macro ID",
    EquipmentSetID = "Equipment Set ID",
    VisualID = "Visual ID",
    RecipeID = "Recipe ID",
    NpcID = "NPC ID",
    UnitAuraID = "Aura ID",
    EnchantID = "Enchant ID",
    BonusIDs = "Bonus IDs",
    GemIDs = "Gem IDs",
    SetID = "Set ID",
    ExpansionID = "Expansion ID",
}

-- Map Blizzard TooltipDataType enums to our kind strings
local TOOLTIP_DATA_TYPE_MAP = {}
local function buildTooltipDataTypeMap()
    if not Enum or not Enum.TooltipDataType then return end
    local mapping = {
        [Enum.TooltipDataType.Spell] = "SpellID",
        [Enum.TooltipDataType.Item] = "ItemID",
        [Enum.TooltipDataType.Quest] = "QuestID",
        [Enum.TooltipDataType.Achievement] = "AchievementID",
        [Enum.TooltipDataType.Currency] = "CurrencyID",
        [Enum.TooltipDataType.Mount] = "MountID",
        [Enum.TooltipDataType.CompanionPet] = "CompanionPetID",
        [Enum.TooltipDataType.EquipmentSet] = "EquipmentSetID",
        [Enum.TooltipDataType.RecipeRankInfo] = "RecipeID",
        [Enum.TooltipDataType.UnitAura] = "UnitAuraID",
    }
    for k, v in pairs(mapping) do
        TOOLTIP_DATA_TYPE_MAP[k] = v
    end
end

-- Re-entrancy guard: AddDoubleLine can trigger another data processor cycle,
-- which would wipe+re-add in an infinite loop. This flag prevents that.
local isAddingIDs = false

-- Dedup within a single processor pass (prevents same ID appearing twice)
local addedLines = {}

local function addIDLine(tooltip, id, kind)
    if not tooltip or not id or not kind then return end
    if not tooltip.AddDoubleLine then return end

    -- Guard against secret values
    if issecurevalue and issecurevalue(id) then return end
    if issecretvalue and issecretvalue(id) then return end

    -- Dedup: don't add the same kind+id twice within one pass
    local dedupKey = kind .. ":" .. tostring(id)
    if addedLines[dedupKey] then return end
    addedLines[dedupKey] = true

    local label = ID_LABELS[kind] or kind
    pcall(tooltip.AddDoubleLine, tooltip, label .. ":", tostring(id), 0.5, 0.5, 1.0, 1, 1, 1)
end

-- Parse item link for extra detail IDs
local function addItemDetailIDs(tooltip, itemLink)
    if not itemLink or type(itemLink) ~= "string" then return end

    -- Item link format: |Hitem:itemID:enchantID:gem1:gem2:gem3:gem4:suffixID:uniqueID:level:specID:upgradeTypeID:instanceDifficultyID:numBonusIDs:bonusID1:bonusID2:...|h
    local linkData = itemLink:match("|Hitem:([^|]+)|h")
    if not linkData then return end

    local parts = {}
    for part in linkData:gmatch("[^:]*") do
        parts[#parts + 1] = part
    end

    -- parts[1] = itemID (already shown), parts[2] = enchantID
    local enchantID = tonumber(parts[2])
    if enchantID and enchantID > 0 then
        addIDLine(tooltip, enchantID, "EnchantID")
    end

    -- parts[3..6] = gem IDs
    local gems = {}
    for i = 3, 6 do
        local gemID = tonumber(parts[i])
        if gemID and gemID > 0 then
            gems[#gems + 1] = tostring(gemID)
        end
    end
    if #gems > 0 then
        addIDLine(tooltip, table.concat(gems, ", "), "GemIDs")
    end

    -- parts[13] = numBonusIDs, parts[14..] = bonus IDs
    local numBonus = tonumber(parts[13])
    if numBonus and numBonus > 0 then
        local bonuses = {}
        for i = 14, 13 + numBonus do
            if parts[i] and parts[i] ~= "" then
                bonuses[#bonuses + 1] = parts[i]
            end
        end
        if #bonuses > 0 then
            addIDLine(tooltip, table.concat(bonuses, ", "), "BonusIDs")
        end
    end
end

local function InitTooltipIDs()
    if tooltipIDsInitialized then return end
    tooltipIDsInitialized = true

    buildTooltipDataTypeMap()

    -- Main data processor hook: catches spells, items, quests, achievements, etc.
    -- Uses re-entrancy guard: each time Blizzard re-processes tooltip data (e.g.
    -- spells with cooldowns refresh continuously), the tooltip lines are rebuilt
    -- from scratch. We wipe dedup and re-add IDs on every non-reentrant call.
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
        TooltipDataProcessor.AddTooltipPostCall(TooltipDataProcessor.AllTypes, function(tooltip, data)
            if not isTooltipIDsEnabled() then return end
            if not data then return end
            -- Re-entrancy guard: AddDoubleLine may trigger another processor cycle
            if isAddingIDs then return end
            isAddingIDs = true
            -- Wipe dedup so IDs are re-added after Blizzard rebuilds tooltip lines
            -- (spells with cooldowns/charges refresh continuously)
            wipe(addedLines)

            local kind = TOOLTIP_DATA_TYPE_MAP[data.type]
            local id = data.id

            if kind and id then
                addIDLine(tooltip, id, kind)

                -- For items, also extract detail IDs from the hyperlink
                if kind == "ItemID" and data.hyperlink then
                    addItemDetailIDs(tooltip, data.hyperlink)
                end
            end

            -- For unit tooltips, extract NPC ID from GUID
            if data.type == (Enum.TooltipDataType.Unit or -1) then
                local ok, _, unitToken = pcall(tooltip.GetUnit, tooltip)
                if ok and unitToken then
                    local guidOk, guid = pcall(UnitGUID, unitToken)
                    if guidOk and guid and type(guid) == "string" then
                        local npcID = guid:match("Creature%-.-%-.-%-.-%-.-%-(%d+)")
                        if npcID then
                            addIDLine(tooltip, tonumber(npcID), "NpcID")
                        end
                    end
                end
            end

            isAddingIDs = false
        end)
    end

    -- Hook SetAction for action bar spell/item IDs
    if GameTooltip and GameTooltip.SetAction then
        hooksecurefunc(GameTooltip, "SetAction", function(tooltip, actionSlot)
            if not isTooltipIDsEnabled() then return end
            if not actionSlot then return end

            local ok, actionType, id = pcall(GetActionInfo, actionSlot)
            if ok and id then
                if actionType == "spell" then
                    addIDLine(tooltip, id, "SpellID")
                elseif actionType == "item" then
                    addIDLine(tooltip, id, "ItemID")
                elseif actionType == "macro" then
                    addIDLine(tooltip, id, "MacroID")
                end
            end
        end)
    end

    -- Hook SetHyperlink for linked items/spells in chat
    if GameTooltip and GameTooltip.SetHyperlink then
        hooksecurefunc(GameTooltip, "SetHyperlink", function(tooltip, hyperlink)
            if not isTooltipIDsEnabled() then return end
            if not hyperlink or type(hyperlink) ~= "string" then return end

            local kind, id = hyperlink:match("(%a+):(%d+)")
            if kind and id then
                id = tonumber(id)
                if kind == "spell" then
                    addIDLine(tooltip, id, "SpellID")
                elseif kind == "item" then
                    addIDLine(tooltip, id, "ItemID")
                    addItemDetailIDs(tooltip, hyperlink)
                elseif kind == "quest" then
                    addIDLine(tooltip, id, "QuestID")
                elseif kind == "achievement" then
                    addIDLine(tooltip, id, "AchievementID")
                elseif kind == "currency" then
                    addIDLine(tooltip, id, "CurrencyID")
                end
            end
        end)
    end

    -- Hook ItemRefTooltip for shift-clicked links
    if ItemRefTooltip and ItemRefTooltip.SetHyperlink then
        hooksecurefunc(ItemRefTooltip, "SetHyperlink", function(tooltip, hyperlink)
            if not isTooltipIDsEnabled() then return end
            if not hyperlink or type(hyperlink) ~= "string" then return end

            local kind, id = hyperlink:match("(%a+):(%d+)")
            if kind and id then
                id = tonumber(id)
                if kind == "spell" then
                    addIDLine(tooltip, id, "SpellID")
                elseif kind == "item" then
                    addIDLine(tooltip, id, "ItemID")
                    addItemDetailIDs(tooltip, hyperlink)
                elseif kind == "quest" then
                    addIDLine(tooltip, id, "QuestID")
                elseif kind == "achievement" then
                    addIDLine(tooltip, id, "AchievementID")
                elseif kind == "currency" then
                    addIDLine(tooltip, id, "CurrencyID")
                end
            end
        end)
    end

end

local function ApplyTooltipStyling(self)
    local tooltip = _G["GameTooltip"]
    if not tooltip then return end

    local db = self.db or {}

    EnsureNewTooltipTextConfigs(db)

    -- Ensure TooltipDataProcessor hook is registered
    RegisterTooltipPostProcessor()

    -- Initialize tooltip ID system (lazy, one-time)
    InitTooltipIDs()

    -- Apply styling to any already-built tooltip lines
    ApplyGameTooltipText(db)
    ApplyComparisonTooltipText(_G["ShoppingTooltip1"], db)
    ApplyComparisonTooltipText(_G["ShoppingTooltip2"], db)
    ApplyComparisonTooltipText(_G["ItemRefShoppingTooltip1"], db)
    ApplyComparisonTooltipText(_G["ItemRefShoppingTooltip2"], db)

    -- Apply border tint
    ApplyBorderTint(tooltip, db)
    ApplyBorderTint(_G["ShoppingTooltip1"], db)
    ApplyBorderTint(_G["ShoppingTooltip2"], db)
    ApplyBorderTint(_G["ItemRefShoppingTooltip1"], db)
    ApplyBorderTint(_G["ItemRefShoppingTooltip2"], db)

    -- Apply visibility settings: Hide/Show GameTooltipStatusBar (health bar)
    local statusBar = _G["GameTooltipStatusBar"]
    if statusBar then
        if db.hideHealthBar then
            statusBar:Hide()
        else
            statusBar:Show()
        end
    end
    -- Also hide/show the status bar texture (child element)
    local statusBarTexture = _G["GameTooltipStatusBarTexture"]
    if statusBarTexture then
        if db.hideHealthBar then
            statusBarTexture:Hide()
        else
            statusBarTexture:Show()
        end
    end

    -- Apply tooltip scale
    local scale = db.tooltipScale or 1.0
    if tooltip.SetScale then
        tooltip:SetScale(scale)
    end
    -- Also scale comparison tooltips
    for tooltipName in pairs(COMPARISON_TOOLTIP_NAMES) do
        local compTooltip = _G[tooltipName]
        if compTooltip and compTooltip.SetScale then
            compTooltip:SetScale(scale)
        end
    end
end

addon:RegisterComponentInitializer(function(self)
    local Component = addon.ComponentPrototype

    local tooltipComponent = Component:New({
        id = "tooltip",
        name = "Tooltip",
        frameName = "GameTooltip",
        settings = {
            -- Name & Title settings (line 1 on GameTooltip)
            textTitle = { type = "addon", default = {
                fontFace = "FRIZQT__",
                size = 14,
                style = "OUTLINE",
            }, ui = { hidden = true }},

            -- Everything Else settings (lines 2..N on GameTooltip)
            textEverythingElse = { type = "addon", default = {
                fontFace = "FRIZQT__",
                size = 12,
                style = "OUTLINE",
            }, ui = { hidden = true }},

            -- Comparison Tooltips settings (ShoppingTooltip1/2 + ItemRefShoppingTooltip1/2)
            textComparison = { type = "addon", default = {
                fontFace = "FRIZQT__",
                size = 12,
                style = "OUTLINE",
            }, ui = { hidden = true }},

            -- Visibility settings
            hideHealthBar = { type = "addon", default = false, ui = {
                label = "Hide Tooltip Health Bar", widget = "checkbox", section = "Visibility", order = 1
            }},

            -- Class color settings
            classColorPlayerNames = { type = "addon", default = false },

            -- Tooltip scale setting
            tooltipScale = { type = "addon", default = 1.0 },

            -- Border tint settings
            borderTintEnable = { type = "addon", default = false },
            borderTintColor = { type = "addon", default = {1, 1, 1, 1} },

            -- Tooltip IDs
            showTooltipIDs = { type = "addon", default = false },

            -- Marker for enabling Text section in generic renderer
            supportsText = { type = "addon", default = true },
        },
        ApplyStyling = ApplyTooltipStyling,
    })

    self:RegisterComponent(tooltipComponent)
end)
