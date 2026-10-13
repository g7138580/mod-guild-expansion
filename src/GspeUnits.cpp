/*
 * mod-guild-expansion: guild units (champions).
 */

#include "GspeUnits.h"
#include "GspeAddonComm.h"
#include "GspeConfig.h"
#include "GspePerks.h"
#include "GspeProgress.h"

#include "Containers.h"
#include "DatabaseEnv.h"
#include "Log.h"
#include "Player.h"
#include "Random.h"
#include "StringConvert.h"
#include "StringFormat.h"
#include "Tokenize.h"

#include <algorithm>

namespace
{
constexpr uint32 CANDIDATE_LIFETIME = 24 * 3600;

std::vector<uint8> ParseIdList(std::string const& csv)
{
    std::vector<uint8> out;
    for (std::string_view token : Acore::Tokenize(csv, ',', false))
        if (Optional<uint8> v = Acore::StringTo<uint8>(token))
            out.push_back(*v);
    return out;
}

// Up to `count` distinct ids from the pool, in random order.
std::vector<uint8> PickDistinct(std::vector<uint8> pool, std::size_t count)
{
    Acore::Containers::RandomShuffle(pool);
    if (pool.size() > count)
        pool.resize(count);
    return pool;
}
} // namespace

UnitMgr* UnitMgr::instance()
{
    static UnitMgr inst;
    return &inst;
}

void UnitMgr::LoadTemplates()
{
    _templates.clear();
    _templateIndex.clear();
    _names.clear();

    if (QueryResult r = WorldDatabase.Query(
            "SELECT id, kind, name, races, class, role, abilities, traits, icon, weight FROM mod_gspe_unit_template"))
    {
        do
        {
            Field* f = r->Fetch();
            UnitTemplate t;
            t.id = f[0].Get<uint16>();
            t.kind = f[1].Get<uint8>();
            t.name = f[2].Get<std::string>();
            t.races = ParseIdList(f[3].Get<std::string>());
            t.classId = f[4].Get<uint8>();
            t.role = std::min<uint8>(f[5].Get<uint8>(), UNIT_ROLE_DAMAGE);
            t.abilities = ParseIdList(f[6].Get<std::string>());
            t.traits = ParseIdList(f[7].Get<std::string>());
            t.icon = f[8].Get<std::string>();
            t.weight = f[9].Get<uint16>();

            std::erase_if(t.abilities, [](uint8 a) { return a < 1 || a > UNIT_ABILITY_COUNT; });
            std::erase_if(t.traits, [](uint8 a) { return a < 1 || a > UNIT_TRAIT_COUNT; });
            if (t.races.empty() || !t.weight)
            {
                LOG_ERROR("module", "GuildExpansion: unit template {} has no races or zero weight; skipped.", t.id);
                continue;
            }

            _templateIndex[t.id] = _templates.size();
            _templates.push_back(std::move(t));
        } while (r->NextRow());
    }

    if (QueryResult r = WorldDatabase.Query("SELECT race, gender, name FROM mod_gspe_unit_name"))
    {
        do
        {
            Field* f = r->Fetch();
            _names[{ f[0].Get<uint8>(), f[1].Get<uint8>() }].push_back(f[2].Get<std::string>());
        } while (r->NextRow());
    }

    if (QueryResult r = CharacterDatabase.Query("SELECT MAX(id) FROM mod_gspe_unit"))
        _nextId = r->Fetch()[0].Get<uint32>() + 1;

    LOG_INFO("module", "GuildExpansion: {} unit templates loaded.", _templates.size());
}

UnitTemplate const* UnitMgr::GetTemplate(uint16 id) const
{
    auto itr = _templateIndex.find(id);
    return itr != _templateIndex.end() ? &_templates[itr->second] : nullptr;
}

uint32 UnitMgr::XpForNextLevel(uint8 level)
{
    return 150 + 30 * uint32(level);
}

