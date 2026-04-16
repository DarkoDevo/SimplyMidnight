local _, addon = ...

local OutputProfiles = {
    order = {
        "debug_hud",
        "ggl_legacy_5slot",
        "overlay_compact",
    },
    profiles = {},
}

OutputProfiles.profiles.debug_hud = {
    key = "debug_hud",
    label = "Debug HUD",
    shortLabel = "Debug",
    surfaceMode = "pixel-hud",
    description = "Full in-game HUD with slot labels, state cells, and resource bars for live debugging.",
    transport = {
        legacyGGL = false,
        tmwCompat = false,
        mirrorFriendly = true,
    },
    frame = {
        width = 390,
        height = 132,
    },
    signature = {
        size = 8,
        x = 4,
        y = -4,
        gap = 2,
    },
    heartbeat = {
        size = 10,
        x = -6,
        y = -6,
    },
    icons = {
        size = 42,
        startX = 10,
        startY = 20,
        stepX = 48,
        checksumSize = 8,
        checksumInsetX = -2,
        checksumInsetY = 2,
        showLabels = true,
    },
    stateCells = {
        visible = true,
        startX = 268,
        startY = 28,
        stepX = 14,
        size = 10,
        labelOffsetY = -2,
        order = { "burst", "conserve", "hold", "pause", "target", "range", "cast", "overlay" },
    },
    bars = {
        visible = true,
        labelX = 10,
        fillX = 70,
        topY = -78,
        gapY = -18,
        width = 180,
        height = 12,
        fillInset = 2,
        fillHeight = 8,
        showLabels = true,
    },
    debugPanel = {
        width = 472,
        height = 156,
        yOffset = -6,
    },
    overlay = {
        cropWidth = 390,
        cropHeight = 132,
        defaultScale = 2,
    },
}

OutputProfiles.profiles.ggl_legacy_5slot = {
    key = "ggl_legacy_5slot",
    label = "GGL Legacy 5 Slot",
    shortLabel = "GGL Legacy",
    surfaceMode = "legacy-icon-strip",
    description = "Five-slot icon strip sized for legacy GGLoader-style icon reading with minimal extra noise.",
    transport = {
        legacyGGL = true,
        tmwCompat = true,
        mirrorFriendly = true,
    },
    frame = {
        width = 288,
        height = 56,
    },
    signature = {
        size = 6,
        x = 4,
        y = -4,
        gap = 2,
    },
    heartbeat = {
        size = 8,
        x = -4,
        y = -4,
    },
    icons = {
        size = 40,
        startX = 8,
        startY = 8,
        stepX = 45,
        checksumSize = 6,
        checksumInsetX = -2,
        checksumInsetY = 2,
        showLabels = false,
    },
    stateCells = {
        visible = false,
        order = {},
    },
    bars = {
        visible = false,
    },
    debugPanel = {
        width = 472,
        height = 156,
        yOffset = -6,
    },
    overlay = {
        cropWidth = 288,
        cropHeight = 56,
        defaultScale = 3,
    },
}

OutputProfiles.profiles.overlay_compact = {
    key = "overlay_compact",
    label = "Overlay Compact",
    shortLabel = "Compact",
    surfaceMode = "compact-overlay",
    description = "Compact icon-and-bar surface for the external overlay when GGLoader needs more than five icons.",
    transport = {
        legacyGGL = false,
        tmwCompat = false,
        mirrorFriendly = true,
    },
    frame = {
        width = 256,
        height = 92,
    },
    signature = {
        size = 6,
        x = 4,
        y = -4,
        gap = 2,
    },
    heartbeat = {
        size = 8,
        x = -4,
        y = -4,
    },
    icons = {
        size = 32,
        startX = 8,
        startY = 8,
        stepX = 36,
        checksumSize = 6,
        checksumInsetX = -2,
        checksumInsetY = 2,
        showLabels = false,
    },
    stateCells = {
        visible = true,
        startX = 192,
        startY = 12,
        stepX = 10,
        size = 8,
        labelOffsetY = -1,
        order = { "burst", "conserve", "pause", "target", "range", "cast" },
    },
    bars = {
        visible = true,
        labelX = 8,
        fillX = 36,
        topY = -48,
        gapY = -13,
        width = 206,
        height = 9,
        fillInset = 1,
        fillHeight = 5,
        showLabels = true,
    },
    debugPanel = {
        width = 472,
        height = 156,
        yOffset = -6,
    },
    overlay = {
        cropWidth = 256,
        cropHeight = 92,
        defaultScale = 2.5,
    },
}

function OutputProfiles:GetDefaultKey()
    return "debug_hud"
end

function OutputProfiles:IsValid(key)
    return type(key) == "string" and self.profiles[key] ~= nil
end

function OutputProfiles:MatchKey(key)
    key = tostring(key or ""):lower()
    if self.profiles[key] then
        return key
    end

    for _, profileKey in ipairs(self.order) do
        local profile = self.profiles[profileKey]
        if profile then
            local shortLabel = tostring(profile.shortLabel or ""):lower():gsub("%s+", "_")
            local label = tostring(profile.label or ""):lower():gsub("%s+", "_")
            if key == shortLabel or key == label then
                return profileKey
            end
        end
    end

    return nil
end

function OutputProfiles:NormalizeKey(key)
    local matched = self:MatchKey(key)
    if matched then
        return matched
    end

    return self:GetDefaultKey()
end

function OutputProfiles:Get(key)
    return self.profiles[self:NormalizeKey(key)]
end

function OutputProfiles:GetActiveKey()
    local stored = addon.db and addon.db.hud and addon.db.hud.profile or nil
    return self:NormalizeKey(stored)
end

function OutputProfiles:GetActive()
    return self:Get(self:GetActiveKey())
end

function OutputProfiles:GetKeys()
    local keys = {}
    for _, key in ipairs(self.order) do
        keys[#keys + 1] = key
    end
    return keys
end

function OutputProfiles:GetNextKey(currentKey)
    currentKey = self:NormalizeKey(currentKey)
    for index, key in ipairs(self.order) do
        if key == currentKey then
            return self.order[index + 1] or self.order[1]
        end
    end
    return self:GetDefaultKey()
end

function OutputProfiles:GetContract(key)
    local profile = self:Get(key)
    return {
        key = profile.key,
        label = profile.label,
        shortLabel = profile.shortLabel,
        description = profile.description,
        surfaceMode = profile.surfaceMode,
        transport = {
            legacyGGL = profile.transport and profile.transport.legacyGGL or false,
            tmwCompat = profile.transport and profile.transport.tmwCompat or false,
            mirrorFriendly = profile.transport and profile.transport.mirrorFriendly or false,
        },
        frame = {
            width = profile.frame and profile.frame.width or 0,
            height = profile.frame and profile.frame.height or 0,
        },
        overlay = {
            cropWidth = profile.overlay and profile.overlay.cropWidth or 0,
            cropHeight = profile.overlay and profile.overlay.cropHeight or 0,
            defaultScale = profile.overlay and profile.overlay.defaultScale or 1,
        },
    }
end

function OutputProfiles:GetContracts()
    local contracts = {}
    for _, key in ipairs(self.order) do
        contracts[#contracts + 1] = self:GetContract(key)
    end
    return contracts
end

addon.OutputProfiles = OutputProfiles
