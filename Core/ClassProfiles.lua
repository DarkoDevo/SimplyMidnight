local _, addon = ...

local ClassProfiles = {}

local PowerType = Enum and Enum.PowerType or {}

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

local function mergeTables(base, override)
    local merged = cloneTable(base or {})
    for key, value in pairs(override or {}) do
        if type(value) == "table" and type(merged[key]) == "table" then
            merged[key] = mergeTables(merged[key], value)
        else
            merged[key] = cloneTable(value)
        end
    end
    return merged
end

local function resource(powerType, key, label, shortLabel, reader)
    return {
        powerType = powerType,
        key = key,
        label = label,
        shortLabel = shortLabel or label,
        reader = reader or "power",
    }
end

local function buildProfile(id, options)
    options = options or {}
    return {
        id = id,
        class = options.class,
        name = options.name or id,
        rangeStyle = options.rangeStyle or "mixed",
        petClass = options.petClass == true,
        primary = cloneTable(options.primary),
        secondary = cloneTable(options.secondary),
    }
end

local classProfiles = {
    DEATHKNIGHT = buildProfile("deathknight", {
        class = "DEATHKNIGHT",
        name = "Death Knight",
        rangeStyle = "melee",
        petClass = true,
        primary = resource(PowerType.RunicPower or 6, "runic_power", "Runic Power", "RP"),
        secondary = resource(PowerType.Runes or 5, "runes", "Runes", "Runes", "deathknight_runes"),
    }),
    HUNTER = buildProfile("hunter", {
        class = "HUNTER",
        name = "Hunter",
        rangeStyle = "ranged",
        petClass = true,
        primary = resource(PowerType.Focus or 2, "focus", "Focus", "Focus"),
    }),
    ROGUE = buildProfile("rogue", {
        class = "ROGUE",
        name = "Rogue",
        rangeStyle = "melee",
        primary = resource(PowerType.Energy or 3, "energy", "Energy", "Energy"),
        secondary = resource(PowerType.ComboPoints or 4, "combo_points", "Combo Points", "CP"),
    }),
    DRUID = buildProfile("druid", {
        class = "DRUID",
        name = "Druid",
        rangeStyle = "mixed",
        primary = resource(PowerType.Mana or 0, "mana", "Mana", "Mana"),
    }),
    MONK = buildProfile("monk", {
        class = "MONK",
        name = "Monk",
        rangeStyle = "melee",
        primary = resource(PowerType.Energy or 3, "energy", "Energy", "Energy"),
        secondary = resource(PowerType.Chi or 12, "chi", "Chi", "Chi"),
    }),
    PALADIN = buildProfile("paladin", {
        class = "PALADIN",
        name = "Paladin",
        rangeStyle = "melee",
        primary = resource(PowerType.HolyPower or 9, "holy_power", "Holy Power", "HP"),
        secondary = resource(PowerType.Mana or 0, "mana", "Mana", "Mana"),
    }),
    WARRIOR = buildProfile("warrior", {
        class = "WARRIOR",
        name = "Warrior",
        rangeStyle = "melee",
        primary = resource(PowerType.Rage or 1, "rage", "Rage", "Rage"),
    }),
    DEMONHUNTER = buildProfile("demonhunter", {
        class = "DEMONHUNTER",
        name = "Demon Hunter",
        rangeStyle = "melee",
        primary = resource(PowerType.Fury or 17, "fury", "Fury", "Fury"),
    }),
    PRIEST = buildProfile("priest", {
        class = "PRIEST",
        name = "Priest",
        rangeStyle = "ranged",
        primary = resource(PowerType.Mana or 0, "mana", "Mana", "Mana"),
    }),
    MAGE = buildProfile("mage", {
        class = "MAGE",
        name = "Mage",
        rangeStyle = "ranged",
        primary = resource(PowerType.Mana or 0, "mana", "Mana", "Mana"),
        secondary = resource(PowerType.ArcaneCharges or 16, "arcane_charges", "Arcane Charges", "Charges"),
    }),
    WARLOCK = buildProfile("warlock", {
        class = "WARLOCK",
        name = "Warlock",
        rangeStyle = "ranged",
        primary = resource(PowerType.SoulShards or 7, "soul_shards", "Soul Shards", "Shards"),
        secondary = resource(PowerType.Mana or 0, "mana", "Mana", "Mana"),
    }),
    EVOKER = buildProfile("evoker", {
        class = "EVOKER",
        name = "Evoker",
        rangeStyle = "ranged",
        primary = resource(PowerType.Essence or 19, "essence", "Essence", "Essence"),
        secondary = resource(PowerType.Mana or 0, "mana", "Mana", "Mana"),
    }),
}

