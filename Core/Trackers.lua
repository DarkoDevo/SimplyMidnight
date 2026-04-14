local _, addon = ...

local Trackers = {
    outbreakTrackedByGUID = {},
    outbreakRequestedByGUID = {},
    lastObservedOutbreakSinceLastCast = math.huge,
    lastObservedOutbreakCastAt = 0,
    lastObservedOutbreakTargetGUID = nil,
    resourceEstimates = {},
}

local OUTBREAK_SPELL_ID = 77575
local OUTBREAK_TRACK_SECONDS = 24
local OUTBREAK_REQUEST_SECONDS = 1.5
local OUTBREAK_DISEASE_IDS = {
    191587,
    1240996,
    196782,
    1241786,
}

local function protectedCall(callback, ...)
    if type(callback) ~= "function" then
        return nil
    end

    local ok, resultA, resultB, resultC, resultD, resultE = pcall(callback, ...)
    if not ok then
        return nil
    end

    return resultA, resultB, resultC, resultD, resultE
end

local function now()
    return type(GetTime) == "function" and GetTime() or 0
end

local function untaintNumber(value, fallback)
    return addon:UntaintNumber(value, fallback)
end

local function unitGUID(unitID)
    return addon:NormalizeString(protectedCall(UnitGUID, unitID))
end

local function unitIsUnit(leftUnitID, rightUnitID)
    return addon:NormalizeBoolean(protectedCall(UnitIsUnit, leftUnitID, rightUnitID), false)
end

local function clamp(value, minimum, maximum)
    value = tonumber(value) or 0
    minimum = tonumber(minimum) or 0
    maximum = tonumber(maximum) or minimum
    if value < minimum then
        return minimum
    end
    if value > maximum then
        return maximum
    end
    return value
end

local function percentage(current, maximum)
    current = tonumber(current)
    maximum = tonumber(maximum)
    if not current or not maximum or maximum <= 0 then
        return 0
    end

    return clamp((current / maximum) * 100, 0, 100)
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

local function unitHasAura(unitID, spellID, filter)
    if not unitID or not spellID then
        return false
    end

    for index = 1, 40 do
        local auraData = getAuraObject(unitID, index, filter)
        if auraData then
            local auraSpellID = addon:UntaintNumber(auraData.spellId or auraData.spellID, 0)
            if auraSpellID == tonumber(spellID) then
                return true
            end
        end
    end

    return false
end

local function isOutbreakDiseaseSpell(spellID)
    spellID = tonumber(spellID)
    if not spellID then
        return false
    end

    for index = 1, #OUTBREAK_DISEASE_IDS do
        if OUTBREAK_DISEASE_IDS[index] == spellID then
            return true
        end
    end

    return false
end

local function getSpellCooldownRemaining(spellID)
    if type(C_Spell) == "table" and type(C_Spell.GetSpellCooldown) == "function" then
        local info = protectedCall(C_Spell.GetSpellCooldown, spellID)
        if type(info) == "table" then
            local startTime = addon:UntaintNumber(info.startTime, 0)
            local duration = addon:UntaintNumber(info.duration, 0)
            if duration > 0 then
                return math.max((startTime + duration) - now(), 0)
            end
        end
    end

    if type(GetSpellCooldown) == "function" then
        local startTime, duration = protectedCall(GetSpellCooldown, spellID)
        startTime = addon:UntaintNumber(startTime, 0)
        duration = addon:UntaintNumber(duration, 0)
        if duration > 0 then
            return math.max((startTime + duration) - now(), 0)
        end
    end

    return 0
end

local function getActionSpellTimeSinceLastCast(spellID)
    if type(addon.GetActionSpell) ~= "function" then
        return math.huge
    end

    local spell = addon:GetActionSpell(spellID)
    if type(spell) ~= "table" or type(spell.GetSpellTimeSinceLastCast) ~= "function" then
        return math.huge
    end

    local sinceLastCast = untaintNumber(protectedCall(spell.GetSpellTimeSinceLastCast, spell), math.huge)
    if type(sinceLastCast) ~= "number" or sinceLastCast < 0 then
        return math.huge
    end

    return sinceLastCast
end

