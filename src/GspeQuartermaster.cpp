/*
 * mod-guild-expansion: the guild quartermaster.
 */

#include "GspeQuartermaster.h"
#include "GspeAddonComm.h"
#include "GspeAdvancement.h"
#include "GspeConfig.h"
#include "GspeContracts.h"
#include "GspeItems.h"
#include "GspeMissions.h"
#include "GspeProgress.h"
#include "GspeUnits.h"
#include "GspeWorkOrders.h"

#include "CharacterCache.h"
#include "Containers.h"
#include "DatabaseEnv.h"
#include "Item.h"
#include "ItemEnchantmentMgr.h"
#include "Log.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "Random.h"
#include "SpellMgr.h"
#include "StringFormat.h"

#include <algorithm>
#include <unordered_set>

namespace
{
// Professions whose recipes can show up in the weekly stock.
constexpr uint32 RECIPE_SKILLS[] =
{
    SKILL_ALCHEMY, SKILL_BLACKSMITHING, SKILL_ENCHANTING, SKILL_ENGINEERING, SKILL_INSCRIPTION,
    SKILL_JEWELCRAFTING, SKILL_LEATHERWORKING, SKILL_TAILORING, SKILL_COOKING, SKILL_FIRST_AID,
};

// "Learn" spells that items use to teach the real spell in their next slot.
bool IsLearnWrapper(int32 spellId)
{
    return spellId == 483 || spellId == 55884;
}

// The spells an item teaches or casts, without the generic learning spells.
std::vector<uint32> ItemSpells(ItemTemplate const* proto)
{
    std::vector<uint32> out;
    if (!proto)
        return out;
    for (auto const& spell : proto->Spells)
        if (spell.SpellId > 0 && !IsLearnWrapper(spell.SpellId))
            out.push_back(uint32(spell.SpellId));
    return out;
}

uint32 WeeklyGearCost(uint32 quality)
{
    switch (quality)
    {
        case ITEM_QUALITY_EPIC: return 400;
        case ITEM_QUALITY_RARE: return 120;
        default:                return 40;
    }
}

uint32 RecipeCost(uint32 quality)
{
    switch (quality)
    {
        case ITEM_QUALITY_EPIC: return 500;
        case ITEM_QUALITY_RARE: return 200;
        default:                return 80;
    }
}

bool IsJunkName(std::string const& name)
{
    return name.find("Test") != std::string::npos || name.find("Deprecated") != std::string::npos
        || name.find("[PH]") != std::string::npos || name.find("OLD") != std::string::npos;
}
} // namespace

QuartermasterMgr* QuartermasterMgr::instance()
{
    static QuartermasterMgr inst;
    return &inst;
}

void QuartermasterMgr::Load()
{
    _stock.clear();
    if (QueryResult r = WorldDatabase.Query(
            "SELECT id, category, item, count, service, cost, guild_level, min_level, max_level, char_limit "
            "FROM mod_gspe_qm_stock ORDER BY category, id"))
    {
        do
        {
            Field* f = r->Fetch();
            QuartermasterRow row;
            row.id = f[0].Get<uint16>();
            row.category = f[1].Get<uint8>();
            row.item = f[2].Get<uint32>();
            row.count = std::max<uint16>(1, f[3].Get<uint16>());
            row.service = f[4].Get<uint8>();
            row.cost = f[5].Get<uint32>();
            row.guildLevel = f[6].Get<uint8>();
            row.minLevel = f[7].Get<uint8>();
            row.maxLevel = f[8].Get<uint8>();
            row.charLimit = f[9].Get<uint16>();

            if (row.service == QM_SERVICE_NONE && !sObjectMgr->GetItemTemplate(row.item))
            {
                LOG_ERROR("module", "GuildExpansion: quartermaster row {} sells unknown item {}, skipped.", row.id, row.item);
                continue;
            }
            _stock.push_back(row);
        } while (r->NextRow());
    }

    LoadWeeklyPools();
    LOG_INFO("module", "GuildExpansion: quartermaster ready ({} items and services; weekly pools: {} gear, {} recipes, "
        "{} materials, {} curiosities).", _stock.size(), _gearPool.size(), _recipePool.size(), _materials.size(), _curiosities.size());
}

