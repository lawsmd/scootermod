local addonName, addon = ...

addon.SettingsPanel = addon.SettingsPanel or {}
local panel = addon.SettingsPanel

-- Collapsible section header (Keybindings-style) ---------------------------------
ScooterExpandableSectionMixin = {}

function ScooterExpandableSectionMixin:OnLoad()
    if SettingsExpandableSectionMixin and SettingsExpandableSectionMixin.OnLoad then
        SettingsExpandableSectionMixin.OnLoad(self)
    end
end

function ScooterExpandableSectionMixin:Init(initializer)
    if SettingsExpandableSectionMixin and SettingsExpandableSectionMixin.Init then
        SettingsExpandableSectionMixin.Init(self, initializer)
    end
    local data = initializer and initializer.data or {}
    self._initializing = true
    self.sectionKey = data.sectionKey
    self.componentId = data.componentId
    if self.Button and self.Button.Text and self.Button.Text.GetFont then
        if not self._origHeaderFont then
            local fp, fh, ff = self.Button.Text:GetFont()
            self._origHeaderFont = { fp, fh, ff }
            self._headerFontScaled = false
        end
        if not self._headerFontScaled then
            local fp, fh, ff = self._origHeaderFont[1], self._origHeaderFont[2], self._origHeaderFont[3]
            if fh then
                local bigger = math.max(1, math.floor((fh * 1.3) + 0.5))
                local face = (addon and addon.Fonts and (addon.Fonts.ROBOTO_MED or addon.Fonts.ROBOTO_REG)) or fp
                self.Button.Text:SetFont(face, bigger, ff)
                if self.Button.Text.SetTextColor then self.Button.Text:SetTextColor(0.20, 0.90, 0.30, 1) end
            end
            self._headerFontScaled = true
        end
    end
    self:OnExpandedChanged(self:GetExpanded())
    self._initializing = false
end

function ScooterExpandableSectionMixin:GetExpanded()
    local cid = self.componentId or ""
    local key = self.sectionKey or ""
    addon.SettingsPanel._expanded = addon.SettingsPanel._expanded or {}
    addon.SettingsPanel._expanded[cid] = addon.SettingsPanel._expanded[cid] or {}
    local expanded = addon.SettingsPanel._expanded[cid][key]
    if expanded == nil then expanded = false end
    return expanded
end

function ScooterExpandableSectionMixin:SetExpanded(expanded)
    local cid = self.componentId or ""
    local key = self.sectionKey or ""
    addon.SettingsPanel._expanded = addon.SettingsPanel._expanded or {}
    addon.SettingsPanel._expanded[cid] = addon.SettingsPanel._expanded[cid] or {}
    addon.SettingsPanel._expanded[cid][key] = not not expanded
end

function ScooterExpandableSectionMixin:CalculateHeight()
    return 34
end

function ScooterExpandableSectionMixin:OnExpandedChanged(expanded)
    if self.Button and self.Button.Right then
        if expanded then
            self.Button.Right:SetAtlas("Options_ListExpand_Right_Expanded", TextureKitConstants.UseAtlasSize)
        else
            self.Button.Right:SetAtlas("Options_ListExpand_Right", TextureKitConstants.UseAtlasSize)
        end
    end
    self:SetExpanded(expanded)
    if not self._initializing and addon and addon.SettingsPanel then
        if addon.SettingsPanel.RefreshCurrentCategory then addon.SettingsPanel.RefreshCurrentCategory() end
    end
    if addon and addon.SettingsPanel and type(addon.SettingsPanel.UpdateProfilesSectionVisibility) == "function" then
        addon.SettingsPanel:UpdateProfilesSectionVisibility()
    end
end

function panel:IsSectionExpanded(componentId, sectionKey)
    self._expanded = self._expanded or {}
    self._expanded[componentId] = self._expanded[componentId] or {}
    local v = self._expanded[componentId][sectionKey]
    if v == nil then v = false end
    return v
end

