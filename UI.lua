local ADDON, ns = ...
local L, U, Cards = ns.L, ns.U, ns.Cards

local UI = {}
ns.UI = UI

local W, H = 1000, 563         -- taille logique de la fenêtre (même ratio que l'image de la table)
local M = ns.MEDIA
local GOLD = { 1, 0.82, 0.30 }
local BETTING = { preflop = true, flop = true, turn = true, river = true }

-- Sprites dans Media\ui.tga (512x512)
local SPR = {
    RED = { 0, 0, 256, 96 }, DARK = { 256, 0, 128, 48 }, CHIP = { 384, 0, 64, 64 },
    DEALER = { 448, 0, 64, 64 }, TIMER = { 384, 64, 64, 64 }, KNOB = { 448, 64, 64, 64 },
    TRACK = { 0, 96, 256, 32 }, FILL = { 0, 128, 256, 32 }, VALUE = { 0, 160, 256, 64 },
    POT = { 256, 160, 256, 64 },
}

-- Places à l'écran (fractions de la fenêtre), en partant de moi en bas puis dans le sens horaire
local SLOTS = {
    { 0.476, 0.781, big = true, bet = { 0.395, 0.655 }, dealer = { 0.336, 0.730 } },
    { 0.147, 0.560, bet = { 0.270, 0.575 }, dealer = { 0.250, 0.515 } },
    { 0.154, 0.338, bet = { 0.270, 0.375 }, dealer = { 0.250, 0.290 } },
    { 0.350, 0.204, bet = { 0.290, 0.300 }, dealer = { 0.247, 0.204 } },
    { 0.658, 0.204, bet = { 0.680, 0.300 }, dealer = { 0.765, 0.204 } },
    { 0.860, 0.338, bet = { 0.700, 0.375 }, dealer = { 0.752, 0.290 } },
    { 0.860, 0.560, bet = { 0.700, 0.575 }, dealer = { 0.752, 0.515 } },
}

-- ------------------------------------------------------------------
-- Outils
-- ------------------------------------------------------------------
local function viewBB()
    local v = ns.Net and ns.Net.view
    return v and math.max(1, v.bb) or 1
end

local function Sprite(parent, layer, spr)
    local t = parent:CreateTexture(nil, layer or "ARTWORK")
    t:SetTexture(M .. "ui.tga")
    t:SetTexCoord(spr[1] / 512, (spr[1] + spr[3]) / 512, spr[2] / 512, (spr[2] + spr[4]) / 512)
    return t
end

local function Text(parent, size, color, flags, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, size, flags or "OUTLINE")
    if color then fs:SetTextColor(color[1], color[2], color[3]) end
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 0.9)
    return fs
end

local function At(region, parent, fx, fy, point)
    region:ClearAllPoints()
    region:SetPoint(point or "CENTER", parent, "TOPLEFT", fx * W, -fy * H)
end

local function Button(parent, spr, w, h, label, size, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h)
    b.bg = Sprite(b, "BACKGROUND", spr)
    b.bg:SetAllPoints()
    local hl = Sprite(b, "HIGHLIGHT", spr)
    hl:SetAllPoints()
    hl:SetBlendMode("ADD")
    hl:SetAlpha(0.3)
    b.text = Text(b, size or 13, { 1, 1, 1 })
    b.text:SetPoint("CENTER", 0, 1)
    b.text:SetText(label or "")
    b:SetScript("OnMouseDown", function(self)
        if self:IsEnabled() then self.text:SetPoint("CENTER", 1, 0) end
    end)
    b:SetScript("OnMouseUp", function(self) self.text:SetPoint("CENTER", 0, 1) end)
    b:SetScript("OnClick", function(self)
        U.Sound("click")
        if onClick then onClick(self) end
    end)
    function b:SetActive(on)
        if on then
            self:Enable()
            self.bg:SetDesaturated(false)
            self:SetAlpha(1)
        else
            self:Disable()
            self.bg:SetDesaturated(true)
            self:SetAlpha(0.55)
        end
    end
    return b
end

-- Bouton rouge standard de World of Warcraft (même interface que Button ci-dessus)
local function NativeButton(parent, w, h, label, onClick, template)
    local ok, b = false, nil
    if template then ok, b = pcall(CreateFrame, "Button", nil, parent, template) end
    if not ok or not b then b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate") end
    b:SetSize(w, h)
    b:SetText(label or "")
    b.text = b:GetFontString()
    if b.text then
        b.text:SetFont(STANDARD_TEXT_FONT, 13, "")
        b.text:SetWidth(w - 12)
    end
    b:SetScript("OnClick", function(self)
        U.Sound("click")
        if onClick then onClick(self) end
    end)
    function b:SetActive(on)
        if on then self:Enable() else self:Disable() end
    end
    return b
end

-- Bordures d'origine de World of Warcraft (BackdropTemplate)
local function NativeBorder(parent, file, edge, inset, level, outset)
    local ok, bf = pcall(CreateFrame, "Frame", nil, parent, "BackdropTemplate")
    if not ok or not bf then bf = CreateFrame("Frame", nil, parent) end
    if not bf.SetBackdrop then return end
    outset = outset or 0
    bf:SetPoint("TOPLEFT", parent, "TOPLEFT", -outset, outset)
    bf:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", outset, -outset)
    bf:SetFrameLevel(parent:GetFrameLevel() + (level or 1))
    bf:EnableMouse(false)
    bf:SetBackdrop({ edgeFile = file, edgeSize = edge, insets = { left = inset, right = inset, top = inset, bottom = inset } })
    return bf
