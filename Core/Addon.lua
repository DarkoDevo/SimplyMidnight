local addonName, addon = ...

local unpackCompat = table.unpack or unpack
local bootstrapFrame
local runtimeEventListeners = {}
local dispatchRuntimeEvent

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

-- Centralize Midnight secret-value handling so every module can read game state
-- through the same compatibility path when Blizzard or Action changes behavior.
function addon:GetCompatLayer()
    local action = rawget(_G, "Action")
    if type(action) ~= "table" then
        local secretEngine = rawget(_G, "ActionSecretEngine")
        if type(secretEngine) == "table" then
            return secretEngine
        end
        return nil
    end

    if type(action.Compat) == "table" then
        return action.Compat
    end

    if type(action.SecretEngine) == "table" and type(action.SecretEngine.Compat) == "table" then
        return action.SecretEngine.Compat
    end

    local secretEngine = rawget(_G, "ActionSecretEngine")
    if type(secretEngine) == "table" then
        return secretEngine
    end

    return nil
end

function addon:GetNativeSecretEngine()
    local compat = self:GetCompatLayer()
    if compat and type(compat.NativeSecretEngine) == "table" then
        return compat.NativeSecretEngine
    end

    local native = rawget(_G, "ActionSecretEngineNative")
    if type(native) == "table" then
        return native
    end

    local action = rawget(_G, "Action")
    if type(action) == "table" and type(action.SecretEngineNative) == "table" then
        return action.SecretEngineNative
    end

    return nil
end

function addon:GetSecretEngine()
    local native = self:GetNativeSecretEngine()
    if native then
        return native
    end

    local compat = self:GetCompatLayer()
    if compat and type(compat) == "table" then
        return compat
    end

    local secretEngine = rawget(_G, "ActionSecretEngine")
    if type(secretEngine) == "table" then
        return secretEngine
    end

    return nil
end

function addon:IsSecretValue(value)
    if value == nil then
        return false
    end

    local compat = self:GetCompatLayer()
    if compat and type(compat.IsSecret) == "function" then
        local ok, secret = pcall(compat.IsSecret, compat, value)
        if ok and secret then
            return true
        end

        ok, secret = pcall(compat.IsSecret, value)
        if ok and secret then
            return true
        end
    end

    if type(_G.issecretvalue) == "function" then
        local ok, secret = pcall(_G.issecretvalue, value)
        if ok and secret then
            return true
        end
    end

    return false
end

function addon:NormalizeValue(value)
    if value == nil then
        return nil
    end

    local compat = self:GetCompatLayer()
    if compat and type(compat.NormalizeValue) == "function" then
        local ok, normalized = pcall(compat.NormalizeValue, compat, value)
        if ok and normalized ~= nil then
            return normalized
        end

        ok, normalized = pcall(compat.NormalizeValue, value)
        if ok and normalized ~= nil then
            return normalized
        end
    end

    if not self:IsSecretValue(value) then
        return value
    end

    if type(_G.scrubsecretvalues) == "function" then
        local ok, scrubbed = pcall(_G.scrubsecretvalues, value)
        if ok and not self:IsSecretValue(scrubbed) then
            return scrubbed
        end
    end

    return nil
end

function addon:NormalizeBoolean(value, fallback)
    local normalized = self:NormalizeValue(value)
    if normalized == true or normalized == 1 then
        return true
    end

    if normalized == false or normalized == 0 then
        return false
    end

    return fallback and true or false
end

function addon:NormalizeString(value)
    local normalized = self:NormalizeValue(value)
    if type(normalized) ~= "string" or normalized == "" then
        return nil
    end

    return normalized
end

function addon:NormalizeAuraData(auraData)
    if auraData == nil then
        return nil
    end

    local compat = self:GetCompatLayer()
    if compat and type(compat.NormalizeAuraData) == "function" then
        local ok, normalized = pcall(compat.NormalizeAuraData, compat, auraData)
        if ok and normalized then
            return normalized
        end

        ok, normalized = pcall(compat.NormalizeAuraData, auraData)
        if ok and normalized then
            return normalized
        end
    end

    return auraData
