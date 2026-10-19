/*
 * mod-guild-expansion: guild XP, level and supplies.
 */

#ifndef MOD_GSPE_PROGRESS_H_
#define MOD_GSPE_PROGRESS_H_

#include "Define.h"
#include <ctime>
#include <unordered_map>
#include <unordered_set>

class Player;

struct GuildProgressState
{
    uint64 xp = 0;
    uint8 level = 1;
    uint32 supplies = 0;
    uint32 todayXp = 0;
    uint32 weekXp = 0;
    uint32 lastDailyReset = 0;
    uint32 lastWeeklyReset = 0;
};

class GuildProgressMgr
{
public:
    static GuildProgressMgr* instance();

    // Copies mod-guild-levels' `guild_progress` into `mod_gspe_progress` the first time.
    void MigrateFromGuildLevels();

    void DeleteProgress(uint32 guildId);
    bool LoadProgress(uint32 guildId, GuildProgressState& out);
    [[nodiscard]] uint8 GetLevel(uint32 guildId);

    // contributor may be null (GM commands). Gains from headless sessions (bots) are
    // ignored when GuildExpansion.IgnoreHeadlessPlayers is set.
    void AddGuildXP(uint32 guildId, uint32 amount, Player const* contributor);
    void AddSupplies(uint32 guildId, uint32 amount);
    // Takes supplies if the guild has enough; returns false (and changes nothing) otherwise.
    [[nodiscard]] bool SpendSupplies(uint32 guildId, uint32 amount);
    void SetGuildXp(uint32 guildId, uint64 xp);
    void SetGuildLevel(uint32 guildId, uint8 level);
    void SetSupplies(uint32 guildId, uint32 supplies);

    void RefreshPlayerPerks(Player* player);
    void ClearGuildPerks(Player* player);

    // Sends addon snapshots that the XP-gain rate limit held back, once their window has passed.
    void FlushPendingAddonPushes();

    [[nodiscard]] static bool IsHeadless(Player const* player);
    [[nodiscard]] static uint8 MaxGuildLevel();
    [[nodiscard]] static uint64 CumulativeXpForLevel(uint8 targetLevel);
    [[nodiscard]] static uint8 LevelFromTotalXp(uint64 xp);
    [[nodiscard]] static uint64 MaxStorableXp();
    // Supplies paid for reaching a level after 25 (0 for levels up to 25).
    [[nodiscard]] static uint32 LevelUpSupplies(uint8 level);

private:
    GuildProgressMgr() = default;

    static constexpr time_t ADDON_PUSH_INTERVAL = 5;

    void EnsureProgressRow(uint32 guildId);
    bool ApplyCalendarResets(GuildProgressState& st);
    void SaveProgress(uint32 guildId, GuildProgressState const& st);
    void OnLevelChanged(uint32 guildId, uint8 oldLevel, uint8 newLevel);
    void PushAddonState(uint32 guildId, bool immediate);
    void UpdateTemporarySpell(Player* player, uint32 spellId, bool shouldHave);

    std::unordered_map<uint32, GuildProgressState> _cache;
    // Last addon snapshot push per guild, to rate-limit XP broadcasts.
    std::unordered_map<uint32, time_t> _lastAddonPush;
    // Guilds whose latest change fell inside the rate-limit window and still need a push.
    std::unordered_set<uint32> _pendingAddonPush;
};

#define sGuildProgressMgr GuildProgressMgr::instance()

#endif
