local _, addon = ...

local Packs = {}

local packList = {
    {
        key = "deathknight-unholy",
        version = 3,
        class = "DEATHKNIGHT",
        specID = 252,
        name = "Unholy Death Knight",
        rangeHints = {
            meleeSpellID = 85948,
            shortSpellID = 77575,
        },
        entries = {
            {
                spellID = 343294,
                slot = "primary",
                priority = 150,
                conditions = {
                    inCombat = true,
                    requireTarget = true,
                    targetHostile = true,
                    targetAlive = true,
                    targetHpBelow = 35,
                },
                note = "Soul Reaper execute",
            },
            {
                spellID = 77575,
                slot = "primary",
                priority = 145,
                conditions = {
                    inCombat = true,
                    requireTarget = true,
                    targetHostile = true,
                    targetAlive = true,
                    auraMissing = {
                        unit = "target",
                        spellID = 191587,
                        filter = "HARMFUL",
                    },
                },
                note = "Apply Virulent Plague",
            },
            {
                spellID = 77575,
                slot = "primary",
                priority = 143,
                conditions = {
                    inCombat = true,
                    requireTarget = true,
                    targetHostile = true,
                    targetAlive = true,
                    auraRemainingBelow = {
                        unit = "target",
                        spellID = 191587,
                        filter = "HARMFUL",
                        seconds = 4,
                    },
                },
                note = "Refresh Virulent Plague",
            },
            {
                spellID = 43265,
                slot = "primary",
                priority = 140,
                conditions = {
                    inCombat = true,
                    requireTarget = true,
                    targetHostile = true,
                    targetAlive = true,
                    rangeBucket = "melee",
                    enemyCountAtLeast = 3,
                    cooldownReady = true,
                    modeConserve = false,
                },
                note = "AoE setup",
            },
            {
                spellID = 85948,
                slot = "primary",
                priority = 136,
                conditions = {
                    inCombat = true,
                    requireTarget = true,
                    targetHostile = true,
                    targetAlive = true,
                    rangeBucket = "melee",
                    secondaryAtLeast = 2,
                    auraMissing = {
                        unit = "target",
                        spellID = 194310,
                        filter = "HARMFUL",
                    },
                },
                note = "Build Festering Wounds",
            },
            {
                spellID = 85948,
                slot = "primary",
                priority = 134,
                conditions = {
                    inCombat = true,
                    requireTarget = true,
                    targetHostile = true,
                    targetAlive = true,
                    rangeBucket = "melee",
                    secondaryAtLeast = 2,
                    auraStacksAtMost = {
                        unit = "target",
                        spellID = 194310,
                        filter = "HARMFUL",
                        stacks = 2,
                    },
                },
                note = "Rebuild Festering Wounds",
            },
            {
                spellID = 55090,
                slot = "primary",
                priority = 132,
                conditions = {
                    inCombat = true,
                    requireTarget = true,
                    targetHostile = true,
                    targetAlive = true,
                    rangeBucket = "melee",
                    auraStacksAtLeast = {
                        unit = "target",
                        spellID = 194310,
                        filter = "HARMFUL",
                        stacks = 1,
                    },
                    secondaryAtLeast = 1,
                },
                note = "Spend Festering Wounds",
            },
            {
                spellID = 207317,
                slot = "primary",
                priority = 128,
                conditions = {
                    inCombat = true,
                    requireTarget = true,
                    targetHostile = true,
                    targetAlive = true,
                    enemyCountAtLeast = 3,
                    resourceAtLeast = 60,
                    auraPresent = {
                        unit = "target",
                        spellID = 191587,
                        filter = "HARMFUL",
                    },
                },
                note = "AoE runic spender",
            },
            {
                spellID = 47541,
                slot = "primary",
                priority = 126,
                conditions = {
                    inCombat = true,
                    requireTarget = true,
                    targetHostile = true,
                    targetAlive = true,
                    auraPresent = {
                        unit = "player",
                        spellID = 81340,
                        filter = "HELPFUL",
                    },
                },
                note = "Sudden Doom proc",
            },
            {
                spellID = 47541,
                slot = "primary",
                priority = 122,
                conditions = {
                    inCombat = true,
                    requireTarget = true,
                    targetHostile = true,
                    targetAlive = true,
                    resourceAtLeast = 80,
                },
                note = "Spend high Runic Power",
            },
            {
                spellID = 55090,
                slot = "primary",
                priority = 120,
                conditions = {
                    inCombat = true,
                    requireTarget = true,
                    targetHostile = true,
                    targetAlive = true,
                    rangeBucket = "melee",
                    secondaryAtLeast = 1,
                },
                note = "Rune spender",
            },
            {
                spellID = 47541,
                slot = "primary",
                priority = 110,
                conditions = {
                    inCombat = true,
                    requireTarget = true,
                    targetHostile = true,
                    targetAlive = true,
                    resourceAtLeast = 40,
                },
                note = "Runic filler",
            },
            {
                spellID = 42650,
                slot = "secondary",
                priority = 150,
                conditions = {
                    inCombat = true,
                    requireTarget = true,
                    targetHostile = true,
                    targetAlive = true,
                    modeBurst = true,
                    cooldownReady = true,
                    modeConserve = false,
                },
                note = "Major burst",
            },
            {
                spellID = 1233448,
                slot = "secondary",
                priority = 145,
                conditions = {
                    inCombat = true,
                    requireTarget = true,
                    targetHostile = true,
                    targetAlive = true,
                    petAlive = true,
                    cooldownReady = true,
                    modeConserve = false,
                },
                note = "Dark Transformation burst window",
            },
            {
                spellID = 43265,
                slot = "secondary",
                priority = 142,
                conditions = {
                    inCombat = true,
                    requireTarget = true,
                    targetHostile = true,
                    targetAlive = true,
                    rangeBucket = "melee",
                    enemyCountAtLeast = 3,
                    cooldownReady = true,
                    modeConserve = false,
                },
                note = "AoE support",
            },
            {
                spellID = 46584,
                slot = "secondary",
                priority = 140,
                conditions = {
                    inCombat = true,
                    requireTarget = true,
                    targetHostile = true,
                    targetAlive = true,
                    petAlive = false,
                    cooldownReady = true,
                },
                note = "Raise ghoul",
            },
            {
                spellID = 207317,
                slot = "secondary",
                priority = 130,
                conditions = {
                    inCombat = true,
                    requireTarget = true,
                    targetHostile = true,
                    targetAlive = true,
                    enemyCountAtLeast = 3,
                    resourceAtLeast = 40,
                },
                note = "AoE pressure",
            },
            {
                spellID = 47541,
                slot = "secondary",
                priority = 110,
                conditions = {
                    inCombat = true,
                    requireTarget = true,
                    targetHostile = true,
                    targetAlive = true,
                    resourceAtLeast = 60,
                },
                note = "Runic pressure",
            },
            {
                spellID = 49998,
                slot = "defensive",
                priority = 145,
                conditions = {
                    inCombat = true,
                    playerHpBelow = 70,
                    resourceAtLeast = 35,
                },
                note = "Emergency self heal",
            },
            {
                spellID = 48707,
                slot = "defensive",
                priority = 140,
                conditions = {
                    inCombat = true,
                    playerHpBelow = 55,
                },
                note = "Magic mitigation",
            },
            {
                spellID = 47528,
                slot = "interrupt",
                priority = 150,
                conditions = {
                    inCombat = true,
                    requireTarget = true,
                    targetHostile = true,
                    targetCasting = true,
                    targetInterruptible = true,
                },
                note = "Interrupt",
            },
            {
                spellID = 48265,
                slot = "utility",
                priority = 120,
                conditions = {
                    inCombat = true,
                    moving = true,
                },
                note = "Stick to target",
            },
            {
                spellID = 212552,
                slot = "utility",
                priority = 110,
                conditions = {
                    inCombat = true,
                    moving = true,
                    modeConserve = false,
                },
                note = "Mobility escape",
            },
        },
    },
    {
        key = "hunter-beastmastery",
        version = 1,
        class = "HUNTER",
        specID = 253,
        name = "Beast Mastery Hunter",
        rangeHints = {
            shortSpellID = 34026,
        },
        entries = {
            {
                spellID = 53351,
                slot = "primary",
                priority = 140,
                conditions = {
                    inCombat = true,
                    requireTarget = true,
                    targetHostile = true,
                    targetAlive = true,
                },
                note = "Kill Shot execute/proc",
            },
            {
                spellID = 217200,
                slot = "primary",
                priority = 133,
                conditions = {
                    inCombat = true,
                    requireTarget = true,
                    targetHostile = true,
                    targetAlive = true,
                    petAlive = true,
                    auraMissing = {
                        unit = "pet",
                        spellID = 272790,
                        filter = "HELPFUL",
                    },
                },
                note = "Start Frenzy",
            },
            {
                spellID = 217200,
                slot = "primary",
                priority = 132,
                conditions = {
                    inCombat = true,
                    requireTarget = true,
                    targetHostile = true,
                    targetAlive = true,
                    petAlive = true,
                    auraRemainingBelow = {
                        unit = "pet",
                        spellID = 272790,
                        filter = "HELPFUL",
                        seconds = 1.5,
                    },
                },
                note = "Refresh Frenzy",
            },
            {
                spellID = 217200,
                slot = "primary",
                priority = 130,
                conditions = {
                    inCombat = true,
                    requireTarget = true,
                    targetHostile = true,
                    targetAlive = true,
                    petAlive = true,
                    chargesAtLeast = 2,
                },
                note = "Avoid Barbed Shot cap",
            },
            {
                spellID = 2643,
                slot = "primary",
                priority = 126,
                conditions = {
                    inCombat = true,
                    requireTarget = true,
                    targetHostile = true,
                    targetAlive = true,
                    enemyCountAtLeast = 3,
                },
                note = "AoE pressure",
            },
            {
                spellID = 34026,
                slot = "primary",
                priority = 120,
                conditions = {
                    inCombat = true,
                    requireTarget = true,
                    targetHostile = true,
                    targetAlive = true,
                    petAlive = true,
                },
                note = "Kill Command core",
            },
            {
                spellID = 193455,
                slot = "primary",
                priority = 110,
                conditions = {
                    inCombat = true,
                    requireTarget = true,
                    targetHostile = true,
                    targetAlive = true,
                    resourceAtLeast = 60,
                    modeConserve = false,
                },
                note = "Focus dump",
            },
            {
                spellID = 19574,
                slot = "secondary",
                priority = 145,
                conditions = {
                    inCombat = true,
                    requireTarget = true,
                    targetHostile = true,
                    targetAlive = true,
                    petAlive = true,
                    cooldownReady = true,
                    modeConserve = false,
                },
                note = "Bestial Wrath",
            },
            {
                spellID = 217200,
                slot = "secondary",
                priority = 130,
                conditions = {
                    inCombat = true,
                    requireTarget = true,
                    targetHostile = true,
                    targetAlive = true,
                    petAlive = true,
                    auraRemainingBelow = {
                        unit = "pet",
                        spellID = 272790,
                        filter = "HELPFUL",
                        seconds = 2.5,
                    },
                },
                note = "Backup Frenzy",
            },
            {
                spellID = 2643,
                slot = "secondary",
                priority = 125,
                conditions = {
                    inCombat = true,
                    requireTarget = true,
                    targetHostile = true,
                    targetAlive = true,
                    enemyCountAtLeast = 3,
                },
                note = "AoE support",
            },
            {
                spellID = 34026,
                slot = "secondary",
                priority = 115,
                conditions = {
                    inCombat = true,
                    requireTarget = true,
                    targetHostile = true,
                    targetAlive = true,
                    petAlive = true,
                },
                note = "Fallback damage",
            },
            {
                spellID = 109304,
                slot = "defensive",
                priority = 145,
                conditions = {
                    inCombat = true,
                    playerHpBelow = 55,
                },
                note = "Self heal",
            },
            {
                spellID = 264735,
                slot = "defensive",
                priority = 140,
                conditions = {
                    inCombat = true,
                    playerHpBelow = 40,
                },
                note = "Major defensive",
            },
            {
                spellID = 147362,
                slot = "interrupt",
                priority = 150,
                conditions = {
                    inCombat = true,
                    requireTarget = true,
                    targetHostile = true,
                    targetCasting = true,
                    targetInterruptible = true,
                },
                note = "Interrupt",
            },
            {
                spellID = 5384,
                slot = "utility",
                priority = 130,
                conditions = {
                    inCombat = true,
                    playerHpBelow = 25,
                },
                note = "Panic drop",
            },
            {
                spellID = 781,
                slot = "utility",
                priority = 120,
                conditions = {
                    inCombat = true,
                    moving = true,
                    rangeBucket = "melee",
                },
                note = "Break melee",
            },
            {
                spellID = 186257,
                slot = "utility",
                priority = 110,
                conditions = {
                    inCombat = false,
                    moving = true,
                },
                note = "Travel speed",
            },
        },
    },
}

local packsByKey = {}

for _, pack in ipairs(packList) do
    packsByKey[pack.key] = pack
end

function Packs:GetByKey(key)
    return packsByKey[key]
end

function Packs:GetForSpec(specID, classTag)
    specID = tonumber(specID)
    classTag = classTag or select(2, UnitClass("player"))

    for _, pack in ipairs(packList) do
        if pack.class == classTag and pack.specID == specID then
            return pack
        end
    end
end

function Packs:GetCurrent()
    local specIndex = GetSpecialization and GetSpecialization() or nil
    local specID = specIndex and GetSpecializationInfo(specIndex) or nil
    local _, classTag = UnitClass("player")
    return self:GetForSpec(specID, classTag)
end

function Packs:GetCurrentLabel()
    local pack = self:GetCurrent()
    if pack then
        return pack.name
    end
    return "Custom / Unsupported Spec"
end

addon.Packs = Packs
