/*
 * mod-guild-expansion: daily guild contracts.
 */

#include "GspeContracts.h"
#include "GspeAddonComm.h"
#include "GspeAdvancement.h"
#include "GspeConfig.h"
#include "GspeItems.h"
#include "GspeMissions.h"
#include "GspeProgress.h"
#include "GspeWorkOrders.h"

#include "Battleground.h"
#include "Chat.h"
#include "Containers.h"
#include "Creature.h"
#include "DatabaseEnv.h"
#include "Formulas.h"
#include "GameObject.h"
#include "Group.h"
#include "Log.h"
#include "Map.h"
#include "ObjectAccessor.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "QuestDef.h"
#include "Random.h"
#include "StringFormat.h"

#include <algorithm>
#include <cmath>

namespace
{
// Contract kinds that share a family are never offered on the same day.
uint8 FamilyOf(uint8 kind)
{
    return kind == CONTRACT_BG_WIN ? uint8(CONTRACT_BG_COMPLETE) : kind;
}

// Creature types offered by "Slay N <type>" contracts, with their plural names.
struct SlayType
{
    uint8 type;
    char const* plural;
};

constexpr SlayType SLAY_TYPES[] =
{
    { CREATURE_TYPE_BEAST,      "Beasts" },
    { CREATURE_TYPE_DRAGONKIN,  "Dragonkin" },
    { CREATURE_TYPE_DEMON,      "Demons" },
    { CREATURE_TYPE_ELEMENTAL,  "Elementals" },
    { CREATURE_TYPE_GIANT,      "Giants" },
    { CREATURE_TYPE_UNDEAD,     "Undead" },
    { CREATURE_TYPE_HUMANOID,   "Humanoids" },
    { CREATURE_TYPE_MECHANICAL, "Mechanicals" },
};

char const* SlayTypeName(uint32 type)
{
    for (SlayType const& t : SLAY_TYPES)
        if (t.type == type)
            return t.plural;
    return "Enemies";
}

constexpr uint16 GATHER_SKILLS[] = { SKILL_HERBALISM, SKILL_MINING, SKILL_SKINNING };

// A creature type needs this many spawns around the character's level to be offered.
constexpr uint32 MIN_TYPE_SPAWNS = 40;
constexpr uint32 MIN_ELITE_SPAWNS = 20;

// Bonus cache consumables, best first is picked by required level.
constexpr uint32 HEALING_POTIONS[] = { 118, 858, 929, 1710, 3928, 13446, 22829, 33447 };
constexpr uint32 MANA_POTIONS[] = { 2455, 3385, 3827, 6149, 13443, 13444, 22832, 33448 };

template <std::size_t N>
uint32 BestForLevel(uint32 const (&items)[N], uint8 level)
{
    uint32 best = 0;
    uint32 bestLevel = 0;
    for (uint32 entry : items)
        if (ItemTemplate const* t = sObjectMgr->GetItemTemplate(entry))
            if (t->RequiredLevel <= level && (!best || t->RequiredLevel >= bestLevel))
            {
                best = entry;
                bestLevel = t->RequiredLevel;
            }
    return best;
}

// Fishing pools keep the same guid for every catch; a new catch takes a few seconds.
constexpr time_t FISH_LOOT_DEDUPE = 3;
} // namespace

ContractMgr* ContractMgr::instance()
{
    static ContractMgr inst;
    return &inst;
}

