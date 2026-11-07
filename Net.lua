local ADDON, ns = ...
local L, U, Cards = ns.L, ns.U, ns.Cards

--[[
  Réseau : l'hôte de la table fait tourner le moteur (Engine.lua) et diffuse l'état.
  - Groupe (PARTY/RAID) : annonces de table, état public, actions, abattage, gains.
  - Chuchotement addon : cartes privées, réponses d'inscription, jetons rendus.
  - Les joueurs envoient leurs actions à l'hôte, qui vérifie tout.
  Champs séparés par « ~ », listes par « ; » et « , ».
]]
local N = {}
ns.Net = N

local PREFIX = "LDPOKER"
local SEP = "~"
N.host = nil      -- { id, engine, opts } quand je suis l'hôte
N.view = nil      -- ce que j'affiche de la table où je suis assis
N.pending = nil   -- demande d'inscription en cours
N.adverts = {}    -- tables annoncées dans le groupe

local register = (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) or RegisterAddonMessagePrefix
local sendAddon = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
if register then register(PREFIX) end

-- ------------------------------------------------------------------
-- File d'envoi (anti-limitation du serveur) avec fusion des états
-- ------------------------------------------------------------------
local queue = {}
local function enqueue(msg, channel, target, key)
    if key then
        for _, q in ipairs(queue) do
            if q.key == key and q.channel == channel then q.msg = msg return end
        end
    end
    queue[#queue + 1] = { msg = msg, channel = channel, target = target, key = key }
end

local sender = CreateFrame("Frame")
local elapsed = 0
sender:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < 0.11 or #queue == 0 then return end
    elapsed = 0
    local q = table.remove(queue, 1)
    pcall(sendAddon, PREFIX, q.msg, q.channel, q.target)
end)

local function join(...)
    local t = { ... }
    for i = 1, select("#", ...) do t[i] = tostring(t[i] == nil and "" or t[i]) end
    return table.concat(t, SEP)
end

