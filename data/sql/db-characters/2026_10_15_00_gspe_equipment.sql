-- mod-guild-expansion (acore_characters): unit equipment, promotions and mission consumables.

ALTER TABLE `mod_gspe_unit`
  ADD COLUMN `weapon_item` INT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'item entry given as the weapon',
  ADD COLUMN `weapon_ilvl` SMALLINT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'weapon item level incl. enchant and gem bonus',
  ADD COLUMN `armor_item` INT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'item entry given as the armor',
  ADD COLUMN `armor_ilvl` SMALLINT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'armor item level incl. enchant and gem bonus',
  ADD COLUMN `effect_item` INT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'item entry in the effect slot',
  ADD COLUMN `effect_kind` TINYINT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'effect of the effect-slot item',
  ADD COLUMN `promo_xp` INT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'XP earned at the level cap toward the next quality';

ALTER TABLE `mod_gspe_mission`
  ADD COLUMN `consumable` TINYINT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'kind of consumable sent with the running mission';