void QuartermasterMgr::OnLogout(Player* player)
{
    _purchases.erase(player->GetGUID().GetCounter());
    _characterWeekly.erase(player->GetGUID().GetCounter());
}

uint32 QuartermasterMgr::Price(Player* player, uint32 cost)
{
    if (!cost)
        return 0;
    float const price = float(cost) * sAdvancementMgr->QuartermasterPriceMultiplier(player->GetGuildId());
    return std::max<uint32>(1, uint32(price + 0.5f));
}

bool QuartermasterMgr::CheckRequest(Player* player)
{
    if (!sGspeConfig->enable || !sGspeConfig->quartermasterEnable)
    {
        GspeAddonComm::Send(player, "QB\t2\t0\t0");
        GspeAddonComm::Send(player, "QE");
        return false;
    }
    if (!player->GetGuildId())
    {
        GspeAddonComm::Send(player, "QB\t1\t0\t0");
        GspeAddonComm::Send(player, "QE");
        return false;
    }
    return true;
}

QuartermasterRow const* QuartermasterMgr::FindRow(uint16 id) const
{
    auto itr = std::find_if(_stock.begin(), _stock.end(), [id](QuartermasterRow const& r) { return r.id == id; });
    return itr != _stock.end() ? &*itr : nullptr;
}

std::unordered_map<uint16, uint16>& QuartermasterMgr::Purchases(Player* player)
{
    ObjectGuid::LowType const guid = player->GetGUID().GetCounter();
    if (auto itr = _purchases.find(guid); itr != _purchases.end())
        return itr->second;

    std::unordered_map<uint16, uint16>& bought = _purchases[guid];
    if (QueryResult r = CharacterDatabase.Query("SELECT stock_id, count FROM mod_gspe_qm_purchase WHERE guid = {}", guid))
        do
            bought[r->Fetch()[0].Get<uint16>()] = r->Fetch()[1].Get<uint16>();
        while (r->NextRow());
    return bought;
}

bool QuartermasterMgr::ServiceAvailable(Player* player, uint8 service) const
{
    GspeConfig const* cfg = sGspeConfig;
    switch (service)
    {
        case QM_SERVICE_RECRUITS:      return cfg->unitsEnable;
        case QM_SERVICE_MISSION_BOARD: return cfg->missionsEnable;
        case QM_SERVICE_WORK_ORDER:    return cfg->workOrdersEnable && sWorkOrderMgr->HasWaitingOrder(player);
        case QM_SERVICE_CONTRACT:      return cfg->contractsEnable;
        default:                       return false;
    }
}

uint8 QuartermasterMgr::RowState(Player* player, QuartermasterRow const& row, uint8 guildLevel)
{
    if (guildLevel < row.guildLevel)
        return QM_ROW_LOCKED;
    if (row.service != QM_SERVICE_NONE)
        return ServiceAvailable(player, row.service) ? QM_ROW_OK : QM_ROW_UNAVAILABLE;

    ItemTemplate const* proto = sObjectMgr->GetItemTemplate(row.item);
    if (!proto || player->CanUseItem(proto) != EQUIP_ERR_OK)
        return QM_ROW_UNUSABLE;
    if (row.charLimit)
    {
        auto const& bought = Purchases(player);
        auto itr = bought.find(row.id);
        if (itr != bought.end() && itr->second >= row.charLimit)
            return QM_ROW_LIMIT;
    }
    return QM_ROW_OK;
}