void ContractMgr::BuildCatalog()
{
    for (auto& row : _normalSpawns)
        row.fill(0);
    _eliteSpawns.fill(0);

    // Normal creatures on the open-world maps; elites anywhere, since dungeons count too.
    QueryResult r = WorldDatabase.Query(
        "SELECT ct.type, ct.`rank`, ct.minlevel, ct.maxlevel, c.map IN (0, 1, 530, 571), COUNT(*) "
        "FROM creature c JOIN creature_template ct ON ct.entry = c.id "
        "WHERE ct.npcflag = 0 AND ct.type BETWEEN 1 AND 10 AND ct.type <> 8 "
        "GROUP BY ct.type, ct.`rank`, ct.minlevel, ct.maxlevel, c.map IN (0, 1, 530, 571)");
    if (!r)
        return;

    do
    {
        Field* f = r->Fetch();
        uint8 const type = f[0].Get<uint8>();
        uint8 const rank = f[1].Get<uint8>();
        uint8 const minLevel = std::clamp<uint8>(f[2].Get<uint8>(), 1, MAX_LEVEL);
        uint8 const maxLevel = std::clamp<uint8>(f[3].Get<uint8>(), minLevel, MAX_LEVEL);
        bool const openWorld = f[4].Get<bool>();
        uint32 const count = uint32(f[5].Get<uint64>());
        if (type >= CREATURE_TYPES)
            continue;

        for (uint8 level = minLevel; level <= maxLevel; ++level)
        {
            if (rank == CREATURE_ELITE_ELITE || rank == CREATURE_ELITE_RAREELITE)
                _eliteSpawns[level] += count;
            else if ((rank == CREATURE_ELITE_NORMAL || rank == CREATURE_ELITE_RARE) && openWorld)
                _normalSpawns[type][level] += count;
        }
    } while (r->NextRow());

    LOG_INFO("module", "GuildExpansion: contracts ready.");
}

bool ContractMgr::CheckRequest(Player* player)
{
    if (!sGspeConfig->enable || !sGspeConfig->contractsEnable)
    {
        GspeAddonComm::Send(player, "CB\t0\t2\t0\t0\t0\t0\t0");
        GspeAddonComm::Send(player, "CE");
        return false;
    }
    if (!player->GetGuildId())
    {
        GspeAddonComm::Send(player, "CB\t0\t1\t0\t0\t0\t0\t0");
        GspeAddonComm::Send(player, "CE");
        return false;
    }
    return true;
}

ContractMgr::CharacterContracts* ContractMgr::Get(Player* player)
{
    if (!player || !sGspeConfig->enable || !sGspeConfig->contractsEnable || !player->GetGuildId()
        || GuildProgressMgr::IsHeadless(player))
        return nullptr;

    ObjectGuid::LowType const guid = player->GetGUID().GetCounter();
    auto itr = _characters.find(guid);
    if (itr == _characters.end())
    {
        CharacterContracts& loaded = _characters[guid];
        if (QueryResult r = CharacterDatabase.Query(
                "SELECT day, rerolls, extra_rerolls, bonus_paid FROM mod_gspe_contract_day WHERE guid = {}", guid))
        {
            Field* f = r->Fetch();
            loaded.day = f[0].Get<uint32>();
            loaded.rerollsUsed = f[1].Get<uint8>();
            loaded.extraRerolls = f[2].Get<uint8>();
            loaded.bonusPaid = f[3].Get<bool>();
        }
        if (QueryResult r = CharacterDatabase.Query(
                "SELECT slot, kind, target, needed, progress, level, gold, supplies, guild_xp, done "
                "FROM mod_gspe_contract WHERE guid = {} ORDER BY slot", guid))
        {
            do
            {
                Field* f = r->Fetch();
                Contract c;
                c.slot = f[0].Get<uint8>();
                c.kind = f[1].Get<uint8>();
                c.target = f[2].Get<uint32>();
                c.needed = std::max<uint16>(1, f[3].Get<uint16>());
                c.progress = f[4].Get<uint16>();
                c.level = f[5].Get<uint8>();
                c.gold = f[6].Get<uint32>();
                c.supplies = f[7].Get<uint32>();
                c.guildXp = f[8].Get<uint32>();
                c.done = f[9].Get<bool>();
                loaded.contracts.push_back(c);
            } while (r->NextRow());
        }
        itr = _characters.find(guid);
    }

    CharacterContracts& cc = itr->second;
    if (cc.day != GspeItems::NextDailyReset())
        Roll(player, cc);
    return &cc;
}

void ContractMgr::Roll(Player* player, CharacterContracts& cc)
{
    ObjectGuid::LowType const guid = player->GetGUID().GetCounter();
    CharacterDatabase.Execute("DELETE FROM mod_gspe_contract WHERE guid = {}", guid);

    cc.day = GspeItems::NextDailyReset();
    cc.contracts.clear();
    cc.rerollsUsed = 0;
    cc.extraRerolls = 0;
    cc.bonusPaid = false;

    for (uint8 slot = 0; slot < sGspeConfig->contractCount; ++slot)
    {
        Contract c;
        if (!Generate(player, cc, c))
            break;
        c.slot = slot;
        cc.contracts.push_back(c);
        Save(player, c);
    }
    SaveDay(player, cc);
}

