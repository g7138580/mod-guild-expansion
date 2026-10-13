/*
 * mod-guild-expansion: configuration loader.
 */

#include "GspeConfig.h"
#include "Config.h"

#include <algorithm>

GspeConfig* GspeConfig::instance()
{
    static GspeConfig inst;
    return &inst;
}

void GspeConfig::Load()
{
    enable = sConfigMgr->GetOption<bool>("GuildExpansion.Enable", true);
    addonSync = sConfigMgr->GetOption<bool>("GuildExpansion.AddonSync", true);
    ignoreHeadlessPlayers = sConfigMgr->GetOption<bool>("GuildExpansion.IgnoreHeadlessPlayers", true);

    levelCurveMultiplier = std::max(0.01f, sConfigMgr->GetOption<float>("GuildExpansion.LevelCurveMultiplier", 0.35f));
    xpKillPct = std::max(0.0f, sConfigMgr->GetOption<float>("GuildExpansion.Xp.KillPct", 0.08f));
    xpQuestPct = std::max(0.0f, sConfigMgr->GetOption<float>("GuildExpansion.Xp.QuestPct", 0.06f));
    xpKillFlat = sConfigMgr->GetOption<uint32>("GuildExpansion.Xp.KillFlat", 8);
    xpExploreFlat = sConfigMgr->GetOption<uint32>("GuildExpansion.Xp.ExploreFlat", 35);
    xpMaxLevelQuests = sConfigMgr->GetOption<bool>("GuildExpansion.Xp.MaxLevelQuests", true);
    dailyXpCap = sConfigMgr->GetOption<uint32>("GuildExpansion.Xp.DailyCap", 0);
    weeklyXpCap = sConfigMgr->GetOption<uint32>("GuildExpansion.Xp.WeeklyCap", 0);

    cashFlowPct1 = std::clamp(sConfigMgr->GetOption<float>("GuildExpansion.CashFlowPct1", 0.05f), 0.0f, 1.0f);
    cashFlowPct2 = std::clamp(sConfigMgr->GetOption<float>("GuildExpansion.CashFlowPct2", 0.10f), 0.0f, 1.0f);
    hastyHearthReductionMs = sConfigMgr->GetOption<uint32>("GuildExpansion.HastyHearthReductionMs", 900000);
    repairDiscount1 = std::clamp(sConfigMgr->GetOption<float>("GuildExpansion.RepairDiscount1", 0.10f), 0.0f, 1.0f);
    repairDiscount2 = std::clamp(sConfigMgr->GetOption<float>("GuildExpansion.RepairDiscount2", 0.20f), 0.0f, 1.0f);
    chugALugPct1 = std::max(0.0f, sConfigMgr->GetOption<float>("GuildExpansion.ChugALugPct1", 0.50f));
    chugALugPct2 = std::max(0.0f, sConfigMgr->GetOption<float>("GuildExpansion.ChugALugPct2", 1.00f));
    mountUpSpellId = sConfigMgr->GetOption<uint32>("GuildExpansion.MountUpSpellId", 80000011);
    mobileBankingSpellId = sConfigMgr->GetOption<uint32>("GuildExpansion.MobileBankingSpellId", 80000012);
    quickAndTheDeadSpellId = sConfigMgr->GetOption<uint32>("GuildExpansion.QuickAndTheDeadSpellId", 80000014);
    mobileBankingGameObject = sConfigMgr->GetOption<uint32>("GuildExpansion.MobileBankingGameObjectEntry", 80000020);
    mobileBankingDurationMs = std::max<uint32>(1000, sConfigMgr->GetOption<uint32>("GuildExpansion.MobileBankingDurationMs", 60000));

    workOrdersEnable = sConfigMgr->GetOption<bool>("GuildExpansion.WorkOrders.Enable", true);
    workOrderCount = std::clamp<uint32>(sConfigMgr->GetOption<uint32>("GuildExpansion.WorkOrders.Count", 3), 1, 6);
    workOrderDurationHours = std::max<uint32>(1, sConfigMgr->GetOption<uint32>("GuildExpansion.WorkOrders.DurationHours", 24));
    workOrderGoldPerLevelSquared = std::max(0.0f, sConfigMgr->GetOption<float>("GuildExpansion.WorkOrders.Gold.PerLevelSquared", 25.0f));
    workOrderGoldValueMultiplier = std::max(0.0f, sConfigMgr->GetOption<float>("GuildExpansion.WorkOrders.Gold.ValueMultiplier", 3.0f));
    workOrderGuildXpPerLevel = sConfigMgr->GetOption<uint32>("GuildExpansion.WorkOrders.GuildXpPerLevel", 100);
    workOrderSuppliesBase = std::max(0.0f, sConfigMgr->GetOption<float>("GuildExpansion.WorkOrders.SuppliesBase", 10.0f));
    workOrderSuppliesPerLevel = std::max(0.0f, sConfigMgr->GetOption<float>("GuildExpansion.WorkOrders.SuppliesPerLevel", 0.5f));

    unitsEnable = sConfigMgr->GetOption<bool>("GuildExpansion.Units.Enable", true);
    recruitCandidates = std::clamp<uint32>(sConfigMgr->GetOption<uint32>("GuildExpansion.Units.RecruitCandidates", 3), 1, 6);
    recruitCostUncommon = sConfigMgr->GetOption<uint32>("GuildExpansion.Units.RecruitCost.Uncommon", 150);
    recruitCostRare = sConfigMgr->GetOption<uint32>("GuildExpansion.Units.RecruitCost.Rare", 250);
    recruitCostEpic = sConfigMgr->GetOption<uint32>("GuildExpansion.Units.RecruitCost.Epic", 400);
    recruitRareChance = std::min<uint32>(100, sConfigMgr->GetOption<uint32>("GuildExpansion.Units.RareChance", 18));
    recruitEpicChance = std::min<uint32>(100, sConfigMgr->GetOption<uint32>("GuildExpansion.Units.EpicChance", 2));

    missionsEnable = sConfigMgr->GetOption<bool>("GuildExpansion.Missions.Enable", true);
    missionBoardSize = std::clamp<uint32>(sConfigMgr->GetOption<uint32>("GuildExpansion.Missions.BoardSize", 6), 1, 10);
    missionCostMultiplier = std::max(0.0f, sConfigMgr->GetOption<float>("GuildExpansion.Missions.CostMultiplier", 1.0f));
    missionGoldMultiplier = std::max(0.0f, sConfigMgr->GetOption<float>("GuildExpansion.Missions.GoldMultiplier", 1.0f));
    missionGuildXpMultiplier = std::max(0.0f, sConfigMgr->GetOption<float>("GuildExpansion.Missions.GuildXpMultiplier", 1.0f));
    missionUnitXpMultiplier = std::max(0.0f, sConfigMgr->GetOption<float>("GuildExpansion.Missions.UnitXpMultiplier", 1.0f));
    missionEffectChance = std::min<uint32>(100, sConfigMgr->GetOption<uint32>("GuildExpansion.Missions.EffectChance", 25));
    missionRareChance = std::min<uint32>(100, sConfigMgr->GetOption<uint32>("GuildExpansion.Missions.RareChance", 10));
    missionSalvageChance = std::min<uint32>(100, sConfigMgr->GetOption<uint32>("GuildExpansion.Missions.SalvageChance", 15));
    consumableBonus = sConfigMgr->GetOption<uint32>("GuildExpansion.Missions.ConsumableBonus", 10);
    flaskBonus = sConfigMgr->GetOption<uint32>("GuildExpansion.Missions.FlaskBonus", 20);
    troopCost = sConfigMgr->GetOption<uint32>("GuildExpansion.Units.TroopCost", 40);
}