end

-- Cadre de la fenêtre : bordure des boîtes de dialogue de WoW
local function BuildFrameBorder(f)
    NativeBorder(f, "Interface\\DialogFrame\\UI-DialogBox-Border", 32, 11, 30, 10)
end

local function Panel(parent, w, h)
    local p = CreateFrame("Frame", nil, parent)
    p:SetSize(w, h)
    local bg = p:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.03, 0.04, 0.07, 0.9)
    NativeBorder(p, "Interface\\Tooltips\\UI-Tooltip-Border", 16, 5, 1, 2)
    return p
end
local function Input(parent, w, default)
    local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    e:SetSize(w, 20)
    e:SetAutoFocus(false)
    e:SetNumeric(true)
    e:SetMaxLetters(7)
    e:SetText(tostring(default or ""))
    e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return e
end

local function SetCard(tex, card)
    tex:SetTexCoord(Cards.TexCoord(card))
    tex:Show()
end

-- ------------------------------------------------------------------
-- Construction
-- ------------------------------------------------------------------
local f, seats, board, betFrames, potPanel, actions, lobby, logFrame, flashText, centerText
local toolbar = {}

local function BuildSeat(slot)
    local cfg = SLOTS[slot]
    local w, h = (cfg.big and 240 or 172), (cfg.big and 85 or 61)
    local s = CreateFrame("Frame", nil, f)
    s:SetSize(w, h)
    At(s, f, cfg[1], cfg[2])
    s:SetFrameLevel(f:GetFrameLevel() + 5)

    -- cartes derrière la plaque (elles dépassent par le haut)
    local cw, ch = (cfg.big and 58 or 30), (cfg.big and 80 or 41)
    s.cards = {}
    for k = 1, 2 do
        local c = s:CreateTexture(nil, "BACKGROUND")
        c:SetTexture(M .. "cards.tga")
        c:SetSize(cw, ch)
        if cfg.big then
            c:SetPoint("BOTTOMLEFT", s, "TOPLEFT", w * 0.42 + (k - 1) * (cw + 4), -h * 0.30)
        else
            c:SetPoint("BOTTOMLEFT", s, "TOPLEFT", w * 0.56 + (k - 1) * (cw * 0.62), -h * 0.30)
        end
        c:Hide()
        s.cards[k] = c
    end

    s.plate = s:CreateTexture(nil, "ARTWORK")
    s.plate:SetTexture(M .. "plate.tga")
    s.plate:SetAllPoints()
    s.glow = s:CreateTexture(nil, "OVERLAY")
    s.glow:SetTexture(M .. "plate.tga")
    s.glow:SetAllPoints()
    s.glow:SetBlendMode("ADD")
    s.glow:SetVertexColor(1, 0.8, 0.3)
    s.glow:Hide()

    -- portrait : modèle 3D si le joueur est visible, sinon portrait ou icône de classe
    local px, py, pw, ph = w * 0.032, h * 0.095, w * 0.300, h * 0.80
    s.portrait = s:CreateTexture(nil, "ARTWORK", nil, 1)
    s.portrait:SetPoint("TOPLEFT", px, -py)
    s.portrait:SetSize(pw, ph)
    s.model = CreateFrame("PlayerModel", nil, s)
    s.model:SetPoint("TOPLEFT", px, -py)
    s.model:SetSize(pw, ph)
    s.model:Hide()

    s.name = Text(s, cfg.big and 18 or 13, { 1, 1, 1 })
    s.name:SetPoint("CENTER", s, "TOPLEFT", w * 0.615, -h * 0.36)
    s.stack = Text(s, cfg.big and 18 or 13, GOLD)
    s.stack:SetPoint("CENTER", s, "TOPLEFT", w * 0.615, -h * 0.66)

    s.act = Text(s, cfg.big and 13 or 11, { 0.95, 0.95, 0.85 })
    s.act:SetPoint("TOP", s, "BOTTOM", 0, 1)

    -- minuteur sur le portrait
    s.timer = CreateFrame("Frame", nil, s)
    s.timer:SetSize(cfg.big and 32 or 24, cfg.big and 32 or 24)
    s.timer:SetPoint("CENTER", s, "BOTTOMLEFT", w * 0.05, h * 0.12)
    s.timer:SetFrameLevel(s:GetFrameLevel() + 3)
    local tt = Sprite(s.timer, "ARTWORK", SPR.TIMER)
    tt:SetAllPoints()
    s.timer.text = Text(s.timer, cfg.big and 14 or 11, { 1, 1, 1 })
    s.timer.text:SetPoint("CENTER", 0, 0)
    s.timer:Hide()

    -- gain flottant
    s.float = Text(s, cfg.big and 20 or 16, { 0.4, 1, 0.4 })
    s.float:SetPoint("BOTTOM", s, "TOP", 0, cfg.big and 70 or 30)
    s.float:Hide()

    -- mise devant le joueur
    local b = CreateFrame("Frame", nil, f)
    b:SetSize(90, 22)
    At(b, f, cfg.bet[1], cfg.bet[2])
    b:SetFrameLevel(f:GetFrameLevel() + 4)
    local chip = Sprite(b, "ARTWORK", SPR.CHIP)
    chip:SetSize(22, 22)
    chip:SetPoint("LEFT", 0, 0)
    b.text = Text(b, 13, { 1, 1, 1 })
    b.text:SetPoint("LEFT", chip, "RIGHT", 3, 0)
    b:Hide()
    s.betFrame = b

    s.dealer = Sprite(f, "OVERLAY", SPR.DEALER)
    s.dealer:SetSize(22, 22)
    At(s.dealer, f, cfg.dealer[1], cfg.dealer[2])
    s.dealer:Hide()

    s:Hide()
    return s