end

function addon:TryCompatUnwrap(value)
    if value == nil then
        return nil, true
    end

    local compat = self:GetCompatLayer()
    if compat and type(compat.TryUnwrap) == "function" then
        local ok, success, normalized = pcall(compat.TryUnwrap, compat, value)
        if ok and success then
            return normalized, true
        end

        ok, success, normalized = pcall(compat.TryUnwrap, value)
        if ok and success then
            return normalized, true
        end
    end

    local normalized = self:NormalizeValue(value)
    if normalized ~= nil then
        return normalized, true
    end

    return nil, false
end

function addon:TryUntaintNumber(value, fallback)
    local requestedFallback = type(fallback) == "number" and fallback or 0
    local secretInput = self:IsSecretValue(value)

    if type(value) == "number" and not secretInput then
        return value, true
    end

    local unwrapped, unwrappedKnown = self:TryCompatUnwrap(value)
    if unwrappedKnown and type(unwrapped) == "number" and not self:IsSecretValue(unwrapped) then
        return unwrapped, true
    end

    local compat = self:GetCompatLayer()
    if compat and type(compat.UntaintNumber) == "function" then
        local ok, normalized = pcall(compat.UntaintNumber, compat, value, requestedFallback)
        if ok and type(normalized) == "number" and not self:IsSecretValue(normalized) then
            if not secretInput or normalized ~= requestedFallback then
                return normalized, true
            end
        end

        ok, normalized = pcall(compat.UntaintNumber, value, requestedFallback)
        if ok and type(normalized) == "number" and not self:IsSecretValue(normalized) then
            if not secretInput or normalized ~= requestedFallback then
                return normalized, true
            end
        end
    end

    local normalized = self:NormalizeValue(value)
    if type(normalized) == "number" and not self:IsSecretValue(normalized) then
        return normalized, true
    end

    return requestedFallback, false
end

function addon:UntaintNumber(value, fallback)
    local normalized = self:TryUntaintNumber(value, fallback)
    return normalized
end

function addon:GetActionUnit(unitID)
    local action = rawget(_G, "Action")
    local unitFactory = action and action.Unit
    if type(action) ~= "table" or (type(unitFactory) ~= "function" and type(unitFactory) ~= "table") then
        return nil
    end

    local ok, unit = pcall(unitFactory, unitID)
    if ok and type(unit) == "table" then
        return unit
    end

    return nil
end

function addon:GetActionPlayer()
    local action = rawget(_G, "Action")
    local player = action and action.Player
    if type(player) == "table" then
        return player
    end
    return nil
end

function addon:GetActionSpell(spellID, ownerID)
    local action = rawget(_G, "Action")
    spellID = tonumber(spellID)
    if type(action) ~= "table" or not spellID or spellID <= 0 then
        return nil
    end

    local owner = tonumber(ownerID) or tonumber(action.PlayerSpec) or action.PlayerClass
    if not owner then
        return nil
    end

    self._actionSpellCache = type(self._actionSpellCache) == "table" and self._actionSpellCache or {}

    local ownerCache = self._actionSpellCache[owner]
    if type(ownerCache) == "table" and ownerCache[spellID] ~= nil then
        return ownerCache[spellID] or nil
    end

    local spellTable = action[owner]
    if type(spellTable) ~= "table" then
        return nil
    end

    local found = false
    for _, candidate in pairs(spellTable) do
        if type(candidate) == "table" and tonumber(candidate.ID) == spellID then
            found = candidate
            break
        end
    end

    ownerCache = type(ownerCache) == "table" and ownerCache or {}
    ownerCache[spellID] = found
    self._actionSpellCache[owner] = ownerCache

    return found or nil
end

function addon:TryActionUnitNumber(unitID, methodName, fallback, ...)
    local unit = self:GetActionUnit(unitID)
    if not unit then
        return fallback or 0, false
    end

    local method = unit[methodName]
    if type(method) ~= "function" then
        return fallback or 0, false
    end

    local ok, raw = pcall(method, unit, ...)
    if not ok then
        return fallback or 0, false
    end

    return self:TryUntaintNumber(raw, fallback)
