/*
 * mod-guild-expansion: guild missions.
 */

#include "GspeMissions.h"
#include "GspeAddonComm.h"
#include "GspeConfig.h"
#include "GspePerks.h"
#include "GspeProgress.h"
#include "GspeUnits.h"
#include "GspeWorkOrders.h"

#include "Chat.h"
#include "Containers.h"
#include "DatabaseEnv.h"
#include "Guild.h"
#include "GuildMgr.h"
#include "Item.h"
#include "Log.h"
#include "Mail.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "Random.h"
#include "StringConvert.h"
#include "StringFormat.h"
#include "Tokenize.h"

#include <algorithm>
#include <cmath>
#include <unordered_set>

namespace
{
constexpr uint32 OFFER_LIFETIME = 24 * 3600;
// Missing a role the mission needs (tank, healer) costs this much success chance.
constexpr int32 MISSING_ROLE_PENALTY = 25;

template <typename T>
std::vector<T> ParseCsv(std::string const& csv)
{
    std::vector<T> out;
    for (std::string_view token : Acore::Tokenize(csv, ',', false))
        if (Optional<T> v = Acore::StringTo<T>(token))
            out.push_back(*v);
    return out;
}

template <typename T>
std::string JoinCsv(std::vector<T> const& values)
{
    std::string out;
    for (T v : values)
    {
        if (!out.empty())
            out += ',';
        out += std::to_string(uint32(v));
    }
    return out;
}

// Per mission type: gold, flat supplies, guild XP and unit XP multipliers, crafting
// material reward, and gear reward quality (0 = none).
struct TypeRewards
{
    float gold;
    uint32 supplies;
    float guildXp;
    float unitXp;
    bool material;
    uint8 gear;
};

TypeRewards RewardsFor(uint8 type)
{
    switch (type)
    {
        case MISSION_GATHERING: return { 0.4f, 5,  0.8f, 1.0f, true,  0 };
        case MISSION_SUPPLY:    return { 0.5f, 0,  0.8f, 1.0f, false, 0 };
        case MISSION_BOUNTY:    return { 0.6f, 5,  1.0f, 1.0f, false, 2 };
        case MISSION_DUNGEON:   return { 1.2f, 10, 1.5f, 1.2f, false, 3 };
        case MISSION_TRAINING:  return { 0.1f, 0,  0.5f, 2.5f, false, 0 };
        case MISSION_RAID:      return { 2.0f, 20, 2.0f, 1.5f, false, 4 };
        default:                return { 1.0f, 5,  1.0f, 1.0f, false, 0 };   // patrol
    }
}

// Gives the item, mailing whatever doesn't fit in the bags.
void GiveItem(Player* player, uint32 itemId, uint32 count)
{
    ItemTemplate const* proto = sObjectMgr->GetItemTemplate(itemId);
    if (!proto || !count)
        return;

    uint32 const stack = std::max<uint32>(1, proto->GetMaxStackSize());
    while (count)
    {
        uint32 const n = std::min(count, stack);
        count -= n;

        int32 const randomProperty = Item::GenerateItemRandomPropertyId(itemId);
        ItemPosCountVec dest;
        if (player->CanStoreNewItem(NULL_BAG, NULL_SLOT, dest, itemId, n) == EQUIP_ERR_OK)
        {
            if (Item* item = player->StoreNewItem(dest, itemId, true, randomProperty))
                player->SendNewItem(item, n, true, false);
            continue;
        }

        if (Item* item = Item::CreateItem(itemId, n, player, false, randomProperty))
        {
            CharacterDatabaseTransaction trans = CharacterDatabase.BeginTransaction();
            item->SaveToDB(trans);
            MailDraft("Guild mission rewards", "Your bags were full, so the guild sent these along.")
                .AddItem(item)
                .SendMailTo(trans, MailReceiver(player), MailSender(MAIL_NORMAL, player->GetGUID().GetCounter(), MAIL_STATIONERY_GM));
            CharacterDatabase.CommitTransaction(trans);
            ChatHandler(player->GetSession()).SendSysMessage("Your bags are full; mission rewards were sent by mail.");
        }
    }
}

uint32 BestArmorSubclass(Player* player)
{
    if (player->HasSkill(SKILL_PLATE_MAIL))
        return ITEM_SUBCLASS_ARMOR_PLATE;
    if (player->HasSkill(SKILL_MAIL))
        return ITEM_SUBCLASS_ARMOR_MAIL;
    if (player->HasSkill(SKILL_LEATHER))
        return ITEM_SUBCLASS_ARMOR_LEATHER;
    return ITEM_SUBCLASS_ARMOR_CLOTH;
}
} // namespace