end

local function BuildBoard()
    board = {}
    for k = 1, 5 do
        local c = f:CreateTexture(nil, "ARTWORK")
        c:SetTexture(M .. "cards.tga")
        c:SetSize(56, 77)
        At(c, f, 0.5 + (k - 3) * 0.062, 0.462)
        c:Hide()
        board[k] = c
    end

    potPanel = CreateFrame("Frame", nil, f)
    potPanel:SetSize(300, 42)
    At(potPanel, f, 0.5, 0.338)
    local bg = Sprite(potPanel, "BACKGROUND", SPR.POT)
    bg:SetAllPoints()
    local chip = Sprite(potPanel, "ARTWORK", SPR.CHIP)
    chip:SetSize(34, 34)
    chip:SetPoint("CENTER", 0, 0)
    potPanel.l1 = Text(potPanel, 11, { 0.9, 0.9, 0.9 })
    potPanel.l1:SetPoint("CENTER", -82, 8)
    potPanel.l1:SetText(L.POT_TOTAL)
    potPanel.v1 = Text(potPanel, 16, { 1, 1, 1 })
    potPanel.v1:SetPoint("CENTER", -82, -8)
    potPanel.l2 = Text(potPanel, 11, { 0.9, 0.9, 0.9 })
    potPanel.l2:SetPoint("CENTER", 82, 8)
    potPanel.l2:SetText(L.POT_MAIN)
    potPanel.v2 = Text(potPanel, 16, { 1, 1, 1 })
    potPanel.v2:SetPoint("CENTER", 82, -8)
    potPanel:Hide()

    centerText = Text(f, 15, { 1, 0.92, 0.7 })
    At(centerText, f, 0.5, 0.60)
    centerText:SetWidth(520)

    flashText = Text(f, 26, GOLD)
    At(flashText, f, 0.5, 0.25)
    flashText:Hide()
end