function Trackers:Initialize()
    if self.initialized then
        return
    end

    self.initialized = true
    self.outbreakTrackedByGUID = {}
    self.outbreakRequestedByGUID = {}
    self.lastObservedOutbreakSinceLastCast = math.huge
    self.lastObservedOutbreakCastAt = 0
    self.lastObservedOutbreakTargetGUID = nil
    self.resourceEstimates = {}

    addon:RegisterRuntimeEvent("COMBAT_LOG_EVENT_UNFILTERED", self, "OnRuntimeEvent")
    addon:RegisterRuntimeEvent("PLAYER_ENTERING_WORLD", self, "OnRuntimeEvent")
    addon:RegisterRuntimeEvent("PLAYER_REGEN_ENABLED", self, "OnRuntimeEvent")
end

function Trackers:GetEstimatedPrimaryResource(config, hints)
    if type(config) ~= "table" or not config.id then
        return nil
    end

    hints = type(hints) == "table" and hints or {}
    local estimate = self.resourceEstimates[config.id]
    if type(estimate) ~= "table" then
        estimate = {
            current = tonumber(config.defaultCurrent) or 0,
            max = tonumber(config.max) or 100,
            known = false,
            config = config,
            lastSecondaryCurrent = nil,
            spenderSinceLastCast = {},
            spenderBuffState = {},
            totalGenerated = 0,
            totalSpent = 0,
            lastObservedSpellID = nil,
            debug = {},
        }
        self.resourceEstimates[config.id] = estimate
    else
        estimate.config = config
    end

    local maxValue = tonumber(config.max) or estimate.max or 100
    estimate.max = maxValue

    local inCombat = hints.inCombat == true
    local secondaryCurrent = tonumber(hints.secondaryCurrent)
    local secondaryMax = tonumber(hints.secondaryMax)
    local rawCurrent = tonumber(hints.rawCurrent)
    local rawKnown = hints.rawKnown == true

    if rawKnown then
        estimate.current = clamp(rawCurrent, 0, maxValue)
        estimate.known = true
    elseif config.resetOutOfCombat and not inCombat then
        estimate.current = clamp(config.defaultCurrent or 0, 0, maxValue)
        estimate.known = true
    else
        local generated = 0
        local seeded = 0
        if config.seedFromSecondaryGap and estimate.lastSecondaryCurrent == nil and secondaryCurrent ~= nil and secondaryMax and secondaryMax > 0 then
            local perSpend = tonumber(config.generationPerSecondarySpend) or 0
            local missingSecondary = math.max(0, secondaryMax - secondaryCurrent)
            seeded = missingSecondary * perSpend
            if seeded > 0 then
                estimate.current = clamp(math.max(estimate.current or 0, seeded), 0, maxValue)
                estimate.known = true
                estimate.totalGenerated = (estimate.totalGenerated or 0) + seeded
            end
        end

        if secondaryCurrent and estimate.lastSecondaryCurrent ~= nil and secondaryCurrent < estimate.lastSecondaryCurrent then
            local spentSecondary = estimate.lastSecondaryCurrent - secondaryCurrent
            local perSpend = tonumber(config.generationPerSecondarySpend) or 0
            generated = math.max(0, spentSecondary) * perSpend
            if generated > 0 then
                estimate.current = clamp((estimate.current or 0) + generated, 0, maxValue)
                estimate.known = true
                estimate.totalGenerated = (estimate.totalGenerated or 0) + generated
            end
        end

        local spent = 0
        for spellID, spellConfig in pairs(config.spenderSpells or {}) do
            local sinceLastCast = getActionSpellTimeSinceLastCast(spellID)
            local previousSinceLastCast = estimate.spenderSinceLastCast[spellID] or math.huge
            local previousBuffActive = estimate.spenderBuffState[spellID] == true
            local observedCast = false

            if sinceLastCast ~= math.huge and sinceLastCast <= 10 then
                if previousSinceLastCast == math.huge then
                    observedCast = sinceLastCast <= 0.4
                else
                    observedCast = sinceLastCast + 0.2 < previousSinceLastCast
                end
            end

            if observedCast then
                local spellCost = tonumber(spellConfig.cost) or 0
                if spellConfig.freeBuffSpellID and previousBuffActive then
                    spellCost = 0
                end
                if spellCost > 0 then
                    spent = spent + spellCost
                    estimate.current = clamp((estimate.current or 0) - spellCost, 0, maxValue)
                    estimate.known = true
                    estimate.totalSpent = (estimate.totalSpent or 0) + spellCost
                    estimate.lastObservedSpellID = tonumber(spellID) or nil
                end
            end

            estimate.spenderSinceLastCast[spellID] = sinceLastCast
            estimate.spenderBuffState[spellID] = spellConfig.freeBuffSpellID and unitHasAura("player", spellConfig.freeBuffSpellID, "HELPFUL") or false
        end

        estimate.debug = {
            generated = generated,
            spent = spent,
            seeded = seeded,
            totalGenerated = estimate.totalGenerated,
            totalSpent = estimate.totalSpent,
            lastSpellID = estimate.lastObservedSpellID,
        }
    end

    if secondaryCurrent ~= nil then
        estimate.lastSecondaryCurrent = secondaryCurrent
    end

    return {
        current = clamp(estimate.current or 0, 0, maxValue),
        max = maxValue,
        pct = percentage(estimate.current or 0, maxValue),
        known = estimate.known == true,
        estimated = true,
        debug = estimate.debug,
    }