void QuartermasterMgr::SendStock(Player* player)
{
    if (!CheckRequest(player))
        return;

    uint8 const guildLevel = sGuildProgressMgr->GetLevel(player->GetGuildId());
    uint8 const level = uint8(player->GetLevel());
    auto const& bought = Purchases(player);

    uint32 const now = uint32(time(nullptr));
    uint32 const week = GspeItems::NextWeeklyReset();
    GspeAddonComm::Send(player, Acore::StringFormat("QB\t0\t{}\t{}", uint32(guildLevel), week > now ? week - now : 0));
    for (QuartermasterRow const& row : _stock)
    {
        if (level < row.minLevel || level > row.maxLevel)
            continue;

        auto itr = bought.find(row.id);
        uint32 const boughtCount = itr != bought.end() ? itr->second : 0;
        // QT\tid\tcategory\titem\tcount\tservice\tcost\tguildLevel\tlimit\tbought\tstate
        GspeAddonComm::Send(player, Acore::StringFormat("QT\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}",
            row.id, uint32(row.category), row.item, row.count, uint32(row.service), Price(player, row.cost), uint32(row.guildLevel),
            row.charLimit, boughtCount, uint32(RowState(player, row, guildLevel))));
    }

    for (WeeklyOffer const& offer : CharacterWeekly(player).offers)
        SendWeeklyLine(player, offer);
    for (WeeklyOffer const& offer : GuildWeekly(player->GetGuildId()).offers)
        SendWeeklyLine(player, offer);
    GspeAddonComm::Send(player, "QE");
}

void QuartermasterMgr::HandleBuy(Player* player, uint16 rowId)
{
    if (!CheckRequest(player))
        return;

    QuartermasterRow const* row = FindRow(rowId);
    uint8 const level = uint8(player->GetLevel());
    if (!row || level < row->minLevel || level > row->maxLevel)
    {
        GspeAddonComm::SendError(player, "The quartermaster doesn't have that.");
        SendStock(player);
        return;
    }

    uint32 const guildId = player->GetGuildId();
    switch (RowState(player, *row, sGuildProgressMgr->GetLevel(guildId)))
    {
        case QM_ROW_OK:
            break;
        case QM_ROW_LOCKED:
            GspeAddonComm::SendError(player, Acore::StringFormat("Requires guild level {}.", uint32(row->guildLevel)));
            return;
        case QM_ROW_UNUSABLE:
            GspeAddonComm::SendError(player, "You can't use that item.");
            return;
        case QM_ROW_LIMIT:
            GspeAddonComm::SendError(player, "You already bought as many of those as you can.");
            return;
        default:
            GspeAddonComm::SendError(player, "There is nothing for that service to do right now.");
            return;
    }

    if (!sGuildProgressMgr->SpendSupplies(guildId, Price(player, row->cost)))
    {
        GspeAddonComm::SendError(player, "Your guild doesn't have enough supplies.");
        return;
    }

    if (row->service != QM_SERVICE_NONE)
        RunService(player, row->service);
    else
        GspeItems::GiveItem(player, row->item, row->count, "Guild quartermaster");

    if (row->charLimit)
    {
        uint16& count = Purchases(player)[row->id];
        ++count;
        CharacterDatabase.Execute("REPLACE INTO mod_gspe_qm_purchase (guid, stock_id, count) VALUES ({}, {}, {})",
            player->GetGUID().GetCounter(), row->id, count);
    }

    GspeAddonComm::Send(player, Acore::StringFormat("QBOUGHT\t{}", row->id));
    SendStock(player);
}

void QuartermasterMgr::RunService(Player* player, uint8 service)
{
    uint32 const guildId = player->GetGuildId();
    switch (service)
    {
        case QM_SERVICE_RECRUITS:
            sUnitMgr->RerollCandidates(guildId);
            sUnitMgr->SendUnits(player);
            break;
        case QM_SERVICE_MISSION_BOARD:
            sMissionMgr->RerollBoard(guildId);
            sMissionMgr->SendBoard(player);
            break;
        case QM_SERVICE_WORK_ORDER:
            sWorkOrderMgr->SkipWait(player);
            break;
        case QM_SERVICE_CONTRACT:
            sContractMgr->AddReroll(player);
            sContractMgr->SendContracts(player);
            break;
        default:
            break;
    }
}

