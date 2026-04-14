local _, addon = ...

local ConfigUI = {
    slotChoices = { "primary", "secondary", "defensive", "interrupt", "utility" },
    rows = {},
    addSlotIndex = 1,
    selectedIndex = 1,
    scrollOffset = 0,
    visibleRows = 12,
    boolControls = {},
    numberControls = {},
}

local boolStates = {
    { value = nil, label = "Any" },
    { value = true, label = "On" },
    { value = false, label = "Off" },
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

local function trim(value)
    value = tostring(value or "")
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    return value
end

local function shortText(value, limit)
    value = tostring(value or "-")
    limit = tonumber(limit) or 32
    if #value <= limit then
        return value
    end
    return string.sub(value, 1, limit - 3) .. "..."
end

local function setWidgetEnabled(widget, enabled)
    if not widget then
        return
    end

    if type(widget.SetEnabled) == "function" then
        widget:SetEnabled(enabled)
        return
    end

    if enabled then
        if type(widget.Enable) == "function" then
            widget:Enable()
        end
    else
        if type(widget.Disable) == "function" then
            widget:Disable()
        end
    end
end

local function getBoolStateIndex(value)
    for index, state in ipairs(boolStates) do
        if state.value == value then
            return index
        end
    end
    return 1
end

local function formatContentScope(scope)
    scope = tostring(scope or "all"):lower()
    if scope == "pve" then
        return "PvE"
    elseif scope == "pvp" then
        return "PvP"
    end
    return "All"
end

function ConfigUI:CurrentAddSlot()
    return self.slotChoices[self.addSlotIndex] or "primary"
end

function ConfigUI:GetSelectedEntry()
    return addon.Registry:Get(self.selectedIndex)
end

function ConfigUI:EnsureSelection()
    local spells = addon.Registry:GetAll()
    if #spells == 0 then
        self.selectedIndex = nil
        return
    end

    if not self.selectedIndex or not spells[self.selectedIndex] then
        self.selectedIndex = 1
    end
end

function ConfigUI:SetSelectedIndex(index)
    index = tonumber(index)
    if index and addon.Registry:Get(index) then
        self.selectedIndex = index
    else
        self.selectedIndex = nil
    end
end

function ConfigUI:CreateListRow(rowIndex)
    local row = createBackdropFrame(nil, self.listPanel)
    row:SetSize(474, 28)
    row:SetPoint("TOPLEFT", self.listPanel, "TOPLEFT", 10, -52 - ((rowIndex - 1) * 30))

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(20, 20)
    row.icon:SetPoint("LEFT", 6, 0)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.name:SetWidth(150)
    row.name:SetJustifyH("LEFT")

    row.slotButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.slotButton:SetSize(74, 20)
    row.slotButton:SetPoint("LEFT", row, "LEFT", 190, 0)
    row.slotButton:SetScript("OnClick", function(button)
        if button.rowIndex then
            addon.Registry:CycleSlot(button.rowIndex)
            self:Refresh()
        end
    end)

    row.priorityMinus = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.priorityMinus:SetSize(22, 20)
    row.priorityMinus:SetPoint("LEFT", row.slotButton, "RIGHT", 6, 0)
    row.priorityMinus:SetText("-")
    row.priorityMinus:SetScript("OnClick", function(button)
        if button.rowIndex then
            addon.Registry:AdjustPriority(button.rowIndex, -5)
            self:Refresh()
        end
    end)

    row.priorityText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.priorityText:SetPoint("LEFT", row.priorityMinus, "RIGHT", 6, 0)
    row.priorityText:SetWidth(26)

    row.priorityPlus = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.priorityPlus:SetSize(22, 20)
    row.priorityPlus:SetPoint("LEFT", row.priorityText, "RIGHT", 6, 0)
    row.priorityPlus:SetText("+")
    row.priorityPlus:SetScript("OnClick", function(button)
        if button.rowIndex then
            addon.Registry:AdjustPriority(button.rowIndex, 5)
            self:Refresh()
        end
    end)

    row.logic = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.logic:SetSize(58, 20)
    row.logic:SetPoint("LEFT", row.priorityPlus, "RIGHT", 8, 0)
    row.logic:SetText("Logic")
    row.logic:SetScript("OnClick", function(button)
        if button.rowIndex then
            self:SetSelectedIndex(button.rowIndex)
            self:Refresh()
        end
    end)

    row.enabled = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.enabled:SetPoint("LEFT", row.logic, "RIGHT", 8, 0)
    row.enabled:SetScript("OnClick", function(button)
        if button.rowIndex then
            addon.Registry:ToggleEnabled(button.rowIndex)
            self:Refresh()
        end
    end)

    row.remove = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.remove:SetSize(58, 20)
    row.remove:SetPoint("LEFT", row.enabled, "RIGHT", 6, 0)
    row.remove:SetText("Remove")
    row.remove:SetScript("OnClick", function(button)
        if button.rowIndex then
            local removingSelected = self.selectedIndex == button.rowIndex
            addon.Registry:RemoveSpell(button.rowIndex)
            if removingSelected then
                self.selectedIndex = nil
            end
            self:Refresh()
        end
    end)

    self.rows[rowIndex] = row
end

function ConfigUI:CreateBoolControl(conditionKey, index)
    local definition = addon.ConditionSchema:GetDefinition(conditionKey)
    local control = CreateFrame("Button", nil, self.editorPanel, "UIPanelButtonTemplate")
    control:SetSize(72, 20)
    control.conditionKey = conditionKey
    control.stateIndex = 1
    control:SetScript("OnClick", function(button)
        local entry = self:GetSelectedEntry()
        if not entry then
            return
        end

        button.stateIndex = button.stateIndex + 1
        if button.stateIndex > #boolStates then
            button.stateIndex = 1
        end

        local state = boolStates[button.stateIndex]
        addon.Registry:SetCondition(self.selectedIndex, button.conditionKey, state.value)
        self:Refresh()
    end)

    local label = self.editorPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("RIGHT", control, "LEFT", -8, 0)
    label:SetWidth(130)
    label:SetJustifyH("RIGHT")
    label:SetText(definition and definition.label or conditionKey)

    control.label = label
    self.boolControls[#self.boolControls + 1] = control
end

function ConfigUI:CreateNumberControl(conditionKey, index)
    local definition = addon.ConditionSchema:GetDefinition(conditionKey)
    local label = self.editorPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetWidth(132)
    label:SetJustifyH("LEFT")
    label:SetText(definition and definition.label or conditionKey)

    local box = CreateFrame("EditBox", nil, self.editorPanel, "InputBoxTemplate")
    box:SetSize(56, 22)
    box:SetPoint("LEFT", label, "RIGHT", 8, 0)
    box:SetAutoFocus(false)
    box:SetNumeric(true)
    box.conditionKey = conditionKey

    local function saveNumber(editBox)
        local entry = self:GetSelectedEntry()
        if not entry then
            return
        end
        local text = trim(editBox:GetText())
        addon.Registry:SetCondition(self.selectedIndex, editBox.conditionKey, text ~= "" and tonumber(text) or nil)
        self:Refresh()
    end

    box:SetScript("OnEnterPressed", function(editBox)
        saveNumber(editBox)
        editBox:ClearFocus()
    end)
    box:SetScript("OnEditFocusLost", saveNumber)

    box.label = label
    self.numberControls[#self.numberControls + 1] = box
end

function ConfigUI:LayoutEditor()
    if not self.editorPanel then
        return
    end

    local panel = self.editorPanel
    local function setTopLeft(widget, x, y)
        widget:ClearAllPoints()
        widget:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -y)
    end

    setTopLeft(self.noteLabel, 16, 84)
    setTopLeft(self.noteBox, 16, 108)

    setTopLeft(self.summaryLabel, 16, 144)
    setTopLeft(self.summaryText, 16, 164)
    self.summaryText:SetWidth(454)
    self.summaryText:SetJustifyH("LEFT")
    self.summaryText:SetJustifyV("TOP")
    self.summaryText:SetWordWrap(false)
    self.summaryText:SetHeight(40)

    local cursorY = 214

    setTopLeft(self.boolHeader, 16, cursorY)
    local boolTop = cursorY + 28
    for index, control in ipairs(self.boolControls) do
        local column = (index - 1) % 2
        local row = math.floor((index - 1) / 2)
        control:ClearAllPoints()
        control:SetPoint("TOPLEFT", panel, "TOPLEFT", 140 + (column * 234), -(boolTop + (row * 24)))
    end

    local boolRows = math.max(math.ceil(#self.boolControls / 2), 1)
    cursorY = boolTop + ((boolRows - 1) * 24) + 30

    setTopLeft(self.rangeLabel, 22, cursorY)
    self.rangeButton:ClearAllPoints()
    self.rangeButton:SetPoint("LEFT", self.rangeLabel, "RIGHT", 12, 0)

    cursorY = cursorY + 28
    setTopLeft(self.numberHeader, 16, cursorY)
    local numberTop = cursorY + 24
    for index, box in ipairs(self.numberControls) do
        local column = (index - 1) % 3
        local row = math.floor((index - 1) / 3)
        local baseX = 22 + (column * 150)
        if box.label then
            box.label:ClearAllPoints()
            box.label:SetPoint("TOPLEFT", panel, "TOPLEFT", baseX, -(numberTop + (row * 26)))
            box.label:SetWidth(92)
        end
        box:ClearAllPoints()
        box:SetPoint("LEFT", box.label, "RIGHT", 8, 0)
    end

    self.advancedHeader:Hide()
    self.advancedText:Hide()
end

function ConfigUI:SetScrollOffset(offset)
    local total = #(addon.Registry:GetAll() or {})
    local maxOffset = math.max(total - self.visibleRows, 0)
    self.scrollOffset = math.max(0, math.min(tonumber(offset) or 0, maxOffset))
    if self.listScrollFrame and type(FauxScrollFrame_SetOffset) == "function" then
        FauxScrollFrame_SetOffset(self.listScrollFrame, self.scrollOffset)
    end
end

function ConfigUI:EnsureSelectionVisible()
    if not self.selectedIndex then
        return
    end

    if self.selectedIndex <= self.scrollOffset then
        self:SetScrollOffset(self.selectedIndex - 1)
    elseif self.selectedIndex > (self.scrollOffset + self.visibleRows) then
        self:SetScrollOffset(self.selectedIndex - self.visibleRows)
    end
end

function ConfigUI:Initialize()
    if self.frame then
        return
    end

    self.frame = createBackdropFrame("SimplyMidnightConfigFrame", UIParent)
    self.frame:SetSize(1040, 690)
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
    self.subTitle:SetText("Basic logic editing is now live for shared conditions. Complex aura and custom-rule editing stays reserved for later phases.")

    self.defaultsButton = CreateFrame("Button", nil, self.frame, "UIPanelButtonTemplate")
    self.defaultsButton:SetSize(110, 22)
    self.defaultsButton:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -38, -34)
    self.defaultsButton:SetText("Defaults")
    self.defaultsButton:SetScript("OnClick", function()
        local ok, info = addon.Registry:EnsureCurrentPack(false)
        addon:Print(info or (ok and "Installed current spec defaults" or "Could not install defaults"))
        self:Refresh()
    end)

    self.resetButton = CreateFrame("Button", nil, self.frame, "UIPanelButtonTemplate")
    self.resetButton:SetSize(110, 22)
    self.resetButton:SetPoint("RIGHT", self.defaultsButton, "LEFT", -8, 0)
    self.resetButton:SetText("Reset Spec")
    self.resetButton:SetScript("OnClick", function()
        local ok, info = addon.Registry:ResetCurrentPack()
        addon:Print(info or (ok and "Reset current spec defaults" or "Could not reset defaults"))
        self:Refresh()
    end)

    self.closeButton = CreateFrame("Button", nil, self.frame, "UIPanelCloseButton")
    self.closeButton:SetPoint("TOPRIGHT", -4, -4)

    local addLabel = self.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    addLabel:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 16, -58)
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
            self.selectedIndex = #addon.Registry:GetAll()
            self:Refresh()
        else
            addon:Print(info or "Could not add spell")
        end
    end)

    self.listPanel = createBackdropFrame(nil, self.frame)
    self.listPanel:SetSize(504, 580)
    self.listPanel:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 16, -92)
    self.listPanel:EnableMouseWheel(true)
    self.listPanel:SetScript("OnMouseWheel", function(_, delta)
        self:SetScrollOffset(self.scrollOffset - delta)
        self:RefreshList()
    end)

    self.listHeader = self.listPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.listHeader:SetPoint("TOPLEFT", self.listPanel, "TOPLEFT", 10, -12)
    self.listHeader:SetText("Icon / Name / Slot / Priority / Logic / Enabled / Remove")

    self.listScrollFrame = CreateFrame("ScrollFrame", nil, self.listPanel, "FauxScrollFrameTemplate")
    self.listScrollFrame:SetPoint("TOPRIGHT", self.listPanel, "TOPRIGHT", -6, -46)
    self.listScrollFrame:SetPoint("BOTTOMRIGHT", self.listPanel, "BOTTOMRIGHT", -6, 10)
    self.listScrollFrame:SetWidth(20)
    self.listScrollFrame:SetScript("OnVerticalScroll", function(scrollFrame, offset)
        FauxScrollFrame_OnVerticalScroll(scrollFrame, offset, 30, function()
            self.scrollOffset = FauxScrollFrame_GetOffset(scrollFrame) or 0
            self:RefreshList()
        end)
    end)

    for rowIndex = 1, self.visibleRows do
        self:CreateListRow(rowIndex)
    end

    self.editorPanel = createBackdropFrame(nil, self.frame)
    self.editorPanel:SetSize(488, 580)
    self.editorPanel:SetPoint("TOPLEFT", self.listPanel, "TOPRIGHT", 12, 0)

    self.editorTitle = self.editorPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.editorTitle:SetPoint("TOPLEFT", self.editorPanel, "TOPLEFT", 14, -12)
    self.editorTitle:SetText("Logic Editor")

    self.selectedIcon = self.editorPanel:CreateTexture(nil, "ARTWORK")
    self.selectedIcon:SetSize(34, 34)
    self.selectedIcon:SetPoint("TOPLEFT", self.editorPanel, "TOPLEFT", 16, -34)

    self.selectedName = self.editorPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.selectedName:SetPoint("TOPLEFT", self.selectedIcon, "TOPRIGHT", 10, -2)
    self.selectedName:SetWidth(300)
    self.selectedName:SetJustifyH("LEFT")

    self.selectedMeta = self.editorPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.selectedMeta:SetPoint("TOPLEFT", self.selectedName, "BOTTOMLEFT", 0, -4)
    self.selectedMeta:SetWidth(300)
    self.selectedMeta:SetJustifyH("LEFT")

    self.scopeButton = CreateFrame("Button", nil, self.editorPanel, "UIPanelButtonTemplate")
    self.scopeButton:SetSize(78, 22)
    self.scopeButton:SetPoint("TOPRIGHT", self.editorPanel, "TOPRIGHT", -14, -36)
    self.scopeButton:SetScript("OnClick", function()
        if self.selectedIndex then
            addon.Registry:CycleContentScope(self.selectedIndex)
            self:Refresh()
        end
    end)

    self.clearConditionsButton = CreateFrame("Button", nil, self.editorPanel, "UIPanelButtonTemplate")
    self.clearConditionsButton:SetSize(110, 22)
    self.clearConditionsButton:SetPoint("RIGHT", self.scopeButton, "LEFT", -8, 0)
    self.clearConditionsButton:SetText("Clear Simple")
    self.clearConditionsButton:SetScript("OnClick", function()
        if self.selectedIndex then
            addon.Registry:ClearEditableConditions(self.selectedIndex)
            self:Refresh()
        end
    end)

    self.noteLabel = self.editorPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.noteLabel:SetPoint("TOPLEFT", self.editorPanel, "TOPLEFT", 16, -84)
    self.noteLabel:SetText("Suggestion Note")

    self.noteBox = CreateFrame("EditBox", nil, self.editorPanel, "InputBoxTemplate")
    self.noteBox:SetSize(454, 24)
    self.noteBox:SetPoint("TOPLEFT", self.noteLabel, "BOTTOMLEFT", 0, -8)
    self.noteBox:SetAutoFocus(false)
    self.noteBox:SetScript("OnEnterPressed", function(editBox)
        if self.selectedIndex then
            addon.Registry:SetNote(self.selectedIndex, editBox:GetText())
            self:Refresh()
        end
        editBox:ClearFocus()
    end)
    self.noteBox:SetScript("OnEditFocusLost", function(editBox)
        if self.selectedIndex then
            addon.Registry:SetNote(self.selectedIndex, editBox:GetText())
            self:Refresh()
        end
    end)

    self.summaryLabel = self.editorPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.summaryLabel:SetPoint("TOPLEFT", self.noteBox, "BOTTOMLEFT", 0, -12)
    self.summaryLabel:SetText("Current Logic Summary")

    self.summaryText = self.editorPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.summaryText:SetPoint("TOPLEFT", self.summaryLabel, "BOTTOMLEFT", 0, -6)
    self.summaryText:SetWidth(454)
    self.summaryText:SetJustifyH("LEFT")
    self.summaryText:SetJustifyV("TOP")
    self.summaryText:SetWordWrap(true)

    self.boolHeader = self.editorPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.boolHeader:SetPoint("TOPLEFT", self.editorPanel, "TOPLEFT", 16, -170)
    self.boolHeader:SetText("Shared Boolean Gates")

    for index, key in ipairs(addon.ConditionSchema:GetBoolOrder()) do
        self:CreateBoolControl(key, index)
    end

    self.rangeLabel = self.editorPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.rangeLabel:SetPoint("TOPLEFT", self.editorPanel, "TOPLEFT", 22, -352)
    self.rangeLabel:SetText("Range Bucket")

    self.rangeButton = CreateFrame("Button", nil, self.editorPanel, "UIPanelButtonTemplate")
    self.rangeButton:SetSize(110, 20)
    self.rangeButton:SetPoint("LEFT", self.rangeLabel, "RIGHT", 12, 0)
    self.rangeButton:SetScript("OnClick", function(button)
        local entry = self:GetSelectedEntry()
        if not entry then
            return
        end

        local currentValue = addon.Registry:GetCondition(self.selectedIndex, "rangeBucket")
        local nextValue = nil
        local options = addon.ConditionSchema:GetRangeOptions()
        for index, option in ipairs(options) do
            if option.value == currentValue then
                local nextOption = options[index + 1] or options[1]
                nextValue = nextOption.value
                break
            end
        end
        if nextValue == nil and options[1] then
            nextValue = options[1].value
        end

        addon.Registry:SetCondition(self.selectedIndex, "rangeBucket", nextValue)
        self:Refresh()
    end)

    self.numberHeader = self.editorPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.numberHeader:SetPoint("TOPLEFT", self.editorPanel, "TOPLEFT", 16, -382)
    self.numberHeader:SetText("Shared Numeric Gates")

    for index, key in ipairs(addon.ConditionSchema:GetNumberOrder()) do
        self:CreateNumberControl(key, index)
    end

    self.advancedHeader = self.editorPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.advancedHeader:SetPoint("TOPLEFT", self.editorPanel, "TOPLEFT", 16, -318)
    self.advancedHeader:SetText("Advanced Rule Placeholder")

    self.advancedText = self.editorPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.advancedText:SetPoint("TOPLEFT", self.advancedHeader, "BOTTOMLEFT", 0, -6)
    self.advancedText:SetWidth(454)
    self.advancedText:SetJustifyH("LEFT")
    self.advancedText:SetText("Custom rule text, aura builders, and full logic editing are still reserved. This panel now handles shared gates and keeps unsupported pack logic intact.")
    self.advancedHeader:Hide()
    self.advancedText:Hide()

    self.footer = self.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.footer:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", 16, 18)
    self.footer:SetWidth(1000)
    self.footer:SetJustifyH("LEFT")
    self.footer:SetText("Selection-aware logic editor is active. Complex aura logic still stays preserved even if it is not yet editable from the UI.")
