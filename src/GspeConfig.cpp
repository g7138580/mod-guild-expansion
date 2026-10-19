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
    maxGuildLevel = std::clamp<uint32>(sConfigMgr->GetOption<uint32>("GuildExpansion.Levels.Max", 250), 25, 250);
    levelCostAfter25 = sConfigMgr->GetOption<uint32>("GuildExpansion.Levels.CostAfter25", 875000);
    levelCostStep = sConfigMgr->GetOption<uint32>("GuildExpansion.Levels.CostStep", 25000);
    levelSuppliesBase = sConfigMgr->GetOption<uint32>("GuildExpansion.Levels.SuppliesBase", 100);
    levelSuppliesStep = sConfigMgr->GetOption<uint32>("GuildExpansion.Levels.SuppliesStep", 2);
    levelCapstoneSupplies = sConfigMgr->GetOption<uint32>("GuildExpansion.Levels.CapstoneSupplies", 10000);
    advancementResetCostPerPoint = sConfigMgr->GetOption<uint32>("GuildExpansion.Levels.ResetCostPerPoint", 10);
    milestoneChangeCost = sConfigMgr->GetOption<uint32>("GuildExpansion.Levels.MilestoneChangeCost", 500);
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
    workOrderAbandonDelayHours = sConfigMgr->GetOption<uint32>("GuildExpansion.WorkOrders.AbandonDelayHours", 4);
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

    contractsEnable = sConfigMgr->GetOption<bool>("GuildExpansion.Contracts.Enable", true);
    contractCount = std::clamp<uint32>(sConfigMgr->GetOption<uint32>("GuildExpansion.Contracts.Count", 3), 1, 5);
    contractFreeRerolls = sConfigMgr->GetOption<uint32>("GuildExpansion.Contracts.FreeRerolls", 1);
    contractBattlegrounds = sConfigMgr->GetOption<bool>("GuildExpansion.Contracts.Battlegrounds", true);
    contractDungeonBosses = sConfigMgr->GetOption<bool>("GuildExpansion.Contracts.DungeonBosses", true);
    contractSuppliesBase = std::max(0.0f, sConfigMgr->GetOption<float>("GuildExpansion.Contracts.SuppliesBase", 15.0f));
    contractSuppliesPerLevel = std::max(0.0f, sConfigMgr->GetOption<float>("GuildExpansion.Contracts.SuppliesPerLevel", 0.6f));
    contractGuildXpPerLevel = sConfigMgr->GetOption<uint32>("GuildExpansion.Contracts.GuildXpPerLevel", 100);
    contractGoldPerLevelSquared = std::max(0.0f, sConfigMgr->GetOption<float>("GuildExpansion.Contracts.GoldPerLevelSquared", 10.0f));
    contractBonusSuppliesBase = std::max(0.0f, sConfigMgr->GetOption<float>("GuildExpansion.Contracts.BonusSuppliesBase", 20.0f));
    contractBonusSuppliesPerLevel = std::max(0.0f, sConfigMgr->GetOption<float>("GuildExpansion.Contracts.BonusSuppliesPerLevel", 0.5f));

    quartermasterEnable = sConfigMgr->GetOption<bool>("GuildExpansion.Quartermaster.Enable", true);
    quartermasterWeeklyEpicChance = std::min<uint32>(100, sConfigMgr->GetOption<uint32>("GuildExpansion.Quartermaster.WeeklyEpicChance", 15));
    quartermasterCuriosityMountChance = std::min<uint32>(100, sConfigMgr->GetOption<uint32>("GuildExpansion.Quartermaster.CuriosityMountChance", 20));
}
