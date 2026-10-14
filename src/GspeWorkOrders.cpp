/*
 * mod-guild-expansion: work orders.
 */

#include "GspeWorkOrders.h"
#include "GspeAddonComm.h"
#include "GspeConfig.h"
#include "GspeProgress.h"

#include "Bag.h"
#include "Chat.h"
#include "Containers.h"
#include "DBCStores.h"
#include "DatabaseEnv.h"
#include "Item.h"
#include "Log.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "Random.h"
#include "SpellInfo.h"
#include "SpellMgr.h"
#include "StringFormat.h"

#include <algorithm>
#include <random>
#include <unordered_set>

namespace
{
// Professions that produce items from recipes. Mining is included for smelting.
constexpr uint16 CRAFT_SKILLS[] =
{
    SKILL_ALCHEMY, SKILL_BLACKSMITHING, SKILL_ENCHANTING, SKILL_ENGINEERING, SKILL_INSCRIPTION,
    SKILL_JEWELCRAFTING, SKILL_LEATHERWORKING, SKILL_TAILORING, SKILL_COOKING, SKILL_FIRST_AID,
    SKILL_MINING,
};

// Materials asked for by provisioning orders. Skill 0 = anyone.
struct GatherSource
{
    uint16 skill;
    char const* lootTable;
    uint32 subclass;     // item class 7 (trade goods) subclass
};

constexpr GatherSource GATHER_SOURCES[] =
{
    { SKILL_HERBALISM, "gameobject_loot_template", 9 },   // herbs
    { SKILL_MINING,    "gameobject_loot_template", 7 },   // ore, stone
    { SKILL_SKINNING,  "skinning_loot_template",   6 },   // leather, hides, scales
    { SKILL_FISHING,   "fishing_loot_template",    8 },   // raw fish
    { SKILL_ENCHANTING, "disenchant_loot_template", 12 }, // dust, essences, shards
    { 0,               "creature_loot_template",   5 },   // cloth
    { 0,               "reference_loot_template",  5 },   // cloth dropped through reference loot
};

constexpr uint32 MAX_ORDER_QUANTITY = 20;

bool IsJunkItemName(std::string const& name)
{
    static char const* const markers[] = { "Deprecated", "DEPRECATED", "Test", "TEST", "OLD", "[PH]", "Monster -", "zz" };
    for (char const* m : markers)
        if (name.find(m) != std::string::npos)
            return true;
    return false;
}

template <typename T, typename WeightFn>
T const* PickWeighted(std::vector<T const*> const& items, WeightFn weight)
{
    uint32 total = 0;
    for (T const* t : items)
        total += weight(*t);
    if (!total)
        return nullptr;

    uint32 roll = urand(1, total);
    for (T const* t : items)
    {
        uint32 const w = weight(*t);
        if (roll <= w)
            return t;
        roll -= w;
    }
    return nullptr;
}
} // namespace

WorkOrderMgr* WorkOrderMgr::instance()
{
    static WorkOrderMgr inst;
    return &inst;
}

