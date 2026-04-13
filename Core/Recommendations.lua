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

local function isSpellKnown(spellID)
    if type(IsSpellKnownOrOverridesKnown) == "function" then
        return IsSpellKnownOrOverridesKnown(spellID)
    end
    if type(IsPlayerSpell) == "function" and IsPlayerSpell(spellID) then
        return true
    end
    if type(IsSpellKnown) == "function" then
        return IsSpellKnown(spellID)
    end
    return addon:GetSpellName(spellID) ~= nil
end

local function isSpellUsable(spellID)
    if type(IsUsableSpell) == "function" then
        local usable = IsUsableSpell(spellID)
        return usable and true or false
    end
    return true
end

local function isSpellInRange(spellID, unitID)
    if type(IsSpellInRange) ~= "function" or not unitID or not UnitExists(unitID) then
        return true
    end

    local ok, result = pcall(IsSpellInRange, spellID, unitID)
    if not ok or result == nil then
        return true
    end

    if result == 0 or result == false then
        return false
    end

    return true
end

local function asConditionList(value)
    if type(value) ~= "table" then
        return nil
    end
    if value.spellID then
        return { value }
    end
    return value
end

local function readAura(unitID, spellID, filter, sourceUnit)
    if not unitID or not spellID or not UnitExists(unitID) or type(UnitAura) ~= "function" then
        return nil
    end

    for index = 1, 40 do
        local name, _, count, _, duration, expirationTime, source, _, _, auraSpellID = UnitAura(unitID, index, filter)
        if not name then
            break
        end

        if auraSpellID == spellID then
            if sourceUnit and (type(source) ~= "string" or not UnitExists(sourceUnit) or not UnitIsUnit(source, sourceUnit)) then
                -- Keep scanning until we find the aura from the requested source.
            else
                local remaining = 0
                if expirationTime and expirationTime > 0 then
                    remaining = math.max(expirationTime - GetTime(), 0)
                end

                return {
                    count = count or 0,
                    duration = duration or 0,
                    expirationTime = expirationTime or 0,
                    remaining = remaining,
                    source = source,
                }
            end
        end
    end

    return nil
end