// Weekly stock -------------------------------------------------------------------------

void QuartermasterMgr::LoadWeeklyPools()
{
    _gearPool.clear();
    _recipePool.clear();
    _materials.clear();
    _curiosities.clear();
    _guildWeekly.clear();
    _characterWeekly.clear();

    // Bind-on-equip world drops (reference loot) that no vendor sells.
    if (QueryResult r = WorldDatabase.Query(
            "SELECT DISTINCT it.entry FROM item_template it JOIN reference_loot_template rl ON rl.Item = it.entry "
            "WHERE it.class IN (2, 4) AND it.bonding = 2 AND it.Quality BETWEEN 2 AND 4 AND it.RequiredLevel > 0 "
            "AND it.InventoryType > 0 AND NOT EXISTS (SELECT 1 FROM npc_vendor v WHERE v.item = it.entry)"))
    {
        do
        {
            uint32 const entry = r->Fetch()[0].Get<uint32>();
            if (ItemTemplate const* proto = sObjectMgr->GetItemTemplate(entry))
                if (!IsJunkName(proto->Name1))
                    _gearPool.push_back(entry);
        } while (r->NextRow());
    }

    // World-drop recipes that no vendor sells.
    if (QueryResult r = WorldDatabase.Query(
            "SELECT DISTINCT it.entry FROM item_template it JOIN reference_loot_template rl ON rl.Item = it.entry "
            "WHERE it.class = 9 AND it.Quality BETWEEN 2 AND 4 AND it.RequiredSkill > 0 "
            "AND NOT EXISTS (SELECT 1 FROM npc_vendor v WHERE v.item = it.entry)"))
    {
        do
        {
            uint32 const entry = r->Fetch()[0].Get<uint32>();
            ItemTemplate const* proto = sObjectMgr->GetItemTemplate(entry);
            if (!proto || IsJunkName(proto->Name1)
                || std::find(std::begin(RECIPE_SKILLS), std::end(RECIPE_SKILLS), proto->RequiredSkill) == std::end(RECIPE_SKILLS))
                continue;
            std::vector<uint32> const spells = ItemSpells(proto);
            if (!spells.empty() && sSpellMgr->GetSpellInfo(spells.front()))
                _recipePool.push_back(entry);
        } while (r->NextRow());
    }

    if (QueryResult r = WorldDatabase.Query("SELECT item, min_level, max_level, count, cost FROM mod_gspe_qm_material"))
    {
        do
        {
            Field* f = r->Fetch();
            Material m{ f[0].Get<uint32>(), f[1].Get<uint8>(), f[2].Get<uint8>(), std::max<uint16>(1, f[3].Get<uint16>()), f[4].Get<uint32>() };
            if (sObjectMgr->GetItemTemplate(m.item))
                _materials.push_back(m);
            else
                LOG_ERROR("module", "GuildExpansion: weekly material {} is not a known item, skipped.", m.item);
        } while (r->NextRow());
    }

    if (QueryResult r = WorldDatabase.Query("SELECT item, kind, guild_level, cost, weight FROM mod_gspe_qm_curiosity"))
    {
        do
        {
            Field* f = r->Fetch();
            Curiosity c{ f[0].Get<uint32>(), f[1].Get<uint8>(), f[2].Get<uint8>(), f[3].Get<uint32>(), f[4].Get<uint16>() };
            if (c.weight && sObjectMgr->GetItemTemplate(c.item))
                _curiosities.push_back(c);
            else if (c.weight)
                LOG_ERROR("module", "GuildExpansion: weekly curiosity {} is not a known item, skipped.", c.item);
        } while (r->NextRow());
    }
}

