local _, NS = ...
NS.UI = NS.UI or {}
NS.UI.Details = {}

local parentFrame, nameText, countText, typeText, lastKillText, rankIcon, modelView, rankText

function NS.UI.Details.Init(mainFrame)
    parentFrame = CreateFrame("Frame", nil, mainFrame)
    parentFrame:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 304, -22)
    parentFrame:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -305, 45)

    local headerFrame = CreateFrame("Frame", nil, parentFrame, "BackdropTemplate")
    headerFrame:SetHeight(120)
    headerFrame:SetPoint("TOPLEFT", 0, 0)
    headerFrame:SetPoint("TOPRIGHT", 0, 0)
    headerFrame:SetBackdrop({
        bgFile = "Interface\\Collections\\CollectionsBackgroundTile",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 400, edgeSize = 8,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    headerFrame:SetBackdropColor(1, 1, 1, 1)

    nameText = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    nameText:SetPoint("TOP", headerFrame, "TOP", 0, -15)
    nameText:SetTextColor(1, 0.82, 0)

    typeText = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    typeText:SetPoint("TOP", nameText, "BOTTOM", 0, -4)
    typeText:SetTextColor(0.7, 0.7, 0.7)

    countText = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    countText:SetPoint("TOP", typeText, "BOTTOM", 0, -16)
    countText:SetTextColor(1, 1, 1)

    lastKillText = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lastKillText:SetPoint("BOTTOM", headerFrame, "BOTTOM", 0, 8)
    lastKillText:SetTextColor(0.6, 0.6, 0.6)

    rankIcon = headerFrame:CreateTexture(nil, "OVERLAY")
    rankIcon:SetSize(24, 24)
    rankIcon:SetPoint("BOTTOMRIGHT", headerFrame, "BOTTOMRIGHT", -15, 10)
    rankText = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rankText:SetPoint("RIGHT", rankIcon, "LEFT", -5, 0)
    rankText:SetJustifyH("RIGHT")

    local modelFrame = CreateFrame("Frame", nil, parentFrame, "BackdropTemplate")
    modelFrame:SetPoint("TOPLEFT", headerFrame, "BOTTOMLEFT", 0, 0)
    modelFrame:SetPoint("BOTTOMRIGHT", parentFrame, "BOTTOMRIGHT", 0, 0)
    modelFrame:SetBackdrop({ edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 6 })
    modelFrame:SetBackdropColor(0.55, 0.55, 0.55, 1)

    -- Oversizing the spellbook parchment texture and clipping children crops out its built-in
    -- page margins so the model sits on a seamless journal-page backdrop.
    local bg = modelFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Spellbook\\Spellbook-Page-1")
    bg:SetPoint("TOPLEFT", -70, 0)
    bg:SetPoint("BOTTOMRIGHT", 50, -50)
    bg:SetVertexColor(0.45, 0.45, 0.45, 1)
    modelFrame:SetClipsChildren(true)

    modelView = CreateFrame("PlayerModel", nil, modelFrame)
    modelView:SetPoint("TOPLEFT", 4, -4)
    modelView:SetPoint("BOTTOMRIGHT", -4, 4)

    modelView.currentZoom = -2
    modelView.panX = 0
    modelView.panY = 0
    modelView:SetPosition(modelView.currentZoom, modelView.panX, modelView.panY)

    -- Left-drag orbits the creature, right-drag pans camera space, and middle-click freezes
    -- idle animations for closer inspection.
    modelView:SetScript("OnMouseDown", function(self, button)
        local cx, cy = GetCursorPosition()

        if button == "LeftButton" then
            self.isRotating = true
            self.startX = cx
            self.startRotation = self:GetFacing() or 0

        elseif button == "RightButton" then
            self.isPanning = true
            self.startX = cx
            self.startY = cy
            self.startPanX = self.panX
            self.startPanY = self.panY

        elseif button == "MiddleButton" then
            local isPaused = self:GetPaused()
            self:SetPaused(not isPaused)
        end
    end)

    modelView:SetScript("OnMouseUp", function(self)
        self.isRotating = false
        self.isPanning = false
    end)

    modelView:SetScript("OnUpdate", function(self)
        local cx, cy = GetCursorPosition()

        if self.isRotating then
            self:SetFacing(self.startRotation + (cx - self.startX) / 80)

        elseif self.isPanning then
            -- Scaling pan sensitivity with zoom depth keeps drag speed feeling consistent
            -- whether inspecting a giant boss zoomed far out or a tiny critter up close.
            local baseSensitivity = 80
            local zoomScale = math.max(0.1, (10 - self.currentZoom) / 10)

            local deltaX = ((cx - self.startX) / baseSensitivity) * zoomScale
            local deltaY = ((cy - self.startY) / baseSensitivity) * zoomScale

            local newX = self.startPanX + deltaX
            local newY = self.startPanY + deltaY

            -- Clamp offsets so the creature cannot be dragged completely out of the viewport.
            local clampLimit = 8.0
            newX = math.max(-clampLimit, math.min(clampLimit, newX))
            newY = math.max(-clampLimit, math.min(clampLimit, newY))

            self.panX = newX
            self.panY = newY
            self:SetPosition(self.currentZoom, newX, newY)
        end
    end)

    modelView:EnableMouseWheel(true)
    modelView:SetScript("OnMouseWheel", function(self, d)
        self.currentZoom = math.max(-15, math.min(4, self.currentZoom + (d * 0.5)))
        self:SetPosition(self.currentZoom, self.panX, self.panY)
    end)
end

-- Mirrors the parent/zone key formatting used in List.lua so encounter aggregation matches
-- whichever tree branch the user clicked.
local function GetEncounterKeys(encounter)
    local pKey = encounter.parentMap or "Uncategorized"
    local zKey = encounter.zoneName or "Unknown Zone"

    if encounter.instType and encounter.instType ~= "none" and encounter.diffName and encounter.diffName ~= "" then
        pKey = pKey .. " [" .. encounter.diffName .. "]"
    end
    return pKey, zKey
end

function NS.UI.Details.ShowMob(npcID, filterParent, filterZone, isInstance)
    local data = MobCompendiumDB[npcID]
    if not data then
        return
    end

    nameText:SetText(data.name)

    local totalKills = 0
    local filteredKills = 0
    local displayRank = "unknown"
    local displayType = nil

    local lastSeenEntry = nil
    local latestTimeStr = ""

    if data.encounters then
        for _, encounter in pairs(data.encounters) do
            local encIsInstance = NS.IsInstanceType(encounter.instType)
            if isInstance == nil or encIsInstance == isInstance then
                totalKills = totalKills + (encounter.kills or 0)

                local pKey, zKey = GetEncounterKeys(encounter)
                local isMatch = (not filterParent or pKey == filterParent) and
                        (not filterZone or zKey == filterZone)

                if isMatch then
                    filteredKills = filteredKills + (encounter.kills or 0)

                    if encounter.rank then
                        displayRank = encounter.rank
                    end
                    if encounter.type then
                        displayType = encounter.type
                    end

                    -- ISO "YYYY-MM-DD HH:MM" timestamps sort chronologically by plain string comparison.
                    if encounter.lastTime and encounter.lastTime >= latestTimeStr then
                        latestTimeStr = encounter.lastTime
                        lastSeenEntry = encounter
                    end
                end
            end
        end
    end

    if displayType then
        typeText:SetText(displayType)
        typeText:Show()
    else
        typeText:Hide()
    end

    if filterParent and filteredKills > 0 then
        countText:SetText("Killed: " .. filteredKills)
    else
        countText:SetText("Killed: " .. totalKills)
    end

    if lastSeenEntry then
        local timeStr = lastSeenEntry.lastTime or "?"
        if lastSeenEntry.lastX and lastSeenEntry.lastY then
            lastKillText:SetTextColor(0.6, 0.6, 0.6)
            lastKillText:SetText(string.format("Loc: %.1f, %.1f (%s)", lastSeenEntry.lastX, lastSeenEntry.lastY, timeStr))
            lastKillText:Show()
        elseif isInstance then
            lastKillText:SetTextColor(0.76, 0.62, 0.85)
            lastKillText:SetText(string.format("Loc: [%s] (%s)", NS.LORE_REDACTED_LOCATION, timeStr))
            lastKillText:Show()
        else
            lastKillText:SetTextColor(0.6, 0.6, 0.6)
            lastKillText:SetText("Last Kill: " .. timeStr)
            lastKillText:Show()
        end
    elseif isInstance then
        lastKillText:SetTextColor(0.76, 0.62, 0.85)
        lastKillText:SetText("Loc: [" .. NS.LORE_REDACTED_LOCATION .. "]")
        lastKillText:Show()
    else
        lastKillText:Hide()
    end

    local rKey = displayRank or "unknown"
    local rConfig = NS.RANK_CONFIG[rKey] or NS.RANK_CONFIG["unknown"]
    rankText:SetText(rConfig.text)

    if rConfig.icon then
        rankIcon:Show()
        rankIcon:SetTexture(rConfig.icon)
        if rConfig.coords then
            rankIcon:SetTexCoord(unpack(rConfig.coords))
        end
        rankIcon:SetVertexColor(unpack(rConfig.color or { 1, 1, 1 }))
    else
        rankIcon:Hide()
    end

    -- Reset camera transforms before loading a new creature so zoom/pan from a previous model
    -- does not push the newly selected mob out of frame. pcall protects against retired or
    -- unsupported creature IDs that could otherwise throw in Midnight's model pipeline.
    modelView.currentZoom = 0
    modelView.panX = 0
    modelView.panY = 0
    modelView:SetFacing(0)
    modelView:SetPosition(0, 0, 0)
    pcall(modelView.SetCreature, modelView, npcID)
end

function NS.UI.Details.Reset()
    if not nameText then
        return
    end
    nameText:SetText("")
    countText:SetText("")
    typeText:SetText("")
    lastKillText:SetText("")
    rankText:SetText("")
    rankIcon:Hide()
    modelView:ClearModel()
end
