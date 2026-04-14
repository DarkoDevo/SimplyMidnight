local _, addon = ...

local Adapter = {}

function Adapter:Initialize()
    self.detected = rawget(_G, "Action") ~= nil
    if addon.Compatibility and addon.Compatibility.RegisterAdapter then
        addon.Compatibility:RegisterAdapter("simplyglad", self)
    end
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
        provider = "SimplyGlad",
        loaded = true,
        profile = profileName,
        burstToggle = type(action.GetToggle) == "function" and true or false,
        secretEngine = type(action.SecretEngine) == "table",
        metaEngine = type(action.MetaEngine) == "table",
    }
end

function Adapter:GetCompatibilitySnapshot()
    local snapshot = self:GetSnapshot()
    return {
        provider = "SimplyGlad",
        loaded = snapshot.loaded,
        profile = snapshot.profile,
        compatibilityMode = snapshot.loaded and "capability-probed" or "missing",
        bridge = {
            reader = true,
            pixelHUD = true,
            publicBridgeTable = true,
        },
        capabilities = {
            burstToggle = snapshot.burstToggle and true or false,
            secretEngine = snapshot.secretEngine and true or false,
            metaEngine = snapshot.metaEngine and true or false,
        },
    }
end

function Adapter:GetStatusLine()
    local snapshot = addon.TaintGuard:SafeAdapterRead("SimplyGlad", function()
        return self:GetCompatibilitySnapshot()
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