end

function Trackers:ObserveSpellCast(spellID, sourceGUID, destGUID)
    spellID = tonumber(spellID)
    if not spellID then
        return
    end

    local playerGUID = unitGUID("player")
    if playerGUID and sourceGUID and sourceGUID ~= playerGUID then
        return
    end

    if spellID == OUTBREAK_SPELL_ID then
        self.lastObservedOutbreakCastAt = now()
        self.lastObservedOutbreakTargetGUID = addon:NormalizeString(destGUID) or unitGUID("target")
    end

    for _, estimate in pairs(self.resourceEstimates) do
        local config = type(estimate) == "table" and estimate.config or nil
        local spellConfig = config and config.spenderSpells and config.spenderSpells[spellID] or nil
        if type(spellConfig) == "table" then
            local spellCost = tonumber(spellConfig.cost) or 0
            local previousBuffActive = estimate.spenderBuffState and estimate.spenderBuffState[spellID] == true
            if spellConfig.freeBuffSpellID and previousBuffActive then
                spellCost = 0
            end

            if spellCost > 0 then
                estimate.current = clamp((estimate.current or 0) - spellCost, 0, tonumber(config.max) or estimate.max or 100)
                estimate.known = true
                estimate.totalSpent = (estimate.totalSpent or 0) + spellCost
            end

            estimate.lastObservedSpellID = spellID
            estimate.spenderSinceLastCast[spellID] = 0
            if type(estimate.debug) ~= "table" then
                estimate.debug = {}
            end
            estimate.debug.lastSpellID = spellID
        end
    end
end

function Trackers:OnRuntimeEvent(event)
    if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_REGEN_ENABLED" then
        self.lastObservedOutbreakSinceLastCast = math.huge
        self.lastObservedOutbreakCastAt = 0
        self.lastObservedOutbreakTargetGUID = nil
        return
    end

    if event ~= "COMBAT_LOG_EVENT_UNFILTERED" or type(CombatLogGetCurrentEventInfo) ~= "function" then
        return
    end

    local _, subEvent, _, sourceGUID, _, _, _, destGUID, _, _, _, spellID = CombatLogGetCurrentEventInfo()
    if sourceGUID ~= unitGUID("player") then
        return
    end

    if subEvent == "SPELL_CAST_SUCCESS" then
        self:ObserveSpellCast(spellID, sourceGUID, destGUID)
        return
    end

    if (subEvent == "SPELL_AURA_APPLIED" or subEvent == "SPELL_AURA_REFRESH") and isOutbreakDiseaseSpell(spellID) and destGUID then
        self:RememberOutbreakForGUID(destGUID, OUTBREAK_TRACK_SECONDS)
    end
end

function Trackers:RememberSpellForGUID(guid, spellID, durationSeconds)
    guid = addon:NormalizeString(guid)
    spellID = tonumber(spellID)
    durationSeconds = tonumber(durationSeconds) or OUTBREAK_TRACK_SECONDS
    if not guid or not spellID or durationSeconds <= 0 then
        return
    end

    local expiresAt = now() + durationSeconds
    local tracked = self.outbreakTrackedByGUID[guid]
    if type(tracked) ~= "table" then
        tracked = {}
        self.outbreakTrackedByGUID[guid] = tracked
    end

    tracked[spellID] = math.max(tracked[spellID] or 0, expiresAt)
end

function Trackers:RememberSpellForUnit(unitID, spellID, durationSeconds)
    local guid = unitGUID(unitID)
    if guid then
        self:RememberSpellForGUID(guid, spellID, durationSeconds)
    end
end

function Trackers:ForgetSpellForGUID(guid, spellID)
    guid = addon:NormalizeString(guid)
    spellID = tonumber(spellID)
    local tracked = guid and self.outbreakTrackedByGUID[guid] or nil
    if type(tracked) ~= "table" or not spellID then
        return
    end

    tracked[spellID] = nil
    if next(tracked) == nil then
        self.outbreakTrackedByGUID[guid] = nil
    end
