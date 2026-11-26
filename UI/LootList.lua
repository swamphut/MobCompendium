local _, NS = ...
NS.UI = NS.UI or {}
NS.UI.LootList = {}

local scrollChild, emptyText
local buttons = {}
local updateToken = 0

local function GetEncounterKeys(encounter)
    local pKey = encounter.parentMap or "Uncategorized"
    local zKey = encounter.zoneName or "Unknown Zone"

    if encounter.instType and encounter.instType ~= "none" and encounter.diffName and encounter.diffName ~= "" then
        pKey = pKey .. " [" .. encounter.diffName .. "]"
    end
    return pKey, zKey
end

function NS.UI.LootList.Init(parent, anchorTop, anchorBottom)
    local scrollFrame = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")

    scrollFrame:SetPoint("TOP", anchorTop, "BOTTOM", 0, -5)
    scrollFrame:SetPoint("LEFT", parent, "LEFT", 10, 0)
    scrollFrame:SetPoint("RIGHT", parent, "RIGHT", -30, 0)
    scrollFrame:SetPoint("BOTTOM", anchorBottom, "TOP", 0, 10)

    scrollChild = CreateFrame("Frame")
    scrollChild:SetSize(260, 1)
    scrollFrame:SetScrollChild(scrollChild)

    emptyText = scrollFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    emptyText:SetPoint("CENTER", scrollFrame, "CENTER", 0, 0)
    emptyText:SetWidth(230)
    emptyText:SetJustifyH("CENTER")
    emptyText:SetTextColor(0.55, 0.55, 0.6)
    emptyText:Hide()
end

function NS.UI.LootList.Reset()
    updateToken = updateToken + 1
    for _, btn in pairs(buttons) do
        btn:Hide()
    end
    if emptyText then
        emptyText:Hide()
    end
end

function NS.UI.LootList.Update(data, filterParent, filterZone, isInstance)
    updateToken = updateToken + 1
    local currentToken = updateToken

    for _, btn in pairs(buttons) do
        btn:Hide()
    end
    if emptyText then
        emptyText:Hide()
    end

    if not data or not data.encounters then
        return
    end

    local uniqueDrops = {}
    local hasLoot = false

    for _, encounter in pairs(data.encounters) do
        local encIsInstance = NS.IsInstanceType(encounter.instType)
        local tabMatches = (isInstance == nil) or (encIsInstance == isInstance)
        local pKey, zKey = GetEncounterKeys(encounter)
        local contextMatches = (not filterParent or pKey == filterParent) and (not filterZone or zKey == filterZone)

        if tabMatches and contextMatches and encounter.drops then
            for itemID, _ in pairs(encounter.drops) do
                uniqueDrops[itemID] = true
                hasLoot = true
            end
        end
    end

    if not hasLoot then
        if emptyText then
            emptyText:SetText("No loot recorded yet.")
            emptyText:Show()
        end
        scrollChild:SetHeight(1)
        return
    end

    local list = {}
    for id, _ in pairs(uniqueDrops) do
        table.insert(list, id)
    end
    table.sort(list)

    local height = 0
    for i, itemID in ipairs(list) do
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

        btn.itemID = itemID
        btn:Show()
        btn:SetPoint("TOPLEFT", 0, -height)

        btn.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        btn.name:SetText("Loading...")
        btn.name:SetTextColor(1, 1, 1)

        local item = Item:CreateFromItemID(itemID)
        item:ContinueOnItemLoad(function()
            if currentToken ~= updateToken or btn.itemID ~= itemID then
                return
            end
            local itemName, _, quality, _, _, _, _, _, _, icon = NS.GetItemInfo(itemID)
            if icon then
                btn.icon:SetTexture(icon)
            end
            if itemName then
                local r, g, b = NS.GetItemQualityColor(quality or 1)
                btn.name:SetText(itemName)
                btn.name:SetTextColor(r, g, b)
            else
                btn.name:SetText("Unknown Item")
            end
        end)

        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(itemID)
            GameTooltip:Show()
        end)

        btn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        btn:SetScript("OnClick", function()
            if IsModifiedClick("CHATLINK") then
                local _, l = NS.GetItemInfo(itemID)
                if l then
                    ChatEdit_InsertLink(l)
                end
            end
        end)

        height = height + 44
    end
    scrollChild:SetHeight(height)
end
