-- mod-guild-expansion (acore_characters): troops, mission effects and rare missions.

-- Troops are stored as units (their template has kind 2); vitality is the number of
-- missions a troop has left. 0 for champions.
ALTER TABLE `mod_gspe_unit`
  ADD COLUMN `vitality` TINYINT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'troops: missions left';

ALTER TABLE `mod_gspe_mission`
  ADD COLUMN `effect` TINYINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '0 none, 1 slowing, 2 lethal, 3 cursed, 4 costly',
  ADD COLUMN `rare` TINYINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '1 = rare mission';
