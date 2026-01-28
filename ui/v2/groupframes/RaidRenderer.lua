-- RaidRenderer.lua - Raid Frames TUI renderer
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.GroupFrames = addon.UI.GroupFrames or {}
local GF = addon.UI.GroupFrames
local SettingsBuilder = addon.UI.SettingsBuilder

local COMPONENT_ID = "gfRaid"

--------------------------------------------------------------------------------
-- Database Access
--------------------------------------------------------------------------------

local function ensureDB()
    return GF.ensureRaidDB()
end

local function ensureTextDB(key)
    return GF.ensureRaidTextDB(key)
end

--------------------------------------------------------------------------------
-- Apply Functions
--------------------------------------------------------------------------------

local function applyStyles()
    GF.applyRaidStyles()
end

local function applyText()
    GF.applyRaidText()
end

--------------------------------------------------------------------------------
-- Edit Mode Helpers
--------------------------------------------------------------------------------

local function getRaidFrame()
    return GF.getRaidFrame()
end

local function getEditModeSetting(settingId)
    local frame = getRaidFrame()
    return GF.getEditModeSetting(frame, settingId)
end

local function setEditModeSetting(settingId, value, options)
    local frame = getRaidFrame()
    GF.setEditModeSetting(frame, settingId, value, options)
end

--------------------------------------------------------------------------------
-- Shared Tab Builders
--------------------------------------------------------------------------------

local function buildStyleTab(inner, barPrefix, applyFn)
    -- Foreground Texture
    inner:AddBarTextureSelector({
        label = "Foreground Texture",
        get = function()
            local t = ensureDB() or {}
            return t[barPrefix .. "Texture"] or "default"
        end,
        set = function(v)
            local t = ensureDB()
            if not t then return end
            t[barPrefix .. "Texture"] = v or "default"
            applyFn()
        end,
    })

    -- Foreground Color
    inner:AddSelectorColorPicker({
        label = "Foreground Color",
        values = GF.healthColorValues,
        order = GF.healthColorOrder,
        get = function()
            local t = ensureDB() or {}
            return t[barPrefix .. "ColorMode"] or "default"
        end,
        set = function(v)
            local t = ensureDB()
            if not t then return end
            t[barPrefix .. "ColorMode"] = v or "default"
            applyFn()
        end,
        getColor = function()
            local t = ensureDB() or {}
            local c = t[barPrefix .. "Tint"] or {1, 1, 1, 1}
            return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
        end,
        setColor = function(r, g, b, a)
            local t = ensureDB()
            if not t then return end
            t[barPrefix .. "Tint"] = {r or 1, g or 1, b or 1, a or 1}
            applyFn()
        end,
        customValue = "custom",
        hasAlpha = true,
    })

    inner:AddSpacer(8)

    -- Background Texture
    inner:AddBarTextureSelector({
        label = "Background Texture",
        get = function()
            local t = ensureDB() or {}
            return t[barPrefix .. "BackgroundTexture"] or "default"
        end,
        set = function(v)
            local t = ensureDB()
            if not t then return end
            t[barPrefix .. "BackgroundTexture"] = v or "default"
            applyFn()
        end,
    })

    -- Background Color
    inner:AddSelectorColorPicker({
        label = "Background Color",
        values = GF.bgColorValues,
        order = GF.bgColorOrder,
        get = function()
            local t = ensureDB() or {}
            return t[barPrefix .. "BackgroundColorMode"] or "default"
        end,
        set = function(v)
            local t = ensureDB()
            if not t then return end
            t[barPrefix .. "BackgroundColorMode"] = v or "default"
            applyFn()
        end,
        getColor = function()
            local t = ensureDB() or {}
            local c = t[barPrefix .. "BackgroundTint"] or {0, 0, 0, 1}
            return c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1
        end,
        setColor = function(r, g, b, a)
            local t = ensureDB()
            if not t then return end
            t[barPrefix .. "BackgroundTint"] = {r or 0, g or 0, b or 0, a or 1}
            applyFn()
        end,
        customValue = "custom",
        hasAlpha = true,
    })

    -- Background Opacity
    inner:AddSlider({
        label = "Background Opacity",
        min = 0,
        max = 100,
        step = 1,
        get = function()
            local t = ensureDB() or {}
            return tonumber(t[barPrefix .. "BackgroundOpacity"]) or 50
        end,
        set = function(v)
            local t = ensureDB()
            if not t then return end
            t[barPrefix .. "BackgroundOpacity"] = tonumber(v) or 50
            applyFn()
        end,
    })

    inner:Finalize()
