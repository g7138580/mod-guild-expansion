/*
 * mod-guild-expansion: guild advancement after level 25.
 */

#include "GspeAdvancement.h"
#include "GspeAddonComm.h"
#include "GspeConfig.h"
#include "GspePerks.h"
#include "GspeProgress.h"
#include "GspeUnits.h"

#include "DatabaseEnv.h"
#include "Player.h"
#include "StringFormat.h"

#include <algorithm>

namespace
{
bool IsChoiceMilestone(uint32 level)
{
    return level >= MILESTONE_FIRST && level <= MILESTONE_LAST_CHOICE && level % MILESTONE_STEP == 0;
}
} // namespace

AdvancementMgr* AdvancementMgr::instance()
{
    static AdvancementMgr inst;
    return &inst;
}

AdvancementMgr::GuildAdvancement& AdvancementMgr::Get(uint32 guildId)
{
    if (auto itr = _guilds.find(guildId); itr != _guilds.end())
        return itr->second;

    GuildAdvancement& adv = _guilds[guildId];
    if (QueryResult r = CharacterDatabase.Query("SELECT track, points FROM mod_gspe_guild_points WHERE guildid = {}", guildId))
        do
        {
            uint8 const track = r->Fetch()[0].Get<uint8>();
            if (track >= 1 && track <= TRACK_COUNT)
                adv.tracks[track] = std::min<uint32>(r->Fetch()[1].Get<uint16>(), TRACK_MAX_POINTS);
        } while (r->NextRow());
    if (QueryResult r = CharacterDatabase.Query("SELECT milestone, choice FROM mod_gspe_guild_milestone WHERE guildid = {}", guildId))
        do
        {
            uint32 const milestone = r->Fetch()[0].Get<uint16>();
            uint8 const choice = r->Fetch()[1].Get<uint8>();
            if (IsChoiceMilestone(milestone) && (choice == MILESTONE_A || choice == MILESTONE_B))
                adv.milestones[milestone] = choice;
        } while (r->NextRow());
    return adv;
}

void AdvancementMgr::OnGuildDisband(uint32 guildId)
{
    _guilds.erase(guildId);
    CharacterDatabase.Execute("DELETE FROM mod_gspe_guild_points WHERE guildid = {}", guildId);
    CharacterDatabase.Execute("DELETE FROM mod_gspe_guild_milestone WHERE guildid = {}", guildId);
}

uint32 AdvancementMgr::Points(uint32 guildId, uint8 track)
{
    if (!guildId || track < 1 || track > TRACK_COUNT)
        return 0;
    return Get(guildId).tracks[track];
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
        spent += Get(guildId).tracks[t];
    return spent;
}

uint8 AdvancementMgr::Milestone(uint32 guildId, uint32 level)
{
    if (!guildId || sGuildProgressMgr->GetLevel(guildId) < level)
        return MILESTONE_NONE;
    auto const& milestones = Get(guildId).milestones;
    auto itr = milestones.find(level);
    return itr != milestones.end() ? itr->second : MILESTONE_NONE;
}

// Tracks ------------------------------------------------------------------------------

float AdvancementMgr::SuppliesMultiplier(uint32 guildId)           { return 1.0f + 0.01f * float(Points(guildId, TRACK_SUPPLY_LINES)); }
uint32 AdvancementMgr::MissionSuccessBonus(uint32 guildId)         { return Points(guildId, TRACK_FIELD_COMMAND); }
float AdvancementMgr::MissionDurationMultiplier(uint32 guildId)    { return 1.0f - 0.01f * float(Points(guildId, TRACK_SWIFT_COURIERS)); }
float AdvancementMgr::GoldMultiplier(uint32 guildId)               { return 1.0f + 0.02f * float(Points(guildId, TRACK_TRADE_AGREEMENTS)); }
float AdvancementMgr::UnitXpMultiplier(uint32 guildId)             { return 1.0f + 0.02f * float(Points(guildId, TRACK_DRILL_SERGEANT)); }
float AdvancementMgr::QuartermasterPriceMultiplier(uint32 guildId) { return 1.0f - 0.01f * float(Points(guildId, TRACK_QUARTERMASTER)); }
float AdvancementMgr::CharacterXpMultiplier(uint32 guildId)        { return 1.0f + 0.004f * float(Points(guildId, TRACK_SEASONED_TRAVELERS)); }
float AdvancementMgr::ReputationMultiplier(uint32 guildId)         { return 1.0f + 0.004f * float(Points(guildId, TRACK_GOOD_STANDING)); }
float AdvancementMgr::ExtraSkillUpChance(uint32 guildId)           { return 0.4f * float(Points(guildId, TRACK_STEADY_HANDS)); }

// Milestones ---------------------------------------------------------------------------

uint32 AdvancementMgr::MissionSlots(uint32 guildId)
{
    return GspePerks::MissionSlots(sGuildProgressMgr->GetLevel(guildId)) + (Has(guildId, 50, MILESTONE_A) ? 1 : 0);
}

uint32 AdvancementMgr::UnitSlots(uint32 guildId)
{
    return GspePerks::UnitSlots(sGuildProgressMgr->GetLevel(guildId)) + (Has(guildId, 50, MILESTONE_B) ? 1 : 0);
}

uint32 AdvancementMgr::TroopSlots(uint32 guildId)
{
    return GspePerks::TroopSlots(sGuildProgressMgr->GetLevel(guildId)) + (Has(guildId, 75, MILESTONE_A) ? 2 : 0);
}

uint8 AdvancementMgr::TroopVitality(uint32 guildId)
{
    return TROOP_VITALITY + (Has(guildId, 75, MILESTONE_B) ? 1 : 0);
}

