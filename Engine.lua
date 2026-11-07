local ADDON, ns = ...
local Cards = ns.Cards

--[[
  Moteur de Texas Hold'em No Limit, exécuté uniquement chez l'hôte de la table.

  Règles appliquées :
  - Blindes : petite blinde à gauche du donneur, grosse blinde ensuite.
    En tête-à-tête, le donneur pose la petite blinde, parle en premier avant le flop
    et en dernier après.
  - Avant le flop, la parole commence à gauche de la grosse blinde (qui garde l'option) ;
    ensuite elle commence au premier joueur actif à gauche du donneur.
  - Mise minimale = grosse blinde ; relance minimale = montant de la dernière mise ou relance.
  - Un tapis inférieur à une relance complète ne rouvre pas les enchères pour les joueurs
    qui ont déjà parlé (ils peuvent seulement suivre ou se coucher).
  - On ne joue que ce qui est sur la table : un joueur sans assez de jetons fait tapis
    et des pots annexes sont créés. Pas de dette pendant une main.
  - Abattage : meilleure main de 5 cartes parmi 7 ; égalité = pot partagé,
    jeton indivisible au premier gagnant à gauche du donneur.

  io (fourni par Net.lua ou par les tests) :
    io.Event(kind, ...)   io.After(delay, fn) -> handle   io.Cancel(handle)
    io.InRange(name)      io.Random(n)                    io.Now()
]]

local E = {}
E.__index = E
ns.Engine = E

local BETTING = { preflop = true, flop = true, turn = true, river = true }
E.BETTING = BETTING

local function inHand(p) return p.inHand end
local function alive(p) return p.inHand and not p.folded end
local function canAct(p) return p.inHand and not p.folded and not p.allin end

function E.New(opts, io)
    local self = setmetatable({}, E)
    self.sb = opts.sb
    self.bb = opts.bb
    self.buyin = opts.buyin
    self.maxSeats = opts.maxSeats or 7
    self.actionTime = opts.actionTime or 30
    self.proximity = opts.proximity ~= false
    self.nextHandDelay = opts.nextHandDelay or 6
    self.io = io
    self.seats = {}
    self.handNo = 0
    self.phase = "idle"
    self.board = {}
    self.dealer = 0
    self.currentBet = 0
    self.minRaise = self.bb
    self.running = false
    return self
end

-- ------------------------------------------------------------------
-- Places
-- ------------------------------------------------------------------
function E:SeatOf(name)
    for i = 1, self.maxSeats do
        local p = self.seats[i]
        if p and not p.gone and p.name == name then return i, p end
    end
end

function E:NumPlayers()
    local n = 0
    for i = 1, self.maxSeats do
        local p = self.seats[i]
        if p and not p.gone then n = n + 1 end
    end
    return n
end

function E:NextSeat(from, pred)
    for k = 1, self.maxSeats do
        local i = ((from - 1 + k) % self.maxSeats) + 1
        local p = self.seats[i]
        if p and pred(p, i) then return i end
    end
end

function E:Count(pred)
    local n = 0
    for i = 1, self.maxSeats do
        local p = self.seats[i]
        if p and pred(p) then n = n + 1 end
    end
    return n
end

function E:Changed()
    self.io.Event("state")
end

function E:AddPlayer(name, buyin, class, bot)
    if self:SeatOf(name) then return nil, "RUNNING" end
    for i = 1, self.maxSeats do
        if not self.seats[i] then
            self.seats[i] = {
                name = name, stack = math.max(0, math.floor(buyin or 0)), bet = 0, committed = 0,
                class = class, bot = bot and true or false, hole = {}, pendingRebuy = 0,
            }
            self.io.Event("join", i, name)
            self:Changed()
            if self.running and not BETTING[self.phase] and self.phase ~= "showdown" then
                self:ScheduleNext(1.5)
            end
            return i
        end
    end
    return nil, "FULL"
end

-- Retire un joueur ; renvoie les jetons qu'il récupère.
function E:RemovePlayer(name)
    local i, p = self:SeatOf(name)
    if not p then return 0 end
    local cash = p.stack + (p.pendingRebuy or 0)
    p.stack, p.pendingRebuy = 0, 0
    p.gone = true
    self.io.Event("leave", i, name)
    if BETTING[self.phase] and alive(p) then
        if self.toAct == i then
            self:DoAction(i, "F")
        else
            p.folded, p.needAct, p.act = true, false, "F"
            self:AfterFold()
        end
    elseif not (BETTING[self.phase] and p.inHand) then
        self.seats[i] = nil
    end
    self:Changed()
    return cash
end

function E:Rebuy(name, amount)
    local i, p = self:SeatOf(name)
    if not p then return false end
    amount = math.max(0, math.floor(amount or 0))
    if BETTING[self.phase] and alive(p) then
        p.pendingRebuy = (p.pendingRebuy or 0) + amount
    else
        p.stack = p.stack + amount
    end
    self.io.Event("rebuy", i, name, amount)
    self:Changed()
    if self.running and (self.phase == "idle") then self:ScheduleNext(1.5) end
    return true
end

function E:SetRunning(on)
    self.running = on and true or false
    if self.running and not BETTING[self.phase] and self.phase ~= "showdown" then
        self:ScheduleNext(1)
    elseif not self.running then
        self.io.Cancel(self.nextTimer)
        self.nextTimer = nil
    end
    self:Changed()
end

function E:ScheduleNext(delay)
    self.io.Cancel(self.nextTimer)
    self.nextTimer = self.io.After(delay, function()
        self.nextTimer = nil
        self:StartHand()
    end)
end

function E:Stop()
    self.running = false
    for _, h in ipairs({ self.nextTimer, self.turnTimer, self.stepTimer }) do self.io.Cancel(h) end
    self.nextTimer, self.turnTimer, self.stepTimer = nil, nil, nil
end

-- ------------------------------------------------------------------
-- Déroulement d'une main
-- ------------------------------------------------------------------
function E:Move(p, amount)
    amount = math.min(amount, p.stack)
    p.stack = p.stack - amount
    p.bet = p.bet + amount
    p.committed = p.committed + amount
    if p.stack == 0 then p.allin = true end
    return amount
end

function E:StartHand()
    if not self.running then
        self.phase = "idle"
        self:Changed()
        return
    end
    for i = 1, self.maxSeats do
        local p = self.seats[i]
        if p and p.gone then self.seats[i] = nil end
    end

    local elig = 0
    for i = 1, self.maxSeats do
        local p = self.seats[i]
        if p then
            if (p.pendingRebuy or 0) > 0 then
                p.stack, p.pendingRebuy = p.stack + p.pendingRebuy, 0
            end
            p.inHand, p.folded, p.allin = false, false, false
            p.bet, p.committed, p.hole, p.act = 0, 0, {}, nil
            p.needAct, p.acted, p.canRaise = false, false, true
            p.far = (not p.bot) and self.proximity and not self.io.InRange(p.name)
            if p.stack > 0 and not p.far then
                p.inHand = true
                elig = elig + 1
            end
        end
    end

    self.board, self.toAct, self.revealed = {}, nil, false
    if elig < 2 then
        self.phase = "idle"
        self.io.Event("notice", "WAIT")
        self:Changed()
        return
    end

    self.handNo = self.handNo + 1
    self.deck = Cards.Shuffle(Cards.NewDeck(), self.io.Random)
    self.dealer = self:NextSeat(self.dealer, inHand)
    if elig == 2 then
        self.sbSeat = self.dealer
    else
        self.sbSeat = self:NextSeat(self.dealer, inHand)
    end
    self.bbSeat = self:NextSeat(self.sbSeat, inHand)
    self.phase = "preflop"
    self.io.Event("hand", self.handNo)

    local sbP, bbP = self.seats[self.sbSeat], self.seats[self.bbSeat]
    sbP.act = "SB" .. self:Move(sbP, self.sb)
    bbP.act = "BB" .. self:Move(bbP, self.bb)
    self.currentBet, self.minRaise = self.bb, self.bb

    -- Distribution : une carte à la fois, en partant de la petite blinde
    for _ = 1, 2 do
        local i = self.sbSeat
        repeat
            local p = self.seats[i]
            p.hole[#p.hole + 1] = table.remove(self.deck)
            i = self:NextSeat(i, inHand)
        until i == self.sbSeat
    end
    for i = 1, self.maxSeats do
        local p = self.seats[i]
        if p and p.inHand then
            self.io.Event("hole", i, p.name, p.hole[1], p.hole[2])
            if not p.allin then p.needAct, p.canRaise, p.acted = true, true, false end
        end
    end

    self:PruneNeedAct()
    self:SetTurn(self:NextSeat(self.bbSeat, function(p) return canAct(p) and p.needAct end))
end

-- Si un seul joueur peut encore parler et qu'il n'a rien à payer, inutile de lui demander.
function E:PruneNeedAct()
    if self:Count(canAct) <= 1 then
        for i = 1, self.maxSeats do
            local p = self.seats[i]
            if p and canAct(p) and p.bet >= self.currentBet then p.needAct = false end
        end
    end
end

function E:SetTurn(i)
    self.io.Cancel(self.turnTimer)
    self.turnTimer = nil
    if not i then return self:EndRound() end
    self.toAct = i
    self.turnStart = self.io.Now()
    local p = self.seats[i]
    self:Changed()
    local hand = self.handNo
    local function guard(fn)
        return function()
            if self.handNo == hand and self.toAct == i and BETTING[self.phase] then fn() end
        end
    end
    if p.bot then
        self.turnTimer = self.io.After(0.9 + self.io.Random(15) / 10, guard(function() self:BotAct(i) end))
    elseif self.proximity and not self.io.InRange(p.name) then
        self.turnTimer = self.io.After(0.5, guard(function()
            self.io.Event("notice", "FAR", p.name)
            self:AutoAct(i)
        end))
    else
        self.turnTimer = self.io.After(self.actionTime, guard(function()
            self.io.Event("notice", "TIMEOUT", p.name)
            self:AutoAct(i)
        end))
    end
end

function E:TimeLeft()
    if not self.toAct or not self.turnStart then return 0 end
    local p = self.seats[self.toAct]
    if p and p.bot then return 0 end
    return math.max(0, math.floor(self.actionTime - (self.io.Now() - self.turnStart) + 0.5))
end

function E:AutoAct(i)
    local p = self.seats[i]
    if p.bet >= self.currentBet then self:DoAction(i, "K") else self:DoAction(i, "F") end
end

function E:BotAct(i)
    local a, amt = ns.Bots.Decide(self, i)
    self:DoAction(i, a, amt)
end

-- Appelé par le réseau : vérifie que c'est bien au bon joueur de parler
function E:Act(name, handNo, action, amount)
    if not BETTING[self.phase] or handNo ~= self.handNo then return false end
    local i, p = self:SeatOf(name)
    if not p or self.toAct ~= i then return false end
    return self:DoAction(i, action, amount)
end

-- action : F (se coucher), K (parler), C (suivre), R (relancer à `amount`), A (tapis)
function E:DoAction(i, a, amount)
    local p = self.seats[i]
    if not p or not canAct(p) or self.toAct ~= i then return false end
    local toCall = self.currentBet - p.bet
    local shown

    if a == "K" and toCall > 0 then a = "F" end
    if a == "C" and toCall <= 0 then a = "K" end

    if a == "F" then
        p.folded, p.act = true, "F"
    elseif a == "K" then
        p.act = "K"
    elseif a == "C" then
        self:Move(p, toCall)
        p.act = (p.allin and "A" or "C") .. p.bet
        shown = p.bet
    elseif a == "R" or a == "A" then
        local maxTo = p.bet + p.stack
        local to = (a == "A") and maxTo or math.floor(tonumber(amount) or 0)
        if to > maxTo then to = maxTo end
        if to <= self.currentBet or not p.canRaise then
            return self:DoAction(i, "C")
        end
        local inc = to - self.currentBet
        if inc < self.minRaise and to < maxTo then
            to = math.min(self.currentBet + self.minRaise, maxTo)
            inc = to - self.currentBet
        end
        local full = inc >= self.minRaise
        local wasOpen = self.currentBet == 0
        self:Move(p, to - p.bet)
        self.currentBet = to
        if full then self.minRaise = inc end
        for j = 1, self.maxSeats do
            local q = self.seats[j]
            if q and j ~= i and canAct(q) then
                if full then
                    q.needAct, q.canRaise, q.acted = true, true, false
                else
                    if q.bet < to then q.needAct = true end
                    if q.acted then q.canRaise = false end
                end
            end
        end
        p.act = (p.allin and "A" or (wasOpen and "B" or "R")) .. to
        shown = to
    else
        return false
    end

    p.needAct, p.acted = false, true
    self.io.Cancel(self.turnTimer)
    self.turnTimer = nil
    self.io.Event("action", i, p.name, p.act:sub(1, 1), shown or 0)

    if p.folded then return self:AfterFold(i) or true end
    self:PruneNeedAct()
    local nxt = self:NextSeat(i, function(q) return canAct(q) and q.needAct end)
    if nxt then self:SetTurn(nxt) else self:EndRound() end
    return true
end

function E:AfterFold(from)
    if self:Count(alive) <= 1 then
        self:EndRound()
        return true
    end
    if from then
        self:PruneNeedAct()
        local nxt = self:NextSeat(from, function(q) return canAct(q) and q.needAct end)
        if nxt then self:SetTurn(nxt) else self:EndRound() end
    elseif self.toAct == nil then
        return true -- tableau en cours de déroulement : rien à faire
    else
        -- le joueur parti n'était pas en train de parler : vérifier qu'il reste quelqu'un à attendre
        self:PruneNeedAct()
        local cur = self.seats[self.toAct]
        if not (cur and canAct(cur) and cur.needAct) then
            local nxt = self:NextSeat(self.toAct, function(q) return canAct(q) and q.needAct end)
            if nxt then self:SetTurn(nxt) else self:EndRound() end
        end
    end
    return true
end

function E:EndRound()
    self.io.Cancel(self.turnTimer)
    self.turnTimer, self.toAct = nil, nil
    for i = 1, self.maxSeats do
        local p = self.seats[i]
        if p then p.bet = 0 end
    end
    self.currentBet, self.minRaise = 0, self.bb

    if self:Count(alive) <= 1 then return self:Award() end
    if self.phase == "river" then return self:Showdown() end

    if self:Count(canAct) <= 1 then
        -- Tout le monde (ou presque) est à tapis : on dévoile et on déroule le tableau
        self:Reveal()
        self:Changed()
        local function step()
            self.stepTimer = nil
            if self.phase == "river" then return self:Showdown() end
            self:DealStreet()
            self:Changed()
            self.stepTimer = self.io.After(1.4, step)
        end
        self.stepTimer = self.io.After(1.2, step)
        return
    end

    self:DealStreet()
    for i = 1, self.maxSeats do
        local p = self.seats[i]
        if p and canAct(p) then
            p.needAct, p.canRaise, p.acted, p.act = true, true, false, nil
        end
    end
    self:SetTurn(self:NextSeat(self.dealer, function(p) return canAct(p) and p.needAct end))
end

function E:DealStreet()
    table.remove(self.deck) -- carte brûlée
    local n = (self.phase == "preflop") and 3 or 1
    for _ = 1, n do self.board[#self.board + 1] = table.remove(self.deck) end
    self.phase = ({ preflop = "flop", flop = "turn", turn = "river" })[self.phase]
    self.io.Event("board", self.phase, table.concat(self.board))
end

function E:HandValue(p)
    local cards = { p.hole[1], p.hole[2] }
    for _, c in ipairs(self.board) do cards[#cards + 1] = c end
    return Cards.Evaluate(cards)
end

function E:Reveal()
    for i = 1, self.maxSeats do
        local p = self.seats[i]
        if p and alive(p) then
            local _, cat, keys = self:HandValue(p)
            self.io.Event("show", i, p.name, p.hole[1], p.hole[2], cat, keys)
        end
    end
    self.revealed = true
end

function E:Showdown()
    self.phase = "showdown"
    self:Reveal()
    self:Award()
end

-- Pots principal et annexes : chaque niveau de tapis crée un pot
function E:BuildPots()
    local levels, seen = {}, {}
    for i = 1, self.maxSeats do
        local p = self.seats[i]
        if p and alive(p) and p.committed > 0 and not seen[p.committed] then
            seen[p.committed] = true
            levels[#levels + 1] = p.committed
        end
    end
    table.sort(levels)
    local pots, prev, total = {}, 0, 0
    for _, lv in ipairs(levels) do
        local amount, elig = 0, {}
        for i = 1, self.maxSeats do
            local p = self.seats[i]
            if p and p.committed > 0 then
                amount = amount + math.min(p.committed, lv) - math.min(p.committed, prev)
                if alive(p) and p.committed >= lv then elig[#elig + 1] = i end
            end
        end
        if amount > 0 then pots[#pots + 1] = { amount = amount, elig = elig } end
        total = total + amount
        prev = lv
    end
    local all = 0
    for i = 1, self.maxSeats do
        local p = self.seats[i]
        if p then all = all + p.committed end
    end
    if all > total and #pots > 0 then pots[#pots].amount = pots[#pots].amount + (all - total) end
    return pots
end

function E:Award()
    self.io.Cancel(self.stepTimer)
    self.stepTimer = nil
    self.io.Cancel(self.turnTimer)
    self.turnTimer, self.toAct = nil, nil
    local won, desc = {}, {}
    local aliveCount = self:Count(alive)

    if aliveCount == 1 then
        local w = self:NextSeat(0, alive)
        local total = 0
        for i = 1, self.maxSeats do
            local p = self.seats[i]
            if p then total = total + p.committed end
        end
        won[w] = total
    else
        local value = {}
        for i = 1, self.maxSeats do
            local p = self.seats[i]
            if p and alive(p) then
                local v, cat, keys = self:HandValue(p)
                value[i] = v
                desc[i] = { cat, keys }
            end
        end
        for _, pot in ipairs(self:BuildPots()) do
            local best = -1
            for _, i in ipairs(pot.elig) do
                if value[i] > best then best = value[i] end
            end
            local winners = {}
            for k = 1, self.maxSeats do -- ordre : à gauche du donneur
                local i = ((self.dealer - 1 + k) % self.maxSeats) + 1
                for _, e in ipairs(pot.elig) do
                    if e == i and value[i] == best then winners[#winners + 1] = i end
                end
            end
            local share = math.floor(pot.amount / #winners)
            local rest = pot.amount - share * #winners
            for n, i in ipairs(winners) do
                won[i] = (won[i] or 0) + share + ((n <= rest) and 1 or 0)
            end
        end
    end

    for i = 1, self.maxSeats do
        local p = self.seats[i]
        if p then
            if won[i] and won[i] > 0 then
                if not p.gone then p.stack = p.stack + won[i] end
                local d = desc[i]
                self.io.Event("win", i, p.name, won[i], d and d[1], d and d[2])
            end
            p.bet, p.committed = 0, 0
        end
    end
    self.phase = "done"
    self:Changed()
    if self.running then self:ScheduleNext(self.nextHandDelay) end
end

-- ------------------------------------------------------------------
-- Infos publiques pour l'affichage
-- ------------------------------------------------------------------
function E:Pots()
    local total, current = 0, 0
    for i = 1, self.maxSeats do
        local p = self.seats[i]
        if p then
            total = total + p.committed
            current = current + p.bet
        end
    end
    return total, total - current
end
