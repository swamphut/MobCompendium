local _, NS = ...

-- Default Configuration
local defaultSettings = {
    lockWindow = false,
    printNew = true,
    printUpdate = true,
    minimap = {
        hide = false,
        angle = 45
    },
    rankFilters = {
        boss = true,
        rareelite = true,
        elite = true,
        rare = true,
        normal = true,
        minion = true,
        critter = true,
        wildpet = true,
        unknown = true
    }
}

function NS.InitSettings()

    if not MobCompendiumDB.settings then
        MobCompendiumDB.settings = CopyTable(defaultSettings)
    else
        for k, v in pairs(defaultSettings) do
            if MobCompendiumDB.settings[k] == nil then
                MobCompendiumDB.settings[k] = v
            end
        end
        
        if not MobCompendiumDB.settings.rankFilters then
            MobCompendiumDB.settings.rankFilters = CopyTable(defaultSettings.rankFilters)
        else
            for k, v in pairs(defaultSettings.rankFilters) do
                if MobCompendiumDB.settings.rankFilters[k] == nil then
                    MobCompendiumDB.settings.rankFilters[k] = v
                end
            end
        end
    end

    local panel = CreateFrame("Frame")
    panel.name = "Mob Compendium"

    NS.SettingsPanelFrame = panel

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Mob Compendium Settings")

    local desc = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetText("Configure the behavior of the Mob Compendium.")

    local function CreateSettingCheckbox(parent, label, anchorTo, offsetY, initialValue, onToggle)
        local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        cb:SetSize(26, 26)
        cb:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, offsetY)

        local text = cb.text or cb.Text
        if not text then
            text = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
            text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
            cb.Text = text
        end
        text:SetText(label)
        text:SetFontObject("GameFontHighlight")

        cb:SetChecked(initialValue)
        cb:SetScript("OnClick", function(self)
            onToggle(self:GetChecked())
        end)
        return cb
    end

    -- ---------------------------------------------------------------------
    -- Lock Window
    -- ---------------------------------------------------------------------
    local cbLock = CreateSettingCheckbox(panel, "Lock Main Window", desc, -20, MobCompendiumDB.settings.lockWindow, function(checked)
        MobCompendiumDB.settings.lockWindow = checked
    end)

    -- ---------------------------------------------------------------------
    -- Print New Discoveries
    -- ---------------------------------------------------------------------
    local cbPrintNew = CreateSettingCheckbox(panel, "Chat Message: New Discovery", cbLock, -10, MobCompendiumDB.settings.printNew, function(checked)
        MobCompendiumDB.settings.printNew = checked
    end)

    -- ---------------------------------------------------------------------
    -- Print Updates
    -- ---------------------------------------------------------------------
    CreateSettingCheckbox(panel, "Chat Message: Kill Update", cbPrintNew, -10, MobCompendiumDB.settings.printUpdate, function(checked)
        MobCompendiumDB.settings.printUpdate = checked
    end)

    local category, layout = Settings.RegisterCanvasLayoutCategory(panel, "Mob Compendium")
    NS.SettingsCategory = category
    Settings.RegisterAddOnCategory(category)
end