MissionMgr* MissionMgr::instance()
{
    static MissionMgr inst;
    return &inst;
}

void MissionMgr::Load()
{
    _templates.clear();
    _templateIndex.clear();
    _guilds.clear();
    _gearPool.clear();

    if (QueryResult r = WorldDatabase.Query(
            "SELECT id, type, name, description, slots, min_minutes, max_minutes, threats, threat_count, roles, "
            "min_level, weight FROM mod_gspe_mission_template"))
    {
        do
        {
            Field* f = r->Fetch();
            MissionTemplate t;
            t.id = f[0].Get<uint16>();
            t.type = f[1].Get<uint8>();
            t.name = f[2].Get<std::string>();
            t.description = f[3].Get<std::string>();
            t.slots = std::clamp<uint8>(f[4].Get<uint8>(), 1, MAX_MISSION_UNITS);
            t.minMinutes = std::max<uint32>(5, f[5].Get<uint16>());
            t.maxMinutes = std::max<uint32>(t.minMinutes, f[6].Get<uint16>());
            t.threats = ParseCsv<uint8>(f[7].Get<std::string>());
            std::erase_if(t.threats, [](uint8 x) { return x < 1 || x > UNIT_ABILITY_COUNT; });
            t.threatCount = std::min<uint8>(f[8].Get<uint8>(), uint8(t.threats.size()));
            t.roles = ParseCsv<uint8>(f[9].Get<std::string>());
            t.minLevel = f[10].Get<uint8>();
            t.weight = f[11].Get<uint16>();
            if (!t.weight)
                continue;

            _templateIndex[t.id] = _templates.size();
            _templates.push_back(std::move(t));
        } while (r->NextRow());
    }

    // Gear that actually drops or is a quest reward, so missions don't hand out unused items.
    std::unordered_set<uint32> gear;
    auto collect = [&gear](std::string const& sql)
    {
        if (QueryResult r = WorldDatabase.Query(sql))
            do
                gear.insert(r->Fetch()[0].Get<uint32>());
            while (r->NextRow());
    };
    std::string const filter = "it.class IN (2, 4) AND it.Quality BETWEEN 2 AND 4 AND it.RequiredLevel > 0";
    for (char const* table : { "creature_loot_template", "reference_loot_template", "gameobject_loot_template", "item_loot_template" })
        collect(Acore::StringFormat("SELECT DISTINCT lt.Item FROM {} lt JOIN item_template it ON it.entry = lt.Item "
                                    "WHERE lt.Reference = 0 AND {}", table, filter));
    for (char const* column : { "RewardChoiceItemID1", "RewardChoiceItemID2", "RewardChoiceItemID3",
                                "RewardChoiceItemID4", "RewardChoiceItemID5", "RewardChoiceItemID6",
                                "RewardItem1", "RewardItem2", "RewardItem3", "RewardItem4" })
        collect(Acore::StringFormat("SELECT DISTINCT q.{0} FROM quest_template q JOIN item_template it ON it.entry = q.{0} "
                                    "WHERE {1}", column, filter));
    _gearPool.assign(gear.begin(), gear.end());

    if (QueryResult r = CharacterDatabase.Query("SELECT MAX(id) FROM mod_gspe_mission"))
        _nextId = r->Fetch()[0].Get<uint32>() + 1;

    // Load guilds with running missions so completion alerts work without anyone opening the board.
    if (QueryResult r = CharacterDatabase.Query("SELECT DISTINCT guildid FROM mod_gspe_mission WHERE state = 1"))
        do
            GetMissions(r->Fetch()[0].Get<uint32>());
        while (r->NextRow());

    LOG_INFO("module", "GuildExpansion: {} mission templates, {} gear rewards.", _templates.size(), _gearPool.size());
}

MissionTemplate const* MissionMgr::GetTemplate(uint16 id) const
{
    auto itr = _templateIndex.find(id);
    return itr != _templateIndex.end() ? &_templates[itr->second] : nullptr;
}

