-- mod-guild-expansion (acore_characters): Guild Points spent per track.
-- Points are earned from guild levels after 25; only where they are spent is stored.

CREATE TABLE IF NOT EXISTS `mod_gspe_guild_points` (
  `guildid` INT UNSIGNED NOT NULL,
  `track` TINYINT UNSIGNED NOT NULL,
  `points` SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`guildid`, `track`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
COMMENT='mod-guild-expansion: Guild Points spent per track';