QuartermasterMgr::Weekly& QuartermasterMgr::GuildWeekly(uint32 guildId)
{
    auto itr = _guildWeekly.find(guildId);
    if (itr == _guildWeekly.end())
    {
        Weekly& loaded = _guildWeekly[guildId];
        if (QueryResult r = CharacterDatabase.Query(
                "SELECT slot, week, item, count, cost, bought_by FROM mod_gspe_qm_weekly WHERE guildid = {} ORDER BY slot", guildId))
        {
            do
            {
                Field* f = r->Fetch();
                WeeklyOffer o;
                o.slot = f[0].Get<uint8>();
                loaded.week = f[1].Get<uint32>();
                o.item = f[2].Get<uint32>();
                o.count = f[3].Get<uint16>();
                o.cost = f[4].Get<uint32>();
                o.boughtBy = f[5].Get<uint32>();
                loaded.offers.push_back(o);
            } while (r->NextRow());
        }
        itr = _guildWeekly.find(guildId);
    }

    if (itr->second.week != GspeItems::NextWeeklyReset())
        RollGuildWeekly(guildId, itr->second);
    return itr->second;
}

QuartermasterMgr::Weekly& QuartermasterMgr::CharacterWeekly(Player* player)
{
    ObjectGuid::LowType const guid = player->GetGUID().GetCounter();
    auto itr = _characterWeekly.find(guid);
    if (itr == _characterWeekly.end())
    {
        Weekly& loaded = _characterWeekly[guid];
        if (QueryResult r = CharacterDatabase.Query(
                "SELECT slot, week, item, random_property, cost, bought FROM mod_gspe_qm_weekly_gear WHERE guid = {} ORDER BY slot", guid))
        {
            do
            {
                Field* f = r->Fetch();
                WeeklyOffer o;
                o.slot = f[0].Get<uint8>();
                loaded.week = f[1].Get<uint32>();
                o.item = f[2].Get<uint32>();
                o.randomProperty = f[3].Get<int32>();
                o.cost = f[4].Get<uint32>();
                o.boughtBy = f[5].Get<bool>() ? uint32(guid) : 0;
                loaded.offers.push_back(o);
            } while (r->NextRow());
        }
        itr = _characterWeekly.find(guid);
    }

    if (itr->second.week != GspeItems::NextWeeklyReset())
        RollCharacterWeekly(player, itr->second);
    return itr->second;
}

void QuartermasterMgr::RollCharacterWeekly(Player* player, Weekly& weekly)
{
    weekly.week = GspeItems::NextWeeklyReset();
    weekly.offers.clear();

    uint32 first = 0;
    for (uint8 slot : { QM_WEEKLY_GEAR_1, QM_WEEKLY_GEAR_2 })
    {
        WeeklyOffer o = RollGear(player, slot, first);
        first = o.item;
        weekly.offers.push_back(o);
        SaveGearOffer(player, weekly.week, o);
    }
}

WeeklyOffer QuartermasterMgr::RollGear(Player* player, uint8 slot, uint32 exclude) const
{
    WeeklyOffer o;
    o.slot = slot;

    uint32 const level = player->GetLevel();
    // Few rare drops require exactly 80, so level 80 also gets 78 and 79.
    uint32 const minLevel = level >= 80 ? 78 : (level > 3 ? level - 3 : 1);
    uint32 const best = GspeItems::BestArmorSubclass(player);

    auto candidates = [&](uint32 quality)
    {
        std::vector<uint32> out;
        for (uint32 entry : _gearPool)
        {
            ItemTemplate const* t = sObjectMgr->GetItemTemplate(entry);
            if (!t || entry == exclude || t->Quality != quality || t->RequiredLevel < minLevel || t->RequiredLevel > level)
                continue;
            // Armor in the class's best armor type; cloaks, jewelry, shields and the like for anyone.
            if (t->Class == ITEM_CLASS_ARMOR && t->SubClass >= ITEM_SUBCLASS_ARMOR_CLOTH
                && t->SubClass <= ITEM_SUBCLASS_ARMOR_PLATE && t->InventoryType != INVTYPE_CLOAK && t->SubClass != best)
                continue;
            if (player->CanUseItem(t) != EQUIP_ERR_OK)
                continue;
            out.push_back(entry);
        }
        return out;
    };

    std::vector<uint32> pool;
    if (urand(1, 100) <= sGspeConfig->quartermasterWeeklyEpicChance)
        pool = candidates(ITEM_QUALITY_EPIC);
    if (pool.empty())
        pool = candidates(ITEM_QUALITY_RARE);
    if (pool.empty())
        pool = candidates(ITEM_QUALITY_UNCOMMON);
    if (pool.empty())
        return o;

    o.item = Acore::Containers::SelectRandomContainerElement(pool);
    o.randomProperty = Item::GenerateItemRandomPropertyId(o.item);
    o.cost = WeeklyGearCost(sObjectMgr->GetItemTemplate(o.item)->Quality);
    return o;
}