uint16 UnitMgr::ItemLevelForLevel(uint8 level)
{
    if (level <= 60)
        return uint16(level + 5);
    if (level <= 70)
        return uint16(65 + (level - 60) * 5);
    return uint16(115 + (level - 70) * 7);
}

std::vector<GuildUnit>& UnitMgr::GetUnits(uint32 guildId)
{
    if (auto itr = _guilds.find(guildId); itr != _guilds.end())
        return itr->second;

    std::vector<GuildUnit>& units = _guilds[guildId];
    if (QueryResult r = CharacterDatabase.Query(
            "SELECT id, template, name, race, gender, quality, level, xp, item_level, ability1, ability2, "
            "trait1, trait2, status, mission, cost, expires, vitality FROM mod_gspe_unit WHERE guildid = {} ORDER BY id", guildId))
    {
        do
        {
            Field* f = r->Fetch();
            GuildUnit u;
            u.id = f[0].Get<uint32>();
            u.guildId = guildId;
            u.templateId = f[1].Get<uint16>();
            u.name = f[2].Get<std::string>();
            u.race = f[3].Get<uint8>();
            u.gender = f[4].Get<uint8>();
            u.quality = f[5].Get<uint8>();
            u.level = f[6].Get<uint8>();
            u.xp = f[7].Get<uint32>();
            u.itemLevel = f[8].Get<uint16>();
            u.abilities[0] = f[9].Get<uint8>();
            u.abilities[1] = f[10].Get<uint8>();
            u.traits[0] = f[11].Get<uint8>();
            u.traits[1] = f[12].Get<uint8>();
            u.status = f[13].Get<uint8>();
            u.mission = f[14].Get<uint32>();
            u.cost = f[15].Get<uint32>();
            u.expires = f[16].Get<uint32>();
            u.vitality = f[17].Get<uint8>();
            units.push_back(std::move(u));
        } while (r->NextRow());
    }
    return units;
}

GuildUnit* UnitMgr::FindUnit(uint32 guildId, uint32 unitId)
{
    std::vector<GuildUnit>& units = GetUnits(guildId);
    auto itr = std::find_if(units.begin(), units.end(), [unitId](GuildUnit const& u) { return u.id == unitId; });
    return itr != units.end() ? &*itr : nullptr;
}

void UnitMgr::SaveUnit(GuildUnit const& u)
{
    std::string name = u.name;
    CharacterDatabase.EscapeString(name);
    CharacterDatabase.Execute(
        "REPLACE INTO mod_gspe_unit (id, guildid, template, name, race, gender, quality, level, xp, item_level, "
        "ability1, ability2, trait1, trait2, status, mission, cost, expires, vitality) "
        "VALUES ({}, {}, {}, '{}', {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {})",
        u.id, u.guildId, u.templateId, name, u.race, u.gender, u.quality, u.level, u.xp, u.itemLevel,
        u.abilities[0], u.abilities[1], u.traits[0], u.traits[1], u.status, u.mission, u.cost, u.expires, u.vitality);
}

void UnitMgr::DeleteUnit(uint32 unitId)
{
    CharacterDatabase.Execute("DELETE FROM mod_gspe_unit WHERE id = {}", unitId);
}

void UnitMgr::RemoveUnit(uint32 guildId, uint32 unitId)
{
    DeleteUnit(unitId);
    std::erase_if(GetUnits(guildId), [unitId](GuildUnit const& u) { return u.id == unitId; });
}

bool UnitMgr::IsTroop(GuildUnit const& unit) const
{
    UnitTemplate const* t = GetTemplate(unit.templateId);
    return t && t->kind == UNIT_KIND_TROOP;
}

void UnitMgr::OnGuildDisband(uint32 guildId)
{
    _guilds.erase(guildId);
    CharacterDatabase.Execute("DELETE FROM mod_gspe_unit WHERE guildid = {}", guildId);
}

