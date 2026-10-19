/*
 * mod-guild-expansion: guild XP, level and supplies persistence.
 */

#include "GspeProgress.h"
#include "GspeAddonComm.h"
#include "GspeConfig.h"
#include "GspePerks.h"

#include "DatabaseEnv.h"
#include "Guild.h"
#include "GuildMgr.h"
#include "Log.h"
#include "Player.h"
#include "SpellMgr.h"
#include "StringFormat.h"
#include "WorldSession.h"

#include <algorithm>

GuildProgressMgr* GuildProgressMgr::instance()
{
    static GuildProgressMgr inst;
    return &inst;
}

bool GuildProgressMgr::IsHeadless(Player const* player)
{
    // Playerbots and other server-driven sessions have no client socket.
    return player && player->GetSession() && player->GetSession()->IsSocketClosed();
}

uint8 GuildProgressMgr::MaxGuildLevel()
{
    return uint8(sGspeConfig->maxGuildLevel);
}

uint64 GuildProgressMgr::CumulativeXpForLevel(uint8 targetLevel)
{
    if (targetLevel <= 1)
        return 0;

    // Levels up to 25: 4000 x level^2 for each level, scaled by the curve multiplier.
    uint64 const n = std::min<uint64>(targetLevel, GspePerks::MAX_GUILD_LEVEL) - 1;
    uint64 const squares = n * (n + 1) * (2 * n + 1) / 6;
    uint64 total = uint64(double(4000ull * squares) * sGspeConfig->levelCurveMultiplier);

    // After 25 each level costs a fixed step more than the one before.
    if (targetLevel > GspePerks::MAX_GUILD_LEVEL)
    {
        uint64 const m = targetLevel - GspePerks::MAX_GUILD_LEVEL;
        total += m * sGspeConfig->levelCostAfter25 + uint64(sGspeConfig->levelCostStep) * m * (m + 1) / 2;
    }
    return total;
}

uint32 GuildProgressMgr::LevelUpSupplies(uint8 level)
{
    if (level <= GspePerks::MAX_GUILD_LEVEL)
        return 0;
    uint32 supplies = sGspeConfig->levelSuppliesBase + sGspeConfig->levelSuppliesStep * (level - GspePerks::MAX_GUILD_LEVEL);
    if (level == MaxGuildLevel())
        supplies += sGspeConfig->levelCapstoneSupplies;
    return supplies;
}

uint8 GuildProgressMgr::LevelFromTotalXp(uint64 xp)
{
    uint8 level = 1;
    while (level < MaxGuildLevel() && xp >= CumulativeXpForLevel(level + 1))
        ++level;
    return level;
}

uint64 GuildProgressMgr::MaxStorableXp()
{
    return CumulativeXpForLevel(MaxGuildLevel() + 1) - 1;
}

void GuildProgressMgr::MigrateFromGuildLevels()
{
    QueryResult hasOld = CharacterDatabase.Query(
        "SELECT 1 FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = 'guild_progress'");
    if (!hasOld)
        return;

    if (CharacterDatabase.Query("SELECT 1 FROM mod_gspe_progress LIMIT 1"))
        return;

    CharacterDatabase.DirectExecute(
        "INSERT INTO mod_gspe_progress (guildid, xp, level, today_xp, week_xp, last_daily_reset, last_weekly_reset) "
        "SELECT gp.guildid, gp.xp, gp.level, gp.today_xp, gp.week_xp, gp.last_daily_reset, gp.last_weekly_reset "
        "FROM guild_progress gp JOIN guild g ON g.guildid = gp.guildid");
    LOG_INFO("module", "GuildExpansion: copied guild progress from mod-guild-levels (guild_progress).");
}

void GuildProgressMgr::EnsureProgressRow(uint32 guildId)
{
    CharacterDatabase.DirectExecute("INSERT IGNORE INTO mod_gspe_progress (guildid) VALUES ({})", guildId);
}

void GuildProgressMgr::DeleteProgress(uint32 guildId)
{
    CharacterDatabase.Execute("DELETE FROM mod_gspe_progress WHERE guildid = {}", guildId);
    _cache.erase(guildId);
    _lastAddonPush.erase(guildId);
    _pendingAddonPush.erase(guildId);
}

bool GuildProgressMgr::ApplyCalendarResets(GuildProgressState& st)
{
    time_t const now = time(nullptr);
    uint32 const dayIndex = uint32(now / 86400);
    uint32 const weekIndex = uint32(now / (86400 * 7));

    bool changed = false;
    if (st.lastDailyReset != dayIndex)
    {
        st.todayXp = 0;
        st.lastDailyReset = dayIndex;
        changed = true;
    }
    if (st.lastWeeklyReset != weekIndex)
    {
        st.weekXp = 0;
        st.lastWeeklyReset = weekIndex;
        changed = true;
    }
    return changed;
}

