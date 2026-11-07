local ADDON, ns = ...
local L, U = ns.L, ns.U

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("CHAT_MSG_ADDON")
ev:RegisterEvent("GROUP_ROSTER_UPDATE")
pcall(ev.RegisterEvent, ev, "PARTY_MEMBERS_CHANGED")
pcall(ev.RegisterEvent, ev, "RAID_ROSTER_UPDATE")

local rosterTimer
ev:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= ADDON then return end
        LDPokerDB = LDPokerDB or {}
        if LDPokerDB.proximity == nil then LDPokerDB.proximity = true end
        ns.Bank.Init()
        if math.randomseed then
            pcall(math.randomseed, math.floor(GetTime() * 1000) % 2147483647)
        end
    elseif event == "PLAYER_LOGIN" then
        ns.UI.Build()
        ns.BuildMinimapButton()
    elseif event == "CHAT_MSG_ADDON" then
        ns.Net.OnAddonMessage(...)
    else
        -- composition du groupe modifiée : on vérifie qui est encore là (une seconde plus tard)
        ns.Cancel(rosterTimer)
        rosterTimer = ns.After(1, ns.Net.CheckRoster)
    end
end)

SLASH_LDPOKER1 = "/poker"
SLASH_LDPOKER2 = "/ldpoker"
SlashCmdList["LDPOKER"] = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, arg = msg:match("^(%S*)%s*(.-)$")
    if cmd == "reset" then
        ns.Bank.Reset()
    elseif cmd == "scale" then
        local s = tonumber(arg)
        if s and s >= 0.5 and s <= 1.5 then ns.UI.SetScale(s) else U.Print(L.HELP) end
    elseif cmd == "help" or cmd == "?" then
        U.Print(L.HELP)
    else
        ns.UI.Toggle()
    end
end
