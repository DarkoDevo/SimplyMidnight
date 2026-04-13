local _, addon = ...

local ConfigUI = {
    slotChoices = { "primary", "secondary", "defensive", "interrupt", "utility" },
    rows = {},
    addSlotIndex = 1,
}

local function createBackdropFrame(name, parent)
    local frame = CreateFrame("Frame", name, parent, "BackdropTemplate")
    frame:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true,
        tileSize = 8,
        edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    frame:SetBackdropColor(0.02, 0.02, 0.03, 0.94)
    frame:SetBackdropBorderColor(0.25, 0.55, 1.0, 0.9)
    return frame
end

function ConfigUI:CurrentAddSlot()
    return self.slotChoices[self.addSlotIndex] or "primary"
end

function ConfigUI:Initialize()
    if self.frame then
        return
    end

    self.frame = createBackdropFrame("SimplyMidnightConfigFrame", UIParent)
    self.frame:SetSize(620, 420)
    self.frame:SetPoint("CENTER")
    self.frame:SetMovable(true)
    self.frame:EnableMouse(true)
    self.frame:RegisterForDrag("LeftButton")
    self.frame:SetScript("OnDragStart", function(frame) frame:StartMoving() end)
    self.frame:SetScript("OnDragStop", function(frame) frame:StopMovingOrSizing() end)
    self.frame:Hide()

    self.title = self.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    self.title:SetPoint("TOPLEFT", 14, -12)
    self.title:SetText("SimplyMidnight Spell Registry")

    self.subTitle = self.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.subTitle:SetPoint("TOPLEFT", self.title, "BOTTOMLEFT", 0, -4)
    self.subTitle:SetText("Foundation editor: add spells, move slots, reorder priority. Advanced logic UI comes later.")

    self.closeButton = CreateFrame("Button", nil, self.frame, "UIPanelCloseButton")
    self.closeButton:SetPoint("TOPRIGHT", -4, -4)

    local addLabel = self.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    addLabel:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 16, -56)
    addLabel:SetText("Add spell")

    self.spellIDBox = CreateFrame("EditBox", nil, self.frame, "InputBoxTemplate")
    self.spellIDBox:SetSize(90, 24)
    self.spellIDBox:SetPoint("LEFT", addLabel, "RIGHT", 12, 0)
    self.spellIDBox:SetAutoFocus(false)
    self.spellIDBox:SetNumeric(true)

    self.priorityBox = CreateFrame("EditBox", nil, self.frame, "InputBoxTemplate")
    self.priorityBox:SetSize(60, 24)
    self.priorityBox:SetPoint("LEFT", self.spellIDBox, "RIGHT", 10, 0)
    self.priorityBox:SetAutoFocus(false)
    self.priorityBox:SetNumeric(true)
    self.priorityBox:SetText("50")

    self.slotButton = CreateFrame("Button", nil, self.frame, "UIPanelButtonTemplate")
    self.slotButton:SetSize(110, 24)
    self.slotButton:SetPoint("LEFT", self.priorityBox, "RIGHT", 10, 0)
    self.slotButton:SetText(self:CurrentAddSlot())
    self.slotButton:SetScript("OnClick", function()
        self.addSlotIndex = self.addSlotIndex + 1
        if self.addSlotIndex > #self.slotChoices then
            self.addSlotIndex = 1
        end
        self.slotButton:SetText(self:CurrentAddSlot())
    end)

    self.addButton = CreateFrame("Button", nil, self.frame, "UIPanelButtonTemplate")
    self.addButton:SetSize(90, 24)
    self.addButton:SetPoint("LEFT", self.slotButton, "RIGHT", 10, 0)
    self.addButton:SetText("Add")
    self.addButton:SetScript("OnClick", function()
        local spellID = tonumber(self.spellIDBox:GetText())
        local priority = tonumber(self.priorityBox:GetText()) or 50
        local ok, info = addon.Registry:AddSpell(spellID, self:CurrentAddSlot(), priority)
        if ok then
            addon:Print("Added " .. tostring(info))
            self.spellIDBox:SetText("")
            self:Refresh()
        else
            addon:Print(info or "Could not add spell")
        end
    end)

    local header = self.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    header:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 16, -92)
    header:SetText("Icon / Name / Slot / Priority / Enabled / Remove")

    for rowIndex = 1, 10 do
        local row = createBackdropFrame(nil, self.frame)
        row:SetSize(586, 26)
        row:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 16, -100 - (rowIndex * 28))

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(20, 20)
        row.icon:SetPoint("LEFT", 6, 0)

        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
        row.name:SetWidth(220)
        row.name:SetJustifyH("LEFT")

        row.slotButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.slotButton:SetSize(90, 20)
        row.slotButton:SetPoint("LEFT", row, "LEFT", 258, 0)
        row.slotButton:SetScript("OnClick", function(button)
            if not button.rowIndex then
                return
            end
            addon.Registry:CycleSlot(button.rowIndex)
            self:Refresh()
        end)

        row.priorityMinus = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.priorityMinus:SetSize(22, 20)
        row.priorityMinus:SetPoint("LEFT", row.slotButton, "RIGHT", 10, 0)
        row.priorityMinus:SetText("-")
        row.priorityMinus:SetScript("OnClick", function(button)
            if not button.rowIndex then
                return
            end
            addon.Registry:AdjustPriority(button.rowIndex, -5)
            self:Refresh()
        end)

        row.priorityText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.priorityText:SetPoint("LEFT", row.priorityMinus, "RIGHT", 8, 0)
        row.priorityText:SetWidth(28)

        row.priorityPlus = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.priorityPlus:SetSize(22, 20)
        row.priorityPlus:SetPoint("LEFT", row.priorityText, "RIGHT", 8, 0)
        row.priorityPlus:SetText("+")
        row.priorityPlus:SetScript("OnClick", function(button)
            if not button.rowIndex then
                return
            end
            addon.Registry:AdjustPriority(button.rowIndex, 5)
            self:Refresh()
        end)

        row.enabled = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        row.enabled:SetPoint("LEFT", row.priorityPlus, "RIGHT", 12, 0)
        row.enabled:SetScript("OnClick", function(button)
            if not button.rowIndex then
                return
            end
            addon.Registry:ToggleEnabled(button.rowIndex)
            self:Refresh()
        end)

        row.remove = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.remove:SetSize(70, 20)
        row.remove:SetPoint("LEFT", row.enabled, "RIGHT", 12, 0)
        row.remove:SetText("Remove")
        row.remove:SetScript("OnClick", function(button)
            if not button.rowIndex then
                return
            end
            addon.Registry:RemoveSpell(button.rowIndex)
            self:Refresh()
        end)

        self.rows[rowIndex] = row
    end

    self.footer = self.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.footer:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", 16, 18)
    self.footer:SetWidth(580)
    self.footer:SetJustifyH("LEFT")
    self.footer:SetText("Future foundation already reserved in Registry.conditions and Registry.advancedRule.")
