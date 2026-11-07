local ADDON, ns = ...

-- Bouton autour de la minimap : clic gauche = ouvrir/fermer la table, glisser = déplacer.
local btn
local RADIUS = 80

local function UpdatePosition()
    local angle = math.rad((LDPokerDB and LDPokerDB.minimapAngle) or 215)
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * RADIUS, math.sin(angle) * RADIUS)
end

function ns.BuildMinimapButton()
    if btn or not Minimap then return end
    btn = CreateFrame("Button", "LDPokerMinimapButton", Minimap)
    btn:SetSize(31, 31)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")
    btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local icon = btn:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(22, 22)
    icon:SetPoint("CENTER", 0, 1)
    icon:SetTexture("Interface\\AddOns\\LD_Poker\\Media\\icon")
    icon:SetTexCoord(0.02, 0.98, 0.02, 0.98)
    -- masque rond : retire les coins noirs de l'image pour qu'elle remplisse le cercle
    if btn.CreateMaskTexture then
        local mask = btn:CreateMaskTexture()
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(icon)
        icon:AddMaskTexture(mask)
    end

    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    btn:SetScript("OnClick", function() ns.UI.Toggle() end)

    btn:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local scale = Minimap:GetEffectiveScale()
            local cx, cy = GetCursorPosition()
            LDPokerDB.minimapAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
            UpdatePosition()
        end)
    end)
    btn:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("LD Poker")
        local fr = GetLocale() == "frFR"
        GameTooltip:AddLine(fr and "Clic : ouvrir la table" or "Click: open the table", 1, 1, 1)
        GameTooltip:AddLine(fr and "Glisser : déplacer le bouton" or "Drag: move this button", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    UpdatePosition()
end