std::vector<GuildMission>& MissionMgr::GetMissions(uint32 guildId)
{
    if (auto itr = _guilds.find(guildId); itr != _guilds.end())
        return itr->second;

    std::vector<GuildMission>& missions = _guilds[guildId];
    if (QueryResult r = CharacterDatabase.Query(
            "SELECT id, template, state, level, threats, duration, cost, gold, supplies, guild_xp, unit_xp, item, "
            "item_count, gear, units, chance, ends, expires FROM mod_gspe_mission WHERE guildid = {} ORDER BY id", guildId))
    {
        do
        {
            Field* f = r->Fetch();
            GuildMission m;
            m.id = f[0].Get<uint32>();
            m.guildId = guildId;
            m.templateId = f[1].Get<uint16>();
            m.state = f[2].Get<uint8>();
            m.level = f[3].Get<uint8>();
            m.threats = ParseCsv<uint8>(f[4].Get<std::string>());
            m.duration = f[5].Get<uint32>();
            m.cost = f[6].Get<uint32>();
            m.gold = f[7].Get<uint32>();
            m.supplies = f[8].Get<uint32>();
            m.guildXp = f[9].Get<uint32>();
            m.unitXp = f[10].Get<uint32>();
            m.item = f[11].Get<uint32>();
            m.itemCount = f[12].Get<uint16>();
            m.gear = f[13].Get<uint8>();
            m.units = ParseCsv<uint32>(f[14].Get<std::string>());
            m.chance = f[15].Get<uint16>();
            m.ends = f[16].Get<uint32>();
            m.expires = f[17].Get<uint32>();
            missions.push_back(std::move(m));
        } while (r->NextRow());
    }
    return missions;
}

GuildMission* MissionMgr::Find(uint32 guildId, uint32 missionId)
{
    std::vector<GuildMission>& missions = GetMissions(guildId);
    auto itr = std::find_if(missions.begin(), missions.end(), [missionId](GuildMission const& m) { return m.id == missionId; });
    return itr != missions.end() ? &*itr : nullptr;
}

void MissionMgr::Save(GuildMission const& m)
{
    CharacterDatabase.Execute(
        "REPLACE INTO mod_gspe_mission (id, guildid, template, state, level, threats, duration, cost, gold, supplies, "
        "guild_xp, unit_xp, item, item_count, gear, units, chance, ends, expires) "
        "VALUES ({}, {}, {}, {}, {}, '{}', {}, {}, {}, {}, {}, {}, {}, {}, {}, '{}', {}, {}, {})",
        m.id, m.guildId, m.templateId, m.state, m.level, JoinCsv(m.threats), m.duration, m.cost, m.gold, m.supplies,
        m.guildXp, m.unitXp, m.item, m.itemCount, m.gear, JoinCsv(m.units), m.chance, m.ends, m.expires);
}

void MissionMgr::Delete(uint32 missionId)
{
    CharacterDatabase.Execute("DELETE FROM mod_gspe_mission WHERE id = {}", missionId);
}

void MissionMgr::OnGuildDisband(uint32 guildId)
{
    _guilds.erase(guildId);
    CharacterDatabase.Execute("DELETE FROM mod_gspe_mission WHERE guildid = {}", guildId);
}

void MissionMgr::SetRewards(GuildMission& m, MissionTemplate const& tmpl)
{
    GspeConfig const* cfg = sGspeConfig;
    TypeRewards const tr = RewardsFor(tmpl.type);
    float const hours = std::max(0.5f, float(m.duration) / 3600.0f);
    float const L = float(m.level);

    m.cost = uint32((8.0f + L * 0.25f + hours * 4.0f) * cfg->missionCostMultiplier);
    m.gold = uint32(10.0f * L * L * hours * tr.gold * cfg->missionGoldMultiplier);
    m.supplies = tr.supplies;
    if (tmpl.type == MISSION_SUPPLY)
        m.supplies = uint32((20.0f + L * 0.5f) * hours);
    m.guildXp = uint32(60.0f * L * hours * tr.guildXp * cfg->missionGuildXpMultiplier);
    m.unitXp = uint32(float(UnitMgr::XpForNextLevel(m.level)) * 0.5f * hours * tr.unitXp * cfg->missionUnitXpMultiplier);

    m.item = 0;
    m.itemCount = 0;
    if (tr.material)
        if ((m.item = sWorkOrderMgr->RandomMaterial(m.level)))
            m.itemCount = urand(10, 20);

    m.gear = tr.gear;
    if (m.gear == 2 && roll_chance_i(25))
        m.gear = 3;
    if (m.gear == 4 && !roll_chance_i(30))
        m.gear = 3;
}