bool ContractMgr::Generate(Player* player, CharacterContracts const& cc, Contract& out)
{
    struct Option
    {
        uint8 kind;
        uint32 target;
        uint32 weight;
    };

    uint8 const level = uint8(std::min<uint32>(player->GetLevel(), MAX_LEVEL));
    uint8 const low = level > 4 ? level - 4 : 1;
    uint8 const high = std::min<uint8>(level + 1, MAX_LEVEL);
    std::vector<Option> options;

    // Creature types weighted by spawns around the level; the square root keeps humanoids
    // and beasts from crowding out the rest.
    for (SlayType const& t : SLAY_TYPES)
    {
        uint32 spawns = 0;
        for (uint8 l = low; l <= high; ++l)
            spawns += _normalSpawns[t.type][l];
        if (spawns >= MIN_TYPE_SPAWNS)
            options.push_back({ CONTRACT_SLAY_TYPE, t.type, uint32(std::sqrt(double(spawns))) });
    }
    // Spread the slay-type share (300) over the types found.
    uint32 typeWeightSum = 0;
    for (Option const& o : options)
        typeWeightSum += o.weight;
    for (Option& o : options)
        o.weight = std::max<uint32>(1, o.weight * 30 * 10 / std::max<uint32>(1, typeWeightSum));

    uint32 eliteSpawns = 0;
    for (uint8 l = low; l <= high; ++l)
        eliteSpawns += _eliteSpawns[l];
    if (level >= 8 && eliteSpawns >= MIN_ELITE_SPAWNS)
        options.push_back({ CONTRACT_SLAY_ELITE, 0, 150 });

    options.push_back({ CONTRACT_QUESTS, 0, 200 });

    std::vector<uint16> gather;
    for (uint16 skill : GATHER_SKILLS)
        if (player->HasSkill(skill))
            gather.push_back(skill);
    if (!gather.empty())
        options.push_back({ CONTRACT_GATHER, Acore::Containers::SelectRandomContainerElement(gather), 200 });

    if (player->HasSkill(SKILL_FISHING))
        options.push_back({ CONTRACT_FISH, 0, 100 });
    if (sGspeConfig->contractDungeonBosses && level >= 15)
        options.push_back({ CONTRACT_DUNGEON_BOSS, 0, 120 });
    if (sGspeConfig->contractBattlegrounds && level >= 10)
    {
        options.push_back({ CONTRACT_BG_COMPLETE, 0, 50 });
        options.push_back({ CONTRACT_BG_WIN, 0, 30 });
        options.push_back({ CONTRACT_HONOR_KILLS, 0, 60 });
    }

    std::erase_if(options, [&cc](Option const& o)
    {
        return std::any_of(cc.contracts.begin(), cc.contracts.end(),
            [&o](Contract const& c) { return FamilyOf(c.kind) == FamilyOf(o.kind); });
    });

    uint32 total = 0;
    for (Option const& o : options)
        total += o.weight;
    if (!total)
        return false;

    uint32 roll = urand(1, total);
    Option const* pick = &options.front();
    for (Option const& o : options)
    {
        if (roll <= o.weight)
        {
            pick = &o;
            break;
        }
        roll -= o.weight;
    }

    out = Contract{};
    out.kind = pick->kind;
    out.target = pick->target;
    switch (out.kind)
    {
        case CONTRACT_SLAY_TYPE:    out.needed = uint16(level < 10 ? urand(10, 15) : urand(20, 30)); break;
        case CONTRACT_SLAY_ELITE:   out.needed = uint16(level < 20 ? urand(4, 6) : urand(6, 10)); break;
        case CONTRACT_QUESTS:       out.needed = uint16(urand(4, 6)); break;
        case CONTRACT_GATHER:       out.needed = uint16(urand(10, 15)); break;
        case CONTRACT_FISH:         out.needed = uint16(urand(12, 20)); break;
        case CONTRACT_DUNGEON_BOSS: out.needed = uint16(urand(2, 3)); break;
        case CONTRACT_HONOR_KILLS:  out.needed = uint16(urand(10, 20)); break;
        default:                    out.needed = 1; break;
    }
    SetRewards(player, out);
    return true;
}