local function BuildActions()
    actions = CreateFrame("Frame", nil, f)
    actions:SetSize(395, 135)
    actions:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 8)
    actions:SetFrameLevel(f:GetFrameLevel() + 10)

    -- présélections (en % du pot)
    local presets = { { "25%", 0.25 }, { "35%", 0.35 }, { "50%", 0.5 }, { "65%", 0.65 }, { "75%", 0.75 },
        { "80%", 0.8 }, { L.POT, 1 }, { L.ALLIN, "ALL" } }
    actions.presets = {}
    for k, pr in ipairs(presets) do
        local b = Button(actions, SPR.DARK, 47, 22, pr[1], 11, function() UI.Preset(pr[2]) end)
        b:SetPoint("TOPLEFT", (k - 1) * 49.5, 0)
        actions.presets[k] = b
    end

    -- barre de mise
    local sl = CreateFrame("Slider", nil, actions)
    sl:SetOrientation("HORIZONTAL")
    sl:SetSize(285, 16)
    sl:SetPoint("TOPLEFT", 2, -38)
    local track = Sprite(sl, "BACKGROUND", SPR.TRACK)
    track:SetAllPoints()
    sl.fill = Sprite(sl, "ARTWORK", SPR.FILL)
    sl.fill:SetPoint("LEFT")
    sl.fill:SetHeight(16)
    local knob = Sprite(sl, "OVERLAY", SPR.KNOB)
    knob:SetSize(28, 28)
    sl:SetThumbTexture(knob)
    sl:SetMinMaxValues(0, 1)
    sl:SetValueStep(1)
    if sl.SetObeyStepOnDrag then sl:SetObeyStepOnDrag(true) end
    sl:SetScript("OnValueChanged", function(self, value)
        UI.SetRaise(math.floor(value + 0.5), true)
    end)
    sl:EnableMouseWheel(true)
    sl:SetScript("OnMouseWheel", function(self, d)
        local v = viewBB()
        self:SetValue(self:GetValue() + d * v)
    end)
    actions.slider = sl

    -- montant
    local box = CreateFrame("Frame", nil, actions)
    box:SetSize(98, 28)
    box:SetPoint("TOPRIGHT", 0, -32)
    local bbg = Sprite(box, "BACKGROUND", SPR.VALUE)
    bbg:SetAllPoints()
    local coin = box:CreateTexture(nil, "ARTWORK")
    coin:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
    coin:SetSize(13, 13)
    coin:SetPoint("RIGHT", -7, 0)
    local eb = CreateFrame("EditBox", nil, box)
    eb:SetPoint("TOPLEFT", 6, 0)
    eb:SetPoint("BOTTOMRIGHT", coin, "BOTTOMLEFT", -2, -7)
    eb:SetFont(STANDARD_TEXT_FONT, 13, "")
    eb:SetJustifyH("RIGHT")
    eb:SetAutoFocus(false)
    eb:SetNumeric(true)
    eb:SetMaxLetters(8)
    eb:SetScript("OnEnterPressed", function(self)
        UI.SetRaise(tonumber(self:GetText()) or 0)
        self:ClearFocus()
    end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    actions.amount = eb

    actions.fold = NativeButton(actions, 120, 40, L.FOLD, function() UI.Do("F") end)
    actions.fold:SetPoint("BOTTOMLEFT", 0, 0)
    actions.call = NativeButton(actions, 128, 40, L.CALL, function() UI.Do("C") end)
    actions.call:SetPoint("BOTTOM", 4, 0)
    actions.raise = NativeButton(actions, 128, 40, L.RAISE, function() UI.Do("R") end)
    actions.raise:SetPoint("BOTTOMRIGHT", 0, 0)
    actions:Hide()
end

local function BuildLobby()
    lobby = Panel(f, 560, 250)
    At(lobby, f, 0.5, 0.47)
    lobby:SetFrameLevel(f:GetFrameLevel() + 20)

    local title = Text(lobby, 18, GOLD)
    title:SetPoint("TOPLEFT", 18, -14)
    title:SetText(L.CREATE_TABLE)

    local function row(label, y)
        local t = Text(lobby, 12, { 0.92, 0.92, 0.92 })
        t:SetPoint("TOPLEFT", 20, y)
        t:SetText(label)
        return t
    end
    local db = LDPokerDB
    row(L.SMALL_BLIND, -50)
    lobby.sb = Input(lobby, 70, db.sb or 5)
    lobby.sb:SetPoint("TOPLEFT", 170, -46)
    row(L.BIG_BLIND, -78)
    lobby.bb = Input(lobby, 70, db.bb or 10)
    lobby.bb:SetPoint("TOPLEFT", 170, -74)
    row(L.BUYIN, -106)
    lobby.buyin = Input(lobby, 70, db.buyin or 500)
    lobby.buyin:SetPoint("TOPLEFT", 170, -102)
    lobby.sb:SetScript("OnTextChanged", function(self, user)
        if user then lobby.bb:SetText(tostring((tonumber(self:GetText()) or 0) * 2)) end
    end)

    lobby.prox = CreateFrame("CheckButton", nil, lobby, "UICheckButtonTemplate")
    lobby.prox:SetSize(24, 24)
    lobby.prox:SetPoint("TOPLEFT", 14, -128)
    lobby.prox:SetChecked(db.proximity ~= false)
    local pl = Text(lobby, 12, { 0.92, 0.92, 0.92 })
    pl:SetPoint("LEFT", lobby.prox, "RIGHT", 2, 0)
    pl:SetText(L.PROXIMITY)

    lobby.create = NativeButton(lobby, 200, 46, L.CREATE_TABLE, function()
        local sb = math.max(1, tonumber(lobby.sb:GetText()) or 5)
        local bb = math.max(sb, tonumber(lobby.bb:GetText()) or sb * 2)
        local buyin = math.max(bb * 10, tonumber(lobby.buyin:GetText()) or bb * 50)
        db.sb, db.bb, db.buyin = sb, bb, buyin
        db.proximity = lobby.prox:GetChecked() and true or false
        ns.Net.CreateTable({ sb = sb, bb = bb, buyin = buyin, proximity = db.proximity })
    end)
    lobby.create:SetPoint("BOTTOMLEFT", 18, 16)

    -- séparation
    local sep = lobby:CreateTexture(nil, "BORDER")
    sep:SetColorTexture(0.86, 0.66, 0.26, 0.6)
    sep:SetWidth(1)
    sep:SetPoint("TOP", 0, -14)
    sep:SetPoint("BOTTOM", 0, 14)

    local t2 = Text(lobby, 18, GOLD)
    t2:SetPoint("TOPLEFT", 298, -14)
    t2:SetText(L.TABLES_NEARBY)
    -- liste vide : bouton « Rechercher » sous le texte ; liste non vide : icône d'actualisation en haut à droite
    lobby.search = Button(lobby, SPR.DARK, 96, 24, L.REFRESH, 11, function() ns.Net.Search() end)
    lobby.search:SetPoint("TOPLEFT", 298, -100)
    lobby.refresh = Button(lobby, SPR.DARK, 26, 24, "", 11, function() ns.Net.Search() end)
    lobby.refresh:SetPoint("TOPRIGHT", -14, -12)
    local ric = lobby.refresh:CreateTexture(nil, "OVERLAY")
    ric:SetSize(16, 16)
    ric:SetPoint("CENTER")
    ric:SetTexture("Interface\\Buttons\\UI-RefreshButton")
    lobby.refresh:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(L.REFRESH)
        GameTooltip:Show()
    end)
    lobby.refresh:SetScript("OnLeave", function() GameTooltip:Hide() end)
    lobby.refresh:Hide()

    lobby.rows = {}
    for k = 1, 4 do
        local r = CreateFrame("Frame", nil, lobby)
        r:SetSize(250, 40)
        r:SetPoint("TOPLEFT", 296, -46 - (k - 1) * 46)
        r.title = Text(r, 13, { 1, 1, 1 })
        r.title:SetPoint("TOPLEFT", 0, -2)
        r.info = Text(r, 10, { 0.8, 0.8, 0.8 })
        r.info:SetPoint("TOPLEFT", 0, -20)
        r.join = Button(r, SPR.DARK, 74, 26, L.JOIN, 11)
        r.join:SetPoint("RIGHT", 0, 0)
        r:Hide()
        lobby.rows[k] = r
    end
    lobby.empty = Text(lobby, 12, { 0.75, 0.75, 0.75 })
    lobby.empty:SetPoint("TOPLEFT", 298, -54)
    lobby.empty:SetWidth(240)
    lobby.empty:SetJustifyH("LEFT")
    lobby.empty:SetText(L.NO_TABLE)
    lobby.status = Text(lobby, 12, GOLD)
    lobby.status:SetPoint("BOTTOMRIGHT", -16, 18)