void WorkOrderMgr::BuildCatalog()
{
    _recipesBySkill.clear();
    _gatherBySkill.clear();
    _craftedBy.clear();

    std::unordered_set<uint32> seenSpells;
    uint32 recipeCount = 0;
    for (uint32 i = 0; i < sSkillLineAbilityStore.GetNumRows(); ++i)
    {
        SkillLineAbilityEntry const* sla = sSkillLineAbilityStore.LookupEntry(i);
        if (!sla || !sla->TrivialSkillLineRankHigh)
            continue;

        uint16 const skill = uint16(sla->SkillLine);
        if (std::find(std::begin(CRAFT_SKILLS), std::end(CRAFT_SKILLS), skill) == std::end(CRAFT_SKILLS))
            continue;

        if (!seenSpells.insert(sla->Spell).second)
            continue;

        SpellInfo const* spell = sSpellMgr->GetSpellInfo(sla->Spell);
        if (!spell)
            continue;

        for (SpellEffectInfo const& eff : spell->GetEffects())
        {
            if (eff.Effect != SPELL_EFFECT_CREATE_ITEM || !eff.ItemType)
                continue;

            ItemTemplate const* item = sObjectMgr->GetItemTemplate(eff.ItemType);
            if (!item || item->Class == ITEM_CLASS_QUEST || item->Class == ITEM_CLASS_KEY || IsJunkItemName(item->Name1))
                break;

            uint32 reagentValue = 0;
            for (uint8 r = 0; r < MAX_SPELL_REAGENTS; ++r)
                if (spell->Reagent[r] > 0)
                    if (ItemTemplate const* reagent = sObjectMgr->GetItemTemplate(uint32(spell->Reagent[r])))
                        reagentValue += reagent->SellPrice * spell->ReagentCount[r];

            CraftRecipe recipe;
            recipe.spell = sla->Spell;
            recipe.item = item->ItemId;
            recipe.createCount = uint32(std::max(1, eff.BasePoints + 1));
            recipe.minRank = sla->MinSkillLineRank;
            recipe.yellowAt = sla->TrivialSkillLineRankLow;
            recipe.grayAt = sla->TrivialSkillLineRankHigh;
            recipe.reagentValue = reagentValue;
            _recipesBySkill[skill].push_back(recipe);
            _craftedBy.emplace(item->ItemId, skill);
            ++recipeCount;
            break;
        }
    }

    uint32 gatherCount = 0;
    for (GatherSource const& src : GATHER_SOURCES)
    {
        // Chance >= 20 (or 0 = equal share of a loot group) skips rare bonus drops such as lotuses.
        QueryResult r = WorldDatabase.Query(
            "SELECT DISTINCT lt.Item FROM {} lt JOIN item_template it ON it.entry = lt.Item "
            "WHERE lt.Reference = 0 AND it.class = 7 AND it.subclass = {} AND it.Quality <= 2 "
            "AND (lt.Chance >= 20 OR lt.Chance = 0)", src.lootTable, src.subclass);
        if (!r)
            continue;

        std::vector<GatherItem>& list = _gatherBySkill[src.skill];
        do
        {
            uint32 const entry = r->Fetch()[0].Get<uint32>();
            ItemTemplate const* item = sObjectMgr->GetItemTemplate(entry);
            if (!item || !item->ItemLevel || IsJunkItemName(item->Name1))
                continue;
            if (std::any_of(list.begin(), list.end(), [entry](GatherItem const& g) { return g.item == entry; }))
                continue;

            list.push_back({ entry, item->ItemLevel });
            ++gatherCount;
        } while (r->NextRow());
    }

    if (QueryResult r = CharacterDatabase.Query("SELECT MAX(id) FROM mod_gspe_work_order"))
        _nextId = r->Fetch()[0].Get<uint32>() + 1;

    LOG_INFO("module", "GuildExpansion: work orders ready ({} recipes, {} materials).", recipeCount, gatherCount);
}

bool WorkOrderMgr::CheckRequest(Player* player)
{
    if (!sGspeConfig->enable || !sGspeConfig->workOrdersEnable)
    {
        GspeAddonComm::Send(player, "WOB\t0\t2\t0");
        GspeAddonComm::Send(player, "WOE");
        return false;
    }
    if (!player->GetGuildId())
    {
        GspeAddonComm::Send(player, "WOB\t0\t1\t0");
        GspeAddonComm::Send(player, "WOE");
        return false;
    }
    return true;
}

