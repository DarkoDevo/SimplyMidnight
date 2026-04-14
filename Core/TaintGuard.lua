local _, addon = ...

local TaintGuard = {
    incidents = {},
    recentSignatures = {},
}

local function trimIncidents(incidents)
    while #incidents > 25 do
        table.remove(incidents)
    end
end

local function isRelevantSource(source)
    source = tostring(source or "")
    if source == "" or source == "nil" then
        return false
    end

    if source == addon.name then
        return true
    end

    if source:find("SimplyMidnight", 1, true) then
        return true
    end

    return false
end

local function buildSignature(kind, payload)
    return table.concat({
        tostring(kind or ""),
        tostring(payload and payload.source or ""),
        tostring(payload and payload.message or ""),
    }, "\031")
end

function TaintGuard:Record(kind, payload)
    payload = payload or {}
    payload.kind = kind
    payload.at = date("%H:%M:%S")

    local signature = buildSignature(kind, payload)
    local now = GetTime and GetTime() or 0
    local recent = self.recentSignatures[signature]

    if recent and (now - recent.lastAt) <= 2 then
        recent.lastAt = now
        recent.count = recent.count + 1

        local latest = self.incidents[1]
        if latest and latest.signature == signature then
            latest.at = payload.at
            latest.count = recent.count
        end
    else
        local count = recent and (recent.count + 1) or 1
        payload.signature = signature
        payload.count = count
        table.insert(self.incidents, 1, payload)
        trimIncidents(self.incidents)

        self.recentSignatures[signature] = {
            lastAt = now,
            count = count,
        }
    end

    if addon.session and addon.session.debug then
        local latest = self.incidents[1]
        if latest and latest.signature == signature and latest.count == 1 then
            addon:Print(kind .. " | " .. (payload.source or "runtime") .. " | " .. (payload.message or ""))
        end
    end
end

function TaintGuard:SafeAdapterRead(source, callback, ...)
    local ok, resultA, resultB, resultC = pcall(callback, ...)
    if not ok then
        self:Record("ADAPTER_READ_FAILED", {
            source = source,
            message = tostring(resultA),
        })
        return nil
    end

    return resultA, resultB, resultC
end

function TaintGuard:GetLatestIncident()
    return self.incidents[1]
end

function TaintGuard:GetStatusLine()
    local latest = self:GetLatestIncident()
    if not latest then
        return "taint: clear"
    end

    if (latest.count or 1) > 1 then
        return string.format("taint: %s x%d (%s)", latest.kind, latest.count, latest.source or "runtime")
    end

    return string.format("taint: %s (%s)", latest.kind, latest.source or "runtime")
end

function TaintGuard:Initialize()
    if self.frame then
        return
    end

    self.frame = CreateFrame("Frame")
    self.frame:RegisterEvent("ADDON_ACTION_BLOCKED")
    self.frame:RegisterEvent("ADDON_ACTION_FORBIDDEN")
    self.frame:RegisterEvent("MACRO_ACTION_BLOCKED")
    self.frame:SetScript("OnEvent", function(_, event, source, funcName)
        if not isRelevantSource(source) then
            return
        end

        self:Record(event, {
            source = tostring(source),
            message = tostring(funcName or ""),
        })
    end)
end

addon.TaintGuard = TaintGuard
