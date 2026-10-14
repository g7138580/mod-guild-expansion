/*
 * mod-guild-expansion: world, guild, player and spell hooks.
 */

#include "GspeAddonComm.h"
#include "GspeConfig.h"
#include "GspeMissions.h"
#include "GspePerks.h"
#include "GspeProgress.h"
#include "GspeUnits.h"
#include "GspeWorkOrders.h"

#include "Creature.h"
#include "DatabaseEnv.h"
#include "Group.h"
#include "Guild.h"
#include "GuildMgr.h"
#include "Player.h"
#include "ScriptDefines/AllSpellScript.h"
#include "ScriptDefines/GuildScript.h"
#include "ScriptDefines/PlayerScript.h"
#include "ScriptDefines/WorldScript.h"
#include "ScriptMgr.h"
#include "SpellAuras.h"
#include "SpellMgr.h"
#include "SpellScript.h"
#include "SpellScriptLoader.h"
#include "StringConvert.h"
#include "Tokenize.h"
#include "World.h"

#include <algorithm>
#include <cmath>
#include <string_view>
#include <unordered_map>
#include <unordered_set>

namespace
{
using PlayerKey = ObjectGuid::LowType;

constexpr uint32 SPELL_HEARTHSTONE = 8690;

std::unordered_map<PlayerKey, uint32> sPendingCashFlowLoot;
std::unordered_map<PlayerKey, uint8> sPendingReinforceRestore;
std::unordered_set<PlayerKey> sWorkingOvertimeGuard;
std::unordered_set<PlayerKey> sPendingHastyHearth;

PlayerKey GetPlayerKey(Player const* player)
{
    return player ? player->GetGUID().GetCounter() : 0;
}

uint8 GuildLevelOf(Player const* player)
{
    if (!sGspeConfig->enable || !player || !player->GetGuildId())
        return 0;
    return sGuildProgressMgr->GetLevel(player->GetGuildId());
}

bool InGuildGroup(Player const* player)
{
    Group const* grp = player->GetGroup();
    if (!grp || !player->GetGuildId())
        return false;

    for (GroupReference const* ref = grp->GetFirstMember(); ref; ref = ref->next())
    {
        Player const* m = ref->GetSource();
        if (m && m != player && m->GetGuildId() == player->GetGuildId())
            return true;
    }
    return false;
}

bool ShouldBoostReputation(ReputationSource source)
{
    switch (source)
    {
        case REPUTATION_SOURCE_KILL:
        case REPUTATION_SOURCE_QUEST:
        case REPUTATION_SOURCE_DAILY_QUEST:
        case REPUTATION_SOURCE_WEEKLY_QUEST:
        case REPUTATION_SOURCE_MONTHLY_QUEST:
        case REPUTATION_SOURCE_REPEATABLE_QUEST:
            return true;
        default:
            return false;
    }
}

void QueueCashFlowLoot(Player* player, Loot* loot)
{
    if (!loot || !loot->gold || !player->GetGuildId())
        return;

    ObjectGuid const lootGuid = player->GetLootGUID();
    if (!lootGuid.IsCreatureOrVehicle())
        return;

    Creature* creature = player->GetMap()->GetCreature(lootGuid);
    if (!creature || creature->IsAlive())
        return;

    if (Group* group = player->GetGroup())
    {
        std::vector<Player*> nearby;
        for (GroupReference* itr = group->GetFirstMember(); itr; itr = itr->next())
            if (Player* member = itr->GetSource())
                if (player->IsAtLootRewardDistance(member))
                    nearby.push_back(member);

        if (nearby.empty())
            return;

        uint32 const share = loot->gold / nearby.size();
        if (share)
            for (Player* member : nearby)
                sPendingCashFlowLoot[GetPlayerKey(member)] += share;
        return;
    }

    sPendingCashFlowLoot[GetPlayerKey(player)] += loot->gold;
}

void ApplyCashFlow(Player* player, uint32 lootedCopper)
{
    uint8 const level = GuildLevelOf(player);
    float const pct = GspePerks::Has(level, GspePerks::CASH_FLOW_2) ? sGspeConfig->cashFlowPct2
                    : GspePerks::Has(level, GspePerks::CASH_FLOW_1) ? sGspeConfig->cashFlowPct1 : 0.0f;
    if (pct <= 0.0f)
        return;

    Guild* guild = sGuildMgr->GetGuildById(player->GetGuildId());
    if (!guild)
        return;

    uint64 const bankMoney = guild->GetTotalBankMoney();
    if (bankMoney >= GUILD_BANK_MONEY_LIMIT)
        return;

    uint32 const deposit = uint32(std::min<uint64>(uint64(std::floor(double(lootedCopper) * pct)),
                                                   GUILD_BANK_MONEY_LIMIT - bankMoney));
    if (!deposit)
        return;

    CharacterDatabaseTransaction trans = CharacterDatabase.BeginTransaction();
    if (guild->ModifyBankMoney(trans, deposit, true))
        CharacterDatabase.CommitTransaction(trans);
}

void QueueReinforceRestore(Player* player)
{
    uint8 const level = GuildLevelOf(player);
    if (GspePerks::Has(level, GspePerks::REINFORCE))
        sPendingReinforceRestore[GetPlayerKey(player)] = level;
}

void ApplyReinforceRestore(Player* player)
{
    auto itr = sPendingReinforceRestore.find(GetPlayerKey(player));
    if (itr == sPendingReinforceRestore.end())
        return;

    uint8 const level = itr->second;
    sPendingReinforceRestore.erase(itr);

    if (player->HasPreventDurabilityLossAura())
        return;

    double const lossPct = sWorld->getRate(RATE_DURABILITY_LOSS_ON_DEATH) / 100.0;
    if (lossPct <= 0.0)
        return;

    for (uint8 slot = EQUIPMENT_SLOT_START; slot < EQUIPMENT_SLOT_END; ++slot)
    {
        Item* item = player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot);
        if (!item)
            continue;

        uint32 const maxDurability = item->GetUInt32Value(ITEM_FIELD_MAXDURABILITY);
        if (!maxDurability)
            continue;

        uint32 const lost = std::max<uint32>(1, uint32(maxDurability * lossPct));
        int32 const restore = int32(GspePerks::ReinforceRestorePoints(level, lost));
        if (restore > 0)
            player->DurabilityPointsLoss(item, -restore);
    }
}