-- ScooterTabbedSectionMixin ------------------------------------------------------
ScooterTabbedSectionMixin = {}

function ScooterTabbedSectionMixin:OnLoad()
    self.tabsGroup = self.tabsGroup or CreateRadioButtonGroup()
    -- Hide optional tabs by default; they will be enabled in Init/SetTitles when text is provided
    if self.TabC then self.TabC:Hide() end
    if self.TabD then self.TabD:Hide() end
    if self.TabE then self.TabE:Hide() end
    if self.TabF then self.TabF:Hide() end
    if self.TabG then self.TabG:Hide() end
    if self.TabH then self.TabH:Hide() end
    if self.TabI then self.TabI:Hide() end
    local buttons = {}
    if self.TabA then table.insert(buttons, self.TabA) end
    if self.TabB then table.insert(buttons, self.TabB) end
    -- Do not add TabC/TabD here; they may be added later if enabled by SetTitles
    if #buttons == 0 then return end
    self.tabsGroup:AddButtons(buttons)
    self.tabsGroup:SelectAtIndex(1)
    self.tabsGroup:RegisterCallback(ButtonGroupBaseMixin.Event.Selected, function(_, btn)
        if self.tabsGroup and self.tabsGroup.GetSelectedIndex then
            self._selectedIndex = self.tabsGroup:GetSelectedIndex()
        end
        self:EvaluateVisibility(btn)
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
        if self.UpdateTabTheme then self:UpdateTabTheme(btn) end
    end, self)
    self:EvaluateVisibility(self.TabA or buttons[1])
    if self.UpdateTabTheme then self:UpdateTabTheme(self.TabA or buttons[1]) end
    -- Ensure theme is corrected whenever the section becomes visible (e.g., after
    -- switching categories) even if the button group's Selected callback doesn't fire.
    if self.SetScript and not self._scooterOnShowHooked then
        self._scooterOnShowHooked = true
        self:SetScript("OnShow", function()
            if self.UpdateTabTheme then self:UpdateTabTheme() end
        end)
    end
end

