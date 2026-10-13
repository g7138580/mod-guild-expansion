-- mod-guild-expansion (acore_world): troop templates (kind 2).
-- Troops are trained with Guild Supplies, fill a mission slot, count for their role and
-- counter one threat. They wear out after a few missions and die on lethal missions.

DELETE FROM `mod_gspe_unit_template` WHERE `id` IN (101, 102, 103);
INSERT INTO `mod_gspe_unit_template` (`id`, `kind`, `name`, `races`, `class`, `role`, `abilities`, `traits`, `icon`, `weight`) VALUES
(101, 2, 'Shieldbearers', '1', 0, 0, '7',  '', 'INV_Shield_05',   1),
(102, 2, 'Field Medics',  '1', 0, 1, '10', '', 'Spell_Holy_Heal02', 1),
(103, 2, 'Archers',       '1', 0, 2, '8',  '', 'INV_Weapon_Bow_02', 1);