uint32 AdvancementMgr::RecruitCandidates(uint32 guildId)
{
    return sGspeConfig->recruitCandidates + (Has(guildId, 100, MILESTONE_A) ? 1 : 0);
}

uint32 AdvancementMgr::RecruitRareChance(uint32 guildId)
{
    return sGspeConfig->recruitRareChance + (Has(guildId, 100, MILESTONE_B) ? 10 : 0);
}

uint32 AdvancementMgr::RecruitEpicChance(uint32 guildId)
{
    return sGspeConfig->recruitEpicChance + (Has(guildId, 100, MILESTONE_B) ? 3 : 0);
}

uint32 AdvancementMgr::ContractCount(uint32 guildId)
{
    return sGspeConfig->contractCount + (Has(guildId, 150, MILESTONE_A) ? 1 : 0);
}

uint32 AdvancementMgr::ContractFreeRerolls(uint32 guildId)
{
    return sGspeConfig->contractFreeRerolls + (Has(guildId, 150, MILESTONE_B) ? 1 : 0);
}

float AdvancementMgr::ContractBonusMultiplier(uint32 guildId)
{
    return Has(guildId, 150, MILESTONE_B) ? 1.5f : 1.0f;
}

uint32 AdvancementMgr::WorkOrderCount(uint32 guildId)
{
    return sGspeConfig->workOrderCount + (Has(guildId, 175, MILESTONE_A) ? 1 : 0);
}

uint32 AdvancementMgr::AbandonDelayHours(uint32 guildId)
{
    return Has(guildId, 175, MILESTONE_B) ? 0 : sGspeConfig->workOrderAbandonDelayHours;
}

uint32 AdvancementMgr::RareMissionChance(uint32 guildId)
{
    return sGspeConfig->missionRareChance * (Has(guildId, 200, MILESTONE_A) ? 2 : 1);
}

uint32 AdvancementMgr::SalvageChance(uint32 guildId)
{
    return sGspeConfig->missionSalvageChance * (Has(guildId, 200, MILESTONE_B) ? 2 : 1);
}

float AdvancementMgr::MissionSuppliesMultiplier(uint32 guildId)
{
    return Has(guildId, 225, MILESTONE_A) ? 1.25f : 1.0f;
}

float AdvancementMgr::MissionLootMultiplier(uint32 guildId)
{
    return Has(guildId, 225, MILESTONE_B) ? 1.25f : 1.0f;
}

// Requests -----------------------------------------------------------------------------

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
        GspeAddonComm::Send(player, Acore::StringFormat("AB\t{}\t0\t0\t0\t0\t0\t0\t0", sGspeConfig->enable ? 1 : 2));
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
    GuildAdvancement& adv = Get(guildId);
    // AB\tstatus\tlevel\tearned\tspent\tresetCost\tcanEdit\ttrackMax\tchangeCost
    GspeAddonComm::Send(player, Acore::StringFormat("AB\t0\t{}\t{}\t{}\t{}\t{}\t{}\t{}",
        uint32(sGuildProgressMgr->GetLevel(guildId)), Earned(guildId), Spent(guildId), ResetCost(guildId),
        CanEdit(player) ? 1 : 0, TRACK_MAX_POINTS, sGspeConfig->milestoneChangeCost));
    for (uint8 t = 1; t <= TRACK_COUNT; ++t)
        GspeAddonComm::Send(player, Acore::StringFormat("AT\t{}\t{}", uint32(t), adv.tracks[t]));
    for (auto const& [milestone, choice] : adv.milestones)
        GspeAddonComm::Send(player, Acore::StringFormat("AM\t{}\t{}", milestone, uint32(choice)));
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
    auto& tracks = Get(guildId).tracks;
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

void AdvancementMgr::HandleChoose(Player* player, uint32 milestone, uint8 choice)
{
    if (!CheckRequest(player))
        return;
    if (!CanEdit(player))
    {
        GspeAddonComm::SendError(player, "Only the guild master and officers can choose milestone bonuses.");
        return;
    }
    if (!IsChoiceMilestone(milestone) || (choice != MILESTONE_A && choice != MILESTONE_B))
        return;

    uint32 const guildId = player->GetGuildId();
    if (sGuildProgressMgr->GetLevel(guildId) < milestone)
    {
        GspeAddonComm::SendError(player, Acore::StringFormat("Your guild needs to reach level {} first.", milestone));
        return;
    }

    auto& milestones = Get(guildId).milestones;
    auto itr = milestones.find(milestone);
    uint8 const current = itr != milestones.end() ? itr->second : MILESTONE_NONE;
    if (current == choice)
        return;

    // The first choice is free; changing it later costs supplies.
    if (current != MILESTONE_NONE && !sGuildProgressMgr->SpendSupplies(guildId, sGspeConfig->milestoneChangeCost))
    {
        GspeAddonComm::SendError(player, "Your guild doesn't have enough supplies.");
        return;
    }

    milestones[milestone] = choice;
    CharacterDatabase.Execute("REPLACE INTO mod_gspe_guild_milestone (guildid, milestone, choice) VALUES ({}, {}, {})",
        guildId, milestone, uint32(choice));
    GspeAddonComm::Send(player, Acore::StringFormat("ACHOSEN\t{}\t{}", milestone, uint32(choice)));
    SendAdvancement(player);
}

void AdvancementMgr::ResetPoints(uint32 guildId)
{
    Get(guildId).tracks.fill(0);
    CharacterDatabase.Execute("DELETE FROM mod_gspe_guild_points WHERE guildid = {}", guildId);
}
