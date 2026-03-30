local _, addon = ...
local DM2 = addon.DamageMetersV2

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local HEADER_HEIGHT = 24
local ICON_SIZE = 22
local NAME_WIDTH = 100
local PINNED_SEPARATOR_HEIGHT = 1

local function GetDefaultFont()
    if addon.ResolveFontFace then
        return addon.ResolveFontFace("ROBOTO_SEMICOND_BOLD")
    end
    return "Fonts\\FRIZQT__.TTF"
end

--------------------------------------------------------------------------------
-- Bar Row Creation
--
-- Each bar row has: Icon, NameText, a single full-width StatusBar (representing
-- the primary column's data), and up to MAX_COLUMNS value text FontStrings
-- positioned at their column offsets on top of the bar.
--------------------------------------------------------------------------------

function DM2._CreateBarRow(scrollContent, rowIndex)
    local row = CreateFrame("Frame", nil, scrollContent)
    row:SetHeight(22)

    -- Icon
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.icon = icon

    -- Bar area starts at a fixed offset (icon + gap + name width + gap)
    local barAreaLeft = ICON_SIZE + 6 + NAME_WIDTH + 4

    -- Name clip region — clips long names so they don't overflow into rank area
    -- Leave 22px gap at the right for rank numbers
    local nameClipWidth = NAME_WIDTH - 22
    local nameClip = CreateFrame("Frame", nil, row)
    nameClip:SetPoint("LEFT", icon, "RIGHT", 4, 0)
    nameClip:SetPoint("TOP", row, "TOP")
    nameClip:SetPoint("BOTTOM", row, "BOTTOM")
    nameClip:SetWidth(nameClipWidth)
    nameClip:SetClipsChildren(true)
    nameClip:SetFrameLevel(row:GetFrameLevel() + 1)

    -- Inner frame holds the FontString (ClipsChildren clips child frames)
    local nameInner = CreateFrame("Frame", nil, nameClip)
    nameInner:SetAllPoints()

    local nameText = nameInner:CreateFontString(nil, "OVERLAY")
    nameText:SetFont(GetDefaultFont(), 12, "OUTLINE")
    nameText:SetPoint("LEFT", 0, 0)
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)
    nameText:SetTextColor(1, 1, 1, 1)
    row.nameText = nameText

    -- Bar background (full width, behind the StatusBar)
    local barBg = row:CreateTexture(nil, "BACKGROUND")
    barBg:SetPoint("LEFT", row, "LEFT", barAreaLeft, 0)
    barBg:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    barBg:SetPoint("TOP", row, "TOP", 0, 0)
    barBg:SetPoint("BOTTOM", row, "BOTTOM", 0, 0)
    barBg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
    row.barBg = barBg

    -- Single full-width StatusBar (primary column data)
    local bar = CreateFrame("StatusBar", nil, row)
    bar:SetPoint("LEFT", row, "LEFT", barAreaLeft, 0)
    bar:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    bar:SetPoint("TOP", row, "TOP", 0, 0)
    bar:SetPoint("BOTTOM", row, "BOTTOM", 0, 0)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    row.bar = bar

    -- Rank number text (e.g., "1.", "2.") — positioned dynamically in layout
    -- Use a higher sublevel so it renders on top of the name clip area
    local rankText = row:CreateFontString(nil, "OVERLAY", nil, 7)
    rankText:SetFont(GetDefaultFont(), 11, "OUTLINE")
    rankText:SetJustifyH("RIGHT")
    rankText:SetWordWrap(false)
    rankText:SetTextColor(0.6, 0.6, 0.6, 0.7)
    row.rankText = rankText

    -- Column value texts (up to MAX_COLUMNS, positioned at column offsets)
    row.valueTexts = {}
    for c = 1, DM2.MAX_COLUMNS do
        local vt = bar:CreateFontString(nil, "OVERLAY")
        vt:SetFont(GetDefaultFont(), 11, "OUTLINE")
        vt:SetJustifyH("RIGHT")
        vt:SetWordWrap(false)
        vt:SetTextColor(1, 1, 1, 1)
        vt:Hide()
        row.valueTexts[c] = vt
    end

    row._rowIndex = rowIndex
    row:Hide()
    return row
end

--------------------------------------------------------------------------------
-- Window Creation
--------------------------------------------------------------------------------

