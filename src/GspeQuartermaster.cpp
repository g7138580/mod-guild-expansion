/*
 * mod-guild-expansion: the guild quartermaster.
 */

#include "GspeQuartermaster.h"
#include "GspeAddonComm.h"
#include "GspeConfig.h"
#include "GspeContracts.h"
#include "GspeItems.h"
#include "GspeMissions.h"
#include "GspeProgress.h"
#include "GspeUnits.h"
#include "GspeWorkOrders.h"

#include "DatabaseEnv.h"
#include "Log.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "StringFormat.h"

#include <algorithm>

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

    LOG_INFO("module", "GuildExpansion: quartermaster ready ({} items and services).", _stock.size());
}

void QuartermasterMgr::OnLogout(Player* player)
{
    _purchases.erase(player->GetGUID().GetCounter());
}

bool QuartermasterMgr::CheckRequest(Player* player)
{
    if (!sGspeConfig->enable || !sGspeConfig->quartermasterEnable)
    {
        GspeAddonComm::Send(player, "QB\t2\t0");
        GspeAddonComm::Send(player, "QE");
        return false;
    }
    if (!player->GetGuildId())
    {
        GspeAddonComm::Send(player, "QB\t1\t0");
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

    GspeAddonComm::Send(player, Acore::StringFormat("QB\t0\t{}", uint32(guildLevel)));
    for (QuartermasterRow const& row : _stock)
    {
        if (level < row.minLevel || level > row.maxLevel)
            continue;

        auto itr = bought.find(row.id);
        uint32 const boughtCount = itr != bought.end() ? itr->second : 0;
        // QT\tid\tcategory\titem\tcount\tservice\tcost\tguildLevel\tlimit\tbought\tstate
        GspeAddonComm::Send(player, Acore::StringFormat("QT\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}",
            row.id, uint32(row.category), row.item, row.count, uint32(row.service), row.cost, uint32(row.guildLevel),
            row.charLimit, boughtCount, uint32(RowState(player, row, guildLevel))));
    }
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

    if (!sGuildProgressMgr->SpendSupplies(guildId, row->cost))
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
