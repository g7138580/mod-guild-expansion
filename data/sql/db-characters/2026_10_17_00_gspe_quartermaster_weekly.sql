-- mod-guild-expansion (acore_characters): the quartermaster's weekly stock.

CREATE TABLE IF NOT EXISTS `mod_gspe_qm_weekly` (
  `guildid` INT UNSIGNED NOT NULL,
  `slot` TINYINT UNSIGNED NOT NULL COMMENT '3 material, 4-5 recipes, 6 curiosity',
  `week` INT UNSIGNED NOT NULL COMMENT 'weekly reset time the stock was rolled for',
  `item` INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '0 = nothing this week',
  `count` SMALLINT UNSIGNED NOT NULL DEFAULT 1,
  `cost` INT UNSIGNED NOT NULL DEFAULT 0,
  `bought_by` INT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'character that bought it, 0 = for sale',
  PRIMARY KEY (`guildid`, `slot`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
COMMENT='mod-guild-expansion: weekly quartermaster stock shared by the guild';

CREATE TABLE IF NOT EXISTS `mod_gspe_qm_weekly_gear` (
  `guid` INT UNSIGNED NOT NULL COMMENT 'character',
  `slot` TINYINT UNSIGNED NOT NULL COMMENT '1-2',
  `week` INT UNSIGNED NOT NULL,
  `item` INT UNSIGNED NOT NULL DEFAULT 0,
  `random_property` INT NOT NULL DEFAULT 0,
  `cost` INT UNSIGNED NOT NULL DEFAULT 0,
  `bought` TINYINT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`guid`, `slot`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
COMMENT='mod-guild-expansion: weekly quartermaster gear per character';