void ContractMgr::SetRewards(Player* player, Contract& c)
{
    GspeConfig const* cfg = sGspeConfig;
    uint32 const level = player->GetLevel();
    c.level = uint8(level);
    c.supplies = uint32(cfg->contractSuppliesBase + cfg->contractSuppliesPerLevel * float(level));
    c.guildXp = cfg->contractGuildXpPerLevel * level;
    c.gold = uint32(cfg->contractGoldPerLevelSquared * float(level * level));
}

void ContractMgr::Save(Player* player, Contract const& c)
{
    CharacterDatabase.Execute(
        "REPLACE INTO mod_gspe_contract (guid, slot, kind, target, needed, progress, level, gold, supplies, guild_xp, done) "
        "VALUES ({}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {})",
        player->GetGUID().GetCounter(), uint32(c.slot), uint32(c.kind), c.target, c.needed, c.progress,
        uint32(c.level), c.gold, c.supplies, c.guildXp, c.done ? 1 : 0);
}

void ContractMgr::SaveDay(Player* player, CharacterContracts const& cc)
{
    CharacterDatabase.Execute(
        "REPLACE INTO mod_gspe_contract_day (guid, day, rerolls, extra_rerolls, bonus_paid) VALUES ({}, {}, {}, {}, {})",
        player->GetGUID().GetCounter(), cc.day, uint32(cc.rerollsUsed), uint32(cc.extraRerolls), cc.bonusPaid ? 1 : 0);
}

std::string ContractMgr::Title(Contract const& c) const
{
    switch (c.kind)
    {
        case CONTRACT_SLAY_TYPE:  return Acore::StringFormat("Slay {} {}", c.needed, SlayTypeName(c.target));
        case CONTRACT_SLAY_ELITE: return Acore::StringFormat("Slay {} elite enemies", c.needed);
        case CONTRACT_QUESTS:     return Acore::StringFormat("Complete {} quests", c.needed);
        case CONTRACT_GATHER:
            switch (c.target)
            {
                case SKILL_HERBALISM: return Acore::StringFormat("Gather from {} herb nodes", c.needed);
                case SKILL_MINING:    return Acore::StringFormat("Mine {} ore deposits", c.needed);
                default:              return Acore::StringFormat("Skin {} creatures", c.needed);
            }
        case CONTRACT_FISH:       return Acore::StringFormat("Catch {} fish", c.needed);
        case CONTRACT_DUNGEON_BOSS:
            return c.needed == 1 ? std::string("Defeat a dungeon boss")
                                 : Acore::StringFormat("Defeat {} dungeon bosses", c.needed);
        case CONTRACT_BG_COMPLETE:
            return c.needed == 1 ? std::string("Complete a battleground")
                                 : Acore::StringFormat("Complete {} battlegrounds", c.needed);
        case CONTRACT_BG_WIN:
            return c.needed == 1 ? std::string("Win a battleground")
                                 : Acore::StringFormat("Win {} battlegrounds", c.needed);
        case CONTRACT_HONOR_KILLS: return Acore::StringFormat("Earn {} honorable kills", c.needed);
        default:                   return "Contract";
    }
}

std::string ContractMgr::Label(Contract const& c) const
{
    switch (c.kind)
    {
        case CONTRACT_SLAY_TYPE:  return Acore::StringFormat("{} slain", SlayTypeName(c.target));
        case CONTRACT_SLAY_ELITE: return "Elite enemies slain";
        case CONTRACT_QUESTS:     return "Quests completed";
        case CONTRACT_GATHER:
            switch (c.target)
            {
                case SKILL_HERBALISM: return "Herb nodes gathered";
                case SKILL_MINING:    return "Ore deposits mined";
                default:              return "Creatures skinned";
            }
        case CONTRACT_FISH:          return "Fish caught";
        case CONTRACT_DUNGEON_BOSS:  return "Dungeon bosses defeated";
        case CONTRACT_BG_COMPLETE:   return "Battlegrounds completed";
        case CONTRACT_BG_WIN:        return "Battlegrounds won";
        case CONTRACT_HONOR_KILLS:   return "Honorable kills";
        default:                     return "Progress";
    }
}

