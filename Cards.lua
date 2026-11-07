local ADDON, ns = ...
local C = {}
ns.Cards = C

-- Une carte = 2 caractères : rang "23456789TJQKA" + couleur "shdc" (pique, cœur, carreau, trèfle)
local RANKS = "23456789TJQKA"
local SUITS = "shdc"
C.RANKS, C.SUITS = RANKS, SUITS

local RANKVAL, SUITIDX = {}, {}
for i = 1, 13 do RANKVAL[RANKS:sub(i, i)] = i + 1 end
for i = 1, 4 do SUITIDX[SUITS:sub(i, i)] = i end

C.RANK_LABEL = { [2] = "2", [3] = "3", [4] = "4", [5] = "5", [6] = "6", [7] = "7", [8] = "8",
    [9] = "9", [10] = "10", [11] = "J", [12] = "Q", [13] = "K", [14] = "A" }

function C.Parse(card)
    return RANKVAL[card:sub(1, 1)], SUITIDX[card:sub(2, 2)]
end

function C.Valid(card)
    return type(card) == "string" and #card == 2 and RANKVAL[card:sub(1, 1)] ~= nil and SUITIDX[card:sub(2, 2)] ~= nil
end

-- Coordonnées de texture dans Media\cards.tga (2048x1024, cellules 128x176)
function C.TexCoord(card)
    local col, row
    if not card or card == "??" then
        col, row = 0, 4
    else
        local r, s = C.Parse(card)
        col, row = r - 2, s - 1
    end
    local l, t = col * 128 / 2048, row * 176 / 1024
    return l, l + 128 / 2048, t, t + 176 / 1024
end

-- Petite image de la carte insérable dans du texte (journal)
function C.Inline(card, h)
    h = h or 16
    local l, r, t, b = C.TexCoord(card)
    return string.format("|T%scards.tga:%d:%d:0:0:2048:1024:%d:%d:%d:%d|t",
        ns.MEDIA, h, math.floor(h * 0.73 + 0.5), l * 2048, r * 2048, t * 1024, b * 1024)
end

function C.NewDeck()
    local d = {}
    for s = 1, 4 do
        for r = 1, 13 do d[#d + 1] = RANKS:sub(r, r) .. SUITS:sub(s, s) end
    end
    return d
end

-- Mélange de Fisher-Yates
function C.Shuffle(d, rnd)
    rnd = rnd or math.random
    for i = #d, 2, -1 do
        local j = rnd(i)
        d[i], d[j] = d[j], d[i]
    end
    return d
end

-- ------------------------------------------------------------------
-- Évaluation de la meilleure main de 5 cartes parmi 5 à 7
-- Retourne : score comparable (plus grand = meilleur), catégorie (1..9), rangs clés
-- Catégories : 1 carte haute, 2 paire, 3 double paire, 4 brelan, 5 quinte,
--              6 couleur, 7 full, 8 carré, 9 quinte flush
-- ------------------------------------------------------------------
local function score(cat, t)
    local v = cat
    for i = 1, 5 do v = v * 15 + (t[i] or 0) end
    return v
end

local function straightHigh(present)
    for hi = 14, 5, -1 do
        local ok = true
        for k = 0, 4 do
            local r = hi - k
            if r == 1 then r = 14 end
            if not present[r] then ok = false break end
        end
        if ok then return hi end
    end
    return nil
end

function C.Evaluate(cards)
    local cnt, bySuit, present = {}, { {}, {}, {}, {} }, {}
    for r = 2, 14 do cnt[r] = 0 end
    for _, card in ipairs(cards) do
        local r, s = C.Parse(card)
        cnt[r] = cnt[r] + 1
        present[r] = true
        local t = bySuit[s]
        t[#t + 1] = r
    end

    local flush
    for s = 1, 4 do
        if #bySuit[s] >= 5 then
            flush = bySuit[s]
            table.sort(flush, function(a, b) return a > b end)
        end
    end

    if flush then
        local fp = {}
        for _, r in ipairs(flush) do fp[r] = true end
        local h = straightHigh(fp)
        if h then return score(9, { h }), 9, { h } end
    end

    local quads, trips, pairs, singles = {}, {}, {}, {}
    for r = 14, 2, -1 do
        local n = cnt[r]
        if n == 4 then quads[#quads + 1] = r
        elseif n == 3 then trips[#trips + 1] = r
        elseif n == 2 then pairs[#pairs + 1] = r
        elseif n == 1 then singles[#singles + 1] = r end
    end

    local function highestExcept(...)
        local ex = {}
        for _, v in ipairs({ ... }) do ex[v] = true end
        for r = 14, 2, -1 do
            if cnt[r] > 0 and not ex[r] then return r end
        end
        return 0
    end

    if quads[1] then
        local k = highestExcept(quads[1])
        return score(8, { quads[1], k }), 8, { quads[1], k }
    end

    if trips[1] and (trips[2] or pairs[1]) then
        local second = math.max(trips[2] or 0, pairs[1] or 0)
        return score(7, { trips[1], second }), 7, { trips[1], second }
    end

    if flush then
        local t = { flush[1], flush[2], flush[3], flush[4], flush[5] }
        return score(6, t), 6, t
    end

    local h = straightHigh(present)
    if h then return score(5, { h }), 5, { h } end

    if trips[1] then
        local k = {}
        for r = 14, 2, -1 do
            if cnt[r] > 0 and r ~= trips[1] then k[#k + 1] = r end
            if #k == 2 then break end
        end
        local t = { trips[1], k[1] or 0, k[2] or 0 }
        return score(4, t), 4, t
    end

    if pairs[2] then
        local k = highestExcept(pairs[1], pairs[2])
        local t = { pairs[1], pairs[2], k }
        return score(3, t), 3, t
    end

    if pairs[1] then
        local k = {}
        for r = 14, 2, -1 do
            if cnt[r] > 0 and r ~= pairs[1] then k[#k + 1] = r end
            if #k == 3 then break end
        end
        local t = { pairs[1], k[1] or 0, k[2] or 0, k[3] or 0 }
        return score(2, t), 2, t
    end

    local t = {}
    for r = 14, 2, -1 do
        if cnt[r] > 0 then t[#t + 1] = r end
        if #t == 5 then break end
    end
    return score(1, t), 1, t
end

-- Texte court et lisible : « Full (K par 7) », « Paire (A) »…
function C.Describe(cat, keys)
    local L = ns.L
    local R = C.RANK_LABEL
    if cat == 9 and keys[1] == 14 then return L.HAND_10 end
    local name = L["HAND_" .. cat]
    if cat == 3 or cat == 7 then
        return string.format("%s (%s / %s)", name, R[keys[1]], R[keys[2]])
    elseif cat == 6 then
        return string.format("%s (%s)", name, R[keys[1]])
    else
        return string.format("%s (%s)", name, R[keys[1]])
    end
end