WorkOrderMgr::CharacterOrders* WorkOrderMgr::GetOrders(Player* player)
{
    ObjectGuid::LowType const guid = player->GetGUID().GetCounter();
    if (auto itr = _characters.find(guid); itr != _characters.end())
        return &itr->second;

    CharacterOrders& co = _characters[guid];
    if (QueryResult r = CharacterDatabase.Query(
            "SELECT id, kind, skill, spell, item, quantity, level, gold, supplies, guild_xp, expires "
            "FROM mod_gspe_work_order WHERE guid = {} ORDER BY id", guid))
    {
        do
        {
            Field* f = r->Fetch();
            WorkOrder o;
            o.id = f[0].Get<uint32>();
            o.kind = f[1].Get<uint8>();
            o.skill = f[2].Get<uint16>();
            o.spell = f[3].Get<uint32>();
            o.item = f[4].Get<uint32>();
            o.quantity = f[5].Get<uint16>();
            o.level = f[6].Get<uint8>();
            o.gold = f[7].Get<uint32>();
            o.supplies = f[8].Get<uint32>();
            o.guildXp = f[9].Get<uint32>();
            o.expires = f[10].Get<uint32>();
            co.orders.push_back(o);
        } while (r->NextRow());
    }
    return &co;
}

WorkOrder* WorkOrderMgr::FindOrder(CharacterOrders& co, uint32 orderId)
{
    auto itr = std::find_if(co.orders.begin(), co.orders.end(), [orderId](WorkOrder const& o) { return o.id == orderId && o.item; });
    return itr != co.orders.end() ? &*itr : nullptr;
}

void WorkOrderMgr::Remove(CharacterOrders& co, uint32 orderId)
{
    co.orders.erase(std::remove_if(co.orders.begin(), co.orders.end(),
        [orderId](WorkOrder const& o) { return o.id == orderId; }), co.orders.end());
    co.placements.erase(orderId);
    CharacterDatabase.Execute("DELETE FROM mod_gspe_work_order WHERE id = {}", orderId);
}

void WorkOrderMgr::Insert(Player* player, WorkOrder const& o)
{
    CharacterDatabase.Execute(
        "INSERT INTO mod_gspe_work_order (id, guid, kind, skill, spell, item, quantity, level, gold, supplies, guild_xp, expires) "
        "VALUES ({}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {})",
        o.id, player->GetGUID().GetCounter(), uint32(o.kind), o.skill, o.spell, o.item, o.quantity,
        uint32(o.level), o.gold, o.supplies, o.guildXp, o.expires);
}

void WorkOrderMgr::Refill(Player* player, CharacterOrders& co)
{
    uint32 const now = uint32(time(nullptr));
    std::vector<uint32> expired;
    for (WorkOrder const& o : co.orders)
        if (o.expires <= now || (o.item && !sObjectMgr->GetItemTemplate(o.item)))
            expired.push_back(o.id);
    for (uint32 id : expired)
        Remove(co, id);

    while (co.orders.size() < sGspeConfig->workOrderCount)
    {
        WorkOrder order;
        if (!Generate(player, co, order))
            break;

        order.id = _nextId++;
        order.expires = now + sGspeConfig->workOrderDurationHours * HOUR;
        co.orders.push_back(order);
        Insert(player, order);
    }
}

bool WorkOrderMgr::Generate(Player* player, CharacterOrders const& co, WorkOrder& out)
{
    struct Source
    {
        uint8 kind;
        uint16 skill;
    };

    std::vector<Source> sources;
    for (uint16 skill : CRAFT_SKILLS)
        if (player->HasSkill(skill) && _recipesBySkill.count(skill))
            sources.push_back({ WORK_ORDER_CRAFT, skill });
    for (GatherSource const& src : GATHER_SOURCES)
        if ((!src.skill || player->HasSkill(src.skill)) && _gatherBySkill.count(src.skill)
            && std::none_of(sources.begin(), sources.end(),
                [&src](Source const& s) { return s.kind == WORK_ORDER_GATHER && s.skill == src.skill; }))
            sources.push_back({ WORK_ORDER_GATHER, src.skill });

    // Prefer sources that no open order uses yet, so the board stays varied.
    auto inUse = [&co](Source const& s)
    {
        return std::any_of(co.orders.begin(), co.orders.end(),
            [&s](WorkOrder const& o) { return o.kind == s.kind && o.skill == s.skill; });
    };
    std::stable_partition(sources.begin(), sources.end(), [&](Source const& s) { return !inUse(s); });
    std::size_t const fresh = std::count_if(sources.begin(), sources.end(), [&](Source const& s) { return !inUse(s); });
    std::shuffle(sources.begin(), sources.begin() + fresh, RandomEngine::Instance());
    std::shuffle(sources.begin() + fresh, sources.end(), RandomEngine::Instance());

    for (Source const& s : sources)
    {
        bool const ok = s.kind == WORK_ORDER_CRAFT ? GenerateCraft(player, s.skill, out) : GenerateGather(player, s.skill, out);
        if (ok)
            return true;
    }
    return false;
}

