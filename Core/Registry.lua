local _, addon = ...

local Registry = {}

local slotCycle = {
    primary = "secondary",
    secondary = "defensive",
    defensive = "interrupt",
    interrupt = "utility",
    utility = "primary",
}

local starterSpellsByClass = {
    DEATHKNIGHT = {
        {
            spellID = 47541,
            slot = "primary",
            priority = 100,
            enabled = true,
            contentScope = "all",
            conditions = { inCombat = true, requireTarget = true, targetHostile = true },
        },
        {
            spellID = 49998,
            slot = "secondary",
            priority = 90,
            enabled = true,
            contentScope = "all",
            conditions = { inCombat = true, playerHpBelow = 85 },
        },
        {
            spellID = 48707,
            slot = "defensive",
            priority = 95,
            enabled = true,
            contentScope = "all",
            conditions = { inCombat = true, playerHpBelow = 70 },
        },
        {
            spellID = 47528,
            slot = "interrupt",
            priority = 110,
            enabled = true,
            contentScope = "all",
            conditions = { inCombat = true, requireTarget = true, targetHostile = true, targetCasting = true },
        },
        {
            spellID = 212552,
            slot = "utility",
            priority = 60,
            enabled = true,
            contentScope = "all",
            conditions = { inCombat = true },
        },
    },
    HUNTER = {
        {
            spellID = 34026,
            slot = "primary",
            priority = 100,
            enabled = true,
            contentScope = "all",
            conditions = { inCombat = true, requireTarget = true, targetHostile = true },
        },
        {
            spellID = 193455,
            slot = "secondary",
            priority = 90,
            enabled = true,
            contentScope = "all",
            conditions = { inCombat = true, requireTarget = true, targetHostile = true },
        },
        {
            spellID = 109304,
            slot = "defensive",
            priority = 95,
            enabled = true,
            contentScope = "all",
            conditions = { inCombat = true, playerHpBelow = 70 },
        },
        {
            spellID = 147362,
            slot = "interrupt",
            priority = 110,
            enabled = true,
            contentScope = "all",
            conditions = { inCombat = true, requireTarget = true, targetHostile = true, targetCasting = true },
        },
        {
            spellID = 781,
            slot = "utility",
            priority = 60,
            enabled = true,
            contentScope = "all",
            conditions = { inCombat = true },
        },
    },
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

function Registry:NormalizeEntry(entry)
    return {
        spellID = tonumber(entry.spellID),
        slot = normalizeSlot(entry.slot),
        priority = tonumber(entry.priority) or 50,
        enabled = entry.enabled ~= false,
        contentScope = entry.contentScope or "all",
        conditions = cloneTable(entry.conditions or {}),
        advancedRule = entry.advancedRule,
    }
end

function Registry:Initialize()
    if type(addon.db.registry.spells) ~= "table" then
        addon.db.registry.spells = {}
    end

    if #addon.db.registry.spells == 0 then
        local _, classTag = UnitClass("player")
        local starterSpells = starterSpellsByClass[classTag] or {}
        for _, entry in ipairs(starterSpells) do
            table.insert(addon.db.registry.spells, self:NormalizeEntry(entry))
        end
    else
        for index, entry in ipairs(addon.db.registry.spells) do
            addon.db.registry.spells[index] = self:NormalizeEntry(entry)
        end
    end
end

function Registry:GetAll()
    return addon.db.registry.spells
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