bool MissionMgr::GenerateOffer(uint32 guildId, std::vector<GuildMission> const& existing, GuildMission& out)
{
    uint8 const cap = sUnitMgr->LevelCap(guildId);
    uint8 top = 0;
    for (GuildUnit const& u : sUnitMgr->GetUnits(guildId))
        if (u.status != UNIT_STATUS_CANDIDATE)
            top = std::max(top, u.level);
    if (!top)
        top = cap;

    uint8 const level = uint8(std::clamp<int32>(int32(top) - int32(urand(0, 2)), 1, cap));

    // Weighted pick among templates allowed at this level and not already on the board.
    std::vector<MissionTemplate const*> pool;
    uint32 total = 0;
    for (MissionTemplate const& t : _templates)
    {
        if (t.minLevel > level)
            continue;
        if (std::any_of(existing.begin(), existing.end(), [&t](GuildMission const& m) { return m.templateId == t.id; }))
            continue;
        pool.push_back(&t);
        total += t.weight;
    }
    if (!total)
        return false;

    MissionTemplate const* tmpl = nullptr;
    uint32 roll = urand(1, total);
    for (MissionTemplate const* t : pool)
    {
        if (roll <= t->weight)
        {
            tmpl = t;
            break;
        }
        roll -= t->weight;
    }
    if (!tmpl)
        return false;

    out = GuildMission{};
    out.id = _nextId++;
    out.guildId = guildId;
    out.templateId = tmpl->id;
    out.level = level;

    std::vector<uint8> threats = tmpl->threats;
    Acore::Containers::RandomShuffle(threats);
    threats.resize(tmpl->threatCount);
    out.threats = threats;

    uint32 const minutes = urand(tmpl->minMinutes / 5, tmpl->maxMinutes / 5) * 5;
    out.duration = std::max<uint32>(5, minutes) * 60;
    out.expires = uint32(time(nullptr)) + OFFER_LIFETIME;
    SetRewards(out, *tmpl);
    return true;
}

void MissionMgr::RefillBoard(uint32 guildId, std::vector<GuildMission>& missions)
{
    uint32 const now = uint32(time(nullptr));
    for (GuildMission const& m : missions)
        if (m.state == MISSION_STATE_OFFER && (m.expires <= now || !GetTemplate(m.templateId)))
            Delete(m.id);
    std::erase_if(missions, [&](GuildMission const& m)
        { return m.state == MISSION_STATE_OFFER && (m.expires <= now || !GetTemplate(m.templateId)); });

    auto offers = [&missions]()
    {
        return uint32(std::count_if(missions.begin(), missions.end(),
            [](GuildMission const& m) { return m.state == MISSION_STATE_OFFER; }));
    };

    while (offers() < sGspeConfig->missionBoardSize)
    {
        GuildMission offer;
        if (!GenerateOffer(guildId, missions, offer))
            break;
        Save(offer);
        missions.push_back(std::move(offer));
    }
}

void MissionMgr::RerollBoard(uint32 guildId)
{
    std::vector<GuildMission>& missions = GetMissions(guildId);
    for (GuildMission const& m : missions)
        if (m.state == MISSION_STATE_OFFER)
            Delete(m.id);
    std::erase_if(missions, [](GuildMission const& m) { return m.state == MISSION_STATE_OFFER; });
    RefillBoard(guildId, missions);
}

void MissionMgr::FinishRunning(uint32 guildId)
{
    uint32 const now = uint32(time(nullptr));
    for (GuildMission& m : GetMissions(guildId))
        if (m.state == MISSION_STATE_RUNNING && m.ends > now)
        {
            m.ends = now;
            Save(m);
        }
}