uint8 UnitMgr::LevelCap(uint32 guildId)
{
    uint8 cap = 1;
    if (QueryResult r = CharacterDatabase.Query(
            "SELECT MAX(c.level) FROM characters c JOIN guild_member gm ON gm.guid = c.guid WHERE gm.guildid = {}", guildId))
        cap = r->Fetch()[0].Get<uint8>();
    return std::clamp<uint8>(cap, 1, UNIT_MAX_LEVEL);
}

uint32 UnitMgr::AddXp(GuildUnit& unit, uint32 xp, uint8 cap)
{
    uint32 levels = 0;
    unit.xp += xp;
    while (unit.level < cap && unit.xp >= XpForNextLevel(unit.level))
    {
        unit.xp -= XpForNextLevel(unit.level);
        ++unit.level;
        ++levels;
        unit.itemLevel = std::max(unit.itemLevel, uint16(ItemLevelForLevel(unit.level) - 5));
    }

    // At the cap, XP stops at one level's worth so nothing is lost when the cap rises.
    if (unit.level >= cap)
        unit.xp = std::min(unit.xp, XpForNextLevel(unit.level) - 1);
    return levels;
}

UnitTemplate const* UnitMgr::PickTemplate(int8 role) const
{
    uint32 total = 0;
    for (UnitTemplate const& t : _templates)
        if (t.kind != UNIT_KIND_TROOP && (role < 0 || t.role == uint8(role)))
            total += t.weight;
    if (!total)
        return nullptr;

    uint32 roll = urand(1, total);
    for (UnitTemplate const& t : _templates)
    {
        if (t.kind == UNIT_KIND_TROOP || (role >= 0 && t.role != uint8(role)))
            continue;
        if (roll <= t.weight)
            return &t;
        roll -= t.weight;
    }
    return nullptr;
}

uint8 UnitMgr::RollQuality() const
{
    uint32 const roll = urand(1, 100);
    if (roll <= sGspeConfig->recruitEpicChance)
        return UNIT_QUALITY_EPIC;
    if (roll <= sGspeConfig->recruitEpicChance + sGspeConfig->recruitRareChance)
        return UNIT_QUALITY_RARE;
    return UNIT_QUALITY_UNCOMMON;
}

uint32 UnitMgr::RecruitCost(uint8 quality) const
{
    switch (quality)
    {
        case UNIT_QUALITY_EPIC: return sGspeConfig->recruitCostEpic;
        case UNIT_QUALITY_RARE: return sGspeConfig->recruitCostRare;
        default:                return sGspeConfig->recruitCostUncommon;
    }
}

std::string UnitMgr::PickName(uint8 race, uint8 gender, std::vector<GuildUnit> const& existing) const
{
    auto itr = _names.find({ race, gender });
    if (itr == _names.end() || itr->second.empty())
        return "Nameless Recruit";

    // Prefer a name nobody in the guild has yet.
    std::vector<std::string const*> unused;
    for (std::string const& n : itr->second)
        if (std::none_of(existing.begin(), existing.end(), [&n](GuildUnit const& u) { return u.name == n; }))
            unused.push_back(&n);

    return unused.empty() ? Acore::Containers::SelectRandomContainerElement(itr->second)
                          : *Acore::Containers::SelectRandomContainerElement(unused);
}

