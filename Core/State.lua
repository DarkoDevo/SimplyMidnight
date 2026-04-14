local _, addon = ...

local State = {
    snapshot = {},
}

local secondaryPowerByClass = {
    DEATHKNIGHT = Enum and Enum.PowerType and Enum.PowerType.Runes or 5,
    ROGUE = Enum and Enum.PowerType and Enum.PowerType.ComboPoints or 4,
    DRUID = Enum and Enum.PowerType and Enum.PowerType.ComboPoints or 4,
    MONK = Enum and Enum.PowerType and Enum.PowerType.Chi or 12,
    PALADIN = Enum and Enum.PowerType and Enum.PowerType.HolyPower or 9,
    WARLOCK = Enum and Enum.PowerType and Enum.PowerType.SoulShards or 7,
    EVOKER = Enum and Enum.PowerType and Enum.PowerType.Essence or 19,
    MAGE = Enum and Enum.PowerType and Enum.PowerType.ArcaneCharges or 16,
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

local function unitDead(unitID)
    return addon:NormalizeBoolean(protectedCall(UnitIsDead, unitID), false)
end

local function unitCanAttack(leftUnitID, rightUnitID)
    return addon:NormalizeBoolean(protectedCall(UnitCanAttack, leftUnitID, rightUnitID), false)
end

local function getVisibleEnemyCount()
    local count = 0

    if type(C_NamePlate) == "table" and type(C_NamePlate.GetNamePlates) == "function" then
        local nameplates = protectedCall(C_NamePlate.GetNamePlates, false) or {}
        for _, plate in ipairs(nameplates) do
            local unitID = addon:NormalizeString(plate and plate.namePlateUnitToken)
            if unitID and unitExists(unitID) and not unitDead(unitID) and unitCanAttack("player", unitID) then
                count = count + 1
            end
        end
    end

    if count == 0 and unitExists("target") and not unitDead("target") and unitCanAttack("player", "target") then
        count = 1
    end

    return count
end

local function percentage(current, max)
    if not current or not max or max <= 0 then
        return 0
    end
    return math.max(0, math.min(100, (current / max) * 100))
end

local function readUnitHealth(unitID)
    local current, currentKnown = addon:TryUntaintNumber(protectedCall(UnitHealth, unitID), 0)
    local max, maxKnown = addon:TryUntaintNumber(protectedCall(UnitHealthMax, unitID), 0)
    return current, max, percentage(current, max), currentKnown and maxKnown and max > 0
end

local function readPower(unitID, powerType)
    if powerType == nil then
        powerType = addon:UntaintNumber(protectedCall(UnitPowerType, unitID), 0)
    end

    local current, currentKnown = addon:TryUntaintNumber(protectedCall(UnitPower, unitID, powerType), 0)
    local max, maxKnown = addon:TryUntaintNumber(protectedCall(UnitPowerMax, unitID, powerType), 0)
    return current, max, percentage(current, max), currentKnown and maxKnown and max > 0
end

local function getMode()
    local inInstance, instanceType = protectedCall(IsInInstance)
    inInstance = addon:NormalizeBoolean(inInstance, false)
    instanceType = addon:NormalizeString(instanceType)
    if inInstance then
        if instanceType == "arena" or instanceType == "pvp" then
            return "pvp"
        end
        return "pve"
    end

    if addon:NormalizeBoolean(protectedCall(UnitIsPVP, "player"), false) then
        return "pvp"
    end

    return "pve"
end

local function getRangeBucket()
    if not unitExists("target") then
        return "none"
    end

    if addon:NormalizeBoolean(protectedCall(CheckInteractDistance, "target", 3), false) then
        return "melee"
    end

    if addon:NormalizeBoolean(protectedCall(CheckInteractDistance, "target", 4), false) then
        return "short"
    end

    return "long"
end

local function getTargetCastingInfo()
    local castName, _, _, _, endTimeMS, _, _, notInterruptible = protectedCall(UnitCastingInfo, "target")
    if castName ~= nil then
        return {
            active = true,
            interruptible = addon:NormalizeBoolean(notInterruptible, true) == false,
            name = addon:NormalizeString(castName),
            remainingMS = math.max(addon:UntaintNumber(endTimeMS, 0) - (GetTime() * 1000), 0),
        }
    end

    local channelName, _, _, _, endTimeChannelMS, _, notInterruptibleChannel = protectedCall(UnitChannelInfo, "target")
    if channelName ~= nil then
        return {
            active = true,
            interruptible = addon:NormalizeBoolean(notInterruptibleChannel, true) == false,
            name = addon:NormalizeString(channelName),
            remainingMS = math.max(addon:UntaintNumber(endTimeChannelMS, 0) - (GetTime() * 1000), 0),
        }
    end

    return {
        active = false,
        interruptible = false,
        name = nil,
        remainingMS = 0,
    }
end

function State:Initialize()
    self.snapshot = {}
end

function State:Refresh()
    local _, classTag = protectedCall(UnitClass, "player")
    classTag = addon:NormalizeString(classTag)
    local flags = addon:GetModeFlags()

    local playerCurrent, playerMax, playerPct, playerHealthKnown = readUnitHealth("player")
    local _, _, targetPct, targetHealthKnown = readUnitHealth("target")
    local primaryCurrent, primaryMax, primaryPct, primaryKnown = readPower("player")

    local secondaryType = secondaryPowerByClass[classTag]
    local secondaryCurrent, secondaryMax, secondaryPct, secondaryKnown = 0, 0, 0, false
    if secondaryType ~= nil then
        secondaryCurrent, secondaryMax, secondaryPct, secondaryKnown = readPower("player", secondaryType)
    end

    local targetExists = unitExists("target")
    local targetAlive = targetExists and not unitDead("target")
    local targetHostile = targetExists and unitCanAttack("player", "target") or false
    local petExists = unitExists("pet")
    local petAlive = petExists and not unitDead("pet")
    local rangeBucket = getRangeBucket()
    local castInfo = getTargetCastingInfo()
    local specIndex = type(GetSpecialization) == "function" and addon:UntaintNumber(protectedCall(GetSpecialization), 0) or 0
    local specID = specIndex > 0 and addon:UntaintNumber(protectedCall(GetSpecializationInfo, specIndex), 0) or nil
    local enemyCount = getVisibleEnemyCount()
    local moving = addon:UntaintNumber(protectedCall(GetUnitSpeed, "player"), 0) > 0
    local mounted = addon:NormalizeBoolean(protectedCall(IsMounted), false)
    local inCombat = addon:NormalizeBoolean(protectedCall(UnitAffectingCombat, "player"), false)
        or addon:NormalizeBoolean(protectedCall(InCombatLockdown), false)

    self.snapshot = {
        updatedAt = GetTime(),
        mode = getMode(),
        player = {
            class = classTag,
            specID = specID,
            inCombat = inCombat,
            moving = moving,
            mounted = mounted,
            currentHealth = playerCurrent,
            maxHealth = playerMax,
            healthPct = playerPct,
            healthKnown = playerHealthKnown,
            primaryCurrent = primaryCurrent,
            primaryMax = primaryMax,
            primaryPct = primaryPct,
            primaryKnown = primaryKnown,
            secondaryCurrent = secondaryCurrent,
            secondaryMax = secondaryMax,
            secondaryPct = secondaryPct,
            secondaryKnown = secondaryKnown,
            petExists = petExists,
            petAlive = petAlive,
        },
        target = {
            exists = targetExists,
            alive = targetAlive,
            hostile = targetHostile,
            healthPct = targetPct,
            healthKnown = targetHealthKnown,
            rangeBucket = rangeBucket,
            inMelee = rangeBucket == "melee",
            inShortRange = rangeBucket == "short" or rangeBucket == "melee",
            casting = castInfo.active,
            interruptible = castInfo.interruptible,
            castName = castInfo.name,
            castRemainingMS = castInfo.remainingMS,
        },
        environment = {
            enemyCount = enemyCount,
        },
        modes = flags,
    }

    return self.snapshot
end

addon.State = State