bool GuildProgressMgr::LoadProgress(uint32 guildId, GuildProgressState& out)
{
    if (!guildId)
        return false;

    if (auto itr = _cache.find(guildId); itr != _cache.end())
    {
        out = itr->second;
        return true;
    }

    out = GuildProgressState{};
    if (QueryResult r = CharacterDatabase.Query(
            "SELECT xp, level, supplies, today_xp, week_xp, last_daily_reset, last_weekly_reset "
            "FROM mod_gspe_progress WHERE guildid = {}", guildId))
    {
        Field* f = r->Fetch();
        out.xp = f[0].Get<uint64>();
        uint8 const dbLevel = f[1].Get<uint8>();
        out.supplies = f[2].Get<uint32>();
        out.todayXp = f[3].Get<uint32>();
        out.weekXp = f[4].Get<uint32>();
        out.lastDailyReset = f[5].Get<uint32>();
        out.lastWeeklyReset = f[6].Get<uint32>();

        // The level is derived from XP so curve changes in config apply on load.
        out.level = LevelFromTotalXp(out.xp);
        if (ApplyCalendarResets(out) || out.level != dbLevel)
            SaveProgress(guildId, out);
        else
            _cache[guildId] = out;
        return true;
    }

    if (!sGuildMgr->GetGuildById(guildId))
        return false;

    EnsureProgressRow(guildId);
    ApplyCalendarResets(out);
    SaveProgress(guildId, out);
    return true;
}

uint8 GuildProgressMgr::GetLevel(uint32 guildId)
{
    GuildProgressState st{};
    return LoadProgress(guildId, st) ? st.level : 0;
}

void GuildProgressMgr::SaveProgress(uint32 guildId, GuildProgressState const& st)
{
    _cache[guildId] = st;
    CharacterDatabase.Execute(
        "UPDATE mod_gspe_progress SET xp = {}, level = {}, supplies = {}, today_xp = {}, week_xp = {}, "
        "last_daily_reset = {}, last_weekly_reset = {} WHERE guildid = {}",
        st.xp, st.level, st.supplies, st.todayXp, st.weekXp, st.lastDailyReset, st.lastWeeklyReset, guildId);
}

void GuildProgressMgr::AddGuildXP(uint32 guildId, uint32 amount, Player const* contributor)
{
    if (!guildId || !amount || !sGspeConfig->enable)
        return;

    if (sGspeConfig->ignoreHeadlessPlayers && IsHeadless(contributor))
        return;

    GuildProgressState st{};
    if (!LoadProgress(guildId, st))
        return;

    ApplyCalendarResets(st);

    uint32 add = amount;
    if (uint32 const cap = sGspeConfig->dailyXpCap)
        add = st.todayXp < cap ? std::min(add, cap - st.todayXp) : 0;
    if (uint32 const cap = sGspeConfig->weeklyXpCap)
        add = st.weekXp < cap ? std::min(add, cap - st.weekXp) : 0;
    if (!add)
        return;

    uint8 const oldLevel = st.level;
    st.xp = std::min(st.xp + add, MaxStorableXp());
    st.todayXp += add;
    st.weekXp += add;
    st.level = LevelFromTotalXp(st.xp);
    SaveProgress(guildId, st);

    if (st.level != oldLevel)
        OnLevelChanged(guildId, oldLevel, st.level);

    // XP ticks on every kill and quest, so rate-limit the guild-wide push. A level-up
    // pushes immediately; held-back gains go out from FlushPendingAddonPushes().
    PushAddonState(guildId, st.level != oldLevel);
}

void GuildProgressMgr::AddSupplies(uint32 guildId, uint32 amount)
{
    GuildProgressState st{};
    if (!amount || !LoadProgress(guildId, st))
        return;

    st.supplies += amount;
    SaveProgress(guildId, st);
    PushAddonState(guildId, false);
}

bool GuildProgressMgr::SpendSupplies(uint32 guildId, uint32 amount)
{
    GuildProgressState st{};
    if (!LoadProgress(guildId, st) || st.supplies < amount)
        return false;

    st.supplies -= amount;
    SaveProgress(guildId, st);
    PushAddonState(guildId, true);
    return true;
}

void GuildProgressMgr::SetSupplies(uint32 guildId, uint32 supplies)
{
    GuildProgressState st{};
    if (!LoadProgress(guildId, st))
        return;

    st.supplies = supplies;
    SaveProgress(guildId, st);
    PushAddonState(guildId, true);
}