SpellCastResult CheckMobileBanking(Player* player)
{
    if (!player || !player->GetGuildId())
        return SPELL_FAILED_CANT_DO_THAT_RIGHT_NOW;
    if (!player->IsAlive())
        return SPELL_FAILED_CASTER_DEAD;
    if (player->IsInCombat())
        return SPELL_FAILED_AFFECTING_COMBAT;
    if (!GspePerks::Has(GuildLevelOf(player), GspePerks::MOBILE_BANKING) || !sGspeConfig->mobileBankingGameObject)
        return SPELL_FAILED_SPELL_UNAVAILABLE;
    return SPELL_CAST_OK;
}

// Mobile Banking exists only in the server's spell_dbc, so the client cannot cast it;
// the add-on asks the server to cast it on the player's behalf.
void HandleUseMobileBanking(Player* player)
{
    uint32 const spellId = sGspeConfig->mobileBankingSpellId;
    if (!spellId || !sSpellMgr->GetSpellInfo(spellId))
    {
        GspeAddonComm::SendError(player, "Mobile Banking is not configured on this server.");
        return;
    }

    SpellCastResult result = CheckMobileBanking(player);
    if (result == SPELL_CAST_OK)
        result = player->CastSpell(player, spellId, false);

    switch (result)
    {
        case SPELL_CAST_OK:
            break;
        case SPELL_FAILED_CASTER_DEAD:
            GspeAddonComm::SendError(player, "You can't do that while dead.");
            break;
        case SPELL_FAILED_AFFECTING_COMBAT:
            GspeAddonComm::SendError(player, "You can't do that while in combat.");
            break;
        case SPELL_FAILED_SPELL_UNAVAILABLE:
            GspeAddonComm::SendError(player, "Your guild has not unlocked Mobile Banking yet.");
            break;
        default:
            GspeAddonComm::SendError(player, "You can't do that right now.");
            break;
    }
}

