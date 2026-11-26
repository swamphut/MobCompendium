local _, NS = ...

NS.DB_VERSION = 2

-- Compendium Tabs
NS.TAB_OPEN_WORLD = "openworld"
NS.TAB_INSTANCES = "instances"

-- Midnight (12.0+) Secret Value & Compatibility Helpers
function NS.IsSecret(val)
    return issecretvalue ~= nil and issecretvalue(val)
end

function NS.IsSafe(val)
    return val ~= nil and not NS.IsSecret(val)
end

function NS.IsInstanceType(instType)
    return instType == "party"
        or instType == "raid"
        or instType == "scenario"
        or instType == "pvp"
        or instType == "arena"
end

function NS.GetItemInfo(item)
    if C_Item and C_Item.GetItemInfo then
        return C_Item.GetItemInfo(item)
    elseif GetItemInfo then
        return GetItemInfo(item)
    end
end

function NS.GetItemInfoInstant(item)
    if C_Item and C_Item.GetItemInfoInstant then
        return C_Item.GetItemInfoInstant(item)
    elseif GetItemInfoInstant then
        return GetItemInfoInstant(item)
    end
end

function NS.GetItemQualityColor(quality)
    if C_Item and C_Item.GetItemQualityColor then
        return C_Item.GetItemQualityColor(quality)
    elseif GetItemQualityColor then
        return GetItemQualityColor(quality)
    end
    return 1, 1, 1
end

-- Lore Strings for Redacted Instanced Telemetry
NS.LORE_REDACTED_TITLE = "[ REDACTED ]"
NS.LORE_REDACTED_SPELLS = "Arcane interference within instanced sanctums shrouds live spellcraft from field observation.\n\nOnly physical spoils and combat records endure."
NS.LORE_REDACTED_LOCATION = "Restricted — Instanced Sanctum"

-- Rank Configuration
NS.RANK_CONFIG = {
    boss = {
        text = "Boss",
        icon = "Interface\\Icons\\inv_misc_bone_humanskull_02",
        coords = { 0, 1, 0, 1 },
        color = { 1, 1, 1 }
    },
    rareelite = {
        text = "Rare Elite",
        icon = "Interface\\Icons\\inv_misc_head_dragon_black",
        coords = { 0, 1, 0, 1 },
        color = { 1, 1, 1 }
    },
    elite = {
        text = "Elite",
        icon = "Interface\\Icons\\inv_misc_head_dragon_bronze",
        coords = { 0, 1, 0, 1 },
        color = { 1, 1, 1 }
    },
    rare = {
        text = "Rare",
        icon = "Interface\\Icons\\inv_misc_head_dragon_blue",
        coords = { 0, 1, 0, 1 },
        color = { 1, 1, 1 }
    },
    minion = {
        text = "Minion",
        icon = "Interface\\Icons\\inv_babyfaeriedragon",
        coords = { 0, 1, 0, 1 },
        color = { 1, 1, 1 }
    },
    wildpet = {
        text = "Wild Pet",
        icon = "Interface\\Icons\\inv_box_petcarrier_01",
        coords = { 0, 1, 0, 1 },
        color = { 1, 1, 1 }
    },
    critter = {
        text = "Critter",
        icon = "Interface\\Icons\\INV_Misc_Rabbit_2",
        coords = { 0, 1, 0, 1 },
        color = { 1, 1, 1 }
    },
    normal = {
        text = "Normal",
        icon = "Interface\\Icons\\Achievement_character_human_male",
        coords = { 0, 1, 0, 1 },
        color = { 1, 1, 1 }
    },
    unknown = {
        text = "Unknown",
        icon = "Interface\\Icons\\INV_Misc_QuestionMark",
        coords = { 0, 1, 0, 1 },
        color = { 0.7, 0.7, 0.7 }
    }
}

-- Zone Icon Configuration
NS.ZONE_ICONS = {
    raid = {
        icon = "Interface\\Minimap\\Raid_Icon",
        color = { 1, 1, 1 },
        size = 40
    },
    party = {
        icon = "Interface\\Minimap\\Dungeon_Icon",
        color = { 1, 1, 1 },
        size = 40
    },
    scenario = {
        icon = "Interface\\Icons\\Icon_Scenarios",
        color = { 1, 1, 1 }
    },
    pvp = {
        icon = "Interface\\Icons\\Faction_Alliance_Vanguard",
        color = { 1, 0, 0 }
    },
    arena = {
        icon = "Interface\\Icons\\Achievement_Arena_2v2_7",
        color = { 1, 0.3, 0.3 }
    },
    none = {
        icon = "Interface\\Icons\\INV_Misc_Map02",
        color = { 1, 1, 1 }
    }
}