--[[✅ Full Database Synchronization Between rcore_gangs and Qbox Core

This bridge ensures that when you create, join, leave, or delete a gang using rcore_gangs, it automatically stays synced with Qbox Core’s player and gang data — including:

rcore_gangs internal database

qbx_gangs table

qbx_player_groups table

players.metadata.gang

players.ganginfo

⚙️ Features Matrix
Action	         rcore_gangs	Qbox gangs	Qbox player_groups	          Qbox players.metadata.gang	Qbox players.ganginfo
Create gang	         ✅	          ✅	             ✅ (entry only)	                  ❌	                         ❌
Add leader	         ✅	          ✅	             ✅	                              ✅	                         ✅
Add member	         ✅	          ✅	             ✅	                              ✅	                         ✅
Remove member	     ✅	          ❌	             ✅ (removed)	                  ✅ (cleared)	             ✅ (cleared)
Player leaves	     ✅	          ❌	             ✅ (removed)	                  ✅ (cleared)	             ✅ (cleared)
Delete gang	         ✅	          ✅ (removed)	 ✅ (removed)	                  ✅ (cleared)	             ✅ (cleared)


INSTALLATION

Run these into your sql database using a new query


🧩 Run these into your sql database using a new query]]

-- =====================================================
-- 1️⃣ Add ganginfo JSON column to players table
-- =====================================================
ALTER TABLE `players`
ADD COLUMN IF NOT EXISTS `ganginfo` LONGTEXT NULL DEFAULT NULL COLLATE 'utf8mb4_bin',
ADD CONSTRAINT IF NOT EXISTS `chk_ganginfo` CHECK (json_valid(`ganginfo`));

-- =====================================================
-- 2️⃣ Ensure player_groups table exists with correct FK
-- =====================================================
CREATE TABLE IF NOT EXISTS `player_groups` (
    `citizenid` VARCHAR(50) NOT NULL COLLATE 'utf8mb4_unicode_ci',
    `group` VARCHAR(50) NOT NULL COLLATE 'utf8mb4_unicode_ci',
    `type` VARCHAR(50) NOT NULL COLLATE 'utf8mb4_unicode_ci',
    `grade` TINYINT(3) UNSIGNED NOT NULL,
    PRIMARY KEY (`citizenid`, `type`, `group`) USING BTREE,
    CONSTRAINT `fk_citizenid` FOREIGN KEY (`citizenid`)
        REFERENCES `players` (`citizenid`) ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =====================================================
-- 3️⃣ Add missing columns to gangs table if needed
-- =====================================================
ALTER TABLE `gangs`
ADD COLUMN IF NOT EXISTS `identifier` VARCHAR(255) NOT NULL AFTER `id`,
ADD COLUMN IF NOT EXISTS `tag` VARCHAR(10) NOT NULL AFTER `identifier`,
ADD COLUMN IF NOT EXISTS `group` VARCHAR(24) NULL DEFAULT NULL AFTER `color`,
ADD UNIQUE INDEX IF NOT EXISTS `gangs_ui_tag` (`tag`),
ADD UNIQUE INDEX IF NOT EXISTS `gangs_ui_name` (`name`);


--[[Apply the above ALTER TABLE statements to your Qbox database.



------NEXT STEP------

Head into your rcore_gangs/server/database/api.lua

Search for this

SQL.InsertGang = function(playerId, color, group, tag, name, gangInfo)


From this line down to where it says 'end'

replace that function with this:]]

    SQL.InsertGang = function(playerId, color, group, tag, name, gangInfo)
    -- Try insert, ignore if tag already exists
    SQL.Execute([[
        INSERT INTO gangs
        (`identifier`, `color`, `group`, `tag`, `name`)
        VALUES
        (@playerId, @color, @group, @tag, @name)
        ON DUPLICATE KEY UPDATE `color` = @color, `group` = @group, `name` = @name
    ]], {
        ['@playerId'] = playerId,
        ['@color'] = color,
        ['@group'] = group,
        ['@tag'] = tag,
        ['@name'] = name
    })

    -- Update ganginfo in your framework table
    return SQL.Execute([[
        UPDATE ]] .. Config.FrameworkSQLTables.table .. [[ SET
            ganginfo = @gangInfo
        WHERE
            ]] .. Config.FrameworkSQLTables.identifier .. [[ = @playerId
    ]], {
        ['@gangInfo'] = gangInfo,
        ['@playerId'] = playerId
    })
end

--[[  ^^  This removes any faults or errors with duplicate gang names or tags



Place rcore_gangs_qbx_sync resource in your server.

It is important to start your bridge script after qbx_core and rcore_gangs like below

Add to server.cfg:

ensure rcore_gangs
ensure qbx_core
ensure rcore_gangs_qbx_sync


Restart server, create a new gang and then test /gang.

    🧩 Developer Notes

The bridge never inserts fake citizenids — prevents foreign key errors.

Works with the F10 gang menu from rcore_gangs.

Fully compatible with /gang and Qbox metadata expectations.


Frameworks: 
 × rcore_gangs (https://store.rcore.cz/)
 × Qbox Core  (https://www.qbox.re/)
