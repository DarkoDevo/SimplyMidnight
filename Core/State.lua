local _, addon = ...

local State = {
    snapshot = {},
}
local playerPowerBarCache = {
    expiresAt = 0,
    snapshot = nil,
    candidates = nil,
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

local function getFrameLabel(frame)
    if type(frame) ~= "table" then
        return nil
    end

    local name = type(frame.GetName) == "function" and frame:GetName() or nil
    if type(name) == "string" and name ~= "" then
        return name
    end

    local objectType = type(frame.GetObjectType) == "function" and frame:GetObjectType() or nil
    if type(objectType) == "string" and objectType ~= "" then
        return objectType
    end

    return "frame"
end

local function getFramePath(frame)
    if type(frame) ~= "table" then
        return nil
    end

    local segments = {}
    local current = frame
    local guard = 0
    while current and guard < 8 do
        guard = guard + 1
        segments[#segments + 1] = getFrameLabel(current)
        current = type(current.GetParent) == "function" and current:GetParent() or nil
    end

    local path = {}
    for index = #segments, 1, -1 do
        path[#path + 1] = segments[index]
    end

    return table.concat(path, ".")
end

local explicitPlayerPowerBarPaths = {
    {
        label = "PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea.ManaBar",
        segments = { "PlayerFrameContent", "PlayerFrameContentMain", "ManaBarArea", "ManaBar" },
        assumedMax = 100,
        scoreBias = 220,
    },
    {
        label = "PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.PowerBarArea.PowerBar",
        segments = { "PlayerFrameContent", "PlayerFrameContentMain", "PowerBarArea", "PowerBar" },
        assumedMax = 100,
        scoreBias = 200,
    },
    {
        label = "PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.ManaBar",
        segments = { "PlayerFrameContent", "PlayerFrameContentMain", "ManaBar" },
        assumedMax = 100,
        scoreBias = 180,
    },
    {
        label = "PlayerFrameManaBar",
        globalName = "PlayerFrameManaBar",
        assumedMax = 100,
        scoreBias = 180,
    },
    {
        label = "PlayerFrameEnergyBar",
        globalName = "PlayerFrameEnergyBar",
        assumedMax = 100,
        scoreBias = 170,
    },
}

local explicitPlayerPowerTextPaths = {
    {
        label = "PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea.ManaBar.RightText",
        segments = { "PlayerFrameContent", "PlayerFrameContentMain", "ManaBarArea", "ManaBar", "RightText" },
        assumedMax = 100,
        scoreBias = 180,
    },
    {
        label = "PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea.ManaBar.ManaBarText",
        segments = { "PlayerFrameContent", "PlayerFrameContentMain", "ManaBarArea", "ManaBar", "ManaBarText" },
        assumedMax = 100,
        scoreBias = 170,
    },
    {
        label = "PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea.ManaBar.LeftText",
        segments = { "PlayerFrameContent", "PlayerFrameContentMain", "ManaBarArea", "ManaBar", "LeftText" },
        assumedMax = 100,
        scoreBias = 160,
    },
    {
        label = "PlayerFrameManaBarText",
        globalName = "PlayerFrameManaBarText",
        assumedMax = 100,
        scoreBias = 160,
    },
    {
        label = "PlayerFrameManaBarTextRight",
        globalName = "PlayerFrameManaBarTextRight",
        assumedMax = 100,
        scoreBias = 150,
    },
    {
        label = "PlayerFrameManaBarTextLeft",
        globalName = "PlayerFrameManaBarTextLeft",
        assumedMax = 100,
        scoreBias = 140,
    },
}

local function resolveNestedFrame(root, segments)
    local current = root
    for _, segment in ipairs(segments or {}) do
        local currentType = type(current)
        if currentType ~= "table" and currentType ~= "userdata" then
            return nil
        end

        local nextValue = nil
        if currentType == "table" then
            nextValue = rawget(current, segment)
        end
        if nextValue == nil then
            nextValue = current[segment]
        end
        current = nextValue
        if current == nil then
            return nil
        end
    end

    return current
end

local function getExplicitPlayerPowerFrame(root, probe)
    if type(probe) ~= "table" then
        return nil
    end

    if type(probe.globalName) == "string" and probe.globalName ~= "" then
        return rawget(_G, probe.globalName)
    end

    return resolveNestedFrame(root, probe.segments)
end

local function getExplicitPlayerPowerText(root, probe)
    if type(probe) ~= "table" then
        return nil
    end

    if type(probe.globalName) == "string" and probe.globalName ~= "" then
        return rawget(_G, probe.globalName)
    end

    return resolveNestedFrame(root, probe.segments)
end

local function parseVisiblePowerText(text, assumedMax)
    if type(text) ~= "string" then
        return nil
    end

    local normalized = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub(",", ""):gsub("%s+", " ")
    normalized = normalized:match("^%s*(.-)%s*$")
    if not normalized or normalized == "" then
        return nil
    end

    local current, max = normalized:match("^(%d+)%s*/%s*(%d+)$")
    if current and max then
        current = tonumber(current)
        max = tonumber(max)
        if current and max and max > 0 then
            return current, max, percentage(current, max), normalized
        end
    end

    local pct = normalized:match("^(%d+)%%$")
    if pct then
        pct = tonumber(pct)
        local fallbackMax = type(assumedMax) == "number" and assumedMax > 0 and assumedMax or 100
        if pct then
            pct = math.max(0, math.min(100, pct))
            return math.floor((fallbackMax * pct / 100) + 0.5), fallbackMax, pct, normalized
        end
    end

    local plain = normalized:match("^(%d+)$")
    if plain then
        plain = tonumber(plain)
        local fallbackMax = type(assumedMax) == "number" and assumedMax > 0 and assumedMax or 100
        if plain then
            return math.max(0, plain), fallbackMax, percentage(plain, fallbackMax), normalized
        end
    end

    return nil
end

local function buildPlayerPowerTextCandidate(fontString, path, assumedMax, scoreBias)
    local fontType = type(fontString)
    if fontType ~= "table" and fontType ~= "userdata" then
        return nil
    end

    if type(fontString.GetText) ~= "function" then
        return nil
    end

    if type(fontString.IsShown) == "function" and not addon:NormalizeBoolean(protectedCall(fontString.IsShown, fontString), false) then
        return nil
    end

    local rawText = addon:NormalizeString(protectedCall(fontString.GetText, fontString))
    local current, max, pct, normalized = parseVisiblePowerText(rawText, assumedMax)
    if not current or not max or max <= 0 then
        return nil
    end

    local score = type(scoreBias) == "number" and scoreBias or 0
    local loweredPath = tostring(path or ""):lower()
    if loweredPath:find("righttext", 1, true) then
        score = score + 20
    elseif loweredPath:find("manabartext", 1, true) then
        score = score + 15
    elseif loweredPath:find("lefttext", 1, true) then
        score = score + 8
    end

    if normalized:find("/") then
        score = score + 15
    elseif normalized:find("%%") then
        score = score + 10
    else
        score = score + 5
    end

    return {
        current = current,
        max = max,
        pct = pct,
        path = path,
        score = score,
        source = "text",
        text = normalized,
    }
end

local function getPlayerPowerTextSnapshot()
    local root = rawget(_G, "PlayerFrame")
    if type(root) ~= "table" and type(root) ~= "userdata" then
        return nil, nil
    end

    local bestCandidate = nil
    local candidates = {}
    for _, probe in ipairs(explicitPlayerPowerTextPaths) do
        local fontString = getExplicitPlayerPowerText(root, probe)
        local candidate = buildPlayerPowerTextCandidate(fontString, probe.label, probe.assumedMax, probe.scoreBias)
        if candidate then
            candidates[#candidates + 1] = candidate
            if not bestCandidate or (candidate.score or -999999) > (bestCandidate.score or -999999) then
                bestCandidate = candidate
            end
        end
    end

    table.sort(candidates, function(left, right)
        return (left.score or -999999) > (right.score or -999999)
    end)

    return bestCandidate, candidates
end

local function scorePlayerPowerBarCandidate(frame, path, minValue, maxValue, value, red, green, blue)
    if maxValue <= 5 then
        return -9999
    end

    local score = 0
    path = tostring(path or "")

    if maxValue > 0 and maxValue <= 120 then
        score = score + 25
    end

    if maxValue >= 20 and maxValue <= 120 then
        score = score + 20
    end

    if value >= minValue and value <= maxValue then
        score = score + 10
    end

    if path:find("ManaBar", 1, true) or path:find("PowerBar", 1, true) or path:find("ManaBarArea", 1, true) or path:find("PowerBarArea", 1, true) then
        score = score + 80
    end

    if path:find("PlayerFrame", 1, true) then
        score = score + 20
    end

    if path:find("Health", 1, true) then
        score = score - 120
    end

    if path:find("Cast", 1, true) or path:find("Mirror", 1, true) or path:find("Alt", 1, true) then
        score = score - 40
    end

    if blue and blue > (red or 0) and blue > (green or 0) then
        score = score + 8
    end

    local width = addon:UntaintNumber(protectedCall(frame.GetWidth, frame), 0)
    if width >= 50 then
        score = score + 5
    end
    if width < 20 then
        score = score - 80
    end

    return score
end

local function buildPlayerPowerBarCandidate(frame, path, assumedMax, scoreBias)
    local frameType = type(frame)
    if frameType ~= "table" and frameType ~= "userdata" then
        return nil
    end

    local hasStatusMethods = type(frame.GetValue) == "function"
        or type(frame.GetMinMaxValues) == "function"
        or type(frame.GetStatusBarTexture) == "function"
    if not hasStatusMethods then
        return nil
    end

    if not addon:NormalizeBoolean(protectedCall(frame.IsShown, frame), false) then
        return nil
    end

    local value, valueKnown = 0, false
    if type(frame.GetValue) == "function" then
        value, valueKnown = addon:TryUntaintNumber(protectedCall(frame.GetValue, frame), 0)
    end

    local minValue, maxValue = 0, 0
    local maxValueKnown = false
    if type(frame.GetMinMaxValues) == "function" then
        minValue, maxValue = protectedCall(frame.GetMinMaxValues, frame)
        minValue, _ = addon:TryUntaintNumber(minValue, 0)
        maxValue, maxValueKnown = addon:TryUntaintNumber(maxValue, 0)
    end

    local barWidth = addon:UntaintNumber(protectedCall(frame.GetWidth, frame), 0)
    local texture = type(frame.GetStatusBarTexture) == "function" and protectedCall(frame.GetStatusBarTexture, frame) or nil
    local textureWidth = 0
    if type(texture) == "table" and type(texture.GetWidth) == "function" then
        textureWidth = addon:UntaintNumber(protectedCall(texture.GetWidth, texture), 0)
    end

    local fillPct = 0
    local fillPctKnown = false
    if barWidth > 20 and textureWidth > 0 then
        fillPct = math.max(0, math.min(100, (textureWidth / barWidth) * 100))
        fillPctKnown = true
    end

    local effectiveMax = 0
    local effectiveMaxKnown = false
    if maxValueKnown and maxValue > minValue and maxValue > 0 then
        effectiveMax = maxValue
        effectiveMaxKnown = true
    elseif type(assumedMax) == "number" and assumedMax > 0 then
        effectiveMax = assumedMax
        effectiveMaxKnown = true
    end

    local current = 0
    local currentKnown = false
    if valueKnown and effectiveMaxKnown and value >= minValue and value <= effectiveMax then
        current = value
        currentKnown = true
    elseif fillPctKnown and effectiveMaxKnown then
        current = math.floor((effectiveMax * fillPct / 100) + 0.5)
        currentKnown = true
    end

    local pct = 0
    local pctKnown = false
    if currentKnown and effectiveMaxKnown and effectiveMax > 0 then
        pct = percentage(current, effectiveMax)
        pctKnown = true
    elseif fillPctKnown then
        pct = fillPct
        pctKnown = true
    end

    if not currentKnown and not pctKnown then
        return nil
    end

    local red, green, blue = protectedCall(frame.GetStatusBarColor, frame)
    red = addon:UntaintNumber(red, 0)
    green = addon:UntaintNumber(green, 0)
    blue = addon:UntaintNumber(blue, 0)

    local scoreValue = currentKnown and current or math.floor(((effectiveMaxKnown and effectiveMax or 100) * (pctKnown and pct or 0) / 100) + 0.5)
    local scoreMax = effectiveMaxKnown and effectiveMax or 0
    local score = scorePlayerPowerBarCandidate(frame, path, minValue, scoreMax, scoreValue, red, green, blue)
    if type(scoreBias) == "number" then
        score = score + scoreBias
    end

    if fillPctKnown and not valueKnown then
        score = score + 40
    end

    if effectiveMaxKnown and not maxValueKnown then
        score = score + 25
    end

    return {
        current = current,
        max = effectiveMax,
        pct = pct,
        path = path or getFramePath(frame),
        score = score,
        source = (valueKnown and maxValueKnown and "value") or (fillPctKnown and "texture") or "mixed",
        color = {
            red = red,
            green = green,
            blue = blue,
        },
        width = barWidth,
        fillWidth = textureWidth,
    }
end

local function addPlayerPowerBarCandidate(candidates, bestSnapshot, bestScore, frame, path, assumedMax, scoreBias)
    local candidate = buildPlayerPowerBarCandidate(frame, path, assumedMax, scoreBias)
    if not candidate then
        return bestSnapshot, bestScore
    end

    candidates[#candidates + 1] = candidate
    if (candidate.score or -999999) > bestScore then
        bestSnapshot = {
            current = candidate.current,
            max = candidate.max,
            pct = candidate.pct,
            path = candidate.path,
            score = candidate.score,
            source = candidate.source,
            width = candidate.width,
            fillWidth = candidate.fillWidth,
        }
        bestScore = candidate.score or bestScore
    end

    return bestSnapshot, bestScore
end

local function scanExplicitPowerRoot(candidates, bestSnapshot, bestScore, rootFrame, label, assumedMax, scoreBias)
    local rootType = type(rootFrame)
    if rootType ~= "table" and rootType ~= "userdata" then
        return bestSnapshot, bestScore
    end

    bestSnapshot, bestScore = addPlayerPowerBarCandidate(
        candidates,
        bestSnapshot,
        bestScore,
        rootFrame,
        label,
        assumedMax,
        scoreBias
    )

    local queue = { rootFrame }
    local index = 1
    local depth = {}
    depth[rootFrame] = 0

    while queue[index] do
        local frame = queue[index]
        local frameDepth = depth[frame] or 0
        index = index + 1

        if frameDepth < 3 and type(frame.GetChildren) == "function" then
            local children = { frame:GetChildren() }
            for childIndex = 1, #children do
                local child = children[childIndex]
                if child then
                    queue[#queue + 1] = child
                    depth[child] = frameDepth + 1
                end
            end
        end

        if frame ~= rootFrame then
            local childLabel = string.format("%s.%s", tostring(label or "probe"), tostring(getFrameLabel(frame) or "?"))
            bestSnapshot, bestScore = addPlayerPowerBarCandidate(
                candidates,
                bestSnapshot,
                bestScore,
                frame,
                childLabel,
                assumedMax,
                scoreBias - (frameDepth * 10)
            )
        end
    end

    return bestSnapshot, bestScore
end

local function getPlayerPowerBarSnapshot()
    local currentTime = type(GetTime) == "function" and GetTime() or 0
    if playerPowerBarCache.snapshot and playerPowerBarCache.expiresAt > currentTime then
        return playerPowerBarCache.snapshot
    end

    playerPowerBarCache.expiresAt = currentTime + 0.2
    playerPowerBarCache.snapshot = nil
    playerPowerBarCache.candidates = nil

    local root = rawget(_G, "PlayerFrame")
    if type(root) ~= "table" then
        return nil
    end

    local queue = { root }
    local bestSnapshot = nil
    local bestScore = -999999
    local candidates = {}
    local index = 1

    for _, probe in ipairs(explicitPlayerPowerBarPaths) do
        local frame = getExplicitPlayerPowerFrame(root, probe)
        bestSnapshot, bestScore = scanExplicitPowerRoot(
            candidates,
            bestSnapshot,
            bestScore,
            frame,
            probe.label,
            probe.assumedMax,
            probe.scoreBias
        )
    end

    while queue[index] do
        local frame = queue[index]
        index = index + 1

        if type(frame.GetChildren) == "function" then
            local children = { frame:GetChildren() }
            for childIndex = 1, #children do
                queue[#queue + 1] = children[childIndex]
            end
        end

        if type(frame.GetValue) == "function" or type(frame.GetMinMaxValues) == "function" or type(frame.GetStatusBarTexture) == "function" then
            bestSnapshot, bestScore = addPlayerPowerBarCandidate(
                candidates,
                bestSnapshot,
                bestScore,
                frame,
                getFramePath(frame),
                100,
                0
            )
        end
    end

    table.sort(candidates, function(left, right)
        return (left.score or -999999) > (right.score or -999999)
    end)
    playerPowerBarCache.candidates = candidates

    if bestSnapshot and bestSnapshot.score >= 40 then
        playerPowerBarCache.snapshot = bestSnapshot
    end

    return playerPowerBarCache.snapshot
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
    local deficitPowerSignal = false

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
                local providesSignal = (tonumber(actionUntypedDeficit) or 0) < deficitBaseMax
                if providesSignal and not typedPowerSignal then
                    current = derivedCurrent
                    currentKnown = true
                    pct = percentage(derivedCurrent, deficitBaseMax)
                    pctKnown = true
                elseif providesSignal then
                    current, currentKnown = preferPositiveNumber(current, currentKnown, derivedCurrent, true)
                    pct, pctKnown = preferPositiveNumber(pct, pctKnown, percentage(derivedCurrent, deficitBaseMax), true)
                end
                deficitPowerSignal = deficitPowerSignal or providesSignal
            end

            local actionUntypedDeficitPct, actionUntypedDeficitPctKnown = addon:TryActionUnitNumber(unitID, "PowerDeficitPercent", 0)
            if actionUntypedDeficitPctKnown then
                local derivedPct = math.max(0, math.min(100, 100 - (tonumber(actionUntypedDeficitPct) or 0)))
                local providesSignal = derivedPct > 0
                if providesSignal and not typedPowerSignal then
                    pct = derivedPct
                    pctKnown = true
                    if maxKnown and max and max > 0 then
                        current = math.floor((max * derivedPct / 100) + 0.5)
                        currentKnown = true
                    end
                elseif providesSignal then
                    pct, pctKnown = preferPositiveNumber(pct, pctKnown, derivedPct, true)
                end
                deficitPowerSignal = deficitPowerSignal or providesSignal
            end

            if not typedPowerSignal and not deficitPowerSignal then
                local textSnapshot = getPlayerPowerTextSnapshot()
                if textSnapshot and textSnapshot.max and textSnapshot.max > 0 then
                    current = textSnapshot.current
                    max = textSnapshot.max
                    pct = textSnapshot.pct
                    currentKnown = true
                    maxKnown = true
                    pctKnown = true
                    typedPowerSignal = true
                end
            end

            if not typedPowerSignal and not deficitPowerSignal then
                local frameSnapshot = getPlayerPowerBarSnapshot()
                if frameSnapshot and frameSnapshot.max and frameSnapshot.max > 0 then
                    current = frameSnapshot.current
                    max = frameSnapshot.max
                    pct = frameSnapshot.pct
                    currentKnown = true
                    maxKnown = true
                    pctKnown = true
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

            if not typedPowerSignal and not deficitPowerSignal and currentKnown and (tonumber(current) or 0) <= 0 and pctKnown and (tonumber(pct) or 0) <= 0 then
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

    local frameSnapshot = getPlayerPowerBarSnapshot()
    debug.frameCurrent = frameSnapshot and frameSnapshot.current or nil
    debug.frameMax = frameSnapshot and frameSnapshot.max or nil
    debug.framePath = frameSnapshot and frameSnapshot.path or nil
    debug.frameSource = frameSnapshot and frameSnapshot.source or nil
    debug.frameWidth = frameSnapshot and frameSnapshot.width or nil
    debug.frameFillWidth = frameSnapshot and frameSnapshot.fillWidth or nil
    debug.frameCandidates = playerPowerBarCache.candidates

    local textSnapshot, textCandidates = getPlayerPowerTextSnapshot()
    debug.textCurrent = textSnapshot and textSnapshot.current or nil
    debug.textMax = textSnapshot and textSnapshot.max or nil
    debug.textPct = textSnapshot and textSnapshot.pct or nil
    debug.textPath = textSnapshot and textSnapshot.path or nil
    debug.textRaw = textSnapshot and textSnapshot.text or nil
    debug.textCandidates = textCandidates

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