local specOverrides = {
    [252] = buildProfile("deathknight-unholy", {
        class = "DEATHKNIGHT",
        name = "Unholy Death Knight",
        rangeStyle = "melee",
        petClass = true,
        primary = mergeTables(resource(PowerType.RunicPower or 6, "runic_power", "Runic Power", "RP"), {
            estimate = {
                id = "deathknight_runic_power",
                max = 100,
                defaultCurrent = 0,
                resetOutOfCombat = true,
                seedFromSecondaryGap = true,
                generationPerSecondarySpend = 10,
                spenderSpells = {
                    [47541] = { cost = 40, freeBuffSpellID = 81340 },
                    [207317] = { cost = 30 },
                    [49998] = { cost = 35 },
                },
            },
        }),
        secondary = resource(PowerType.Runes or 5, "runes", "Runes", "Runes", "deathknight_runes"),
    }),
    [253] = buildProfile("hunter-beastmastery", {
        class = "HUNTER",
        name = "Beast Mastery Hunter",
        rangeStyle = "ranged",
        petClass = true,
        primary = resource(PowerType.Focus or 2, "focus", "Focus", "Focus"),
    }),
    [102] = buildProfile("druid-balance", {
        class = "DRUID",
        name = "Balance Druid",
        rangeStyle = "ranged",
        primary = resource(PowerType.LunarPower or 8, "astral_power", "Astral Power", "AP"),
    }),
    [103] = buildProfile("druid-feral", {
        class = "DRUID",
        name = "Feral Druid",
        rangeStyle = "melee",
        primary = resource(PowerType.Energy or 3, "energy", "Energy", "Energy"),
        secondary = resource(PowerType.ComboPoints or 4, "combo_points", "Combo Points", "CP"),
    }),
    [104] = buildProfile("druid-guardian", {
        class = "DRUID",
        name = "Guardian Druid",
        rangeStyle = "melee",
        primary = resource(PowerType.Rage or 1, "rage", "Rage", "Rage"),
    }),
    [70] = buildProfile("paladin-retribution", {
        class = "PALADIN",
        name = "Retribution Paladin",
        rangeStyle = "melee",
        primary = resource(PowerType.HolyPower or 9, "holy_power", "Holy Power", "HP"),
        secondary = resource(PowerType.Mana or 0, "mana", "Mana", "Mana"),
    }),
    [66] = buildProfile("paladin-protection", {
        class = "PALADIN",
        name = "Protection Paladin",
        rangeStyle = "melee",
        primary = resource(PowerType.HolyPower or 9, "holy_power", "Holy Power", "HP"),
        secondary = resource(PowerType.Mana or 0, "mana", "Mana", "Mana"),
    }),
    [258] = buildProfile("priest-shadow", {
        class = "PRIEST",
        name = "Shadow Priest",
        rangeStyle = "ranged",
        primary = resource(PowerType.Insanity or 13, "insanity", "Insanity", "Ins"),
    }),
}

local fallbackProfile = buildProfile("unknown", {
    name = "Unknown",
    rangeStyle = "mixed",
    primary = resource(nil, "primary", "Primary", "PWR"),
    secondary = resource(nil, "secondary", "Secondary", "SEC"),
})

function ClassProfiles:Get(classTag, specID)
    classTag = tostring(classTag or ""):upper()
    specID = tonumber(specID)

    local base = classProfiles[classTag] or fallbackProfile
    local override = specID and specOverrides[specID] or nil
    local profile = mergeTables(base, override)
    profile.class = profile.class or classTag
    profile.specID = specID
    return profile
end

addon.ClassProfiles = ClassProfiles