end

local function BuildToolbar()
    local x = 14
    local function add(key, label, w, fn)
        local b = Button(f, SPR.DARK, w, 26, label, 11, fn)
        b:SetFrameLevel(f:GetFrameLevel() + 15)
        toolbar[key] = b
        b:Hide()
    end
    add("start", L.START, 86, function() ns.Net.ToggleRunning() end)
    add("bot", L.ADD_BOT, 70, function() ns.Net.AddBot() end)
    add("close", L.CLOSE_TABLE, 120, function() ns.Net.CloseTable() end)
    add("leave", L.LEAVE, 86, function() ns.Net.Leave() end)
    add("rebuy", L.REBUY, 86, function() ns.Net.Rebuy() end)

    local purse = CreateFrame("Frame", nil, f)
    purse:SetSize(330, 24)
    purse:SetPoint("TOPRIGHT", f, "TOPRIGHT", -40, -10)
    purse:SetFrameLevel(f:GetFrameLevel() + 15)
    local bg = purse:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.55)
    purse.text = Text(purse, 12, { 1, 1, 1 })
    purse.text:SetPoint("RIGHT", -8, 0)
    purse.repay = Button(purse, SPR.DARK, 86, 22, L.REPAY, 10, function() ns.Bank.Repay() end)
    purse.repay:SetPoint("RIGHT", purse, "LEFT", -4, 0)
    toolbar.purse = purse

    -- aide : classement des mains avec exemples
    local help = Panel(f, 330, 380)
    help:SetScale(1.3)
    help:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12 / 1.3, -40 / 1.3)
    help:SetFrameLevel(f:GetFrameLevel() + 30)
    local ht = Text(help, 13, GOLD)
    ht:SetPoint("TOPLEFT", 12, -10)
    ht:SetWidth(306)
    ht:SetJustifyH("LEFT")
    ht:SetText(L.RULES_TITLE)
    local examples = {
        { 10, "Ah Kh Qh Jh Th" }, { 9, "9s 8s 7s 6s 5s" }, { 8, "Kc Kd Kh Ks 2d" }, { 7, "Qh Qd Qs 7c 7d" },
        { 6, "Ad Jd 8d 5d 2d" }, { 5, "Tc 9h 8d 7s 6c" }, { 4, "8h 8c 8s Kd 3c" }, { 3, "Jh Jc 4d 4s Ac" },
        { 2, "Ah Ad 9c 6s 3h" }, { 1, "Ks Jd 8c 6h 2s" },
    }
    for k, ex in ipairs(examples) do
        local line = Text(help, 11, { 1, 1, 1 })
        line:SetPoint("TOPLEFT", 12, -32 - (k - 1) * 27)
        local imgs = ""
        for c in ex[2]:gmatch("%S+") do imgs = imgs .. Cards.Inline(c, 22) end
        line:SetText(imgs .. "  " .. L["HAND_" .. ex[1]])
    end
    local tip = Text(help, 11, { 0.85, 0.85, 0.85 })
    tip:SetPoint("BOTTOMLEFT", 12, 10)
    tip:SetWidth(306)
    tip:SetJustifyH("LEFT")
    tip:SetText(L.RULES_TIP)
    help:Hide()
    toolbar.help = help

    local hb = NativeButton(f, 90, 26, L.HELP_BTN, function()
        if help:IsShown() then help:Hide() else help:Show() end
    end)
    hb:SetPoint("TOP", f, "TOP", 0, -10)
    hb:SetFrameLevel(f:GetFrameLevel() + 15)
end

local function LayoutToolbar(list)
    local x = 14
    for _, key in ipairs({ "start", "bot", "close", "leave", "rebuy" }) do toolbar[key]:Hide() end
    for _, key in ipairs(list) do
        local b = toolbar[key]
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", f, "TOPLEFT", x, -10)
        b:Show()
        x = x + b:GetWidth() + 6
    end
end