void ContractMgr::Advance(Player* player, uint8 kind, uint32 target, uint16 amount)
{
    CharacterContracts* cc = Get(player);
    if (!cc)
        return;

    for (Contract& c : cc->contracts)
    {
        if (c.done || c.kind != kind || c.target != target)
            continue;

        c.progress = uint16(std::min<uint32>(c.needed, uint32(c.progress) + amount));
        if (c.progress >= c.needed)
        {
            Complete(player, *cc, c);
            continue;
        }

        Save(player, c);
        GspeAddonComm::Send(player, Acore::StringFormat("CP\t{}\t{}\t{}\t{}",
            uint32(c.slot), c.progress, c.needed, GspeAddonComm::Sanitize(Label(c), 60)));
    }
}

void ContractMgr::Complete(Player* player, CharacterContracts& cc, Contract& c)
{
    c.done = true;
    c.progress = c.needed;
    Save(player, c);

    uint32 const gold = uint32(float(c.gold) * sAdvancementMgr->GoldMultiplier(player->GetGuildId()));
    player->ModifyMoney(int32(std::min<uint32>(gold, uint32(INT32_MAX))));
    if (uint32 const guildId = player->GetGuildId())
    {
        sGuildProgressMgr->AddSupplies(guildId, c.supplies);
        sGuildProgressMgr->AddGuildXP(guildId, c.guildXp, player);
    }

    std::string const title = Title(c);
    ChatHandler(player->GetSession()).SendSysMessage(Acore::StringFormat(
        "|cff00ccffContract complete:|r {} - {}g {}s {}c, {} guild XP, {} guild supplies.",
        title, gold / 10000, (gold / 100) % 100, gold % 100, c.guildXp, c.supplies));
    GspeAddonComm::Send(player, Acore::StringFormat("CDONE\t{}\t{}\t{}\t{}\t{}",
        uint32(c.slot), gold, c.supplies, c.guildXp, GspeAddonComm::Sanitize(title, 80)));

    if (!cc.bonusPaid && !cc.contracts.empty()
        && std::all_of(cc.contracts.begin(), cc.contracts.end(), [](Contract const& x) { return x.done; }))
        PayBonus(player, cc);

    SendContracts(player);
}

void ContractMgr::PayBonus(Player* player, CharacterContracts& cc)
{
    cc.bonusPaid = true;
    SaveDay(player, cc);

    GspeConfig const* cfg = sGspeConfig;
    uint8 const level = uint8(player->GetLevel());
    uint32 const supplies = uint32(cfg->contractBonusSuppliesBase + cfg->contractBonusSuppliesPerLevel * float(level));
    if (uint32 const guildId = player->GetGuildId())
        sGuildProgressMgr->AddSupplies(guildId, supplies);

    // One extra item: consumables (60%), materials (30%) or gear (10%), falling back in that order.
    uint32 item = 0;
    uint32 count = 0;
    uint32 const roll = urand(1, 100);
    if (roll > 90)
    {
        item = sMissionMgr->RollGear(player, level, ITEM_QUALITY_RARE);
        count = 1;
    }
    if (!item && roll > 60)
    {
        std::vector<uint16> skills = { 0 };   // 0 = cloth
        for (uint16 skill : GATHER_SKILLS)
            if (player->HasSkill(skill))
                skills.push_back(skill);
        item = sWorkOrderMgr->RandomMaterial(level, Acore::Containers::SelectRandomContainerElement(skills));
        if (ItemTemplate const* t = item ? sObjectMgr->GetItemTemplate(item) : nullptr)
            count = std::clamp<uint32>(urand(5, 10), 1, std::max<uint32>(1, t->GetMaxStackSize()));
    }
    if (!item)
    {
        bool const mana = player->getPowerType() == POWER_MANA && urand(0, 1);
        item = mana ? BestForLevel(MANA_POTIONS, level) : BestForLevel(HEALING_POTIONS, level);
        count = 5;
    }

    if (item)
        GspeItems::GiveItem(player, item, count, "Guild contract rewards");

    ChatHandler(player->GetSession()).SendSysMessage(Acore::StringFormat(
        "|cff00ccffAll of today's contracts complete!|r Bonus: {} guild supplies.", supplies));
    GspeAddonComm::Send(player, Acore::StringFormat("CBONUS\t{}\t{}\t{}", supplies, item, count));
}

