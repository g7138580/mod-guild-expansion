/*
 * mod-guild-expansion: guild advancement after level 25.
 *
 * Every guild level after 25 gives a Guild Point (the points come from the level, only
 * where they are spent is stored). Points go into tracks with small guild-wide bonuses,
 * up to 25 points each. Every 25 levels (50 to 225) is a milestone with a choice of two
 * lasting bonuses; level 250 is the capstone. Guild masters and officers spend points and
 * make the choices; a reset refunds every point and a changed choice costs supplies.
 */

#ifndef MOD_GSPE_ADVANCEMENT_H_
#define MOD_GSPE_ADVANCEMENT_H_

#include "Define.h"

#include <array>
#include <map>
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

// Milestones every 25 levels; choice 1 or 2. Keep in sync with Advancement.lua.
constexpr uint32 MILESTONE_FIRST = 50;
constexpr uint32 MILESTONE_LAST_CHOICE = 225;
constexpr uint32 MILESTONE_STEP = 25;

enum MilestoneChoice : uint8
{
    MILESTONE_NONE = 0,
    MILESTONE_A    = 1,
    MILESTONE_B    = 2,
};

class AdvancementMgr
{
public:
    static AdvancementMgr* instance();

    void OnGuildDisband(uint32 guildId);

    [[nodiscard]] uint32 Points(uint32 guildId, uint8 track);
    [[nodiscard]] uint32 Earned(uint32 guildId);
    [[nodiscard]] uint32 Spent(uint32 guildId);
    // The choice made at a milestone, MILESTONE_NONE if none or the guild is below it.
    [[nodiscard]] uint8 Milestone(uint32 guildId, uint32 level);
    [[nodiscard]] bool Has(uint32 guildId, uint32 level, uint8 choice) { return Milestone(guildId, level) == choice; }

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

    // Limits and chances with the milestone choices applied.
    [[nodiscard]] uint32 MissionSlots(uint32 guildId);          // 50 A
    [[nodiscard]] uint32 UnitSlots(uint32 guildId);             // 50 B
    [[nodiscard]] uint32 TroopSlots(uint32 guildId);            // 75 A
    [[nodiscard]] uint8 TroopVitality(uint32 guildId);          // 75 B
    [[nodiscard]] uint32 RecruitCandidates(uint32 guildId);     // 100 A
    [[nodiscard]] uint32 RecruitRareChance(uint32 guildId);     // 100 B
    [[nodiscard]] uint32 RecruitEpicChance(uint32 guildId);     // 100 B
    [[nodiscard]] bool WeeklyExtraGear(uint32 guildId)      { return Has(guildId, 125, MILESTONE_A); }
    [[nodiscard]] bool WeeklyExtraCuriosity(uint32 guildId) { return Has(guildId, 125, MILESTONE_B); }
    [[nodiscard]] uint32 ContractCount(uint32 guildId);         // 150 A
    [[nodiscard]] uint32 ContractFreeRerolls(uint32 guildId);   // 150 B
    [[nodiscard]] float ContractBonusMultiplier(uint32 guildId);// 150 B
    [[nodiscard]] uint32 WorkOrderCount(uint32 guildId);        // 175 A
    [[nodiscard]] uint32 AbandonDelayHours(uint32 guildId);     // 175 B
    [[nodiscard]] uint32 RareMissionChance(uint32 guildId);     // 200 A
    [[nodiscard]] uint32 SalvageChance(uint32 guildId);         // 200 B
    [[nodiscard]] float MissionSuppliesMultiplier(uint32 guildId);   // 225 A
    [[nodiscard]] float MissionLootMultiplier(uint32 guildId);       // 225 B: gold and materials

    // Client requests.
    void SendAdvancement(Player* player);
    void HandleSpend(Player* player, uint8 track, uint32 count);
    void HandleReset(Player* player);
    void HandleChoose(Player* player, uint32 milestone, uint8 choice);

    // GM: refund all points without the fee.
    void ResetPoints(uint32 guildId);

private:
    AdvancementMgr() = default;

    struct GuildAdvancement
    {
        std::array<uint32, TRACK_COUNT + 1> tracks{};   // index = track, 0 unused
        std::map<uint32, uint8> milestones;             // milestone level -> choice
    };

    GuildAdvancement& Get(uint32 guildId);
    [[nodiscard]] bool CheckRequest(Player* player);
    [[nodiscard]] static bool CanEdit(Player* player);
    [[nodiscard]] uint32 ResetCost(uint32 guildId);

    std::unordered_map<uint32, GuildAdvancement> _guilds;
};

#define sAdvancementMgr AdvancementMgr::instance()

#endif
