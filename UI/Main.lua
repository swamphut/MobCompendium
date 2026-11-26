local _, NS = ...
NS.UI = NS.UI or {}
NS.UI.activeTab = NS.TAB_OPEN_WORLD

local mainFrame
local tabButtons = {}

local function UpdateTabVisuals()
    if not mainFrame then
        return
    end

    local isInstances = (NS.UI.activeTab == NS.TAB_INSTANCES)
    if mainFrame.title then
        if isInstances then
            mainFrame.title:SetText("Mob Compendium — Instanced Archives")
        else
            mainFrame.title:SetText("Mob Compendium — Open World")
        end
    end

    for tabKey, btn in pairs(tabButtons) do
        local isActive = (tabKey == NS.UI.activeTab)
        if isActive then
            btn:SetBackdropColor(0.22, 0.18, 0.12, 1)
            btn:SetBackdropBorderColor(1, 0.82, 0, 1)
            btn.label:SetTextColor(1, 0.85, 0.2)
            btn.accent:Show()
            btn:SetFrameLevel(mainFrame:GetFrameLevel() + 4)
        else
            btn:SetBackdropColor(0.1, 0.1, 0.12, 0.92)
            btn:SetBackdropBorderColor(0.45, 0.45, 0.5, 0.85)
            btn.label:SetTextColor(0.68, 0.68, 0.72)
            btn.accent:Hide()
            btn:SetFrameLevel(mainFrame:GetFrameLevel() + 1)
        end
    end
end

local function CreateCompendiumTab(parent, tabKey, labelText, iconPath, iconSize, anchorTarget, offsetX)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(165, 32)
    if anchorTarget then
        btn:SetPoint("LEFT", anchorTarget, "RIGHT", offsetX or 6, 0)
    else
        btn:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", offsetX or 14, 3)
    end

    btn:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 10,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })

    btn.accent = btn:CreateTexture(nil, "OVERLAY")
    btn.accent:SetHeight(2)
    btn.accent:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 6, 4)
    btn.accent:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -6, 4)
    btn.accent:SetColorTexture(1, 0.82, 0, 0.9)

    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetSize(iconSize or 18, iconSize or 18)
    btn.icon:SetPoint("LEFT", btn, "LEFT", 12, 0)
    btn.icon:SetTexture(iconPath)

    btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btn.label:SetPoint("LEFT", btn.icon, "RIGHT", 6, 0)
    btn.label:SetText(labelText)

    btn.highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    btn.highlight:SetAllPoints(btn)
    btn.highlight:SetColorTexture(1, 1, 1, 0.08)

    btn:SetScript("OnClick", function()
        if NS.UI.activeTab ~= tabKey then
            PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
            NS.SetActiveTab(tabKey)
        end
    end)

    tabButtons[tabKey] = btn
    return btn
end

function NS.SetActiveTab(tabKey)
    NS.UI.activeTab = tabKey
    UpdateTabVisuals()

    if NS.UI.List and NS.UI.List.ClearSelection then
        NS.UI.List.ClearSelection()
    end
    if NS.UI.Details and NS.UI.Details.Reset then
        NS.UI.Details.Reset()
    end
    if NS.UI.RightColumn and NS.UI.RightColumn.Reset then
        NS.UI.RightColumn.Reset()
    end
    if NS.UI.List and NS.UI.List.Update then
        NS.UI.List.Update()
    end
end

function NS.UpdateUI()
    if NS.UI.List and NS.UI.List.Update then
        NS.UI.List.Update()
    end
    if NS.UI.List and NS.UI.List.RefreshSelected then
        NS.UI.List.RefreshSelected()
    end
end

function NS.ResetUI()
    if NS.UI.List then
        NS.UI.List.Reset()
    end
    if NS.UI.Details then
        NS.UI.Details.Reset()
    end
    if NS.UI.RightColumn then
        NS.UI.RightColumn.Reset()
    end
end

function NS.CreateUI()
    if mainFrame then
        return
    end

    mainFrame = CreateFrame("Frame", "MobCompendiumMainWindow", UIParent, "BasicFrameTemplateWithInset")
    mainFrame:SetSize(1150, 650)

    if MobCompendiumDB and MobCompendiumDB.windowPos then
        local pos = MobCompendiumDB.windowPos
        mainFrame:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x, pos.y)
    else
        mainFrame:SetPoint("CENTER")
    end

    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(true)
    mainFrame:RegisterForDrag("LeftButton")

    mainFrame:SetScript("OnDragStart", function(self)
        if not MobCompendiumDB.settings.lockWindow then
            self:StartMoving()
        end
    end)

    mainFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        MobCompendiumDB.windowPos = { point = p, relativePoint = rp, x = x, y = y }
    end)

    mainFrame:SetScript("OnShow", function()
        PlaySound(603)
    end)
    mainFrame:SetScript("OnHide", function()
        PlaySoundFile(4256145)
    end)

    tinsert(UISpecialFrames, "MobCompendiumMainWindow")

    mainFrame.title = mainFrame:CreateFontString(nil, "OVERLAY")
    mainFrame.title:SetFontObject("GameFontHighlight")
    mainFrame.title:SetPoint("LEFT", mainFrame.TitleBg, "LEFT", 5, 0)
    mainFrame.title:SetText("Mob Compendium — Open World")

    -- Bottom Tabs: Open World vs Instanced Archives
    local openWorldTab = CreateCompendiumTab(
        mainFrame,
        NS.TAB_OPEN_WORLD,
        "Open World",
        "Interface\\Icons\\INV_Misc_Map02",
        16,
        nil,
        14
    )
    CreateCompendiumTab(
        mainFrame,
        NS.TAB_INSTANCES,
        "Instances",
        "Interface\\Minimap\\Dungeon_Icon",
        26,
        openWorldTab,
        6
    )

    if NS.UI.FilterBar then
        NS.UI.FilterBar.Init(mainFrame)
    end

    if NS.UI.List then
        NS.UI.List.Init(mainFrame)
    end
    if NS.UI.Details then
        NS.UI.Details.Init(mainFrame)
    end
    if NS.UI.RightColumn then
        NS.UI.RightColumn.Init(mainFrame)
    end

    UpdateTabVisuals()
end

function NS.ToggleUI()
    if not mainFrame then
        NS.CreateUI()
        NS.UpdateUI()
        return
    end
    if mainFrame:IsShown() then
        mainFrame:Hide()
    else
        mainFrame:Show()
        NS.UpdateUI()
    end
end
