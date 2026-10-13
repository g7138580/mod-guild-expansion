-- mod-guild-single-player-expansion (acore_world): mission templates.
--
-- type:         0 patrol/escort, 1 gathering, 2 supply run, 3 bounty/hunt, 4 dungeon delve,
--               5 training, 7 raid (rewards follow the type)
-- slots:        units the mission takes (1-3)
-- min/max_minutes: duration range
-- threats:      comma-separated pool of threat ids (1 Wild Beasts, 2 Unholy Curse, 3 Fel Corruption,
--               4 Elemental Fury, 5 Ambush, 6 Siege Engines, 7 Massive Strike, 8 Minion Swarm,
--               9 Powerful Caster, 10 Grievous Wounds); threat_count of them are picked per offer
-- roles:        comma-separated roles the mission needs (0 tank, 1 healer, 2 damage); each
--               missing role lowers the success chance
-- min_level:    lowest mission level this template appears at

DROP TABLE IF EXISTS `mod_gspe_mission_template`;
CREATE TABLE `mod_gspe_mission_template` (
  `id` SMALLINT UNSIGNED NOT NULL,
  `type` TINYINT UNSIGNED NOT NULL,
  `name` VARCHAR(64) NOT NULL,
  `description` VARCHAR(200) NOT NULL,
  `slots` TINYINT UNSIGNED NOT NULL,
  `min_minutes` SMALLINT UNSIGNED NOT NULL,
  `max_minutes` SMALLINT UNSIGNED NOT NULL,
  `threats` VARCHAR(32) NOT NULL,
  `threat_count` TINYINT UNSIGNED NOT NULL,
  `roles` VARCHAR(16) NOT NULL DEFAULT '',
  `min_level` TINYINT UNSIGNED NOT NULL DEFAULT 1,
  `weight` SMALLINT UNSIGNED NOT NULL DEFAULT 10,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
COMMENT='mod-guild-single-player-expansion: mission templates';

INSERT INTO `mod_gspe_mission_template`
(`id`, `type`, `name`, `description`, `slots`, `min_minutes`, `max_minutes`, `threats`, `threat_count`, `roles`, `min_level`, `weight`) VALUES
-- Patrol / escort
(1,  0, 'Caravan Escort',        'A merchant caravan needs protection on the long road between the trade towns. Bandits have been sighted along the route.', 2, 30, 90, '5,1,8', 2, '', 1, 10),
(2,  0, 'Road Patrol',           'Keep the roads safe for travelers. Report anything unusual, and deal with anything dangerous.', 1, 30, 60, '5,1', 1, '', 1, 10),
(3,  0, 'Border Watch',          'Scouts report movement along the border. Hold the watchtower until relief arrives.', 2, 60, 120, '5,8,9', 2, '', 1, 10),
(4,  0, 'Refugee Escort',        'Families fleeing the Scourge need safe passage to the nearest town. Keep them alive.', 2, 60, 120, '2,8,5', 2, '', 1, 10),
(5,  0, 'Night Watch',           'Something has been stalking the outlying farms after dark. Stand guard until dawn.', 1, 60, 120, '1,2,5', 1, '', 1, 10),
(6,  0, 'Scout the Outpost',     'An enemy outpost has gone quiet. Find out why, and come back alive with what you learn.', 2, 45, 90, '5,9,6', 2, '', 1, 10),
(40, 0, 'Escort the Ambassador', 'An ambassador must reach the capital for peace talks. Not everyone wants her to arrive.', 3, 90, 180, '5,9,8', 2, '', 1, 8),
-- Gathering
(7,  1, 'Herb Expedition',       'The guild''s alchemists are running low. Gather herbs from the wilds, and mind the local wildlife.', 1, 60, 180, '1,4', 1, '', 1, 8),
(8,  1, 'Mining Expedition',     'A promising vein has been found in a kobold-infested mine. Bring back what ore you can carry.', 2, 60, 180, '8,7', 1, '', 1, 8),
(9,  1, 'Hunting Party',         'Track and skin the great beasts of the plains. Their hides fetch a fine price.', 2, 60, 180, '1,7', 1, '', 1, 8),
(10, 1, 'Salvage the Wreck',     'A cargo ship ran aground on the coast. Recover its goods before the murlocs do.', 2, 60, 120, '8,4', 1, '', 1, 8),
(11, 1, 'Cloth Requisition',     'The guild tailors need cloth, and the bandit camps are full of it. Go and get it.', 1, 60, 120, '5,8', 1, '', 1, 8),
(12, 1, 'Elemental Harvest',     'Raw elemental energy has pooled near an unstable rift. Gather it before it fades.', 2, 90, 180, '4,9', 2, '', 20, 8),
-- Supply runs
(13, 2, 'Supply Run',            'Pick up the guild''s supply order from the quartermaster in the next town and bring it home.', 1, 30, 90, '5', 1, '', 1, 8),
(14, 2, 'Requisition Lumber',    'The guild needs timber for repairs. Cut it, haul it, and keep the wolves away.', 2, 60, 120, '1,5', 1, '', 1, 8),
(15, 2, 'Smuggler''s Cache',     'A captured smuggler has given up the location of a hidden cache. Claim it for the guild.', 2, 60, 120, '5,6', 2, '', 1, 8),
(16, 2, 'Trade Negotiations',    'Represent the guild at a goblin trading post. Haggle hard, and watch your purse.', 1, 60, 180, '9,5', 1, '', 1, 8),
(17, 2, 'Recover Stolen Goods',  'Thieves made off with a shipment of guild supplies. Track them down and bring it all back.', 2, 60, 120, '5,8', 2, '', 1, 8),
-- Bounties and hunts
(18, 3, 'Hunt a Rare Beast',     'A legendary beast has been terrorizing hunters in the wilds. Bring back its head.', 2, 120, 240, '1,7', 2, '', 1, 8),
(19, 3, 'Raid a Smugglers'' Cove', 'Smugglers are using a hidden cove to move stolen weapons. Shut it down.', 2, 120, 240, '5,6,8', 2, '', 1, 8),
(20, 3, 'Bandit Bounty',         'The local magistrate has put a price on the head of a notorious bandit lord.', 2, 90, 180, '5,9', 2, '', 1, 8),
(21, 3, 'Cult Hideout',          'Cultists of the Damned are gathering in an abandoned crypt. Scatter them before the ritual is complete.', 2, 120, 240, '2,9,8', 2, '', 10, 8),
(22, 3, 'Demon Hunter',          'A warlock coven has summoned something it can''t control. Banish it back to the Nether.', 2, 120, 240, '3,9', 2, '', 10, 8),
(23, 3, 'Ogre Warlord',          'An ogre warlord has united the hill clans and is raiding the farmlands. End his reign.', 2, 120, 240, '7,8', 2, '', 15, 8),
(24, 3, 'Naga Incursion',        'Naga are coming ashore to raid the fishing villages. Drive them back into the sea.', 2, 120, 180, '4,9,8', 2, '', 20, 8),
(25, 3, 'Dragonkin Lair',        'A young dragon has made its lair in the mountains above town. The town wants it gone.', 3, 180, 300, '7,4,10', 2, '', 30, 6),
-- Dungeon delves (need a tank and a healer)
(26, 4, 'Delve: Ancient Barrow', 'An ancient barrow has been breached and its dead are walking. Clear it and claim what the dead no longer need.', 3, 240, 480, '2,8,7,10', 3, '0,1', 10, 5),
(27, 4, 'Delve: Kobold Warrens', 'The kobold warrens run deep, and the candles never stop. Push through to the chieftain.', 3, 240, 480, '8,6,5', 2, '0,1', 10, 5),
(28, 4, 'Delve: Sunken Temple',  'A drowned temple has risen with the tide, and something old stirs within.', 3, 240, 480, '4,9,10,7', 3, '0,1', 15, 5),
(29, 4, 'Delve: Defias Hideout', 'The Brotherhood is rebuilding in an old mine. Strike before they can arm themselves.', 3, 240, 480, '5,6,8', 3, '0,1', 10, 5),
(30, 4, 'Delve: Scourge Necropolis', 'A fallen necropolis lies half-buried in the snow. The Scourge still guard its vaults.', 3, 240, 480, '2,8,9,10', 3, '0,1', 55, 5),
(31, 4, 'Delve: Burning Crypt',  'Fel energy pours from a crypt beneath the old cathedral. Seal it from the inside.', 3, 240, 480, '3,9,10', 3, '0,1', 30, 5),
(32, 4, 'Delve: Troll Ruins',    'The jungle trolls'' old temple holds both treasure and their angry priests.', 3, 240, 480, '9,1,10', 3, '0,1', 15, 5),
-- Training (mostly unit experience)
(33, 5, 'Sparring Practice',     'A few hours in the practice yard with the guild''s veterans. Bruised pride, sharper skills.', 1, 60, 120, '7', 1, '', 1, 5),
(34, 5, 'Tactics Drill',         'Run drills with the guild''s officers until every maneuver is second nature.', 2, 120, 240, '5,8', 1, '', 1, 5),
(35, 5, 'Survival Training',     'Spend a few days alone in the wilderness. Come back tougher, or don''t come back hungry.', 1, 120, 240, '1,4', 1, '', 1, 5),
(36, 5, 'Arcane Study',          'Study the guild''s collection of tomes under a visiting magister.', 1, 120, 240, '9', 1, '', 1, 5),
-- Raids (level 80, need a tank and a healer)
(37, 7, 'Assault the Frozen Halls', 'Join the vanguard pushing into the frozen halls of the enemy citadel. The rewards are great; so are the dangers.', 3, 480, 720, '2,7,8,10', 3, '0,1', 80, 4),
(38, 7, 'Titan Vaults',          'Explore the deep vaults beneath the titan city, where the watchers still stand guard.', 3, 480, 720, '4,7,6,10', 3, '0,1', 80, 4),
(39, 7, 'Dragon''s Roost',       'A brood of dragons has taken a high roost in the north. Break them before they swarm.', 3, 480, 720, '7,4,8,10', 3, '0,1', 80, 4);
