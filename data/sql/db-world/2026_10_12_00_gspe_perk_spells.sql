-- mod-guild-single-player-expansion (acore_world): server-side perk spells.
-- These spells exist only on the server; the client add-on asks the server to use them.
-- Ids 80000011-80000013 and gameobject 80000020 were previously owned by mod-guild-levels.

DELETE FROM `spell_script_names` WHERE `spell_id` IN (80000012, 80000013);
INSERT INTO `spell_script_names` (`spell_id`, `ScriptName`) VALUES
(80000012, 'spell_gspe_mobile_banking');

-- 80000011 Mount Up: +10% mounted speed (SPELL_AURA_MOD_INCREASE_MOUNTED_SPEED).
--   AttributesEx3 0x00100000 (death persistent) so the aura survives dying.
-- 80000012 Mobile Banking: script effect, handled by spell_gspe_mobile_banking.
-- 80000014 The Quick and the Dead: +50% run speed while a ghost (SPELL_AURA_MOD_INCREASE_SPEED).
--   Attributes 0x00800000 (castable while dead), AttributesEx2 0x00000001 (allow dead target).
-- 80000013 (Mass Resurrection) is retired.
DELETE FROM `spell_dbc` WHERE `Id` IN (80000011, 80000012, 80000013, 80000014);
INSERT INTO `spell_dbc` (
	`Id`, `Attributes`, `AttributesEx2`, `AttributesEx3`, `Targets`, `CastingTimeIndex`, `ProcChance`,
	`RangeIndex`, `EquippedItemClass`, `Effect_1`, `EffectBasePoints_1`, `ImplicitTargetA_1`,
	`EffectAura_1`, `Name_Lang_enUS`, `Description_Lang_enUS`, `AuraDescription_Lang_enUS`,
	`EffectBonusMultiplier_1`, `EffectBonusMultiplier_2`, `EffectBonusMultiplier_3`
) VALUES
(80000011, 0x00000000, 0x00000000, 0x00100000, 0, 1, 101, 1, -1, 6, 9, 1, 32, 'Mount Up',
 'Guild perk: increases mounted movement speed by 10%.', 'Mounted movement speed increased by 10%.', 1, 1, 1),
(80000012, 0x00000000, 0x00000000, 0x00000000, 0, 1, 101, 1, -1, 77, 0, 1, 0, 'Mobile Banking',
 'Summons a temporary guild bank for your guild.', '', 1, 1, 1),
(80000014, 0x00800000, 0x00000001, 0x00000000, 0, 1, 101, 1, -1, 6, 49, 1, 31, 'The Quick and the Dead',
 'Guild perk: increases movement speed while dead by 50%.', 'Movement speed increased by 50%.', 1, 1, 1);

DELETE FROM `gameobject_template` WHERE `entry` = 80000020;
INSERT INTO `gameobject_template` (
	`entry`, `type`, `displayId`, `name`, `IconName`, `castBarCaption`, `unk1`, `size`,
	`Data0`, `Data1`, `Data2`, `Data3`, `Data4`, `Data5`, `Data6`, `Data7`, `Data8`,
	`Data9`, `Data10`, `Data11`, `Data12`, `Data13`, `Data14`, `Data15`, `Data16`,
	`Data17`, `Data18`, `Data19`, `Data20`, `Data21`, `Data22`, `Data23`, `AIName`,
	`ScriptName`, `VerifiedBuild`
) VALUES
(80000020, 34, 333, 'Guild Mobile Banker', '', '', '', 1,
0, 0, 0, 0, 0, 0, -1, 0, 0,
0, 0, 0, 0, 0, 0, 0, 0,
0, 0, 0, 0, 0, 0, 0, '',
'', 0);