local function split(msg)
    local t = {}
    for field in (msg .. SEP):gmatch("(.-)" .. SEP) do t[#t + 1] = field end
    return t
end

function N.ToGroup(msg, key)
    local ch = U.GroupChannel()
    if ch then enqueue(msg, ch, nil, key) end
end

function N.ToPlayer(name, msg)
    if name == U.Me() then
        N.Handle(msg, name, "LOCAL")
    else
        enqueue(msg, "WHISPER", name)
    end
end

-- Diffusion de l'hôte : moi immédiatement + le groupe
function N.HostBroadcast(msg, key)
    N.Handle(msg, U.Me(), "LOCAL")
    N.ToGroup(msg, key)
end

-- ------------------------------------------------------------------
-- Côté hôte
-- ------------------------------------------------------------------
local function myClass()
    local _, cls = UnitClass("player")
    return cls
end

function N.Advertise()
    local h = N.host
    if not h then return end
    local e = h.engine
    N.HostBroadcast(join("ADV", h.id, e.sb, e.bb, e.buyin, e:NumPlayers(), e.maxSeats, e.proximity and 1 or 0), "ADV")
end

local function seatRecord(i, p)
    local flags = ""
    if p.inHand then flags = flags .. "H" end
    if p.folded then flags = flags .. "F" end
    if p.allin then flags = flags .. "A" end
    if p.canRaise then flags = flags .. "R" end
    if p.bot then flags = flags .. "B" end
    if p.far then flags = flags .. "W" end
    if p.gone then flags = flags .. "G" end
    local name = p.name:gsub("[,;~]", "")
    return table.concat({ i, name, p.stack, p.bet, flags, p.act or "", p.class or "", p.pendingRebuy or 0 }, ",")
end

local flushTimer
local function flushState()
    flushTimer = nil
    local h = N.host
    if not h then return end
    local e = h.engine
    local total, main = e:Pots()
    N.HostBroadcast(join("T", h.id, e.handNo, e.phase, e.dealer or 0, e.toAct or 0, e:TimeLeft(),
        e.currentBet, e.minRaise, total, main, table.concat(e.board), e.sb, e.bb, e.buyin,
        e.running and 1 or 0, e.maxSeats, e.actionTime), "T")
    local records = {}
    for i = 1, e.maxSeats do
        local p = e.seats[i]
        if p then records[#records + 1] = seatRecord(i, p) end
    end
    -- découpage en messages de moins de 255 caractères
    local parts, cur = {}, ""
    for _, r in ipairs(records) do
        if #cur + #r + 1 > 200 then parts[#parts + 1] = cur; cur = r
        else cur = (cur == "" and r) or (cur .. ";" .. r) end
    end
    parts[#parts + 1] = cur
    for k, part in ipairs(parts) do
        N.HostBroadcast(join("S", h.id, k, #parts, part), "S" .. k)
    end
end

local function keysToString(keys)
    if type(keys) ~= "table" then return "" end
    local t = {}
    for i, v in ipairs(keys) do t[i] = tostring(v) end
    return table.concat(t, ",")
end

function N.HostEvent(kind, ...)
    local h = N.host
    if not h then return end
    local id, e = h.id, h.engine
    if kind == "state" then
        if not flushTimer then flushTimer = ns.After(0.05, flushState) end
    elseif kind == "hole" then
        local i, name, c1, c2 = ...
        local p = e.seats[i]
        if p and not p.bot then N.ToPlayer(name, join("H", id, e.handNo, c1 .. c2)) end
    elseif kind == "action" then
        local i, name, code, amount = ...
        N.HostBroadcast(join("A", id, e.handNo, i, code, amount))
    elseif kind == "show" then
        local i, name, c1, c2, cat, keys = ...
        N.HostBroadcast(join("D", id, e.handNo, i, c1 .. c2, cat, keysToString(keys)))
    elseif kind == "win" then
        local i, name, amount, cat, keys = ...
        N.HostBroadcast(join("W", id, e.handNo, i, amount, cat or 0, keysToString(keys)))
    elseif kind == "hand" then
        N.HostBroadcast(join("N", id, "HAND", (...)))
    elseif kind == "notice" then
        local code, arg = ...
        N.HostBroadcast(join("N", id, code, arg or ""))
    elseif kind == "join" or kind == "leave" then
        local _, name = ...
        N.HostBroadcast(join("N", id, kind == "join" and "JOIN" or "LEAVE", name))
        N.Advertise()
    elseif kind == "rebuy" then
        local _, name, amount = ...
        N.HostBroadcast(join("N", id, "REBUY", name, amount))
    end
end

function N.CreateTable(opts)
    if N.view or N.pending then return U.Print(L.ERR_RUNNING) end
    ns.Bank.Spend(opts.buyin, function(ok)
        if not ok then return end
        local io = {
            Event = N.HostEvent, After = ns.After, Cancel = ns.Cancel,
            InRange = U.InRange, Random = math.random, Now = GetTime,
        }
        local e = ns.Engine.New({
            sb = opts.sb, bb = opts.bb, buyin = opts.buyin, proximity = opts.proximity,
            maxSeats = 7, actionTime = opts.actionTime or 30, nextHandDelay = 6,
        }, io)
        local id = tostring(math.random(100000, 999999))
        N.host = { id = id, engine = e, opts = opts }
        N.EnsureView(id, U.Me())
        e:AddPlayer(U.Me(), opts.buyin, myClass(), false)
        N.Advertise()
        if not U.GroupChannel() then U.Print(L.ERR_NOGROUP) end
        ns.UI.Refresh()
    end)
end

function N.AddBot()
    local h = N.host
    if not h then return end
    local e = h.engine
    for _, name in ipairs(ns.Bots.NAMES) do
        if not e:SeatOf(name) then
            e:AddPlayer(name, e.buyin, ns.Bots.CLASSES[math.random(#ns.Bots.CLASSES)], true)
            return
        end
    end
end

function N.ToggleRunning()
    local h = N.host
    if h then h.engine:SetRunning(not h.engine.running) end
end

function N.CloseTable()
    local h = N.host
    if not h then return end
    local e = h.engine
    e:Stop()
    for i = 1, e.maxSeats do
        local p = e.seats[i]
        if p and not p.bot and not p.gone then
            -- main annulée : chacun récupère aussi ce qu'il avait misé
            local cash = p.stack + p.committed + (p.pendingRebuy or 0)
            if p.name == U.Me() then ns.Bank.Receive(cash)
            else N.ToPlayer(p.name, join("CASH", h.id, cash)) end
        end
    end
    N.ToGroup(join("X", h.id))
    N.adverts[h.id] = nil
    N.host = nil
    N.view = nil
    ns.UI.Refresh()
end

-- Joueurs partis du groupe : on les retire et on leur rend leurs jetons
function N.CheckRoster()
    local h = N.host
    if h then
        local e = h.engine
        for i = 1, e.maxSeats do
            local p = e.seats[i]
            if p and not p.bot and not p.gone and p.name ~= U.Me() and not U.UnitForName(p.name) then
                local cash = e:RemovePlayer(p.name)
                N.ToPlayer(p.name, join("CASH", h.id, cash))
            end
        end
    elseif N.view and not U.UnitForName(N.view.host) then
        U.Print(L.LOG_CLOSED)
        N.view = nil
        ns.UI.Refresh()
    end
end

local function hostReceive(cmd, f, sender)
    local h = N.host
    if not h or f[2] ~= h.id or sender == U.Me() then return end
    local e = h.engine
    if cmd == "J" then
        local buyin = tonumber(f[3]) or 0
        if e:SeatOf(sender) then
            return N.ToPlayer(sender, join("NO", h.id, "RUNNING", buyin))
        end
        if e.proximity and not U.InRange(sender) then
            return N.ToPlayer(sender, join("NO", h.id, "FAR", buyin))
        end
        if buyin ~= e.buyin then buyin = e.buyin end
        local seat, err = e:AddPlayer(sender, buyin, f[4] ~= "" and f[4] or nil, false)
        if not seat then return N.ToPlayer(sender, join("NO", h.id, err or "FULL", buyin)) end
        N.ToPlayer(sender, join("OK", h.id, seat, buyin))
    elseif cmd == "Q" then
        local cash = e:RemovePlayer(sender)
        N.ToPlayer(sender, join("CASH", h.id, cash))
    elseif cmd == "C" then
        e:Act(sender, tonumber(f[3]), f[4], tonumber(f[5]))
    elseif cmd == "R" then
        local amount = tonumber(f[3]) or 0
        if not e:Rebuy(sender, amount) then N.ToPlayer(sender, join("CASH", h.id, amount)) end
    end
end

-- ------------------------------------------------------------------
-- Côté joueur
-- ------------------------------------------------------------------
function N.EnsureView(id, host)
    if N.view and N.view.id == id then return N.view end
    N.view = {
        id = id, host = host, seats = {}, board = {}, hole = {}, shows = {}, wins = {},
        handNo = 0, phase = "idle", sb = 0, bb = 0, buyin = 0, maxSeats = 7,
        potTotal = 0, potMain = 0, currentBet = 0, minRaise = 0, toAct = 0, dealer = 0,
        partial = {},
    }
    N.lastHost = host
    N.pending = nil
    return N.view
end

function N.MySeat()
    local v = N.view
    if not v then return nil end
    local me = U.Me()
    for i, s in pairs(v.seats) do
        if s.name == me and not s.gone then return i, s end
    end
end

function N.Search()
    for id, a in pairs(N.adverts) do
        if not (N.host and N.host.id == id) then N.adverts[id] = nil end
    end
    N.ToGroup("WHO")
    if N.host then N.Advertise() end
    ns.UI.RefreshLobby()
end

function N.Join(id)
    local a = N.adverts[id]
    if not a then return U.Print(L.ERR_UNKNOWN) end
    if N.view or N.pending then return U.Print(L.ERR_RUNNING) end
    if a.proximity and not U.InRange(a.host) then return U.Print(L.ERR_FAR) end
    ns.Bank.Spend(a.buyin, function(ok)
        if not ok then return end
        N.pending = { id = id, host = a.host, buyin = a.buyin }
        N.ToPlayer(a.host, join("J", id, a.buyin, myClass() or ""))
        local pending = N.pending
        ns.After(8, function()
            if N.pending == pending then -- pas de réponse de l'hôte
                N.pending = nil
                ns.Bank.Receive(pending.buyin, true)
                U.Print(L.ERR_UNKNOWN)
                ns.UI.Refresh()
            end
        end)
    end)
end

function N.Leave()
    if N.host then return N.CloseTable() end
    local v = N.view
    if not v then return end
    N.ToPlayer(v.host, join("Q", v.id))
    v.leaving = true
    ns.After(6, function()
        if N.view == v then N.view = nil; ns.UI.Refresh() end
    end)
end

function N.Act(code, amount)
    local v = N.view
    if not v then return end
    if N.host then
        N.host.engine:Act(U.Me(), v.handNo, code, amount)
    else
        N.ToPlayer(v.host, join("C", v.id, v.handNo, code, amount or 0))
    end
end

function N.Rebuy()
    local v = N.view
    local _, me = N.MySeat()
    if not v or not me then return end
    local amount = v.buyin - me.stack - (me.pendingRebuy or 0)
    if amount <= 0 then return end
    ns.Bank.Spend(amount, function(ok)
        if not ok then return end
        if N.host then N.host.engine:Rebuy(U.Me(), amount)
        else N.ToPlayer(v.host, join("R", v.id, amount)) end
    end)
end

local function parseKeys(s)
    local t = {}
    for v in (s or ""):gmatch("[^,]+") do t[#t + 1] = tonumber(v) end
    return t
end

local function seatName(i)
    local s = N.view and N.view.seats[i]
    return s and s.name or "?"
end

local function clientReceive(cmd, f, sender, channel)
    local id = f[2]
    -- réponses à une demande d'inscription
    if (cmd == "OK" or cmd == "NO") and N.pending and N.pending.id == id and sender == N.pending.host then
        if cmd == "OK" then
            N.EnsureView(id, sender)
        else
            local p = N.pending
            N.pending = nil
            ns.Bank.Receive(p.buyin, true)
            U.Print(L["ERR_" .. (f[3] or "UNKNOWN")] or L.ERR_UNKNOWN)
        end
        return ns.UI.Refresh()
    end
    if N.pending and N.pending.id == id and sender == N.pending.host and (cmd == "T" or cmd == "S") then
        N.EnsureView(id, sender)
    end

    local v = N.view
    if not v or v.id ~= id or (sender ~= v.host and channel ~= "LOCAL") then return end
    local me = U.Me()

    if cmd == "T" then
        local hand = tonumber(f[3]) or 0
        if hand ~= v.handNo then
            v.handNo, v.shows, v.wins = hand, {}, {}
            if v.hole.hand ~= hand then v.hole = {} end
        end
        local prevBoard = #v.board
        v.phase = f[4]
        v.dealer = tonumber(f[5]) or 0
        local prevTurn = v.toAct
        v.toAct = tonumber(f[6]) or 0
        v.deadline = GetTime() + (tonumber(f[7]) or 0)
        v.currentBet, v.minRaise = tonumber(f[8]) or 0, tonumber(f[9]) or 0
        v.potTotal, v.potMain = tonumber(f[10]) or 0, tonumber(f[11]) or 0
        v.board = {}
        for c in (f[12] or ""):gmatch("..") do v.board[#v.board + 1] = c end
        v.sb, v.bb, v.buyin = tonumber(f[13]) or 0, tonumber(f[14]) or 0, tonumber(f[15]) or 0
        v.running = f[16] == "1"
        v.maxSeats = tonumber(f[17]) or 7
        v.actionTime = tonumber(f[18]) or 30
        if #v.board > prevBoard then U.Sound("card") end
        local mySeat = N.MySeat()
        if mySeat and v.toAct == mySeat and prevTurn ~= mySeat then
            U.Sound("turn")
            ns.UI.Flash(L.YOUR_TURN)
        end
        ns.UI.Refresh()
    elseif cmd == "S" then
        local part, nparts = tonumber(f[3]) or 1, tonumber(f[4]) or 1
        if part == 1 then v.partial = {} end
        for rec in (f[5] or ""):gmatch("[^;]+") do
            local r = {}
            for x in (rec .. ","):gmatch("(.-),") do r[#r + 1] = x end
            local i = tonumber(r[1])
            if i then
                local fl = r[5] or ""
                v.partial[i] = {
                    name = r[2], stack = tonumber(r[3]) or 0, bet = tonumber(r[4]) or 0,
                    inHand = fl:find("H") ~= nil, folded = fl:find("F") ~= nil, allin = fl:find("A") ~= nil,
                    canRaise = fl:find("R") ~= nil, bot = fl:find("B") ~= nil, far = fl:find("W") ~= nil,
                    gone = fl:find("G") ~= nil, act = r[6] or "", class = (r[7] ~= "" and r[7]) or nil,
                    pendingRebuy = tonumber(r[8]) or 0,
                }
            end
        end
        if part >= nparts then
            v.seats = v.partial
            v.partial = {}
            ns.UI.Refresh()
        end
    elseif cmd == "H" then
        local hand = tonumber(f[3])
        local cards = f[4] or ""
        local c1, c2 = cards:sub(1, 2), cards:sub(3, 4)
        if Cards.Valid(c1) and Cards.Valid(c2) then
            v.hole = { c1, c2, hand = hand }
            U.Sound("card")
            ns.UI.Refresh()
        end
    elseif cmd == "A" then
        local i, code, amount = tonumber(f[4]), f[5], tonumber(f[6]) or 0
        local fmt = L["LOG_ACT_" .. code]
        if fmt then ns.UI.Log(string.format(fmt, seatName(i), U.MoneyPO(amount))) end
        if code ~= "F" and code ~= "K" then U.Sound("chips") end
        ns.UI.SeatPulse(i)
    elseif cmd == "D" then
        local i = tonumber(f[4])
        local cards = f[5] or ""
        local cat = tonumber(f[6]) or 0
        local c1, c2 = cards:sub(1, 2), cards:sub(3, 4)
        if i and Cards.Valid(c1) and Cards.Valid(c2) then
            local desc = cat > 0 and Cards.Describe(cat, parseKeys(f[7])) or ""
            v.shows[i] = { c1, c2, desc = desc }
            if #v.board >= 5 or v.phase == "showdown" or v.phase == "done" then
                ns.UI.Log(string.format(L.LOG_SHOW, seatName(i), Cards.Inline(c1) .. Cards.Inline(c2), desc))
            end
            ns.UI.Refresh()
        end
    elseif cmd == "W" then
        local i, amount, cat = tonumber(f[4]), tonumber(f[5]) or 0, tonumber(f[6]) or 0
        if i then
            local desc = cat > 0 and Cards.Describe(cat, parseKeys(f[7])) or nil
            v.wins[i] = { amount = amount, desc = desc }
            if desc then
                ns.UI.Log(string.format(L.LOG_WIN_HAND, seatName(i), U.MoneyPO(amount), desc))
            else
                ns.UI.Log(string.format(L.LOG_WIN, seatName(i), U.MoneyPO(amount)))
            end
            if seatName(i) == me then
                U.Sound("win")
                local st = LDPokerCharDB.stats
                st.won = (st.won or 0) + 1
                if amount > (st.bestPot or 0) then st.bestPot = amount end
            end
            ns.UI.Refresh()
            ns.UI.WinPulse(i, amount)
        end
    elseif cmd == "N" then
        local code, a1, a2 = f[3], f[4], f[5]
        if code == "HAND" then
            ns.UI.Log(string.format(L.LOG_HAND, tonumber(a1) or 0))
            LDPokerCharDB.stats.hands = (LDPokerCharDB.stats.hands or 0) + 1
        elseif code == "JOIN" then ns.UI.Log(string.format(L.LOG_JOIN, a1))
        elseif code == "LEAVE" then ns.UI.Log(string.format(L.LOG_LEAVE, a1))
        elseif code == "FAR" then ns.UI.Log(string.format(L.LOG_FAR, a1))
        elseif code == "TIMEOUT" then ns.UI.Log(string.format(L.LOG_TIMEOUT, a1))
        elseif code == "WAIT" then ns.UI.Log(L.LOG_WAIT)
        elseif code == "REBUY" then
            ns.UI.Log(string.format(L.LOG_REBUY, a1, U.MoneyPO(tonumber(a2) or 0)))
        end
    elseif cmd == "CASH" then
        ns.Bank.Receive(tonumber(f[3]) or 0)
        if v.leaving or not N.MySeat() then N.view = nil end
        ns.UI.Refresh()
    elseif cmd == "X" then
        U.Print(L.LOG_CLOSED)
        N.view = nil
        ns.UI.Refresh()
    end
end

function N.Handle(msg, sender, channel)
    sender = U.Short(sender)
    if channel ~= "LOCAL" and sender == U.Me() then return end -- écho de mes propres envois
    local f = split(msg)
    local cmd = f[1]
    if cmd == "WHO" then
        if N.host then N.Advertise() end
    elseif cmd == "ADV" then
        local id = f[2]
        N.adverts[id] = {
            id = id, host = sender, sb = tonumber(f[3]) or 0, bb = tonumber(f[4]) or 0,
            buyin = tonumber(f[5]) or 0, players = tonumber(f[6]) or 0, max = tonumber(f[7]) or 7,
            proximity = f[8] == "1", seen = GetTime(),
        }
        ns.UI.RefreshLobby()
    elseif cmd == "X" and N.adverts[f[2]] then
        N.adverts[f[2]] = nil
        ns.UI.RefreshLobby()
        clientReceive(cmd, f, sender, channel)
    elseif cmd == "J" or cmd == "Q" or cmd == "C" or cmd == "R" then
        hostReceive(cmd, f, sender)
    else
        clientReceive(cmd, f, sender, channel)
    end
end

-- CASH reçu alors que la vue est déjà fermée (table fermée par l'hôte)
local origHandle = N.Handle
function N.Handle(msg, sender, channel)
    if msg:sub(1, 5) == "CASH" .. SEP and not N.view then
        local f = split(msg)
        if U.Short(sender) ~= U.Me() and U.Short(sender) == N.lastHost then
            ns.Bank.Receive(tonumber(f[3]) or 0)
        end
        return
    end
    return origHandle(msg, sender, channel)
end

function N.OnAddonMessage(prefix, msg, channel, sender)
    if prefix ~= PREFIX then return end
    N.Handle(msg, sender, channel)
end
