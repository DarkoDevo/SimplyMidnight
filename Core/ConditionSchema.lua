local _, addon = ...

local ConditionSchema = {}

local contentScopes = { "all", "pve", "pvp" }
local rangeBuckets = {
    { value = nil, label = "Any Range" },
    { value = "melee", label = "Melee" },
    { value = "short", label = "Short" },
    { value = "long", label = "Long" },
}

local definitions = {
    inCombat = { key = "inCombat", label = "In Combat", kind = "bool" },
    requireTarget = { key = "requireTarget", label = "Need Target", kind = "bool" },
    targetHostile = { key = "targetHostile", label = "Target Hostile", kind = "bool" },
    targetAlive = { key = "targetAlive", label = "Target Alive", kind = "bool" },
    petAlive = { key = "petAlive", label = "Pet Alive", kind = "bool" },
    moving = { key = "moving", label = "Moving", kind = "bool" },
    targetCasting = { key = "targetCasting", label = "Target Casting", kind = "bool" },
    targetInterruptible = { key = "targetInterruptible", label = "Target Interruptible", kind = "bool" },
    cooldownReady = { key = "cooldownReady", label = "Cooldown Ready", kind = "bool" },
    modeBurst = { key = "modeBurst", label = "Burst Mode", kind = "bool" },
    modeConserve = { key = "modeConserve", label = "Conserve Mode", kind = "bool" },
    modeHold = { key = "modeHold", label = "Hold Mode", kind = "bool" },
    modePause = { key = "modePause", label = "Pause Mode", kind = "bool" },
    playerHpBelow = { key = "playerHpBelow", label = "Player HP Below %", kind = "number", min = 1, max = 100 },
    playerHpAbove = { key = "playerHpAbove", label = "Player HP Above %", kind = "number", min = 1, max = 100 },
    targetHpBelow = { key = "targetHpBelow", label = "Target HP Below %", kind = "number", min = 1, max = 100 },
    targetHpAbove = { key = "targetHpAbove", label = "Target HP Above %", kind = "number", min = 1, max = 100 },
    resourceAtLeast = { key = "resourceAtLeast", label = "Primary At Least", kind = "number", min = 0, max = 100 },
    resourceAtMost = { key = "resourceAtMost", label = "Primary At Most", kind = "number", min = 0, max = 100 },
    secondaryAtLeast = { key = "secondaryAtLeast", label = "Secondary At Least", kind = "number", min = 0, max = 12 },
    secondaryAtMost = { key = "secondaryAtMost", label = "Secondary At Most", kind = "number", min = 0, max = 12 },
    enemyCountAtLeast = { key = "enemyCountAtLeast", label = "Enemies At Least", kind = "number", min = 1, max = 40 },
    enemyCountAtMost = { key = "enemyCountAtMost", label = "Enemies At Most", kind = "number", min = 1, max = 40 },
    chargesAtLeast = { key = "chargesAtLeast", label = "Charges At Least", kind = "number", min = 1, max = 5 },
    chargesAtMost = { key = "chargesAtMost", label = "Charges At Most", kind = "number", min = 1, max = 5 },
    rangeBucket = { key = "rangeBucket", label = "Range Bucket", kind = "enum", options = rangeBuckets },
}

local boolOrder = {
    "inCombat",
    "requireTarget",
    "targetHostile",
    "targetAlive",
    "petAlive",
    "moving",
    "targetCasting",
    "targetInterruptible",
    "cooldownReady",
    "modeBurst",
    "modeConserve",
    "modeHold",
    "modePause",
}

local numberOrder = {
    "playerHpBelow",
    "playerHpAbove",
    "targetHpBelow",
    "targetHpAbove",
    "resourceAtLeast",
    "resourceAtMost",
    "secondaryAtLeast",
    "secondaryAtMost",
    "enemyCountAtLeast",
    "enemyCountAtMost",
    "chargesAtLeast",
    "chargesAtMost",
}

local function cloneTable(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for key, nested in pairs(value) do
        copy[key] = cloneTable(nested)
    end
    return copy
end

function ConditionSchema:GetDefinition(key)
    return definitions[key]
end

function ConditionSchema:GetBoolOrder()
    return boolOrder
end

function ConditionSchema:GetNumberOrder()
    return numberOrder
end

function ConditionSchema:GetContentScopes()
    return contentScopes
end

function ConditionSchema:GetRangeOptions()
    return rangeBuckets
end

function ConditionSchema:NormalizeConditionValue(key, value)
    local definition = self:GetDefinition(key)
    if not definition then
        return cloneTable(value)
    end

    if definition.kind == "bool" then
        if value == nil then
            return nil
        end
        return value == true
    end

    if definition.kind == "number" then
        local numericValue = tonumber(value)
        if not numericValue then
            return nil
        end
        if definition.min then
            numericValue = math.max(definition.min, numericValue)
        end
        if definition.max then
            numericValue = math.min(definition.max, numericValue)
        end
        return numericValue
    end

    if definition.kind == "enum" then
        if value == nil or value == "" then
            return nil
        end
        value = tostring(value)
        for _, option in ipairs(definition.options or {}) do
            if option.value == value then
                return value
            end
        end
        return nil
    end

    return cloneTable(value)
end

function ConditionSchema:DescribeCondition(key, value)
    local definition = self:GetDefinition(key)
    if not definition then
        return tostring(key)
    end

    if definition.kind == "bool" then
        return definition.label .. (value and "" or " Off")
    end

    if definition.kind == "enum" then
        for _, option in ipairs(definition.options or {}) do
            if option.value == value then
                return definition.label .. ": " .. option.label
            end
        end
    end

    return string.format("%s: %s", definition.label, tostring(value))
end

function ConditionSchema:SummarizeEntry(entry)
    entry = entry or {}
    local conditions = type(entry.conditions) == "table" and entry.conditions or {}
    local summary = {
        simple = {},
        complex = {},
    }

    for _, key in ipairs(boolOrder) do
        if conditions[key] ~= nil then
            summary.simple[#summary.simple + 1] = self:DescribeCondition(key, conditions[key])
        end
    end

    for _, key in ipairs(numberOrder) do
        if conditions[key] ~= nil then
            summary.simple[#summary.simple + 1] = self:DescribeCondition(key, conditions[key])
        end
    end

    if conditions.rangeBucket ~= nil then
        summary.simple[#summary.simple + 1] = self:DescribeCondition("rangeBucket", conditions.rangeBucket)
    end

    for key in pairs(conditions) do
        if not definitions[key] then
            summary.complex[#summary.complex + 1] = tostring(key)
        end
    end

    table.sort(summary.complex)
    return summary
end

addon.ConditionSchema = ConditionSchema
