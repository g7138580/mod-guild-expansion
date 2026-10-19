-- mod-guild-expansion (acore_characters): milestone choices (every 25 guild levels from 50 to 225).

CREATE TABLE IF NOT EXISTS `mod_gspe_guild_milestone` (
  `guildid` INT UNSIGNED NOT NULL,
  `milestone` SMALLINT UNSIGNED NOT NULL COMMENT 'guild level of the milestone',
  `choice` TINYINT UNSIGNED NOT NULL COMMENT '1 or 2',
  PRIMARY KEY (`guildid`, `milestone`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
COMMENT='mod-guild-expansion: milestone choices per guild';
