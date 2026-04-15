local _, addon = ...

local Commands = {}

local function boolFromArg(value, current)
    value = tostring(value or ""):lower()
    if value == "on" then
        return true
    elseif value == "off" then
        return false
    elseif value == "toggle" or value == "" then
        return not current
    end
    return current
end

local function printHelp()
    addon:Print("Commands: /sm help | /sm config | /sm burst [seconds] | /sm hold [seconds]")
    addon:Print("/sm conserve on|off|toggle | /sm pause on|off|toggle | /sm debug on|off")
    addon:Print("/sm overlay on|off | /sm export [profile|list] | /sm hud lock|unlock")
    addon:Print("/sm add <spellID> [slot] [priority] | /sm list")
    addon:Print("/sm defaults | /sm reset | /sm compat | /sm diag")
end

local function printExportProfiles()
    local activeKey = addon:GetExportProfileKey()
    addon:Print("Export profiles:")
    for _, key in ipairs(addon.OutputProfiles and addon.OutputProfiles:GetKeys() or {}) do
        local contract = addon.OutputProfiles:GetContract(key)
        local marker = key == activeKey and "*" or "-"
        addon:Print(string.format("%s %s | %s | %dx%d", marker, contract.key, tostring(contract.label), tonumber(contract.frame.width) or 0, tonumber(contract.frame.height) or 0))
    end
end

local function printRegistry()
    for index, entry in ipairs(addon.Registry:GetAll()) do
        local spellName = addon:GetSpellName(entry.spellID) or tostring(entry.spellID)
        addon:Print(string.format("%d. %s | slot=%s | prio=%d | spec=%s | enabled=%s", index, spellName, entry.slot, entry.priority, tostring(entry.specID or "-"), tostring(entry.enabled)))
    end
end

