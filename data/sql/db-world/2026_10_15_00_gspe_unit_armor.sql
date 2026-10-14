-- mod-guild-expansion (acore_world): armor type each unit template can wear.
-- armor: 1 cloth, 2 leather, 3 mail, 4 plate, 0 none (troops can't be equipped).

ALTER TABLE `mod_gspe_unit_template`
  ADD COLUMN `armor` TINYINT UNSIGNED NOT NULL DEFAULT 0 AFTER `role`;

UPDATE `mod_gspe_unit_template` SET `armor` = 4 WHERE `id` IN (1, 2, 6, 17);          -- Warrior, Paladin, Death Knight, Draenei Vindicator
UPDATE `mod_gspe_unit_template` SET `armor` = 3 WHERE `id` IN (3, 7, 13, 14, 18, 20);  -- Hunter, Shaman, Kodo Rider, Dwarven Rifleman, Blood Elf Spellbreaker, Orcish Wolf Rider
UPDATE `mod_gspe_unit_template` SET `armor` = 2 WHERE `id` IN (4, 10, 11, 12, 15);     -- Rogue, Druid, Gnomish Engineer, Goblin Sapper, Night Elf Sentinel
UPDATE `mod_gspe_unit_template` SET `armor` = 1 WHERE `id` IN (5, 8, 9, 16, 19);       -- Priest, Mage, Warlock, Forsaken Apothecary, Troll Witch Doctor