template <typename T>
T ArgAt(std::vector<std::string_view> const& args, std::size_t index)
{
    if (index >= args.size())
        return T(0);
    return Acore::StringTo<T>(args[index]).value_or(T(0));
}

// Requests from the add-on, after "GSPE\t". Arguments are space separated.
void Dispatch(Player* player, std::string_view request)
{
    std::vector<std::string_view> const args = Acore::Tokenize(request, ' ', false);
    if (args.empty())
        return;

    std::string_view const cmd = args[0];
    if (cmd == "PULL")
    {
        GspeAddonComm::SendState(player);
        sWorkOrderMgr->SendOrders(player);
    }
    else if (cmd == "STATE")
        GspeAddonComm::SendState(player);
    else if (cmd == "WO")
        sWorkOrderMgr->SendOrders(player);
    else if (cmd == "PLACE")
        sWorkOrderMgr->HandlePlace(player, ArgAt<uint32>(args, 1), ArgAt<uint8>(args, 2), ArgAt<uint8>(args, 3));
    else if (cmd == "CLEAR")
        sWorkOrderMgr->HandleClear(player, ArgAt<uint32>(args, 1));
    else if (cmd == "FILL")
        sWorkOrderMgr->HandleFill(player, ArgAt<uint32>(args, 1));
    else if (cmd == "TURNIN")
        sWorkOrderMgr->HandleTurnIn(player, ArgAt<uint32>(args, 1));
    else if (cmd == "ABANDON")
        sWorkOrderMgr->HandleAbandon(player, ArgAt<uint32>(args, 1));
    else if (cmd == "USE" && args.size() > 1 && args[1] == "BANK")
        HandleUseMobileBanking(player);
    else if (cmd == "UTPL")
        sUnitMgr->SendTemplates(player);
    else if (cmd == "UNITS")
        sUnitMgr->SendUnits(player);
    else if (cmd == "RECRUIT")
        sUnitMgr->HandleRecruit(player, ArgAt<uint32>(args, 1));
    else if (cmd == "DISMISS")
        sUnitMgr->HandleDismiss(player, ArgAt<uint32>(args, 1));
    else if (cmd == "MTPL")
        sMissionMgr->SendTemplates(player);
    else if (cmd == "MISSIONS")
        sMissionMgr->SendBoard(player);
    else if (cmd == "MPREVIEW" || cmd == "MSTART")
    {
        // MSTART <mission> [C<bag>.<slot>] <unit> <unit> ...
        std::vector<uint32> unitIds;
        MissionConsumable consumable;
        for (std::size_t i = 2; i < args.size() && unitIds.size() < MAX_MISSION_UNITS + 1; ++i)
        {
            std::string_view const arg = args[i];
            if (!arg.empty() && arg[0] == 'C')
            {
                std::vector<std::string_view> const pos = Acore::Tokenize(arg.substr(1), '.', false);
                if (pos.size() == 2)
                {
                    consumable.set = true;
                    consumable.bag = Acore::StringTo<uint8>(pos[0]).value_or(0);
                    consumable.slot = Acore::StringTo<uint8>(pos[1]).value_or(0);
                }
            }
            else if (uint32 id = ArgAt<uint32>(args, i))
                unitIds.push_back(id);
        }

        if (cmd == "MPREVIEW")
            sMissionMgr->HandlePreview(player, ArgAt<uint32>(args, 1), unitIds, consumable);
        else
            sMissionMgr->HandleStart(player, ArgAt<uint32>(args, 1), unitIds, consumable);
    }
    else if (cmd == "TROOP")
        sUnitMgr->HandleTrainTroop(player, ArgAt<uint16>(args, 1));
    else if (cmd == "EQUIP" && args.size() >= 5)
    {
        // EQUIP <unit> <W|A|E> <bag> <slot>
        uint8 const gearSlot = args[2] == "W" ? UNIT_GEAR_WEAPON : args[2] == "A" ? UNIT_GEAR_ARMOR : UNIT_GEAR_EFFECT;
        sUnitMgr->HandleEquip(player, ArgAt<uint32>(args, 1), gearSlot, ArgAt<uint8>(args, 3), ArgAt<uint8>(args, 4));
    }
    else if (cmd == "MCOLLECT")
        sMissionMgr->HandleCollect(player, ArgAt<uint32>(args, 1));
}
} // namespace

