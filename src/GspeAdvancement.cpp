/*
 * mod-guild-expansion: guild advancement after level 25.
 */

#include "GspeAdvancement.h"
#include "GspeAddonComm.h"
#include "GspeConfig.h"
#include "GspePerks.h"
#include "GspeProgress.h"

#include "DatabaseEnv.h"
#include "Player.h"
#include "StringFormat.h"

#include <algorithm>

AdvancementMgr* AdvancementMgr::instance()
{
    static AdvancementMgr inst;
    return &inst;
}

AdvancementMgr::Tracks& AdvancementMgr::GetTracks(uint32 guildId)
{
    if (auto itr = _guilds.find(guildId); itr != _guilds.end())
        return itr->second;

    Tracks& tracks = _guilds[guildId];
    tracks.fill(0);
    if (QueryResult r = CharacterDatabase.Query("SELECT track, points FROM mod_gspe_guild_points WHERE guildid = {}", guildId))
        do
        {
            uint8 const track = r->Fetch()[0].Get<uint8>();
            if (track >= 1 && track <= TRACK_COUNT)
                tracks[track] = std::min<uint32>(r->Fetch()[1].Get<uint16>(), TRACK_MAX_POINTS);
        } while (r->NextRow());
    return tracks;
}

void AdvancementMgr::OnGuildDisband(uint32 guildId)
{
    _guilds.erase(guildId);
    CharacterDatabase.Execute("DELETE FROM mod_gspe_guild_points WHERE guildid = {}", guildId);
}

uint32 AdvancementMgr::Points(uint32 guildId, uint8 track)
{
    if (!guildId || track < 1 || track > TRACK_COUNT)
        return 0;
    return GetTracks(guildId)[track];
}

uint32 AdvancementMgr::Earned(uint32 guildId)
{
    uint8 const level = sGuildProgressMgr->GetLevel(guildId);
    return level > GspePerks::MAX_GUILD_LEVEL ? uint32(level - GspePerks::MAX_GUILD_LEVEL) : 0;
}

uint32 AdvancementMgr::Spent(uint32 guildId)
{
    uint32 spent = 0;
    for (uint8 t = 1; t <= TRACK_COUNT; ++t)
        spent += GetTracks(guildId)[t];
    return spent;
}

float AdvancementMgr::SuppliesMultiplier(uint32 guildId)           { return 1.0f + 0.01f * float(Points(guildId, TRACK_SUPPLY_LINES)); }
uint32 AdvancementMgr::MissionSuccessBonus(uint32 guildId)         { return Points(guildId, TRACK_FIELD_COMMAND); }
float AdvancementMgr::MissionDurationMultiplier(uint32 guildId)    { return 1.0f - 0.01f * float(Points(guildId, TRACK_SWIFT_COURIERS)); }
float AdvancementMgr::GoldMultiplier(uint32 guildId)               { return 1.0f + 0.02f * float(Points(guildId, TRACK_TRADE_AGREEMENTS)); }
float AdvancementMgr::UnitXpMultiplier(uint32 guildId)             { return 1.0f + 0.02f * float(Points(guildId, TRACK_DRILL_SERGEANT)); }
float AdvancementMgr::QuartermasterPriceMultiplier(uint32 guildId) { return 1.0f - 0.01f * float(Points(guildId, TRACK_QUARTERMASTER)); }
float AdvancementMgr::CharacterXpMultiplier(uint32 guildId)        { return 1.0f + 0.004f * float(Points(guildId, TRACK_SEASONED_TRAVELERS)); }
float AdvancementMgr::ReputationMultiplier(uint32 guildId)         { return 1.0f + 0.004f * float(Points(guildId, TRACK_GOOD_STANDING)); }
float AdvancementMgr::ExtraSkillUpChance(uint32 guildId)           { return 0.4f * float(Points(guildId, TRACK_STEADY_HANDS)); }

bool AdvancementMgr::CanEdit(Player* player)
{
    // The guild master and officers (the two highest ranks).
    return player->GetRank() <= 1;
}

uint32 AdvancementMgr::ResetCost(uint32 guildId)
{
    return Spent(guildId) * sGspeConfig->advancementResetCostPerPoint;
}

bool AdvancementMgr::CheckRequest(Player* player)
{
    if (!sGspeConfig->enable || !player->GetGuildId())
    {
        GspeAddonComm::Send(player, Acore::StringFormat("AB\t{}\t0\t0\t0\t0\t0\t0", sGspeConfig->enable ? 1 : 2));
        GspeAddonComm::Send(player, "AE");
        return false;
    }
    return true;
}

void AdvancementMgr::SendAdvancement(Player* player)
{
    if (!CheckRequest(player))
        return;

    uint32 const guildId = player->GetGuildId();
    // AB\tstatus\tlevel\tearned\tspent\tresetCost\tcanEdit\ttrackMax
    GspeAddonComm::Send(player, Acore::StringFormat("AB\t0\t{}\t{}\t{}\t{}\t{}\t{}",
        uint32(sGuildProgressMgr->GetLevel(guildId)), Earned(guildId), Spent(guildId), ResetCost(guildId),
        CanEdit(player) ? 1 : 0, TRACK_MAX_POINTS));
    for (uint8 t = 1; t <= TRACK_COUNT; ++t)
        GspeAddonComm::Send(player, Acore::StringFormat("AT\t{}\t{}", uint32(t), GetTracks(guildId)[t]));
    GspeAddonComm::Send(player, "AE");
}

void AdvancementMgr::HandleSpend(Player* player, uint8 track, uint32 count)
{
    if (!CheckRequest(player))
        return;
    if (!CanEdit(player))
    {
        GspeAddonComm::SendError(player, "Only the guild master and officers can spend Guild Points.");
        return;
    }
    if (track < 1 || track > TRACK_COUNT || !count)
        return;

    uint32 const guildId = player->GetGuildId();
    Tracks& tracks = GetTracks(guildId);
    uint32 const available = Earned(guildId) - std::min(Earned(guildId), Spent(guildId));
    uint32 const add = std::min({ count, available, TRACK_MAX_POINTS - std::min(tracks[track], TRACK_MAX_POINTS) });
    if (!add)
    {
        GspeAddonComm::SendError(player, available ? "That track is full." : "No Guild Points to spend.");
        return;
    }

    tracks[track] += add;
    CharacterDatabase.Execute("REPLACE INTO mod_gspe_guild_points (guildid, track, points) VALUES ({}, {}, {})",
        guildId, uint32(track), tracks[track]);
    GspeAddonComm::Send(player, Acore::StringFormat("ASPENT\t{}\t{}", uint32(track), add));
    SendAdvancement(player);
}

void AdvancementMgr::HandleReset(Player* player)
{
    if (!CheckRequest(player))
        return;
    if (!CanEdit(player))
    {
        GspeAddonComm::SendError(player, "Only the guild master and officers can reset Guild Points.");
        return;
    }

    uint32 const guildId = player->GetGuildId();
    if (!Spent(guildId))
        return;
    if (!sGuildProgressMgr->SpendSupplies(guildId, ResetCost(guildId)))
    {
        GspeAddonComm::SendError(player, "Your guild doesn't have enough supplies.");
        return;
    }

    ResetPoints(guildId);
    SendAdvancement(player);
}

void AdvancementMgr::ResetPoints(uint32 guildId)
{
    GetTracks(guildId).fill(0);
    CharacterDatabase.Execute("DELETE FROM mod_gspe_guild_points WHERE guildid = {}", guildId);
}
