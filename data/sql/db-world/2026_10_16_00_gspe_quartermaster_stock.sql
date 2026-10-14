-- mod-guild-expansion (acore_world): the guild quartermaster's fixed stock.
--
-- category:    1 bags, 2 profession tools, 3 consumables, 4 services
-- item/count:  item and stack size sold (0 for services)
-- service:     1 reroll recruit candidates, 2 reroll the mission board,
--              3 replace an abandoned work order now, 4 one more contract reroll today
-- cost:        guild supplies
-- guild_level: guild level that unlocks the row
-- min/max_level: character levels the row is shown to; consumable tiers use this so only
--              the tier for the character's level shows
-- char_limit:  purchases per character, 0 = no limit

DROP TABLE IF EXISTS `mod_gspe_qm_stock`;
CREATE TABLE `mod_gspe_qm_stock` (
  `id` SMALLINT UNSIGNED NOT NULL,
  `category` TINYINT UNSIGNED NOT NULL,
  `item` INT UNSIGNED NOT NULL DEFAULT 0,
  `count` SMALLINT UNSIGNED NOT NULL DEFAULT 1,
  `service` TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `cost` INT UNSIGNED NOT NULL,
  `guild_level` TINYINT UNSIGNED NOT NULL DEFAULT 1,
  `min_level` TINYINT UNSIGNED NOT NULL DEFAULT 1,
  `max_level` TINYINT UNSIGNED NOT NULL DEFAULT 255,
  `char_limit` SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
COMMENT='mod-guild-expansion: guild quartermaster fixed stock';

INSERT INTO `mod_gspe_qm_stock` (`id`, `category`, `item`, `count`, `service`, `cost`, `guild_level`, `min_level`, `max_level`, `char_limit`) VALUES
-- General bags
(101, 1, 14046, 1, 0,  60,  3, 1, 255, 0),   -- Runecloth Bag (14)
(102, 1, 21841, 1, 0, 120,  7, 1, 255, 0),   -- Netherweave Bag (16)
(103, 1, 21843, 1, 0, 200, 12, 1, 255, 0),   -- Imbued Netherweave Bag (18)
(104, 1, 41599, 1, 0, 300, 16, 1, 255, 0),   -- Frostweave Bag (20)
(105, 1, 41600, 1, 0, 750, 22, 1, 255, 4),   -- Glacial Bag (22)
-- Profession bags
(111, 1, 22252, 1, 0, 250,  9, 1, 255, 0),   -- Satchel of Cenarius (herbs)
(112, 1, 29540, 1, 0, 250,  9, 1, 255, 0),   -- Reinforced Mining Bag
(113, 1, 34490, 1, 0, 250,  9, 1, 255, 0),   -- Bag of Many Hides (leather)
(114, 1, 22249, 1, 0, 250,  9, 1, 255, 0),   -- Big Bag of Enchantment
(115, 1, 24270, 1, 0, 250,  9, 1, 255, 0),   -- Bag of Jewels
(116, 1, 23774, 1, 0, 250,  9, 1, 255, 0),   -- Fel Iron Toolbox (engineering)
(117, 1, 44446, 1, 0, 250,  9, 1, 255, 0),   -- Pack of Endless Pockets (inscription)
-- Profession tools
(201, 2,  6367, 1, 0,  40,  2, 1, 255, 1),   -- Big Iron Fishing Pole
(202, 2, 25978, 1, 0, 150, 10, 1, 255, 1),   -- Seth's Graphite Fishing Pole
(203, 2, 44050, 1, 0, 400, 18, 1, 255, 1),   -- Mastercraft Kalu'ak Fishing Pole
-- Healing potions (5)
(301, 3,   118, 5, 0, 10,  1,  1,   2, 0),   -- Minor
(302, 3,   858, 5, 0, 10,  1,  3,  11, 0),   -- Lesser
(303, 3,   929, 5, 0, 10,  1, 12,  20, 0),
(304, 3,  1710, 5, 0, 10,  1, 21,  34, 0),   -- Greater
(305, 3,  3928, 5, 0, 10,  1, 35,  44, 0),   -- Superior
(306, 3, 13446, 5, 0, 10,  1, 45,  54, 0),   -- Major
(307, 3, 22829, 5, 0, 10,  1, 55,  69, 0),   -- Super
(308, 3, 33447, 5, 0, 10,  1, 70, 255, 0),   -- Runic
-- Mana potions (5)
(311, 3,  2455, 5, 0, 10,  1,  5,  13, 0),   -- Minor
(312, 3,  3385, 5, 0, 10,  1, 14,  21, 0),   -- Lesser
(313, 3,  3827, 5, 0, 10,  1, 22,  30, 0),
(314, 3,  6149, 5, 0, 10,  1, 31,  40, 0),   -- Greater
(315, 3, 13443, 5, 0, 10,  1, 41,  48, 0),   -- Superior
(316, 3, 13444, 5, 0, 10,  1, 49,  54, 0),   -- Major
(317, 3, 22832, 5, 0, 10,  1, 55,  69, 0),   -- Super
(318, 3, 33448, 5, 0, 10,  1, 70, 255, 0),   -- Runic
-- Heavy bandages (10), need First Aid
(321, 3,  2581, 10, 0, 8,  1,  1,   9, 0),   -- Heavy Linen
(322, 3,  3531, 10, 0, 8,  1, 10,  19, 0),   -- Heavy Wool
(323, 3,  6451, 10, 0, 8,  1, 20,  29, 0),   -- Heavy Silk
(324, 3,  8545, 10, 0, 8,  1, 30,  44, 0),   -- Heavy Mageweave
(325, 3, 14530, 10, 0, 8,  1, 45,  59, 0),   -- Heavy Runecloth
(326, 3, 21991, 10, 0, 8,  1, 60,  69, 0),   -- Heavy Netherweave
(327, 3, 34722, 10, 0, 8,  1, 70, 255, 0),   -- Heavy Frostweave
-- Flasks (1), by tier
(331, 3, 13510, 1, 0, 30, 13, 50,  64, 0),   -- Flask of the Titans
(332, 3, 13511, 1, 0, 30, 13, 50,  64, 0),   -- Flask of Distilled Wisdom
(333, 3, 13512, 1, 0, 30, 13, 50,  64, 0),   -- Flask of Supreme Power
(334, 3, 22851, 1, 0, 30, 13, 65,  74, 0),   -- Flask of Fortification
(335, 3, 22853, 1, 0, 30, 13, 65,  74, 0),   -- Flask of Mighty Restoration
(336, 3, 22854, 1, 0, 30, 13, 65,  74, 0),   -- Flask of Relentless Assault
(337, 3, 22861, 1, 0, 30, 13, 65,  74, 0),   -- Flask of Blinding Light
(338, 3, 22866, 1, 0, 30, 13, 65,  74, 0),   -- Flask of Pure Death
(339, 3, 46376, 1, 0, 30, 13, 75, 255, 0),   -- Flask of the Frost Wyrm
(340, 3, 46377, 1, 0, 30, 13, 75, 255, 0),   -- Flask of Endless Rage
(341, 3, 46378, 1, 0, 30, 13, 75, 255, 0),   -- Flask of Pure Mojo
(342, 3, 46379, 1, 0, 30, 13, 75, 255, 0),   -- Flask of Stoneblood
-- Services
(401, 4, 0, 1, 4, 20,  1, 1, 255, 0),        -- One more contract reroll today
(402, 4, 0, 1, 3, 15,  2, 1, 255, 0),        -- Replace an abandoned work order now
(403, 4, 0, 1, 1, 50,  4, 1, 255, 0),        -- Reroll recruit candidates
(404, 4, 0, 1, 2, 60,  8, 1, 255, 0);        -- Reroll the mission board