bool WorkOrderMgr::GenerateCraft(Player* player, uint16 skill, WorkOrder& out)
{
    auto itr = _recipesBySkill.find(skill);
    if (itr == _recipesBySkill.end())
        return false;

    uint32 const value = player->GetSkillValue(skill);
    std::vector<CraftRecipe const*> known;
    for (CraftRecipe const& r : itr->second)
        if (player->HasSpell(r.spell))
            known.push_back(&r);
    if (known.empty())
        return false;

    // Orange and yellow recipes (still give skill-ups) are favoured; green less so.
    CraftRecipe const* pick = PickWeighted(known, [value](CraftRecipe const& r) -> uint32
    {
        uint32 const greenAt = (r.yellowAt + r.grayAt) / 2;
        if (value < greenAt)
            return 3;
        if (value < r.grayAt)
            return 1;
        return 0;
    });

    // Everything known is grey: use one of the five highest recipes.
    if (!pick)
    {
        std::sort(known.begin(), known.end(), [](CraftRecipe const* a, CraftRecipe const* b) { return a->minRank > b->minRank; });
        known.resize(std::min<std::size_t>(known.size(), 5));
        pick = Acore::Containers::SelectRandomContainerElement(known);
    }

    ItemTemplate const* item = sObjectMgr->GetItemTemplate(pick->item);
    if (!item)
        return false;

    uint32 const stack = std::min<uint32>(item->GetMaxStackSize(), MAX_ORDER_QUANTITY);
    uint32 quantity = 1;
    if (stack > 1)
        quantity = std::min(stack, pick->createCount * urand(1, 3));
    uint32 const crafts = (quantity + pick->createCount - 1) / pick->createCount;

    out = WorkOrder{};
    out.kind = WORK_ORDER_CRAFT;
    out.skill = skill;
    out.spell = pick->spell;
    out.item = pick->item;
    out.quantity = uint16(quantity);
    SetRewards(player, out, std::max(pick->reagentValue * crafts, item->SellPrice * quantity));
    return true;
}

bool WorkOrderMgr::GenerateGather(Player* player, uint16 skill, WorkOrder& out)
{
    auto itr = _gatherBySkill.find(skill);
    if (itr == _gatherBySkill.end() || itr->second.empty())
        return false;

    uint32 const level = player->GetLevel();
    std::vector<GatherItem const*> band;
    for (GatherItem const& g : itr->second)
        if (g.itemLevel + 10 >= level && g.itemLevel <= level + 2)
            band.push_back(&g);

    // Nothing in the band: take the highest-level materials below it (or the lowest overall).
    if (band.empty())
    {
        std::vector<GatherItem const*> all;
        for (GatherItem const& g : itr->second)
            all.push_back(&g);
        std::sort(all.begin(), all.end(), [](GatherItem const* a, GatherItem const* b) { return a->itemLevel > b->itemLevel; });
        for (GatherItem const* g : all)
            if (g->itemLevel <= level + 2 && band.size() < 3)
                band.push_back(g);
        if (band.empty())
            band.push_back(all.back());
    }

    GatherItem const* pick = Acore::Containers::SelectRandomContainerElement(band);
    ItemTemplate const* item = sObjectMgr->GetItemTemplate(pick->item);
    if (!item)
        return false;

    uint32 const stack = std::clamp<uint32>(item->GetMaxStackSize(), 1, MAX_ORDER_QUANTITY);
    uint32 const quantity = std::max<uint32>(std::min<uint32>(stack, 5), urand(stack / 2, stack));

    out = WorkOrder{};
    out.kind = WORK_ORDER_GATHER;
    out.skill = skill;
    out.item = pick->item;
    out.quantity = uint16(quantity);
    SetRewards(player, out, item->SellPrice * quantity);
    return true;
}