end

function ConfigUI:Refresh()
    if not self.frame then
        return
    end

    local spells = addon.Registry:GetAll()
    for rowOffset = 1, #self.rows do
        local row = self.rows[rowOffset]
        local entry = spells[rowOffset]
        if entry then
            row:Show()
            row.icon:SetTexture(addon:GetSpellTexture(entry.spellID) or addon.constants.questionMarkIcon)
            row.name:SetText((addon:GetSpellName(entry.spellID) or ("Spell " .. tostring(entry.spellID))) .. " (" .. tostring(entry.spellID) .. ")")
            row.slotButton:SetText(entry.slot)
            row.priorityText:SetText(tostring(entry.priority))
            row.enabled:SetChecked(entry.enabled)

            row.slotButton.rowIndex = rowOffset
            row.priorityMinus.rowIndex = rowOffset
            row.priorityPlus.rowIndex = rowOffset
            row.enabled.rowIndex = rowOffset
            row.remove.rowIndex = rowOffset
        else
            row:Hide()
        end
    end

    if #spells > #self.rows then
        self.footer:SetText("Showing first " .. #self.rows .. " spells. More list UI and logic editing will come in later phases.")
    else
        self.footer:SetText("Future foundation already reserved in Registry.conditions and Registry.advancedRule.")
    end
end

function ConfigUI:Toggle()
    if not self.frame then
        return
    end

    if self.frame:IsShown() then
        self.frame:Hide()
    else
        self:Refresh()
        self.frame:Show()
    end
end

addon.ConfigUI = ConfigUI