GuildUnit UnitMgr::RollUnit(uint32 guildId, UnitTemplate const& tmpl, uint8 quality, uint8 level,
                            std::vector<GuildUnit> const& existing)
{
    GuildUnit u;
    u.id = _nextId++;
    u.guildId = guildId;
    u.templateId = tmpl.id;
    u.race = Acore::Containers::SelectRandomContainerElement(tmpl.races);
    u.gender = uint8(urand(0, 1));
    u.name = PickName(u.race, u.gender, existing);
    u.quality = quality;
    u.level = level;
    u.itemLevel = uint16(ItemLevelForLevel(level) - urand(3, 6));

    std::size_t const abilityCount = quality >= UNIT_QUALITY_RARE ? 2 : 1;
    std::size_t const traitCount = quality == UNIT_QUALITY_EPIC ? 2 : (quality == UNIT_QUALITY_RARE ? 1 : 0);

    std::vector<uint8> const abilities = PickDistinct(tmpl.abilities, abilityCount);
    for (std::size_t i = 0; i < abilities.size(); ++i)
        u.abilities[i] = abilities[i];

    std::vector<uint8> traitPool = tmpl.traits;
    if (traitPool.empty())
        for (uint8 t = 1; t <= UNIT_TRAIT_COUNT; ++t)
            traitPool.push_back(t);
    std::vector<uint8> const traits = PickDistinct(traitPool, traitCount);
    for (std::size_t i = 0; i < traits.size(); ++i)
        u.traits[i] = traits[i];

    return u;
}

void UnitMgr::EnsureStarterUnits(uint32 guildId, std::vector<GuildUnit>& units)
{
    QueryResult r = CharacterDatabase.Query("SELECT starter_units FROM mod_gspe_progress WHERE guildid = {}", guildId);
    if (!r || r->Fetch()[0].Get<uint8>())
        return;

    if (std::any_of(units.begin(), units.end(), [this](GuildUnit const& u) { return u.status != UNIT_STATUS_CANDIDATE && !IsTroop(u); }))
    {
        CharacterDatabase.Execute("UPDATE mod_gspe_progress SET starter_units = 1 WHERE guildid = {}", guildId);
        return;
    }

    // One tank, one healer, one damage dealer at the guild's level cap.
    uint8 const level = LevelCap(guildId);
    for (int8 role : { int8(UNIT_ROLE_TANK), int8(UNIT_ROLE_HEALER), int8(UNIT_ROLE_DAMAGE) })
    {
        UnitTemplate const* tmpl = PickTemplate(role);
        if (!tmpl)
            continue;
        GuildUnit u = RollUnit(guildId, *tmpl, UNIT_QUALITY_UNCOMMON, level, units);
        SaveUnit(u);
        units.push_back(std::move(u));
    }

    CharacterDatabase.Execute("UPDATE mod_gspe_progress SET starter_units = 1 WHERE guildid = {}", guildId);
}

void UnitMgr::RefreshCandidates(uint32 guildId, std::vector<GuildUnit>& units, bool force)
{
    uint32 const now = uint32(time(nullptr));
    bool const expired = std::any_of(units.begin(), units.end(), [now](GuildUnit const& u)
        { return u.status == UNIT_STATUS_CANDIDATE && u.expires <= now; });
    bool const none = std::none_of(units.begin(), units.end(), [](GuildUnit const& u)
        { return u.status == UNIT_STATUS_CANDIDATE; });

    // Candidates are replaced as a set once a day; recruiting one leaves fewer until then.
    if (!force && !expired && !none)
        return;

    for (GuildUnit const& u : units)
        if (u.status == UNIT_STATUS_CANDIDATE)
            DeleteUnit(u.id);
    std::erase_if(units, [](GuildUnit const& u) { return u.status == UNIT_STATUS_CANDIDATE; });

    uint8 const cap = LevelCap(guildId);
    for (uint32 i = 0; i < sGspeConfig->recruitCandidates; ++i)
    {
        UnitTemplate const* tmpl = PickTemplate(-1);
        if (!tmpl)
            break;

        uint8 const quality = RollQuality();
        uint8 const level = uint8(std::max<int32>(1, int32(cap) - int32(urand(0, 2))));
        GuildUnit u = RollUnit(guildId, *tmpl, quality, level, units);
        u.status = UNIT_STATUS_CANDIDATE;
        u.cost = RecruitCost(quality);
        u.expires = now + CANDIDATE_LIFETIME;
        SaveUnit(u);
        units.push_back(std::move(u));
    }
}