function DM2._CreateWindow(windowIndex, comp)
    local db = comp.db
    local fw = tonumber(db.frameWidth) or 350
    local fh = tonumber(db.frameHeight) or 250

    -- Main container
    local frame = CreateFrame("Frame", "ScootDMV2Window" .. windowIndex, UIParent)
    frame:SetSize(fw, fh)
    frame:SetPoint("CENTER", UIParent, "CENTER", -200 + (windowIndex - 1) * 100, 0)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:Hide()

    -- Background
    local background = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    background:SetAllPoints()
    background:SetColorTexture(0.06, 0.06, 0.08, 0.95)

    -- Header
    local header = CreateFrame("Frame", nil, frame)
    header:SetHeight(HEADER_HEIGHT)
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)

    local headerBg = header:CreateTexture(nil, "BACKGROUND", nil, -6)
    headerBg:SetAllPoints()
    headerBg:SetColorTexture(0.08, 0.08, 0.10, 0.9)
    header._bg = headerBg

    -- Gear button (left side of header, opens flyout menu)
    local gearBtn = CreateFrame("Button", nil, header)
    gearBtn:SetSize(18, 18)
    gearBtn:SetPoint("LEFT", header, "LEFT", 4, 0)

    local gearIcon = gearBtn:CreateTexture(nil, "ARTWORK")
    gearIcon:SetAllPoints()
    gearIcon:SetTexture("Interface\\Buttons\\UI-OptionsButton")
    gearIcon:SetDesaturated(true)
    gearIcon:SetVertexColor(0.8, 0.8, 0.8, 0.7)
    gearBtn._icon = gearIcon

    gearBtn:SetScript("OnEnter", function() gearIcon:SetVertexColor(1, 1, 1, 1) end)
    gearBtn:SetScript("OnLeave", function() gearIcon:SetVertexColor(0.8, 0.8, 0.8, 0.7) end)

    -- Title text (e.g., "Overall", "Current") — to the right of gear button
    local titleText = header:CreateFontString(nil, "OVERLAY")
    titleText:SetFont(GetDefaultFont(), 13, "OUTLINE")
    titleText:SetPoint("LEFT", gearBtn, "RIGHT", 4, 0)
    titleText:SetTextColor(1, 1, 1, 1) -- default white
    titleText:SetText("Overall")

    -- Timer text (e.g., "[5:23]") — to the right of title
    local timerText = header:CreateFontString(nil, "OVERLAY")
    timerText:SetFont(GetDefaultFont(), 13, "OUTLINE")
    timerText:SetPoint("LEFT", titleText, "RIGHT", 4, 0)
    timerText:SetTextColor(1.0, 0.82, 0, 1) -- default yellow
    timerText:SetText("")

    -- Vertical title text (shown when verticalTitleMode is on)
    local verticalTitle = frame:CreateFontString(nil, "OVERLAY")
    verticalTitle:SetFont(GetDefaultFont(), 11, "OUTLINE")
    verticalTitle:SetTextColor(1, 1, 1, 0.7)
    verticalTitle:SetText("")
    verticalTitle:Hide()
    -- Rotate 90 degrees counter-clockwise for vertical text
    -- WoW doesn't support FontString rotation directly, so we use a workaround:
    -- Put the text in a frame and rotate the frame... but WoW doesn't support
    -- frame rotation either. Use single-character-per-line approach instead.

    -- For vertical title: we'll set the text as stacked characters in _UpdateTimerText

    -- Column headers (right side, created dynamically)
    local columnHeaders = {}
    for c = 1, DM2.MAX_COLUMNS do
        local ch = header:CreateFontString(nil, "OVERLAY")
        ch:SetFont(GetDefaultFont(), 10, "OUTLINE")
        ch:SetTextColor(0.8, 0.8, 0.8, 1)
        ch:SetJustifyH("RIGHT")
        ch:Hide()
        columnHeaders[c] = ch
    end

    -- Header divider
    local headerDiv = frame:CreateTexture(nil, "ARTWORK")
    headerDiv:SetHeight(1)
    headerDiv:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    headerDiv:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 0)
    headerDiv:SetColorTexture(0.3, 0.3, 0.35, 0.5)

    -- Scroll area (clips children)
    local scrollArea = CreateFrame("Frame", nil, frame)
    scrollArea:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -1)
    scrollArea:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    scrollArea:SetClipsChildren(true)

    -- Scroll content (height grows with data)
    local scrollContent = CreateFrame("Frame", nil, scrollArea)
    scrollContent:SetPoint("TOPLEFT", scrollArea, "TOPLEFT", 0, 0)
    scrollContent:SetPoint("RIGHT", scrollArea, "RIGHT", 0, 0)
    scrollContent:SetHeight(1) -- grows dynamically

    -- Mouse wheel for scrolling
    scrollArea:EnableMouseWheel(true)
    scrollArea:SetScript("OnMouseWheel", function(self, delta)
        local win = DM2._windows[windowIndex]
        if not win or not win.mergedData then return end
        local bh = (tonumber(db.barHeight) or 22) + (tonumber(db.barSpacing) or 2)
        local maxVisible = math.floor(scrollArea:GetHeight() / bh)
        local totalRows = #win.mergedData.playerOrder
        local maxOffset = math.max(0, totalRows - maxVisible)
        win.scrollOffset = math.max(0, math.min(win.scrollOffset - delta, maxOffset))
        DM2._RefreshBarRows(windowIndex, comp)
    end)

    -- Create bar row pool
    local barRows = {}
    for r = 1, DM2.MAX_POOL do
        barRows[r] = DM2._CreateBarRow(scrollContent, r)
    end

    -- Local player pinned row (separate frame below scroll area)
    local pinnedRow = DM2._CreateBarRow(frame, 0)
    pinnedRow:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    pinnedRow:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)

    local pinnedSeparator = frame:CreateTexture(nil, "ARTWORK")
    pinnedSeparator:SetHeight(PINNED_SEPARATOR_HEIGHT)
    pinnedSeparator:SetPoint("BOTTOMLEFT", pinnedRow, "TOPLEFT", 0, 0)
    pinnedSeparator:SetPoint("BOTTOMRIGHT", pinnedRow, "TOPRIGHT", 0, 0)
    pinnedSeparator:SetColorTexture(0.4, 0.4, 0.45, 0.6)
    pinnedSeparator:Hide()

    -- Gear button click handler: flyout menu with export + reset
    local gearMenu = nil
    local winIdx = windowIndex -- capture for closures
    gearBtn:SetScript("OnClick", function()
        if gearMenu and gearMenu:IsShown() then
            gearMenu:Hide()
            return
        end
        if not gearMenu then
            local menuHeight = 230 -- export window + 5 chat channels + header + divider + reset + padding
            gearMenu = CreateFrame("Frame", nil, UIParent)
            gearMenu:SetSize(160, menuHeight)
            gearMenu:SetFrameStrata("FULLSCREEN_DIALOG")
            gearMenu:SetFrameLevel(200)
            gearMenu:EnableMouse(true)

            local menuBg = gearMenu:CreateTexture(nil, "BACKGROUND", nil, -8)
            menuBg:SetAllPoints()
            menuBg:SetColorTexture(0.06, 0.06, 0.08, 0.95)

            local menuBorder = { 0.3, 0.3, 0.35, 0.8 }
            for _, info in ipairs({
                { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
                { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false },
            }) do
                local t = gearMenu:CreateTexture(nil, "BORDER")
                t:SetPoint(info[1]); t:SetPoint(info[2])
                if info[3] then t:SetHeight(1) else t:SetWidth(1) end
                t:SetColorTexture(menuBorder[1], menuBorder[2], menuBorder[3], menuBorder[4])
            end

            local yOff = -4
            local function AddMenuRow(label, textColor, onClick)
                local btn = CreateFrame("Button", nil, gearMenu)
                btn:SetSize(152, 24)
                btn:SetPoint("TOP", gearMenu, "TOP", 0, yOff)
                local bg = btn:CreateTexture(nil, "BACKGROUND", nil, -6)
                bg:SetAllPoints()
                bg:SetColorTexture(1, 1, 1, 0)
                local txt = btn:CreateFontString(nil, "OVERLAY")
                txt:SetFont(GetDefaultFont(), 10, "OUTLINE")
                txt:SetPoint("LEFT", 8, 0)
                txt:SetText(label)
                txt:SetTextColor(textColor[1], textColor[2], textColor[3], textColor[4] or 1)
                btn:SetScript("OnEnter", function() bg:SetColorTexture(1, 1, 1, 0.08) end)
                btn:SetScript("OnLeave", function() bg:SetColorTexture(1, 1, 1, 0) end)
                btn:SetScript("OnClick", function()
                    gearMenu:Hide()
                    onClick()
                end)
                yOff = yOff - 24
                return btn
            end

            -- Export to Window
            AddMenuRow("Export to Window", { 1, 1, 1, 0.9 }, function()
                if DM2._ExportToWindow then DM2._ExportToWindow(winIdx) end
            end)

            -- Export to Chat (with inline channel selector)
            local chatChannels = { "SAY", "PARTY", "RAID", "INSTANCE_CHAT", "GUILD" }
            local chatLabels = { SAY = "Say", PARTY = "Party", RAID = "Raid", INSTANCE_CHAT = "Instance", GUILD = "Guild" }
            local currentChannel = (DM2._comp and DM2._comp.db and DM2._comp.db.exportChatChannel) or "PARTY"
            local currentLines = (DM2._comp and DM2._comp.db and DM2._comp.db.exportChatLineCount) or 5

            -- Channel label row (header)
            local chatHeader = gearMenu:CreateFontString(nil, "OVERLAY")
            chatHeader:SetFont(GetDefaultFont(), 9, "OUTLINE")
            chatHeader:SetPoint("TOPLEFT", gearMenu, "TOPLEFT", 8, yOff)
            chatHeader:SetText("Export to Chat")
            chatHeader:SetTextColor(0.7, 0.7, 0.7, 1)
            yOff = yOff - 16

            -- Channel buttons (compact row)
            for _, ch in ipairs(chatChannels) do
                local chBtn = CreateFrame("Button", nil, gearMenu)
                chBtn:SetSize(152, 20)
                chBtn:SetPoint("TOP", gearMenu, "TOP", 0, yOff)
                local chBg = chBtn:CreateTexture(nil, "BACKGROUND", nil, -6)
                chBg:SetAllPoints()
                chBg:SetColorTexture(1, 1, 1, 0)
                local chText = chBtn:CreateFontString(nil, "OVERLAY")
                chText:SetFont(GetDefaultFont(), 9, "OUTLINE")
                chText:SetPoint("LEFT", 16, 0)
                chText:SetText(chatLabels[ch] or ch)
                chText:SetTextColor(1, 1, 1, 0.8)
                -- Send indicator
                local sendText = chBtn:CreateFontString(nil, "OVERLAY")
                sendText:SetFont(GetDefaultFont(), 9, "OUTLINE")
                sendText:SetPoint("RIGHT", -8, 0)
                sendText:SetText("Send")
                sendText:SetTextColor(0.5, 0.5, 0.5, 0.6)
                chBtn:SetScript("OnEnter", function()
                    chBg:SetColorTexture(1, 1, 1, 0.08)
                    sendText:SetTextColor(0.3, 1.0, 0.3, 1)
                end)
                chBtn:SetScript("OnLeave", function()
                    chBg:SetColorTexture(1, 1, 1, 0)
                    sendText:SetTextColor(0.5, 0.5, 0.5, 0.6)
                end)
                chBtn:SetScript("OnClick", function()
                    gearMenu:Hide()
                    if DM2._ExportToChatChannel then
                        DM2._ExportToChatChannel(winIdx, ch, currentLines)
                    end
                end)
                yOff = yOff - 20
            end

            -- Divider
            local divider = gearMenu:CreateTexture(nil, "ARTWORK")
            divider:SetSize(148, 1)
            divider:SetPoint("TOP", gearMenu, "TOP", 0, yOff - 4)
            divider:SetColorTexture(0.3, 0.3, 0.35, 0.5)
            yOff = yOff - 9

            -- Reset All Data (red)
            AddMenuRow("Reset All Data", { 1, 0.3, 0.3, 1 }, function()
                if C_DamageMeter and C_DamageMeter.ResetAllCombatSessions then
                    C_DamageMeter.ResetAllCombatSessions()
                end
                DM2._HandleReset()
            end)
        end
        gearMenu:ClearAllPoints()
        gearMenu:SetPoint("TOPLEFT", gearBtn, "BOTTOMLEFT", 0, -2)
        gearMenu:Show()
    end)

    -- Store window state
    DM2._windows[windowIndex] = {
        frame = frame,
        background = background,
        header = header,
        gearBtn = gearBtn,
        titleText = titleText,
        timerText = timerText,
        verticalTitle = verticalTitle,
        columnHeaders = columnHeaders,
        scrollArea = scrollArea,
        scrollContent = scrollContent,
        barRows = barRows,
        pinnedRow = pinnedRow,
        pinnedSeparator = pinnedSeparator,
        scrollOffset = 0,
        mergedData = nil,
        cachedSecondary = nil,
        lastUpdateTime = 0,
    }
end

--------------------------------------------------------------------------------
-- Accessors
--------------------------------------------------------------------------------

DM2.HEADER_HEIGHT = HEADER_HEIGHT
DM2.ICON_SIZE = ICON_SIZE
DM2.NAME_WIDTH = NAME_WIDTH
