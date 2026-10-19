--[[
  Guild Expansion: server sync.
  The server whispers LANG_ADDON lines to the player: "GSPE\t<command>\t<fields>".
    STATE\tlevel\txp\tprev\tnext\ttoday\tweek\tdailyCap\tweeklyCap\tsupplies\tmaxLevel\tguildId\tname
    CLEAR | ERROR\ttext
    WOB\tcount\tstatus, WO\t..., WOE    work order list (status 0 ok, 1 no guild, 2 disabled)
    PLACED\torderId\ttotal | DONE\torderId\tgold\tguildXp\tsupplies
    CB\tcount\tstatus\tresetsIn\trerollsLeft\tbonusPaid\tbonusSupplies\tdone, C\t..., CE   contracts
    CP\tslot\tprogress\tneeded\tlabel | CDONE\tslot\tgold\tsupplies\tguildXp\ttitle | CBONUS\tsupplies\titem\tcount
    QB\tstatus\tguildLevel\tweeklyResetsIn, QT\t..., QW\t..., QE   quartermaster stock | QBOUGHT\trowId
  Requests are whispered to ourselves ("GSPE", "<command> <args>"); the server swallows them.
]]

local ADDON_NAME = "GuildExpansion"
local PREFIX = "GSPE"
local PULL_THROTTLE = 2

GuildExpansion = GuildExpansion or {}
local GE = GuildExpansion

GE.MAX_LEVEL = 250      -- replaced by the server's maximum from STATE
GE.PERK_LEVEL = 25      -- last level with perks; later levels give Guild Points
GE.state = nil          -- guild progress, nil when not in a guild
GE.orders = {}          -- work orders, in server order
GE.ordersStatus = 0     -- 0 ok, 1 no guild, 2 disabled
GE.unitTemplates = {}   -- id -> { kind, role, class, icon, name }
GE.units = {}           -- the guild's units
GE.candidates = {}      -- recruit candidates
GE.troops = {}          -- the guild's troops
GE.unitInfo = { count = 0, max = 0, cap = 0, expiresAt = 0, status = 0, troops = 0, maxTroops = 0, troopCost = 0 }
GE.missionTemplates = {} -- id -> { type, slots, roles = {...}, name, desc }
GE.offers = {}          -- missions on the board
GE.running = {}         -- missions in progress
GE.missionInfo = { slots = 0, status = 0 }
GE.chance = nil         -- last success preview: { id, value, countered = set, missing = set }
GE.lastResult = nil     -- last collected mission result
GE.contracts = {}       -- today's contracts, in slot order
GE.contractInfo = { status = 0, resetsAt = 0, rerollsLeft = 0, bonusPaid = false, bonusSupplies = 0, done = 0 }
GE.qmStock = {}         -- quartermaster rows shown to this character
GE.qmInfo = { status = 0, guildLevel = 0, weeklyResetsAt = 0 }
GE.advancement = { status = 0, level = 0, earned = 0, spent = 0, resetCost = 0, canEdit = false, trackMax = 25,
                   changeCost = 0, tracks = {}, milestones = {} }

-- Rank names for the milestones; keep the levels in sync with src/GspeAdvancement.h.
GE.GUILD_RANKS = {
    { lv = 50, name = "Renowned" }, { lv = 75, name = "Distinguished" }, { lv = 100, name = "Honored" },
    { lv = 125, name = "Revered" }, { lv = 150, name = "Exalted" }, { lv = 175, name = "Illustrious" },
    { lv = 200, name = "Heroic" }, { lv = 225, name = "Mythic" }, { lv = 250, name = "Legendary" },
}

-- The highest rank name the guild has reached, or nil below level 50.
function GE.GuildRank(level)
    local rank
    for _, r in ipairs(GE.GUILD_RANKS) do
        if level >= r.lv then
            rank = r.name
        end
    end
    return rank
end
GE.qmWeekly = {}        -- this week's offers, by slot (1-2 gear, 3 material, 4-5 recipes, 6 pet or mount)

