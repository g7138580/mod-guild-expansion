-- mod-guild-expansion (acore_characters): daily contracts.

CREATE TABLE IF NOT EXISTS `mod_gspe_contract` (
  `guid` INT UNSIGNED NOT NULL COMMENT 'character',
  `slot` TINYINT UNSIGNED NOT NULL,
  `kind` TINYINT UNSIGNED NOT NULL,
  `target` INT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'creature type or gathering skill, 0 = none',
  `needed` SMALLINT UNSIGNED NOT NULL,
  `progress` SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  `level` TINYINT UNSIGNED NOT NULL,
  `gold` INT UNSIGNED NOT NULL,
  `supplies` INT UNSIGNED NOT NULL,
  `guild_xp` INT UNSIGNED NOT NULL,
  `done` TINYINT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`guid`, `slot`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
COMMENT='mod-guild-expansion: the day''s contracts per character';

CREATE TABLE IF NOT EXISTS `mod_gspe_contract_day` (
  `guid` INT UNSIGNED NOT NULL COMMENT 'character',
  `day` INT UNSIGNED NOT NULL COMMENT 'daily reset time the contracts were rolled for',
  `rerolls` TINYINT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'rerolls used today',
  `extra_rerolls` TINYINT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'rerolls bought today',
  `bonus_paid` TINYINT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`guid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
COMMENT='mod-guild-expansion: contract rerolls and bonus per character and day';
