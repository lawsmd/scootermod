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
    local buttons = {}
    if self.TabA then table.insert(buttons, self.TabA) end
    if self.TabB then table.insert(buttons, self.TabB) end
    if self.TabC then table.insert(buttons, self.TabC) end
    if self.TabD then table.insert(buttons, self.TabD) end
    if #buttons == 0 then return end
    self.tabsGroup:AddButtons(buttons)
    self.tabsGroup:SelectAtIndex(1)
    self.tabsGroup:RegisterCallback(ButtonGroupBaseMixin.Event.Selected, function(_, btn)
        self:EvaluateVisibility(btn)
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
        if self.UpdateTabTheme then self:UpdateTabTheme() end
    end, self)
    self:EvaluateVisibility(self.TabA or buttons[1])
    if self.UpdateTabTheme then self:UpdateTabTheme() end
end

function ScooterTabbedSectionMixin:SetTitles(sectionTitle, tabAText, tabBText, tabCText, tabDText)
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
    if self.TabC then
        self.TabC.tabText = tabCText or (self.TabC.tabText or "Tab C")
        if self.TabC.Text then
            self.TabC.Text:SetText(self.TabC.tabText)
            self.TabC:SetWidth(self.TabC.Text:GetStringWidth() + 40)
        end
    end
    if self.TabD then
        self.TabD.tabText = tabDText or (self.TabD.tabText or "Tab D")
        if self.TabD.Text then
            self.TabD.Text:SetText(self.TabD.tabText)
            self.TabD:SetWidth(self.TabD.Text:GetStringWidth() + 40)
        end
    end
    if self.UpdateTabTheme then self:UpdateTabTheme() end
end

function ScooterTabbedSectionMixin:EvaluateVisibility(selected)
    local index = 1
    if self.tabsGroup and self.tabsGroup.GetSelectedIndex then
        index = self.tabsGroup:GetSelectedIndex() or index
    else
        if selected == self.TabA then index = 1
        elseif selected == self.TabB then index = 2
        elseif selected == self.TabC then index = 3
        elseif selected == self.TabD then index = 4 end
    end
    local pages = { self.PageA, self.PageB, self.PageC, self.PageD }
    for i = 1, #pages do
        if pages[i] then pages[i]:SetShown(i == index) end
    end
end

function ScooterTabbedSectionMixin:UpdateTabTheme()
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
    local selectedIndex = (self.tabsGroup and self.tabsGroup.GetSelectedIndex) and self.tabsGroup:GetSelectedIndex() or 1
    local tabs = { self.TabA, self.TabB, self.TabC, self.TabD }
    for i = 1, #tabs do
        style(tabs[i], selectedIndex == i)
    end
end

function ScooterTabbedSectionMixin:Init(initializer)
    local data = initializer and initializer.data or {}
    self:SetTitles(data.sectionTitle or "", data.tabAText or "Tab A", data.tabBText or "Tab B", data.tabCText, data.tabDText)
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
    if type(data.build) == "function" then
        data.build(self)
    end
end