local function printCompatibility()
    local snapshot = addon.Compatibility and addon.Compatibility:GetSnapshot() or nil
    if not snapshot then
        addon:Print("Compatibility snapshot unavailable")
        return
    end

    addon:Print(string.format("Compat: protocol=%s | export=%s | risks=%d", snapshot.protocolVersion, snapshot.export.protocolVersion, #snapshot.riskFlags))
    addon:Print(string.format("WoW: version=%s | build=%s | interface=%s", tostring(snapshot.wow.version), tostring(snapshot.wow.build), tostring(snapshot.wow.interface)))
    addon:Print(string.format("APIs: aura=%s range=%s nameplates=%s cspell=%s", tostring(snapshot.api.unitAura), tostring(snapshot.api.spellRange), tostring(snapshot.api.nameplates), tostring(snapshot.api.cSpell)))

    local adapter = snapshot.adapters and snapshot.adapters.simplyglad or nil
    if adapter and adapter.loaded then
        addon:Print(string.format("SimplyGlad: mode=%s | profile=%s | secret=%s | meta=%s", tostring(adapter.compatibilityMode), tostring(adapter.profile or "-"), tostring(adapter.capabilities and adapter.capabilities.secretEngine or false), tostring(adapter.capabilities and adapter.capabilities.metaEngine or false)))
    else
        addon:Print("SimplyGlad: not detected")
    end
end

local function printDiagnostics()
    local state = addon.State and addon.State:Refresh() or nil
    local preAuraDebug = addon.Recommendations and addon.Recommendations.GetAuraDebug and addon.Recommendations:GetAuraDebug("target", 191587, "HARMFUL", "player") or nil
    local trackerDebug = addon.Trackers and addon.Trackers.GetDebugSnapshot and addon.Trackers:GetDebugSnapshot("target", 191587) or nil
    local recommendations = addon.Recommendations and addon.Recommendations:Refresh(state, { diagnostics = true }) or nil
    if not state or not recommendations then
        addon:Print("Diagnostics unavailable")
        return
    end

    if addon.ExportHUD and addon.ExportHUD.GetDiagnosticLines then
        local lines = addon.ExportHUD:GetDiagnosticLines(state, recommendations)
        for _, line in ipairs(lines or {}) do
            if line and line ~= "" then
                addon:Print(line)
            end
        end

        local primaryDebug = state.player and state.player.primaryDebug or nil
        if type(primaryDebug) == "table" then
            local function fmt(value)
                if type(value) == "number" then
                    return tostring(math.floor(value + 0.5))
                end
                return "?"
            end

            addon:Print(string.format(
                "pwrsrc rawT=%s raw=%s actP=%s actD=%s actU=%s actUD=%s secT=%s sec=%s thr=%s/%s est=%s/%s",
                fmt(primaryDebug.rawTyped),
                fmt(primaryDebug.rawUntyped),
                fmt(primaryDebug.actionPlayer),
                fmt(primaryDebug.actionDeficit),
                fmt(primaryDebug.actionUnit),
                fmt(primaryDebug.actionUnitDeficit),
                fmt(primaryDebug.secretTyped),
                fmt(primaryDebug.secretUntyped),
                fmt(primaryDebug.thresholdCurrent),
                fmt(primaryDebug.thresholdMax),
                fmt(primaryDebug.estimatedCurrent),
                fmt(primaryDebug.estimatedMax)
            ))

            if primaryDebug.thresholdMode then
                addon:Print(string.format(
                    "pwrthr mode=%s known=%s pct=%s attempts=%s",
                    tostring(primaryDebug.thresholdMode),
                    tostring(primaryDebug.thresholdKnown),
                    fmt(primaryDebug.thresholdPct),
                    fmt(primaryDebug.thresholdAttempts)
                ))
            end

            if primaryDebug.estimatedMax then
                addon:Print(string.format(
                    "pwrest active=%s known=%s pct=%s gen=%s spent=%s",
                    tostring(primaryDebug.estimatedActive),
                    tostring(primaryDebug.estimatedKnown),
                    fmt(primaryDebug.estimatedPct),
                    fmt(primaryDebug.estimatedGenerated),
                    fmt(primaryDebug.estimatedSpent)
                ))
                addon:Print(string.format(
                    "pwrest2 seed=%s totalGen=%s totalSpent=%s last=%s",
                    fmt(primaryDebug.estimatedSeeded),
                    fmt(primaryDebug.estimatedTotalGenerated),
                    fmt(primaryDebug.estimatedTotalSpent),
                    fmt(primaryDebug.estimatedLastSpellID)
                ))
            end

            if primaryDebug.framePath then
                addon:Print(string.format(
                    "pwrui cur=%s max=%s src=%s w=%s fill=%s path=%s",
                    fmt(primaryDebug.frameCurrent),
                    fmt(primaryDebug.frameMax),
                    tostring(primaryDebug.frameSource or "?"),
                    fmt(primaryDebug.frameWidth),
                    fmt(primaryDebug.frameFillWidth),
                    tostring(primaryDebug.framePath)
                ))
            end

            local frameCandidates = primaryDebug.frameCandidates
            if type(frameCandidates) == "table" then
                for index = 1, math.min(3, #frameCandidates) do
                    local candidate = frameCandidates[index]
                    if type(candidate) == "table" then
                        addon:Print(string.format(
                            "pwrui%d score=%s cur=%s max=%s src=%s w=%s fill=%s rgb=%s/%s/%s path=%s",
                            index,
                            fmt(candidate.score),
                            fmt(candidate.current),
                            fmt(candidate.max),
                            tostring(candidate.source or "?"),
                            fmt(candidate.width),
                            fmt(candidate.fillWidth),
                            fmt(candidate.color and candidate.color.red and math.floor((candidate.color.red or 0) * 100 + 0.5) or 0),
                            fmt(candidate.color and candidate.color.green and math.floor((candidate.color.green or 0) * 100 + 0.5) or 0),
                            fmt(candidate.color and candidate.color.blue and math.floor((candidate.color.blue or 0) * 100 + 0.5) or 0),
                            tostring(candidate.path or "?")
                        ))
                    end
                end
            end

            if primaryDebug.textPath then
                addon:Print(string.format(
                    "pwrtxt cur=%s max=%s txt=%s path=%s",
                    fmt(primaryDebug.textCurrent),
                    fmt(primaryDebug.textMax),
                    tostring(primaryDebug.textRaw or "?"),
                    tostring(primaryDebug.textPath)
                ))
            end

            local textCandidates = primaryDebug.textCandidates
            if type(textCandidates) == "table" then
                for index = 1, math.min(3, #textCandidates) do
                    local candidate = textCandidates[index]
                    if type(candidate) == "table" then
                        addon:Print(string.format(
                            "pwrtxt%d score=%s cur=%s max=%s txt=%s path=%s",
                            index,
                            fmt(candidate.score),
                            fmt(candidate.current),
                            fmt(candidate.max),
                            tostring(candidate.text or "?"),
                            tostring(candidate.path or "?")
                        ))
                    end
                end
            end
        end

        if type(preAuraDebug) == "table" then
            local remainText = type(preAuraDebug.remaining) == "number" and string.format("%.1f", preAuraDebug.remaining) or "?"
            local countText = type(preAuraDebug.count) == "number" and tostring(math.floor(preAuraDebug.count + 0.5)) or "?"
            addon:Print(string.format("disease src=%s rem=%s cnt=%s prov=%s", tostring(preAuraDebug.source or "missing"), remainText, countText, tostring(preAuraDebug.provisional)))
        end

        if type(trackerDebug) == "table" then
            local function fmtTime(value)
                if type(value) ~= "number" or value == math.huge then
                    return "?"
                end
                return string.format("%.1f", value)
            end

            addon:Print(string.format(
                "otrk cast=%s req=%s trk=%s cd=%s",
                fmtTime(trackerDebug.sinceLastCast),
                fmtTime(trackerDebug.requestRemaining),
                fmtTime(trackerDebug.trackedRemaining),
                fmtTime(trackerDebug.cooldownRemaining)
            ))
        end
        return
    end

    addon:Print("Diagnostics generated but HUD formatter is unavailable")
end

local function refreshConfigIfShown()
    if addon.ConfigUI and addon.ConfigUI.frame and addon.ConfigUI.frame:IsShown() then
        addon.ConfigUI:Refresh()
    end
end

function Commands:Initialize()
    if self.initialized then
        return
    end

    SLASH_SIMPLYMIDNIGHT1 = "/sm"
    SLASH_SIMPLYMIDNIGHT2 = "/simplymidnight"
    SlashCmdList.SIMPLYMIDNIGHT = function(message)
        local command, rest = string.match(message or "", "^(%S*)%s*(.-)$")
        command = string.lower(command or "")

        if command == "" or command == "help" then
            printHelp()
        elseif command == "config" then
            addon.ConfigUI:Toggle()
        elseif command == "burst" then
            local seconds = tonumber(rest) or 8
            addon:SetTimedMode("burst", seconds)
            addon:Print("Burst mode enabled for " .. seconds .. "s")
        elseif command == "hold" then
            local seconds = tonumber(rest) or 6
            addon:SetTimedMode("hold", seconds)
            addon:Print("Hold mode enabled for " .. seconds .. "s")
        elseif command == "conserve" then
            local nextValue = boolFromArg(rest, addon.session.conserve)
            addon:SetToggleMode("conserve", nextValue)
            addon:Print("Conserve mode: " .. tostring(addon.session.conserve))
        elseif command == "pause" then
            local nextValue = boolFromArg(rest, addon.session.pause)
            addon:SetToggleMode("pause", nextValue)
            addon:Print("Pause mode: " .. tostring(addon.session.pause))
        elseif command == "debug" then
            local nextValue = boolFromArg(rest, addon.session.debug)
            addon:SetToggleMode("debug", nextValue)
            addon:Print("Debug mode: " .. tostring(addon.session.debug))
        elseif command == "overlay" then
            local nextValue = boolFromArg(rest, addon.session.overlay)
            addon:SetToggleMode("overlay", nextValue)
            addon:Print("Overlay mode: " .. tostring(addon.session.overlay))
        elseif command == "export" or command == "profile" then
            local exportArg = string.lower(tostring(rest or "")):gsub("^%s+", ""):gsub("%s+$", "")
            if exportArg == "" or exportArg == "current" then
                local contract = addon.OutputProfiles and addon.OutputProfiles:GetContract(addon:GetExportProfileKey()) or nil
                if contract then
                    addon:Print(string.format("Export profile: %s | %s | %dx%d", contract.key, contract.label, tonumber(contract.frame.width) or 0, tonumber(contract.frame.height) or 0))
                else
                    addon:Print("Export profile unavailable")
                end
            elseif exportArg == "list" then
                printExportProfiles()
            else
                local ok, value = addon:SetExportProfile(exportArg)
                if ok then
                    local contract = addon.OutputProfiles and addon.OutputProfiles:GetContract(value) or nil
                    addon:Print("Export profile: " .. tostring(contract and contract.label or value))
                    refreshConfigIfShown()
                else
                    addon:Print(value or "Unknown export profile")
                    printExportProfiles()
                end
            end
        elseif command == "hud" then
            local option = string.lower(rest or "")
            if option == "lock" then
                addon.ExportHUD:SetLocked(true)
                addon:Print("HUD locked")
            elseif option == "unlock" then
                addon.ExportHUD:SetLocked(false)
                addon:Print("HUD unlocked")
            else
                addon:Print("Use /sm hud lock or /sm hud unlock")
            end
        elseif command == "add" then
            local spellID, slot, priority = string.match(rest or "", "^(%d+)%s*(%S*)%s*(%S*)$")
            local ok, info = addon.Registry:AddSpell(spellID, slot ~= "" and slot or "primary", priority ~= "" and tonumber(priority) or 50)
            if ok then
                addon:Print("Added " .. tostring(info))
                refreshConfigIfShown()
            else
                addon:Print(info or "Could not add spell")
            end
        elseif command == "defaults" then
            local ok, info = addon.Registry:EnsureCurrentPack(false)
            addon:Print(info or (ok and "Installed current spec defaults" or "No defaults installed"))
            refreshConfigIfShown()
        elseif command == "reset" then
            local ok, info = addon.Registry:ResetCurrentPack()
            addon:Print(info or (ok and "Reset current spec defaults" or "Could not reset current spec"))
            refreshConfigIfShown()
        elseif command == "list" then
            printRegistry()
        elseif command == "compat" then
            printCompatibility()
        elseif command == "diag" then
            printDiagnostics()
        else
            addon:Print("Unknown command: " .. tostring(command))
            printHelp()
        end
    end

    self.initialized = true
end

addon.Commands = Commands