void UnitMgr::RerollCandidates(uint32 guildId)
{
    RefreshCandidates(guildId, GetUnits(guildId), true);
}

bool UnitMgr::CheckRequest(Player* player)
{
    if (!sGspeConfig->enable || !sGspeConfig->unitsEnable)
    {
        GspeAddonComm::Send(player, "UB\t0\t0\t0\t0\t0\t2\t0\t0\t0");
        GspeAddonComm::Send(player, "UE");
        return false;
    }
    if (!player->GetGuildId())
    {
        GspeAddonComm::Send(player, "UB\t0\t0\t0\t0\t0\t1\t0\t0\t0");
        GspeAddonComm::Send(player, "UE");
        return false;
    }
    return true;
}

void UnitMgr::SendTemplates(Player* player)
{
    // UT\tid\tkind\trole\tclass\ticon\tname\tabilities
    for (UnitTemplate const& t : _templates)
    {
        std::string abilities;
        for (uint8 a : t.abilities)
            abilities += (abilities.empty() ? "" : ",") + std::to_string(a);
        GspeAddonComm::Send(player, Acore::StringFormat("UT\t{}\t{}\t{}\t{}\t{}\t{}\t{}",
            t.id, uint32(t.kind), uint32(t.role), uint32(t.classId),
            GspeAddonComm::Sanitize(t.icon, 64), GspeAddonComm::Sanitize(t.name, 48), abilities));
    }
    GspeAddonComm::Send(player, "UTE");
}

void UnitMgr::SendUnitLine(Player* player, GuildUnit const& u)
{
    // U\tid\ttemplate\trace\tgender\tquality\tlevel\txp\txpNext\titemLevel\ta1\ta2\tt1\tt2\tstatus\tcost\tvitality\tname
    GspeAddonComm::Send(player, Acore::StringFormat("U\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}",
        u.id, u.templateId, uint32(u.race), uint32(u.gender), uint32(u.quality), uint32(u.level), u.xp,
        XpForNextLevel(u.level), u.itemLevel, uint32(u.abilities[0]), uint32(u.abilities[1]),
        uint32(u.traits[0]), uint32(u.traits[1]), uint32(u.status), u.cost, uint32(u.vitality),
        GspeAddonComm::Sanitize(u.name, 48)));
}

void UnitMgr::SendUnits(Player* player)
{
    if (!CheckRequest(player))
        return;

    uint32 const guildId = player->GetGuildId();
    uint8 const guildLevel = sGuildProgressMgr->GetLevel(guildId); // also creates the progress row
    std::vector<GuildUnit>& units = GetUnits(guildId);
    EnsureStarterUnits(guildId, units);
    RefreshCandidates(guildId, units, false);

    uint32 const now = uint32(time(nullptr));
    uint32 unitCount = 0, troopCount = 0, candidateCount = 0, candidatesExpireIn = 0;
    for (GuildUnit const& u : units)
    {
        if (u.status == UNIT_STATUS_CANDIDATE)
        {
            ++candidateCount;
            candidatesExpireIn = u.expires > now ? u.expires - now : 0;
        }
        else if (IsTroop(u))
            ++troopCount;
        else
            ++unitCount;
    }

    // UB\tunits\tmaxUnits\tlevelCap\tcandidates\tcandidatesExpireIn\tstatus\ttroops\tmaxTroops\ttroopCost
    GspeAddonComm::Send(player, Acore::StringFormat("UB\t{}\t{}\t{}\t{}\t{}\t0\t{}\t{}\t{}",
        unitCount, GspePerks::UnitSlots(guildLevel), uint32(LevelCap(guildId)),
        candidateCount, candidatesExpireIn, troopCount, GspePerks::TroopSlots(guildLevel), sGspeConfig->troopCost));
    for (GuildUnit const& u : units)
        SendUnitLine(player, u);
    GspeAddonComm::Send(player, "UE");
}

