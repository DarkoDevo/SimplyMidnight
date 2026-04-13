local _, addon = ...

local TaintGuard = {
    incidents = {},
}

local function trimIncidents(incidents)
    while #incidents > 25 do
        table.remove(incidents)
    end
end

function TaintGuard:Record(kind, payload)
    payload = payload or {}
    payload.kind = kind
    payload.at = date("%H:%M:%S")

    table.insert(self.incidents, 1, payload)
    trimIncidents(self.incidents)

    if addon.session and addon.session.debug then
        addon:Print(kind .. " | " .. (payload.source or "runtime") .. " | " .. (payload.message or ""))
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
        self:Record(event, {
            source = tostring(source),
            message = tostring(funcName or ""),
        })
    end)
end

addon.TaintGuard = TaintGuard

