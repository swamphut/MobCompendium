local _, NS = ...
NS.UI = NS.UI or {}
NS.UI.SpellList = {}

local scrollChild, redactedFrame, redactedTitle, redactedBody, emptyText
local buttons = {}

function NS.UI.SpellList.Init(parent, anchorTop)
    local scrollFrame = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")

    scrollFrame:SetPoint("TOP", anchorTop, "BOTTOM", 0, -5)
    scrollFrame:SetPoint("LEFT", parent, "LEFT", 10, 0)
    scrollFrame:SetPoint("RIGHT", parent, "RIGHT", -30, 0)
    scrollFrame:SetPoint("BOTTOM", parent, "BOTTOM", 0, 10)

    scrollChild = CreateFrame("Frame")
    scrollChild:SetSize(260, 1)
    scrollFrame:SetScrollChild(scrollChild)

    -- Lore-styled Redacted notice for instanced content where live combat spells are restricted
    redactedFrame = CreateFrame("Frame", nil, scrollFrame, "BackdropTemplate")
    redactedFrame:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 6, -18)
    redactedFrame:SetPoint("TOPRIGHT", scrollFrame, "TOPRIGHT", -6, -18)
    redactedFrame:SetHeight(145)
    redactedFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 12,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    redactedFrame:SetBackdropColor(0.14, 0.08, 0.18, 0.85)
    redactedFrame:SetBackdropBorderColor(0.6, 0.35, 0.72, 0.85)
    redactedFrame:Hide()

    redactedTitle = redactedFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    redactedTitle:SetPoint("TOP", redactedFrame, "TOP", 0, -18)
    redactedTitle:SetTextColor(0.85, 0.45, 0.95)
    redactedTitle:SetText(NS.LORE_REDACTED_TITLE)

    redactedBody = redactedFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    redactedBody:SetPoint("TOP", redactedTitle, "BOTTOM", 0, -10)
    redactedBody:SetWidth(215)
    redactedBody:SetJustifyH("CENTER")
    redactedBody:SetTextColor(0.75, 0.72, 0.8)
    redactedBody:SetText(NS.LORE_REDACTED_SPELLS)

    -- Simple empty notice for Open World entries with no observed casts yet
    emptyText = scrollFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    emptyText:SetPoint("CENTER", scrollFrame, "CENTER", 0, 0)
    emptyText:SetWidth(230)
    emptyText:SetJustifyH("CENTER")
    emptyText:SetTextColor(0.55, 0.55, 0.6)
    emptyText:Hide()
end

function NS.UI.SpellList.Reset()
    for _, btn in pairs(buttons) do
        btn:Hide()
    end
    if redactedFrame then
        redactedFrame:Hide()
    end
    if emptyText then
        emptyText:Hide()
    end
end

function NS.UI.SpellList.Update(data, isInstance)
    for _, btn in pairs(buttons) do
        btn:Hide()
    end
    if redactedFrame then
        redactedFrame:Hide()
    end
    if emptyText then
        emptyText:Hide()
    end

    if not data then
        return
    end

    local list = {}
    if data.spells then
        for id, _ in pairs(data.spells) do
            table.insert(list, id)
        end
    end

    if #list == 0 then
        scrollChild:SetHeight(1)
        if isInstance then
            if redactedFrame then
                redactedFrame:Show()
            end
        elseif emptyText then
            emptyText:SetText("No abilities observed in combat yet.")
            emptyText:Show()
        end
        return
    end

    table.sort(list)

    local height = 0
    for i, spellID in ipairs(list) do
        local btn = buttons[i]
        if not btn then
            btn = CreateFrame("Button", nil, scrollChild)
            btn:SetSize(260, 44)
            btn.icon = btn:CreateTexture(nil, "ARTWORK")
            btn.icon:SetSize(36, 36)
            btn.icon:SetPoint("LEFT", 4, 0)
            btn.name = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            btn.name:SetPoint("LEFT", btn.icon, "RIGHT", 10, 8)
            btn.name:SetWidth(200)
            btn.name:SetJustifyH("LEFT")
            btn.name:SetWordWrap(false)
            btn.sub = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            btn.sub:SetPoint("TOPLEFT", btn.name, "BOTTOMLEFT", 0, -2)
            btn.sub:SetTextColor(0.6, 0.6, 0.6)
            btn.hl = btn:CreateTexture(nil, "HIGHLIGHT")
            btn.hl:SetAllPoints()
            btn.hl:SetColorTexture(1, 1, 1, 0.1)
            buttons[i] = btn
        end

        btn:Show()
        btn:SetPoint("TOPLEFT", 0, -height)

        -- Load Spell
        local spellInfo = C_Spell.GetSpellInfo(spellID)
        if spellInfo then
            btn.icon:SetTexture(spellInfo.iconID)
            btn.name:SetText(spellInfo.name)
        else
            btn.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            btn.name:SetText("Unknown Spell")
        end
        btn.name:SetTextColor(1, 1, 1)

        -- Interactions
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetSpellByID(spellID)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        btn:SetScript("OnClick", function()
            if IsModifiedClick("CHATLINK") then
                local l = C_Spell.GetSpellLink(spellID)
                if l then
                    ChatEdit_InsertLink(l)
                end
            end
        end)

        height = height + 44
    end
    scrollChild:SetHeight(height)
end
