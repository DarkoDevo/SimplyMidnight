local _, addon = ...

local ExportHUD = {
    iconFrames = {},
    stateCells = {},
    bars = {},
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
    frame:SetBackdropColor(0.05, 0.05, 0.08, 0.85)
    frame:SetBackdropBorderColor(0.2, 0.6, 1.0, 0.75)
    return frame
end

local function colorFromSpellID(spellID)
    spellID = tonumber(spellID) or 0
    local red = bit.band(spellID, 255) / 255
    local green = bit.band(bit.rshift(spellID, 8), 255) / 255
    local blue = bit.band(bit.rshift(spellID, 16), 255) / 255
    return red, green, blue
end

local function setBar(texture, valuePct)
    if not texture then
        return
    end

    valuePct = math.max(0, math.min(valuePct or 0, 100))
    texture:SetWidth((texture.__maxWidth or 1) * (valuePct / 100))
end

local function shortText(value, limit)
    value = tostring(value or "-")
    limit = tonumber(limit) or 24
    if #value <= limit then
        return value
    end

    if limit <= 3 then
        return string.sub(value, 1, limit)
    end

    return string.sub(value, 1, limit - 3) .. "..."
end

local function shortBool(value)
    return value and "Y" or "N"
end

local function compactStatusText(value, options)
    value = tostring(value or "-")
    options = options or {}

    if options.stripPrefix and options.stripPrefix ~= "" then
        value = value:gsub("^" .. options.stripPrefix .. "%s*", "")
    end

    if options.replacements then
        for _, replacement in ipairs(options.replacements) do
            value = value:gsub(replacement[1], replacement[2])
        end
    end

    return shortText(value, options.limit or 28)
end

local function statusTag(isKnown, isEstimated)
    if isEstimated then
        return "EST"
    end
    return isKnown and "OK" or "UNK"
end

local function formatPct(value, isKnown)
    if not isKnown then
        return "?"
    end

    value = tonumber(value) or 0
    return string.format("%.1f%%", value)
end

local function formatResourceLine(label, current, pct, currentKnown, pctKnown, estimated)
    if currentKnown and pctKnown then
        return string.format("%s=%s (%d) [%s]", label, formatPct(pct, true), tonumber(current) or 0, statusTag(true, estimated))
    end

    if currentKnown then
        return string.format("%s=? (%d) [%s]", label, tonumber(current) or 0, statusTag(true, estimated))
    end

    if pctKnown then
        return string.format("%s=%s (?) [%s]", label, formatPct(pct, true), statusTag(true, estimated))
    end

    if not currentKnown and not pctKnown then
        return string.format("%s=? [%s]", label, statusTag(false, estimated))
    end

    return string.format("%s=? [%s]", label, statusTag(false, estimated))
end

local function getSlotShortLabel(slot)
    return string.upper(string.sub(slot or "?", 1, 1))
end

local function getEntryName(entry)
    if not entry or not entry.spellID then
        return "-"
    end

    return addon:GetSpellName(entry.spellID) or tostring(entry.spellID)
end

function ExportHUD:SavePosition()
    local point, _, relativePoint, xOfs, yOfs = self.frame:GetPoint(1)
    addon.db.hud.point = point
    addon.db.hud.relativePoint = relativePoint
    addon.db.hud.x = math.floor(xOfs)
    addon.db.hud.y = math.floor(yOfs)
    addon:NotifyCompatibilityChanged()
end

function ExportHUD:ApplyPosition()
    self.frame:ClearAllPoints()
    self.frame:SetPoint(
        addon.db.hud.point,
        UIParent,
        addon.db.hud.relativePoint,
        addon.db.hud.x,
        addon.db.hud.y
    )
    self.frame:SetScale(addon.db.hud.scale or 1)
end

function ExportHUD:SetLocked(locked)
    addon.db.hud.locked = locked and true or false
    self.frame:EnableMouse(not addon.db.hud.locked)
    self.dragHint:SetShown(not addon.db.hud.locked)
    addon:NotifyCompatibilityChanged()
end

function ExportHUD:ToggleLocked()
    self:SetLocked(not addon.db.hud.locked)
end

function ExportHUD:CreateIcon(slot)
    local iconFrame = createBackdropFrame(nil, self.frame)

    iconFrame.texture = iconFrame:CreateTexture(nil, "ARTWORK")
    iconFrame.texture:SetAllPoints()
    iconFrame.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    iconFrame.checksum = iconFrame:CreateTexture(nil, "OVERLAY")
    iconFrame.checksum:SetPoint("BOTTOMRIGHT", -2, 2)

    iconFrame.label = iconFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    iconFrame.label:SetText(slot)

    self.iconFrames[slot] = iconFrame
end

function ExportHUD:CreateStateCell(key)
    local cell = self.frame:CreateTexture(nil, "OVERLAY")
    local label = self.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetText(string.sub(key, 1, 1):upper())

    self.stateCells[key] = {
        texture = cell,
        label = label,
    }
end

function ExportHUD:CreateBar(labelText, color)
    local label = self.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetText(labelText)

    local holder = createBackdropFrame(nil, self.frame)
    local fill = holder:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("LEFT", holder, "LEFT", 2, 0)
    fill:SetTexture("Interface/Buttons/WHITE8X8")
    fill:SetVertexColor(color[1], color[2], color[3], 0.95)

    return {
        label = label,
        holder = holder,
        fill = fill,
        defaultLabel = labelText,
    }
end

function ExportHUD:CreateDebugPanel()
    self.debugPanel = createBackdropFrame(nil, self.frame)
    self.debugPanel:Hide()

    self.debugLines = {}
    for index = 1, 8 do
        local line = self.debugPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        line:SetJustifyH("LEFT")
        line:SetWordWrap(false)
        self.debugLines[index] = line
    end
end

function ExportHUD:GetDiagnosticLines(state, recommendations)
    local diagnostics = recommendations and recommendations.diagnostics and recommendations.diagnostics.slots or {}
    local compatStatus = addon.Compatibility and addon.Compatibility:GetStatusLine() or "compat: unavailable"
    local adapterStatus = addon.SimplyGladAdapter and addon.SimplyGladAdapter:GetStatusLine() or "adapter: unavailable"
    local taintStatus = addon.TaintGuard and addon.TaintGuard:GetStatusLine() or "taint: unavailable"
    local packLabel = addon.Registry and addon.Registry:GetCurrentPackLabel() or "unknown pack"
    local uiScale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
    local compactCompatStatus = compactStatusText(compatStatus, {
        stripPrefix = "compat:",
        replacements = {
            { "risks", "risk" },
            { "^unavailable$", "compat unavailable" },
        },
        limit = 18,
    })
    local compactAdapterStatus = compactStatusText(adapterStatus, {
        stripPrefix = "adapter:",
        replacements = {
            { "^SimplyGlad%s*", "SG " },
            { "profile=", "" },
            { "Death Knight", "DK" },
            { "Beast Mastery", "BM" },
            { "^unavailable$", "adapter unavailable" },
        },
        limit = 28,
    })
    local compactTaintStatus = compactStatusText(taintStatus, {
        stripPrefix = "taint:",
        replacements = {
            { "^clear$", "taint clear" },
            { "^unavailable$", "taint unavailable" },
        },
        limit = 22,
    })

    local slotLine = {}
    local reasonSegments = {}
    for _, slot in ipairs(addon:GetSlotOrder()) do
        local slotKey = getSlotShortLabel(slot)
        local selectedEntry = recommendations and recommendations.slots and recommendations.slots[slot] or nil
        local slotDiagnostics = diagnostics and diagnostics[slot] or nil
        local chosenName = shortText(getEntryName(selectedEntry), 14)
        slotLine[#slotLine + 1] = string.format("%s=%s", slotKey, chosenName)

        local slotMessage = "-"
        if slotDiagnostics and slotDiagnostics.selected and slotDiagnostics.selected.note then
            slotMessage = shortText(slotDiagnostics.selected.note, 18)
        elseif slotDiagnostics and slotDiagnostics.selected and slotDiagnostics.selected.name then
            slotMessage = "selected"
        elseif slotDiagnostics and slotDiagnostics.rejected and slotDiagnostics.rejected[1] then
            slotMessage = shortText(slotDiagnostics.rejected[1].reason, 18)
        elseif slotDiagnostics and slotDiagnostics.empty then
            slotMessage = "no entries"
        elseif recommendations and recommendations.diagnostics and recommendations.diagnostics.paused then
            slotMessage = "paused"
        end

        reasonSegments[#reasonSegments + 1] = string.format("%s:%s", slotKey, shortText(slotMessage, 16))
    end

    local groupedReasonLines = {}
    for index, segment in ipairs(reasonSegments) do
        local groupIndex = math.floor((index - 1) / 3) + 1
        groupedReasonLines[groupIndex] = groupedReasonLines[groupIndex] or {}
        groupedReasonLines[groupIndex][#groupedReasonLines[groupIndex] + 1] = segment
    end

    return {
        string.format("pack=%s | spec=%s | mode=%s | enemies=%d", shortText(packLabel, 26), tostring(state.player.specID or "-"), tostring(state.mode or "-"), tonumber(state.environment.enemyCount) or 0),
        string.format("player c=%s mv=%s mt=%s pet=%s/%s | modes b=%s c=%s h=%s p=%s", shortBool(state.player.inCombat), shortBool(state.player.moving), shortBool(state.player.mounted), shortBool(state.player.petExists), shortBool(state.player.petAlive), shortBool(state.modes.burst), shortBool(state.modes.conserve), shortBool(state.modes.hold), shortBool(state.modes.pause)),
        string.format("target ex=%s al=%s ho=%s rg=%s cast=%s int=%s hp=%s [%s]", shortBool(state.target.exists), shortBool(state.target.alive), shortBool(state.target.hostile), tostring(state.target.rangeBucket or "-"), shortBool(state.target.casting), shortBool(state.target.interruptible), formatPct(state.target.healthPct, state.target.healthKnown), statusTag(state.target.healthKnown)),
        string.format(
            "self hp=%s [%s] | %s | %s",
            formatPct(state.player.healthPct, state.player.healthKnown),
            statusTag(state.player.healthKnown),
            formatResourceLine(state.player.primaryResourceShortLabel or "pwr", state.player.primaryCurrent, state.player.primaryPct, state.player.primaryKnown, state.player.primaryPctKnown, state.player.primaryEstimated),
            formatResourceLine(state.player.secondaryResourceShortLabel or "sec", state.player.secondaryCurrent, state.player.secondaryPct, state.player.secondaryKnown, state.player.secondaryPctKnown)
        ),
        table.concat(slotLine, " | "),
        table.concat(groupedReasonLines[1] or {}, " | "),
        table.concat(groupedReasonLines[2] or {}, " | "),
        string.format("hud=%.2f ui=%.2f | %s | %s | %s", tonumber(addon.db.hud.scale) or 1, uiScale, compactCompatStatus, compactAdapterStatus, compactTaintStatus),
    }
end

function ExportHUD:ApplyActiveProfile()
    if not self.frame then
        return
    end

    local profile = addon:GetExportProfile() or addon.OutputProfiles:GetActive()
    local frameLayout = profile.frame or {}
    local iconLayout = profile.icons or {}
    local stateLayout = profile.stateCells or {}
    local barLayout = profile.bars or {}
    local signatureLayout = profile.signature or {}
    local heartbeatLayout = profile.heartbeat or {}
    local debugLayout = profile.debugPanel or {}

    self.activeProfile = profile
    self.frame:SetSize(frameLayout.width or 390, frameLayout.height or 132)
    self:ApplyPosition()
    self.frame:SetShown(addon.db.hud.visible ~= false)

    self.signatureA:SetSize(signatureLayout.size or 8, signatureLayout.size or 8)
    self.signatureA:ClearAllPoints()
    self.signatureA:SetPoint("TOPLEFT", signatureLayout.x or 4, signatureLayout.y or -4)
    self.signatureA:SetTexture("Interface/Buttons/WHITE8X8")
    self.signatureA:SetVertexColor(1, 0, 1, 1)

    self.signatureB:SetSize(signatureLayout.size or 8, signatureLayout.size or 8)
    self.signatureB:ClearAllPoints()
    self.signatureB:SetPoint("LEFT", self.signatureA, "RIGHT", signatureLayout.gap or 2, 0)
    self.signatureB:SetTexture("Interface/Buttons/WHITE8X8")
    self.signatureB:SetVertexColor(0, 1, 1, 1)

    self.heartbeat:SetSize(heartbeatLayout.size or 10, heartbeatLayout.size or 10)
    self.heartbeat:ClearAllPoints()
    self.heartbeat:SetPoint("TOPRIGHT", heartbeatLayout.x or -6, heartbeatLayout.y or -6)
    self.heartbeat:SetTexture("Interface/Buttons/WHITE8X8")

    self.dragHint:ClearAllPoints()
    self.dragHint:SetPoint("TOP", self.frame, "TOP", 0, -6)
    self.dragHint:SetText("drag /sm hud lock")

    for index, slot in ipairs(addon:GetSlotOrder()) do
        local iconFrame = self.iconFrames[slot]
        local size = iconLayout.size or 42
        iconFrame:SetSize(size, size)
        iconFrame:ClearAllPoints()
        iconFrame:SetPoint("TOPLEFT", self.frame, "TOPLEFT", (iconLayout.startX or 10) + ((index - 1) * (iconLayout.stepX or (size + 4))), -(iconLayout.startY or 20))
        iconFrame.checksum:SetSize(iconLayout.checksumSize or 8, iconLayout.checksumSize or 8)
        iconFrame.checksum:ClearAllPoints()
        iconFrame.checksum:SetPoint("BOTTOMRIGHT", iconLayout.checksumInsetX or -2, iconLayout.checksumInsetY or 2)

        iconFrame.label:ClearAllPoints()
        iconFrame.label:SetPoint("BOTTOM", iconFrame, "TOP", 0, 2)
        iconFrame.label:SetText(slot)
        iconFrame.label:SetShown(iconLayout.showLabels ~= false)
    end

    local visibleStateKeys = {}
    if stateLayout.visible then
        for index, key in ipairs(stateLayout.order or {}) do
            local cell = self.stateCells[key]
            if cell then
                visibleStateKeys[key] = true
                cell.texture:SetSize(stateLayout.size or 10, stateLayout.size or 10)
                cell.texture:ClearAllPoints()
                cell.texture:SetPoint("TOPLEFT", self.frame, "TOPLEFT", (stateLayout.startX or 268) + ((index - 1) * (stateLayout.stepX or 14)), -(stateLayout.startY or 28))
                cell.texture:Show()

                cell.label:ClearAllPoints()
                cell.label:SetPoint("TOP", cell.texture, "BOTTOM", 0, stateLayout.labelOffsetY or -2)
                cell.label:SetText(string.sub(key, 1, 1):upper())
                cell.label:Show()
            end
        end
    end

    for key, cell in pairs(self.stateCells) do
        if not visibleStateKeys[key] then
            cell.texture:Hide()
            cell.label:Hide()
        end
    end

    local barOrder = { "player", "target", "resource" }
    if barLayout.visible then
        for index, key in ipairs(barOrder) do
            local bar = self.bars[key]
            if bar then
                local y = (barLayout.topY or -78) + ((index - 1) * (barLayout.gapY or -18))
                bar.label:ClearAllPoints()
                bar.label:SetPoint("TOPLEFT", self.frame, "TOPLEFT", barLayout.labelX or 10, y)
                bar.label:SetShown(barLayout.showLabels ~= false)

                bar.holder:ClearAllPoints()
                bar.holder:SetPoint("TOPLEFT", self.frame, "TOPLEFT", barLayout.fillX or 70, y + 2)
                bar.holder:SetSize(barLayout.width or 180, barLayout.height or 12)
                bar.holder:Show()

                bar.fill:ClearAllPoints()
                bar.fill:SetPoint("LEFT", bar.holder, "LEFT", barLayout.fillInset or 2, 0)
                bar.fill:SetHeight(barLayout.fillHeight or 8)
                bar.fill.__maxWidth = math.max((barLayout.width or 180) - ((barLayout.fillInset or 2) * 2), 1)
            end
        end
    else
        for _, key in ipairs(barOrder) do
            local bar = self.bars[key]
            if bar then
                bar.label:Hide()
                bar.holder:Hide()
            end
        end
    end

    if barLayout.visible then
        self.bars.player.label:Show()
        self.bars.target.label:Show()
        self.bars.resource.label:Show()
    end

    self.debugPanel:ClearAllPoints()
    self.debugPanel:SetPoint("TOPLEFT", self.frame, "BOTTOMLEFT", 0, debugLayout.yOffset or -6)
    self.debugPanel:SetSize(debugLayout.width or math.max(frameLayout.width or 390, 472), debugLayout.height or 156)
    for index, line in ipairs(self.debugLines) do
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", self.debugPanel, "TOPLEFT", 12, -10 - ((index - 1) * 18))
        line:SetWidth((debugLayout.width or math.max(frameLayout.width or 390, 472)) - 24)
    end

    addon:NotifyCompatibilityChanged()
end

function ExportHUD:Initialize()
    if self.frame then
        return
    end

    self.frame = createBackdropFrame("SimplyMidnightExportFrame", UIParent)
    self.frame:SetClampedToScreen(true)
    self.frame:SetMovable(true)
    self.frame:RegisterForDrag("LeftButton")
    self.frame:SetScript("OnDragStart", function(frame)
        if addon.db.hud.locked then
            return
        end
        frame:StartMoving()
    end)
    self.frame:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        self:SavePosition()
    end)

    self.signatureA = self.frame:CreateTexture(nil, "OVERLAY")
    self.signatureB = self.frame:CreateTexture(nil, "OVERLAY")
    self.heartbeat = self.frame:CreateTexture(nil, "OVERLAY")

    self.dragHint = self.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")

    for _, slot in ipairs(addon:GetSlotOrder()) do
        self:CreateIcon(slot)
    end

    for _, key in ipairs({ "burst", "conserve", "hold", "pause", "target", "range", "cast", "overlay" }) do
        self:CreateStateCell(key)
    end

    self.bars.player = self:CreateBar("HP", { 0.15, 0.95, 0.25 })
    self.bars.target = self:CreateBar("TGT", { 0.95, 0.25, 0.25 })
    self.bars.resource = self:CreateBar("PWR", { 0.25, 0.65, 1.0 })

    self:CreateDebugPanel()

    self:SetLocked(addon.db.hud.locked)
    self:ApplyActiveProfile()
end

function ExportHUD:RenderStateCell(key, active, activeColor, inactiveColor)
    local cell = self.stateCells[key]
    if not cell then
        return
    end

    cell.texture:SetTexture("Interface/Buttons/WHITE8X8")
    if active then
        cell.texture:SetVertexColor(activeColor[1], activeColor[2], activeColor[3], 1)
    else
        cell.texture:SetVertexColor(inactiveColor[1], inactiveColor[2], inactiveColor[3], 0.35)
    end
end

function ExportHUD:RenderIcon(slot, entry)
    local iconFrame = self.iconFrames[slot]
    if not iconFrame then
        return
    end

    if entry and entry.spellID then
        local texture = addon:GetSpellTexture(entry.spellID) or addon.constants.questionMarkIcon
        iconFrame.texture:SetTexture(texture)
        iconFrame.texture:SetDesaturated(false)
        local red, green, blue = colorFromSpellID(entry.spellID)
        iconFrame.checksum:SetTexture("Interface/Buttons/WHITE8X8")
        iconFrame.checksum:SetVertexColor(red, green, blue, 1)
    else
        iconFrame.texture:SetTexture(addon.constants.questionMarkIcon)
        iconFrame.texture:SetDesaturated(true)
        iconFrame.checksum:SetTexture("Interface/Buttons/WHITE8X8")
        iconFrame.checksum:SetVertexColor(0.2, 0.2, 0.2, 0.85)
    end
end

function ExportHUD:Render(state, recommendations)
    local pulseOn = math.floor(GetTime() * 2) % 2 == 0
    self.heartbeat:SetVertexColor(pulseOn and 0 or 1, pulseOn and 1 or 0.2, 0.2, 1)

    for _, slot in ipairs(addon:GetSlotOrder()) do
        self:RenderIcon(slot, recommendations.slots[slot])
    end

    self:RenderStateCell("burst", state.modes.burst, { 0.95, 0.35, 0.2 }, { 0.3, 0.15, 0.1 })
    self:RenderStateCell("conserve", state.modes.conserve, { 1.0, 0.9, 0.2 }, { 0.2, 0.2, 0.1 })
    self:RenderStateCell("hold", state.modes.hold, { 1.0, 0.55, 0.15 }, { 0.2, 0.15, 0.1 })
    self:RenderStateCell("pause", state.modes.pause, { 1.0, 0.1, 0.1 }, { 0.25, 0.1, 0.1 })
    self:RenderStateCell("target", state.target.exists and state.target.hostile and state.target.alive, { 0.2, 0.85, 1.0 }, { 0.1, 0.2, 0.25 })
    self:RenderStateCell("range", state.target.inMelee or state.target.inShortRange, { 0.35, 0.95, 0.35 }, { 0.15, 0.2, 0.15 })
    self:RenderStateCell("cast", state.target.casting and state.target.interruptible, { 0.85, 0.2, 1.0 }, { 0.15, 0.1, 0.2 })
    self:RenderStateCell("overlay", state.modes.overlay, { 0.35, 1.0, 0.95 }, { 0.1, 0.2, 0.2 })

    if self.bars.player then
        setBar(self.bars.player.fill, state.player.healthKnown and state.player.healthPct or 0)
    end
    if self.bars.target then
        setBar(self.bars.target.fill, state.target.healthKnown and state.target.healthPct or 0)
    end
    if self.bars.resource then
        self.bars.resource.label:SetText(string.upper(state.player.primaryResourceShortLabel or self.bars.resource.defaultLabel or "PWR"))
        setBar(self.bars.resource.fill, state.player.primaryPctKnown and state.player.primaryPct or 0)
    end

    if addon.session.debug then
        local lines = self:GetDiagnosticLines(state, recommendations)
        for index = 1, #self.debugLines do
            self.debugLines[index]:SetText(lines[index] or "")
        end
        self.debugPanel:Show()
    else
        self.debugPanel:Hide()
    end
end

function ExportHUD:Tick()
    addon:SafeCall("ExportHUD.Tick", function()
        local state = addon.State:Refresh()
        local recommendations = addon.Recommendations:Refresh(state)
        self:Render(state, recommendations)
    end)
end

function ExportHUD:Start()
    if self.ticker then
        return
    end

    self.ticker = C_Timer.NewTicker(0.05, function()
        self:Tick()
    end)
end

addon.ExportHUD = ExportHUD