void GuildProgressMgr::SetGuildXp(uint32 guildId, uint64 xp)
{
    GuildProgressState st{};
    if (!LoadProgress(guildId, st))
        return;

    uint8 const oldLevel = st.level;
    st.xp = std::min(xp, MaxStorableXp());
    st.level = LevelFromTotalXp(st.xp);
    SaveProgress(guildId, st);

    if (st.level != oldLevel)
        OnLevelChanged(guildId, oldLevel, st.level);
    PushAddonState(guildId, true);
}

void GuildProgressMgr::SetGuildLevel(uint32 guildId, uint8 level)
{
    level = std::clamp<uint8>(level, 1, MaxGuildLevel());
    SetGuildXp(guildId, CumulativeXpForLevel(level));
}

void GuildProgressMgr::OnLevelChanged(uint32 guildId, uint8 oldLevel, uint8 newLevel)
{
    Guild* guild = sGuildMgr->GetGuildById(guildId);
    if (!guild)
        return;

    if (newLevel > oldLevel)
    {
        // Each level after 25 pays supplies (and a Guild Point, counted from the level).
        uint32 supplies = 0;
        for (uint32 level = uint32(oldLevel) + 1; level <= newLevel; ++level)
            supplies += LevelUpSupplies(uint8(level));
        if (supplies)
            AddSupplies(guildId, supplies);

        std::string text = Acore::StringFormat("Your guild has reached level {}!", uint32(newLevel));
        if (newLevel > GspePerks::MAX_GUILD_LEVEL)
        {
            uint32 const points = uint32(newLevel) - std::max<uint32>(oldLevel, GspePerks::MAX_GUILD_LEVEL);
            text += Acore::StringFormat(" +{} Guild Point{}, +{} guild supplies.", points, points == 1 ? "" : "s", supplies);
        }
        guild->BroadcastToGuild(nullptr, false, text);
    }

    struct PerkRefresh
    {
        void operator()(Player* member) const { GuildProgressMgr::instance()->RefreshPlayerPerks(member); }
    } worker;
    guild->BroadcastWorker(worker);
}

void GuildProgressMgr::PushAddonState(uint32 guildId, bool immediate)
{
    time_t const now = time(nullptr);
    time_t& lastPush = _lastAddonPush[guildId];
    if (immediate || now - lastPush >= ADDON_PUSH_INTERVAL)
    {
        lastPush = now;
        _pendingAddonPush.erase(guildId);
        GspeAddonComm::BroadcastState(guildId);
    }
    else
        _pendingAddonPush.insert(guildId);
}

void GuildProgressMgr::FlushPendingAddonPushes()
{
    if (_pendingAddonPush.empty())
        return;

    time_t const now = time(nullptr);
    for (auto itr = _pendingAddonPush.begin(); itr != _pendingAddonPush.end();)
    {
        time_t& lastPush = _lastAddonPush[*itr];
        if (now - lastPush < ADDON_PUSH_INTERVAL)
        {
            ++itr;
            continue;
        }

        lastPush = now;
        GspeAddonComm::BroadcastState(*itr);
        itr = _pendingAddonPush.erase(itr);
    }
}

void GuildProgressMgr::UpdateTemporarySpell(Player* player, uint32 spellId, bool shouldHave)
{
    if (!player || !spellId)
        return;

    if (!shouldHave || !sSpellMgr->GetSpellInfo(spellId))
    {
        if (player->HasSpell(spellId))
            player->removeSpell(spellId, SPEC_MASK_ALL, true);
        return;
    }

    if (!player->HasSpell(spellId))
        player->learnSpell(spellId, true);
}

void GuildProgressMgr::RefreshPlayerPerks(Player* player)
{
    if (!player)
        return;

    ClearGuildPerks(player);

    if (!player->GetGuildId() || !sGspeConfig->enable)
        return;

    uint8 const level = GetLevel(player->GetGuildId());

    uint32 const mountUp = sGspeConfig->mountUpSpellId;
    if (mountUp && sSpellMgr->GetSpellInfo(mountUp) && GspePerks::Has(level, GspePerks::MOUNT_UP))
        player->CastSpell(player, mountUp, true);

    UpdateTemporarySpell(player, sGspeConfig->mobileBankingSpellId,
        GspePerks::Has(level, GspePerks::MOBILE_BANKING));
}

void GuildProgressMgr::ClearGuildPerks(Player* player)
{
    if (!player)
        return;

    if (uint32 const mountUp = sGspeConfig->mountUpSpellId)
        player->RemoveAurasDueToSpell(mountUp);

    UpdateTemporarySpell(player, sGspeConfig->mobileBankingSpellId, false);
}
