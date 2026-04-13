local _, addon = ...

local Adapter = {}

function Adapter:Initialize()
    self.detected = rawget(_G, "Action") ~= nil
end

function Adapter:GetSnapshot()
    local action = rawget(_G, "Action")
    if type(action) ~= "table" then
        return {
            loaded = false,
            profile = nil,
        }
    end

    local profileName = nil
    if type(action.CurrentProfile) == "string" and action.CurrentProfile ~= "" then
        profileName = action.CurrentProfile
    end

    return {
        loaded = true,
        profile = profileName,
        burstToggle = type(action.GetToggle) == "function" and true or false,
        secretEngine = type(action.SecretEngine) == "table",
    }
end

function Adapter:GetStatusLine()
    local snapshot = addon.TaintGuard:SafeAdapterRead("SimplyGlad", function()
        return self:GetSnapshot()
    end)

    if not snapshot or not snapshot.loaded then
        return "adapter: SimplyGlad missing"
    end

    if snapshot.profile then
        return "adapter: SimplyGlad profile=" .. snapshot.profile
    end

    return "adapter: SimplyGlad detected"
end

addon.SimplyGladAdapter = Adapter
