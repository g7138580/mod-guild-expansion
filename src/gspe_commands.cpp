/*
 * mod-guild-expansion: GM commands (.gspe).
 */

#include "GspeConfig.h"
#include "GspeContracts.h"
#include "GspeMissions.h"
#include "GspeProgress.h"
#include "GspeUnits.h"
#include "GspeWorkOrders.h"

#include "Chat.h"
#include "ChatCommand.h"
#include "Player.h"
#include "ScriptMgr.h"
#include "StringFormat.h"

using namespace Acore::ChatCommands;

namespace
{
// The selected player's guild, else the GM's own.
uint32 ResolveGuildId(ChatHandler* handler)
{
    if (Player* sel = handler->getSelectedPlayer())
        if (sel->GetGuildId())
            return sel->GetGuildId();

    if (Player* self = handler->GetPlayer())
        return self->GetGuildId();

    return 0;
}

uint32 RequireGuild(ChatHandler* handler)
{
    uint32 const gid = ResolveGuildId(handler);
    if (!gid)
        handler->SendSysMessage("GuildExpansion: no guild (select a player in a guild or join one).");
    return gid;
}
} // namespace

class gspe_commandscript : public CommandScript
{
public:
    gspe_commandscript() : CommandScript("gspe_commandscript") { }

    ChatCommandTable GetCommands() const override
    {
        static ChatCommandTable gspeTable =
        {
            { "reload",   HandleReload,   SEC_ADMINISTRATOR, Console::Yes },
            { "info",     HandleInfo,     SEC_GAMEMASTER,    Console::No },
            { "setlevel", HandleSetLevel, SEC_ADMINISTRATOR, Console::No },
            { "setxp",    HandleSetXp,    SEC_ADMINISTRATOR, Console::No },
            { "addxp",    HandleAddXp,    SEC_ADMINISTRATOR, Console::No },
            { "supplies", HandleSupplies, SEC_ADMINISTRATOR, Console::No },
            { "orders",   HandleOrders,   SEC_ADMINISTRATOR, Console::No },
            { "recruits", HandleRecruits, SEC_ADMINISTRATOR, Console::No },
            { "missions", HandleMissions, SEC_ADMINISTRATOR, Console::No },
            { "finish",   HandleFinish,   SEC_ADMINISTRATOR, Console::No },
            { "contracts", HandleContracts, SEC_ADMINISTRATOR, Console::No },
            { "contract", HandleContract, SEC_ADMINISTRATOR, Console::No },
            { "",         HandleInfo,     SEC_GAMEMASTER,    Console::No },
        };

        static ChatCommandTable root = { { "gspe", gspeTable } };
        return root;
    }

    static bool HandleReload(ChatHandler* handler)
    {
        sGspeConfig->Load();
        handler->SendSysMessage("GuildExpansion: configuration reloaded.");
        return true;
    }

    static bool HandleInfo(ChatHandler* handler)
    {
        uint32 const gid = RequireGuild(handler);
        GuildProgressState st{};
        if (!gid || !sGuildProgressMgr->LoadProgress(gid, st))
            return false;

        uint64 const next = st.level >= GuildProgressMgr::MaxGuildLevel()
            ? st.xp : GuildProgressMgr::CumulativeXpForLevel(st.level + 1);
        handler->SendSysMessage(Acore::StringFormat(
            "GuildExpansion: guild {} - level {} - xp {} / {} - supplies {} - today {}",
            gid, uint32(st.level), st.xp, next, st.supplies, st.todayXp));
        return true;
    }

    static bool HandleSetLevel(ChatHandler* handler, uint8 level)
    {
        uint32 const gid = RequireGuild(handler);
        if (!gid)
            return false;
        sGuildProgressMgr->SetGuildLevel(gid, level);
        return HandleInfo(handler);
    }

    static bool HandleSetXp(ChatHandler* handler, uint64 xp)
    {
        uint32 const gid = RequireGuild(handler);
        if (!gid)
            return false;
        sGuildProgressMgr->SetGuildXp(gid, xp);
        return HandleInfo(handler);
    }

    static bool HandleAddXp(ChatHandler* handler, uint32 amount)
    {
        uint32 const gid = RequireGuild(handler);
        if (!gid)
            return false;
        sGuildProgressMgr->AddGuildXP(gid, amount, nullptr);
        return HandleInfo(handler);
    }

    static bool HandleSupplies(ChatHandler* handler, uint32 amount)
    {
        uint32 const gid = RequireGuild(handler);
        if (!gid)
            return false;
        sGuildProgressMgr->SetSupplies(gid, amount);
        return HandleInfo(handler);
    }

    // Replaces the guild's recruit candidates with new ones.
    static bool HandleRecruits(ChatHandler* handler)
    {
        uint32 const gid = RequireGuild(handler);
        if (!gid)
            return false;
        sUnitMgr->RerollCandidates(gid);
        if (Player* self = handler->GetPlayer())
            sUnitMgr->SendUnits(self);
        handler->SendSysMessage("GuildExpansion: new recruit candidates.");
        return true;
    }

    // Replaces the guild's mission board offers with new ones.
    static bool HandleMissions(ChatHandler* handler)
    {
        uint32 const gid = RequireGuild(handler);
        if (!gid)
            return false;
        sMissionMgr->RerollBoard(gid);
        if (Player* self = handler->GetPlayer())
            sMissionMgr->SendBoard(self);
        handler->SendSysMessage("GuildExpansion: new mission board.");
        return true;
    }

    // Completes the guild's running missions now so they can be collected.
    static bool HandleFinish(ChatHandler* handler)
    {
        uint32 const gid = RequireGuild(handler);
        if (!gid)
            return false;
        sMissionMgr->FinishRunning(gid);
        if (Player* self = handler->GetPlayer())
            sMissionMgr->SendBoard(self);
        handler->SendSysMessage("GuildExpansion: running missions finished.");
        return true;
    }

    // Replaces the selected (or own) character's work orders with new ones.
    static bool HandleOrders(ChatHandler* handler)
    {
        Player* target = handler->getSelectedPlayerOrSelf();
        if (!target)
            return false;
        sWorkOrderMgr->ResetOrders(target);
        handler->SendSysMessage(Acore::StringFormat("GuildExpansion: new work orders for {}.", target->GetName()));
        return true;
    }

    // Replaces the selected (or own) character's contracts with new ones.
    static bool HandleContracts(ChatHandler* handler)
    {
        Player* target = handler->getSelectedPlayerOrSelf();
        if (!target)
            return false;
        sContractMgr->ResetContracts(target);
        handler->SendSysMessage(Acore::StringFormat("GuildExpansion: new contracts for {}.", target->GetName()));
        return true;
    }

    // Finishes contract N (1-based) of the selected (or own) character.
    static bool HandleContract(ChatHandler* handler, uint8 number)
    {
        Player* target = handler->getSelectedPlayerOrSelf();
        if (!target || !number)
            return false;
        sContractMgr->FinishContract(target, number - 1);
        return true;
    }
};

void AddSC_gspe_commands()
{
    new gspe_commandscript();
}