void WorkOrderMgr::SetRewards(Player* player, WorkOrder& order, uint32 materialValue)
{
    GspeConfig const* cfg = sGspeConfig;
    uint32 const level = player->GetLevel();
    order.level = uint8(level);
    order.gold = uint32(cfg->workOrderGoldPerLevelSquared * float(level * level)
        + cfg->workOrderGoldValueMultiplier * float(materialValue));
    order.supplies = uint32(cfg->workOrderSuppliesBase + cfg->workOrderSuppliesPerLevel * float(level));
    order.guildXp = cfg->workOrderGuildXpPerLevel * level;
}

uint32 WorkOrderMgr::ValidatePlacements(Player* player, WorkOrder const& order, std::vector<Placement>& placed)
{
    uint32 total = 0;
    for (auto itr = placed.begin(); itr != placed.end();)
    {
        Item* item = player->GetItemByGuid(itr->item);
        if (!item || item->GetEntry() != order.item || item->IsInTrade() || !Player::IsInventoryPos(item->GetPos()))
        {
            itr = placed.erase(itr);
            continue;
        }

        itr->count = std::min(itr->count, item->GetCount());
        total += itr->count;
        ++itr;
    }

    // Placed more than needed (e.g. after a refresh): trim from the end.
    while (total > order.quantity && !placed.empty())
    {
        uint32 const excess = total - order.quantity;
        Placement& last = placed.back();
        if (last.count > excess)
        {
            last.count -= excess;
            total -= excess;
        }
        else
        {
            total -= last.count;
            placed.pop_back();
        }
    }
    return total;
}

void WorkOrderMgr::ForgetItemElsewhere(CharacterOrders& co, uint32 keepOrderId, ObjectGuid item)
{
    for (auto& [orderId, placed] : co.placements)
    {
        if (orderId == keepOrderId)
            continue;
        placed.erase(std::remove_if(placed.begin(), placed.end(),
            [item](Placement const& p) { return p.item == item; }), placed.end());
    }
}

void WorkOrderMgr::SendPlaced(Player* player, uint32 orderId, uint32 total)
{
    GspeAddonComm::Send(player, Acore::StringFormat("PLACED\t{}\t{}", orderId, total));
}

void WorkOrderMgr::SendOrderLine(Player* player, WorkOrder const& o, uint32 placed)
{
    ItemTemplate const* item = sObjectMgr->GetItemTemplate(o.item);
    uint32 const now = uint32(time(nullptr));
    // WO\tid\tkind\tskill\tspell\titem\tquality\tquantity\tplaced\tgold\tsupplies\tguildXp\texpiresIn\tname
    GspeAddonComm::Send(player, Acore::StringFormat("WO\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}",
        o.id, uint32(o.kind), o.skill, o.spell, o.item, item ? item->Quality : 1, o.quantity, placed,
        o.gold, o.supplies, o.guildXp, o.expires > now ? o.expires - now : 0,
        GspeAddonComm::Sanitize(item ? item->Name1 : "Unknown item", 60)));
}

void WorkOrderMgr::SendOrders(Player* player)
{
    if (!CheckRequest(player))
        return;

    CharacterOrders* co = GetOrders(player);
    Refill(player, *co);

    GspeAddonComm::Send(player, Acore::StringFormat("WOB\t{}\t0\t{}", co->orders.size(),
        sGspeConfig->workOrderAbandonDelayHours));
    for (WorkOrder const& o : co->orders)
        SendOrderLine(player, o, ValidatePlacements(player, o, co->placements[o.id]));
    GspeAddonComm::Send(player, "WOE");
}

