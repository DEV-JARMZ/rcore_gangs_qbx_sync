--[[
rcore_gangs ↔ Qbox Core Sync Bridge
Copyright (c) 2025 [Your Name]

This software is released under the MIT License.
You are free to use, modify, and distribute it, as long as this notice is included.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.
]]

---------------------------------------
-- Helper Functions
---------------------------------------

-- Sync gang in Qbox gangs table
local function syncGangToQbox(name, tag, color, group)
    if not name then return end

    local exists = MySQL.scalar.await('SELECT id FROM gangs WHERE name = ?', { name })
    if exists then
        MySQL.update.await(
            'UPDATE gangs SET tag = ?, color = ?, `group` = ? WHERE name = ?',
            { tag, color, group, name }
        )
        print(('[SYNC] Updated gang "%s" in Qbox gangs'):format(name))
    else
        MySQL.insert.await(
            'INSERT INTO gangs (identifier, tag, name, color, `group`, balance) VALUES (?, ?, ?, ?, ?, 0)',
            { 'system', tag, name, color, group }
        )
        print(('[SYNC] Created gang "%s" in Qbox gangs'):format(name))
    end
end

-- We no longer insert into player_groups during gang creation,
-- because that table only accepts valid citizenids (real players).
-- We'll just log the creation to keep track.
local function createGangInPlayerGroups(name)
    if not name then return end
    print(('[SYNC] Gang "%s" created — waiting for members to join before adding to player_groups'):format(name))
end

-- Assign a player to a gang in Qbox (updates metadata.gang, player_groups, and ganginfo)
local function assignPlayerToGang(src, gangName, rank)
    if not src or not gangName then return end
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return end
    local citizenid = player.PlayerData.citizenid

    -- 🧩 Fixed: Make grade a table, not a number
    local roleNames = {
        [0] = "Leader",
        [1] = "Co-Leader",
        [2] = "Member",
        [3] = "Prospect"
    }

    local gangData = {
        name = gangName,
        label = gangName,
        grade = {
            name = roleNames[rank or 2] or "Member",
            level = rank or 2
        }
    }

    -- Update metadata.gang
    exports.qbx_core:SetPlayerData(src, "gang", gangData)
    local gangJson = json.encode(gangData)
    MySQL.update.await(
        'UPDATE players SET metadata = JSON_SET(metadata, "$.gang", ?) WHERE citizenid = ?',
        { gangJson, citizenid }
    )

    -- Update ganginfo
    MySQL.update.await(
        'UPDATE players SET ganginfo = ? WHERE citizenid = ?',
        { gangJson, citizenid }
    )

    -- Add to player_groups
    MySQL.insert.await([[
        INSERT INTO player_groups (citizenid, `group`, type, grade)
        VALUES (?, ?, 'gang', ?)
        ON DUPLICATE KEY UPDATE grade = VALUES(grade)
    ]], { citizenid, gangName, rank or 0 })

    print(('[SYNC] Assigned player %s to gang "%s" with grade "%s" (%s)'):format(
        citizenid, gangName, gangData.grade.name, gangData.grade.level
    ))
end

-- Remove a player from a gang in Qbox (also clears ganginfo)
local function removePlayerFromGang(src, gangName)
    if not src then return end
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return end
    local citizenid = player.PlayerData.citizenid

    -- Clear metadata
    exports.qbx_core:SetPlayerData(src, "gang", nil)
    MySQL.update.await(
        'UPDATE players SET metadata = JSON_REMOVE(metadata, "$.gang") WHERE citizenid = ?',
        { citizenid }
    )

    -- Clear ganginfo
    MySQL.update.await(
        'UPDATE players SET ganginfo = NULL WHERE citizenid = ?',
        { citizenid }
    )

    -- Remove from player_groups
    if gangName then
        MySQL.update.await([[
            DELETE FROM player_groups
            WHERE citizenid = ? AND type = 'gang' AND `group` = ?
        ]], { citizenid, gangName })
    end

    print(('[SYNC] Removed player %s from gang "%s"'):format(citizenid, gangName or "unknown"))
end

-- Remove offline player from gang (for kicks)
local function removeOfflinePlayerFromGang(identifier, gangName)
    MySQL.update.await(
        [[UPDATE players SET metadata = JSON_REMOVE(metadata, "$.gang"), ganginfo = NULL WHERE citizenid = ? OR license = ?]],
        { identifier, identifier }
    )
    if gangName then
        MySQL.update.await([[
            DELETE FROM player_groups WHERE citizenid = ? AND type = 'gang' AND `group` = ?
        ]], { identifier, gangName })
    end
    print(('[SYNC] Removed offline player %s from gang "%s"'):format(identifier, gangName or "unknown"))
end

---------------------------------------
-- Event Listeners
---------------------------------------

-- 1️⃣ Create gang (F10 menu)
RegisterNetEvent('rcore_gangs:server:create_gang', function(leaderId, color, group, tag, name)
    if not name then return end

    -- Update Qbox databases
    syncGangToQbox(name, tag, color, group)
    createGangInPlayerGroups(name)

    -- Assign leader
    if leaderId then
        assignPlayerToGang(leaderId, name, 0)
    end
end)

-- 2️⃣ Internal gang registration
RegisterNetEvent('rcore_gangs:createdGang', function(_, gangData)
    if not gangData then return end
    syncGangToQbox(gangData.name, gangData.tag, gangData.color, gangData.group)
    createGangInPlayerGroups(gangData.name)
end)

-- 3️⃣ Add/promote member or leader
RegisterNetEvent('rcore_gangs:setGang', function(src, gangName, rank)
    assignPlayerToGang(src, gangName, rank)
end)

-- 4️⃣ Player leaves
RegisterNetEvent('rcore_gangs:server:leave', function()
    local src = source
    local player = exports.qbx_core:GetPlayer(src)
    if player and player.PlayerData.gang then
        removePlayerFromGang(src, player.PlayerData.gang.name)
    end
end)

-- 5️⃣ Player is kicked
RegisterNetEvent('rcore_gangs:server:kick_member', function(identifier)
    -- Check if player is online
    local targetSrc
    for _, playerId in pairs(GetPlayers()) do
        local player = exports.qbx_core:GetPlayer(tonumber(playerId))
        if player and (player.PlayerData.citizenid == identifier or player.PlayerData.license == identifier) then
            targetSrc = tonumber(playerId)
            break
        end
    end

    if targetSrc then
        local player = exports.qbx_core:GetPlayer(targetSrc)
        if player and player.PlayerData.gang then
            removePlayerFromGang(targetSrc, player.PlayerData.gang.name)
        end
    else
        removeOfflinePlayerFromGang(identifier, nil)
    end
end)

-- 6️⃣ Delete gang
RegisterNetEvent('rcore_gangs:deletedGang', function(_, gangName)
    if not gangName then return end

    -- Delete gang row
    MySQL.update.await('DELETE FROM gangs WHERE name = ?', { gangName })

    -- Remove all players from this gang in player_groups
    MySQL.update.await([[
        DELETE FROM player_groups
        WHERE type = 'gang' AND `group` = ?
    ]], { gangName })

    print(('[SYNC] Deleted gang "%s" from all Qbox tables'):format(gangName))
end)
