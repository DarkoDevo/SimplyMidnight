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

local function getVisibleEnemyCount()
    local count = 0

    if type(C_NamePlate) == "table" and type(C_NamePlate.GetNamePlates) == "function" then
        local nameplates = C_NamePlate.GetNamePlates(false) or {}
        for _, plate in ipairs(nameplates) do
            local unitID = plate and plate.namePlateUnitToken
            if unitID and UnitExists(unitID) and not UnitIsDead(unitID) and UnitCanAttack("player", unitID) then
                count = count + 1
            end
        end
    end

    if count == 0 and UnitExists("target") and not UnitIsDead("target") and UnitCanAttack("player", "target") then
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
    local current = UnitHealth(unitID) or 0
    local max = UnitHealthMax(unitID) or 0
    return current, max, percentage(current, max)
end

local function readPower(unitID, powerType)
    if powerType == nil then
        powerType = UnitPowerType(unitID)
    end

    local current = UnitPower(unitID, powerType) or 0
    local max = UnitPowerMax(unitID, powerType) or 0
    return current, max, percentage(current, max)
end

local function getMode()
    local inInstance, instanceType = IsInInstance()
    if inInstance then
        if instanceType == "arena" or instanceType == "pvp" then
            return "pvp"
        end
        return "pve"
    end

    if UnitIsPVP("player") then
        return "pvp"
    end

    return "pve"
end

local function getRangeBucket()
    if not UnitExists("target") then
        return "none"
    end

    if CheckInteractDistance("target", 3) then
        return "melee"
    end

    if CheckInteractDistance("target", 4) then
        return "short"
    end

    return "long"
end

local function getTargetCastingInfo()
    local castName, _, _, _, endTimeMS, _, _, notInterruptible = UnitCastingInfo("target")
    if castName then
        return {
            active = true,
            interruptible = not notInterruptible,
            name = castName,
            remainingMS = math.max((endTimeMS or 0) - (GetTime() * 1000), 0),
        }
    end

    local channelName, _, _, _, endTimeChannelMS, _, notInterruptibleChannel = UnitChannelInfo("target")
    if channelName then
        return {
            active = true,
            interruptible = not notInterruptibleChannel,
            name = channelName,
            remainingMS = math.max((endTimeChannelMS or 0) - (GetTime() * 1000), 0),
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
    local _, classTag = UnitClass("player")
    local flags = addon:GetModeFlags()

    local playerCurrent, playerMax, playerPct = readUnitHealth("player")
    local _, _, targetPct = readUnitHealth("target")
    local primaryCurrent, primaryMax, primaryPct = readPower("player")

    local secondaryType = secondaryPowerByClass[classTag]
    local secondaryCurrent, secondaryMax, secondaryPct = 0, 0, 0
    if secondaryType ~= nil then
        secondaryCurrent, secondaryMax, secondaryPct = readPower("player", secondaryType)
    end

    local targetExists = UnitExists("target")
    local targetAlive = targetExists and not UnitIsDead("target")
    local targetHostile = targetExists and UnitCanAttack("player", "target") or false
    local petExists = UnitExists("pet")
    local petAlive = petExists and not UnitIsDead("pet")
    local rangeBucket = getRangeBucket()
    local castInfo = getTargetCastingInfo()
    local specIndex = GetSpecialization and GetSpecialization() or nil
    local specID = specIndex and GetSpecializationInfo(specIndex) or nil
    local enemyCount = getVisibleEnemyCount()

    self.snapshot = {
        updatedAt = GetTime(),
        mode = getMode(),
        player = {
            class = classTag,
            specID = specID,
            inCombat = UnitAffectingCombat("player") or InCombatLockdown(),
            moving = GetUnitSpeed("player") > 0,
            mounted = IsMounted(),
            currentHealth = playerCurrent,
            maxHealth = playerMax,
            healthPct = playerPct,
            primaryCurrent = primaryCurrent,
            primaryMax = primaryMax,
            primaryPct = primaryPct,
            secondaryCurrent = secondaryCurrent,
            secondaryMax = secondaryMax,
            secondaryPct = secondaryPct,
            petExists = petExists,
            petAlive = petAlive,
        },
        target = {
            exists = targetExists,
            alive = targetAlive,
            hostile = targetHostile,
            healthPct = targetPct,
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
