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

function Trackers:Initialize()
    if self.initialized then
        return
    end

    self.initialized = true
    addon:RegisterRuntimeEvent("PLAYER_ENTERING_WORLD", self, "OnRuntimeEvent")
    addon:RegisterRuntimeEvent("UNIT_SPELLCAST_SUCCEEDED", self, "OnRuntimeEvent")
    addon:RegisterRuntimeEvent("COMBAT_LOG_EVENT_UNFILTERED", self, "OnRuntimeEvent")
end

function Trackers:OnRuntimeEvent(event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        self.outbreakTrackedByGUID = {}
        self.outbreakRequestedByGUID = {}
        return
    end

    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unitID, _, spellID = ...
        spellID = addon:UntaintNumber(spellID, 0)
        if unitID == "player" and spellID == OUTBREAK_SPELL_ID then
            self:RememberOutbreakRequestForUnit("target", OUTBREAK_REQUEST_SECONDS)
            self:RememberOutbreakForUnit("target", OUTBREAK_TRACK_SECONDS)
        end
        return
    end

    local _, subevent, _, sourceGUID, _, _, _, destGUID, _, _, _, spellID = CombatLogGetCurrentEventInfo()
    sourceGUID = addon:NormalizeString(sourceGUID)
    destGUID = addon:NormalizeString(destGUID)
    spellID = addon:UntaintNumber(spellID, 0)
    if not sourceGUID or not destGUID or spellID <= 0 then
        return
    end

    local playerGUID = unitGUID("player")
    if not playerGUID or sourceGUID ~= playerGUID then
        return
    end

    if spellID == OUTBREAK_SPELL_ID and subevent == "SPELL_CAST_SUCCESS" then
        self:RememberOutbreakRequestForGUID(destGUID, OUTBREAK_REQUEST_SECONDS)
        self:RememberOutbreakForGUID(destGUID, OUTBREAK_TRACK_SECONDS)
        return
    end

    if not isOutbreakDiseaseSpell(spellID) then
        return
    end

    if subevent == "SPELL_AURA_APPLIED" or subevent == "SPELL_AURA_REFRESH" or subevent == "SPELL_AURA_APPLIED_DOSE" then
        self:RememberSpellForGUID(destGUID, spellID, OUTBREAK_TRACK_SECONDS)
    elseif subevent == "SPELL_AURA_REMOVED" then
        self:ForgetSpellForGUID(destGUID, spellID)
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

    self.outbreakRequestedByGUID[guid] = now() + durationSeconds
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

function Trackers:GetTrackedAura(unitID, spellID, filter, sourceUnit)
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
        local requestedUntil = self.outbreakRequestedByGUID[guid] or 0
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