local DEFAULT_OPTIONS = {
    xpText = true,
    levelAlert = true,
    scale = 1,
    summary = true,             -- "what's ready" row on the Guild tab
    minimapButton = true,
    minimapAngle = 200,
    contractNotice = true,      -- chat line when a new day's contracts arrive
    contractProgress = true,    -- on-screen progress text like quest objectives
    toasts = true,              -- "Mission complete" / "Contract complete" alerts
    guildTab = true,            -- side tab on the Guild frame
}

GE.DEFAULT_KEY = "SHIFT-G"
BINDING_HEADER_GUILDEXPANSION = "Guild Expansion"
BINDING_NAME_GUILDEXPANSION_TOGGLE = "Open or close the Guild Expansion window"

-- The key that opens the window, as the client shows it ("SHIFT-G"), or nil.
function GE.KeyText()
    local key = GetBindingKey("GUILDEXPANSION_TOGGLE")
    return key and GetBindingText(key, "KEY_") or nil
end

local listeners = {}
local pendingOrders
local pendingUnits
local pendingMissions
local pendingContracts
local pendingStock
local pendingTracks
local pendingMilestones
local pendingWeekly
local hadSnapshotThisSession = false
local lastPull = 0

function GE.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffGuild Expansion:|r " .. msg)
end

function GE.FormatNumber(n)
    local formatted, k = tostring(math.floor(n or 0)), 0
    repeat
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
    until k == 0
    return formatted
end

local COIN_ICON = "|TInterface\\MoneyFrame\\UI-%sIcon:%d:%d:2:0|t"