function UI.Build()
    if f then return end
    f = CreateFrame("Frame", "LDPokerFrame", UIParent)
    f:SetSize(W, H)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        LDPokerDB.point = { p, rp, x, y }
    end)
    local pt = LDPokerDB.point
    if pt then f:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4]) else f:SetPoint("CENTER") end
    f:SetScale(LDPokerDB.scale or 0.9)
    f:Hide()
    tinsert(UISpecialFrames, "LDPokerFrame")

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(M .. "table.tga")
    bg:SetAllPoints()
    BuildFrameBorder(f)

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetFrameLevel(f:GetFrameLevel() + 20)

    seats = {}
    for slot = 1, #SLOTS do seats[slot] = BuildSeat(slot) end
    BuildBoard()
    BuildActions()
    BuildLobby()
    BuildToolbar()

    logFrame = CreateFrame("ScrollingMessageFrame", nil, f)
    logFrame:SetSize(300, 92)
    logFrame:SetPoint("BOTTOMLEFT", 10, 10)
    logFrame:SetFrameLevel(f:GetFrameLevel() + 10)
    logFrame:SetFont(STANDARD_TEXT_FONT, 11, "")
    logFrame:SetJustifyH("LEFT")
    logFrame:SetFading(false)
    logFrame:SetMaxLines(120)
    logFrame:EnableMouseWheel(true)
    logFrame:SetScript("OnMouseWheel", function(self, d)
        if d > 0 then self:ScrollUp() else self:ScrollDown() end
    end)
    UI._w = { lobby = lobby, actions = actions, toolbar = toolbar, seats = seats, board = board, frame = f }


    -- animations légères : halo de la place qui parle, minuteur, textes flottants
    local acc = 0
    f:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        local t = GetTime()
        for _, s in ipairs(seats) do
            if s.glow:IsShown() then s.glow:SetAlpha(0.18 + 0.17 * math.sin(t * 5)) end
            if s.floatUntil then
                local left = s.floatUntil - t
                if left <= 0 then s.float:Hide(); s.floatUntil = nil
                else s.float:SetAlpha(math.min(1, left)) end
            end
        end
        if UI.flashUntil then
            local left = UI.flashUntil - t
            if left <= 0 then flashText:Hide(); UI.flashUntil = nil else flashText:SetAlpha(math.min(1, left)) end
        end
        if acc < 0.2 then return end
        acc = 0
        UI.UpdateTimers()
    end)
end

-- ------------------------------------------------------------------
-- Rafraîchissement
-- ------------------------------------------------------------------
local function slotToSeat(slot, v, base)
    return ((base - 1 + slot - 1) % v.maxSeats) + 1
end

local function seatToSlot(i)
    local v = ns.Net.view
    if not v then return nil end
    local base = ns.Net.MySeat() or 1
    return ((i - base) % v.maxSeats) + 1
end

local function actLabel(code)
    if not code or code == "" then return nil end
    local tag, amount = code:match("^(%a+)(%d*)$")
    if not tag then return nil end
    local label = L["ACT_" .. tag]
    if not label then return nil end
    if amount ~= "" and tag ~= "F" and tag ~= "K" then
        label = label .. " " .. U.Money(amount)
    end
    return label
end

local function UpdatePortrait(s, seat)
    local unit = (not seat.bot) and U.UnitForName(seat.name) or nil
    local visible = unit and UnitIsVisible(unit)
    local key = seat.name .. (visible and ":v" or (unit and ":u" or ":-"))
    if s.portraitKey == key then return end
    s.portraitKey = key
    if visible then
        s.portrait:Hide()
        s.model:Show()
        s.model:ClearModel()
        s.model:SetUnit(unit)
        if s.model.SetPortraitZoom then s.model:SetPortraitZoom(1) end
    else
        s.model:Hide()
        s.portrait:Show()
        if unit then
            SetPortraitTexture(s.portrait, unit)
            s.portrait:SetTexCoord(0.1, 0.9, 0.1, 0.9)
        elseif seat.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[seat.class] then
            s.portrait:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
            local c = CLASS_ICON_TCOORDS[seat.class]
            s.portrait:SetTexCoord(c[1], c[2], c[3], c[4])
        else
            s.portrait:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            s.portrait:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
    end
end

