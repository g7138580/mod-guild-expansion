-- mod-guild-single-player-expansion (acore_characters): guild units (champions).

CREATE TABLE IF NOT EXISTS `mod_gspe_unit` (
  `id` INT UNSIGNED NOT NULL,
  `guildid` INT UNSIGNED NOT NULL,
  `template` SMALLINT UNSIGNED NOT NULL,
  `name` VARCHAR(48) NOT NULL,
  `race` TINYINT UNSIGNED NOT NULL,
  `gender` TINYINT UNSIGNED NOT NULL,
  `quality` TINYINT UNSIGNED NOT NULL COMMENT '2 uncommon, 3 rare, 4 epic',
  `level` TINYINT UNSIGNED NOT NULL,
  `xp` INT UNSIGNED NOT NULL DEFAULT 0,
  `item_level` SMALLINT UNSIGNED NOT NULL,
  `ability1` TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `ability2` TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `trait1` TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `trait2` TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `status` TINYINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '0 idle, 1 on mission, 2 recruit candidate',
  `mission` INT UNSIGNED NOT NULL DEFAULT 0,
  `cost` INT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'supplies, candidates only',
  `expires` INT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'unix time, candidates only',
  PRIMARY KEY (`id`),
  KEY `idx_guild` (`guildid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
COMMENT='mod-guild-single-player-expansion: guild units and recruit candidates';

ALTER TABLE `mod_gspe_progress`
  ADD COLUMN `starter_units` TINYINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '1 once the starting units were granted';
