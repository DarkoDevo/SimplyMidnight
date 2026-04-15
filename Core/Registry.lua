local _, addon = ...

local Registry = {}

local slotCycle = {
    primary = "secondary",
    secondary = "defensive",
    defensive = "interrupt",
    interrupt = "utility",
    utility = "primary",
}
local contentScopeCycle = {
    all = "pve",
    pve = "pvp",
    pvp = "all",
}

local function cloneTable(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for key, nested in pairs(value) do
        copy[key] = cloneTable(nested)
    end
    return copy
end

local function normalizeSlot(slot)
    slot = tostring(slot or ""):lower()
    for _, knownSlot in ipairs(addon:GetSlotOrder()) do
        if slot == knownSlot then
            return knownSlot
        end
    end
    return "primary"
end

local function getCurrentSpecID()
    local specIndex = GetSpecialization and GetSpecialization() or nil
    if not specIndex or not GetSpecializationInfo then
        return nil
    end
    return GetSpecializationInfo(specIndex)
end

local function isEmptyTable(value)
    if type(value) ~= "table" then
        return true
    end

    return next(value) == nil
end

local function buildDefaultManualConditions(slot)
    slot = normalizeSlot(slot)
    if slot == "utility" then
        return {}
    end

    local conditions = {
        inCombat = true,
    }

    if slot == "primary" or slot == "secondary" or slot == "interrupt" then
        conditions.requireTarget = true
        conditions.targetHostile = true
        conditions.targetAlive = true
    end

    if slot == "interrupt" then
        conditions.targetCasting = true
        conditions.targetInterruptible = true
    end

    return conditions
end

local function conditionsMatchDefault(entry)
    if type(entry) ~= "table" then
        return false
    end

    local expected = buildDefaultManualConditions(entry.slot)
    local actual = type(entry.conditions) == "table" and entry.conditions or {}

    for key, value in pairs(expected) do
        if actual[key] ~= value then
            return false
        end
    end

    for key in pairs(actual) do
        if expected[key] == nil then
            return false
        end
    end

    return true
end

local function isTemporaryManualPrimary(entry)
    local spellID = tonumber(entry and entry.spellID)
    if type(entry) ~= "table" or entry.source ~= "manual" or entry.slot ~= "primary" then
        return false
    end

    if spellID ~= 1247378 and spellID ~= 444347 then
        return false
    end

    return conditionsMatchDefault(entry)
end

function Registry:NormalizeEntry(entry)
    return {
        spellID = tonumber(entry.spellID),
        slot = normalizeSlot(entry.slot),
        priority = tonumber(entry.priority) or 50,
        enabled = entry.enabled ~= false,
        contentScope = entry.contentScope or "all",
        conditions = cloneTable(entry.conditions or {}),
        advancedRule = entry.advancedRule,
        specID = tonumber(entry.specID),
        packKey = entry.packKey,
        packVersion = tonumber(entry.packVersion),
        source = entry.source,
        note = entry.note,
        decisionGroup = entry.decisionGroup,
        overridePrimary = entry.overridePrimary == true,
        commitMargin = tonumber(entry.commitMargin),
    }
end

function Registry:Initialize()
    local currentSpecID = getCurrentSpecID()
    local previousVersion = tonumber(addon.db.registry.version) or 0

    if type(addon.db.registry.spells) ~= "table" then
        addon.db.registry.spells = {}
    end
    if type(addon.db.registry.installedPacks) ~= "table" then
        addon.db.registry.installedPacks = {}
    end

    if previousVersion < 2 then
        local looksLikeLegacyStarter = #addon.db.registry.spells > 0 and #addon.db.registry.spells <= 5
        for _, entry in ipairs(addon.db.registry.spells) do
            if entry.source or entry.packKey or entry.specID then
                looksLikeLegacyStarter = false
                break
            end
        end
        if looksLikeLegacyStarter then
            addon.db.registry.spells = {}
        end
    end

    for index, entry in ipairs(addon.db.registry.spells) do
        addon.db.registry.spells[index] = self:NormalizeEntry(entry)
        if addon.db.registry.spells[index].specID == nil then
            addon.db.registry.spells[index].specID = currentSpecID
        end
        if addon.db.registry.spells[index].source == nil then
            addon.db.registry.spells[index].source = "legacy"
        end
        if previousVersion < 3 and addon.db.registry.spells[index].source == "manual" and isEmptyTable(addon.db.registry.spells[index].conditions) then
            addon.db.registry.spells[index].conditions = buildDefaultManualConditions(addon.db.registry.spells[index].slot)
        end
        if previousVersion < 4 and isTemporaryManualPrimary(addon.db.registry.spells[index]) then
            addon.db.registry.spells[index].enabled = false
        end
    end

    addon.db.registry.version = addon.defaults.registry.version

    self:EnsureCurrentPack(false)

    if not self.initialized then
        self.initialized = true
        addon:RegisterRuntimeEvent("PLAYER_SPECIALIZATION_CHANGED", self, "OnRuntimeEvent")
    end
end

function Registry:OnRuntimeEvent(_, unitID)
    if unitID ~= "player" then
        return
    end

    self:EnsureCurrentPack(false)
    if addon.ConfigUI and addon.ConfigUI.frame and addon.ConfigUI.frame:IsShown() then
        addon.ConfigUI:Refresh()
    end
end

function Registry:GetAll()
    return addon.db.registry.spells
end

function Registry:Get(index)
    index = tonumber(index)
    if not index then
        return nil
    end
    return addon.db.registry.spells[index]
end

function Registry:GetCurrentPack()
    return addon.Packs and addon.Packs:GetCurrent() or nil
end

function Registry:GetCurrentPackLabel()
    local pack = self:GetCurrentPack()
    if pack then
        return pack.name
    end
    return "Custom / Unsupported Spec"
end

function Registry:CountEntriesForSpec(specID)
    local count = 0
    specID = tonumber(specID)

    for _, entry in ipairs(addon.db.registry.spells) do
        if tonumber(entry.specID) == specID then
            count = count + 1
        end
    end

    return count
end

function Registry:CountBuiltinEntriesForPack(packKey)
    local count = 0

    for _, entry in ipairs(addon.db.registry.spells) do
        if entry.source == "builtin" and entry.packKey == packKey then
            count = count + 1
        end
    end

    return count
end

function Registry:RemoveBuiltinEntriesForPack(packKey)
    local removed = 0

    for index = #addon.db.registry.spells, 1, -1 do
        local entry = addon.db.registry.spells[index]
        if entry.source == "builtin" and entry.packKey == packKey then
            table.remove(addon.db.registry.spells, index)
            removed = removed + 1
        end
    end

    return removed
end

function Registry:InstallPack(pack, options)
    options = options or {}
    if type(pack) == "string" then
        pack = addon.Packs and addon.Packs:GetByKey(pack) or nil
    end

    if not pack then
        return false, "no built-in pack for this spec"
    end

    if not options.force and addon.db.registry.installedPacks[pack.key] then
        return false, pack.name .. " is already installed"
    end

    local added = 0
    for _, entry in ipairs(pack.entries or {}) do
        local normalized = self:NormalizeEntry(entry)
        normalized.specID = pack.specID
        normalized.packKey = pack.key
        normalized.packVersion = tonumber(pack.version) or 1
        normalized.source = "builtin"
        table.insert(addon.db.registry.spells, normalized)
        added = added + 1
    end

    addon.db.registry.installedPacks[pack.key] = tonumber(pack.version) or 1
    return true, string.format("Installed %s (%d entries)", pack.name, added)
end

function Registry:EnsureCurrentPack(force)
    local pack = self:GetCurrentPack()
    if not pack then
        return false, "no built-in pack for this spec"
    end

    local packVersion = tonumber(pack.version) or 1
    local installedVersion = tonumber(addon.db.registry.installedPacks[pack.key]) or 0
    local builtinCount = self:CountBuiltinEntriesForPack(pack.key)

    if force or (installedVersion > 0 and (installedVersion < packVersion or builtinCount == 0)) then
        self:RemoveBuiltinEntriesForPack(pack.key)
        addon.db.registry.installedPacks[pack.key] = nil
        return self:InstallPack(pack, { force = true })
    end

    if not force then
        if installedVersion > 0 then
            return false, pack.name .. " is already installed"
        end
        if self:CountEntriesForSpec(pack.specID) > 0 then
            return false, pack.name .. " already has entries"
        end
    end

    return self:InstallPack(pack, { force = force })
end

function Registry:ResetCurrentPack()
    local pack = self:GetCurrentPack()
    if not pack then
        return false, "no built-in pack for this spec"
    end

    for index = #addon.db.registry.spells, 1, -1 do
        local entry = addon.db.registry.spells[index]
        if tonumber(entry.specID) == pack.specID then
            table.remove(addon.db.registry.spells, index)
        end
    end

    addon.db.registry.installedPacks[pack.key] = nil
    return self:InstallPack(pack, { force = true })
end

function Registry:AddSpell(spellID, slot, priority)
    spellID = tonumber(spellID)
    if not spellID then
        return false, "spell id must be a number"
    end

    local spellName = addon:GetSpellName(spellID)
    if not spellName then
        return false, "unknown spell id"
    end

    table.insert(addon.db.registry.spells, self:NormalizeEntry({
        spellID = spellID,
        slot = slot,
        priority = priority,
        enabled = true,
        contentScope = "all",
        conditions = buildDefaultManualConditions(slot),
        specID = getCurrentSpecID(),
        source = "manual",
    }))

    return true, spellName
end

function Registry:SetContentScope(index, contentScope)
    local entry = self:Get(index)
    if not entry then
        return false
    end

    contentScope = tostring(contentScope or "all"):lower()
    if contentScope ~= "all" and contentScope ~= "pve" and contentScope ~= "pvp" then
        contentScope = "all"
    end

    entry.contentScope = contentScope
    return true
end

function Registry:CycleContentScope(index)
    local entry = self:Get(index)
    if not entry then
        return false
    end

    entry.contentScope = contentScopeCycle[entry.contentScope] or "all"
    return true
end

function Registry:SetNote(index, note)
    local entry = self:Get(index)
    if not entry then
        return false
    end

    note = tostring(note or ""):gsub("^%s+", ""):gsub("%s+$", "")
    entry.note = note ~= "" and note or nil
    return true
end

function Registry:SetCondition(index, key, value)
    local entry = self:Get(index)
    if not entry or type(key) ~= "string" or key == "" then
        return false
    end

    entry.conditions = type(entry.conditions) == "table" and entry.conditions or {}
    local normalized = addon.ConditionSchema and addon.ConditionSchema:NormalizeConditionValue(key, value) or value
    if normalized == nil then
        entry.conditions[key] = nil
    else
        entry.conditions[key] = normalized
    end
    return true
end

function Registry:GetCondition(index, key)
    local entry = self:Get(index)
    if not entry or type(entry.conditions) ~= "table" then
        return nil
    end
    return entry.conditions[key]
end

function Registry:ClearConditions(index)
    local entry = self:Get(index)
    if not entry then
        return false
    end

    entry.conditions = {}
    return true
end

function Registry:ClearEditableConditions(index)
    local entry = self:Get(index)
    if not entry then
        return false
    end

    entry.conditions = type(entry.conditions) == "table" and entry.conditions or {}

    for _, key in ipairs(addon.ConditionSchema:GetBoolOrder() or {}) do
        entry.conditions[key] = nil
    end
    for _, key in ipairs(addon.ConditionSchema:GetNumberOrder() or {}) do
        entry.conditions[key] = nil
    end
    entry.conditions.rangeBucket = nil
    return true
end

function Registry:RemoveSpell(index)
    index = tonumber(index)
    if not index or not addon.db.registry.spells[index] then
        return false
    end

    table.remove(addon.db.registry.spells, index)
    return true
end

function Registry:ToggleEnabled(index)
    local entry = addon.db.registry.spells[index]
    if not entry then
        return false
    end

    entry.enabled = not entry.enabled
    return true
end

function Registry:CycleSlot(index)
    local entry = addon.db.registry.spells[index]
    if not entry then
        return false
    end

    entry.slot = slotCycle[entry.slot] or "primary"
    return true
end

function Registry:AdjustPriority(index, delta)
    local entry = addon.db.registry.spells[index]
    if not entry then
        return false
    end

    entry.priority = math.max(0, (tonumber(entry.priority) or 0) + (tonumber(delta) or 0))
    return true
end

function Registry:GetEntriesForSlot(slot)
    local matches = {}
    slot = normalizeSlot(slot)

    for index, entry in ipairs(addon.db.registry.spells) do
        if entry.slot == slot then
            matches[#matches + 1] = {
                index = index,
                entry = entry,
            }
        end
    end

    table.sort(matches, function(a, b)
        if a.entry.priority == b.entry.priority then
            return a.index < b.index
        end
        return a.entry.priority > b.entry.priority
    end)

    return matches
end

addon.Registry = Registry