MissionMgr::Chance MissionMgr::ComputeChance(GuildMission const& m, std::vector<GuildUnit const*> const& units) const
{
    Chance result;
    MissionTemplate const* tmpl = GetTemplate(m.templateId);
    if (!tmpl)
        return result;

    float chance = 0.0f;
    float const missionItemLevel = float(UnitMgr::ItemLevelForLevel(m.level));
    float const share = 60.0f / float(tmpl->slots);
    for (GuildUnit const* u : units)
    {
        float const levelFactor = std::clamp(1.0f - 0.15f * float(std::max(0, int32(m.level) - int32(u->level))), 0.0f, 1.0f);
        float const gearFactor = std::clamp(1.0f + (float(u->itemLevel) - missionItemLevel) / 50.0f, 0.5f, 1.5f);
        chance += share * levelFactor * gearFactor;
    }

    if (m.threats.empty())
        chance += 40.0f;
    for (uint8 threat : m.threats)
    {
        bool const countered = std::any_of(units.begin(), units.end(), [threat](GuildUnit const* u)
            { return u->abilities[0] == threat || u->abilities[1] == threat; });
        if (countered)
        {
            chance += 40.0f / float(m.threats.size());
            result.countered.push_back(threat);
        }
    }

    for (uint8 role : tmpl->roles)
    {
        bool const present = std::any_of(units.begin(), units.end(), [role](GuildUnit const* u)
        {
            UnitTemplate const* ut = sUnitMgr->GetTemplate(u->templateId);
            return ut && ut->role == role;
        });
        if (!present)
        {
            chance -= float(MISSING_ROLE_PENALTY);
            result.missingRoles.push_back(role);
        }
    }

    result.value = uint32(std::clamp(std::lround(chance), 0L, 200L));
    return result;
}

bool MissionMgr::ResolveUnits(Player* player, GuildMission const& m, std::vector<uint32> const& unitIds,
                              std::vector<GuildUnit*>& out, bool reportErrors)
{
    MissionTemplate const* tmpl = GetTemplate(m.templateId);
    if (!tmpl)
        return false;

    auto fail = [&](char const* text)
    {
        if (reportErrors)
            GspeAddonComm::SendError(player, text);
        return false;
    };

    if (unitIds.size() > tmpl->slots)
        return fail("Too many units for this mission.");

    std::unordered_set<uint32> seen;
    for (uint32 id : unitIds)
    {
        if (!seen.insert(id).second)
            return fail("A unit can only fill one slot.");

        GuildUnit* u = sUnitMgr->FindUnit(m.guildId, id);
        if (!u || u->status == UNIT_STATUS_CANDIDATE)
            return fail("That unit is not in your guild.");
        if (u->status == UNIT_STATUS_ON_MISSION)
            return fail("That unit is already on a mission.");
        out.push_back(u);
    }
    return true;
}

bool MissionMgr::CheckRequest(Player* player)
{
    if (!sGspeConfig->enable || !sGspeConfig->missionsEnable || !sGspeConfig->unitsEnable)
    {
        GspeAddonComm::Send(player, "MB\t0\t0\t0\t2");
        GspeAddonComm::Send(player, "ME");
        return false;
    }
    if (!player->GetGuildId())
    {
        GspeAddonComm::Send(player, "MB\t0\t0\t0\t1");
        GspeAddonComm::Send(player, "ME");
        return false;
    }
    return true;
}

void MissionMgr::SendTemplates(Player* player)
{
    // MT\tid\ttype\tslots\troles\tname, then MD\tid\tdescription
    for (MissionTemplate const& t : _templates)
    {
        GspeAddonComm::Send(player, Acore::StringFormat("MT\t{}\t{}\t{}\t{}\t{}",
            t.id, uint32(t.type), uint32(t.slots), JoinCsv(t.roles), GspeAddonComm::Sanitize(t.name, 64)));
        GspeAddonComm::Send(player, Acore::StringFormat("MD\t{}\t{}", t.id, GspeAddonComm::Sanitize(t.description, 200)));
    }
    GspeAddonComm::Send(player, "MTE");
}

void MissionMgr::SendMissionLine(Player* player, GuildMission const& m)
{
    uint32 const now = uint32(time(nullptr));
    // M\tid\tstate\ttemplate\tlevel\titemLevel\tthreats\tduration\tcost\tgold\tsupplies\tguildXp\tunitXp\titem\t
    //   itemCount\tgear\tchance\tunits\tremaining\texpiresIn
    GspeAddonComm::Send(player, Acore::StringFormat(
        "M\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}",
        m.id, uint32(m.state), m.templateId, uint32(m.level), UnitMgr::ItemLevelForLevel(m.level), JoinCsv(m.threats),
        m.duration, m.cost, m.gold, m.supplies, m.guildXp, m.unitXp, m.item, m.itemCount, uint32(m.gear), m.chance,
        JoinCsv(m.units), m.ends > now ? m.ends - now : 0, m.expires > now ? m.expires - now : 0));
}