class Gspe_WorldScript : public WorldScript
{
public:
    Gspe_WorldScript() : WorldScript("Gspe_WorldScript",
        { WORLDHOOK_ON_AFTER_CONFIG_LOAD, WORLDHOOK_ON_STARTUP, WORLDHOOK_ON_UPDATE }) { }

    void OnAfterConfigLoad(bool /*reload*/) override
    {
        sGspeConfig->Load();
    }

    void OnStartup() override
    {
        sGuildProgressMgr->MigrateFromGuildLevels();
        sWorkOrderMgr->BuildCatalog();
        sUnitMgr->LoadTemplates();
        sMissionMgr->Load();
    }

    void OnUpdate(uint32 diff) override
    {
        _flushTimer += diff;
        if (_flushTimer < 1000)
            return;

        _flushTimer = 0;
        sGuildProgressMgr->FlushPendingAddonPushes();

        if (++_missionTicks >= 5)
        {
            _missionTicks = 0;
            sMissionMgr->Update();
        }
    }

private:
    uint32 _flushTimer = 0;
    uint32 _missionTicks = 0;
};

class Gspe_GuildScript : public GuildScript
{
public:
    Gspe_GuildScript() : GuildScript("Gspe_GuildScript",
        { GUILDHOOK_ON_DISBAND, GUILDHOOK_ON_ADD_MEMBER, GUILDHOOK_ON_REMOVE_MEMBER }) { }

    void OnDisband(Guild* guild) override
    {
        if (!guild)
            return;
        sGuildProgressMgr->DeleteProgress(guild->GetId());
        sUnitMgr->OnGuildDisband(guild->GetId());
        sMissionMgr->OnGuildDisband(guild->GetId());
    }

    void OnAddMember(Guild* /*guild*/, Player* player, uint8& /*plRank*/) override
    {
        if (!player || !sGspeConfig->enable)
            return;
        sGuildProgressMgr->RefreshPlayerPerks(player);
        GspeAddonComm::SendState(player);
    }

    void OnRemoveMember(Guild* /*guild*/, Player* player, bool /*isDisbanding*/, bool /*isKicked*/) override
    {
        if (!player)
            return;
        sGuildProgressMgr->ClearGuildPerks(player);
        GspeAddonComm::SendClear(player);
    }
};