end

function addon:TryActionPlayerNumber(methodName, fallback, ...)
    local player = self:GetActionPlayer()
    if not player then
        return fallback or 0, false
    end

    local method = player[methodName]
    if type(method) ~= "function" then
        return fallback or 0, false
    end

    local ok, raw = pcall(method, player, ...)
    if not ok then
        return fallback or 0, false
    end

    return self:TryUntaintNumber(raw, fallback)
end

function addon:TrySecretEngineNumber(methodName, fallback, ...)
    local requestedFallback = type(fallback) == "number" and fallback or 0
    local engines = {
        self:GetNativeSecretEngine(),
        self:GetSecretEngine(),
    }

    for _, secretEngine in ipairs(engines) do
        if type(secretEngine) == "table" then
            local method = secretEngine[methodName]
            if type(method) == "function" then
                local ok, first, second = pcall(method, secretEngine, ...)
                if not ok then
                    ok, first, second = pcall(method, ...)
                end

                if ok then
                    local raw = first
                    if type(first) == "boolean" then
                        if first then
                            raw = second
                        else
                            raw = nil
                        end
                    end

                    if raw ~= nil then
                        local normalized, isKnown = self:TryUntaintNumber(raw, requestedFallback)
                        if isKnown then
                            return normalized, true
                        end
                    end
                end
            end
        end
    end

    return requestedFallback, false
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
    self:NotifyCompatibilityChanged()
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

    self:NotifyCompatibilityChanged()
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

function addon:NotifyCompatibilityChanged()
    if self.Compatibility and self.Compatibility.Refresh then
        self.Compatibility:Refresh()
    end
end

function addon:RegisterRuntimeEvent(eventName, owner, methodName)
    eventName = tostring(eventName or "")
    if eventName == "" or type(owner) ~= "table" or type(owner[methodName]) ~= "function" then
        return false
    end

    local listeners = runtimeEventListeners[eventName]
    if type(listeners) ~= "table" then
        listeners = {}
        runtimeEventListeners[eventName] = listeners
    end

    for _, listener in ipairs(listeners) do
        if listener.owner == owner and listener.methodName == methodName then
            return true
        end
    end

    listeners[#listeners + 1] = {
        owner = owner,
        methodName = methodName,
    }

    return true
end

function addon:FireRuntimeEvent(eventName, ...)
    dispatchRuntimeEvent(eventName, ...)
end

function addon:InitializeModules()
    self._actionSpellCache = nil

    if self.TaintGuard and self.TaintGuard.Initialize then
        self.TaintGuard:Initialize()
    end
    if self.Compatibility and self.Compatibility.Initialize then
        self.Compatibility:Initialize()
    end
    if self.Trackers and self.Trackers.Initialize then
        self.Trackers:Initialize()
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
    self:NotifyCompatibilityChanged()
    self:FireRuntimeEvent("PLAYER_ENTERING_WORLD")
end

dispatchRuntimeEvent = function(event, ...)
    local listeners = runtimeEventListeners[event]
    if type(listeners) ~= "table" then
        return
    end

    for _, listener in ipairs(listeners) do
        local owner = listener.owner
        local method = owner and owner[listener.methodName]
        if type(method) == "function" then
            addon:SafeCall("EVENT:" .. tostring(event), method, owner, event, ...)
        end
    end
end

bootstrapFrame = CreateFrame("Frame")
bootstrapFrame:RegisterEvent("ADDON_LOADED")
bootstrapFrame:RegisterEvent("PLAYER_LOGIN")
bootstrapFrame:SetScript("OnEvent", function(_, event, ...)
    local arg1 = ...
    if event == "ADDON_LOADED" and arg1 == addonName then
        addon:InitializeDatabase()
    elseif event == "PLAYER_LOGIN" then
        addon:InitializeModules()
        addon:Print("Loaded v" .. addon.version)
    else
        dispatchRuntimeEvent(event, ...)
    end
end)