void WorkOrderMgr::HandlePlace(Player* player, uint32 orderId, uint8 clientBag, uint8 clientSlot)
{
    if (!CheckRequest(player))
        return;

    CharacterOrders* co = GetOrders(player);
    WorkOrder* order = FindOrder(*co, orderId);
    if (!order)
    {
        GspeAddonComm::SendError(player, "That work order is no longer available.");
        SendOrders(player);
        return;
    }

    uint8 bag = 0, slot = 0;
    Item* item = GspeAddonComm::ClientSlotToServer(clientBag, clientSlot, bag, slot) ? player->GetItemByPos(bag, slot) : nullptr;
    if (!item || item->IsInTrade())
    {
        GspeAddonComm::SendError(player, "Item not found in your bags.");
        return;
    }
    if (item->GetEntry() != order->item)
    {
        GspeAddonComm::SendError(player, "That item isn't what this order needs.");
        return;
    }

    std::vector<Placement>& placed = co->placements[orderId];
    // Re-placing an item already in this order replaces its entry.
    placed.erase(std::remove_if(placed.begin(), placed.end(),
        [item](Placement const& p) { return p.item == item->GetGUID(); }), placed.end());

    uint32 const total = ValidatePlacements(player, *order, placed);
    if (total >= order->quantity)
    {
        GspeAddonComm::SendError(player, "This order already has enough items.");
        SendPlaced(player, orderId, total);
        return;
    }

    uint32 const take = std::min(item->GetCount(), order->quantity - total);
    placed.push_back({ item->GetGUID(), take });
    ForgetItemElsewhere(*co, orderId, item->GetGUID());
    SendPlaced(player, orderId, total + take);
}

void WorkOrderMgr::HandleClear(Player* player, uint32 orderId)
{
    if (!CheckRequest(player))
        return;

    CharacterOrders* co = GetOrders(player);
    co->placements.erase(orderId);
    SendPlaced(player, orderId, 0);
}

void WorkOrderMgr::HandleFill(Player* player, uint32 orderId)
{
    if (!CheckRequest(player))
        return;

    CharacterOrders* co = GetOrders(player);
    WorkOrder* order = FindOrder(*co, orderId);
    if (!order)
        return;

    std::vector<Placement>& placed = co->placements[orderId];
    uint32 total = ValidatePlacements(player, *order, placed);

    auto isPlacedAnywhere = [co](ObjectGuid guid)
    {
        for (auto const& [id, list] : co->placements)
            for (Placement const& p : list)
                if (p.item == guid)
                    return true;
        return false;
    };

    auto consider = [&](Item* item)
    {
        if (total >= order->quantity || !item || item->GetEntry() != order->item || item->IsInTrade()
            || isPlacedAnywhere(item->GetGUID()))
            return;
        uint32 const take = std::min(item->GetCount(), order->quantity - total);
        placed.push_back({ item->GetGUID(), take });
        total += take;
    };

    for (uint8 i = INVENTORY_SLOT_ITEM_START; i < INVENTORY_SLOT_ITEM_END; ++i)
        consider(player->GetItemByPos(INVENTORY_SLOT_BAG_0, i));
    for (uint8 i = INVENTORY_SLOT_BAG_START; i < INVENTORY_SLOT_BAG_END; ++i)
        if (Bag* bag = player->GetBagByPos(i))
            for (uint32 j = 0; j < bag->GetBagSize(); ++j)
                consider(bag->GetItemByPos(uint8(j)));

    if (total < order->quantity)
        GspeAddonComm::SendError(player, Acore::StringFormat("You only have {} of {} in your bags.", total, order->quantity));
    SendPlaced(player, orderId, total);
}