void QuartermasterMgr::RollGuildWeekly(uint32 guildId, Weekly& weekly)
{
    weekly.week = GspeItems::NextWeeklyReset();
    weekly.offers.clear();

    // Material for the highest character level in the guild.
    WeeklyOffer material;
    material.slot = QM_WEEKLY_MATERIAL;
    uint8 const level = sUnitMgr->LevelCap(guildId);
    std::vector<Material const*> materials;
    for (Material const& m : _materials)
        if (level >= m.minLevel && level <= m.maxLevel)
            materials.push_back(&m);
    if (!materials.empty())
    {
        Material const* m = Acore::Containers::SelectRandomContainerElement(materials);
        material.item = m->item;
        material.count = m->count;
        material.cost = m->cost;
    }
    weekly.offers.push_back(material);

    RollRecipes(guildId, weekly);
    weekly.offers.push_back(RollCuriosity(guildId));

    for (WeeklyOffer const& o : weekly.offers)
        SaveGuildOffer(guildId, weekly.week, o);
}

void QuartermasterMgr::RollRecipes(uint32 guildId, Weekly& weekly) const
{
    // The guild's professions and its best skill in each.
    std::unordered_map<uint32, uint32> skills;
    if (QueryResult r = CharacterDatabase.Query(
            "SELECT cs.skill, MAX(cs.value) FROM character_skills cs JOIN guild_member gm ON gm.guid = cs.guid "
            "WHERE gm.guildid = {} GROUP BY cs.skill", guildId))
    {
        do
            skills[r->Fetch()[0].Get<uint32>()] = r->Fetch()[1].Get<uint32>();
        while (r->NextRow());
    }

    // Recipes the guild can learn, preferring ones within 75 points of its best skill.
    std::vector<ItemTemplate const*> closeRecipes, allRecipes;
    for (uint32 entry : _recipePool)
    {
        ItemTemplate const* t = sObjectMgr->GetItemTemplate(entry);
        auto itr = t ? skills.find(t->RequiredSkill) : skills.end();
        if (itr == skills.end() || t->RequiredSkillRank > itr->second)
            continue;
        allRecipes.push_back(t);
        if (t->RequiredSkillRank + 75 >= itr->second)
            closeRecipes.push_back(t);
    }
    std::vector<ItemTemplate const*>& pool = closeRecipes.size() >= 2 ? closeRecipes : allRecipes;
    std::shuffle(pool.begin(), pool.end(), RandomEngine::Instance());

    ItemTemplate const* picks[2] = { nullptr, nullptr };
    for (ItemTemplate const* t : pool)
    {
        if (!picks[0])
            picks[0] = t;
        else if (t->RequiredSkill != picks[0]->RequiredSkill)
        {
            picks[1] = t;
            break;
        }
    }
    // Only one profession: two recipes from it.
    if (picks[0] && !picks[1])
        for (ItemTemplate const* t : pool)
            if (t != picks[0])
            {
                picks[1] = t;
                break;
            }

    for (uint8 i = 0; i < 2; ++i)
    {
        WeeklyOffer o;
        o.slot = uint8(QM_WEEKLY_RECIPE_1 + i);
        if (picks[i])
        {
            o.item = picks[i]->ItemId;
            o.cost = RecipeCost(picks[i]->Quality);
        }
        weekly.offers.push_back(o);
    }
}

