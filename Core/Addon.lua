local addonName, addon = ...

local unpackCompat = table.unpack or unpack

local function deepCopy(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for key, nested in pairs(value) do
        copy[key] = deepCopy(nested)
    end
    return copy
end

local function mergeDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then
                target[key] = {}
            end
            mergeDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
    return target
end

local function now()
    if type(GetTime) == "function" then
        return GetTime()
    end
    return 0
end

function addon:Print(message)
    print("|cff7ec8ffSimplyMidnight|r: " .. tostring(message))
end

function addon:InitializeDatabase()
    if type(_G.SimplyMidnightDB) ~= "table" then
        _G.SimplyMidnightDB = {}
    end

    self.db = mergeDefaults(_G.SimplyMidnightDB, deepCopy(self.defaults))
    _G.SimplyMidnightDB = self.db

    self.session = {
        burstUntil = 0,
        holdUntil = 0,
        conserve = self.db.modes.conserve and true or false,
        pause = self.db.modes.pause and true or false,
        debug = self.db.debug and true or false,
        overlay = self.db.overlay and true or false,
    }
end

function addon:IsTimedModeActive(modeName)
    local key = modeName .. "Until"
    return (self.session[key] or 0) > now()
end

function addon:SetTimedMode(modeName, seconds)
    seconds = tonumber(seconds) or 0
    local key = modeName .. "Until"
    self.session[key] = now() + math.max(seconds, 0)
end

function addon:SetToggleMode(modeName, value)
    self.session[modeName] = value and true or false

    if modeName == "debug" then
        self.db.debug = self.session.debug
    elseif modeName == "overlay" then
        self.db.overlay = self.session.overlay
    elseif modeName == "conserve" or modeName == "pause" then
        self.db.modes[modeName] = self.session[modeName]
    end
end

function addon:ToggleMode(modeName)
    self:SetToggleMode(modeName, not self.session[modeName])
end

function addon:GetModeFlags()
    return {
        burst = self:IsTimedModeActive("burst"),
        hold = self:IsTimedModeActive("hold"),
        conserve = self.session.conserve and true or false,
        pause = self.session.pause and true or false,
        debug = self.session.debug and true or false,
        overlay = self.session.overlay and true or false,
    }
end

function addon:GetSlotOrder()
    return self.constants.slotOrder
end

function addon:GetSpellTexture(spellID)
    if type(C_Spell) == "table" and type(C_Spell.GetSpellTexture) == "function" then
        local ok, texture = pcall(C_Spell.GetSpellTexture, spellID)
        if ok and texture then
            return texture
        end
    end

    if type(GetSpellInfo) == "function" then
        local _, _, texture = GetSpellInfo(spellID)
        return texture
    end
end

function addon:GetSpellName(spellID)
    if type(C_Spell) == "table" and type(C_Spell.GetSpellInfo) == "function" then
        local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
        if ok and type(info) == "table" then
            return info.name
        end
    end

    if type(GetSpellInfo) == "function" then
        return GetSpellInfo(spellID)
    end
end

function addon:SafeCall(moduleName, callback, ...)
    if type(callback) ~= "function" then
        return nil
    end

    local results = { pcall(callback, ...) }
    if not results[1] then
        if self.TaintGuard and self.TaintGuard.Record then
            self.TaintGuard:Record("SAFE_CALL_FAILED", {
                source = moduleName,
                message = tostring(results[2]),
            })
        end
        return nil
    end

    return unpackCompat(results, 2)
end

function addon:InitializeModules()
    if self.TaintGuard and self.TaintGuard.Initialize then
        self.TaintGuard:Initialize()
    end
    if self.Registry and self.Registry.Initialize then
        self.Registry:Initialize()
    end
    if self.State and self.State.Initialize then
        self.State:Initialize()
    end
    if self.Recommendations and self.Recommendations.Initialize then
        self.Recommendations:Initialize()
    end
    if self.ConfigUI and self.ConfigUI.Initialize then
        self.ConfigUI:Initialize()
    end
    if self.Commands and self.Commands.Initialize then
        self.Commands:Initialize()
    end
    if self.SimplyGladAdapter and self.SimplyGladAdapter.Initialize then
        self.SimplyGladAdapter:Initialize()
    end
    if self.ExportHUD and self.ExportHUD.Initialize then
        self.ExportHUD:Initialize()
        self.ExportHUD:Start()
    end
end

local bootstrapFrame = CreateFrame("Frame")
bootstrapFrame:RegisterEvent("ADDON_LOADED")
bootstrapFrame:RegisterEvent("PLAYER_LOGIN")
bootstrapFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        addon:InitializeDatabase()
    elseif event == "PLAYER_LOGIN" then
        addon:InitializeModules()
        addon:Print("Loaded v" .. addon.version)
    end
end)