void WorkOrderMgr::HandleTurnIn(Player* player, uint32 orderId)
{
    if (!CheckRequest(player))
        return;

    CharacterOrders* co = GetOrders(player);
    WorkOrder* found = FindOrder(*co, orderId);
    if (!found)
    {
        GspeAddonComm::SendError(player, "That work order is no longer available.");
        SendOrders(player);
        return;
    }

    WorkOrder const order = *found;
    std::vector<Placement>& placed = co->placements[orderId];
    uint32 const total = ValidatePlacements(player, order, placed);
    if (total < order.quantity)
    {
        GspeAddonComm::SendError(player, Acore::StringFormat("Place {} more to complete this order.", order.quantity - total));
        SendPlaced(player, orderId, total);
        return;
    }

    for (Placement const& p : placed)
    {
        if (Item* item = player->GetItemByGuid(p.item))
        {
            uint32 count = p.count;
            player->DestroyItemCount(item, count, true);
        }
    }

    player->ModifyMoney(int32(std::min<uint32>(order.gold, uint32(INT32_MAX))));
    if (uint32 const guildId = player->GetGuildId())
    {
        sGuildProgressMgr->AddSupplies(guildId, order.supplies);
        sGuildProgressMgr->AddGuildXP(guildId, order.guildXp, player);
    }

    Remove(*co, orderId);

    ChatHandler(player->GetSession()).SendSysMessage(Acore::StringFormat(
        "|cff00ccffWork order complete:|r {}g {}s {}c, {} guild XP, {} guild supplies.",
        order.gold / 10000, (order.gold / 100) % 100, order.gold % 100, order.guildXp, order.supplies));
    GspeAddonComm::Send(player, Acore::StringFormat("DONE\t{}\t{}\t{}\t{}", orderId, order.gold, order.guildXp, order.supplies));
    SendOrders(player);
}

void WorkOrderMgr::HandleAbandon(Player* player, uint32 orderId)
{
    if (!CheckRequest(player))
        return;

    CharacterOrders* co = GetOrders(player);
    WorkOrder* order = FindOrder(*co, orderId);
    if (!order)
    {
        SendOrders(player);
        return;
    }

    // The slot stays empty until the delay passes; Refill then puts a new order in it.
    co->placements.erase(orderId);
    uint32 const readyAt = uint32(time(nullptr)) + sGspeConfig->workOrderAbandonDelayHours * HOUR;
    *order = WorkOrder{ .id = orderId, .expires = readyAt };
    CharacterDatabase.Execute(
        "UPDATE mod_gspe_work_order SET kind = 0, skill = 0, spell = 0, item = 0, quantity = 0, gold = 0, supplies = 0, "
        "guild_xp = 0, expires = {} WHERE id = {}", readyAt, orderId);
    SendOrders(player);
}

void WorkOrderMgr::ResetOrders(Player* player)
{
    CharacterOrders* co = GetOrders(player);
    std::vector<uint32> ids;
    for (WorkOrder const& o : co->orders)
        ids.push_back(o.id);
    for (uint32 id : ids)
        Remove(*co, id);
    SendOrders(player);
}

uint16 WorkOrderMgr::CraftedBy(uint32 item) const
{
    auto itr = _craftedBy.find(item);
    return itr != _craftedBy.end() ? itr->second : 0;
}

uint32 WorkOrderMgr::RandomMaterial(uint8 level, uint16 skill) const
{
    std::vector<uint32> band;
    for (auto const& [gatherSkill, list] : _gatherBySkill)
    {
        if (skill != ANY_SKILL && gatherSkill != skill)
            continue;
        for (GatherItem const& g : list)
            if (g.itemLevel + 10 >= level && g.itemLevel <= uint32(level) + 2)
                band.push_back(g.item);
    }
    return band.empty() ? 0 : Acore::Containers::SelectRandomContainerElement(band);
}

void WorkOrderMgr::OnLogout(Player* player)
{
    _characters.erase(player->GetGUID().GetCounter());
}