void MissionMgr::SendBoard(Player* player)
{
    if (!CheckRequest(player))
        return;

    uint32 const guildId = player->GetGuildId();
    std::vector<GuildMission>& missions = GetMissions(guildId);
    RefillBoard(guildId, missions);

    uint32 offers = 0, running = 0;
    for (GuildMission const& m : missions)
        (m.state == MISSION_STATE_OFFER ? offers : running)++;

    // MB\toffers\trunning\tslots\tstatus
    GspeAddonComm::Send(player, Acore::StringFormat("MB\t{}\t{}\t{}\t0",
        offers, running, GspePerks::MissionSlots(sGuildProgressMgr->GetLevel(guildId))));
    for (GuildMission const& m : missions)
        SendMissionLine(player, m);
    GspeAddonComm::Send(player, "ME");
}

void MissionMgr::HandlePreview(Player* player, uint32 missionId, std::vector<uint32> const& unitIds)
{
    if (!player->GetGuildId())
        return;

    GuildMission* m = Find(player->GetGuildId(), missionId);
    std::vector<GuildUnit*> units;
    if (!m || m->state != MISSION_STATE_OFFER || !ResolveUnits(player, *m, unitIds, units, false))
        return;

    Chance const c = ComputeChance(*m, std::vector<GuildUnit const*>(units.begin(), units.end()));
    // MCHANCE\tid\tchance\tcountered\tmissingRoles
    GspeAddonComm::Send(player, Acore::StringFormat("MCHANCE\t{}\t{}\t{}\t{}",
        missionId, c.value, JoinCsv(c.countered), JoinCsv(c.missingRoles)));
}

void MissionMgr::HandleStart(Player* player, uint32 missionId, std::vector<uint32> const& unitIds)
{
    if (!CheckRequest(player))
        return;

    uint32 const guildId = player->GetGuildId();
    GuildMission* m = Find(guildId, missionId);
    if (!m || m->state != MISSION_STATE_OFFER || m->expires <= uint32(time(nullptr)))
    {
        GspeAddonComm::SendError(player, "That mission is no longer available.");
        SendBoard(player);
        return;
    }

    std::vector<GuildUnit*> units;
    if (!ResolveUnits(player, *m, unitIds, units, true))
        return;
    if (units.empty())
    {
        GspeAddonComm::SendError(player, "Assign at least one unit.");
        return;
    }

    std::vector<GuildMission> const& missions = GetMissions(guildId);
    uint32 const running = uint32(std::count_if(missions.begin(), missions.end(),
        [](GuildMission const& x) { return x.state == MISSION_STATE_RUNNING; }));
    if (running >= GspePerks::MissionSlots(sGuildProgressMgr->GetLevel(guildId)))
    {
        GspeAddonComm::SendError(player, "All of your guild's mission slots are in use.");
        return;
    }

    if (!sGuildProgressMgr->SpendSupplies(guildId, m->cost))
    {
        GspeAddonComm::SendError(player, Acore::StringFormat("This mission costs {} guild supplies.", m->cost));
        return;
    }

    m->chance = ComputeChance(*m, std::vector<GuildUnit const*>(units.begin(), units.end())).value;
    m->state = MISSION_STATE_RUNNING;
    m->ends = uint32(time(nullptr)) + m->duration;
    m->units.clear();
    for (GuildUnit* u : units)
    {
        m->units.push_back(u->id);
        u->status = UNIT_STATUS_ON_MISSION;
        u->mission = m->id;
        sUnitMgr->SaveUnit(*u);
    }
    Save(*m);

    GspeAddonComm::Send(player, Acore::StringFormat("MSTARTED\t{}", missionId));
    SendBoard(player);
    sUnitMgr->SendUnits(player);
}

uint32 MissionMgr::RollGear(Player* player, uint8 level, uint8 quality) const
{
    uint32 const best = BestArmorSubclass(player);
    uint32 const minLevel = level > 6 ? level - 6 : 1;

    for (uint8 q = quality; q >= 2; --q)
    {
        std::vector<uint32> candidates;
        for (uint32 entry : _gearPool)
        {
            ItemTemplate const* t = sObjectMgr->GetItemTemplate(entry);
            if (!t || t->Quality != q || t->RequiredLevel < minLevel || t->RequiredLevel > level)
                continue;
            // Armor in the class's best armor type; cloaks, jewelry, shields and the like for anyone.
            if (t->Class == ITEM_CLASS_ARMOR && t->SubClass >= ITEM_SUBCLASS_ARMOR_CLOTH
                && t->SubClass <= ITEM_SUBCLASS_ARMOR_PLATE && t->InventoryType != INVTYPE_CLOAK && t->SubClass != best)
                continue;
            if (player->CanUseItem(t) != EQUIP_ERR_OK)
                continue;
            candidates.push_back(entry);
        }
        if (!candidates.empty())
            return Acore::Containers::SelectRandomContainerElement(candidates);
    }
    return 0;
}

