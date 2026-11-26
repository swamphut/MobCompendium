local _, NS = ...
local frame = CreateFrame("Frame")

-- In-memory session caches (never persisted until a mob is engaged & defeated/looted)
local npcMetaCache = {}       -- [npcID] = { name, rank, type, lastSeen }
local engagedGUIDs = {}       -- [guid]  = { npcID, name, rank, type, time }
local seenAliveGUIDs = {}     -- [guid]  = true (prevents counting already-dead corpses on hover)
local killedGUIDs = {}        -- [guid]  = true (deduplicates unit death + loot confirmation)
local recentBossKills = {}    -- [npcID] = timestamp (deduplicates BOSS_KILL + boss loot)
local lootCache = {}          -- [guid]  = { [itemID] = true }
local tempSpellCache = {}     -- [guid]  = { [spellID] = true }
local combatSessionNpcIDs = {} -- [npcID] = true (distinct enemy types fought during current combat)
local pendingNpcSpells = {}    -- [npcID] = { spells = { [spellID] = true }, time = GetTime() }
local lastProcessedDMSessionID = nil

local inCombat = false
local lastPlayerActionTime = 0
local lastTargetGUID = nil
local debugMode = false

-- Spells that appear in DamageTaken but are basic swings or player self-damage mechanics
local IGNORED_DAMAGE_TAKEN_SPELLS = {
    [6603] = true,   -- Auto Attack (Melee)
    [75] = true,     -- Auto Shot
    [5019] = true,   -- Shoot (Wand)
    [124255] = true, -- Monk: Stagger (self-damage tick)
    [111400] = true, -- Warlock: Burning Rush
    [1454] = true,   -- Warlock: Life Tap
    [108416] = true, -- Warlock: Dark Pact
    [32409] = true,  -- Priest: Shadow Word: Death backlash
    [190714] = true, -- Environmental / Misc self-damage
    [340928] = true, -- Miscellaneous fall/self tick
}

local INSPECT_UNITS = { "target", "mouseover", "focus", "softenemy", "boss1", "boss2", "boss3", "boss4", "boss5" }

-- =========================================================================
-- Commands
-- =========================================================================

SLASH_MobCompendium1 = "/mobc"
SlashCmdList["MobCompendium"] = function()
    NS.ToggleUI()
end

SLASH_MobCompendiumReset1 = "/mobcreset"
SlashCmdList["MobCompendiumReset"] = function()
    MobCompendiumDB = { dbVersion = NS.DB_VERSION }
    NS.InitSettings()
    NS.ResetUI()
    print("|cff00ffffMobCompendium:|r Database has been reset.")
end

SLASH_MobCompendiumDebug1 = "/mobcdebug"
SlashCmdList["MobCompendiumDebug"] = function()
    debugMode = not debugMode
    print("|cff00ffffMobCompendium:|r Debug logging " .. (debugMode and "|cff00ff00ENABLED|r" or "|cffff4444DISABLED|r"))
end