class Gspe_PlayerScript : public PlayerScript
{
public:
    Gspe_PlayerScript() : PlayerScript("Gspe_PlayerScript",
        { PLAYERHOOK_ON_PLAYER_JUST_DIED, PLAYERHOOK_ON_PVP_KILL, PLAYERHOOK_ON_PLAYER_KILLED_BY_CREATURE,
          PLAYERHOOK_ON_MONEY_CHANGED, PLAYERHOOK_ON_BEFORE_LOOT_MONEY, PLAYERHOOK_ON_GIVE_EXP,
          PLAYERHOOK_ON_GIVE_REPUTATION, PLAYERHOOK_ON_LOGIN, PLAYERHOOK_ON_LOGOUT, PLAYERHOOK_ON_UPDATE_SKILL,
          PLAYERHOOK_ON_VICTIM_REWARD_AFTER, PLAYERHOOK_CAN_PLAYER_USE_PRIVATE_CHAT, PLAYERHOOK_ON_SPELL_CAST,
          PLAYERHOOK_ON_UPDATE, PLAYERHOOK_ON_PLAYER_RELEASED_GHOST, PLAYERHOOK_ON_PLAYER_RESURRECT,
          PLAYERHOOK_ON_BEFORE_DURABILITY_REPAIR, PLAYERHOOK_ON_QUEST_COMPUTE_EXP }) { }

    void OnPlayerLogin(Player* player) override
    {
        if (!sGspeConfig->enable)
            return;

        if (player->GetGuildId())
            sGuildProgressMgr->RefreshPlayerPerks(player);
        else
            sGuildProgressMgr->ClearGuildPerks(player);

        GspeAddonComm::SendState(player);
    }

    void OnPlayerLogout(Player* player) override
    {
        PlayerKey const key = GetPlayerKey(player);
        sPendingCashFlowLoot.erase(key);
        sPendingReinforceRestore.erase(key);
        sWorkingOvertimeGuard.erase(key);
        sPendingHastyHearth.erase(key);
        sWorkOrderMgr->OnLogout(player);
    }

    // The add-on whispers itself; swallow those messages so they never show up as chat.
    bool OnPlayerCanUseChat(Player* player, uint32 /*type*/, uint32 lang, std::string& msg, Player* receiver) override
    {
        if (lang != LANG_ADDON || receiver != player)
            return true;

        static constexpr std::string_view header = "GSPE\t";
        if (msg.compare(0, header.size(), header) != 0)
            return true;

        if (!sGspeConfig->enable)
            GspeAddonComm::SendClear(player);
        else
            Dispatch(player, std::string_view(msg).substr(header.size()));
        return false;
    }

    void OnPlayerGiveXP(Player* player, uint32& amount, Unit* /*victim*/, uint8 xpSource) override
    {
        if (!sGspeConfig->enable || !player->GetGuildId() || !amount)
            return;

        uint8 const level = GuildLevelOf(player);
        uint32 contrib = 0;
        switch (xpSource)
        {
            case XPSOURCE_KILL:
                amount = uint32(float(amount) * GspePerks::XpMultiplier(level));
                contrib = uint32(float(amount) * sGspeConfig->xpKillPct) + sGspeConfig->xpKillFlat;
                break;
            case XPSOURCE_QUEST:
            case XPSOURCE_QUEST_DF:
                amount = uint32(float(amount) * GspePerks::XpMultiplier(level));
                contrib = uint32(float(amount) * sGspeConfig->xpQuestPct);
                break;
            case XPSOURCE_EXPLORE:
                contrib = sGspeConfig->xpExploreFlat;
                break;
            default:
                break;
        }

        if (!contrib)
            return;

        if (InGuildGroup(player))
            contrib = uint32(float(contrib) * 1.25f);

        sGuildProgressMgr->AddGuildXP(player->GetGuildId(), contrib, player);
    }

    // At max level quests pay money instead of XP, so OnPlayerGiveXP never runs for them.
    void OnPlayerQuestComputeXP(Player* player, Quest const* /*quest*/, uint32& xpValue) override
    {
        if (!sGspeConfig->enable || !sGspeConfig->xpMaxLevelQuests || !xpValue || !player->GetGuildId())
            return;
        if (player->GetLevel() < sWorld->getIntConfig(CONFIG_MAX_PLAYER_LEVEL))
            return;

        if (uint32 const contrib = uint32(float(xpValue) * sGspeConfig->xpQuestPct))
            sGuildProgressMgr->AddGuildXP(player->GetGuildId(), contrib, player);
    }

