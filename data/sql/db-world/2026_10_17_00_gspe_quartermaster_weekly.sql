-- mod-guild-expansion (acore_world): pools for the quartermaster's weekly stock.
-- Weekly gear and recipes are picked by rule from the world's loot tables; materials and
-- curiosities come from these lists.
--
-- mod_gspe_qm_material:  one is offered per week, for the highest character level in the guild
-- mod_gspe_qm_curiosity: kind 1 pet, 2 mount; guild_level unlocks it; weight is the relative chance

DROP TABLE IF EXISTS `mod_gspe_qm_material`;
CREATE TABLE `mod_gspe_qm_material` (
  `item` INT UNSIGNED NOT NULL,
  `min_level` TINYINT UNSIGNED NOT NULL,
  `max_level` TINYINT UNSIGNED NOT NULL,
  `count` SMALLINT UNSIGNED NOT NULL DEFAULT 1,
  `cost` INT UNSIGNED NOT NULL,
  PRIMARY KEY (`item`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
COMMENT='mod-guild-expansion: weekly quartermaster materials';

INSERT INTO `mod_gspe_qm_material` (`item`, `min_level`, `max_level`, `count`, `cost`) VALUES
(7067, 20, 39, 5, 60),     -- Elemental Earth
(7068, 20, 39, 5, 60),     -- Elemental Fire
(7069, 20, 39, 5, 60),     -- Elemental Air
(7070, 20, 39, 5, 60),     -- Elemental Water
(7077, 40, 49, 3, 70),     -- Heart of Fire
(7075, 40, 49, 3, 70),     -- Core of Earth
(7079, 40, 49, 3, 70),     -- Globe of Water
(7081, 40, 49, 3, 70),     -- Breath of Wind
(7972, 40, 49, 3, 70),     -- Ichor of Undeath
(7910, 40, 49, 3, 70),     -- Star Ruby
(12360, 50, 59, 2, 80),    -- Arcanite Bar
(12803, 50, 59, 3, 80),    -- Living Essence
(7078, 50, 59, 3, 80),     -- Essence of Fire
(7080, 50, 59, 3, 80),     -- Essence of Water
(7082, 50, 59, 3, 80),     -- Essence of Air
(12808, 50, 59, 3, 80),    -- Essence of Undeath
(14344, 50, 59, 2, 80),    -- Large Brilliant Shard
(14342, 50, 59, 2, 80),    -- Mooncloth
(14256, 50, 59, 3, 80),    -- Felcloth
(13468, 60, 69, 2, 100),   -- Black Lotus
(23571, 60, 69, 2, 100),   -- Primal Might
(21884, 60, 69, 3, 100),   -- Primal Fire
(21885, 60, 69, 3, 100),   -- Primal Water
(21886, 60, 69, 3, 100),   -- Primal Life
(22451, 60, 69, 3, 100),   -- Primal Air
(22452, 60, 69, 3, 100),   -- Primal Earth
(22456, 60, 69, 3, 100),   -- Primal Shadow
(22457, 60, 69, 3, 100),   -- Primal Mana
(22794, 70, 79, 2, 110),   -- Fel Lotus
(22450, 70, 79, 1, 110),   -- Void Crystal
(30183, 70, 79, 1, 110),   -- Nether Vortex
(36860, 70, 79, 2, 110),   -- Eternal Fire
(35622, 70, 79, 2, 110),   -- Eternal Water
(35623, 70, 79, 2, 110),   -- Eternal Air
(35624, 70, 79, 2, 110),   -- Eternal Earth
(35625, 70, 79, 2, 110),   -- Eternal Life
(35627, 70, 79, 2, 110),   -- Eternal Shadow
(43102, 80, 255, 2, 120),  -- Frozen Orb
(36908, 80, 255, 2, 120),  -- Frost Lotus
(34057, 80, 255, 1, 120),  -- Abyss Crystal
(34052, 80, 255, 2, 120),  -- Dream Shard
(41163, 80, 255, 2, 120),  -- Titanium Bar
(36919, 80, 255, 1, 120),  -- Cardinal Ruby
(36922, 80, 255, 1, 120),  -- King's Amber
(36925, 80, 255, 1, 120),  -- Majestic Zircon
(36928, 80, 255, 1, 120),  -- Dreadstone
(36931, 80, 255, 1, 120),  -- Ametrine
(36934, 80, 255, 1, 120);  -- Eye of Zul

DROP TABLE IF EXISTS `mod_gspe_qm_curiosity`;
CREATE TABLE `mod_gspe_qm_curiosity` (
  `item` INT UNSIGNED NOT NULL,
  `kind` TINYINT UNSIGNED NOT NULL COMMENT '1 pet, 2 mount',
  `guild_level` TINYINT UNSIGNED NOT NULL DEFAULT 1,
  `cost` INT UNSIGNED NOT NULL,
  `weight` SMALLINT UNSIGNED NOT NULL DEFAULT 10,
  PRIMARY KEY (`item`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
COMMENT='mod-guild-expansion: weekly quartermaster pets and mounts';

INSERT INTO `mod_gspe_qm_curiosity` (`item`, `kind`, `guild_level`, `cost`, `weight`) VALUES
(46545, 1,  4,  250, 10),  -- Curious Oracle Hatchling
(46544, 1,  4,  250, 10),  -- Curious Wolvar Pup
(44738, 1,  8,  250, 10),  -- Kirin Tor Familiar
(25535, 1,  8,  250, 10),  -- Netherwhelp's Collar
(23712, 1, 12,  250, 10),  -- White Tiger Cub
(49662, 1, 12,  250, 10),  -- Gryphon Hatchling
(49663, 1, 12,  250, 10),  -- Wind Rider Cub
(49665, 1, 16,  250, 10),  -- Pandaren Monk
(54847, 1, 16,  250, 10),  -- Lil' XT
(49646, 1, 20,  250, 10),  -- Core Hound Pup
(56806, 1, 20,  250, 10),  -- Mini Thor
(43963, 2, 10, 1000, 10),  -- Reins of the Brown Polar Bear
(43964, 2, 15, 1500, 10),  -- Reins of the Black Polar Bear
(54860, 2, 16, 2500, 10),  -- X-53 Touring Rocket
(33182, 2, 18, 2500, 10),  -- Swift Flying Broom
(37719, 2, 18, 1500, 10),  -- Swift Zhevra
(30609, 2, 20, 3000, 10),  -- Swift Nether Drake
(54811, 2, 25, 4000, 10);  -- Celestial Steed
