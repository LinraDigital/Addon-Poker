local ADDON, ns = ...
local Cards = ns.Cards
local B = {}
ns.Bots = B

B.NAMES = { "Graakor", "Elunara", "Mok'Rath", "Valerian", "Thorgar", "Sylthae", "Brannok", "Zul'Kesh" }
B.CLASSES = { "WARRIOR", "PRIEST", "SHAMAN", "PALADIN", "HUNTER", "MAGE", "ROGUE", "WARLOCK", "DRUID" }

-- Force de la main de départ, entre 0 et 1 (inspirée de la formule de Chen)
local function preflopStrength(c1, c2)
    local r1, s1 = Cards.Parse(c1)
    local r2, s2 = Cards.Parse(c2)
    local hi, lo = math.max(r1, r2), math.min(r1, r2)
    local base = ({ [14] = 10, [13] = 8, [12] = 7, [11] = 6 })[hi] or hi / 2
    if r1 == r2 then base = math.max(5, base * 2) end
    if s1 == s2 then base = base + 2 end
    local gap = hi - lo - 1
    if r1 ~= r2 then
        if gap == 1 then base = base - 1 elseif gap == 2 then base = base - 2
        elseif gap == 3 then base = base - 4 elseif gap >= 4 then base = base - 5 end
        if gap <= 1 and hi < 12 then base = base + 1 end
    end
    return math.max(0, math.min(1, base / 20))
end

local function postflopStrength(engine, p)
    local _, cat, keys = engine:HandValue(p)
    local s = ({ 0.12, 0.42, 0.68, 0.8, 0.86, 0.9, 0.95, 0.99, 1 })[cat]
    if cat == 2 then
        -- paire avec le tableau : meilleure si c'est la plus haute carte du board
        local top = 0
        for _, c in ipairs(engine.board) do
            local r = Cards.Parse(c)
            if r > top then top = r end
        end
        if keys[1] >= top then s = 0.58 elseif keys[1] < top then s = 0.4 end
        local r1 = Cards.Parse(p.hole[1])
        local r2 = Cards.Parse(p.hole[2])
        if r1 ~= keys[1] and r2 ~= keys[1] then s = 0.22 end -- paire uniquement sur le tableau
    end
    return s
end

function B.Decide(engine, i)
    local p = engine.seats[i]
    local rnd = engine.io.Random
    local toCall = engine.currentBet - p.bet
    local pot = engine:Pots()
    local strength
    if #engine.board == 0 then
        strength = preflopStrength(p.hole[1], p.hole[2])
    else
        strength = postflopStrength(engine, p)
    end
    strength = strength + (rnd(21) - 11) / 100 -- un peu d'humeur

    local maxTo = p.bet + p.stack
    local minTo = engine.currentBet + engine.minRaise
    local bluff = rnd(100) <= 6

    if (strength > 0.72 or bluff) and p.canRaise and maxTo > engine.currentBet then
        local target = engine.currentBet + math.floor((pot + toCall) * (0.5 + rnd(50) / 100))
        target = math.max(minTo, target)
        if strength > 0.93 and rnd(3) == 1 then target = maxTo end
        if target >= maxTo then return "A" end
        return "R", target
    end

    if toCall <= 0 then
        if strength > 0.5 and p.canRaise and rnd(100) <= 35 then
            local target = math.max(engine.bb, math.floor(pot * 0.5))
            if target >= maxTo then return "A" end
            return "R", target
        end
        return "K"
    end

    local odds = toCall / (pot + toCall)
    if strength >= odds + 0.08 or (toCall <= engine.bb and strength > 0.25) then
        return "C"
    end
    return "F"
end
