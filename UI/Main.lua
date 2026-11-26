local _, NS = ...
NS.UI = NS.UI or {}
NS.UI.activeTab = NS.TAB_OPEN_WORLD

local mainFrame
local tabButtons = {}

-- Raising the active tab's frame level above the main border creates the illusion that it
-- connects seamlessly to the bottom edge of the window, while inactive tabs sit recessed behind it.
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

-- Custom BackdropTemplate tabs are anchored beneath the main frame rather than using Blizzard's
-- PanelTabButtonTemplate so tab styling stays immune to retail template XML changes and does not
-- consume vertical space inside the three-column layout.
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

-- Switching tabs clears the center and right panels so a mob from Open World does not linger
-- visually while browsing Instanced Archives (or vice versa).
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

-- Refreshing both the list and the active selection ensures live kill increments, loot drops,
-- and post-combat harvested spells appear immediately if the window is already open.
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

-- Frame construction is deferred until the player first opens /mobc so the addon keeps zero
-- UI memory footprint during combat sessions when the compendium is never opened.
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

    -- Book open/close foley reinforces the field-journal feel of the compendium.
    mainFrame:SetScript("OnShow", function()
        PlaySound(603)
    end)
    mainFrame:SetScript("OnHide", function()
        PlaySoundFile(4256145)
    end)

    -- Registering with UISpecialFrames allows the Escape key to dismiss the window natively.
    tinsert(UISpecialFrames, "MobCompendiumMainWindow")

    mainFrame.title = mainFrame:CreateFontString(nil, "OVERLAY")
    mainFrame.title:SetFontObject("GameFontHighlight")
    mainFrame.title:SetPoint("LEFT", mainFrame.TitleBg, "LEFT", 5, 0)
    mainFrame.title:SetText("Mob Compendium — Open World")

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

    -- FilterBar initializes before List so rank filter checkbox state is ready for the first render.
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
