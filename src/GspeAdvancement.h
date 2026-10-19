/*
 * mod-guild-expansion: guild advancement after level 25.
 *
 * Every guild level after 25 gives a Guild Point (the points come from the level, only
 * where they are spent is stored). Points go into tracks with small guild-wide bonuses,
 * up to 25 points each. Guild masters and officers spend them; a reset refunds them all
 * for a supplies fee.
 */

#ifndef MOD_GSPE_ADVANCEMENT_H_
#define MOD_GSPE_ADVANCEMENT_H_

#include "Define.h"

#include <array>
#include <unordered_map>

class Player;

// Keep in sync with client_addon/GuildExpansion/Advancement.lua.
enum AdvancementTrack : uint8
{
    TRACK_SUPPLY_LINES       = 1,   // +1% guild supplies earned
    TRACK_FIELD_COMMAND      = 2,   // +1 mission success chance
    TRACK_SWIFT_COURIERS     = 3,   // -1% mission duration
    TRACK_TRADE_AGREEMENTS   = 4,   // +2% gold from work orders, contracts and missions
    TRACK_DRILL_SERGEANT     = 5,   // +2% unit XP
    TRACK_QUARTERMASTER      = 6,   // -1% quartermaster prices
    TRACK_SEASONED_TRAVELERS = 7,   // +0.4% character XP from kills and quests
    TRACK_GOOD_STANDING      = 8,   // +0.4% reputation
    TRACK_STEADY_HANDS       = 9,   // +0.4% chance of an extra profession skill-up
    TRACK_COUNT              = 9,
};

constexpr uint32 TRACK_MAX_POINTS = 25;

class AdvancementMgr
{
public:
    static AdvancementMgr* instance();

    void OnGuildDisband(uint32 guildId);

    [[nodiscard]] uint32 Points(uint32 guildId, uint8 track);
    [[nodiscard]] uint32 Earned(uint32 guildId);
    [[nodiscard]] uint32 Spent(uint32 guildId);

    // Bonuses from the tracks.
    [[nodiscard]] float SuppliesMultiplier(uint32 guildId);
    [[nodiscard]] uint32 MissionSuccessBonus(uint32 guildId);
    [[nodiscard]] float MissionDurationMultiplier(uint32 guildId);
    [[nodiscard]] float GoldMultiplier(uint32 guildId);
    [[nodiscard]] float UnitXpMultiplier(uint32 guildId);
    [[nodiscard]] float QuartermasterPriceMultiplier(uint32 guildId);
    [[nodiscard]] float CharacterXpMultiplier(uint32 guildId);
    [[nodiscard]] float ReputationMultiplier(uint32 guildId);
    [[nodiscard]] float ExtraSkillUpChance(uint32 guildId);   // percent

    // Client requests.
    void SendAdvancement(Player* player);
    void HandleSpend(Player* player, uint8 track, uint32 count);
    void HandleReset(Player* player);

    // GM: refund all points without the fee.
    void ResetPoints(uint32 guildId);

private:
    AdvancementMgr() = default;

    using Tracks = std::array<uint32, TRACK_COUNT + 1>;   // index = track, 0 unused

    Tracks& GetTracks(uint32 guildId);
    [[nodiscard]] bool CheckRequest(Player* player);
    [[nodiscard]] static bool CanEdit(Player* player);
    [[nodiscard]] uint32 ResetCost(uint32 guildId);

    std::unordered_map<uint32, Tracks> _guilds;
};

#define sAdvancementMgr AdvancementMgr::instance()

#endif
