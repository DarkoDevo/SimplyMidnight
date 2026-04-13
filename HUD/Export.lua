local _, addon = ...

local ExportHUD = {
    iconFrames = {},
    stateCells = {},
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
    valuePct = math.max(0, math.min(valuePct or 0, 100))
    texture:SetWidth((texture.__maxWidth or 1) * (valuePct / 100))
end

function ExportHUD:SavePosition()
    local point, _, relativePoint, xOfs, yOfs = self.frame:GetPoint(1)
    addon.db.hud.point = point
    addon.db.hud.relativePoint = relativePoint
    addon.db.hud.x = math.floor(xOfs)
    addon.db.hud.y = math.floor(yOfs)
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
end

function ExportHUD:ToggleLocked()
    self:SetLocked(not addon.db.hud.locked)
end

function ExportHUD:CreateIcon(slot, index)
    local iconFrame = createBackdropFrame(nil, self.frame)
    iconFrame:SetSize(42, 42)
    iconFrame:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 10 + ((index - 1) * 48), -20)

    iconFrame.texture = iconFrame:CreateTexture(nil, "ARTWORK")
    iconFrame.texture:SetAllPoints()
    iconFrame.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    iconFrame.checksum = iconFrame:CreateTexture(nil, "OVERLAY")
    iconFrame.checksum:SetSize(8, 8)
    iconFrame.checksum:SetPoint("BOTTOMRIGHT", -2, 2)

    iconFrame.label = iconFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    iconFrame.label:SetPoint("BOTTOM", iconFrame, "TOP", 0, 2)
    iconFrame.label:SetText(slot)

    self.iconFrames[slot] = iconFrame
end

function ExportHUD:CreateStateCell(key, index)
    local cell = self.frame:CreateTexture(nil, "OVERLAY")
    cell:SetSize(10, 10)
    cell:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 268 + ((index - 1) * 14), -28)
    self.stateCells[key] = cell

    local label = self.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOP", cell, "BOTTOM", 0, -2)
    label:SetText(string.sub(key, 1, 1):upper())
end

function ExportHUD:CreateBar(labelText, yOffset, color)
    local label = self.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 10, yOffset)
    label:SetText(labelText)

    local holder = createBackdropFrame(nil, self.frame)
    holder:SetSize(180, 12)
    holder:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 70, yOffset + 2)

    local fill = holder:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("LEFT", holder, "LEFT", 2, 0)
    fill:SetHeight(8)
    fill.__maxWidth = 176
    fill:SetTexture("Interface/Buttons/WHITE8X8")
    fill:SetVertexColor(color[1], color[2], color[3], 0.95)

    return fill
end

function ExportHUD:Initialize()
    if self.frame then
        return
    end

    self.frame = createBackdropFrame("SimplyMidnightExportFrame", UIParent)
    self.frame:SetSize(390, 132)
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
    self.signatureA:SetSize(8, 8)
    self.signatureA:SetPoint("TOPLEFT", 4, -4)
    self.signatureA:SetTexture("Interface/Buttons/WHITE8X8")
    self.signatureA:SetVertexColor(1, 0, 1, 1)

    self.signatureB = self.frame:CreateTexture(nil, "OVERLAY")
    self.signatureB:SetSize(8, 8)
    self.signatureB:SetPoint("LEFT", self.signatureA, "RIGHT", 2, 0)
    self.signatureB:SetTexture("Interface/Buttons/WHITE8X8")
    self.signatureB:SetVertexColor(0, 1, 1, 1)

    self.heartbeat = self.frame:CreateTexture(nil, "OVERLAY")
    self.heartbeat:SetSize(10, 10)
    self.heartbeat:SetPoint("TOPRIGHT", -6, -6)
    self.heartbeat:SetTexture("Interface/Buttons/WHITE8X8")

    self.dragHint = self.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.dragHint:SetPoint("TOP", self.frame, "TOP", 0, -6)
    self.dragHint:SetText("drag /sm hud lock")

    for index, slot in ipairs(addon:GetSlotOrder()) do
        self:CreateIcon(slot, index)
    end

    local stateOrder = { "burst", "conserve", "hold", "pause", "target", "range", "cast", "overlay" }
    for index, key in ipairs(stateOrder) do
        self:CreateStateCell(key, index)
    end

    self.playerBar = self:CreateBar("HP", -78, { 0.15, 0.95, 0.25 })
    self.targetBar = self:CreateBar("TGT", -96, { 0.95, 0.25, 0.25 })
    self.resourceBar = self:CreateBar("PWR", -114, { 0.25, 0.65, 1.0 })

    self.debugText = self.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.debugText:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", 10, 8)
    self.debugText:SetJustifyH("LEFT")
    self.debugText:SetWidth(360)

    self:ApplyPosition()
    self:SetLocked(addon.db.hud.locked)
    self.frame:SetShown(addon.db.hud.visible ~= false)
end

function ExportHUD:RenderStateCell(key, active, activeColor, inactiveColor)
    local cell = self.stateCells[key]
    if not cell then
        return
    end

    cell:SetTexture("Interface/Buttons/WHITE8X8")
    if active then
        cell:SetVertexColor(activeColor[1], activeColor[2], activeColor[3], 1)
    else
        cell:SetVertexColor(inactiveColor[1], inactiveColor[2], inactiveColor[3], 0.35)
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

    setBar(self.playerBar, state.player.healthPct)
    setBar(self.targetBar, state.target.healthPct)
    setBar(self.resourceBar, state.player.primaryPct)

    if addon.session.debug then
        local adapterStatus = addon.SimplyGladAdapter and addon.SimplyGladAdapter:GetStatusLine() or "adapter: unavailable"
        local taintStatus = addon.TaintGuard and addon.TaintGuard:GetStatusLine() or "taint: unavailable"
        self.debugText:SetText(adapterStatus .. " | " .. taintStatus)
        self.debugText:Show()
    else
        self.debugText:Hide()
    end
end

function ExportHUD:Tick()
    local state = addon.State:Refresh()
    local recommendations = addon.Recommendations:Refresh(state)
    self:Render(state, recommendations)
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