void UnitMgr::HandleRecruit(Player* player, uint32 candidateId)
{
    if (!CheckRequest(player))
        return;

    uint32 const guildId = player->GetGuildId();
    std::vector<GuildUnit>& units = GetUnits(guildId);
    GuildUnit* candidate = FindUnit(guildId, candidateId);
    if (!candidate || candidate->status != UNIT_STATUS_CANDIDATE || candidate->expires <= uint32(time(nullptr)))
    {
        GspeAddonComm::SendError(player, "That recruit is no longer available.");
        SendUnits(player);
        return;
    }

    std::size_t const unitCount = std::count_if(units.begin(), units.end(),
        [this](GuildUnit const& u) { return u.status != UNIT_STATUS_CANDIDATE && !IsTroop(u); });
    if (unitCount >= GspePerks::UnitSlots(sGuildProgressMgr->GetLevel(guildId)))
    {
        GspeAddonComm::SendError(player, "Your guild has no room for another unit.");
        return;
    }

    if (!sGuildProgressMgr->SpendSupplies(guildId, candidate->cost))
    {
        GspeAddonComm::SendError(player, Acore::StringFormat("Recruiting costs {} guild supplies.", candidate->cost));
        return;
    }

    candidate->status = UNIT_STATUS_IDLE;
    candidate->cost = 0;
    candidate->expires = 0;
    SaveUnit(*candidate);

    GspeAddonComm::Send(player, Acore::StringFormat("RECRUITED\t{}", candidateId));
    SendUnits(player);
}

void UnitMgr::HandleDismiss(Player* player, uint32 unitId)
{
    if (!CheckRequest(player))
        return;

    uint32 const guildId = player->GetGuildId();
    GuildUnit* unit = FindUnit(guildId, unitId);
    if (!unit || unit->status == UNIT_STATUS_CANDIDATE)
        return;

    if (unit->status == UNIT_STATUS_ON_MISSION)
    {
        GspeAddonComm::SendError(player, "That unit is away on a mission.");
        return;
    }

    RemoveUnit(guildId, unitId);
    SendUnits(player);
}

void UnitMgr::HandleTrainTroop(Player* player, uint16 templateId)
{
    if (!CheckRequest(player))
        return;

    UnitTemplate const* tmpl = GetTemplate(templateId);
    if (!tmpl || tmpl->kind != UNIT_KIND_TROOP || tmpl->abilities.empty())
        return;

    uint32 const guildId = player->GetGuildId();
    std::vector<GuildUnit>& units = GetUnits(guildId);
    std::size_t const troops = std::count_if(units.begin(), units.end(), [this](GuildUnit const& u) { return IsTroop(u); });
    if (troops >= GspePerks::TroopSlots(sGuildProgressMgr->GetLevel(guildId)))
    {
        GspeAddonComm::SendError(player, "Your guild has no room for more troops.");
        return;
    }

    if (!sGuildProgressMgr->SpendSupplies(guildId, sGspeConfig->troopCost))
    {
        GspeAddonComm::SendError(player, Acore::StringFormat("Training troops costs {} guild supplies.", sGspeConfig->troopCost));
        return;
    }

    uint8 const level = LevelCap(guildId);
    GuildUnit u;
    u.id = _nextId++;
    u.guildId = guildId;
    u.templateId = tmpl->id;
    u.name = tmpl->name;
    u.race = tmpl->races.front();
    u.quality = UNIT_QUALITY_UNCOMMON;
    u.level = level;
    u.itemLevel = ItemLevelForLevel(level);
    u.abilities[0] = tmpl->abilities.front();
    u.vitality = TROOP_VITALITY;
    SaveUnit(u);
    units.push_back(std::move(u));

    GspeAddonComm::Send(player, "RECRUITED\t0");
    SendUnits(player);
}