    void OnPlayerGiveReputation(Player* player, int32 /*factionId*/, float& amount, ReputationSource repSource) override
    {
        if (amount <= 0.f || !ShouldBoostReputation(repSource))
            return;

        float const m = GspePerks::ReputationMultiplier(GuildLevelOf(player));
        if (m > 1.0001f)
            amount *= m;
    }

    void OnPlayerVictimRewardAfter(Player* player, Player* /*victim*/, uint32& /*killer_title*/,
                                   int32& /*victim_rank*/, float& honor_f) override
    {
        if (honor_f > 0.f)
            honor_f *= GspePerks::HonorMultiplier(GuildLevelOf(player));
    }

    void OnPlayerBeforeLootMoney(Player* player, Loot* loot) override
    {
        if (sGspeConfig->enable)
            QueueCashFlowLoot(player, loot);
    }

    void OnPlayerMoneyChanged(Player* player, int32& amount) override
    {
        if (amount <= 0)
            return;

        auto itr = sPendingCashFlowLoot.find(GetPlayerKey(player));
        if (itr == sPendingCashFlowLoot.end())
            return;

        uint32 const looted = std::min<uint32>(itr->second, uint32(amount));
        itr->second -= looted;
        if (!itr->second)
            sPendingCashFlowLoot.erase(itr);

        if (looted)
            ApplyCashFlow(player, looted);
    }

    void OnPlayerPVPKill(Player* /*killer*/, Player* killed) override
    {
        if (killed && sWorld->getBoolConfig(CONFIG_DURABILITY_LOSS_IN_PVP))
            QueueReinforceRestore(killed);
    }

    void OnPlayerKilledByCreature(Creature* /*killer*/, Player* killed) override
    {
        if (killed && !killed->InBattleground())
            QueueReinforceRestore(killed);
    }

    void OnPlayerJustDied(Player* player) override
    {
        ApplyReinforceRestore(player);
    }

    void OnPlayerReleasedGhost(Player* player) override
    {
        uint32 const spellId = sGspeConfig->quickAndTheDeadSpellId;
        if (spellId && sSpellMgr->GetSpellInfo(spellId)
            && GspePerks::Has(GuildLevelOf(player), GspePerks::QUICK_AND_DEAD))
            player->AddAura(spellId, player);
    }

    void OnPlayerResurrect(Player* player, float /*restorePercent*/, bool& /*applySickness*/) override
    {
        if (uint32 const spellId = sGspeConfig->quickAndTheDeadSpellId)
            player->RemoveAurasDueToSpell(spellId);

        if (!GspePerks::Has(GuildLevelOf(player), GspePerks::QUICK_AND_DEAD))
            return;

        player->SetHealth(player->GetMaxHealth());
        if (player->getPowerType() == POWER_MANA)
            player->SetPower(POWER_MANA, player->GetMaxPower(POWER_MANA));
    }

    void OnPlayerBeforeDurabilityRepair(Player* player, ObjectGuid /*npcGUID*/, ObjectGuid /*itemGUID*/,
                                        float& discountMod, uint8 /*guildBank*/) override
    {
        uint8 const level = GuildLevelOf(player);
        if (GspePerks::Has(level, GspePerks::REPAIR_DISCOUNT_2))
            discountMod *= 1.0f - sGspeConfig->repairDiscount2;
        else if (GspePerks::Has(level, GspePerks::REPAIR_DISCOUNT_1))
            discountMod *= 1.0f - sGspeConfig->repairDiscount1;
    }

    // Hasty Hearth: the cooldown is set after this hook, so shorten it on the next update.
    void OnPlayerSpellCast(Player* player, Spell* spell, bool /*skipCheck*/) override
    {
        if (spell->GetSpellInfo()->Id == SPELL_HEARTHSTONE && sGspeConfig->hastyHearthReductionMs
            && GspePerks::Has(GuildLevelOf(player), GspePerks::HASTY_HEARTH))
            sPendingHastyHearth.insert(GetPlayerKey(player));
    }

