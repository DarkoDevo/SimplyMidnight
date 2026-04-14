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
local primaryPowerByClass = {
    DEATHKNIGHT = Enum and Enum.PowerType and Enum.PowerType.RunicPower or 6,
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

local function spellIsInRange(spellID, unitID)
    if not spellID or not unitID or not unitExists(unitID) then
        return nil
    end

    local result
    if type(C_Spell) == "table" and type(C_Spell.IsSpellInRange) == "function" then
        result = protectedCall(C_Spell.IsSpellInRange, spellID, unitID)
    elseif type(IsSpellInRange) == "function" then
        result = protectedCall(IsSpellInRange, spellID, unitID)
    end

    if result == nil then
        return nil
    end

    if result == true or result == 1 then
        return true
    end

    if result == false or result == 0 then
        return false
    end

    return nil
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

local function preferPositiveNumber(currentValue, currentKnown, candidateValue, candidateKnown)
    if not candidateKnown then
        return currentValue, currentKnown
    end

    if not currentKnown then
        return candidateValue, true
    end

    if type(candidateValue) == "number" and candidateValue > 0 and (tonumber(currentValue) or 0) <= 0 then
        return candidateValue, true
    end

    return currentValue, currentKnown
end

local function tryActionHealth(unitID, current, max, pct, currentKnown, maxKnown, pctKnown)
    local looksAlive = unitExists(unitID) and not unitDead(unitID)

    if (not pctKnown) or (looksAlive and (pct or 0) <= 0) then
        local fallbackPct, fallbackPctKnown = addon:TryActionUnitNumber(unitID, "HealthPercent", pct or 0)
        if not fallbackPctKnown then
            fallbackPct, fallbackPctKnown = addon:TrySecretEngineNumber("GetHealthPercent", pct or 0, unitID)
        end
        if fallbackPctKnown then
            pct = math.max(0, math.min(fallbackPct or 0, 100))
            pctKnown = true
        end
    end

    if (not maxKnown) or not max or max <= 0 then
        local fallbackMax, fallbackMaxKnown = addon:TryActionUnitNumber(unitID, "HealthMax", max or 0)
        if fallbackMaxKnown and fallbackMax > 0 then
            max = fallbackMax
            maxKnown = true
        end
    end

    if (not currentKnown) or (looksAlive and (current or 0) <= 0) then
        local fallbackCurrent, fallbackCurrentKnown = addon:TryActionUnitNumber(unitID, "Health", current or 0)
        if not fallbackCurrentKnown then
            fallbackCurrent, fallbackCurrentKnown = addon:TrySecretEngineNumber("GetHealth", current or 0, unitID)
        end
        if fallbackCurrentKnown then
            current = fallbackCurrent
            currentKnown = true
        end
    end

    if currentKnown and maxKnown and max > 0 then
        pct = percentage(current, max)
        pctKnown = true
    elseif pctKnown and maxKnown and max > 0 and not currentKnown then
        current = math.floor((max * pct / 100) + 0.5)
        currentKnown = true
    elseif pctKnown and looksAlive and (not maxKnown or max <= 0) and not currentKnown then
        current = 0
    end

    if looksAlive and pctKnown and (pct or 0) <= 0 then
        pct = 100
    end

    return current or 0, max or 0, pct or 0, pctKnown, currentKnown, maxKnown
end

local function readUnitHealth(unitID)
    if not unitExists(unitID) then
        return 0, 0, 0, false, false, false
    end

    local current, currentKnown = addon:TryUntaintNumber(protectedCall(UnitHealth, unitID), 0)
    local max, maxKnown = addon:TryUntaintNumber(protectedCall(UnitHealthMax, unitID), 0)
    local pct = percentage(current, max)
    local pctKnown = currentKnown and maxKnown and max > 0
    return tryActionHealth(unitID, current, max, pct, currentKnown, maxKnown, pctKnown)
end

local function tryActionPower(unitID, powerType, current, max, pct, currentKnown, maxKnown, pctKnown, preferSecretFallback)
    local allowFallback = preferSecretFallback == true
    local preferPositiveSignal = unitID == "player" and powerType ~= nil
    local runicPowerType = (Enum and Enum.PowerType and Enum.PowerType.RunicPower or 6)
    local typedPowerSignal = currentKnown or pctKnown

    if allowFallback and ((not pctKnown) or (not currentKnown) or (not maxKnown)) then
        if unitID == "player" and powerType == runicPowerType then
            local playerCurrent, playerCurrentKnown = addon:TryActionPlayerNumber("RunicPower", current or 0)
            current, currentKnown = preferPositiveNumber(current, currentKnown, playerCurrent, playerCurrentKnown)
            typedPowerSignal = typedPowerSignal or playerCurrentKnown

            local playerMax, playerMaxKnown = addon:TryActionPlayerNumber("RunicPowerMax", max or 0)
            if playerMaxKnown and playerMax > 0 and ((not maxKnown) or (max or 0) <= 0) then
                max = playerMax
                maxKnown = true
            end

            local playerPct, playerPctKnown = addon:TryActionPlayerNumber("RunicPowerPercentage", pct or 0)
            if playerPctKnown then
                playerPct = math.max(0, math.min(playerPct or 0, 100))
                pct, pctKnown = preferPositiveNumber(pct, pctKnown, playerPct, playerPctKnown)
            end
            typedPowerSignal = typedPowerSignal or playerPctKnown

            local playerDeficit, playerDeficitKnown = addon:TryActionPlayerNumber("RunicPowerDeficit", 0)
            if playerDeficitKnown then
                if not maxKnown or (max or 0) <= 0 then
                    max = 100
                    maxKnown = true
                end

                local derivedCurrent = math.max(0, (max or 100) - math.max(0, tonumber(playerDeficit) or 0))
                current, currentKnown = preferPositiveNumber(current, currentKnown, derivedCurrent, true)
                pct, pctKnown = preferPositiveNumber(pct, pctKnown, percentage(derivedCurrent, max or 100), true)
                typedPowerSignal = true
            end

            local rawUntypedCurrent, rawUntypedCurrentKnown = addon:TryUntaintNumber(protectedCall(UnitPower, unitID), 0)
            current, currentKnown = preferPositiveNumber(current, currentKnown, rawUntypedCurrent, rawUntypedCurrentKnown)

            local rawUntypedMax, rawUntypedMaxKnown = addon:TryUntaintNumber(protectedCall(UnitPowerMax, unitID), 0)
            if rawUntypedMaxKnown and rawUntypedMax > 0 and ((not maxKnown) or (max or 0) <= 0) then
                max = rawUntypedMax
                maxKnown = true
            end

            local actionUntypedPct, actionUntypedPctKnown = addon:TryActionUnitNumber(unitID, "PowerPercent", pct or 0)
            pct, pctKnown = preferPositiveNumber(pct, pctKnown, actionUntypedPct, actionUntypedPctKnown)

            local actionUntypedCurrent, actionUntypedCurrentKnown = addon:TryActionUnitNumber(unitID, "Power", current or 0)
            current, currentKnown = preferPositiveNumber(current, currentKnown, actionUntypedCurrent, actionUntypedCurrentKnown)

            local actionUntypedMax, actionUntypedMaxKnown = addon:TryActionUnitNumber(unitID, "PowerMax", max or 0)
            if actionUntypedMaxKnown and actionUntypedMax > 0 and ((not maxKnown) or (max or 0) <= 0) then
                max = actionUntypedMax
                maxKnown = true
            end

            local actionUntypedDeficit, actionUntypedDeficitKnown = addon:TryActionUnitNumber(unitID, "PowerDeficit", 0)
            if actionUntypedDeficitKnown then
                local deficitBaseMax = (maxKnown and max and max > 0) and max or 100
                local derivedCurrent = math.max(0, deficitBaseMax - math.max(0, tonumber(actionUntypedDeficit) or 0))
                if not typedPowerSignal then
                    current = derivedCurrent
                    currentKnown = true
                    pct = percentage(derivedCurrent, deficitBaseMax)
                    pctKnown = true
                else
                    current, currentKnown = preferPositiveNumber(current, currentKnown, derivedCurrent, true)
                    pct, pctKnown = preferPositiveNumber(pct, pctKnown, percentage(derivedCurrent, deficitBaseMax), true)
                end
            end

            local actionUntypedDeficitPct, actionUntypedDeficitPctKnown = addon:TryActionUnitNumber(unitID, "PowerDeficitPercent", 0)
            if actionUntypedDeficitPctKnown then
                local derivedPct = math.max(0, math.min(100, 100 - (tonumber(actionUntypedDeficitPct) or 0)))
                if not typedPowerSignal then
                    pct = derivedPct
                    pctKnown = true
                    if maxKnown and max and max > 0 then
                        current = math.floor((max * derivedPct / 100) + 0.5)
                        currentKnown = true
                    end
                else
                    pct, pctKnown = preferPositiveNumber(pct, pctKnown, derivedPct, true)
                end
            end

            local secretUntypedPct, secretUntypedPctKnown = addon:TrySecretEngineNumber("GetPowerPercent", pct or 0, unitID)
            pct, pctKnown = preferPositiveNumber(pct, pctKnown, secretUntypedPct, secretUntypedPctKnown)

            local secretUntypedCurrent, secretUntypedCurrentKnown = addon:TrySecretEngineNumber("GetPower", current or 0, unitID)
            current, currentKnown = preferPositiveNumber(current, currentKnown, secretUntypedCurrent, secretUntypedCurrentKnown)

            local secretUntypedMax, secretUntypedMaxKnown = addon:TrySecretEngineNumber("GetPowerMax", max or 0, unitID)
            if secretUntypedMaxKnown and secretUntypedMax > 0 and ((not maxKnown) or (max or 0) <= 0) then
                max = secretUntypedMax
                maxKnown = true
            end

            if not typedPowerSignal and currentKnown and (tonumber(current) or 0) <= 0 and pctKnown and (tonumber(pct) or 0) <= 0 then
                currentKnown = false
                pctKnown = false
                current = 0
                pct = 0
            end
        else
            local fallbackPct, fallbackPctKnown = addon:TryActionUnitNumber(unitID, "PowerPercent", pct or 0, powerType)
            local secretPct, secretPctKnown = addon:TrySecretEngineNumber("GetPowerPercent", pct or 0, unitID, powerType)
            if secretPctKnown then
                fallbackPct, fallbackPctKnown = secretPct, true
            elseif fallbackPctKnown then
                fallbackPctKnown = true
            end
            if fallbackPctKnown then
                fallbackPct = math.max(0, math.min(fallbackPct or 0, 100))
                pct, pctKnown = preferPositiveNumber(pct, pctKnown, fallbackPct, fallbackPctKnown)
            end
            typedPowerSignal = typedPowerSignal or fallbackPctKnown

            local fallbackCurrent, fallbackCurrentKnown = addon:TryActionUnitNumber(unitID, "Power", current or 0, powerType)
            local secretCurrent, secretCurrentKnown = addon:TrySecretEngineNumber("GetPower", current or 0, unitID, powerType)
            if secretCurrentKnown then
                fallbackCurrent, fallbackCurrentKnown = secretCurrent, true
            elseif fallbackCurrentKnown then
                fallbackCurrentKnown = true
            end
            if fallbackCurrentKnown then
                current, currentKnown = preferPositiveNumber(current, currentKnown, fallbackCurrent, fallbackCurrentKnown)
            end
            typedPowerSignal = typedPowerSignal or fallbackCurrentKnown

            local fallbackMax, fallbackMaxKnown = addon:TryActionUnitNumber(unitID, "PowerMax", max or 0, powerType)
            local secretMax, secretMaxKnown = addon:TrySecretEngineNumber("GetPowerMax", max or 0, unitID, powerType)
            if secretMaxKnown and secretMax > 0 then
                fallbackMax, fallbackMaxKnown = secretMax, true
            end
            if fallbackMaxKnown and fallbackMax > 0 and ((not maxKnown) or (max or 0) <= 0) then
                max = fallbackMax
                maxKnown = true
            end
        end
    end

    local suspiciousZeroCurrent = preferPositiveSignal and pctKnown and (pct or 0) > 0 and (current or 0) <= 0
    if maxKnown and max > 0 and pctKnown and ((not currentKnown) or suspiciousZeroCurrent) then
        current = math.floor((max * pct / 100) + 0.5)
        currentKnown = true
        suspiciousZeroCurrent = false
    end

    if currentKnown and maxKnown and max > 0 and not suspiciousZeroCurrent then
        pct = percentage(current, max)
        pctKnown = true
    elseif pctKnown and maxKnown and max > 0 and not currentKnown then
        current = math.floor((max * pct / 100) + 0.5)
        currentKnown = true
    end

    return current or 0, max or 0, pct or 0, currentKnown, pctKnown, maxKnown
end

local function readPower(unitID, powerType)
    local prefersSecretFallback = powerType == nil or unitID == "player"
    if powerType == nil then
        powerType = addon:UntaintNumber(protectedCall(UnitPowerType, unitID), 0)
    end

    local current, currentKnown = addon:TryUntaintNumber(protectedCall(UnitPower, unitID, powerType), 0)
    local max, maxKnown = addon:TryUntaintNumber(protectedCall(UnitPowerMax, unitID, powerType), 0)
    local pct = percentage(current, max)
    local pctKnown = currentKnown and maxKnown and max > 0
    return tryActionPower(unitID, powerType, current, max, pct, currentKnown, maxKnown, pctKnown, prefersSecretFallback)
end

local function getPlayerPrimaryPowerDebug(classTag, powerType)
    if classTag ~= "DEATHKNIGHT" or powerType == nil then
        return nil
    end

    local debug = {}

    local rawTyped, rawTypedKnown = addon:TryUntaintNumber(protectedCall(UnitPower, "player", powerType), 0)
    debug.rawTyped = rawTypedKnown and rawTyped or nil

    local rawUntyped, rawUntypedKnown = addon:TryUntaintNumber(protectedCall(UnitPower, "player"), 0)
    debug.rawUntyped = rawUntypedKnown and rawUntyped or nil

    local actionPlayer, actionPlayerKnown = addon:TryActionPlayerNumber("RunicPower", 0)
    debug.actionPlayer = actionPlayerKnown and actionPlayer or nil

    local actionDeficit, actionDeficitKnown = addon:TryActionPlayerNumber("RunicPowerDeficit", 0)
    debug.actionDeficit = actionDeficitKnown and actionDeficit or nil

    local actionUnit, actionUnitKnown = addon:TryActionUnitNumber("player", "Power", 0)
    debug.actionUnit = actionUnitKnown and actionUnit or nil

    local actionUnitDeficit, actionUnitDeficitKnown = addon:TryActionUnitNumber("player", "PowerDeficit", 0)
    debug.actionUnitDeficit = actionUnitDeficitKnown and actionUnitDeficit or nil

    local secretTyped, secretTypedKnown = addon:TrySecretEngineNumber("GetPower", 0, "player", powerType)
    debug.secretTyped = secretTypedKnown and secretTyped or nil

    local secretUntyped, secretUntypedKnown = addon:TrySecretEngineNumber("GetPower", 0, "player")
    debug.secretUntyped = secretUntypedKnown and secretUntyped or nil

    return debug
end

local function readDeathKnightRunes()
    local readyRunes = -1
    local readyRunesKnown = false

    local frameworkRunes, frameworkRunesKnown = addon:TryActionPlayerNumber("Rune", -1)
    if frameworkRunesKnown then
        readyRunes = math.max(0, math.min(6, math.floor((frameworkRunes or 0) + 0.0001)))
        readyRunesKnown = true
    end

    if type(GetRuneCooldown) == "function" then
        local countedRunes = 0
        local sawRuneData = false

        for index = 1, 6 do
            local _, duration, runeReady = protectedCall(GetRuneCooldown, index)
            if duration ~= nil or runeReady ~= nil then
                sawRuneData = true
                duration = addon:UntaintNumber(duration, 0)
                if addon:NormalizeBoolean(runeReady, false) or duration <= 0 then
                    countedRunes = countedRunes + 1
                end
            end
        end

        if sawRuneData then
            if readyRunesKnown then
                readyRunes = math.max(readyRunes, countedRunes)
            else
                readyRunes = countedRunes
                readyRunesKnown = true
            end
        end
    end

    if not readyRunesKnown then
        return 0, 6, 0, false, false
    end

    return readyRunes, 6, percentage(readyRunes, 6), true, true
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

    local currentPack = addon.Registry and addon.Registry:GetCurrentPack() or nil
    local rangeHints = currentPack and currentPack.rangeHints or nil
    local meleeSpellID = rangeHints and tonumber(rangeHints.meleeSpellID) or nil
    local shortSpellID = rangeHints and tonumber(rangeHints.shortSpellID) or nil

    if meleeSpellID and spellIsInRange(meleeSpellID, "target") == true then
        return "melee"
    end

    if addon:NormalizeBoolean(protectedCall(CheckInteractDistance, "target", 3), false) then
        return "melee"
    end

    if shortSpellID and spellIsInRange(shortSpellID, "target") == true then
        return "short"
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
    local primaryType = primaryPowerByClass[classTag]
    local primaryCurrent, primaryMax, primaryPct, primaryCurrentKnown, primaryPctKnown = readPower("player", primaryType)
    local primaryDebug = getPlayerPrimaryPowerDebug(classTag, primaryType)

    local secondaryType = secondaryPowerByClass[classTag]
    local secondaryCurrent, secondaryMax, secondaryPct, secondaryCurrentKnown, secondaryPctKnown = 0, 0, 0, false, false
    if classTag == "DEATHKNIGHT" then
        secondaryCurrent, secondaryMax, secondaryPct, secondaryCurrentKnown, secondaryPctKnown = readDeathKnightRunes()
    elseif secondaryType ~= nil then
        secondaryCurrent, secondaryMax, secondaryPct, secondaryCurrentKnown, secondaryPctKnown = readPower("player", secondaryType)
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
            primaryKnown = primaryCurrentKnown,
            primaryPctKnown = primaryPctKnown,
            primaryDebug = primaryDebug,
            secondaryCurrent = secondaryCurrent,
            secondaryMax = secondaryMax,
            secondaryPct = secondaryPct,
            secondaryKnown = secondaryCurrentKnown,
            secondaryPctKnown = secondaryPctKnown,
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