local function RefreshSeats(v)
    local mine = ns.Net.MySeat()
    local base = mine or 1
    local showing = v.phase == "showdown" or v.phase == "done"
    for slot, s in ipairs(seats) do
        local i = slotToSeat(slot, v, base)
        local seat = (slot <= v.maxSeats) and v.seats[i] or nil
        s.seatIndex = i
        if not seat or seat.gone then
            s:Hide()
            s.betFrame:Hide()
            s.dealer:Hide()
        else
            s:Show()
            UpdatePortrait(s, seat)
            s.name:SetText(seat.name)
            s.stack:SetText(U.MoneyPO(seat.stack))
            local active = seat.inHand and not seat.folded
            s:SetAlpha((seat.inHand and seat.folded) and 0.55 or ((not seat.inHand and v.phase ~= "idle") and 0.7 or 1))

            -- texte sous la plaque
            local label, color = nil, { 0.95, 0.95, 0.85 }
            local win = v.wins[i]
            local show = v.shows[i]
            if win then
                label, color = "+" .. U.MoneyPO(win.amount), { 0.4, 1, 0.4 }
                if win.desc then label = win.desc .. "  " .. label end
            elseif show and show.desc ~= "" and (showing or #v.board == 5) then
                label = show.desc
            elseif seat.far then
                label, color = L.SITOUT, { 0.7, 0.7, 0.7 }
            elseif BETTING[v.phase] or showing then
                label = actLabel(seat.act)
                if seat.act and seat.act:sub(1, 1) == "A" then color = { 1, 0.45, 0.3 } end
            end
            s.act:SetText(label or "")
            s.act:SetTextColor(color[1], color[2], color[3])

            -- cartes
            if show then
                SetCard(s.cards[1], show[1])
                SetCard(s.cards[2], show[2])
            elseif i == mine and v.hole[1] and v.hole.hand == v.handNo and active then
                SetCard(s.cards[1], v.hole[1])
                SetCard(s.cards[2], v.hole[2])
            elseif active and (BETTING[v.phase] or showing) then
                SetCard(s.cards[1], "??")
                SetCard(s.cards[2], "??")
            else
                s.cards[1]:Hide()
                s.cards[2]:Hide()
            end

            -- mise
            if seat.bet > 0 and BETTING[v.phase] then
                s.betFrame.text:SetText(U.Money(seat.bet))
                s.betFrame:Show()
            else
                s.betFrame:Hide()
            end

            if v.dealer == i and v.phase ~= "idle" then s.dealer:Show() else s.dealer:Hide() end
            if v.toAct == i and BETTING[v.phase] then s.glow:Show() else s.glow:Hide() end
        end
    end
end

local function RefreshBoard(v)
    for k = 1, 5 do
        if v.board[k] then SetCard(board[k], v.board[k]) else board[k]:Hide() end
    end
    if v.potTotal > 0 then
        potPanel.v1:SetText(U.Money(v.potTotal))
        potPanel.v2:SetText(U.Money(v.potMain))
        potPanel:Show()
    else
        potPanel:Hide()
    end
    local host = ns.Net.host
    if v.phase == "idle" or (v.phase == "done" and not v.running) then
        if host and not host.engine.running then centerText:SetText(L.HINT_HOST)
        elseif not v.running then centerText:SetText(L.PAUSED)
        else centerText:SetText(L.WAITING) end
        centerText:Show()
    else
        centerText:Hide()
    end
end

function UI.UpdateTimers()
    local v = ns.Net.view
    if not v or not seats then return end
    for _, s in ipairs(seats) do
        local seat = v.seats[s.seatIndex or 0]
        if s:IsShown() and seat and v.toAct == s.seatIndex and BETTING[v.phase] and not seat.bot and v.deadline then
            local left = math.max(0, math.ceil(v.deadline - GetTime()))
            s.timer.text:SetText(left)
            if left <= 5 then s.timer.text:SetTextColor(1, 0.35, 0.3) else s.timer.text:SetTextColor(1, 1, 1) end
            s.timer:Show()
        else
            s.timer:Hide()
        end
    end
end

-- ------------------------------------------------------------------
-- Actions du joueur
-- ------------------------------------------------------------------
local act = {}   -- état courant du panneau d'action

function UI.SetRaise(value, fromSlider)
    if not act.maxTo then return end
    value = math.max(act.minTo, math.min(act.maxTo, math.floor(value or 0)))
    act.raiseTo = value
    actions.amount:SetText(tostring(value))
    if not fromSlider then actions.slider:SetValue(value) end
    local range = act.maxTo - act.minTo
    local pct = range > 0 and (value - act.minTo) / range or 1
    actions.slider.fill:SetWidth(math.max(1, 285 * pct))
    local label
    if value >= act.maxTo then label = L.ALLIN
    elseif act.currentBet == 0 then label = L.BET
    else label = L.RAISE end
    actions.raise.text:SetText(label .. "\n" .. U.Money(value))
end

function UI.Preset(pct)
    if not act.maxTo then return end
    if pct == "ALL" then return UI.SetRaise(act.maxTo) end
    local potAfterCall = act.pot + act.toCall
    UI.SetRaise(act.currentBet + math.floor(potAfterCall * pct + 0.5))
end

function UI.Do(kind)
    local v = ns.Net.view
    if not v or not act.maxTo then return end
    if kind == "F" then
        ns.Net.Act("F")
    elseif kind == "C" then
        ns.Net.Act(act.toCall > 0 and "C" or "K")
    elseif kind == "R" then
        if act.raiseTo >= act.maxTo then ns.Net.Act("A") else ns.Net.Act("R", act.raiseTo) end
    end
    act.sentFor = v.handNo .. ":" .. v.toAct .. ":" .. v.currentBet .. ":" .. #v.board
    actions:Hide()
end

local function RefreshActions(v)
    local mine, me = ns.Net.MySeat()
    local myTurn = me and v.toAct == mine and BETTING[v.phase] and me.inHand and not me.folded and not me.allin
    local key = v.handNo .. ":" .. v.toAct .. ":" .. v.currentBet .. ":" .. #v.board
    if not myTurn or act.sentFor == key then
        actions:Hide()
        act.maxTo = nil
        return
    end
    local wasShown = actions:IsShown() and act.key == key
    act.key = key
    act.toCall = math.max(0, v.currentBet - me.bet)
    act.currentBet = v.currentBet
    act.pot = v.potTotal
    act.maxTo = me.bet + me.stack
    act.minTo = math.min(v.currentBet + math.max(v.minRaise, v.bb), act.maxTo)
    local canRaise = me.canRaise and act.maxTo > v.currentBet

    if act.toCall == 0 then
        actions.call.text:SetText(L.CHECK)
    elseif act.toCall >= me.stack then
        actions.call.text:SetText(L.ALLIN .. "\n" .. U.Money(me.stack))
    else
        actions.call.text:SetText(L.CALL .. "\n" .. U.Money(act.toCall))
    end

    actions.raise:SetActive(canRaise)
    for _, b in ipairs(actions.presets) do b:SetActive(canRaise) end
    actions.slider:SetMinMaxValues(act.minTo, math.max(act.minTo + 0.001, act.maxTo))
    if act.minTo >= act.maxTo then actions.slider:Disable() else actions.slider:Enable() end
    if not wasShown then
        UI.SetRaise(act.minTo)
    else
        UI.SetRaise(act.raiseTo or act.minTo)
    end
    if not canRaise then actions.raise.text:SetText(L.RAISE) end
    actions:Show()
end

-- ------------------------------------------------------------------
-- Points d'entrée appelés par Net.lua
-- ------------------------------------------------------------------
function UI.RefreshPurse()
    if not f then return end
    local p, d = ns.Bank.Purse(), ns.Bank.Debt()
    local txt = L.PURSE .. " : |cffffd24d" .. U.MoneyPO(p) .. "|r"
    if d > 0 then txt = txt .. "   " .. L.DEBT .. " : |cffff5040" .. U.MoneyPO(d) .. "|r" end
    toolbar.purse.text:SetText(txt)
    if d > 0 and p > 0 then toolbar.purse.repay:Show() else toolbar.purse.repay:Hide() end
end

function UI.RefreshLobby()
    if not f or not lobby:IsShown() then return end
    local list = {}
    for id, a in pairs(ns.Net.adverts) do list[#list + 1] = a end
    table.sort(list, function(a, b) return a.host < b.host end)
    for k, r in ipairs(lobby.rows) do
        local a = list[k]
        if a then
            r.title:SetText(string.format(L.TABLE_OF, a.host))
            r.info:SetText(string.format(L.TABLE_INFO, U.Money(a.sb), U.Money(a.bb), U.MoneyPO(a.buyin), a.players, a.max))
            r.join:SetScript("OnClick", function() U.Sound("click"); ns.Net.Join(a.id) end)
            r.join:SetActive(a.players < a.max)
            r:Show()
        else
            r:Hide()
        end
    end
    if #list == 0 then
        lobby.empty:Show(); lobby.search:Show(); lobby.refresh:Hide()
    else
        lobby.empty:Hide(); lobby.search:Hide(); lobby.refresh:Show()
    end
    lobby.status:SetText(ns.Net.pending and L.JOINING or "")
end

function UI.Refresh()
    if not f then return end
    UI.RefreshPurse()
    local v = ns.Net.view
    if not v then
        lobby:Show()
        for _, s in ipairs(seats) do s:Hide(); s.betFrame:Hide(); s.dealer:Hide() end
        for k = 1, 5 do board[k]:Hide() end
        potPanel:Hide()
        centerText:Hide()
        actions:Hide()
        LayoutToolbar({})
        UI.RefreshLobby()
        return
    end
    lobby:Hide()
    RefreshSeats(v)
    RefreshBoard(v)
    RefreshActions(v)
    UI.UpdateTimers()

    local bar = {}
    local host = ns.Net.host
    if host then
        toolbar.start.text:SetText(host.engine.running and L.PAUSE or L.START)
        bar = { "start", "bot", "close" }
    else
        bar = { "leave" }
    end
    local _, me = ns.Net.MySeat()
    if me and (me.stack + (me.pendingRebuy or 0)) < v.buyin and not (me.inHand and not me.folded and BETTING[v.phase]) then
        bar[#bar + 1] = "rebuy"
    end
    LayoutToolbar(bar)
end

function UI.Log(msg)
    if logFrame then logFrame:AddMessage(msg) end
end

function UI.Flash(msg)
    if not f then return end
    if not f:IsShown() then f:Show() end
    flashText:SetText(msg)
    flashText:SetAlpha(1)
    flashText:Show()
    UI.flashUntil = GetTime() + 2.2
end

function UI.SeatPulse(i)
    -- l'état arrive juste après ; rien de plus à faire pour l'instant
end

function UI.WinPulse(i, amount)
    if not seats then return end
    local slot = seatToSlot(i)
    local s = slot and seats[slot]
    if not s then return end
    s.float:SetText("+" .. U.MoneyPO(amount))
    s.float:SetAlpha(1)
    s.float:Show()
    s.floatUntil = GetTime() + 3
end

function UI.Toggle()
    UI.Build()
    if f:IsShown() then
        f:Hide()
    else
        f:Show()
        UI.Refresh()
        if not ns.Net.view then ns.Net.Search() end
    end
end

function UI.SetScale(s)
    LDPokerDB.scale = s
    if f then f:SetScale(s) end
end