local function matchesAuraList(conditionList, predicate)
    conditionList = asConditionList(conditionList)
    if not conditionList then
        return true
    end

    for _, auraCondition in ipairs(conditionList) do
        if not predicate(auraCondition) then
            return false
        end
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

    if entry.specID and state.player.specID ~= entry.specID then
        return false
    end
    if not isSpellKnown(entry.spellID) then
        return false
    end

    if conditions.inCombat ~= nil and conditions.inCombat ~= state.player.inCombat then
        return false
    end
    if conditions.moving ~= nil and conditions.moving ~= state.player.moving then
        return false
    end
    if conditions.mounted ~= nil and conditions.mounted ~= state.player.mounted then
        return false
    end
    if conditions.petAlive ~= nil and conditions.petAlive ~= state.player.petAlive then
        return false
    end
    if conditions.requireTarget and not state.target.exists then
        return false
    end
    if conditions.targetAlive ~= nil and conditions.targetAlive ~= state.target.alive then
        return false
    end
    if conditions.targetHostile and not state.target.hostile then
        return false
    end
    if conditions.playerHpBelow and state.player.healthPct > conditions.playerHpBelow then
        return false
    end
    if conditions.playerHpAbove and state.player.healthPct < conditions.playerHpAbove then
        return false
    end
    if conditions.targetHpBelow and state.target.healthPct > conditions.targetHpBelow then
        return false
    end
    if conditions.targetHpAbove and state.target.healthPct < conditions.targetHpAbove then
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
    if conditions.resourcePctAtLeast and state.player.primaryPct < conditions.resourcePctAtLeast then
        return false
    end
    if conditions.resourcePctAtMost and state.player.primaryPct > conditions.resourcePctAtMost then
        return false
    end
    if conditions.secondaryPctAtLeast and state.player.secondaryPct < conditions.secondaryPctAtLeast then
        return false
    end
    if conditions.secondaryPctAtMost and state.player.secondaryPct > conditions.secondaryPctAtMost then
        return false
    end
    if conditions.enemyCountAtLeast and (state.environment.enemyCount or 0) < conditions.enemyCountAtLeast then
        return false
    end
    if conditions.enemyCountAtMost and (state.environment.enemyCount or 0) > conditions.enemyCountAtMost then
        return false
    end
    if conditions.targetCasting ~= nil and conditions.targetCasting ~= state.target.casting then
        return false
    end
    if conditions.targetInterruptible ~= nil and conditions.targetInterruptible ~= state.target.interruptible then
        return false
    end
    if conditions.rangeBucket and conditions.rangeBucket ~= state.target.rangeBucket then
        return false
    end
    if conditions.modeBurst ~= nil and conditions.modeBurst ~= state.modes.burst then
        return false
    end
    if conditions.modeConserve ~= nil and conditions.modeConserve ~= state.modes.conserve then
        return false
    end
    if conditions.modeHold ~= nil and conditions.modeHold ~= state.modes.hold then
        return false
    end
    if conditions.modePause ~= nil and conditions.modePause ~= state.modes.pause then
        return false
    end

    local chargeCount = getChargeCount(entry.spellID)
    local cooldownRemaining = getCooldownRemaining(entry.spellID)
    local hasAvailableCharge = chargeCount > 0
    local cooldownReady = cooldownRemaining <= 0 or hasAvailableCharge
    if conditions.cooldownReady ~= nil and cooldownReady ~= conditions.cooldownReady then
        return false
    end
    if cooldownRemaining > 0 and not hasAvailableCharge then
        return false
    end

    if conditions.chargesAtLeast and chargeCount < conditions.chargesAtLeast then
        return false
    end
    if conditions.chargesAtMost and chargeCount > conditions.chargesAtMost then
        return false
    end

    if not matchesAuraList(conditions.auraPresent, function(auraCondition)
        return readAura(auraCondition.unit, auraCondition.spellID, auraCondition.filter, auraCondition.sourceUnit) ~= nil
    end) then
        return false
    end
    if not matchesAuraList(conditions.auraMissing, function(auraCondition)
        return readAura(auraCondition.unit, auraCondition.spellID, auraCondition.filter, auraCondition.sourceUnit) == nil
    end) then
        return false
    end
    if not matchesAuraList(conditions.auraRemainingBelow, function(auraCondition)
        local aura = readAura(auraCondition.unit, auraCondition.spellID, auraCondition.filter, auraCondition.sourceUnit)
        return aura ~= nil and aura.remaining <= (auraCondition.seconds or 0)
    end) then
        return false
    end
    if not matchesAuraList(conditions.auraRemainingAbove, function(auraCondition)
        local aura = readAura(auraCondition.unit, auraCondition.spellID, auraCondition.filter, auraCondition.sourceUnit)
        return aura ~= nil and aura.remaining >= (auraCondition.seconds or 0)
    end) then
        return false
    end
    if not matchesAuraList(conditions.auraStacksAtLeast, function(auraCondition)
        local aura = readAura(auraCondition.unit, auraCondition.spellID, auraCondition.filter, auraCondition.sourceUnit)
        return aura ~= nil and (aura.count or 0) >= (auraCondition.stacks or 0)
    end) then
        return false
    end
    if not matchesAuraList(conditions.auraStacksAtMost, function(auraCondition)
        local aura = readAura(auraCondition.unit, auraCondition.spellID, auraCondition.filter, auraCondition.sourceUnit)
        return aura ~= nil and (aura.count or 0) <= (auraCondition.stacks or 0)
    end) then
        return false
    end

    if conditions.requireTarget and not isSpellInRange(entry.spellID, "target") then
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

    local selectedSpellIDs = {}

    for _, slot in ipairs(addon:GetSlotOrder()) do
        local selected = nil
        for _, record in ipairs(addon.Registry:GetEntriesForSlot(slot)) do
            local entry = record.entry
            if entry.enabled and not selectedSpellIDs[entry.spellID] and matchesScope(entry, state) and matchesConditions(entry, state) then
                selected = entry
                selectedSpellIDs[entry.spellID] = true
                break
            end
        end
        result.slots[slot] = selected
    end

    self.latest = result
    return result
end

addon.Recommendations = Recommendations