end

function ConfigUI:RefreshList()
    local spells = addon.Registry:GetAll()
    local totalEntries = #spells

    self:EnsureSelectionVisible()

    for rowOffset = 1, #self.rows do
        local row = self.rows[rowOffset]
        local actualIndex = rowOffset + self.scrollOffset
        local entry = spells[actualIndex]
        if entry then
            row:Show()
            row.icon:SetTexture(addon:GetSpellTexture(entry.spellID) or addon.constants.questionMarkIcon)
            row.name:SetText(shortText((addon:GetSpellName(entry.spellID) or ("Spell " .. tostring(entry.spellID))), 26))
            row.slotButton:SetText(entry.slot)
            row.priorityText:SetText(tostring(entry.priority))
            row.enabled:SetChecked(entry.enabled)
            row.logic:SetText(self.selectedIndex == actualIndex and "Editing" or "Logic")

            if self.selectedIndex == actualIndex then
                row:SetBackdropBorderColor(1.0, 0.82, 0.25, 0.95)
            else
                row:SetBackdropBorderColor(0.25, 0.55, 1.0, 0.9)
            end

            row.slotButton.rowIndex = actualIndex
            row.priorityMinus.rowIndex = actualIndex
            row.priorityPlus.rowIndex = actualIndex
            row.logic.rowIndex = actualIndex
            row.enabled.rowIndex = actualIndex
            row.remove.rowIndex = actualIndex
        else
            row:Hide()
        end
    end

    if self.listScrollFrame and type(FauxScrollFrame_Update) == "function" then
        FauxScrollFrame_Update(self.listScrollFrame, totalEntries, self.visibleRows, 30)
        self.scrollOffset = FauxScrollFrame_GetOffset(self.listScrollFrame) or self.scrollOffset
    end

    if totalEntries > #self.rows then
        local firstVisible = math.min(self.scrollOffset + 1, totalEntries)
        local lastVisible = math.min(self.scrollOffset + #self.rows, totalEntries)
        self.footer:SetText("Pack: " .. addon.Registry:GetCurrentPackLabel() .. string.format(" | showing %d-%d of %d spells. Use the mouse wheel or scroll bar to browse.", firstVisible, lastVisible, totalEntries))
    else
        self.footer:SetText("Pack: " .. addon.Registry:GetCurrentPackLabel() .. " | select a spell to edit shared conditions on the right.")
    end
end

function ConfigUI:RefreshEditor()
    local entry = self:GetSelectedEntry()
    local hasEntry = entry ~= nil
    local summary = addon.ConditionSchema:SummarizeEntry(entry)
    local spellName = hasEntry and (addon:GetSpellName(entry.spellID) or ("Spell " .. tostring(entry.spellID))) or "No spell selected"

    self.selectedIcon:SetTexture(hasEntry and (addon:GetSpellTexture(entry.spellID) or addon.constants.questionMarkIcon) or addon.constants.questionMarkIcon)
    self.selectedName:SetText(hasEntry and (spellName .. " (" .. tostring(entry.spellID) .. ")") or "No spell selected")
    self.selectedMeta:SetText(hasEntry and string.format("slot=%s | prio=%s | scope=%s | source=%s", tostring(entry.slot), tostring(entry.priority), formatContentScope(entry.contentScope), tostring(entry.source or "manual")) or "Select a spell from the list to edit its shared logic.")

    local summaryLines = {}
    if hasEntry then
        if entry.note and entry.note ~= "" then
            summaryLines[#summaryLines + 1] = shortText("Note: " .. entry.note, 88)
        end
        if summary and #summary.simple > 0 then
            summaryLines[#summaryLines + 1] = shortText("Simple: " .. table.concat(summary.simple, " | "), 88)
        else
            summaryLines[#summaryLines + 1] = "Simple: no shared conditions yet"
        end
        if summary and #summary.complex > 0 then
            summaryLines[#summaryLines + 1] = shortText("Complex: " .. table.concat(summary.complex, ", "), 88)
        else
            summaryLines[#summaryLines + 1] = "Complex preserved: none"
        end
    else
        summaryLines[#summaryLines + 1] = "Simple: unavailable"
        summaryLines[#summaryLines + 1] = "Complex preserved: unavailable"
    end
    self.summaryText:SetText(table.concat(summaryLines, "\n"))
    self:LayoutEditor()

    self.scopeButton:SetText(hasEntry and formatContentScope(entry.contentScope) or "Scope")
    setWidgetEnabled(self.scopeButton, hasEntry)
    setWidgetEnabled(self.clearConditionsButton, hasEntry)
    setWidgetEnabled(self.rangeButton, hasEntry)
    setWidgetEnabled(self.noteBox, hasEntry)
    if not (type(self.noteBox.HasFocus) == "function" and self.noteBox:HasFocus()) then
        self.noteBox:SetText(hasEntry and tostring(entry.note or "") or "")
    end

    local currentRange = hasEntry and addon.Registry:GetCondition(self.selectedIndex, "rangeBucket") or nil
    local rangeText = "Any Range"
    for _, option in ipairs(addon.ConditionSchema:GetRangeOptions()) do
        if option.value == currentRange then
            rangeText = option.label
            break
        end
    end
    self.rangeButton:SetText(rangeText)

    for _, control in ipairs(self.boolControls) do
        local currentValue = hasEntry and addon.Registry:GetCondition(self.selectedIndex, control.conditionKey) or nil
        local stateIndex = getBoolStateIndex(currentValue)
        control.stateIndex = stateIndex
        control:SetText(boolStates[stateIndex].label)
        setWidgetEnabled(control, hasEntry)
    end

    for _, box in ipairs(self.numberControls) do
        local currentValue = hasEntry and addon.Registry:GetCondition(self.selectedIndex, box.conditionKey) or nil
        setWidgetEnabled(box, hasEntry)
        if not (type(box.HasFocus) == "function" and box:HasFocus()) then
            box:SetText(currentValue ~= nil and tostring(currentValue) or "")
        end
    end
end

function ConfigUI:Refresh()
    if not self.frame then
        return
    end

    self:EnsureSelection()
    self:RefreshList()
    self:RefreshEditor()
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
