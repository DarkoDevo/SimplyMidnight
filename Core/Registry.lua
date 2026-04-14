local _, addon = ...

local Registry = {}

local slotCycle = {
    primary = "secondary",
    secondary = "defensive",
    defensive = "interrupt",
    interrupt = "utility",
    utility = "primary",
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
        conditions = {},
        specID = getCurrentSpecID(),
        source = "manual",
    }))

    return true, spellName
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