end

function Trackers:RememberOutbreakForGUID(guid, durationSeconds)
    guid = addon:NormalizeString(guid)
    if not guid then
        return
    end

    for index = 1, #OUTBREAK_DISEASE_IDS do
        self:RememberSpellForGUID(guid, OUTBREAK_DISEASE_IDS[index], durationSeconds)
    end
end

function Trackers:RememberOutbreakForUnit(unitID, durationSeconds)
    local guid = unitGUID(unitID)
    if guid then
        self:RememberOutbreakForGUID(guid, durationSeconds)
    end
end

function Trackers:RememberOutbreakRequestForGUID(guid, durationSeconds)
    guid = addon:NormalizeString(guid)
    durationSeconds = tonumber(durationSeconds) or OUTBREAK_REQUEST_SECONDS
    if not guid or durationSeconds <= 0 then
        return
    end

    local requestedAt = now()
    local existing = self.outbreakRequestedByGUID[guid]
    local existingRequestedAt = type(existing) == "table" and tonumber(existing.requestedAt) or 0
    local existingExpiresAt = type(existing) == "table" and tonumber(existing.expiresAt) or tonumber(existing) or 0

    if existingRequestedAt > 0 and existingExpiresAt > requestedAt then
        self.outbreakRequestedByGUID[guid] = {
            requestedAt = existingRequestedAt,
            expiresAt = math.max(existingExpiresAt, requestedAt + durationSeconds),
        }
        return
    end

    self.outbreakRequestedByGUID[guid] = {
        requestedAt = requestedAt,
        expiresAt = requestedAt + durationSeconds,
    }
end

function Trackers:RememberOutbreakRequestForUnit(unitID, durationSeconds)
    local guid = unitGUID(unitID)
    if guid then
        self:RememberOutbreakRequestForGUID(guid, durationSeconds)
    end
end

function Trackers:RememberSuggestion(spellID, unitID)
    if tonumber(spellID) ~= OUTBREAK_SPELL_ID then
        return
    end

    self:RememberOutbreakRequestForUnit(unitID or "target", OUTBREAK_REQUEST_SECONDS)
end

function Trackers:Poll()
    local currentTime = now()
    local sinceLastOutbreakCast = getActionSpellTimeSinceLastCast(OUTBREAK_SPELL_ID)
    local observedOutbreakCastAt = 0
    if sinceLastOutbreakCast ~= math.huge and sinceLastOutbreakCast <= 12 then
        observedOutbreakCastAt = math.max(0, currentTime - sinceLastOutbreakCast)

        if sinceLastOutbreakCast + 0.2 < (tonumber(self.lastObservedOutbreakSinceLastCast) or math.huge) then
            self.lastObservedOutbreakCastAt = observedOutbreakCastAt
            self.lastObservedOutbreakTargetGUID = unitGUID("target")
        end

        self.lastObservedOutbreakSinceLastCast = sinceLastOutbreakCast
    else
        self.lastObservedOutbreakSinceLastCast = math.huge
    end

    for guid, requestState in pairs(self.outbreakRequestedByGUID) do
        local requestedAt = 0
        local expiresAt = 0
        if type(requestState) == "table" then
            requestedAt = tonumber(requestState.requestedAt) or 0
            expiresAt = tonumber(requestState.expiresAt) or 0
        else
            expiresAt = tonumber(requestState) or 0
            requestedAt = math.max(0, expiresAt - OUTBREAK_REQUEST_SECONDS)
        end

        if expiresAt <= currentTime then
            self.outbreakRequestedByGUID[guid] = nil
        elseif observedOutbreakCastAt > 0 and requestedAt > 0 and observedOutbreakCastAt >= (requestedAt - 0.25) then
            self:RememberOutbreakForGUID(guid, OUTBREAK_TRACK_SECONDS)
            self.outbreakRequestedByGUID[guid] = nil
        elseif getSpellCooldownRemaining(OUTBREAK_SPELL_ID) > 0 then
            self:RememberOutbreakForGUID(guid, OUTBREAK_TRACK_SECONDS)
            self.outbreakRequestedByGUID[guid] = nil
        end
    end

    for guid, tracked in pairs(self.outbreakTrackedByGUID) do
        local keepAny = false
        if type(tracked) == "table" then
            for spellID, expiresAt in pairs(tracked) do
                if expiresAt <= currentTime then
                    tracked[spellID] = nil
                else
                    keepAny = true
                end
            end
        end

        if not keepAny then
            self.outbreakTrackedByGUID[guid] = nil
        end
    end
