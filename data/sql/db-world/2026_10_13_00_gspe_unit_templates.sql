-- mod-guild-single-player-expansion (acore_world): unit templates and names.
--
-- kind:      0 = hero (race + class), 1 = specialist
-- races:     comma-separated ChrRaces ids the unit can be (1 Human, 2 Orc, 3 Dwarf, 4 Night Elf,
--            5 Undead, 6 Tauren, 7 Gnome, 8 Troll, 9 Goblin, 10 Blood Elf, 11 Draenei)
-- class:     ChrClasses id for heroes, 0 for specialists
-- role:      0 tank, 1 healer, 2 damage
-- abilities: comma-separated ability ids a unit of this template can roll; each counters the
--            threat with the same id (1 Beast Lore, 2 Purify, 3 Banish, 4 Ward, 5 Vigilance,
--            6 Sabotage, 7 Shield Wall, 8 Area Attack, 9 Interrupt, 10 Healing)
-- traits:    comma-separated trait ids it can roll; empty = any
-- icon:      Interface\Icons texture name shown in the add-on

DROP TABLE IF EXISTS `mod_gspe_unit_template`;
CREATE TABLE `mod_gspe_unit_template` (
  `id` SMALLINT UNSIGNED NOT NULL,
  `kind` TINYINT UNSIGNED NOT NULL,
  `name` VARCHAR(48) NOT NULL,
  `races` VARCHAR(64) NOT NULL,
  `class` TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `role` TINYINT UNSIGNED NOT NULL,
  `abilities` VARCHAR(64) NOT NULL,
  `traits` VARCHAR(64) NOT NULL DEFAULT '',
  `icon` VARCHAR(64) NOT NULL,
  `weight` SMALLINT UNSIGNED NOT NULL DEFAULT 10,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
COMMENT='mod-guild-single-player-expansion: unit templates';

INSERT INTO `mod_gspe_unit_template` (`id`, `kind`, `name`, `races`, `class`, `role`, `abilities`, `traits`, `icon`, `weight`) VALUES
(1,  0, 'Warrior',                '1,2,3,4,5,6,7,8,11',    1,  0, '7,5,9',    '', 'Ability_Warrior_DefensiveStance', 10),
(2,  0, 'Paladin',                '1,3,10,11',             2,  0, '2,7,3,10', '', 'Spell_Holy_HolyBolt',             10),
(3,  0, 'Hunter',                 '2,3,4,6,8,10,11',       3,  2, '1,5',      '', 'INV_Weapon_Bow_07',               10),
(4,  0, 'Rogue',                  '1,2,3,4,5,7,8,10',      4,  2, '6,9,5',    '', 'Ability_Stealth',                 10),
(5,  0, 'Priest',                 '1,3,4,5,8,10,11',       5,  1, '10,2',     '', 'Spell_Holy_PowerWordShield',      10),
(6,  0, 'Death Knight',           '1,2,3,4,5,6,7,8,10,11', 6,  0, '7,8,9',    '', 'Spell_Deathknight_ClassIcon',     10),
(7,  0, 'Shaman',                 '2,6,8,11',              7,  1, '10,4,2,9', '', 'Spell_Nature_BloodLust',          10),
(8,  0, 'Mage',                   '1,5,7,8,10,11',         8,  2, '4,8',      '', 'INV_Staff_13',                    10),
(9,  0, 'Warlock',                '1,2,5,7,10',            9,  2, '3,8',      '', 'Spell_Shadow_DeathCoil',          10),
(10, 0, 'Druid',                  '4,6',                   11, 1, '10,1',     '', 'Spell_Nature_HealingTouch',       10),
(11, 1, 'Gnomish Engineer',       '7',                     0,  2, '6,8',      '', 'Trade_Engineering',               6),
(12, 1, 'Goblin Sapper',          '9',                     0,  2, '6,8',      '', 'INV_Misc_Bomb_05',                6),
(13, 1, 'Kodo Rider',             '6',                     0,  0, '7,5',      '', 'Ability_Mount_Kodo_03',           6),
(14, 1, 'Dwarven Rifleman',       '3',                     0,  2, '9,5',      '', 'INV_Weapon_Rifle_01',             6),
(15, 1, 'Night Elf Sentinel',     '4',                     0,  2, '1,5',      '', 'Ability_Mount_WhiteTiger',        6),
(16, 1, 'Forsaken Apothecary',    '5',                     0,  1, '10,2',     '', 'INV_Potion_51',                   6),
(17, 1, 'Draenei Vindicator',     '11',                    0,  0, '7,2,3',    '', 'Spell_Holy_AvengersShield',       6),
(18, 1, 'Blood Elf Spellbreaker', '10',                    0,  2, '9,4,3',    '', 'Spell_Arcane_Blast',              6),
(19, 1, 'Troll Witch Doctor',     '8',                     0,  1, '10,2,4',   '', 'INV_Misc_Head_Troll_01',          6),
(20, 1, 'Orcish Wolf Rider',      '2',                     0,  2, '1,8',      '', 'Ability_Mount_BlackDireWolf',     6);

-- gender: 0 male, 1 female
DROP TABLE IF EXISTS `mod_gspe_unit_name`;
CREATE TABLE `mod_gspe_unit_name` (
  `race` TINYINT UNSIGNED NOT NULL,
  `gender` TINYINT UNSIGNED NOT NULL,
  `name` VARCHAR(48) NOT NULL,
  PRIMARY KEY (`race`, `gender`, `name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
COMMENT='mod-guild-single-player-expansion: unit names by race and gender';

INSERT INTO `mod_gspe_unit_name` (`race`, `gender`, `name`) VALUES
(1, 0, 'Aldric Vane'), (1, 0, 'Gareth Holloway'), (1, 0, 'Marcus Brightwater'), (1, 0, 'Roland Ashford'),
(1, 0, 'Tobias Kent'), (1, 0, 'Cedric Stormwell'), (1, 0, 'Halden Moss'), (1, 0, 'Edwin Calloway'),
(1, 1, 'Elena Marsh'), (1, 1, 'Lysa Thorne'), (1, 1, 'Mira Coldbrook'), (1, 1, 'Adeline Rook'),
(1, 1, 'Tessa Ward'), (1, 1, 'Catrin Hale'), (1, 1, 'Isolde Grey'), (1, 1, 'Wren Fairfield'),
(2, 0, 'Durgash Ironhide'), (2, 0, 'Mokra Skullsplitter'), (2, 0, 'Gorrok Stonefang'), (2, 0, 'Rakgar Ashmaw'),
(2, 0, 'Zugrash Redtusk'), (2, 0, 'Kargul Bonecrusher'), (2, 0, 'Throm Ragefang'), (2, 0, 'Nazgar Wolfcaller'),
(2, 1, 'Grisha Frostjaw'), (2, 1, 'Mogra Ironjaw'), (2, 1, 'Shazra Bladeheart'), (2, 1, 'Zurka Embermaw'),
(2, 1, 'Ragga Stormhowl'), (2, 1, 'Kerra Skullcleave'), (2, 1, 'Durka Bloodmane'), (2, 1, 'Ozra Thornhide'),
(3, 0, 'Thorgrim Ironhand'), (3, 0, 'Bromli Stonebeard'), (3, 0, 'Durgan Coppervein'), (3, 0, 'Hagrim Flintforge'),
(3, 0, 'Korvin Deepdelver'), (3, 0, 'Murgin Anvilbrow'), (3, 0, 'Thane Hammerfall'), (3, 0, 'Rurik Stoutale'),
(3, 1, 'Brenna Ironhearth'), (3, 1, 'Dagna Stonebrow'), (3, 1, 'Helga Deepforge'), (3, 1, 'Kara Goldbraid'),
(3, 1, 'Moirna Flintstrike'), (3, 1, 'Sigrun Coalbeard'), (3, 1, 'Tova Hammerstone'), (3, 1, 'Yrsa Frostbeard'),
(4, 0, 'Aerendil Moonshadow'), (4, 0, 'Faelan Starbreeze'), (4, 0, 'Ilthan Nightwhisper'), (4, 0, 'Kaldreth Silverleaf'),
(4, 0, 'Thalion Duskwind'), (4, 0, 'Varaen Shadowbough'), (4, 0, 'Elarian Mistwalker'), (4, 0, 'Saelorn Leafsong'),
(4, 1, 'Shaenara Moonglade'), (4, 1, 'Elyssia Starfall'), (4, 1, 'Ilyana Nightbloom'), (4, 1, 'Lirael Silvermist'),
(4, 1, 'Nyssa Dawnthorn'), (4, 1, 'Aeryn Shadowleaf'), (4, 1, 'Selwyn Moonfeather'), (4, 1, 'Kaelys Thistlewind'),
(5, 0, 'Mordred Grimm'), (5, 0, 'Silas Coldgrave'), (5, 0, 'Edric Hollowmere'), (5, 0, 'Victor Ashgrave'),
(5, 0, 'Lucan Rotwood'), (5, 0, 'Gideon Blackmarsh'), (5, 0, 'Ambrose Duskvale'), (5, 0, 'Corwin Bleakwater'),
(5, 1, 'Morgana Vex'), (5, 1, 'Lenora Graves'), (5, 1, 'Seraphine Crowe'), (5, 1, 'Ophelia Thorn'),
(5, 1, 'Agatha Dread'), (5, 1, 'Evelyn Shade'), (5, 1, 'Mirela Bonechill'), (5, 1, 'Rowena Mourne'),
(6, 0, 'Hakan Thunderhoof'), (6, 0, 'Oro Skyhorn'), (6, 0, 'Tahomi Earthstrider'), (6, 0, 'Kodar Mistrunner'),
(6, 0, 'Bakar Stonehorn'), (6, 0, 'Tarvo Plainswalker'), (6, 0, 'Mahka Windtotem'), (6, 0, 'Garo Swiftmane'),
(6, 1, 'Ahiga Morningbreeze'), (6, 1, 'Nayeli Cloudsong'), (6, 1, 'Kaya Rivermane'), (6, 1, 'Tala Dawnhoof'),
(6, 1, 'Sakari Earthsong'), (6, 1, 'Winona Grasswalker'), (6, 1, 'Alowa Skydancer'), (6, 1, 'Hesa Stormhorn'),
(7, 0, 'Fizzwick Gearlock'), (7, 0, 'Tinkerton Sprocketspark'), (7, 0, 'Nimble Cogsworth'), (7, 0, 'Bixby Fusebolt'),
(7, 0, 'Gizzle Wrenchwhistle'), (7, 0, 'Pip Copperspring'), (7, 0, 'Dabble Boltbuckle'), (7, 0, 'Wizzle Steamtwist'),
(7, 1, 'Tilly Sparkgear'), (7, 1, 'Nessa Cogwhistle'), (7, 1, 'Fizzy Brassbolt'), (7, 1, 'Lilli Gizmotink'),
(7, 1, 'Pippa Wobblesprocket'), (7, 1, 'Minna Fuseflicker'), (7, 1, 'Dottie Gearspinner'), (7, 1, 'Kipsy Coilfizz'),
(8, 0, 'Zun''kal Bloodtusk'), (8, 0, 'Jin''zo Shadowmane'), (8, 0, 'Raz''gul Hexfang'), (8, 0, 'Zalakko'),
(8, 0, 'Ka''lur Spiritbinder'), (8, 0, 'Jakor Bonepicker'), (8, 0, 'Sen''thak Rivertusk'), (8, 0, 'Gaz''rik Mojomaster'),
(8, 1, 'Zanji Moonfang'), (8, 1, 'Shaza Hexweaver'), (8, 1, 'Ra''ja Bonecharm'), (8, 1, 'Kaz''zi Serpentsong'),
(8, 1, 'Yaz''ra Nightstalker'), (8, 1, 'Lin''zi Bloodvine'), (8, 1, 'Tazzi Mojoweaver'), (8, 1, 'Vashi Spiritcall'),
(9, 0, 'Krazzle Fizzbang'), (9, 0, 'Noggle Profitbolt'), (9, 0, 'Zix Coinsnatch'), (9, 0, 'Grizzik Quickfuse'),
(9, 0, 'Sprokk Gearsnap'), (9, 0, 'Rizzle Cashwrench'), (9, 0, 'Boomgut Sparkspanner'), (9, 0, 'Jinx Moneyglint'),
(9, 1, 'Zippa Sparkcoin'), (9, 1, 'Glitzy Boltgrin'), (9, 1, 'Trixie Fusebottom'), (9, 1, 'Nixie Gadgetgrab'),
(9, 1, 'Penny Quickprofit'), (9, 1, 'Sizzla Copperlode'), (9, 1, 'Bixxie Blastwhistle'), (9, 1, 'Kix Moneyspark'),
(10, 0, 'Aelthir Dawnblade'), (10, 0, 'Caelen Brightspire'), (10, 0, 'Lorthan Embersong'), (10, 0, 'Velarion Goldleaf'),
(10, 0, 'Taeral Flamecrest'), (10, 0, 'Ithrian Sunweaver'), (10, 0, 'Kaelith Ashveil'), (10, 0, 'Rhoren Dawnstrike'),
(10, 1, 'Aeriel Sunhallow'), (10, 1, 'Lyandra Brightsong'), (10, 1, 'Sylvara Dawnstar'), (10, 1, 'Vaeliss Emberleaf'),
(10, 1, 'Thaelia Goldvein'), (10, 1, 'Elissia Flamesong'), (10, 1, 'Naelis Sunveil'), (10, 1, 'Rhiannel Ashglow'),
(11, 0, 'Karadon'), (11, 0, 'Velaar'), (11, 0, 'Taroon'), (11, 0, 'Mehlaan'),
(11, 0, 'Ozuun'), (11, 0, 'Kehmaar'), (11, 0, 'Rhoonaal'), (11, 0, 'Nobuur'),
(11, 1, 'Ylari'), (11, 1, 'Saari'), (11, 1, 'Mareeka'), (11, 1, 'Nalaani'),
(11, 1, 'Ishaara'), (11, 1, 'Teelu'), (11, 1, 'Kaalia'), (11, 1, 'Voshana');