end

local function buildTextTab(inner, textKey, applyFn)
    -- Font
    inner:AddFontSelector({
        label = "Font",
        get = function()
            local s = ensureTextDB(textKey) or {}
            return s.fontFace or "FRIZQT__"
        end,
        set = function(v)
            local t = ensureDB()
            if not t then return end
            t[textKey] = t[textKey] or {}
            t[textKey].fontFace = v
            applyFn()
        end,
    })

    -- Style
    inner:AddSelector({
        label = "Style",
        values = GF.fontStyleValues,
        order = GF.fontStyleOrder,
        get = function()
            local s = ensureTextDB(textKey) or {}
            return s.style or "OUTLINE"
        end,
        set = function(v)
            local t = ensureDB()
            if not t then return end
            t[textKey] = t[textKey] or {}
            t[textKey].style = v
            applyFn()
        end,
    })

    -- Size
    inner:AddSlider({
        label = "Size",
        min = 6,
        max = 32,
        step = 1,
        get = function()
            local s = ensureTextDB(textKey) or {}
            return tonumber(s.size) or 12
        end,
        set = function(v)
            local t = ensureDB()
            if not t then return end
            t[textKey] = t[textKey] or {}
            t[textKey].size = tonumber(v) or 12
            applyFn()
        end,
    })

    -- Color
    inner:AddSelectorColorPicker({
        label = "Color",
        values = GF.fontColorValues,
        order = GF.fontColorOrder,
        get = function()
            local s = ensureTextDB(textKey) or {}
            return s.colorMode or "default"
        end,
        set = function(v)
            local t = ensureDB()
            if not t then return end
            t[textKey] = t[textKey] or {}
            t[textKey].colorMode = v or "default"
            applyFn()
        end,
        getColor = function()
            local s = ensureTextDB(textKey) or {}
            local c = s.color or {1, 1, 1, 1}
            return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
        end,
        setColor = function(r, g, b, a)
            local t = ensureDB()
            if not t then return end
            t[textKey] = t[textKey] or {}
            t[textKey].color = {r or 1, g or 1, b or 1, a or 1}
            applyFn()
        end,
        customValue = "custom",
        hasAlpha = true,
    })

    -- Alignment (9-way anchor)
    inner:AddSelector({
        label = "Alignment",
        values = GF.anchorValues,
        order = GF.anchorOrder,
        get = function()
            local s = ensureTextDB(textKey) or {}
            return s.anchor or "TOPLEFT"
        end,
        set = function(v)
            local t = ensureDB()
            if not t then return end
            t[textKey] = t[textKey] or {}
            t[textKey].anchor = v or "TOPLEFT"
            applyFn()
        end,
    })

    -- X Offset
    inner:AddSlider({
        label = "Offset X",
        min = -50,
        max = 50,
        step = 1,
        get = function()
            local s = ensureTextDB(textKey) or {}
            local o = s.offset or {}
            return tonumber(o.x) or 0
        end,
        set = function(v)
            local t = ensureDB()
            if not t then return end
            t[textKey] = t[textKey] or {}
            t[textKey].offset = t[textKey].offset or {}
            t[textKey].offset.x = tonumber(v) or 0
            applyFn()
        end,
    })

    -- Y Offset
    inner:AddSlider({
        label = "Offset Y",
        min = -50,
        max = 50,
        step = 1,
        get = function()
            local s = ensureTextDB(textKey) or {}
            local o = s.offset or {}
            return tonumber(o.y) or 0
        end,
        set = function(v)
            local t = ensureDB()
            if not t then return end
            t[textKey] = t[textKey] or {}
            t[textKey].offset = t[textKey].offset or {}
            t[textKey].offset.y = tonumber(v) or 0
            applyFn()
        end,
    })

    inner:Finalize()
