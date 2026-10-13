/*
 * mod-guild-expansion: configuration.
 */

#ifndef MOD_GSPE_CONFIG_H_
#define MOD_GSPE_CONFIG_H_

#include "Define.h"

struct GspeConfig
{
    static GspeConfig* instance();

    void Load();

    bool enable = true;
    bool addonSync = true;
    bool ignoreHeadlessPlayers = true;

    // Guild XP
    float levelCurveMultiplier = 0.35f;
    float xpKillPct = 0.08f;
    float xpQuestPct = 0.06f;
    uint32 xpKillFlat = 8;
    uint32 xpExploreFlat = 35;
    bool xpMaxLevelQuests = true;
    uint32 dailyXpCap = 0;
    uint32 weeklyXpCap = 0;

    // Perks
    float cashFlowPct1 = 0.05f;
    float cashFlowPct2 = 0.10f;
    uint32 hastyHearthReductionMs = 900000;
    float repairDiscount1 = 0.10f;
    float repairDiscount2 = 0.20f;
    float chugALugPct1 = 0.50f;
    float chugALugPct2 = 1.00f;
    uint32 mountUpSpellId = 80000011;
    uint32 mobileBankingSpellId = 80000012;
    uint32 quickAndTheDeadSpellId = 80000014;
    uint32 mobileBankingGameObject = 80000020;
    uint32 mobileBankingDurationMs = 60000;

    // Work orders
    bool workOrdersEnable = true;
    uint32 workOrderCount = 3;
    uint32 workOrderDurationHours = 24;
    float workOrderGoldPerLevelSquared = 25.0f;
    float workOrderGoldValueMultiplier = 3.0f;
    uint32 workOrderGuildXpPerLevel = 100;
    float workOrderSuppliesBase = 10.0f;
    float workOrderSuppliesPerLevel = 0.5f;

    // Units
    bool unitsEnable = true;
    uint32 recruitCandidates = 3;
    uint32 recruitCostUncommon = 150;
    uint32 recruitCostRare = 250;
    uint32 recruitCostEpic = 400;
    uint32 recruitRareChance = 18;   // percent
    uint32 recruitEpicChance = 2;    // percent

    // Missions
    bool missionsEnable = true;
    uint32 missionBoardSize = 6;
    float missionCostMultiplier = 1.0f;
    float missionGoldMultiplier = 1.0f;
    float missionGuildXpMultiplier = 1.0f;
    float missionUnitXpMultiplier = 1.0f;
};

#define sGspeConfig GspeConfig::instance()

#endif