-- Gold/silver/copper with fixed-size coin icons (GetCoinTextureString sizes them to the
-- font, which sits unevenly with replaced fonts such as ElvUI's).
function GE.FormatMoney(copper, iconSize)
    copper = math.floor(copper or 0)
    iconSize = iconSize or 12
    local gold, silver, cop = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if gold > 0 then
        parts[#parts + 1] = gold .. COIN_ICON:format("Gold", iconSize, iconSize)
    end
    if silver > 0 or gold > 0 then
        parts[#parts + 1] = silver .. COIN_ICON:format("Silver", iconSize, iconSize)
    end
    parts[#parts + 1] = cop .. COIN_ICON:format("Copper", iconSize, iconSize)
    return table.concat(parts, " ")
end

-- fn(event): event is "state" or "orders".
function GE.RegisterListener(fn)
    listeners[#listeners + 1] = fn
end

local function Fire(event)
    for i = 1, #listeners do
        listeners[i](event)
    end
end

function GE.Options()
    return GuildExpansionSaved.options
end

function GE.SetOption(key, value)
    GuildExpansionSaved.options[key] = value
    Fire("state")
end

function GE.SetScale(value)
    value = math.max(0.6, math.min(1.4, tonumber(value) or 1))
    GuildExpansionSaved.options.scale = math.floor(value * 100 + 0.5) / 100
    GE.UI.ApplyScale()
end

function GE.Send(msg)
    SendAddonMessage(PREFIX, msg, "WHISPER", UnitName("player"))
end

function GE.RequestSync(force)
    local now = GetTime()
    if not force and now - lastPull < PULL_THROTTLE then
        return
    end
    lastPull = now
    GE.Send("PULL")
end

function GE.FindOrder(id)
    for _, order in ipairs(GE.orders) do
        if order.id == id then
            return order
        end
    end
    return nil
end

local function ParseState(fields)
    local name = fields[14] or ""
    for i = 15, #fields do
        name = name .. " " .. fields[i]
    end
    GE.MAX_LEVEL = tonumber(fields[12]) or GE.MAX_LEVEL
    return {
        level = tonumber(fields[3]) or 1,
        xp = tonumber(fields[4]) or 0,
        prev = tonumber(fields[5]) or 0,
        nextXp = tonumber(fields[6]) or 0,
        today = tonumber(fields[7]) or 0,
        week = tonumber(fields[8]) or 0,
        dailyCap = tonumber(fields[9]) or 0,
        weeklyCap = tonumber(fields[10]) or 0,
        supplies = tonumber(fields[11]) or 0,
        guildId = tonumber(fields[13]) or 0,
        guildName = name,
    }
end

local function OnState(data)
    local prev = GuildExpansionCharSaved.last
    local sameGuild = prev and prev.guildId == data.guildId

    if sameGuild and data.level > prev.level then
        GE.Notify.LevelUp(prev.level, data.level, data.guildName, not hadSnapshotThisSession)
    elseif sameGuild and hadSnapshotThisSession and data.xp > prev.xp then
        GE.Notify.XpGain(data.xp - prev.xp)
    end

    hadSnapshotThisSession = true
    GuildExpansionCharSaved.last = data
    GE.state = data
    Fire("state")
end

local function ParseOrder(f)
    return {
        id = tonumber(f[3]) or 0,
        kind = tonumber(f[4]) or 0,
        skill = tonumber(f[5]) or 0,
        spell = tonumber(f[6]) or 0,
        item = tonumber(f[7]) or 0,
        quality = tonumber(f[8]) or 1,
        quantity = tonumber(f[9]) or 1,
        placed = tonumber(f[10]) or 0,
        gold = tonumber(f[11]) or 0,
        supplies = tonumber(f[12]) or 0,
        guildXp = tonumber(f[13]) or 0,
        expiresAt = GetTime() + (tonumber(f[14]) or 0),
        name = f[15] or "",
    }
end

local function ParseUnit(f)
    return {
        id = tonumber(f[3]) or 0,
        template = tonumber(f[4]) or 0,
        race = tonumber(f[5]) or 0,
        gender = tonumber(f[6]) or 0,
        quality = tonumber(f[7]) or 2,
        level = tonumber(f[8]) or 1,
        xp = tonumber(f[9]) or 0,
        xpNext = tonumber(f[10]) or 1,
        itemLevel = tonumber(f[11]) or 0,
        abilities = { tonumber(f[12]) or 0, tonumber(f[13]) or 0 },
        traits = { tonumber(f[14]) or 0, tonumber(f[15]) or 0 },
        status = tonumber(f[16]) or 0,
        cost = tonumber(f[17]) or 0,
        vitality = tonumber(f[18]) or 0,
        weaponItem = tonumber(f[19]) or 0,
        weaponIlvl = tonumber(f[20]) or 0,
        armorItem = tonumber(f[21]) or 0,
        armorIlvl = tonumber(f[22]) or 0,
        effectItem = tonumber(f[23]) or 0,
        effectKind = tonumber(f[24]) or 0,
        promoXp = tonumber(f[25]) or 0,
        promoNext = tonumber(f[26]) or 0,
        name = f[27] or "",
    }
end

local function NumberList(csv)
    local out = {}
    for v in string.gmatch(csv or "", "%d+") do
        out[#out + 1] = tonumber(v)
    end
    return out
end

local function NumberSet(csv)
    local out = {}
    for _, v in ipairs(NumberList(csv)) do
        out[v] = true
    end
    return out
end

local function ParseMission(f)
    local now = GetTime()
    return {
        id = tonumber(f[3]) or 0,
        state = tonumber(f[4]) or 0,
        template = tonumber(f[5]) or 0,
        level = tonumber(f[6]) or 1,
        itemLevel = tonumber(f[7]) or 0,
        threats = NumberList(f[8]),
        duration = tonumber(f[9]) or 0,
        cost = tonumber(f[10]) or 0,
        gold = tonumber(f[11]) or 0,
        supplies = tonumber(f[12]) or 0,
        guildXp = tonumber(f[13]) or 0,
        unitXp = tonumber(f[14]) or 0,
        item = tonumber(f[15]) or 0,
        itemCount = tonumber(f[16]) or 0,
        gear = tonumber(f[17]) or 0,
        chance = tonumber(f[18]) or 0,
        units = NumberList(f[19]),
        endsAt = now + (tonumber(f[20]) or 0),
        expiresAt = now + (tonumber(f[21]) or 0),
        effect = tonumber(f[22]) or 0,
        rare = f[23] == "1",
    }
end

-- Asks for the mission board; mission templates are fetched once per session.
function GE.RequestMissions()
    if not next(GE.missionTemplates) then
        GE.Send("MTPL")
    end
    GE.Send("MISSIONS")
end

local function ParseContract(f)
    return {
        slot = tonumber(f[3]) or 0,
        kind = tonumber(f[4]) or 0,
        target = tonumber(f[5]) or 0,
        needed = tonumber(f[6]) or 1,
        progress = tonumber(f[7]) or 0,
        done = f[8] == "1",
        gold = tonumber(f[9]) or 0,
        supplies = tonumber(f[10]) or 0,
        guildXp = tonumber(f[11]) or 0,
        title = f[12] or "",
        label = f[13] or "",
    }
end

function GE.FindContract(slot)
    for _, c in ipairs(GE.contracts) do
        if c.slot == slot then
            return c
        end
    end
    return nil
end

-- Troops are units whose template is kind 2.
function GE.IsTroop(unit)
    local tmpl = GE.unitTemplates[unit.template]
    return tmpl ~= nil and tmpl.kind == 2
end

-- Asks for unit data; unit templates are fetched once per session.
function GE.RequestUnits()
    if not next(GE.unitTemplates) then
        GE.Send("UTPL")
    end
    GE.Send("UNITS")
end

-- What needs attention: contracts done, missions ready to collect, work orders with
-- enough items in the bags, and when the weekly stock changes.
function GE.Summary()
    local now = GetTime()
    local s = {
        contractsDone = 0, contractsTotal = #GE.contracts, bonusPaid = GE.contractInfo.bonusPaid,
        missionsReady = 0, missionsRunning = 0, ordersReady = 0, ordersOpen = 0,
        weeklyResetsAt = GE.qmInfo.weeklyResetsAt,
    }
    for _, c in ipairs(GE.contracts) do
        if c.done then
            s.contractsDone = s.contractsDone + 1
        end
    end
    for _, m in ipairs(GE.running) do
        if m.endsAt <= now then
            s.missionsReady = s.missionsReady + 1
        else
            s.missionsRunning = s.missionsRunning + 1
        end
    end
    for _, o in ipairs(GE.orders) do
        if o.item > 0 then
            s.ordersOpen = s.ordersOpen + 1
            if GetItemCount(o.item) >= o.quantity then
                s.ordersReady = s.ordersReady + 1
            end
        end
    end
    return s
end

-- Chat line the first time this character sees a new day's contracts.
local function NoticeNewContracts()
    local info = GE.contractInfo
    if info.status ~= 0 or #GE.contracts == 0 then
        return
    end
    -- The reset time as a wall-clock hour identifies the day.
    local day = math.floor((time() + (info.resetsAt - GetTime()) + 1800) / 3600)
    if GuildExpansionCharSaved.contractDay == day then
        return
    end
    GuildExpansionCharSaved.contractDay = day
    if not GE.Options().contractNotice then
        return
    end
    local titles = {}
    for _, c in ipairs(GE.contracts) do
        if not c.done then
            titles[#titles + 1] = c.title
        end
    end
    if #titles > 0 then
        GE.Print("New daily contracts: |cffffffff" .. table.concat(titles, ", ") .. "|r. Type /gl contracts.")
    end
end

local function OnLine(line)
    local fields = { strsplit("\t", line) }
    if fields[1] ~= PREFIX then
        return
    end

    local cmd = fields[2]
    if cmd == "STATE" then
        OnState(ParseState(fields))
    elseif cmd == "CLEAR" then
        GuildExpansionCharSaved.last = nil
        GE.state = nil
        Fire("state")
    elseif cmd == "ERROR" then
        UIErrorsFrame:AddMessage(fields[3] or "", 1.0, 0.1, 0.1, 1.0)
    elseif cmd == "WOB" then
        pendingOrders = {}
        GE.ordersStatus = tonumber(fields[4]) or 0
        GE.abandonDelayHours = tonumber(fields[5]) or 0
    elseif cmd == "WO" then
        if pendingOrders then
            pendingOrders[#pendingOrders + 1] = ParseOrder(fields)
        end
    elseif cmd == "WOE" then
        GE.orders = pendingOrders or {}
        pendingOrders = nil
        Fire("orders")
    elseif cmd == "PLACED" then
        local order = GE.FindOrder(tonumber(fields[3]))
        if order then
            order.placed = tonumber(fields[4]) or 0
            Fire("orders")
        end
    elseif cmd == "DONE" then
        PlaySoundFile("Sound\\Interface\\iQuestComplete.wav")
    elseif cmd == "UT" then
        GE.unitTemplates[tonumber(fields[3]) or 0] = {
            kind = tonumber(fields[4]) or 0,
            role = tonumber(fields[5]) or 2,
            class = tonumber(fields[6]) or 0,
            icon = fields[7] or "INV_Misc_QuestionMark",
            name = fields[8] or "",
            abilities = NumberList(fields[9]),
            armor = tonumber(fields[10]) or 0,
        }
    elseif cmd == "UTE" then
        Fire("units")
    elseif cmd == "UB" then
        pendingUnits = {}
        GE.unitInfo = {
            count = tonumber(fields[3]) or 0,
            max = tonumber(fields[4]) or 0,
            cap = tonumber(fields[5]) or 0,
            expiresAt = GetTime() + (tonumber(fields[7]) or 0),
            status = tonumber(fields[8]) or 0,
            troops = tonumber(fields[9]) or 0,
            maxTroops = tonumber(fields[10]) or 0,
            troopCost = tonumber(fields[11]) or 0,
        }
    elseif cmd == "U" then
        if pendingUnits then
            pendingUnits[#pendingUnits + 1] = ParseUnit(fields)
        end
    elseif cmd == "UE" then
        GE.units, GE.candidates, GE.troops = {}, {}, {}
        for _, unit in ipairs(pendingUnits or {}) do
            if unit.status == 2 then
                GE.candidates[#GE.candidates + 1] = unit
            elseif GE.IsTroop(unit) then
                GE.troops[#GE.troops + 1] = unit
            else
                GE.units[#GE.units + 1] = unit
            end
        end
        pendingUnits = nil
        Fire("units")
    elseif cmd == "RECRUITED" then
        PlaySoundFile("Sound\\Interface\\iQuestComplete.wav")
    elseif cmd == "EQUIPPED" then
        PlaySound("igCharacterInfoTab")
    elseif cmd == "MT" then
        local id = tonumber(fields[3]) or 0
        local tmpl = GE.missionTemplates[id] or {}
        tmpl.type = tonumber(fields[4]) or 0
        tmpl.slots = tonumber(fields[5]) or 1
        tmpl.roles = NumberList(fields[6])
        tmpl.name = fields[7] or ""
        GE.missionTemplates[id] = tmpl
    elseif cmd == "MD" then
        local id = tonumber(fields[3]) or 0
        GE.missionTemplates[id] = GE.missionTemplates[id] or {}
        GE.missionTemplates[id].desc = fields[4] or ""
    elseif cmd == "MTE" then
        Fire("missions")
    elseif cmd == "MB" then
        pendingMissions = {}
        GE.missionInfo = {
            slots = tonumber(fields[5]) or 0,
            status = tonumber(fields[6]) or 0,
        }
    elseif cmd == "M" then
        if pendingMissions then
            pendingMissions[#pendingMissions + 1] = ParseMission(fields)
        end
    elseif cmd == "ME" then
        GE.offers, GE.running = {}, {}
        for _, m in ipairs(pendingMissions or {}) do
            if m.state == 1 then
                GE.running[#GE.running + 1] = m
            else
                GE.offers[#GE.offers + 1] = m
            end
        end
        pendingMissions = nil
        Fire("missions")
    elseif cmd == "MCHANCE" then
        GE.chance = {
            id = tonumber(fields[3]) or 0,
            value = tonumber(fields[4]) or 0,
            countered = NumberSet(fields[5]),
            missing = NumberSet(fields[6]),
            duration = tonumber(fields[7]),
            consumableBonus = tonumber(fields[8]) or 0,
            consumableKind = tonumber(fields[9]) or 0,
        }
        Fire("chance")
    elseif cmd == "MSTARTED" then
        PlaySound("igQuestListOpen")
    elseif cmd == "MRESULT" then
        GE.lastResult = {
            id = tonumber(fields[3]) or 0,
            template = tonumber(fields[4]) or 0,
            success = fields[5] == "1",
            bonus = fields[6] == "1",
            gold = tonumber(fields[7]) or 0,
            supplies = tonumber(fields[8]) or 0,
            guildXp = tonumber(fields[9]) or 0,
            unitXp = tonumber(fields[10]) or 0,
            item = tonumber(fields[11]) or 0,
            itemCount = tonumber(fields[12]) or 0,
            gear = tonumber(fields[13]) or 0,
            levelUps = tonumber(fields[14]) or 0,
            extraItem = tonumber(fields[15]) or 0,
            extraCount = tonumber(fields[16]) or 0,
            treasure = tonumber(fields[17]) or 0,
            salvageItem = tonumber(fields[18]) or 0,
            salvageCount = tonumber(fields[19]) or 0,
            salvageGold = tonumber(fields[20]) or 0,
            troopsLost = tonumber(fields[21]) or 0,
            promotions = tonumber(fields[22]) or 0,
        }
        PlaySoundFile(GE.lastResult.success and "Sound\\Interface\\iQuestComplete.wav" or "Sound\\Interface\\iQuestFailed.wav")
        Fire("result")
    elseif cmd == "CB" then
        pendingContracts = {}
        GE.contractInfo = {
            status = tonumber(fields[4]) or 0,
            resetsAt = GetTime() + (tonumber(fields[5]) or 0),
            rerollsLeft = tonumber(fields[6]) or 0,
            bonusPaid = fields[7] == "1",
            bonusSupplies = tonumber(fields[8]) or 0,
            done = tonumber(fields[9]) or 0,
        }
    elseif cmd == "C" then
        if pendingContracts then
            pendingContracts[#pendingContracts + 1] = ParseContract(fields)
        end
    elseif cmd == "CE" then
        GE.contracts = pendingContracts or {}
        pendingContracts = nil
        NoticeNewContracts()
        Fire("contracts")
    elseif cmd == "CP" then
        local c = GE.FindContract(tonumber(fields[3]) or -1)
        if c then
            c.progress = tonumber(fields[4]) or c.progress
            Fire("contracts")
        end
        -- Shown like a quest objective update.
        if GE.Options().contractProgress then
            UIErrorsFrame:AddMessage(string.format("%s: %s/%s", fields[6] or "", fields[4] or "0", fields[5] or "0"), 1.0, 1.0, 0.0, 1.0)
        end
    elseif cmd == "CDONE" then
        GE.Notify.Toast("Contract complete: |cffffffff" .. (fields[7] or "") .. "|r")
    elseif cmd == "CBONUS" then
        GE.Notify.Toast("All of today's contracts complete!", "Sound\\Interface\\LevelUp.wav")
    elseif cmd == "AB" then
        pendingTracks, pendingMilestones = {}, {}
        GE.advancement = {
            status = tonumber(fields[3]) or 0,
            level = tonumber(fields[4]) or 0,
            earned = tonumber(fields[5]) or 0,
            spent = tonumber(fields[6]) or 0,
            resetCost = tonumber(fields[7]) or 0,
            canEdit = fields[8] == "1",
            trackMax = tonumber(fields[9]) or 25,
            changeCost = tonumber(fields[10]) or 0,
            tracks = GE.advancement.tracks,
            milestones = GE.advancement.milestones,
        }
    elseif cmd == "AM" then
        if pendingMilestones then
            pendingMilestones[tonumber(fields[3]) or 0] = tonumber(fields[4]) or 0
        end
    elseif cmd == "AT" then
        if pendingTracks then
            pendingTracks[tonumber(fields[3]) or 0] = tonumber(fields[4]) or 0
        end
    elseif cmd == "AE" then
        GE.advancement.tracks = pendingTracks or {}
        GE.advancement.milestones = pendingMilestones or {}
        pendingTracks, pendingMilestones = nil, nil
        Fire("advancement")
    elseif cmd == "ASPENT" or cmd == "ACHOSEN" then
        PlaySound("igMainMenuOptionCheckBoxOn")
    elseif cmd == "QB" then
        pendingStock, pendingWeekly = {}, {}
        GE.qmInfo = {
            status = tonumber(fields[3]) or 0,
            guildLevel = tonumber(fields[4]) or 0,
            weeklyResetsAt = GetTime() + (tonumber(fields[5]) or 0),
        }
    elseif cmd == "QT" then
        if pendingStock then
            pendingStock[#pendingStock + 1] = {
                id = tonumber(fields[3]) or 0,
                category = tonumber(fields[4]) or 0,
                item = tonumber(fields[5]) or 0,
                count = tonumber(fields[6]) or 1,
                service = tonumber(fields[7]) or 0,
                cost = tonumber(fields[8]) or 0,
                guildLevel = tonumber(fields[9]) or 1,
                limit = tonumber(fields[10]) or 0,
                bought = tonumber(fields[11]) or 0,
                state = tonumber(fields[12]) or 0,
            }
        end
    elseif cmd == "QW" then
        if pendingWeekly then
            local slot = tonumber(fields[3]) or 0
            pendingWeekly[slot] = {
                slot = slot,
                item = tonumber(fields[4]) or 0,
                count = tonumber(fields[5]) or 1,
                cost = tonumber(fields[6]) or 0,
                state = tonumber(fields[7]) or 7,
                randomProperty = tonumber(fields[8]) or 0,
                suffixFactor = tonumber(fields[9]) or 0,
                buyer = fields[10] or "",
            }
        end
    elseif cmd == "QE" then
        GE.qmStock = pendingStock or {}
        GE.qmWeekly = pendingWeekly or {}
        pendingStock, pendingWeekly = nil, nil
        Fire("quartermaster")
    elseif cmd == "QBOUGHT" then
        PlaySound("LOOTWINDOWCOINSOUND")
    elseif cmd == "MDONE" then
        local tmpl = GE.missionTemplates[tonumber(fields[4]) or 0]
        GE.Notify.MissionDone(tmpl and tmpl.name or "A mission")
        Fire("missions")
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_GUILD_UPDATE")
eventFrame:RegisterEvent("CHAT_MSG_ADDON")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= ADDON_NAME then
            return
        end
        GuildExpansionSaved = GuildExpansionSaved or {}
        GuildExpansionSaved.options = GuildExpansionSaved.options or {}
        for key, value in pairs(DEFAULT_OPTIONS) do
            if GuildExpansionSaved.options[key] == nil then
                GuildExpansionSaved.options[key] = value
            end
        end
        GuildExpansionCharSaved = GuildExpansionCharSaved or {}
        GE.state = GuildExpansionCharSaved.last
    elseif event == "PLAYER_LOGIN" then
        -- Shift-G opens the window, the first time only and only when nothing else has the key.
        if not GuildExpansionSaved.boundKey then
            GuildExpansionSaved.boundKey = true
            local action = GetBindingAction(GE.DEFAULT_KEY)
            if not action or action == "" then
                SetBinding(GE.DEFAULT_KEY, "GUILDEXPANSION_TOGGLE")
                SaveBindings(GetCurrentBindingSet())
            end
        end
        Fire("state")
        GE.RequestSync(true)
        -- The summary (Guild tab and minimap button) needs contracts, missions and the
        -- weekly stock time without the tabs being opened first.
        GE.Send("CONTRACTS")
        GE.RequestMissions()
        GE.Send("QM")
        GE.Send("ADV")
    elseif event == "PLAYER_GUILD_UPDATE" then
        GE.RequestSync()
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, body, channel, sender = ...
        if prefix == PREFIX and channel == "WHISPER" and sender == UnitName("player") then
            OnLine(PREFIX .. "\t" .. tostring(body or ""))
        end
    end
end)

local function PrintHelp()
    GE.Print("commands:")
    DEFAULT_CHAT_FRAME:AddMessage("  /gl - open or close the Guild Expansion window")
    DEFAULT_CHAT_FRAME:AddMessage("  /gl missions - open the Missions tab")
    DEFAULT_CHAT_FRAME:AddMessage("  /gl units - open the Units tab")
    DEFAULT_CHAT_FRAME:AddMessage("  /gl orders - open the Work Orders tab")
    DEFAULT_CHAT_FRAME:AddMessage("  /gl contracts - open the Contracts tab")
    DEFAULT_CHAT_FRAME:AddMessage("  /gl qm - open the Quartermaster tab")
    DEFAULT_CHAT_FRAME:AddMessage("  /gl guild - open the Guild tab (level and perks)")
    DEFAULT_CHAT_FRAME:AddMessage("  /gl points - open the Advancement tab (Guild Points)")
    DEFAULT_CHAT_FRAME:AddMessage("  /gl scale 0.9 - change the window size (0.6 to 1.4)")
    DEFAULT_CHAT_FRAME:AddMessage("  /gl bank - use Mobile Banking")
    DEFAULT_CHAT_FRAME:AddMessage("  /gl options - open the options")
    DEFAULT_CHAT_FRAME:AddMessage("  /gl minimap - show or hide the minimap button")
    DEFAULT_CHAT_FRAME:AddMessage("  /gl reset - move the window back to the middle of the screen")
    DEFAULT_CHAT_FRAME:AddMessage("  /gl refresh - ask the server for fresh data")
end

SLASH_GUILDEXPANSION1 = "/gl"
SLASH_GUILDEXPANSION2 = "/guildexpansion"
SlashCmdList["GUILDEXPANSION"] = function(input)
    local cmd = strlower(strtrim(input or ""))
    if cmd == "" then
        GE.UI.Toggle()
    elseif cmd == "orders" or cmd == "wo" then
        GE.UI.Show("orders")
    elseif cmd == "units" then
        GE.UI.Show("units")
    elseif cmd == "missions" or cmd == "m" then
        GE.UI.Show("missions")
    elseif cmd == "contracts" or cmd == "c" then
        GE.UI.Show("contracts")
    elseif cmd == "qm" or cmd == "quartermaster" or cmd == "shop" then
        GE.UI.Show("quartermaster")
    elseif cmd == "points" or cmd == "advancement" then
        GE.UI.Show("advancement")
    elseif cmd == "guild" or cmd == "perks" then
        GE.UI.Show("guild")
    elseif cmd:match("^scale") then
        local value = tonumber(cmd:match("^scale%s+([%d%.]+)"))
        if value then
            GE.SetScale(value)
        end
        GE.Print("window size is " .. GE.Options().scale .. " (use /gl scale 0.6 to 1.4).")
    elseif cmd == "bank" then
        GE.Send("USE BANK")
    elseif cmd == "options" or cmd == "config" then
        GE.OpenOptions()
    elseif cmd == "minimap" then
        GE.SetOption("minimapButton", not GE.Options().minimapButton)
        GE.Print("minimap button " .. (GE.Options().minimapButton and "shown." or "hidden."))
    elseif cmd == "reset" then
        GE.UI.ResetPosition()
        GE.Print("window position reset.")
    elseif cmd == "refresh" or cmd == "pull" then
        GE.RequestSync(true)
    else
        PrintHelp()
    end
end

-- At the daily reset, fetch the new day's contracts (also while the window is closed).
local resetWatcher = CreateFrame("Frame")
local resetElapsed = 0
resetWatcher:SetScript("OnUpdate", function(self, elapsed)
    resetElapsed = resetElapsed + elapsed
    if resetElapsed < 5 then
        return
    end
    resetElapsed = 0
    local info = GE.contractInfo
    if info.status == 0 and #GE.contracts > 0 and info.resetsAt <= GetTime() then
        info.resetsAt = GetTime() + 60
        GE.Send("CONTRACTS")
    end
end)
