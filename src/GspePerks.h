/*
 * mod-guild-expansion: perks, keyed by the guild level that unlocks them.
 * Keep in sync with client_addon/GuildExpansion/Perks.lua.
 */

#ifndef MOD_GSPE_PERKS_H_
#define MOD_GSPE_PERKS_H_

#include "Define.h"

namespace GspePerks
{
// The last level with perks and slot unlocks; levels after it give Guild Points.
constexpr uint8 MAX_GUILD_LEVEL = 25;

enum Perk : uint8
{
    FAST_TRACK_1      = 2,
    HASTY_HEARTH      = 3,
    MR_POPULARITY_1   = 6,
    QUICK_AND_DEAD    = 7,
    CASH_FLOW_1       = 8,
    MOUNT_UP          = 9,
    REPAIR_DISCOUNT_1 = 11,
    FAST_TRACK_2      = 12,
    CHUG_A_LUG_1      = 13,
    CASH_FLOW_2       = 14,
    REINFORCE         = 16,
    MR_POPULARITY_2   = 17,
    HONORABLE_MENTION = 18,
    WORKING_OVERTIME  = 19,
    MOBILE_BANKING    = 20,
    REPAIR_DISCOUNT_2 = 21,
    CHUG_A_LUG_2      = 24,
};

inline bool Has(uint8 guildLevel, Perk perk)
{
    return guildLevel >= perk;
}

inline float XpMultiplier(uint8 guildLevel)
{
    if (Has(guildLevel, FAST_TRACK_2))
        return 1.10f;
    if (Has(guildLevel, FAST_TRACK_1))
        return 1.05f;
    return 1.0f;
}

inline float ReputationMultiplier(uint8 guildLevel)
{
    if (Has(guildLevel, MR_POPULARITY_2))
        return 1.10f;
    if (Has(guildLevel, MR_POPULARITY_1))
        return 1.05f;
    return 1.0f;
}

inline float HonorMultiplier(uint8 guildLevel)
{
    return Has(guildLevel, HONORABLE_MENTION) ? 1.10f : 1.0f;
}

// Units the guild can have: 3, plus one more at guild levels 9, 13 and 18.
inline uint32 UnitSlots(uint8 guildLevel)
{
    return 3 + (guildLevel >= 9 ? 1 : 0) + (guildLevel >= 13 ? 1 : 0) + (guildLevel >= 18 ? 1 : 0);
}

// Troops the guild can have: 2, plus one more at guild levels 7, 12, 17 and 22.
inline uint32 TroopSlots(uint8 guildLevel)
{
    return 2 + (guildLevel >= 7 ? 1 : 0) + (guildLevel >= 12 ? 1 : 0) + (guildLevel >= 17 ? 1 : 0)
             + (guildLevel >= 22 ? 1 : 0);
}

// Missions the guild can run at once: 1, plus one more at guild levels 5, 12, 17 and 22.
inline uint32 MissionSlots(uint8 guildLevel)
{
    return 1 + (guildLevel >= 5 ? 1 : 0) + (guildLevel >= 12 ? 1 : 0) + (guildLevel >= 17 ? 1 : 0)
             + (guildLevel >= 22 ? 1 : 0);
}

// Reinforce restores 20% of the durability lost on death.
inline uint32 ReinforceRestorePoints(uint8 guildLevel, uint32 lostPoints)
{
    return Has(guildLevel, REINFORCE) ? lostPoints / 5 : 0;
}
} // namespace GspePerks

#endif
