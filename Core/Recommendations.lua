local _, addon = ...

local Recommendations = {
    latest = {
        slots = {},
    },
}

local function getCooldownRemaining(spellID)
    if type(C_Spell) == "table" and type(C_Spell.GetSpellCooldown) == "function" then
        local ok, info = pcall(C_Spell.GetSpellCooldown, spellID)
        if ok and type(info) == "table" then
            local startTime = info.startTime or 0
            local duration = info.duration or 0
            if duration <= 0 then
                return 0
            end
            return math.max((startTime + duration) - GetTime(), 0)
        end
    end

    if type(GetSpellCooldown) == "function" then
        local startTime, duration = GetSpellCooldown(spellID)
        if duration and duration > 0 then
            return math.max((startTime + duration) - GetTime(), 0)
        end
    end

    return 0
end

local function getChargeCount(spellID)
    if type(C_Spell) == "table" and type(C_Spell.GetSpellCharges) == "function" then
        local ok, info = pcall(C_Spell.GetSpellCharges, spellID)
        if ok and type(info) == "table" then
            return info.currentCharges or 0
        end
    elseif type(GetSpellCharges) == "function" then
        local charges = GetSpellCharges(spellID)
        return charges or 0
    end
    return 0
end

local function isSpellUsable(spellID)
    if type(IsUsableSpell) == "function" then
        local usable = IsUsableSpell(spellID)
        return usable and true or false
    end
    return true
end

local function matchesScope(entry, state)
    if entry.contentScope == "all" or entry.contentScope == nil then
        return true
    end
    return entry.contentScope == state.mode
end

local function matchesConditions(entry, state)
    local conditions = entry.conditions or {}

    if conditions.inCombat ~= nil and conditions.inCombat ~= state.player.inCombat then
        return false
    end
    if conditions.requireTarget and not state.target.exists then
        return false
    end
    if conditions.targetHostile and not state.target.hostile then
        return false
    end
    if conditions.playerHpBelow and state.player.healthPct > conditions.playerHpBelow then
        return false
    end
    if conditions.targetHpBelow and state.target.healthPct > conditions.targetHpBelow then
        return false
    end
    if conditions.resourceAtLeast and state.player.primaryCurrent < conditions.resourceAtLeast then
        return false
    end
    if conditions.resourceAtMost and state.player.primaryCurrent > conditions.resourceAtMost then
        return false
    end
    if conditions.secondaryAtLeast and state.player.secondaryCurrent < conditions.secondaryAtLeast then
        return false
    end
    if conditions.secondaryAtMost and state.player.secondaryCurrent > conditions.secondaryAtMost then
        return false
    end
    if conditions.targetCasting and not state.target.casting then
        return false
    end
    if conditions.rangeBucket and conditions.rangeBucket ~= state.target.rangeBucket then
        return false
    end
    if conditions.modeBurst and not state.modes.burst then
        return false
    end
    if conditions.modeConserve and not state.modes.conserve then
        return false
    end
    if conditions.modeHold and not state.modes.hold then
        return false
    end
    if conditions.modePause and not state.modes.pause then
        return false
    end
    if conditions.cooldownReady and getCooldownRemaining(entry.spellID) > 0 then
        return false
    end
    if conditions.chargesAtLeast and getChargeCount(entry.spellID) < conditions.chargesAtLeast then
        return false
    end

    if getCooldownRemaining(entry.spellID) > 0 then
        return false
    end

    return isSpellUsable(entry.spellID)
end

function Recommendations:Initialize()
    self.latest = {
        updatedAt = 0,
        slots = {},
    }
end

function Recommendations:Refresh(state)
    state = state or addon.State:Refresh()

    local result = {
        updatedAt = GetTime(),
        slots = {},
    }

    if state.modes.pause then
        self.latest = result
        return result
    end

    for _, slot in ipairs(addon:GetSlotOrder()) do
        local selected = nil
        for _, record in ipairs(addon.Registry:GetEntriesForSlot(slot)) do
            local entry = record.entry
            if entry.enabled and matchesScope(entry, state) and matchesConditions(entry, state) then
                selected = entry
                break
            end
        end
        result.slots[slot] = selected
    end

    self.latest = result
    return result
end

addon.Recommendations = Recommendations