end

--------------------------------------------------------------------------------
-- Renderer Function
--------------------------------------------------------------------------------

function GF.RenderRaid(panel, scrollContent)
    -- Clear existing content
    panel:ClearContent()

    -- Create builder
    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    -- Store reference for re-rendering on changes
    builder:SetOnRefresh(function()
        GF.RenderRaid(panel, scrollContent)
    end)

    local EM = _G.Enum and _G.Enum.EditModeUnitFrameSetting
    local RGD = _G.Enum and _G.Enum.RaidGroupDisplayType

    -- Check if we're in Separate or Combine groups mode
    local isSeparateGroups = GF.isRaidSeparateGroups()
    local isCombineGroups = not isSeparateGroups

    ----------------------------------------------------------------------------
    -- Collapsible Section: Positioning & Sorting
    ----------------------------------------------------------------------------

    builder:AddCollapsibleSection({
        title = "Positioning & Sorting",
        componentId = COMPONENT_ID,
        sectionKey = "positioning",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            -- Groups dropdown
            if EM and EM.RaidGroupDisplayType and RGD and #GF.raidGroupsOrder > 0 then
                inner:AddSelector({
                    label = "Groups",
                    values = GF.raidGroupsValues,
                    order = GF.raidGroupsOrder,
                    get = function()
                        return getEditModeSetting(EM.RaidGroupDisplayType) or RGD.SeparateGroupsVertical
                    end,
                    set = function(v)
                        C_Timer.After(0, function()
                            setEditModeSetting(EM.RaidGroupDisplayType, v, {
                                updaters = { "UpdateSystemSettingRaidGroupDisplayType" },
                                suspendDuration = 0.25,
                            })
                            -- Re-render to show/hide conditional controls
                            C_Timer.After(0.3, function()
                                GF.RenderRaid(panel, scrollContent)
                            end)
                        end)
                    end,
                })
            end

            -- Sort By (Combine Groups only)
            if isCombineGroups then
                if EM and EM.SortPlayersBy then
                    inner:AddSelector({
                        label = "Sort By",
                        values = GF.raidSortByValues,
                        order = GF.raidSortByOrder,
                        get = function()
                            return getEditModeSetting(EM.SortPlayersBy) or 0
                        end,
                        set = function(v)
                            C_Timer.After(0, function()
                                setEditModeSetting(EM.SortPlayersBy, v, {
                                    updaters = { "UpdateSystemSettingSortPlayersBy" },
                                    suspendDuration = 0.25,
                                })
                            end)
                        end,
                        infoIcon = GF.TOOLTIPS.sortBy,
                    })
                end

                -- Column Size (Combine Groups only)
                if EM and EM.RowSize then
                    inner:AddSlider({
                        label = "Column Size",
                        description = "Number of frames per row/column.",
                        min = 2,
                        max = 10,
                        step = 1,
                        get = function()
                            return getEditModeSetting(EM.RowSize) or 5
                        end,
                        set = function(v)
                            C_Timer.After(0, function()
                                setEditModeSetting(EM.RowSize, v, {
                                    updaters = { "UpdateSystemSettingRowSize" },
                                    suspendDuration = 0.25,
                                })
                            end)
                        end,
                        infoIcon = GF.TOOLTIPS.columnSize,
                    })
                end
            else
                inner:AddDescription("Sort By and Column Size options are only available when Groups is set to 'Combine Groups'.")
            end

            inner:Finalize()
        end,
    })

    ----------------------------------------------------------------------------
    -- Collapsible Section: Sizing
    ----------------------------------------------------------------------------

    builder:AddCollapsibleSection({
        title = "Sizing",
        componentId = COMPONENT_ID,
        sectionKey = "sizing",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            -- Frame Width
            if EM and EM.FrameWidth then
                inner:AddSlider({
                    label = "Frame Width",
                    min = 72,
                    max = 144,
                    step = 2,
                    get = function()
                        return getEditModeSetting(EM.FrameWidth) or 72
                    end,
                    set = function(v)
                        C_Timer.After(0, function()
                            setEditModeSetting(EM.FrameWidth, v, {
                                updaters = { "UpdateSystemSettingFrameWidth" },
                                suspendDuration = 0.25,
                            })
                        end)
                    end,
                })
            end

            -- Frame Height
            if EM and EM.FrameHeight then
                inner:AddSlider({
                    label = "Frame Height",
                    min = 36,
                    max = 72,
                    step = 2,
                    get = function()
                        return getEditModeSetting(EM.FrameHeight) or 36
                    end,
                    set = function(v)
                        C_Timer.After(0, function()
                            setEditModeSetting(EM.FrameHeight, v, {
                                updaters = { "UpdateSystemSettingFrameHeight" },
                                suspendDuration = 0.25,
                            })
                        end)
                    end,
                })
            end

            inner:Finalize()
        end,
    })

    ----------------------------------------------------------------------------
    -- Collapsible Section: Border (Separate Groups only)
    ----------------------------------------------------------------------------

    builder:AddCollapsibleSection({
        title = "Border",
        componentId = COMPONENT_ID,
        sectionKey = "border",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            if isSeparateGroups then
                if EM and EM.DisplayBorder then
                    inner:AddToggle({
                        label = "Display Border",
                        description = "Shows Blizzard's default border around each raid GROUP.",
                        get = function()
                            local v = getEditModeSetting(EM.DisplayBorder)
                            return v and v ~= 0
                        end,
                        set = function(v)
                            C_Timer.After(0, function()
                                setEditModeSetting(EM.DisplayBorder, v and 1 or 0, {
                                    updaters = { "UpdateSystemSettingDisplayBorder" },
                                    suspendDuration = 0.25,
                                })
                            end)
                        end,
                        infoIcon = GF.TOOLTIPS.displayBorderRaid,
                    })
                end
            else
                inner:AddDescription("Display Border is only available when Groups is set to 'Separate Groups'.")
            end
            inner:Finalize()
        end,
    })

    ----------------------------------------------------------------------------
    -- Collapsible Section: Style
    ----------------------------------------------------------------------------

    builder:AddCollapsibleSection({
        title = "Style",
        componentId = COMPONENT_ID,
        sectionKey = "style",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            buildStyleTab(inner, "healthBar", applyStyles)
        end,
    })

    ----------------------------------------------------------------------------
    -- Collapsible Section: Text
    ----------------------------------------------------------------------------

    builder:AddCollapsibleSection({
        title = "Text",
        componentId = COMPONENT_ID,
        sectionKey = "text",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddTabbedSection({
                tabs = {
                    { key = "playerName", label = "Player Name" },
                    { key = "statusText", label = "Status Text" },
                    { key = "groupNumbers", label = "Group Numbers" },
                },
                componentId = COMPONENT_ID,
                sectionKey = "text_tabs",
                buildContent = {
                    playerName = function(cf, tabInner)
                        buildTextTab(tabInner, "textPlayerName", applyText)
                    end,
                    statusText = function(cf, tabInner)
                        buildTextTab(tabInner, "textStatusText", applyText)
                    end,
                    groupNumbers = function(cf, tabInner)
                        buildTextTab(tabInner, "textGroupNumbers", applyText)
                    end,
                },
            })
            inner:Finalize()
        end,
    })

    ----------------------------------------------------------------------------
    -- Collapsible Section: Visibility
    ----------------------------------------------------------------------------

    builder:AddCollapsibleSection({
        title = "Visibility",
        componentId = COMPONENT_ID,
        sectionKey = "visibility",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddDescription("Visibility options coming in a future update.")
            inner:Finalize()
        end,
    })

    ----------------------------------------------------------------------------
    -- Finalize
    ----------------------------------------------------------------------------

    builder:Finalize()
end
