local addonName, addon = ...

_G.SimplyMidnight = addon

addon.name = addonName
addon.version = "0.1.0"
addon.constants = {
    questionMarkIcon = 134400,
    slotOrder = { "primary", "secondary", "defensive", "interrupt", "utility" },
}

addon.defaults = {
    debug = false,
    overlay = false,
    modes = {
        conserve = false,
        pause = false,
    },
    hud = {
        locked = true,
        point = "TOPLEFT",
        relativePoint = "TOPLEFT",
        x = 16,
        y = -16,
        scale = 1,
        visible = true,
    },
    registry = {
        version = 1,
        spells = {},
    },
}

addon.db = nil
addon.session = {}