SLASH_MobCompendiumDM1 = "/mobcdm"
SlashCmdList["MobCompendiumDM"] = function()
    if not C_DamageMeter or not Enum or not Enum.DamageMeterSessionType or not Enum.DamageMeterType then
        print("|cffff4444[MobC DM]|r C_DamageMeter API not available.")
        return
    end
    local function fmt(v)
        if NS.IsSecret(v) then return "SECRET" end
        if v == nil then return "nil" end
        return tostring(v)
    end
    local pGUID = UnitGUID("player")
    print("|cff00ffff[MobC DM]|r Checking Current DamageTaken for player out-of-combat...")
    local ok, src = pcall(
        C_DamageMeter.GetCombatSessionSourceFromType,
        Enum.DamageMeterSessionType.Current,
        Enum.DamageMeterType.DamageTaken,
        pGUID
    )
    if not ok then
        print("|cffff4444[MobC DM]|r Error: " .. tostring(src))
        return
    end
    if not src then
        print("|cffffaa00[MobC DM]|r Session source is nil (try right after taking spell damage in combat).")
        return
    end
    if src.combatSpells then
        print("|cff00ff00[MobC DM]|r combatSpells count = " .. #src.combatSpells)
        for i, sp in ipairs(src.combatSpells) do
            local sName = "?"
            if NS.IsSafe(sp.spellID) and type(sp.spellID) == "number" then
                local info = C_Spell.GetSpellInfo(sp.spellID)
                if info and info.name then
                    sName = info.name
                end
            end
            print(string.format(
                "  [%d] spellID=%s (%s) creatureName=%s total=%s ignored=%s",
                i,
                fmt(sp.spellID),
                sName,
                fmt(sp.creatureName),
                fmt(sp.totalAmount),
                tostring(NS.IsSafe(sp.spellID) and IGNORED_DAMAGE_TAKEN_SPELLS[sp.spellID] == true)
            ))
        end
    else
        local keys = {}
        for k, v in pairs(src) do
            table.insert(keys, tostring(k) .. "=" .. fmt(v))
        end
        print("|cffffaa00[MobC DM]|r Source keys: " .. table.concat(keys, ", "))
    end
end

-- =========================================================================
-- Midnight Secret-Safe Helper Functions
-- =========================================================================

local function SafeVal(val)
    if NS.IsSecret(val) then
        return nil
    end
    return val
end

local function SafeUnitGUID(unit)
    if not NS.IsSafe(unit) or type(unit) ~= "string" then
        return nil
    end
    return SafeVal(UnitGUID(unit))
end

local function SafeUnitName(unit)
    if not NS.IsSafe(unit) or type(unit) ~= "string" then
        return nil
    end
    return SafeVal(UnitName(unit))
end

local function SafeParseCreatureGUID(guid)
    if not NS.IsSafe(guid) or type(guid) ~= "string" then
        return nil
    end
    local unitType, _, _, _, _, npcID = strsplit("-", guid)
    if unitType == "Creature" or unitType == "Vehicle" then
        return tonumber(npcID)
    end
    return nil
end

local function ClearCombatCaches()
    engagedGUIDs = {}
    seenAliveGUIDs = {}
    killedGUIDs = {}
    recentBossKills = {}
    lootCache = {}
    tempSpellCache = {}
    combatSessionNpcIDs = {}
    pendingNpcSpells = {}
    lastTargetGUID = nil
end

local function GetLatestDamageMeterSessionID()
    if not C_DamageMeter or not C_DamageMeter.GetAvailableCombatSessions then
        return nil
    end
    local ok, sessions = pcall(C_DamageMeter.GetAvailableCombatSessions)
    if not ok or type(sessions) ~= "table" or #sessions == 0 then
        return nil
    end
    local maxID = nil
    for _, s in ipairs(sessions) do
        if s and NS.IsSafe(s.sessionID) and type(s.sessionID) == "number" then
            if not maxID or s.sessionID > maxID then
                maxID = s.sessionID
            end
        end
    end
    return maxID
end

local function IsIgnoredPlayerOrBasicSpell(spellID)
    if IGNORED_DAMAGE_TAKEN_SPELLS[spellID] then
        return true
    end
    if IsPlayerSpell and IsPlayerSpell(spellID) then
        return true
    end
    return false
end

local function HarvestDamageMeterSpells(foughtNpcs)
    if inCombat then
        return
    end
    if not C_DamageMeter or not Enum or not Enum.DamageMeterSessionType or not Enum.DamageMeterType then
        return
    end

    -- Deduplicate so we never re-attribute a previous combat session to a new mob
    local latestSessionID = GetLatestDamageMeterSessionID()
    if latestSessionID ~= nil then
        if latestSessionID == lastProcessedDMSessionID then
            return
        end
        lastProcessedDMSessionID = latestSessionID
    end

    local pGUID = SafeUnitGUID("player")
    if not pGUID then
        return
    end

    local ok, src = pcall(
        C_DamageMeter.GetCombatSessionSourceFromType,
        Enum.DamageMeterSessionType.Current,
        Enum.DamageMeterType.DamageTaken,
        pGUID
    )
    if not ok or not src or not src.combatSpells or #src.combatSpells == 0 then
        return
    end

    -- Count distinct enemy npcIDs engaged during this combat
    local npcCount = 0
    local singleNpcID = nil
    for npcID, _ in pairs(foughtNpcs) do
        npcCount = npcCount + 1
        singleNpcID = npcID
    end

    if npcCount == 0 then
        return
    end

    local addedAny = false
    for _, sp in ipairs(src.combatSpells) do
        local spellID = sp.spellID
        if NS.IsSafe(spellID) and type(spellID) == "number" and not IsIgnoredPlayerOrBasicSpell(spellID) then
            local spellInfo = C_Spell.GetSpellInfo(spellID)
            if spellInfo and spellInfo.name then
                local targetNpcID = nil

                -- 1. If Blizzard populated creatureName, match it against the fought enemies
                if NS.IsSafe(sp.creatureName) and sp.creatureName ~= "" then
                    local lowerCreature = strlower(sp.creatureName)
                    for npcID, _ in pairs(foughtNpcs) do
                        local meta = npcMetaCache[npcID]
                        local dbEntry = MobCompendiumDB and MobCompendiumDB[npcID]
                        local candidateName = (meta and meta.name) or (dbEntry and dbEntry.name)
                        if candidateName and strlower(candidateName) == lowerCreature then
                            targetNpcID = npcID
                            break
                        end
                    end
                end

                -- 2. Otherwise, if only 1 enemy type was fought in this combat, attribute cleanly to it
                if not targetNpcID and npcCount == 1 then
                    targetNpcID = singleNpcID
                end

                if targetNpcID then
                    local entry = MobCompendiumDB and MobCompendiumDB[targetNpcID]
                    if entry then
                        if not entry.spells then
                            entry.spells = {}
                        end
                        if not entry.spells[spellID] then
                            entry.spells[spellID] = true
                            addedAny = true
                            if debugMode then
                                print(string.format("|cff00ff00[MobC Debug]|r Recorded post-combat spell %d (%s) for npcID %d", spellID, spellInfo.name, targetNpcID))
                            end
                        end
                    else
                        -- Mob might be looted a second later; buffer briefly
                        if not pendingNpcSpells[targetNpcID] then
                            pendingNpcSpells[targetNpcID] = { spells = {}, time = GetTime() }
                        end
                        pendingNpcSpells[targetNpcID].spells[spellID] = true
                        pendingNpcSpells[targetNpcID].time = GetTime()
                    end
                end
            end
        end
    end

    if addedAny and NS.UpdateUI then
        NS.UpdateUI()
    end
end

-- Gets the unit rank for a unit (e.g. Critter, Elite, Rare)
local function ResolveRank(unitToken)
    if not NS.IsSafe(unitToken) then
        return "unknown"
    end

    if SafeVal(UnitIsWildBattlePet(unitToken)) then
        return "wildpet"
    end

    local cType = SafeVal(UnitCreatureType(unitToken))
    if cType == "Critter" then
        return "critter"
    end

    local c = SafeVal(UnitClassification(unitToken))
    if c == "worldboss" then
        return "boss"
    elseif c == "rareelite" then
        return "rareelite"
    elseif c == "elite" then
        return "elite"
    elseif c == "rare" then
        return "rare"
    elseif c == "minus" then
        return "minion"
    elseif c == "normal" then
        return "normal"
    end

    return "unknown"
end

local function GetContinentName(mapID)
    if not mapID then
        return nil
    end

    local currentMapID = mapID
    local loopSafety = 0

    while currentMapID and loopSafety < 10 do
        local info = C_Map.GetMapInfo(currentMapID)
        if not info then
            break
        end

        if info.mapType == Enum.UIMapType.Continent then
            return info.name
        end

        if info.mapType == Enum.UIMapType.Cosmic or info.mapType == Enum.UIMapType.World then
            return nil
        end

        currentMapID = info.parentMapID
        loopSafety = loopSafety + 1
    end

    return nil
end

local function GetLocationData()
    local mapID = C_Map.GetBestMapForUnit("player")
    local zoneName = "Unknown Zone"
    local parentMapName = nil

    if mapID then
        local mapInfo = C_Map.GetMapInfo(mapID)
        if mapInfo and mapInfo.name then
            zoneName = mapInfo.name
        end
    end

    local instName, instanceType, difficultyID, _, _, _, _, instanceID = GetInstanceInfo()
    local isInInstance = NS.IsInstanceType(instanceType)

    if isInInstance and instName and instName ~= "" then
        parentMapName = instName
        if zoneName == "Unknown Zone" then
            zoneName = instName
        end
    else
        parentMapName = GetContinentName(mapID)
        if not parentMapName and mapID then
            local mapInfo = C_Map.GetMapInfo(mapID)
            if mapInfo and mapInfo.parentMapID then
                local pInfo = C_Map.GetMapInfo(mapInfo.parentMapID)
                if pInfo then
                    parentMapName = pInfo.name
                end
            end
        end
    end

    if zoneName then
        zoneName = zoneName:gsub("%s*%(Surface%)", "")
        if string.match(zoneName, "^%d") then
            zoneName = "Unknown Zone"
        end
    end
    if parentMapName then
        parentMapName = parentMapName:gsub("%s*%(Surface%)", "")
        if string.match(parentMapName, "^%d") then
            parentMapName = nil
        end
    end
    if parentMapName == zoneName then
        zoneName = "General"
    end
    if not parentMapName then
        parentMapName = "Unknown Region"
    end

    local shortDiff = ""

    if isInInstance and difficultyID then
        -- PARTY
        if difficultyID == 1 or difficultyID == 205 then
            shortDiff = "N"       -- Normal / Follower (5 player)
        elseif difficultyID == 2 then
            shortDiff = "H"       -- Heroic (5 player)
        elseif difficultyID == 23 then
            shortDiff = "M"       -- Mythic (5 player)
        elseif difficultyID == 8 then
            shortDiff = "M"       -- Mythic Keystone
        elseif difficultyID == 24 then
            shortDiff = "TW"      -- Timewalking (5 player)

        -- RAID
        elseif difficultyID == 14 or difficultyID == 3 or difficultyID == 4 then
            shortDiff = "N"       -- Normal (Flex / Legacy)
        elseif difficultyID == 15 or difficultyID == 5 or difficultyID == 6 then
            shortDiff = "H"       -- Heroic (Flex / Legacy)
        elseif difficultyID == 16 then
            shortDiff = "M"       -- Mythic (20 player)
        elseif difficultyID == 17 or difficultyID == 7 or difficultyID == 151 then
            shortDiff = "LFR"     -- LFR (Flex / Legacy / Event)
        elseif difficultyID == 33 then
            shortDiff = "TW"      -- Timewalking Raid
        elseif difficultyID == 220 then
            shortDiff = "Story"   -- Story Mode Raid

        -- DELVES & SCENARIOS
        elseif difficultyID == 208 then
            shortDiff = "Delve"
        elseif instanceType == "scenario" then
            shortDiff = ""
        end
    end

    local baseID = mapID or instanceID or "Unknown"

    local encounterKey = baseID
    if isInInstance and difficultyID then
        encounterKey = baseID .. ":" .. difficultyID
    end

    return {
        mapID = mapID,
        zoneName = zoneName,
        parentMapName = parentMapName,
        instType = instanceType or "none",
        shortDiff = shortDiff,
        encounterKey = encounterKey,
        isInInstance = isInInstance
    }
end

-- =========================================================================
-- Database Persistence Helpers
-- =========================================================================

local function FlushSpellsToEntry(entry, guid)
    if not guid or not tempSpellCache[guid] then
        return
    end
    if not entry.spells then
        entry.spells = {}
    end
    for spellID, _ in pairs(tempSpellCache[guid]) do
        entry.spells[spellID] = true
    end
    tempSpellCache[guid] = nil
end

local function RecordMobKill(npcID, mobName, rank, creatureType, sourceGUID)
    if not npcID then
        return false
    end

    local meta = npcMetaCache[npcID]
    local finalName = mobName or (meta and meta.name) or "Unknown (Looted)"
    local finalRank = (rank and rank ~= "unknown") and rank or (meta and meta.rank) or "unknown"
    local finalType = creatureType or (meta and meta.type)

    local location = GetLocationData()

    local posX, posY = nil, nil
    if location.mapID and not location.isInInstance then
        local pos = C_Map.GetPlayerMapPosition(location.mapID, "player")
        if pos then
            posX, posY = pos.x * 100, pos.y * 100
        end
    end

    local currentTime = date("%Y-%m-%d %H:%M")
    local newMob = false

    if not MobCompendiumDB[npcID] then
        MobCompendiumDB[npcID] = {
            name = finalName,
            spells = {},
            encounters = {}
        }
        newMob = true
        if MobCompendiumDB.settings and MobCompendiumDB.settings.printNew then
            print("|cff00ffffMobCompendium:|r Discovered " .. finalName .. " (" .. (finalType or "Unknown") .. ")!")
        end
    end

    local entry = MobCompendiumDB[npcID]
    FlushSpellsToEntry(entry, sourceGUID)

    -- Flush any spells harvested from C_DamageMeter right before looting this mob
    local pending = pendingNpcSpells[npcID]
    if pending and (GetTime() - pending.time) < 60 then
        if not entry.spells then
            entry.spells = {}
        end
        for sID, _ in pairs(pending.spells) do
            entry.spells[sID] = true
        end
        pendingNpcSpells[npcID] = nil
    end

    combatSessionNpcIDs[npcID] = true

    if finalName and finalName ~= "Unknown (Looted)" then
        entry.name = finalName
    end

    if not entry.encounters[location.encounterKey] then
        entry.encounters[location.encounterKey] = {
            zoneName = location.zoneName,
            parentMap = location.parentMapName,
            instType = location.instType,
            diffName = location.shortDiff,
            drops = {},
            kills = 0,
            rank = finalRank,
            type = finalType
        }
    end

    local encounter = entry.encounters[location.encounterKey]
    encounter.kills = (encounter.kills or 0) + 1
    encounter.lastX = posX
    encounter.lastY = posY
    encounter.lastTime = currentTime
    encounter.zoneName = location.zoneName
    encounter.parentMap = location.parentMapName
    encounter.instType = location.instType
    encounter.diffName = location.shortDiff

    if (encounter.rank or "unknown") == "unknown" and finalRank ~= "unknown" then
        encounter.rank = finalRank
    end
    if not encounter.type and finalType then
        encounter.type = finalType
    end

    if not newMob and MobCompendiumDB.settings and MobCompendiumDB.settings.printUpdate then
        local printZone = location.zoneName
        if location.shortDiff ~= "" then
            printZone = printZone .. " (" .. location.shortDiff .. ")"
        end
        print("|cffaaaaaaMobCompendium:|r Recorded " .. entry.name .. " (Total Kills in " .. printZone .. ": " .. encounter.kills .. ")")
    end

    if sourceGUID then
        killedGUIDs[sourceGUID] = true
        engagedGUIDs[sourceGUID] = nil
        seenAliveGUIDs[sourceGUID] = nil
    end

    if NS.UpdateUI then
        NS.UpdateUI()
    end

    return true
end

-- Upgrades an existing "Unknown (Looted)" or incomplete DB entry when the player later hovers/targets the mob or corpse
local function UpgradeExistingEntryMetadata(npcID, name, rank, creatureType)
    local entry = MobCompendiumDB and MobCompendiumDB[npcID]
    if not entry then
        return
    end

    local changed = false
    if name and (not entry.name or entry.name == "Unknown (Looted)") then
        entry.name = name
        changed = true
    end

    if entry.encounters then
        for _, enc in pairs(entry.encounters) do
            if rank and rank ~= "unknown" and (not enc.rank or enc.rank == "unknown") then
                enc.rank = rank
                changed = true
            end
            if creatureType and not enc.type then
                enc.type = creatureType
                changed = true
            end
        end
    end

    if changed and NS.UpdateUI then
        NS.UpdateUI()
    end
end

-- =========================================================================
-- Engagement & Observation Logic (Engage-Only, Midnight-Safe)
-- =========================================================================

local function CacheUnitMetadata(unit, npcID)
    local name = SafeUnitName(unit)
    local rank = ResolveRank(unit)
    local cType = SafeVal(UnitCreatureType(unit))

    local existing = npcMetaCache[npcID]
    if not existing then
        existing = {}
        npcMetaCache[npcID] = existing
    end

    if name then
        existing.name = name
    end
    if rank and rank ~= "unknown" then
        existing.rank = rank
    elseif not existing.rank then
        existing.rank = "unknown"
    end
    if cType then
        existing.type = cType
    end
    existing.lastSeen = GetTime()

    UpgradeExistingEntryMetadata(npcID, existing.name, existing.rank, existing.type)
    return existing
end

local function IsUnitTargetingGroup(unit)
    local targetUnit = unit .. "target"
    if not SafeVal(UnitExists(targetUnit)) then
        return false
    end
    if SafeVal(UnitIsUnit(targetUnit, "player")) then
        return true
    end
    if SafeVal(UnitIsUnit(targetUnit, "pet")) then
        return true
    end
    if SafeVal(UnitInParty(targetUnit)) or SafeVal(UnitInRaid(targetUnit)) then
        return true
    end
    return false
end

local function IsUnitEngagedWithGroup(unit)
    local tapDenied = SafeVal(UnitIsTapDenied(unit))
    if tapDenied == true then
        return false
    end

    -- Player is directly on the mob's threat table
    local threat = SafeVal(UnitThreatSituation("player", unit))
    if threat ~= nil then
        return true
    end

    -- Mob is actively targeting us, our pet, or a party/raid member
    if IsUnitTargetingGroup(unit) then
        return true
    end

    -- Mob is in combat while we are in combat and it is our active target
    local unitInCombat = SafeVal(UnitAffectingCombat(unit))
    if unitInCombat and inCombat and SafeVal(UnitIsUnit(unit, "target")) then
        return true
    end

    return false
end

local function MarkEngaged(guid, npcID, meta)
    engagedGUIDs[guid] = {
        npcID = npcID,
        name = meta and meta.name or nil,
        rank = meta and meta.rank or "unknown",
        type = meta and meta.type or nil,
        time = GetTime()
    }
    if npcID then
        combatSessionNpcIDs[npcID] = true
    end
end

local function TryConfirmKillFromUnit(unit, guid, npcID, meta)
    if killedGUIDs[guid] then
        return
    end

    -- Never log kills clearly tapped by someone else
    if SafeVal(UnitIsTapDenied(unit)) == true then
        return
    end

    local inInstance = select(1, IsInInstance())
    local timeout = inInstance and 1800 or 180
    local now = GetTime()

    local eng = engagedGUIDs[guid]
    local isEngaged = eng and ((now - eng.time) < timeout)

    -- Handle 1-shot kills (e.g. critters or low-level mobs that die before combat/threat ticks)
    local isRecentOneShot = false
    if not isEngaged and seenAliveGUIDs[guid] then
        local recentAction = (now - lastPlayerActionTime) < 4
        if recentAction and (guid == lastTargetGUID or SafeVal(UnitIsUnit(unit, "target"))) then
            isRecentOneShot = true
        end
    end

    if isEngaged or isRecentOneShot then
        local name = (eng and eng.name) or (meta and meta.name) or SafeUnitName(unit)
        local rank = (eng and eng.rank ~= "unknown" and eng.rank) or (meta and meta.rank) or ResolveRank(unit)
        local cType = (eng and eng.type) or (meta and meta.type) or SafeVal(UnitCreatureType(unit))
        RecordMobKill(npcID, name, rank, cType, guid)
    end
end

local function ObserveUnit(unit)
    if not NS.IsSafe(unit) or type(unit) ~= "string" then
        return
    end
    if not SafeVal(UnitExists(unit)) then
        return
    end

    local guid = SafeUnitGUID(unit)
    local npcID = SafeParseCreatureGUID(guid)
    if not npcID then
        return
    end

    -- Ignore friendly NPCs unless we're upgrading an already-recorded entry
    local canAttack = SafeVal(UnitCanAttack("player", unit))
    local isFriend = SafeVal(UnitIsFriend("player", unit))
    if isFriend == true and canAttack ~= true then
        return
    end

    local meta = CacheUnitMetadata(unit, npcID)
    local isDead = SafeVal(UnitIsDead(unit))

    if isDead == true then
        TryConfirmKillFromUnit(unit, guid, npcID, meta)
        return
    end

    if canAttack == true then
        seenAliveGUIDs[guid] = true

        if unit == "target" then
            lastTargetGUID = guid
        end

        if IsUnitEngagedWithGroup(unit) then
            MarkEngaged(guid, npcID, meta)
        end
    end
end

local function ScanActiveUnits()
    for _, unit in ipairs(INSPECT_UNITS) do
        ObserveUnit(unit)
    end
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if SafeVal(UnitExists(unit)) then
            ObserveUnit(unit)
        end
    end
end

-- =========================================================================
-- DATABASE VERSIONING
-- =========================================================================

local function CheckDatabaseVersion()
    if MobCompendiumDB.dbVersion == nil then
        MobCompendiumDB = {}
        MobCompendiumDB.dbVersion = NS.DB_VERSION
        return
    end

    if MobCompendiumDB.dbVersion < NS.DB_VERSION then
        print("|cff00ffffMobCompendium:|r Database outdated (v" .. MobCompendiumDB.dbVersion .. "). Preparing structure for v" .. NS.DB_VERSION .. ".")
        MobCompendiumDB.dbVersion = NS.DB_VERSION
    end
end

-- =========================================================================
-- Event Functions
-- =========================================================================

local function OnAddonLoaded()
    if MobCompendiumDB == nil then
        MobCompendiumDB = {}
    end

    CheckDatabaseVersion()
    NS.InitSettings()
    print("|cff00ff00MobCompendium:|r Loaded successfully (Midnight Ready).")
end

local function OnPlayerEnterWorld()
    ClearCombatCaches()
    inCombat = SafeVal(UnitAffectingCombat("player")) == true
    lastProcessedDMSessionID = GetLatestDamageMeterSessionID()
end

-- Handles both LOOT_READY (reliable with fast auto-loot) and LOOT_OPENED
local function OnLootAvailable()
    local numItems = GetNumLootItems()
    if not numItems or numItems <= 0 then
        return
    end

    local location = GetLocationData()
    local foundNewData = false

    for i = 1, numItems do
        local sources = { GetLootSourceInfo(i) }
        for s = 1, #sources, 2 do
            local sourceGUID = sources[s]
            local npcID = SafeParseCreatureGUID(sourceGUID)

            if npcID and location.encounterKey then
                if not lootCache[sourceGUID] then
                    lootCache[sourceGUID] = {}
                end

                -- Confirm kill if this corpse wasn't already counted by live death detection or BOSS_KILL
                if not killedGUIDs[sourceGUID] then
                    local recentBossTime = recentBossKills[npcID]
                    local alreadyCountedAsBoss = recentBossTime and (GetTime() - recentBossTime < 60)

                    if alreadyCountedAsBoss then
                        killedGUIDs[sourceGUID] = true
                        FlushSpellsToEntry(MobCompendiumDB[npcID], sourceGUID)
                    else
                        local eng = engagedGUIDs[sourceGUID]
                        local meta = npcMetaCache[npcID]
                        local name = (eng and eng.name) or (meta and meta.name) or (MobCompendiumDB[npcID] and MobCompendiumDB[npcID].name) or "Unknown (Looted)"
                        local rank = (eng and eng.rank ~= "unknown" and eng.rank) or (meta and meta.rank) or "unknown"
                        local cType = (eng and eng.type) or (meta and meta.type)
                        RecordMobKill(npcID, name, rank, cType, sourceGUID)
                    end
                end

                -- Record dropped items
                if GetLootSlotType(i) == Enum.LootSlotType.Item then
                    local link = GetLootSlotLink(i)
                    if NS.IsSafe(link) then
                        local itemID = NS.GetItemInfoInstant(link)
                        if itemID and not lootCache[sourceGUID][itemID] then
                            local entry = MobCompendiumDB[npcID]
                            if entry then
                                if not entry.encounters then
                                    entry.encounters = {}
                                end
                                if not entry.encounters[location.encounterKey] then
                                    entry.encounters[location.encounterKey] = {
                                        zoneName = location.zoneName,
                                        parentMap = location.parentMapName,
                                        instType = location.instType,
                                        diffName = location.shortDiff,
                                        drops = {},
                                        kills = 0
                                    }
                                end
                                entry.encounters[location.encounterKey].drops[itemID] = true
                                lootCache[sourceGUID][itemID] = true
                                foundNewData = true
                            end
                        end
                    end
                end
            end
        end
    end

    if foundNewData and NS.UpdateUI then
        NS.UpdateUI()
    end
end

-- Records enemy spell casts when Midnight exposes non-secret unit & spell data
local function DescribeVal(val)
    if NS.IsSecret(val) then
        return "SECRET"
    end
    if val == nil then
        return "nil"
    end
    return tostring(val)
end

local function OnUnitSpellCast(event, unitTarget, _, spellID)
    if not NS.IsSafe(unitTarget) then
        if debugMode then
            print("|cffffaa00[MobC Debug]|r " .. tostring(event) .. " unitTarget=SECRET/nil")
        end
        return
    end

    -- Track player/pet offensive actions to catch 1-shot kills
    if unitTarget == "player" or unitTarget == "pet" then
        lastPlayerActionTime = GetTime()
        ObserveUnit("target")
        return
    end

    -- Fallback to UnitCastingInfo / UnitChannelInfo if event spellID is nil
    local castName, castSpellID
    if event == "UNIT_SPELLCAST_CHANNEL_START" then
        local name, _, _, _, _, _, _, sID = UnitChannelInfo(unitTarget)
        castName, castSpellID = name, sID
    else
        local name, _, _, _, _, _, _, _, sID = UnitCastingInfo(unitTarget)
        castName, castSpellID = name, sID
    end

    local resolvedSpellID = spellID
    if not NS.IsSafe(resolvedSpellID) and NS.IsSafe(castSpellID) then
        resolvedSpellID = castSpellID
    end

    local rawGUID = UnitGUID(unitTarget)
    local guid = SafeVal(rawGUID)
    local npcID = SafeParseCreatureGUID(guid)

    if debugMode then
        local castSecretFlag = "n/a"
        if C_Secrets and C_Secrets.ShouldUnitSpellCastingBeSecret then
            local ok, res = pcall(C_Secrets.ShouldUnitSpellCastingBeSecret, unitTarget)
            if ok then
                castSecretFlag = tostring(res)
            end
        end
        print(string.format(
            "|cffffaa00[MobC Debug]|r %s unit=%s spellID=%s castInfo=(%s, %s) guid=%s npcID=%s castingSecret=%s",
            tostring(event),
            tostring(unitTarget),
            DescribeVal(spellID),
            DescribeVal(castName),
            DescribeVal(castSpellID),
            NS.IsSecret(rawGUID) and "SECRET" or (guid and "OK" or "nil"),
            tostring(npcID),
            castSecretFlag
        ))
    end

    if not NS.IsSafe(resolvedSpellID) or type(resolvedSpellID) ~= "number" then
        return
    end

    if not npcID then
        return
    end

    if SafeVal(UnitCanAttack("player", unitTarget)) ~= true then
        return
    end

    local meta = CacheUnitMetadata(unitTarget, npcID)
    local isEngaged = engagedGUIDs[guid] ~= nil or IsUnitEngagedWithGroup(unitTarget)

    if isEngaged then
        MarkEngaged(guid, npcID, meta)
        if MobCompendiumDB[npcID] then
            if not MobCompendiumDB[npcID].spells then
                MobCompendiumDB[npcID].spells = {}
            end
            if not MobCompendiumDB[npcID].spells[resolvedSpellID] then
                MobCompendiumDB[npcID].spells[resolvedSpellID] = true
                if debugMode then
                    print("|cff00ff00[MobC Debug]|r Saved spell " .. resolvedSpellID .. " directly to npcID " .. npcID)
                end
                if NS.UpdateUI then
                    NS.UpdateUI()
                end
            end
            return
        end
    end

    -- Buffer until engagement + defeat is confirmed
    if not tempSpellCache[guid] then
        tempSpellCache[guid] = {}
    end
    tempSpellCache[guid][resolvedSpellID] = true
    if debugMode then
        print("|cff00ffff[MobC Debug]|r Buffered spell " .. resolvedSpellID .. " for npcID " .. npcID .. " (engaged=" .. tostring(isEngaged) .. ")")
    end
end

-- Records Dungeon / Raid boss kills reliably even when combat telemetry is redacted
local function TryRecordBossByName(encounterName)
    if not NS.IsSafe(encounterName) or encounterName == "" then
        return false
    end

    local lowerEnc = strlower(encounterName)

    -- 1. Check engaged GUIDs first
    for guid, eng in pairs(engagedGUIDs) do
        if eng.name and strlower(eng.name) == lowerEnc and not killedGUIDs[guid] then
            recentBossKills[eng.npcID] = GetTime()
            RecordMobKill(eng.npcID, eng.name, "boss", eng.type, guid)
            return true
        end
    end

    -- 2. Check recently observed NPC metadata (e.g. pre-pull target/mouseover)
    local bestNpcID, bestMeta, bestTime = nil, nil, 0
    for npcID, meta in pairs(npcMetaCache) do
        if meta.name and strlower(meta.name) == lowerEnc and (meta.lastSeen or 0) > bestTime then
            bestNpcID = npcID
            bestMeta = meta
            bestTime = meta.lastSeen or 0
        end
    end

    if bestNpcID and (GetTime() - bestTime) < 1800 then
        recentBossKills[bestNpcID] = GetTime()
        RecordMobKill(bestNpcID, bestMeta.name, "boss", bestMeta.type, nil)
        return true
    end

    return false
end

local function OnBossKill(_, encounterName)
    ScanActiveUnits()
    if TryRecordBossByName(encounterName) then
        return
    end

    -- Combat just ended; retry briefly in case boss unit tokens became non-secret
    C_Timer.After(0.5, function()
        ScanActiveUnits()
        TryRecordBossByName(encounterName)
    end)
end

-- =========================================================================
-- Event Handlers
-- =========================================================================

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:RegisterEvent("PLAYER_FOCUS_CHANGED")
frame:RegisterEvent("PLAYER_SOFT_ENEMY_CHANGED")
frame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
frame:RegisterEvent("UNIT_HEALTH")
frame:RegisterEvent("UNIT_FLAGS")
frame:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
frame:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
frame:RegisterEvent("UNIT_TARGET")
frame:RegisterEvent("UNIT_SPELLCAST_START")
frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
frame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
frame:RegisterEvent("UNIT_SPELLCAST_EMPOWER_START")
frame:RegisterEvent("LOOT_READY")
frame:RegisterEvent("LOOT_OPENED")
frame:RegisterEvent("BOSS_KILL")

frame:SetScript("OnEvent", function(_, event, arg1, arg2, arg3)
    if event == "ADDON_LOADED" then
        if arg1 == "MobCompendium" then
            OnAddonLoaded()
        end
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        OnPlayerEnterWorld()
        return
    end

    if event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
        combatSessionNpcIDs = {}
        lastPlayerActionTime = GetTime()
        ScanActiveUnits()
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
        ScanActiveUnits()
        local foughtSnapshot = combatSessionNpcIDs
        combatSessionNpcIDs = {}
        C_Timer.After(0.3, function()
            HarvestDamageMeterSpells(foughtSnapshot)
        end)
        return
    end

    if event == "PLAYER_TARGET_CHANGED" then
        ObserveUnit("target")
        return
    end

    if event == "PLAYER_FOCUS_CHANGED" then
        ObserveUnit("focus")
        return
    end

    if event == "PLAYER_SOFT_ENEMY_CHANGED" then
        ObserveUnit("softenemy")
        return
    end

    if event == "UPDATE_MOUSEOVER_UNIT" then
        ObserveUnit("mouseover")
        return
    end

    if event == "NAME_PLATE_UNIT_ADDED" or event == "UNIT_HEALTH" or event == "UNIT_FLAGS"
        or event == "UNIT_THREAT_LIST_UPDATE" or event == "UNIT_THREAT_SITUATION_UPDATE"
        or event == "UNIT_TARGET" then
        if NS.IsSafe(arg1) then
            ObserveUnit(arg1)
        end
        return
    end

    if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_SUCCEEDED"
        or event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_EMPOWER_START" then
        OnUnitSpellCast(event, arg1, arg2, arg3)
        return
    end

    if event == "LOOT_READY" or event == "LOOT_OPENED" then
        OnLootAvailable()
        return
    end

    if event == "BOSS_KILL" then
        OnBossKill(arg1, arg2)
        return
    end
end)