end

function Trackers:GetTrackedAura(unitID, spellID, filter, sourceUnit)
    self:Poll()

    if not unitID or not spellID then
        return nil
    end

    local upperFilter = tostring(filter or ""):upper()
    if not upperFilter:find("HARMFUL", 1, true) then
        return nil
    end

    if sourceUnit and not unitIsUnit(sourceUnit, "player") then
        return nil
    end

    local guid = unitGUID(unitID)
    if not guid then
        return nil
    end

    local tracked = self.outbreakTrackedByGUID[guid]
    if type(tracked) ~= "table" then
        tracked = nil
    end

    local expiresAt = tracked and tracked[tonumber(spellID)] or 0
    local currentTime = now()
    if expiresAt <= currentTime and isOutbreakDiseaseSpell(spellID) then
        for index = 1, #OUTBREAK_DISEASE_IDS do
            expiresAt = math.max(expiresAt, tracked and tracked[OUTBREAK_DISEASE_IDS[index]] or 0)
        end
    end

    if expiresAt <= currentTime then
        local recentObservedCastAt = tonumber(self.lastObservedOutbreakCastAt) or 0
        if isOutbreakDiseaseSpell(spellID) and recentObservedCastAt > 0 and guid == self.lastObservedOutbreakTargetGUID then
            local recentRemaining = OUTBREAK_TRACK_SECONDS - math.max(0, currentTime - recentObservedCastAt)
            if recentRemaining > 0 then
                self:RememberOutbreakForGUID(guid, recentRemaining)
                tracked = self.outbreakTrackedByGUID[guid]
                expiresAt = tracked and tracked[tonumber(spellID)] or 0
                for index = 1, #OUTBREAK_DISEASE_IDS do
                    expiresAt = math.max(expiresAt, tracked and tracked[OUTBREAK_DISEASE_IDS[index]] or 0)
                end
            end
        end
    end

    if expiresAt <= currentTime then
        self.outbreakTrackedByGUID[guid] = nil
        local requestState = self.outbreakRequestedByGUID[guid]
        local requestedUntil = 0
        if type(requestState) == "table" then
            requestedUntil = tonumber(requestState.expiresAt) or 0
        else
            requestedUntil = tonumber(requestState) or 0
        end
        if requestedUntil > currentTime and isOutbreakDiseaseSpell(spellID) then
            return {
                count = 1,
                duration = OUTBREAK_REQUEST_SECONDS,
                expirationTime = requestedUntil,
                remaining = math.max(0, requestedUntil - currentTime),
                source = "player",
                provisional = true,
            }
        end

        self.outbreakRequestedByGUID[guid] = nil
        return nil
    end

    return {
        count = 1,
        duration = OUTBREAK_TRACK_SECONDS,
        expirationTime = expiresAt,
        remaining = math.max(0, expiresAt - currentTime),
        source = "player",
    }
end

function Trackers:GetDebugSnapshot(unitID, spellID)
    self:Poll()

    local snapshot = {
        sinceLastCast = getActionSpellTimeSinceLastCast(OUTBREAK_SPELL_ID),
        cooldownRemaining = getSpellCooldownRemaining(OUTBREAK_SPELL_ID),
        requestRemaining = 0,
        trackedRemaining = 0,
        observedTarget = self.lastObservedOutbreakTargetGUID,
    }

    local guid = unitGUID(unitID)
    if not guid then
        return snapshot
    end

    local requestState = self.outbreakRequestedByGUID[guid]
    if type(requestState) == "table" then
        snapshot.requestRemaining = math.max(0, (tonumber(requestState.expiresAt) or 0) - now())
    else
        snapshot.requestRemaining = math.max(0, (tonumber(requestState) or 0) - now())
    end

    local tracked = self.outbreakTrackedByGUID[guid]
    if type(tracked) == "table" then
        local trackedRemaining = tonumber(tracked[tonumber(spellID)]) or 0
        if isOutbreakDiseaseSpell(spellID) then
            for index = 1, #OUTBREAK_DISEASE_IDS do
                trackedRemaining = math.max(trackedRemaining, tonumber(tracked[OUTBREAK_DISEASE_IDS[index]]) or 0)
            end
        end
        snapshot.trackedRemaining = math.max(0, trackedRemaining - now())
    end

    return snapshot
end

addon.Trackers = Trackers
