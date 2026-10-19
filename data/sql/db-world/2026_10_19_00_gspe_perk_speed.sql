-- mod-guild-expansion (acore_world): make the speed perks stack with other speed effects.
--
-- Only the strongest effect of a speed aura type counts. The ghost form already gives +50%
-- run speed and every mount its own mounted speed, both with the same aura types the perks
-- used, so the perks added nothing. The "always" aura types multiply with them instead.
--
-- 80000014 The Quick and the Dead: SPELL_AURA_MOD_SPEED_ALWAYS (129), +50% on top of the ghost's speed.
-- 80000011 Mount Up: SPELL_AURA_MOD_MOUNTED_SPEED_ALWAYS (130) for ground mounts and
--          SPELL_AURA_MOD_MOUNTED_FLIGHT_SPEED_ALWAYS (209) for flying mounts, +10% each.

UPDATE `spell_dbc` SET `EffectAura_1` = 129 WHERE `Id` = 80000014;

UPDATE `spell_dbc` SET
  `EffectAura_1` = 130,
  `Effect_2` = 6, `EffectBasePoints_2` = 9, `ImplicitTargetA_2` = 1, `EffectAura_2` = 209
WHERE `Id` = 80000011;
