-- mod-guild-single-player-expansion (acore_characters): guild missions.
-- One table holds the guild's board offers (state 0) and running missions (state 1).

CREATE TABLE IF NOT EXISTS `mod_gspe_mission` (
  `id` INT UNSIGNED NOT NULL,
  `guildid` INT UNSIGNED NOT NULL,
  `template` SMALLINT UNSIGNED NOT NULL,
  `state` TINYINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '0 offer, 1 running',
  `level` TINYINT UNSIGNED NOT NULL,
  `threats` VARCHAR(32) NOT NULL DEFAULT '' COMMENT 'comma-separated threat ids',
  `duration` INT UNSIGNED NOT NULL COMMENT 'seconds',
  `cost` INT UNSIGNED NOT NULL COMMENT 'guild supplies',
  `gold` INT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'copper',
  `supplies` INT UNSIGNED NOT NULL DEFAULT 0,
  `guild_xp` INT UNSIGNED NOT NULL DEFAULT 0,
  `unit_xp` INT UNSIGNED NOT NULL DEFAULT 0,
  `item` INT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'crafting material reward',
  `item_count` SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  `gear` TINYINT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'gear reward quality, 0 = none',
  `units` VARCHAR(48) NOT NULL DEFAULT '' COMMENT 'comma-separated unit ids, running only',
  `chance` SMALLINT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'success chance when started, 0-200',
  `ends` INT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'unix time the running mission completes',
  `expires` INT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'unix time the offer leaves the board',
  PRIMARY KEY (`id`),
  KEY `idx_guild` (`guildid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
COMMENT='mod-guild-single-player-expansion: mission board offers and running missions';