void ContractMgr::SendLine(Player* player, Contract const& c)
{
    // C\tslot\tkind\ttarget\tneeded\tprogress\tdone\tgold\tsupplies\tguildXp\ttitle\tlabel
    GspeAddonComm::Send(player, Acore::StringFormat("C\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}",
        uint32(c.slot), uint32(c.kind), c.target, c.needed, c.progress, c.done ? 1 : 0, c.gold, c.supplies, c.guildXp,
        GspeAddonComm::Sanitize(Title(c), 80), GspeAddonComm::Sanitize(Label(c), 60)));
}

void ContractMgr::SendContracts(Player* player)
{
    if (!CheckRequest(player))
        return;

    CharacterContracts* cc = Get(player);
    if (!cc)
    {
        GspeAddonComm::Send(player, "CB\t0\t2\t0\t0\t0\t0\t0");
        GspeAddonComm::Send(player, "CE");
        return;
    }

    GspeConfig const* cfg = sGspeConfig;
    uint32 const now = uint32(time(nullptr));
    uint32 const rerollsLeft = cfg->contractFreeRerolls + cc->extraRerolls > cc->rerollsUsed
        ? cfg->contractFreeRerolls + cc->extraRerolls - cc->rerollsUsed : 0;
    uint32 const bonusSupplies = uint32(cfg->contractBonusSuppliesBase + cfg->contractBonusSuppliesPerLevel * float(player->GetLevel()));
    uint32 const doneCount = uint32(std::count_if(cc->contracts.begin(), cc->contracts.end(), [](Contract const& c) { return c.done; }));

    // CB\tcount\tstatus\tresetsIn\trerollsLeft\tbonusPaid\tbonusSupplies\tdone
    GspeAddonComm::Send(player, Acore::StringFormat("CB\t{}\t0\t{}\t{}\t{}\t{}\t{}",
        cc->contracts.size(), cc->day > now ? cc->day - now : 0, rerollsLeft, cc->bonusPaid ? 1 : 0,
        bonusSupplies, doneCount));
    for (Contract const& c : cc->contracts)
        SendLine(player, c);
    GspeAddonComm::Send(player, "CE");
}

void ContractMgr::HandleReroll(Player* player, uint8 slot)
{
    if (!CheckRequest(player))
        return;

    CharacterContracts* cc = Get(player);
    if (!cc)
        return;

    auto itr = std::find_if(cc->contracts.begin(), cc->contracts.end(), [slot](Contract const& c) { return c.slot == slot; });
    if (itr == cc->contracts.end() || itr->done)
    {
        SendContracts(player);
        return;
    }

    if (cc->rerollsUsed >= sGspeConfig->contractFreeRerolls + cc->extraRerolls)
    {
        GspeAddonComm::SendError(player, "No rerolls left today. The quartermaster sells more.");
        return;
    }

    // The contract being replaced is still in the list, so the new one is of another kind.
    Contract c;
    if (!Generate(player, *cc, c))
    {
        GspeAddonComm::SendError(player, "No other contract is available right now.");
        return;
    }

    c.slot = slot;
    *itr = c;
    ++cc->rerollsUsed;
    Save(player, c);
    SaveDay(player, *cc);
    SendContracts(player);
}

void ContractMgr::AddReroll(Player* player)
{
    if (CharacterContracts* cc = Get(player))
    {
        cc->extraRerolls = uint8(std::min<uint32>(cc->extraRerolls + 1, 255));
        SaveDay(player, *cc);
    }
}