-- Lay out tabs in up to two rows.
-- Rule: show first up to 5 tabs on the bottom row (left-to-right, row is right-aligned).
-- Any remaining tabs (6+) are placed on a second row above, also right-aligned and ordered left-to-right.
function ScooterTabbedSectionMixin:LayoutTabs()
    local all = { self.TabA, self.TabB, self.TabC, self.TabD, self.TabE, self.TabF, self.TabG, self.TabH, self.TabI }
    local visible = {}
    for i = 1, #all do
        local btn = all[i]
        if btn and btn:IsShown() then table.insert(visible, btn) end
    end
    if #visible == 0 then return end

    local function chainLeft(rowButtons)
        for i = #rowButtons - 1, 1, -1 do
            local btn = rowButtons[i]
            btn:ClearAllPoints()
            btn:SetPoint("TOPRIGHT", rowButtons[i + 1], "TOPLEFT", 0, 0)
        end
    end

    -- Split into rows: bottom (first five) and top (overflow)
    local bottomCount = math.min(5, #visible)
    local bottomRow = {}
    for i = 1, bottomCount do table.insert(bottomRow, visible[i]) end
    local topRow = {}
    if #visible > 5 then for i = 6, #visible do table.insert(topRow, visible[i]) end end

    -- If we have 2 rows, drop the border down by one tab height to make room above it
    local drop = 0
    do
        local tabHeight = 37
        if self.NineSlice and self.NineSlice.ClearAllPoints then
            self.NineSlice:ClearAllPoints()
            if #visible > 5 then
                -- Move border down by the effective extra height (second row minus overlap),
                -- then tighten a few pixels so the bottom row visually meets the border.
                local rowOverlap = 12 -- keep in sync with bottomRow anchor below
                local borderTighten = 4
                drop = math.max(0, tabHeight - rowOverlap - borderTighten)
                self.NineSlice:SetPoint("TOPLEFT", self, "TOPLEFT", -12, -14 - drop)
            else
                self.NineSlice:SetPoint("TOPLEFT", self, "TOPLEFT", -12, -14)
            end
            self.NineSlice:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -6, -16)
        end
    end
    
    -- Anchor page frames to respect the border position and provide consistent top spacing
    do
        local pages = { self.PageA, self.PageB, self.PageC, self.PageD, self.PageE, self.PageF, self.PageG, self.PageH, self.PageI }
        -- Content inset from border edges (left, right, bottom)
        local contentInsetX = 8
        local contentInsetBottom = 8
        -- Top spacing from the border's top edge to the first control (reduced to 8px for better fit)
        local contentTopSpacing = 8
        -- The border's TOPLEFT is at (-12, -14 - drop), so content should start at:
        -- X: -12 + contentInsetX, Y: -14 - drop - contentTopSpacing
        local pageTopY = -14 - drop - contentTopSpacing
        for i = 1, #pages do
            if pages[i] then
                pages[i]:ClearAllPoints()
                pages[i]:SetPoint("TOPLEFT", self, "TOPLEFT", -12 + contentInsetX, pageTopY)
                pages[i]:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -6 - contentInsetX, -16 + contentInsetBottom)
            end
        end
    end

    -- Anchor the TOP row to the frame (to guarantee clearance from the section header)
    if #topRow > 0 then
        local lastTop = topRow[#topRow]
        lastTop:ClearAllPoints()
        -- Nudge downward slightly from the original XML baseline to avoid header overlap
        local topBaseline = 14
        lastTop:SetPoint("TOPRIGHT", self, "TOPRIGHT", -30, topBaseline)
        chainLeft(topRow)
        -- Ensure upper row sits above the lower row visually/click-wise
        local baseLevel = (self:GetFrameLevel() or 1)
        for i = 1, #topRow do if topRow[i] and topRow[i].SetFrameLevel then topRow[i]:SetFrameLevel(baseLevel + 2) end end
        -- Now anchor the BOTTOM row directly below the top row (touching)
        if #bottomRow > 0 then
            local lastBottom = bottomRow[#bottomRow]
            lastBottom:ClearAllPoints()
            local rowOverlap = 12
            -- Positive offset pulls upward (TOP to BOTTOM anchor semantics)
            lastBottom:SetPoint("TOPRIGHT", lastTop, "BOTTOMRIGHT", 0, rowOverlap)
            chainLeft(bottomRow)
            -- Keep bottom row beneath top row and reduce its top hit area so it doesn't capture clicks
            for i = 1, #bottomRow do
                local btn = bottomRow[i]
                if btn then
                    if btn.SetFrameLevel then btn:SetFrameLevel(baseLevel + 1) end
                    if btn.SetHitRectInsets then btn:SetHitRectInsets(0, 0, rowOverlap, 0) end
                end
            end
            -- Restore full hit rect for the top row
            for i = 1, #topRow do
                local btn = topRow[i]
                if btn and btn.SetHitRectInsets then btn:SetHitRectInsets(0, 0, 0, 0) end
            end
        end
    else
        -- Only one row → place the bottomRow at the standard baseline
        local lastOnly = bottomRow[#bottomRow]
        lastOnly:ClearAllPoints()
        lastOnly:SetPoint("TOPRIGHT", self, "TOPRIGHT", -30, 10)
        chainLeft(bottomRow)
        -- Ensure full click area when only one row is present
        for i = 1, #bottomRow do
            local btn = bottomRow[i]
            if btn and btn.SetHitRectInsets then btn:SetHitRectInsets(0, 0, 0, 0) end
        end
    end
end

function ScooterTabbedSectionMixin:SetTitles(sectionTitle, tabAText, tabBText, tabCText, tabDText, tabEText, tabFText, tabGText, tabHText, tabIText)
    if self.TitleFS then self.TitleFS:SetText(sectionTitle or "") end
    if self.TabA then
        self.TabA.tabText = tabAText or "Tab A"
        if self.TabA.Text then
            self.TabA.Text:SetText(self.TabA.tabText)
            self.TabA:SetWidth(self.TabA.Text:GetStringWidth() + 40)
        end
    end
    if self.TabB then
        self.TabB.tabText = tabBText or "Tab B"
        if self.TabB.Text then
            self.TabB.Text:SetText(self.TabB.tabText)
            self.TabB:SetWidth(self.TabB.Text:GetStringWidth() + 40)
        end
    end
    -- Optional tabs C/D: only enable when explicit text is provided
    local enableC = type(tabCText) == "string" and tabCText ~= ""
    local enableD = type(tabDText) == "string" and tabDText ~= ""
    local enableE = type(tabEText) == "string" and tabEText ~= ""
    local enableF = type(tabFText) == "string" and tabFText ~= ""
    local enableG = type(tabGText) == "string" and tabGText ~= ""
    local enableH = type(tabHText) == "string" and tabHText ~= ""
    local enableI = type(tabIText) == "string" and tabIText ~= ""
    if self.TabC then
        if enableC then
            self.TabC.tabText = tabCText
            if self.TabC.Text then
                self.TabC.Text:SetText(self.TabC.tabText)
                self.TabC:SetWidth(self.TabC.Text:GetStringWidth() + 40)
            end
            self.TabC:Show()
            if self.tabsGroup and self.tabsGroup.AddButtons and not self.TabC._ScooterInTabsGroup then
                self.tabsGroup:AddButtons({ self.TabC })
                self.TabC._ScooterInTabsGroup = true
            end
        else
            if self.tabsGroup and self.tabsGroup.RemoveButton and self.TabC._ScooterInTabsGroup then
                self.tabsGroup:RemoveButton(self.TabC)
                self.TabC._ScooterInTabsGroup = false
            end
            self.TabC:Hide()
            if self.PageC then self.PageC:Hide() end
        end
    end
    if self.TabD then
        if enableD then
            self.TabD.tabText = tabDText
            if self.TabD.Text then
                self.TabD.Text:SetText(self.TabD.tabText)
                self.TabD:SetWidth(self.TabD.Text:GetStringWidth() + 40)
            end
            self.TabD:Show()
            if self.tabsGroup and self.tabsGroup.AddButtons and not self.TabD._ScooterInTabsGroup then
                self.tabsGroup:AddButtons({ self.TabD })
                self.TabD._ScooterInTabsGroup = true
            end
        else
            if self.tabsGroup and self.tabsGroup.RemoveButton and self.TabD._ScooterInTabsGroup then
                self.tabsGroup:RemoveButton(self.TabD)
                self.TabD._ScooterInTabsGroup = false
            end
            self.TabD:Hide()
            if self.PageD then self.PageD:Hide() end
        end
    end
    if self.TabE then
        if enableE then
            self.TabE.tabText = tabEText
            if self.TabE.Text then
                self.TabE.Text:SetText(self.TabE.tabText)
                self.TabE:SetWidth(self.TabE.Text:GetStringWidth() + 40)
            end
            self.TabE:Show()
            if self.tabsGroup and self.tabsGroup.AddButtons and not self.TabE._ScooterInTabsGroup then
                self.tabsGroup:AddButtons({ self.TabE })
                self.TabE._ScooterInTabsGroup = true
            end
        else
            if self.tabsGroup and self.tabsGroup.RemoveButton and self.TabE._ScooterInTabsGroup then
                self.tabsGroup:RemoveButton(self.TabE)
                self.TabE._ScooterInTabsGroup = false
            end
            self.TabE:Hide()
            if self.PageE then self.PageE:Hide() end
        end
    end
    if self.TabF then
        if enableF then
            self.TabF.tabText = tabFText
            if self.TabF.Text then
                self.TabF.Text:SetText(self.TabF.tabText)
                self.TabF:SetWidth(self.TabF.Text:GetStringWidth() + 40)
            end
            self.TabF:Show()
            if self.tabsGroup and self.tabsGroup.AddButtons and not self.TabF._ScooterInTabsGroup then
                self.tabsGroup:AddButtons({ self.TabF })
                self.TabF._ScooterInTabsGroup = true
            end
        else
            if self.tabsGroup and self.tabsGroup.RemoveButton and self.TabF._ScooterInTabsGroup then
                self.tabsGroup:RemoveButton(self.TabF)
                self.TabF._ScooterInTabsGroup = false
            end
            self.TabF:Hide()
            if self.PageF then self.PageF:Hide() end
        end
    end
    if self.TabG then
        if enableG then
            self.TabG.tabText = tabGText
            if self.TabG.Text then
                self.TabG.Text:SetText(self.TabG.tabText)
                self.TabG:SetWidth(self.TabG.Text:GetStringWidth() + 40)
            end
            self.TabG:Show()
            if self.tabsGroup and self.tabsGroup.AddButtons and not self.TabG._ScooterInTabsGroup then
                self.tabsGroup:AddButtons({ self.TabG })
                self.TabG._ScooterInTabsGroup = true
            end
        else
            if self.tabsGroup and self.tabsGroup.RemoveButton and self.TabG._ScooterInTabsGroup then
                self.tabsGroup:RemoveButton(self.TabG)
                self.TabG._ScooterInTabsGroup = false
            end
            self.TabG:Hide()
            if self.PageG then self.PageG:Hide() end
        end
    end
    if self.TabH then
        if enableH then
            self.TabH.tabText = tabHText
            if self.TabH.Text then
                self.TabH.Text:SetText(self.TabH.tabText)
                self.TabH:SetWidth(self.TabH.Text:GetStringWidth() + 40)
            end
            self.TabH:Show()
            if self.tabsGroup and self.tabsGroup.AddButtons and not self.TabH._ScooterInTabsGroup then
                self.tabsGroup:AddButtons({ self.TabH })
                self.TabH._ScooterInTabsGroup = true
            end
        else
            if self.tabsGroup and self.tabsGroup.RemoveButton and self.TabH._ScooterInTabsGroup then
                self.tabsGroup:RemoveButton(self.TabH)
                self.TabH._ScooterInTabsGroup = false
            end
            self.TabH:Hide()
            if self.PageH then self.PageH:Hide() end
        end
    end
    if self.TabI then
        if enableI then
            self.TabI.tabText = tabIText
            if self.TabI.Text then
                self.TabI.Text:SetText(self.TabI.tabText)
                self.TabI:SetWidth(self.TabI.Text:GetStringWidth() + 40)
            end
            self.TabI:Show()
            if self.tabsGroup and self.tabsGroup.AddButtons and not self.TabI._ScooterInTabsGroup then
                self.tabsGroup:AddButtons({ self.TabI })
                self.TabI._ScooterInTabsGroup = true
            end
        else
            if self.tabsGroup and self.tabsGroup.RemoveButton and self.TabI._ScooterInTabsGroup then
                self.tabsGroup:RemoveButton(self.TabI)
                self.TabI._ScooterInTabsGroup = false
            end
            self.TabI:Hide()
            if self.PageI then self.PageI:Hide() end
        end
    end
    if self.UpdateTabTheme then self:UpdateTabTheme() end
    -- Recalculate positions after enabling/disabling tabs
    if self.LayoutTabs then self:LayoutTabs() end
end

function ScooterTabbedSectionMixin:EvaluateVisibility(selected)
    local index = 1
    if self.tabsGroup and self.tabsGroup.GetSelectedIndex then
        index = self.tabsGroup:GetSelectedIndex() or index
    else
        if selected == self.TabA then index = 1
        elseif selected == self.TabB then index = 2
        elseif selected == self.TabC then index = 3
        elseif selected == self.TabD then index = 4
        elseif selected == self.TabE then index = 5
        elseif selected == self.TabF then index = 6
        elseif selected == self.TabG then index = 7
        elseif selected == self.TabH then index = 8
        elseif selected == self.TabI then index = 9 end
    end
    local pages = { self.PageA, self.PageB, self.PageC, self.PageD, self.PageE, self.PageF, self.PageG, self.PageH, self.PageI }
    for i = 1, #pages do
        if pages[i] then pages[i]:SetShown(i == index) end
    end
end

function ScooterTabbedSectionMixin:UpdateTabTheme(selectedBtn)
    local brandR, brandG, brandB = 0.20, 0.90, 0.30
    local function style(btn, selected)
        if not btn or not btn.Text then return end
        if panel and panel.ApplyRoboto then panel.ApplyRoboto(btn.Text) end
        if selected then
            btn.Text:SetTextColor(1, 1, 1, 1)
        else
            btn.Text:SetTextColor(brandR, brandG, brandB, 1)
        end
    end
    local selectedIndex = nil
    if selectedBtn then
        if selectedBtn == self.TabA then selectedIndex = 1
        elseif selectedBtn == self.TabB then selectedIndex = 2
        elseif selectedBtn == self.TabC then selectedIndex = 3
        elseif selectedBtn == self.TabD then selectedIndex = 4
        elseif selectedBtn == self.TabE then selectedIndex = 5
        elseif selectedBtn == self.TabF then selectedIndex = 6
        elseif selectedBtn == self.TabG then selectedIndex = 7
        elseif selectedBtn == self.TabH then selectedIndex = 8
        elseif selectedBtn == self.TabI then selectedIndex = 9 end
    end
    -- Prefer our persisted selection if available (survives hide/show and recycler reuse)
    if not selectedIndex and self._selectedIndex then
        selectedIndex = self._selectedIndex
    end
    -- Fall back to the visible page if the button group lost state
    if not selectedIndex then
        local pages = { self.PageA, self.PageB, self.PageC, self.PageD, self.PageE, self.PageF, self.PageG, self.PageH, self.PageI }
        for i = 1, #pages do
            if pages[i] and pages[i]:IsShown() then selectedIndex = i; break end
        end
    end
    -- Finally, ask the button group, and clamp to first tab if still unknown
    if not selectedIndex and self.tabsGroup and self.tabsGroup.GetSelectedIndex then
        selectedIndex = self.tabsGroup:GetSelectedIndex()
    end
    if not selectedIndex then selectedIndex = 1 end
    local tabs = { self.TabA, self.TabB, self.TabC, self.TabD, self.TabE, self.TabF, self.TabG, self.TabH, self.TabI }
    for i = 1, #tabs do
        style(tabs[i], selectedIndex == i)
    end
end

function ScooterTabbedSectionMixin:Init(initializer)
    local data = initializer and initializer.data or {}
    self:SetTitles(data.sectionTitle or "", data.tabAText or "Tab A", data.tabBText or "Tab B", data.tabCText, data.tabDText, data.tabEText, data.tabFText, data.tabGText, data.tabHText, data.tabIText)
    -- Hide any ad-hoc header controls from prior uses (e.g., Tracked Bars "Enable Custom Textures" row)
    if self.EnableCustomTexturesRow then
        self.EnableCustomTexturesRow:Hide()
    end
    local function ClearChildren(frame)
        if not frame or not frame.GetNumChildren then return end
        for i = frame:GetNumChildren(), 1, -1 do
            local child = select(i, frame:GetChildren())
            if child then child:SetParent(nil); child:Hide() end
        end
    end
    ClearChildren(self.PageA)
    ClearChildren(self.PageB)
    ClearChildren(self.PageC)
    ClearChildren(self.PageD)
    ClearChildren(self.PageE)
    ClearChildren(self.PageF)
    ClearChildren(self.PageG)
    ClearChildren(self.PageH)
    ClearChildren(self.PageI)
    if type(data.build) == "function" then
        data.build(self)
    end
end


