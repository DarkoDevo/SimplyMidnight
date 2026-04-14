local _, addon = ...

local Recommendations = {
    latest = {
        slots = {},
    },
}

local function protectedCall(callback, ...)
    if type(callback) ~= "function" then
        return nil
    end

    local ok, resultA, resultB, resultC, resultD, resultE, resultF, resultG, resultH = pcall(callback, ...)
    if not ok then
        return nil
    end

    return resultA, resultB, resultC, resultD, resultE, resultF, resultG, resultH
end

local function unitExists(unitID)
    return addon:NormalizeBoolean(protectedCall(UnitExists, unitID), false)
end

local function unitIsUnit(leftUnitID, rightUnitID)
    return addon:NormalizeBoolean(protectedCall(UnitIsUnit, leftUnitID, rightUnitID), false)
end

local function getCooldownRemaining(spellID)
    if type(C_Spell) == "table" and type(C_Spell.GetSpellCooldown) == "function" then
        local info = protectedCall(C_Spell.GetSpellCooldown, spellID)
        if type(info) == "table" then
            local startTime = addon:UntaintNumber(info.startTime, 0)
            local duration = addon:UntaintNumber(info.duration, 0)
            if duration <= 0 then
                return 0
            end
            return math.max((startTime + duration) - GetTime(), 0)
        end
    end

    if type(GetSpellCooldown) == "function" then
        local startTime, duration = protectedCall(GetSpellCooldown, spellID)
        startTime = addon:UntaintNumber(startTime, 0)
        duration = addon:UntaintNumber(duration, 0)
        if duration and duration > 0 then
            return math.max((startTime + duration) - GetTime(), 0)
        end
    end

    return 0
end

local function getChargeCount(spellID)
    if type(C_Spell) == "table" and type(C_Spell.GetSpellCharges) == "function" then
        local info = protectedCall(C_Spell.GetSpellCharges, spellID)
        if type(info) == "table" then
            return addon:UntaintNumber(info.currentCharges, 0)
        end
    elseif type(GetSpellCharges) == "function" then
        return addon:UntaintNumber(protectedCall(GetSpellCharges, spellID), 0)
    end
    return 0
end

local function isSpellKnown(spellID)
    if type(IsSpellKnownOrOverridesKnown) == "function" then
        return addon:NormalizeBoolean(protectedCall(IsSpellKnownOrOverridesKnown, spellID), false)
    end
    if type(IsPlayerSpell) == "function" and addon:NormalizeBoolean(protectedCall(IsPlayerSpell, spellID), false) then
        return true
    end
    if type(IsSpellKnown) == "function" then
        return addon:NormalizeBoolean(protectedCall(IsSpellKnown, spellID), false)
    end
    return addon:GetSpellName(spellID) ~= nil
end

local function isSpellUsable(spellID)
    if type(IsUsableSpell) == "function" then
        return addon:NormalizeBoolean(protectedCall(IsUsableSpell, spellID), false)
    end
    return true
end

local function isSpellInRange(spellID, unitID)
    if type(IsSpellInRange) ~= "function" or not unitID or not unitExists(unitID) then
        return true
    end

    local result = protectedCall(IsSpellInRange, spellID, unitID)
    if result == nil then
        return true
    end

    if addon:NormalizeBoolean(result, true) == false then
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

local function shortNumber(value)
    if type(value) ~= "number" then
        return tostring(value)
    end

    return string.format("%.1f", value)
end

local function fail(reason)
    return false, reason
end