void ContractMgr::ResetContracts(Player* player)
{
    if (CharacterContracts* cc = Get(player))
        Roll(player, *cc);
    SendContracts(player);
}

void ContractMgr::FinishContract(Player* player, uint8 slot)
{
    CharacterContracts* cc = Get(player);
    if (!cc)
        return;
    for (Contract& c : cc->contracts)
        if (c.slot == slot && !c.done)
            Complete(player, *cc, c);
}

void ContractMgr::OnLogout(Player* player)
{
    ObjectGuid::LowType const guid = player->GetGUID().GetCounter();
    _characters.erase(guid);
    _lastFishLoot.erase(guid);
}

void ContractMgr::OnKillCredit(Player* player, Creature* creature)
{
    if (!player || !creature || !sGspeConfig->contractsEnable)
        return;

    CreatureTemplate const* info = creature->GetCreatureTemplate();
    bool const boss = creature->IsDungeonBoss() && creature->GetMap() && creature->GetMap()->IsDungeon();

    auto credit = [&](Player* p)
    {
        if (!p->GetGuildId() || GuildProgressMgr::IsHeadless(p) || !p->isHonorOrXPTarget(creature))
            return;
        if (info && info->type != CREATURE_TYPE_CRITTER)
            Advance(p, CONTRACT_SLAY_TYPE, info->type);
        if (creature->isElite())
            Advance(p, CONTRACT_SLAY_ELITE, 0);
        if (boss)
            Advance(p, CONTRACT_DUNGEON_BOSS, 0);
    };

    // Kill credit goes to one member of a group (the loot recipient), so share it with the
    // guild members nearby; otherwise a bot in the party could take every kill.
    if (Group* group = player->GetGroup())
    {
        for (GroupReference* ref = group->GetFirstMember(); ref; ref = ref->next())
            if (Player* member = ref->GetSource())
                if (member == player || member->IsAtGroupRewardDistance(creature))
                    credit(member);
    }
    else
        credit(player);
}

void ContractMgr::OnQuestRewarded(Player* player, Quest const* quest)
{
    if (!quest || !sGspeConfig->contractsEnable)
        return;

    // Quests that scale to the character (level -1) always count; others only when not gray.
    int32 const questLevel = quest->GetQuestLevel();
    if (questLevel > 0 && uint32(questLevel) <= Acore::XP::GetGrayLevel(player->GetLevel()))
        return;

    Advance(player, CONTRACT_QUESTS, 0);
}

void ContractMgr::OnGather(Player* player, uint32 skillId)
{
    // Prospecting and milling go through the same hook; only real gathering counts.
    if (sGspeConfig->contractsEnable
        && (skillId == SKILL_HERBALISM || skillId == SKILL_MINING || skillId == SKILL_SKINNING))
        Advance(player, CONTRACT_GATHER, skillId);
}

void ContractMgr::OnLoot(Player* player, ObjectGuid lootGuid)
{
    if (!sGspeConfig->contractsEnable || !lootGuid.IsGameObject())
        return;

    GameObject* go = ObjectAccessor::GetGameObject(*player, lootGuid);
    if (!go || (go->GetGoType() != GAMEOBJECT_TYPE_FISHINGNODE && go->GetGoType() != GAMEOBJECT_TYPE_FISHINGHOLE))
        return;

    // One catch can hold several items, and a fishing pool keeps its guid between catches.
    time_t const now = time(nullptr);
    FishLoot& last = _lastFishLoot[player->GetGUID().GetCounter()];
    if (last.guid == lootGuid && now - last.at < FISH_LOOT_DEDUPE)
        return;
    last = { lootGuid, now };

    Advance(player, CONTRACT_FISH, 0);
}

void ContractMgr::OnHonorableKill(Player* player)
{
    if (sGspeConfig->contractsEnable)
        Advance(player, CONTRACT_HONOR_KILLS, 0);
}

void ContractMgr::OnBattlegroundEnd(Player* player, Battleground* bg, bool won)
{
    if (!player || !bg || bg->isArena() || !sGspeConfig->contractsEnable)
        return;

    Advance(player, CONTRACT_BG_COMPLETE, 0);
    if (won)
        Advance(player, CONTRACT_BG_WIN, 0);
}
