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
    addon:Print("/sm overlay on|off | /sm hud lock|unlock | /sm add <spellID> [slot] [priority] | /sm list")
end

local function printRegistry()
    for index, entry in ipairs(addon.Registry:GetAll()) do
        local spellName = addon:GetSpellName(entry.spellID) or tostring(entry.spellID)
        addon:Print(string.format("%d. %s | slot=%s | prio=%d | enabled=%s", index, spellName, entry.slot, entry.priority, tostring(entry.enabled)))
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
                if addon.ConfigUI and addon.ConfigUI.frame and addon.ConfigUI.frame:IsShown() then
                    addon.ConfigUI:Refresh()
                end
            else
                addon:Print(info or "Could not add spell")
            end
        elseif command == "list" then
            printRegistry()
        else
            addon:Print("Unknown command: " .. tostring(command))
            printHelp()
        end
    end

    self.initialized = true
end

addon.Commands = Commands