local function readAura(unitID, spellID, filter, sourceUnit)
    if not unitID or not spellID or not unitExists(unitID) or type(UnitAura) ~= "function" then
        return nil
    end

    for index = 1, 40 do
        local name, _, count, _, duration, expirationTime, source, _, _, auraSpellID = protectedCall(UnitAura, unitID, index, filter)
        local auraName = addon:NormalizeString(name)
        local normalizedSpellID = addon:UntaintNumber(auraSpellID, 0)
        if not auraName and normalizedSpellID <= 0 then
            break
        end

        if normalizedSpellID == spellID then
            local sourceToken = addon:NormalizeString(source)
            if sourceUnit and (not sourceToken or not unitExists(sourceUnit) or not unitIsUnit(sourceToken, sourceUnit)) then
                -- Keep scanning until we find the aura from the requested source.
            else
                local remaining = 0
                local normalizedExpirationTime = addon:UntaintNumber(expirationTime, 0)
                if normalizedExpirationTime > 0 then
                    remaining = math.max(normalizedExpirationTime - GetTime(), 0)
                end

                return {
                    count = addon:UntaintNumber(count, 0),
                    duration = addon:UntaintNumber(duration, 0),
                    expirationTime = normalizedExpirationTime,
                    remaining = remaining,
                    source = sourceToken,
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
        return true, nil
    end

    if entry.contentScope ~= state.mode then
        return false, "scope=" .. tostring(entry.contentScope)
    end

    return true, nil
end

local function matchesConditions(entry, state)
    local conditions = entry.conditions or {}

    if entry.specID and state.player.specID ~= entry.specID then
        return fail("spec=" .. tostring(entry.specID))
    end
    if not isSpellKnown(entry.spellID) then
        return fail("spell unknown")
    end

    if conditions.inCombat ~= nil and conditions.inCombat ~= state.player.inCombat then
        return fail(conditions.inCombat and "need combat" or "need out of combat")
    end
    if conditions.moving ~= nil and conditions.moving ~= state.player.moving then
        return fail(conditions.moving and "need movement" or "need stationary")
    end
    if conditions.mounted ~= nil and conditions.mounted ~= state.player.mounted then
        return fail(conditions.mounted and "need mounted" or "need unmounted")
    end
    if conditions.petAlive ~= nil and conditions.petAlive ~= state.player.petAlive then
        return fail(conditions.petAlive and "pet not alive" or "pet must be dead")
    end
    if conditions.requireTarget and not state.target.exists then
        return fail("no target")
    end
    if conditions.targetAlive ~= nil and conditions.targetAlive ~= state.target.alive then
        return fail(conditions.targetAlive and "target dead" or "target alive")
    end
    if conditions.targetHostile and not state.target.hostile then
        return fail("target not hostile")
    end
    if conditions.playerHpBelow then
        if not state.player.healthKnown then
            return fail("player hp unknown")
        end
        if state.player.healthPct > conditions.playerHpBelow then
            return fail(string.format("player hp %s > %s", shortNumber(state.player.healthPct), shortNumber(conditions.playerHpBelow)))
        end
    end
    if conditions.playerHpAbove then
        if not state.player.healthKnown then
            return fail("player hp unknown")
        end
        if state.player.healthPct < conditions.playerHpAbove then
            return fail(string.format("player hp %s < %s", shortNumber(state.player.healthPct), shortNumber(conditions.playerHpAbove)))
        end
    end
    if conditions.targetHpBelow then
        if not state.target.healthKnown then
            return fail("target hp unknown")
        end
        if state.target.healthPct > conditions.targetHpBelow then
            return fail(string.format("target hp %s > %s", shortNumber(state.target.healthPct), shortNumber(conditions.targetHpBelow)))
        end
    end
    if conditions.targetHpAbove then
        if not state.target.healthKnown then
            return fail("target hp unknown")
        end
        if state.target.healthPct < conditions.targetHpAbove then
            return fail(string.format("target hp %s < %s", shortNumber(state.target.healthPct), shortNumber(conditions.targetHpAbove)))
        end
    end
    if conditions.resourceAtLeast then
        if not state.player.primaryKnown then
            return fail("primary resource unknown")
        end
        if state.player.primaryCurrent < conditions.resourceAtLeast then
            return fail(string.format("resource %s < %s", shortNumber(state.player.primaryCurrent), shortNumber(conditions.resourceAtLeast)))
        end
    end
    if conditions.resourceAtMost then
        if not state.player.primaryKnown then
            return fail("primary resource unknown")
        end
        if state.player.primaryCurrent > conditions.resourceAtMost then
            return fail(string.format("resource %s > %s", shortNumber(state.player.primaryCurrent), shortNumber(conditions.resourceAtMost)))
        end
    end
    if conditions.secondaryAtLeast then
        if not state.player.secondaryKnown then
            return fail("secondary resource unknown")
        end
        if state.player.secondaryCurrent < conditions.secondaryAtLeast then
            return fail(string.format("secondary %s < %s", shortNumber(state.player.secondaryCurrent), shortNumber(conditions.secondaryAtLeast)))
        end
    end
    if conditions.secondaryAtMost then
        if not state.player.secondaryKnown then
            return fail("secondary resource unknown")
        end
        if state.player.secondaryCurrent > conditions.secondaryAtMost then
            return fail(string.format("secondary %s > %s", shortNumber(state.player.secondaryCurrent), shortNumber(conditions.secondaryAtMost)))
        end
    end
    if conditions.resourcePctAtLeast then
        if not state.player.primaryKnown then
            return fail("primary resource unknown")
        end
        if state.player.primaryPct < conditions.resourcePctAtLeast then
            return fail(string.format("resource%% %s < %s", shortNumber(state.player.primaryPct), shortNumber(conditions.resourcePctAtLeast)))
        end
    end
    if conditions.resourcePctAtMost then
        if not state.player.primaryKnown then
            return fail("primary resource unknown")
        end
        if state.player.primaryPct > conditions.resourcePctAtMost then
            return fail(string.format("resource%% %s > %s", shortNumber(state.player.primaryPct), shortNumber(conditions.resourcePctAtMost)))
        end
    end
    if conditions.secondaryPctAtLeast then
        if not state.player.secondaryKnown then
            return fail("secondary resource unknown")
        end
        if state.player.secondaryPct < conditions.secondaryPctAtLeast then
            return fail(string.format("secondary%% %s < %s", shortNumber(state.player.secondaryPct), shortNumber(conditions.secondaryPctAtLeast)))
        end
    end
    if conditions.secondaryPctAtMost then
        if not state.player.secondaryKnown then
            return fail("secondary resource unknown")
        end
        if state.player.secondaryPct > conditions.secondaryPctAtMost then
            return fail(string.format("secondary%% %s > %s", shortNumber(state.player.secondaryPct), shortNumber(conditions.secondaryPctAtMost)))
        end
    end
    if conditions.enemyCountAtLeast and (state.environment.enemyCount or 0) < conditions.enemyCountAtLeast then
        return fail(string.format("enemies %s < %s", shortNumber(state.environment.enemyCount or 0), shortNumber(conditions.enemyCountAtLeast)))
    end
    if conditions.enemyCountAtMost and (state.environment.enemyCount or 0) > conditions.enemyCountAtMost then
        return fail(string.format("enemies %s > %s", shortNumber(state.environment.enemyCount or 0), shortNumber(conditions.enemyCountAtMost)))
    end
    if conditions.targetCasting ~= nil and conditions.targetCasting ~= state.target.casting then
        return fail(conditions.targetCasting and "target not casting" or "target casting")
    end
    if conditions.targetInterruptible ~= nil and conditions.targetInterruptible ~= state.target.interruptible then
        return fail(conditions.targetInterruptible and "target not interruptible" or "target interruptible")
    end
    if conditions.rangeBucket and conditions.rangeBucket ~= state.target.rangeBucket then
        return fail("range=" .. tostring(state.target.rangeBucket))
    end
    if conditions.modeBurst ~= nil and conditions.modeBurst ~= state.modes.burst then
        return fail(conditions.modeBurst and "burst off" or "burst on")
    end
    if conditions.modeConserve ~= nil and conditions.modeConserve ~= state.modes.conserve then
        return fail(conditions.modeConserve and "conserve off" or "conserve on")
    end
    if conditions.modeHold ~= nil and conditions.modeHold ~= state.modes.hold then
        return fail(conditions.modeHold and "hold off" or "hold on")
    end
    if conditions.modePause ~= nil and conditions.modePause ~= state.modes.pause then
        return fail(conditions.modePause and "pause off" or "pause on")
    end

    local chargeCount = getChargeCount(entry.spellID)
    local cooldownRemaining = getCooldownRemaining(entry.spellID)
    local hasAvailableCharge = chargeCount > 0
    local cooldownReady = cooldownRemaining <= 0 or hasAvailableCharge
    if conditions.cooldownReady ~= nil and cooldownReady ~= conditions.cooldownReady then
        return fail(conditions.cooldownReady and "cooldown not ready" or "cooldown ready")
    end
    if cooldownRemaining > 0 and not hasAvailableCharge then
        return fail(string.format("cooldown %.1fs", cooldownRemaining))
    end

    if conditions.chargesAtLeast and chargeCount < conditions.chargesAtLeast then
        return fail(string.format("charges %d < %d", chargeCount, conditions.chargesAtLeast))
    end
    if conditions.chargesAtMost and chargeCount > conditions.chargesAtMost then
        return fail(string.format("charges %d > %d", chargeCount, conditions.chargesAtMost))
    end

    if not matchesAuraList(conditions.auraPresent, function(auraCondition)
        return readAura(auraCondition.unit, auraCondition.spellID, auraCondition.filter, auraCondition.sourceUnit) ~= nil
    end) then
        local auraCondition = asConditionList(conditions.auraPresent)[1]
        return fail("missing aura " .. tostring(auraCondition and auraCondition.spellID or "?"))
    end
    if not matchesAuraList(conditions.auraMissing, function(auraCondition)
        return readAura(auraCondition.unit, auraCondition.spellID, auraCondition.filter, auraCondition.sourceUnit) == nil
    end) then
        local auraCondition = asConditionList(conditions.auraMissing)[1]
        return fail("aura up " .. tostring(auraCondition and auraCondition.spellID or "?"))
    end
    if not matchesAuraList(conditions.auraRemainingBelow, function(auraCondition)
        local aura = readAura(auraCondition.unit, auraCondition.spellID, auraCondition.filter, auraCondition.sourceUnit)
        return aura ~= nil and aura.remaining <= (auraCondition.seconds or 0)
    end) then
        local auraCondition = asConditionList(conditions.auraRemainingBelow)[1]
        return fail("aura remains > " .. tostring(auraCondition and auraCondition.seconds or "?"))
    end
    if not matchesAuraList(conditions.auraRemainingAbove, function(auraCondition)
        local aura = readAura(auraCondition.unit, auraCondition.spellID, auraCondition.filter, auraCondition.sourceUnit)
        return aura ~= nil and aura.remaining >= (auraCondition.seconds or 0)
    end) then
        local auraCondition = asConditionList(conditions.auraRemainingAbove)[1]
        return fail("aura remains < " .. tostring(auraCondition and auraCondition.seconds or "?"))
    end
    if not matchesAuraList(conditions.auraStacksAtLeast, function(auraCondition)
        local aura = readAura(auraCondition.unit, auraCondition.spellID, auraCondition.filter, auraCondition.sourceUnit)
        return aura ~= nil and (aura.count or 0) >= (auraCondition.stacks or 0)
    end) then
        local auraCondition = asConditionList(conditions.auraStacksAtLeast)[1]
        return fail("aura stacks < " .. tostring(auraCondition and auraCondition.stacks or "?"))
    end
    if not matchesAuraList(conditions.auraStacksAtMost, function(auraCondition)
        local aura = readAura(auraCondition.unit, auraCondition.spellID, auraCondition.filter, auraCondition.sourceUnit)
        return aura ~= nil and (aura.count or 0) <= (auraCondition.stacks or 0)
    end) then
        local auraCondition = asConditionList(conditions.auraStacksAtMost)[1]
        return fail("aura stacks > " .. tostring(auraCondition and auraCondition.stacks or "?"))
    end

    if conditions.requireTarget and not isSpellInRange(entry.spellID, "target") then
        return fail("spell out of range")
    end

    if not isSpellUsable(entry.spellID) then
        return fail("spell unusable")
    end

    return true, nil
end

function Recommendations:Initialize()
    self.latest = {
        updatedAt = 0,
        slots = {},
    }
end

function Recommendations:Refresh(state, options)
    state = state or addon.State:Refresh()
    options = options or {}

    local diagnosticsEnabled = options.diagnostics == true or (addon.session and addon.session.debug)
    local result = {
        updatedAt = GetTime(),
        slots = {},
        diagnostics = diagnosticsEnabled and {
            slots = {},
            paused = false,
        } or nil,
    }

    if state.modes.pause then
        if result.diagnostics then
            result.diagnostics.paused = true
        end
        self.latest = result
        return result
    end

    local selectedSpellIDs = {}

    for _, slot in ipairs(addon:GetSlotOrder()) do
        local selected = nil
        local slotDiagnostics = diagnosticsEnabled and {
            rejected = {},
            totalEntries = 0,
        } or nil

        for _, record in ipairs(addon.Registry:GetEntriesForSlot(slot)) do
            local entry = record.entry
            local matched = false
            local reason = nil

            if slotDiagnostics then
                slotDiagnostics.totalEntries = slotDiagnostics.totalEntries + 1
            end

            if not entry.enabled then
                reason = "disabled"
            elseif selectedSpellIDs[entry.spellID] then
                reason = "already selected"
            else
                local scopeMatches, scopeReason = matchesScope(entry, state)
                if not scopeMatches then
                    reason = scopeReason
                else
                    matched, reason = matchesConditions(entry, state)
                end
            end

            if matched then
                selected = entry
                selectedSpellIDs[entry.spellID] = true
                if slotDiagnostics then
                    slotDiagnostics.selected = {
                        spellID = entry.spellID,
                        name = addon:GetSpellName(entry.spellID) or tostring(entry.spellID),
                        note = entry.note,
                        priority = entry.priority,
                    }
                end
                break
            elseif slotDiagnostics and #slotDiagnostics.rejected < 3 then
                slotDiagnostics.rejected[#slotDiagnostics.rejected + 1] = {
                    spellID = entry.spellID,
                    name = addon:GetSpellName(entry.spellID) or tostring(entry.spellID),
                    note = entry.note,
                    priority = entry.priority,
                    reason = reason or "rejected",
                }
            end
        end

        if slotDiagnostics then
            if not slotDiagnostics.selected and slotDiagnostics.totalEntries == 0 then
                slotDiagnostics.empty = true
            end
            result.diagnostics.slots[slot] = slotDiagnostics
        end

        result.slots[slot] = selected
    end

    self.latest = result
    return result
end

addon.Recommendations = Recommendations
