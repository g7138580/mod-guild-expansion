-- mod-guild-expansion (acore_characters): quartermaster purchases with a per-character limit.

CREATE TABLE IF NOT EXISTS `mod_gspe_qm_purchase` (
  `guid` INT UNSIGNED NOT NULL COMMENT 'character',
  `stock_id` SMALLINT UNSIGNED NOT NULL COMMENT 'mod_gspe_qm_stock.id',
  `count` SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`guid`, `stock_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
COMMENT='mod-guild-expansion: quartermaster purchases per character';
