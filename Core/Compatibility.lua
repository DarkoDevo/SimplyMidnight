local _, addon = ...

local Compatibility = {
    adapters = {},
    latest = nil,
}

local function getBuildSnapshot()
    if type(GetBuildInfo) ~= "function" then
        return {
            version = "unknown",
            build = "unknown",
            interface = 0,
        }
    end

    local version, build, _, interface = GetBuildInfo()
    return {
        version = version or "unknown",
        build = build or "unknown",
        interface = interface or 0,
    }
end

local function getAPISnapshot()
    return {
        cSpell = type(C_Spell) == "table",
        spellTexture = (type(C_Spell) == "table" and type(C_Spell.GetSpellTexture) == "function") or type(GetSpellInfo) == "function",
        spellCooldown = (type(C_Spell) == "table" and type(C_Spell.GetSpellCooldown) == "function") or type(GetSpellCooldown) == "function",
        spellCharges = (type(C_Spell) == "table" and type(C_Spell.GetSpellCharges) == "function") or type(GetSpellCharges) == "function",
        spellKnowledge = type(IsSpellKnownOrOverridesKnown) == "function" or type(IsSpellKnown) == "function" or type(IsPlayerSpell) == "function",
        spellRange = type(IsSpellInRange) == "function",
        unitAura = type(UnitAura) == "function",
        nameplates = type(C_NamePlate) == "table" and type(C_NamePlate.GetNamePlates) == "function",
        unitPower = type(UnitPower) == "function" and type(UnitPowerMax) == "function",
    }
end

local function appendRisk(risks, condition, value)
    if condition then
        risks[#risks + 1] = value
    end
end

function Compatibility:RegisterAdapter(key, adapter)
    if not key or type(adapter) ~= "table" then
        return
    end

    self.adapters[key] = adapter
    self:Refresh()
end

function Compatibility:GetExportSnapshot()
    local hud = addon.db and addon.db.hud or addon.defaults.hud
    local profile = addon.OutputProfiles and addon.OutputProfiles:GetContract(hud.profile) or nil

    return {
        protocolVersion = "sm-export-v1",
        publicTable = "_G.SimplyMidnightBridge",
        profileVersion = "sm-layout-v1",
        profileKey = profile and profile.key or tostring(hud.profile or "debug_hud"),
        profileLabel = profile and profile.label or "Debug HUD",
        surfaceMode = profile and profile.surfaceMode or "pixel-hud",
        directHUD = true,
        overlayMirror = true,
        point = hud.point,
        relativePoint = hud.relativePoint,
        x = hud.x,
        y = hud.y,
        scale = hud.scale,
        visible = hud.visible ~= false,
        locked = hud.locked ~= false,
        width = profile and profile.frame and profile.frame.width or 0,
        height = profile and profile.frame and profile.frame.height or 0,
        slots = addon:GetSlotOrder(),
        transport = profile and profile.transport or nil,
        overlay = profile and profile.overlay or nil,
        availableProfiles = addon.OutputProfiles and addon.OutputProfiles:GetContracts() or {},
    }
end

function Compatibility:GetAdapterSnapshots()
    local snapshots = {}

    for key, adapter in pairs(self.adapters) do
        local snapshot = nil
        if addon.TaintGuard and addon.TaintGuard.SafeAdapterRead then
            snapshot = addon.TaintGuard:SafeAdapterRead(key, function()
                if type(adapter.GetCompatibilitySnapshot) == "function" then
                    return adapter:GetCompatibilitySnapshot()
                end
                if type(adapter.GetSnapshot) == "function" then
                    return adapter:GetSnapshot()
                end
                return {
                    provider = key,
                    loaded = true,
                }
            end)
        end

        snapshots[key] = snapshot or {
            provider = key,
            loaded = false,
            error = true,
        }
    end

    return snapshots
end

function Compatibility:BuildSnapshot()
    local build = getBuildSnapshot()
    local api = getAPISnapshot()
    local adapters = self:GetAdapterSnapshots()
    local risks = {}
    local latestTaint = addon.TaintGuard and addon.TaintGuard:GetLatestIncident() or nil

    appendRisk(risks, not api.spellTexture, "spell_texture_api_missing")
    appendRisk(risks, not api.spellCooldown, "spell_cooldown_api_missing")
    appendRisk(risks, not api.spellKnowledge, "spell_knowledge_api_missing")
    appendRisk(risks, not api.unitAura, "unit_aura_api_missing")
    appendRisk(risks, not api.unitPower, "unit_power_api_missing")
    appendRisk(risks, latestTaint ~= nil, "taint_incident_seen")

    for key, snapshot in pairs(adapters) do
        appendRisk(risks, snapshot.loaded and snapshot.compatibilityMode == "unknown", key .. "_compatibility_unknown")
    end

    return {
        protocolVersion = "sm-bridge-v1",
        addon = addon.name,
        addonVersion = addon.version,
        generatedAt = type(GetTime) == "function" and GetTime() or 0,
        wow = build,
        api = api,
        export = self:GetExportSnapshot(),
        adapters = adapters,
        negotiation = {
            mode = "capability-probed",
            reservedTargets = {
                action = true,
                ggloader = true,
                metaEngine = true,
                tmw = true,
            },
        },
        riskFlags = risks,
        latestTaint = latestTaint,
    }
end

function Compatibility:Refresh()
    self.latest = self:BuildSnapshot()
    _G.SimplyMidnightBridge = self.latest
    return self.latest
end

function Compatibility:GetSnapshot()
    return self.latest or self:Refresh()
end

function Compatibility:GetStatusLine()
    local snapshot = self:GetSnapshot()
    local riskCount = snapshot and #snapshot.riskFlags or 0

    if riskCount == 0 then
        return "compat: stable"
    end

    return string.format("compat: %d risks", riskCount)
end

function Compatibility:Initialize()
    if self.initialized then
        self:Refresh()
        return
    end

    self.initialized = true
    addon:RegisterRuntimeEvent("ADDON_LOADED", self, "OnRuntimeEvent")
    addon:RegisterRuntimeEvent("PLAYER_ENTERING_WORLD", self, "OnRuntimeEvent")
    addon:RegisterRuntimeEvent("DISPLAY_SIZE_CHANGED", self, "OnRuntimeEvent")
    self:Refresh()
end

function Compatibility:OnRuntimeEvent(event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == addon.name or arg1 == "SimplyGlad" or arg1 == "TellMeWhen" then
            self:Refresh()
        end
        return
    end

    self:Refresh()
end

addon.Compatibility = Compatibility