void MissionMgr::HandleCollect(Player* player, uint32 missionId)
{
    if (!CheckRequest(player))
        return;

    uint32 const guildId = player->GetGuildId();
    GuildMission* found = Find(guildId, missionId);
    uint32 const now = uint32(time(nullptr));
    if (!found || found->state != MISSION_STATE_RUNNING)
    {
        SendBoard(player);
        return;
    }
    if (found->ends > now)
    {
        GspeAddonComm::SendError(player, "That mission isn't finished yet.");
        return;
    }

    GuildMission const m = *found;
    bool const success = urand(1, 100) <= std::min<uint32>(m.chance, 100);
    bool const bonus = success && m.chance > 100 && urand(1, 100) <= m.chance - 100;

    uint32 gold = 0, supplies = 0, guildXp = 0, item = 0, itemCount = 0, gear = 0;
    if (success)
    {
        gold = bonus ? m.gold * 2 : m.gold;
        supplies = m.supplies;
        guildXp = m.guildXp;
        item = m.item;
        itemCount = bonus ? m.itemCount * 2 : m.itemCount;
        if (m.gear)
            gear = RollGear(player, std::min<uint8>(m.level, uint8(player->GetLevel())), m.gear);

        if (gold)
            player->ModifyMoney(int32(std::min<uint32>(gold, uint32(INT32_MAX))));
        if (supplies)
            sGuildProgressMgr->AddSupplies(guildId, supplies);
        if (guildXp)
            sGuildProgressMgr->AddGuildXP(guildId, guildXp, player);
        if (item && itemCount)
            GiveItem(player, item, itemCount);
        if (gear)
            GiveItem(player, gear, 1);
    }
    else
    {
        // Failure refunds half the supply cost.
        supplies = m.cost / 2;
        if (supplies)
            sGuildProgressMgr->AddSupplies(guildId, supplies);
    }

    uint32 const unitXp = success ? m.unitXp : m.unitXp / 2;
    uint8 const cap = sUnitMgr->LevelCap(guildId);
    uint32 levelUps = 0;
    for (uint32 unitId : m.units)
    {
        if (GuildUnit* u = sUnitMgr->FindUnit(guildId, unitId))
        {
            levelUps += sUnitMgr->AddXp(*u, unitXp, cap);
            u->status = UNIT_STATUS_IDLE;
            u->mission = 0;
            sUnitMgr->SaveUnit(*u);
        }
    }

    Delete(missionId);
    std::erase_if(GetMissions(guildId), [missionId](GuildMission const& x) { return x.id == missionId; });

    // MRESULT\tid\ttemplate\tsuccess\tbonus\tgold\tsupplies\tguildXp\tunitXp\titem\titemCount\tgear\tlevelUps
    GspeAddonComm::Send(player, Acore::StringFormat("MRESULT\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}",
        missionId, m.templateId, success ? 1 : 0, bonus ? 1 : 0, gold, supplies, guildXp, unitXp, item, itemCount,
        gear, levelUps));
    SendBoard(player);
    sUnitMgr->SendUnits(player);
}

void MissionMgr::Update()
{
    uint32 const now = uint32(time(nullptr));
    for (auto& [guildId, missions] : _guilds)
    {
        for (GuildMission& m : missions)
        {
            if (m.state != MISSION_STATE_RUNNING || m.notified || m.ends > now)
                continue;

            m.notified = true;
            Guild* guild = sGuildMgr->GetGuildById(guildId);
            if (!guild)
                continue;

            std::string const line = Acore::StringFormat("MDONE\t{}\t{}", m.id, m.templateId);
            struct Notifier
            {
                std::string const& line;
                void operator()(Player* p) const { GspeAddonComm::Send(p, line); }
            } notifier{ line };
            guild->BroadcastWorker(notifier);
        }
    }
}
