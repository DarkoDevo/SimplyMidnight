local _, addon = ...

local Recommendations = {
    latest = {
        slots = {},
    },
}
local OUTBREAK_SPELL_ID = 77575
local OUTBREAK_DISEASE_ALIASES = {
    [191587] = true,
    [1240996] = true,
    [196782] = true,
    [1241786] = true,
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

local function auraSpellMatches(requestedSpellID, actualSpellID)
    requestedSpellID = tonumber(requestedSpellID) or 0
    actualSpellID = tonumber(actualSpellID) or 0
    if requestedSpellID <= 0 or actualSpellID <= 0 then
        return false
    end

    if requestedSpellID == actualSpellID then
        return true
    end

    return OUTBREAK_DISEASE_ALIASES[requestedSpellID] == true and OUTBREAK_DISEASE_ALIASES[actualSpellID] == true
end

local function getAuraCandidateSpellIDs(spellID)
    spellID = tonumber(spellID) or 0
    if spellID <= 0 then
        return {}
    end

    if OUTBREAK_DISEASE_ALIASES[spellID] then
        return { 191587, 1240996, 196782, 1241786 }
    end

    return { spellID }
end

local function rememberObservedAura(unitID, requestedSpellID, actualSpellID, duration, remaining)
    if not unitID or not addon.Trackers or type(addon.Trackers.RememberSpellForUnit) ~= "function" then
        return
    end

    local requestedID = tonumber(requestedSpellID) or 0
    local actualID = tonumber(actualSpellID) or 0
    if not OUTBREAK_DISEASE_ALIASES[requestedID] and not OUTBREAK_DISEASE_ALIASES[actualID] then
        return
    end

    local rememberFor = math.max(tonumber(remaining) or 0, tonumber(duration) or 0, 0)
    if rememberFor <= 0 then
        return
    end

    addon.Trackers:RememberSpellForUnit(unitID, actualID > 0 and actualID or requestedID, rememberFor)
end

local function priorityOf(entry)
    return tonumber(entry and entry.priority) or 0
end

local function findCandidateBySpellID(candidates, spellID)
    spellID = tonumber(spellID) or 0
    if spellID <= 0 or type(candidates) ~= "table" then
        return nil
    end

    for _, candidate in ipairs(candidates) do
        if tonumber(candidate and candidate.spellID) == spellID then
            return candidate
        end
    end

    return nil
end

local function getAuraObject(unitID, index, filter)
    if type(C_UnitAuras) == "table" and type(C_UnitAuras.GetAuraDataByIndex) == "function" then
        local auraData = protectedCall(C_UnitAuras.GetAuraDataByIndex, unitID, index, filter)
        return addon:NormalizeAuraData(auraData)
    end

    if type(UnitAura) == "function" then
        local name, icon, count, dispelType, duration, expirationTime, sourceUnit, isStealable, nameplateShowPersonal, spellId, canApplyAura, isBossAura = protectedCall(UnitAura, unitID, index, filter)
        if name == nil and spellId == nil then
            return nil
        end

        return addon:NormalizeAuraData({
            name = name,
            icon = icon,
            applications = count,
            dispelName = dispelType,
            duration = duration,
            expirationTime = expirationTime,
            sourceUnit = sourceUnit,
            isStealable = isStealable,
            nameplateShowPersonal = nameplateShowPersonal,
            spellId = spellId,
            canApplyAura = canApplyAura,
            isBossAura = isBossAura,
        })
    end

    return nil
end

local function tryActionAuraLookup(unitID, spellID, filter, sourceUnit)
    local unit = addon:GetActionUnit(unitID)
    if not unit then
        return nil
    end

    local sourceIsPlayer = sourceUnit and unitExists(sourceUnit) and unitIsUnit(sourceUnit, "player") or false
    local isHelpful = tostring(filter or ""):upper():find("HELPFUL", 1, true) ~= nil
    local remainMethodName = isHelpful and "HasBuffs" or "HasDeBuffs"
    local stacksMethodName = isHelpful and "HasBuffsStacks" or "HasDeBuffsStacks"
    local remainMethod = unit[remainMethodName]
    local stacksMethod = unit[stacksMethodName]
    if type(remainMethod) ~= "function" then
        return nil
    end

    local bestAura = nil
    for _, candidateSpellID in ipairs(getAuraCandidateSpellIDs(spellID)) do
        local okRemain, remain, duration = pcall(remainMethod, unit, candidateSpellID, sourceIsPlayer, true)
        if okRemain then
            remain = addon:UntaintNumber(remain, 0)
            duration = addon:UntaintNumber(duration, 0)
            if remain > 0 or duration > 0 then
                local count = 0
                if type(stacksMethod) == "function" then
                    local okStacks, stacks = pcall(stacksMethod, unit, candidateSpellID, sourceIsPlayer, true)
                    if okStacks then
                        count = addon:UntaintNumber(stacks, 0)
                    end
                end

                local expirationTime = 0
                if remain > 0 and remain < math.huge then
                    expirationTime = GetTime() + remain
                end

                bestAura = {
                    count = count > 0 and count or 1,
                    duration = duration,
                    expirationTime = expirationTime,
                    remaining = remain == math.huge and 0 or remain,
                    source = sourceIsPlayer and "player" or nil,
                }

                if remain > 0 then
                    rememberObservedAura(unitID, spellID, candidateSpellID, duration, remain)
                    return bestAura
                end
            end
        end
    end

    return bestAura
end

local function readAura(unitID, spellID, filter, sourceUnit)
    if not unitID or not spellID or not unitExists(unitID) then
        return nil
    end

    for index = 1, 40 do
        local auraData = getAuraObject(unitID, index, filter)
        local normalizedSpellID = auraData and addon:UntaintNumber(auraData.spellId or auraData.spellID, 0) or 0
        local auraName = auraData and addon:NormalizeString(auraData.name) or nil
        if not auraData or (not auraName and normalizedSpellID <= 0) then
            break
        end

        if auraSpellMatches(spellID, normalizedSpellID) then
            local sourceToken = addon:NormalizeString(auraData.sourceUnit or auraData.unitCaster)
            if sourceUnit and (not sourceToken or not unitExists(sourceUnit) or not unitIsUnit(sourceToken, sourceUnit)) then
                -- Keep scanning until we find the aura from the requested source.
            else
                local remaining = 0
                local normalizedExpirationTime = addon:UntaintNumber(auraData.expirationTime, 0)
                if normalizedExpirationTime > 0 then
                    remaining = math.max(normalizedExpirationTime - GetTime(), 0)
                end
                local count = addon:UntaintNumber(auraData.applications, 0)
                if count <= 0 then
                    count = 1
                end
                local normalizedDuration = addon:UntaintNumber(auraData.duration, 0)

                rememberObservedAura(unitID, spellID, normalizedSpellID, normalizedDuration, remaining)

                return {
                    count = count,
                    duration = normalizedDuration,
                    expirationTime = normalizedExpirationTime,
                    remaining = remaining,
                    source = sourceToken,
                }
            end
        end
    end

    local trackedAura = addon.Trackers and addon.Trackers.GetTrackedAura and addon.Trackers:GetTrackedAura(unitID, spellID, filter, sourceUnit) or nil
    if trackedAura then
        return trackedAura
    end

    return tryActionAuraLookup(unitID, spellID, filter, sourceUnit)
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
        if not state.player.primaryPctKnown then
            return fail("primary resource unknown")
        end
        if state.player.primaryPct < conditions.resourcePctAtLeast then
            return fail(string.format("resource%% %s < %s", shortNumber(state.player.primaryPct), shortNumber(conditions.resourcePctAtLeast)))
        end
    end
    if conditions.resourcePctAtMost then
        if not state.player.primaryPctKnown then
            return fail("primary resource unknown")
        end
        if state.player.primaryPct > conditions.resourcePctAtMost then
            return fail(string.format("resource%% %s > %s", shortNumber(state.player.primaryPct), shortNumber(conditions.resourcePctAtMost)))
        end
    end
    if conditions.secondaryPctAtLeast then
        if not state.player.secondaryPctKnown then
            return fail("secondary resource unknown")
        end
        if state.player.secondaryPct < conditions.secondaryPctAtLeast then
            return fail(string.format("secondary%% %s < %s", shortNumber(state.player.secondaryPct), shortNumber(conditions.secondaryPctAtLeast)))
        end
    end
    if conditions.secondaryPctAtMost then
        if not state.player.secondaryPctKnown then
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
        if aura == nil then
            return false
        end
        if aura.provisional then
            return false
        end
        return aura.remaining <= (auraCondition.seconds or 0)
    end) then
        local auraCondition = asConditionList(conditions.auraRemainingBelow)[1]
        return fail("aura remains > " .. tostring(auraCondition and auraCondition.seconds or "?"))
    end
    if not matchesAuraList(conditions.auraRemainingAbove, function(auraCondition)
        local aura = readAura(auraCondition.unit, auraCondition.spellID, auraCondition.filter, auraCondition.sourceUnit)
        if aura == nil then
            return false
        end
        if aura.provisional then
            return true
        end
        return aura.remaining >= (auraCondition.seconds or 0)
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
    self.primaryCommit = nil
end

function Recommendations:ResolveCommittedPrimary(candidates)
    local topCandidate = candidates and candidates[1] or nil
    if not topCandidate then
        self.primaryCommit = nil
        return nil
    end

    if not self.primaryCommit or not self.primaryCommit.spellID then
        self.primaryCommit = {
            spellID = topCandidate.spellID,
            entry = topCandidate,
        }
        return topCandidate
    end

    local committedCandidate = findCandidateBySpellID(candidates, self.primaryCommit.spellID)
    if not committedCandidate then
        self.primaryCommit = {
            spellID = topCandidate.spellID,
            entry = topCandidate,
        }
        return topCandidate
    end

    if tonumber(committedCandidate.spellID) == tonumber(topCandidate.spellID) then
        self.primaryCommit.entry = topCandidate
        return topCandidate
    end

    local sameGroup = committedCandidate.decisionGroup ~= nil and committedCandidate.decisionGroup == topCandidate.decisionGroup
    local margin = tonumber(committedCandidate.commitMargin or topCandidate.commitMargin) or (sameGroup and 18 or 10)

    if topCandidate.overridePrimary or priorityOf(topCandidate) >= (priorityOf(committedCandidate) + margin) then
        self.primaryCommit = {
            spellID = topCandidate.spellID,
            entry = topCandidate,
        }
        return topCandidate
    end

    self.primaryCommit.entry = committedCandidate
    return committedCandidate
end

function Recommendations:ResolvePrimaryOverride(primaryEntry, slotSelections)
    local overrideEntry = nil
    local overrideScore = -math.huge

    local interruptEntry = slotSelections.interrupt
    if interruptEntry and interruptEntry.overridePrimary then
        overrideEntry = interruptEntry
        overrideScore = priorityOf(interruptEntry) + 100
    end

    local defensiveEntry = slotSelections.defensive
    if defensiveEntry and defensiveEntry.overridePrimary then
        local defensiveScore = priorityOf(defensiveEntry) + 60
        if defensiveScore > overrideScore then
            overrideEntry = defensiveEntry
            overrideScore = defensiveScore
        end
    end

    if not overrideEntry then
        return primaryEntry
    end

    if not primaryEntry or overrideScore >= (priorityOf(primaryEntry) + 5) then
        return overrideEntry
    end

    return primaryEntry
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
    local slotSelections = {}

    for _, slot in ipairs(addon:GetSlotOrder()) do
        local selected = nil
        local matchedEntries = {}
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
                matchedEntries[#matchedEntries + 1] = entry
                if not selected then
                    selected = entry
                    if slotDiagnostics then
                        slotDiagnostics.selected = {
                            spellID = entry.spellID,
                            name = addon:GetSpellName(entry.spellID) or tostring(entry.spellID),
                            note = entry.note,
                            priority = entry.priority,
                        }
                    end
                    if slot ~= "primary" then
                        break
                    end
                end
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

        if slot == "primary" then
            selected = self:ResolveCommittedPrimary(matchedEntries)
            if slotDiagnostics and selected then
                slotDiagnostics.selected = {
                    spellID = selected.spellID,
                    name = addon:GetSpellName(selected.spellID) or tostring(selected.spellID),
                    note = selected.note,
                    priority = selected.priority,
                }
            end
        end

        if selected then
            selectedSpellIDs[selected.spellID] = true
        end

        if slotDiagnostics then
            if not slotDiagnostics.selected and slotDiagnostics.totalEntries == 0 then
                slotDiagnostics.empty = true
            end
            result.diagnostics.slots[slot] = slotDiagnostics
        end

        result.slots[slot] = selected
        slotSelections[slot] = selected
        if selected and addon.Trackers and addon.Trackers.RememberSuggestion then
            addon.Trackers:RememberSuggestion(selected.spellID, "target")
        end
    end

    result.slots.primary = self:ResolvePrimaryOverride(result.slots.primary, slotSelections)
    if result.diagnostics and result.slots.primary then
        result.diagnostics.slots.primary.selected = {
            spellID = result.slots.primary.spellID,
            name = addon:GetSpellName(result.slots.primary.spellID) or tostring(result.slots.primary.spellID),
            note = result.slots.primary.note,
            priority = result.slots.primary.priority,
        }
    end

    self.latest = result
    return result
end

addon.Recommendations = Recommendations
