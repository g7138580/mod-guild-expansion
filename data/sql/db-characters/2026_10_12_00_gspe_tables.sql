-- mod-guild-single-player-expansion (acore_characters)
-- Existing mod-guild-levels progress (`guild_progress`) is copied in at worldserver
-- startup if this table is empty.

CREATE TABLE IF NOT EXISTS `mod_gspe_progress` (
  `guildid` INT UNSIGNED NOT NULL,
  `xp` BIGINT UNSIGNED NOT NULL DEFAULT 0,
  `level` TINYINT UNSIGNED NOT NULL DEFAULT 1,
  `supplies` INT UNSIGNED NOT NULL DEFAULT 0,
  `today_xp` INT UNSIGNED NOT NULL DEFAULT 0,
  `week_xp` INT UNSIGNED NOT NULL DEFAULT 0,
  `last_daily_reset` INT UNSIGNED NOT NULL DEFAULT 0,
  `last_weekly_reset` INT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`guildid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
COMMENT='mod-guild-single-player-expansion: guild level, XP and supplies';

CREATE TABLE IF NOT EXISTS `mod_gspe_work_order` (
  `id` INT UNSIGNED NOT NULL,
  `guid` INT UNSIGNED NOT NULL COMMENT 'character',
  `kind` TINYINT UNSIGNED NOT NULL COMMENT '0 = craft, 1 = gather',
  `skill` SMALLINT UNSIGNED NOT NULL,
  `spell` INT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'recipe for craft orders',
  `item` INT UNSIGNED NOT NULL,
  `quantity` SMALLINT UNSIGNED NOT NULL,
  `level` TINYINT UNSIGNED NOT NULL,
  `gold` INT UNSIGNED NOT NULL,
  `supplies` INT UNSIGNED NOT NULL,
  `guild_xp` INT UNSIGNED NOT NULL,
  `expires` INT UNSIGNED NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_guid` (`guid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
COMMENT='mod-guild-single-player-expansion: open work orders per character';