    void OnPlayerUpdate(Player* player, uint32 /*diff*/) override
    {
        if (sPendingHastyHearth.empty() || !sPendingHastyHearth.erase(GetPlayerKey(player)))
            return;

        player->ModifySpellCooldown(SPELL_HEARTHSTONE, -int32(sGspeConfig->hastyHearthReductionMs));
    }

    void OnPlayerUpdateSkill(Player* player, uint32 skillId, uint32 /*value*/, uint32 max, uint32 step,
                             uint32 newValue) override
    {
        if (!step || !IsProfessionSkill(skillId))
            return;

        PlayerKey const key = GetPlayerKey(player);
        if (sWorkingOvertimeGuard.erase(key))
            return;

        if (!GspePerks::Has(GuildLevelOf(player), GspePerks::WORKING_OVERTIME))
            return;

        if (newValue >= max || urand(1, 100) > 10)
            return;

        sWorkingOvertimeGuard.insert(key);
        player->UpdateSkill(skillId, step);
    }
};

// Chug-A-Lug: longer elixirs and flasks.
class Gspe_AllSpellScript : public AllSpellScript
{
public:
    Gspe_AllSpellScript() : AllSpellScript("Gspe_AllSpellScript", { ALLSPELLHOOK_ON_CALC_MAX_DURATION }) { }

    void OnCalcMaxDuration(Aura const* aura, int32& maxDuration) override
    {
        if (maxDuration <= 0 || !sGspeConfig->enable)
            return;

        uint32 const spellId = aura->GetId();
        if (!sSpellMgr->IsSpellMemberOfSpellGroup(spellId, SPELL_GROUP_ELIXIR_BATTLE)
            && !sSpellMgr->IsSpellMemberOfSpellGroup(spellId, SPELL_GROUP_ELIXIR_GUARDIAN))
            return;

        Unit* caster = aura->GetCaster();
        Player* player = caster ? caster->ToPlayer() : nullptr;
        if (!player || aura->GetOwner() != player)
            return;

        uint8 const level = GuildLevelOf(player);
        float const pct = GspePerks::Has(level, GspePerks::CHUG_A_LUG_2) ? sGspeConfig->chugALugPct2
                        : GspePerks::Has(level, GspePerks::CHUG_A_LUG_1) ? sGspeConfig->chugALugPct1 : 0.0f;
        if (pct > 0.0f)
            maxDuration = int32(float(maxDuration) * (1.0f + pct));
    }
};

class spell_gspe_mobile_banking : public SpellScript
{
    PrepareSpellScript(spell_gspe_mobile_banking);

    SpellCastResult CheckCast()
    {
        return CheckMobileBanking(GetCaster() ? GetCaster()->ToPlayer() : nullptr);
    }

    void HandleAfterCast()
    {
        Player* player = GetCaster() ? GetCaster()->ToPlayer() : nullptr;
        if (!player)
            return;

        float const distance = 2.5f;
        float const o = player->GetOrientation();
        player->SummonGameObject(sGspeConfig->mobileBankingGameObject,
            player->GetPositionX() + distance * std::cos(o), player->GetPositionY() + distance * std::sin(o),
            player->GetPositionZ(), o, 0.0f, 0.0f, 0.0f, 0.0f, sGspeConfig->mobileBankingDurationMs);
    }

    void Register() override
    {
        OnCheckCast += SpellCheckCastFn(spell_gspe_mobile_banking::CheckCast);
        AfterCast += SpellCastFn(spell_gspe_mobile_banking::HandleAfterCast);
    }
};

void AddSC_gspe_scripts()
{
    new Gspe_WorldScript();
    new Gspe_GuildScript();
    new Gspe_PlayerScript();
    new Gspe_AllSpellScript();
    RegisterSpellScript(spell_gspe_mobile_banking);
}
