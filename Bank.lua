local ADDON, ns = ...
local L, U = ns.L, ns.U

--[[
  Bourse fictive du personnage + dette envers l'aubergiste.
  Au poker on ne joue que ce qu'on a sur la table : pas de dette pendant une main.
  La dette n'existe qu'en dehors : si la bourse ne suffit pas pour une cave ou une recave,
  on peut emprunter à l'aubergiste (plafonné). Les gains récupérés en quittant la table
  remboursent la dette en priorité.
]]
local B = {}
ns.Bank = B

B.START = 1000
B.MAX_DEBT = 5000

function B.Init()
    LDPokerCharDB = LDPokerCharDB or {}
    local db = LDPokerCharDB
    if db.purse == nil then db.purse = B.START end
    db.debt = db.debt or 0
    db.stats = db.stats or { hands = 0, bestPot = 0, won = 0 }
end

function B.Purse() return LDPokerCharDB.purse end
function B.Debt() return LDPokerCharDB.debt end

local function changed()
    if ns.UI and ns.UI.RefreshPurse then ns.UI.RefreshPurse() end
end

StaticPopupDialogs["LDPOKER_LOAN"] = {
    text = L.LOAN_TEXT,
    button1 = L.LOAN_OK,
    button2 = L.CANCEL,
    OnAccept = function(_, data) if data and data.yes then data.yes() end end,
    OnCancel = function(_, data) if data and data.no then data.no() end end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- Retire `amount` de la bourse, en proposant un emprunt si besoin. cb(ok)
function B.Spend(amount, cb)
    local db = LDPokerCharDB
    amount = math.floor(amount)
    if db.purse >= amount then
        db.purse = db.purse - amount
        changed()
        return cb(true)
    end
    local need = amount - db.purse
    if db.debt + need > B.MAX_DEBT then
        U.Print(L.ERR_NOMONEY)
        return cb(false)
    end
    StaticPopup_Show("LDPOKER_LOAN", U.Money(need), U.Money(db.debt), {
        yes = function()
            db.debt = db.debt + need
            db.purse = 0
            changed()
            cb(true)
        end,
        no = function() cb(false) end,
    })
end

-- Jetons rendus par la table : remboursent d'abord la dette.
function B.Receive(amount, quiet)
    local db = LDPokerCharDB
    amount = math.max(0, math.floor(amount or 0))
    if amount == 0 then return end
    if not quiet then U.Print(string.format(L.CASHOUT, U.Money(amount))) end
    local repay = math.min(db.debt, amount)
    db.debt = db.debt - repay
    db.purse = db.purse + amount - repay
    if repay > 0 then U.Print(string.format(L.REPAID, U.Money(repay))) end
    changed()
end

function B.Repay()
    local db = LDPokerCharDB
    local repay = math.min(db.debt, db.purse)
    if repay <= 0 then return end
    db.debt = db.debt - repay
    db.purse = db.purse - repay
    U.Print(string.format(L.REPAID, U.Money(repay)))
    changed()
end

function B.Reset()
    LDPokerCharDB.purse = B.START
    LDPokerCharDB.debt = 0
    U.Print(string.format(L.RESET_DONE, U.Money(B.START)))
    changed()
end
