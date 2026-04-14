local _, addon = ...

local Trackers = {
    outbreakTrackedByGUID = {},
    outbreakRequestedByGUID = {},
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

addon.Trackers = Trackers
