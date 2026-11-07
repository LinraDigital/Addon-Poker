local ADDON, ns = ...
local L = ns.L
local U = {}
ns.U = U

ns.MEDIA = "Interface\\AddOns\\LD_Poker\\Media\\"

-- ------------------------------------------------------------------
-- Minuteries (indépendant de C_Timer pour rester compatible partout)
-- ------------------------------------------------------------------
local timers = {}
local timerFrame = CreateFrame("Frame")
timerFrame:SetScript("OnUpdate", function()
    if #timers == 0 then return end
    local now = GetTime()
    local i = 1
    while i <= #timers do
        local t = timers[i]
        if t.cancelled then
            table.remove(timers, i)
        elseif now >= t.at then
            table.remove(timers, i)
            local ok, err = pcall(t.fn)
            if not ok and geterrorhandler then geterrorhandler()(err) end
        else
            i = i + 1
        end
    end
end)

function ns.After(delay, fn)
    local t = { at = GetTime() + (delay or 0), fn = fn }
    timers[#timers + 1] = t
    return t
end

function ns.Cancel(t)
    if t then t.cancelled = true end
end

-- ------------------------------------------------------------------
-- Texte
-- ------------------------------------------------------------------
function U.Money(n)
    n = math.floor((tonumber(n) or 0) + 0.5)
    local s = tostring(math.abs(n))
    local out = s:reverse():gsub("(%d%d%d)", "%1 "):reverse():gsub("^ ", "")
    if n < 0 then out = "-" .. out end
    return out
end

function U.MoneyPO(n)
    return U.Money(n) .. " " .. L.PO
end

function U.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffe8b84a[LD - Poker]|r " .. tostring(msg))
end

function U.Sound(kind)
    if not PlaySound then return end
    local kit = SOUNDKIT or {}
    local id
    if kind == "chips" then id = kit.LOOT_WINDOW_COIN_SOUND or 120
    elseif kind == "turn" then id = kit.READY_CHECK or 8960
    elseif kind == "win" then id = kit.UI_QUEST_ROLLING_FORWARD_01 or kit.IG_QUEST_LIST_COMPLETE or 878
    elseif kind == "card" then id = kit.IG_ABILITY_PAGE_TURN or 836
    elseif kind == "click" then id = kit.IG_MAINMENU_OPTION_CHECKBOX_ON or 856
    else id = kit.IG_MAINMENU_OPEN or 850 end
    pcall(PlaySound, id, "SFX")
end

-- ------------------------------------------------------------------
-- Noms, unités et distance
-- ------------------------------------------------------------------
function U.Short(name)
    if not name then return nil end
    return (name:match("^([^%-]+)")) or name
end

function U.Me()
    return (UnitName("player"))
end

function U.UnitForName(name)
    name = U.Short(name)
    if not name then return nil end
    if name == U.Me() then return "player" end
    if IsInRaid and IsInRaid() then
        for i = 1, 40 do
            local u = "raid" .. i
            if UnitExists(u) and U.Short(UnitName(u)) == name then return u end
        end
    end
    for i = 1, 4 do
        local u = "party" .. i
        if UnitExists(u) and U.Short(UnitName(u)) == name then return u end
    end
    if UnitExists("target") and U.Short(UnitName("target")) == name then return "target" end
    return nil
end

-- ~28 mètres (distance de « suivre ») ; repli sur la portée de groupe.
function U.InRange(name)
    local unit = U.UnitForName(name)
    if not unit then return false end
    if unit == "player" then return true end
    if not UnitIsConnected(unit) then return false end
    if CheckInteractDistance then
        local ok, res = pcall(CheckInteractDistance, unit, 4)
        if ok and res then return true end
        if ok and res == false then return false end
    end
    if UnitInRange then
        local inRange, checked = UnitInRange(unit)
        if checked then return inRange and true or false end
        return inRange and true or false
    end
    return UnitIsVisible(unit) and true or false
end

function U.GroupChannel()
    if IsInRaid and IsInRaid() then return "RAID" end
    if IsInGroup and IsInGroup() then return "PARTY" end
    if GetNumRaidMembers and GetNumRaidMembers() > 0 then return "RAID" end
    if GetNumPartyMembers and GetNumPartyMembers() > 0 then return "PARTY" end
    return nil
end

function U.ClassFile(name)
    local unit = U.UnitForName(name)
    if unit then
        local _, cls = UnitClass(unit)
        return cls
    end
end