WeeklyOffer QuartermasterMgr::RollCuriosity(uint32 guildId) const
{
    WeeklyOffer o;
    o.slot = QM_WEEKLY_CURIOSITY;

    uint8 const guildLevel = sGuildProgressMgr->GetLevel(guildId);
    std::vector<Curiosity const*> pets, mounts;
    for (Curiosity const& c : _curiosities)
        if (guildLevel >= c.guildLevel)
            (c.kind == 2 ? mounts : pets).push_back(&c);

    bool const mount = !mounts.empty() && (pets.empty() || urand(1, 100) <= sGspeConfig->quartermasterCuriosityMountChance);
    std::vector<Curiosity const*>& pool = mount ? mounts : pets;
    if (pool.empty())
        return o;

    // Prefer pets and mounts no guild character has learned yet.
    std::unordered_set<uint32> spells;
    for (Curiosity const* c : pool)
        for (uint32 spell : ItemSpells(sObjectMgr->GetItemTemplate(c->item)))
            spells.insert(spell);
    std::unordered_set<uint32> known;
    if (!spells.empty())
    {
        std::string list;
        for (uint32 spell : spells)
            list += (list.empty() ? "" : ",") + std::to_string(spell);
        if (QueryResult r = CharacterDatabase.Query(
                "SELECT DISTINCT cs.spell FROM character_spell cs JOIN guild_member gm ON gm.guid = cs.guid "
                "WHERE gm.guildid = {} AND cs.spell IN ({})", guildId, list))
        {
            do
                known.insert(r->Fetch()[0].Get<uint32>());
            while (r->NextRow());
        }
    }
    std::vector<Curiosity const*> fresh;
    for (Curiosity const* c : pool)
    {
        std::vector<uint32> const itemSpells = ItemSpells(sObjectMgr->GetItemTemplate(c->item));
        if (std::none_of(itemSpells.begin(), itemSpells.end(), [&known](uint32 s) { return known.count(s); }))
            fresh.push_back(c);
    }
    std::vector<Curiosity const*>& candidates = fresh.empty() ? pool : fresh;

    uint32 total = 0;
    for (Curiosity const* c : candidates)
        total += c->weight;
    uint32 roll = urand(1, std::max<uint32>(1, total));
    Curiosity const* pick = candidates.front();
    for (Curiosity const* c : candidates)
    {
        if (roll <= c->weight)
        {
            pick = c;
            break;
        }
        roll -= c->weight;
    }

    o.item = pick->item;
    o.cost = pick->cost;
    return o;
}

void QuartermasterMgr::SaveGuildOffer(uint32 guildId, uint32 week, WeeklyOffer const& o)
{
    CharacterDatabase.Execute(
        "REPLACE INTO mod_gspe_qm_weekly (guildid, slot, week, item, count, cost, bought_by) VALUES ({}, {}, {}, {}, {}, {}, {})",
        guildId, uint32(o.slot), week, o.item, o.count, o.cost, o.boughtBy);
}

void QuartermasterMgr::SaveGearOffer(Player* player, uint32 week, WeeklyOffer const& o)
{
    CharacterDatabase.Execute(
        "REPLACE INTO mod_gspe_qm_weekly_gear (guid, slot, week, item, random_property, cost, bought) VALUES ({}, {}, {}, {}, {}, {}, {})",
        player->GetGUID().GetCounter(), uint32(o.slot), week, o.item, o.randomProperty, o.cost, o.boughtBy ? 1 : 0);
}

uint8 QuartermasterMgr::WeeklyState(Player* player, WeeklyOffer const& o) const
{
    if (!o.item)
        return QM_ROW_EMPTY;
    if (o.boughtBy)
        return QM_ROW_SOLD;

    ItemTemplate const* proto = sObjectMgr->GetItemTemplate(o.item);
    if (!proto)
        return QM_ROW_EMPTY;
    if (o.slot >= QM_WEEKLY_RECIPE_1)
        for (uint32 spell : ItemSpells(proto))
            if (player->HasSpell(spell))
                return QM_ROW_KNOWN;
    if (player->CanUseItem(proto) != EQUIP_ERR_OK)
        return QM_ROW_UNUSABLE;
    return QM_ROW_OK;
}

void QuartermasterMgr::SendWeeklyLine(Player* player, WeeklyOffer const& o)
{
    std::string buyer;
    if (o.boughtBy)
        sCharacterCache->GetCharacterNameByGuid(ObjectGuid::Create<HighGuid::Player>(o.boughtBy), buyer);
    uint32 const suffixFactor = o.randomProperty < 0 ? GenerateEnchSuffixFactor(o.item) : 0;

    // QW\tslot\titem\tcount\tcost\tstate\trandomProperty\tsuffixFactor\tbuyer
    GspeAddonComm::Send(player, Acore::StringFormat("QW\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}",
        uint32(o.slot), o.item, o.count, Price(player, o.cost), uint32(WeeklyState(player, o)), o.randomProperty, suffixFactor,
        GspeAddonComm::Sanitize(buyer, 24)));
}

void QuartermasterMgr::HandleBuyWeekly(Player* player, uint8 slot)
{
    if (!CheckRequest(player))
        return;

    uint32 const guildId = player->GetGuildId();
    bool const gear = slot == QM_WEEKLY_GEAR_1 || slot == QM_WEEKLY_GEAR_2;
    Weekly& weekly = gear ? CharacterWeekly(player) : GuildWeekly(guildId);
    auto itr = std::find_if(weekly.offers.begin(), weekly.offers.end(), [slot](WeeklyOffer const& o) { return o.slot == slot; });
    if (itr == weekly.offers.end())
    {
        SendStock(player);
        return;
    }

    switch (WeeklyState(player, *itr))
    {
        case QM_ROW_OK:
            break;
        case QM_ROW_SOLD:
            GspeAddonComm::SendError(player, "That has already been bought this week.");
            SendStock(player);
            return;
        case QM_ROW_KNOWN:
            GspeAddonComm::SendError(player, "You already know that.");
            return;
        case QM_ROW_UNUSABLE:
            GspeAddonComm::SendError(player, "You can't use that item.");
            return;
        default:
            GspeAddonComm::SendError(player, "There is nothing for sale there this week.");
            return;
    }

    if (!sGuildProgressMgr->SpendSupplies(guildId, Price(player, itr->cost)))
    {
        GspeAddonComm::SendError(player, "Your guild doesn't have enough supplies.");
        return;
    }

    // Marked sold before the item is handed out, so it can't be bought twice.
    WeeklyOffer const offer = *itr;
    itr->boughtBy = player->GetGUID().GetCounter();
    if (gear)
        SaveGearOffer(player, weekly.week, *itr);
    else
        SaveGuildOffer(guildId, weekly.week, *itr);

    GspeItems::GiveItem(player, offer.item, offer.count, "Guild quartermaster", offer.randomProperty);
    GspeAddonComm::Send(player, Acore::StringFormat("QBOUGHT\tW{}", uint32(slot)));
    SendStock(player);
}

void QuartermasterMgr::OnGuildDisband(uint32 guildId)
{
    _guildWeekly.erase(guildId);
    CharacterDatabase.Execute("DELETE FROM mod_gspe_qm_weekly WHERE guildid = {}", guildId);
}

void QuartermasterMgr::RerollWeekly(Player* player)
{
    if (uint32 const guildId = player->GetGuildId())
        RollGuildWeekly(guildId, GuildWeekly(guildId));
    RollCharacterWeekly(player, CharacterWeekly(player));
    SendStock(player);
}
