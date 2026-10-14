--[[
  Guild Expansion: Contracts page.
  The character's daily contracts as cards with progress bars and rewards, the bonus
  cache for finishing all of them, and the time until new contracts arrive. Progress
  comes from normal play; a finished contract pays out right away.
]]

local GE = GuildExpansion
local UI = GE.UI

local MAX_CARDS = 5
local HEADER_HEIGHT = 96

-- Keep in sync with ContractKind in src/GspeContracts.h.
local KIND = {
    SLAY_TYPE = 1, SLAY_ELITE = 2, QUESTS = 3, GATHER = 4, FISH = 5,
    DUNGEON_BOSS = 6, BG_COMPLETE = 7, BG_WIN = 8, HONOR_KILLS = 9,
}

local CREATURE_TYPE_ICONS = {
    [1] = "Ability_Hunter_Pet_Wolf",          -- beasts
    [2] = "INV_Misc_MonsterScales_05",        -- dragonkin
    [3] = "Spell_Shadow_SummonFelHunter",     -- demons
    [4] = "Spell_Frost_SummonWaterElemental", -- elementals
    [5] = "Ability_Warrior_Titansgrip",       -- giants
    [6] = "Spell_Shadow_RaiseDead",           -- undead
    [7] = "Ability_Rogue_Disguise",           -- humanoids
    [9] = "INV_Gizmo_02",                     -- mechanicals
}

local GATHER_ICONS = {
    [182] = "Spell_Nature_NatureTouchGrow",   -- herbalism
    [186] = "Trade_Mining",
    [393] = "INV_Misc_Pelt_Wolf_01",          -- skinning
}

local KIND_ICONS = {
    [KIND.SLAY_ELITE] = "Ability_Warrior_Rampage",
    [KIND.QUESTS] = "INV_Misc_Note_01",
    [KIND.FISH] = "Trade_Fishing",
    [KIND.DUNGEON_BOSS] = "INV_Misc_Head_Dragon_01",
    [KIND.BG_COMPLETE] = "Achievement_BG_winWSG",
    [KIND.BG_WIN] = "INV_Jewelry_TrinketPVP_01",
    [KIND.HONOR_KILLS] = "Ability_DualWield",
}

local KIND_HINTS = {
    [KIND.SLAY_TYPE] = "Kills that give experience count, including your pet's and your group's.",
    [KIND.SLAY_ELITE] = "Elite and rare elite enemies that give experience, anywhere.",
    [KIND.QUESTS] = "Quests that are not gray for you count when you turn them in.",
    [KIND.GATHER] = "Every node gathered or creature skinned counts.",
    [KIND.FISH] = "Every catch counts, from open water or a fishing pool.",
    [KIND.DUNGEON_BOSS] = "Bosses in dungeons and raids that are not gray for you.",
    [KIND.BG_COMPLETE] = "Play a battleground to the end. Arenas don't count.",
    [KIND.BG_WIN] = "Be on the winning side of a battleground. Arenas don't count.",
    [KIND.HONOR_KILLS] = "Kills that award honor, in battlegrounds or the open world.",
}

local function ContractIcon(c)
    local icon
    if c.kind == KIND.SLAY_TYPE then
        icon = CREATURE_TYPE_ICONS[c.target]
    elseif c.kind == KIND.GATHER then
        icon = GATHER_ICONS[c.target]
    else
        icon = KIND_ICONS[c.kind]
    end
    return "Interface\\Icons\\" .. (icon or "INV_Misc_QuestionMark")
end

StaticPopupDialogs["GUILDEXPANSION_REROLL_CONTRACT"] = {
    text = "Replace \"%s\" with a different contract?",
    button1 = YES,
    button2 = NO,
    OnAccept = function(self, slot)
        GE.Send("CREROLL " .. slot)
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

-- Header: title, reset timer and the bonus cache ----------------------------------

local function BuildHeader(page)
    local ui = page.ui
    local head = UI.Inset(page.frame)
    head:SetPoint("TOPLEFT", 0, 0)
    head:SetPoint("TOPRIGHT", 0, 0)
    head:SetHeight(HEADER_HEIGHT)

    ui.title = head:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    ui.title:SetPoint("TOPLEFT", 16, -14)
    ui.title:SetText("Daily Contracts")
    ui.reset = head:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ui.reset:SetPoint("TOPLEFT", ui.title, "BOTTOMLEFT", 0, -6)
    ui.rerolls = head:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ui.rerolls:SetPoint("TOPLEFT", ui.reset, "BOTTOMLEFT", 0, -6)

    -- Bonus cache, on the right.
    ui.bonusIcon = UI.IconButton(head, 44)
    ui.bonusIcon:SetPoint("TOPRIGHT", -20, -14)
    ui.bonusIcon.icon:SetTexture("Interface\\Icons\\INV_Box_02")
    ui.bonusIcon.tooltip = function()
        local info = GE.contractInfo
        GameTooltip:AddLine("Bonus Cache")
        GameTooltip:AddLine("Finish all of today's contracts to receive:", 1, 1, 1, true)
        GameTooltip:AddLine(info.bonusSupplies .. " guild supplies", 1, 0.82, 0)
        GameTooltip:AddLine("A stack of potions or materials, or sometimes a piece of gear", 1, 1, 1, true)
        if info.bonusPaid then
            GameTooltip:AddLine("Received today.", 0.5, 1, 0.5)
        end
    end
    ui.bonusCheck = ui.bonusIcon:CreateTexture(nil, "OVERLAY")
    ui.bonusCheck:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    ui.bonusCheck:SetWidth(24)
    ui.bonusCheck:SetHeight(24)
    ui.bonusCheck:SetPoint("BOTTOMRIGHT", 4, -4)

    ui.bonusLabel = head:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ui.bonusLabel:SetPoint("TOPRIGHT", ui.bonusIcon, "TOPLEFT", -12, -2)
    ui.bonusLabel:SetText("Bonus Cache")

    ui.bonusBar = CreateFrame("StatusBar", nil, head)
    ui.bonusBar:SetWidth(220)
    ui.bonusBar:SetHeight(14)
    ui.bonusBar:SetPoint("TOPRIGHT", ui.bonusLabel, "BOTTOMRIGHT", 0, -6)
    ui.bonusBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    ui.bonusBar:SetStatusBarColor(1, 0.7, 0.1)
    local barBg = ui.bonusBar:CreateTexture(nil, "BACKGROUND")
    barBg:SetAllPoints(true)
    barBg:SetTexture(0, 0, 0, 0.6)
    ui.bonusText = ui.bonusBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ui.bonusText:SetPoint("CENTER")
end

local function RefreshHeader(page)
    local ui = page.ui
    local info = GE.contractInfo
    local total = #GE.contracts

    ui.reset:SetText("New contracts in |cffffffff" .. UI.FormatDuration(info.resetsAt - GetTime()) .. "|r")
    ui.rerolls:SetText(string.format("Rerolls left today: |cffffffff%d|r", info.rerollsLeft))

    ui.bonusBar:SetMinMaxValues(0, math.max(1, total))
    ui.bonusBar:SetValue(info.done)
    ui.bonusText:SetText(string.format("%d / %d done", info.done, total))
    ui.bonusIcon.icon:SetDesaturated(not info.bonusPaid and info.done < total)
    if info.bonusPaid then
        ui.bonusCheck:Show()
    else
        ui.bonusCheck:Hide()
    end
end

-- Cards ---------------------------------------------------------------------------

local function BuildCard(page, i)
    local card = UI.ParchmentRow(page.frame, UI.CONTENT_WIDTH, 120)
    card:EnableMouse(false)

    card.icon = UI.IconButton(card, 56)
    card.icon:SetPoint("LEFT", 18, 0)
    card.icon.tooltip = function()
        local c = card.contract
        if c then
            GameTooltip:AddLine(c.title)
            if KIND_HINTS[c.kind] then
                GameTooltip:AddLine(KIND_HINTS[c.kind], 1, 1, 1, true)
            end
        end
    end
    card.check = card.icon:CreateTexture(nil, "OVERLAY")
    card.check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    card.check:SetWidth(28)
    card.check:SetHeight(28)
    card.check:SetPoint("BOTTOMRIGHT", 6, -6)

    card.title = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    card.title:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 16, -2)
    card.title:SetJustifyH("LEFT")

    card.bar = CreateFrame("StatusBar", nil, card)
    card.bar:SetWidth(360)
    card.bar:SetHeight(18)
    card.bar:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -10)
    card.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    local barBg = card.bar:CreateTexture(nil, "BACKGROUND")
    barBg:SetAllPoints(true)
    barBg:SetTexture(0, 0, 0, 0.6)
    card.barText = card.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.barText:SetPoint("CENTER")

    card.rewardLabel = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    card.rewardLabel:SetText("Rewards")
    card.rewards = {}
    for r = 1, 3 do
        local b = UI.IconButton(card, 34)
        if r == 1 then
            b:SetPoint("TOPLEFT", card, "TOPRIGHT", -134, -30)
        else
            b:SetPoint("LEFT", card.rewards[r - 1], "RIGHT", 6, 0)
        end
        card.rewards[r] = b
    end
    card.rewardLabel:SetPoint("BOTTOMLEFT", card.rewards[1], "TOPLEFT", 0, 4)

    -- Bottom right corner, under the rewards.
    card.reroll = UI.Button(card, "Reroll", 80, 20)
    card.reroll:SetPoint("BOTTOMRIGHT", -12, 10)
    card.reroll:SetScript("OnClick", function()
        local c = card.contract
        if c then
            local dialog = StaticPopup_Show("GUILDEXPANSION_REROLL_CONTRACT", c.title)
            if dialog then
                dialog.data = c.slot
            end
        end
    end)
    card.reroll:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Reroll")
        GameTooltip:AddLine("Replace this contract with one of another kind. Progress on it is lost.", 1, 1, 1, true)
        if GE.contractInfo.rerollsLeft == 0 then
            GameTooltip:AddLine("No rerolls left today. The quartermaster sells more.", 1, 0.3, 0.3, true)
        end
        GameTooltip:Show()
    end)
    card.reroll:SetScript("OnLeave", function() GameTooltip:Hide() end)

    card.doneText = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    card.doneText:SetPoint("BOTTOMRIGHT", -16, 12)
    card.doneText:SetText("|cff80ff80Complete|r")

    card:Hide()
    return card
end

local function RefreshCards(page)
    local ui = page.ui
    local count = #GE.contracts
    local height = count <= 3 and 124 or 90
    for i, card in ipairs(ui.cards) do
        local c = GE.contracts[i]
        card.contract = c
        if c then
            card:SetHeight(height)
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", 0, -(HEADER_HEIGHT + 10 + (i - 1) * (height + 8)))

            card.icon.icon:SetTexture(ContractIcon(c))
            card.icon.icon:SetDesaturated(c.done)
            card.title:SetText(c.done and ("|cffaaaaaa" .. c.title .. "|r") or c.title)

            card.bar:SetMinMaxValues(0, math.max(1, c.needed))
            card.bar:SetValue(c.progress)
            if c.done then
                card.bar:SetStatusBarColor(0.3, 0.8, 0.3)
            else
                card.bar:SetStatusBarColor(0.2, 0.5, 1.0)
            end
            card.barText:SetText(string.format("%s: %d / %d", c.label, c.progress, c.needed))

            UI.FillRewards(card.rewards, c)
            if c.done then
                card.check:Show()
                card.doneText:Show()
                card.reroll:Hide()
            else
                card.check:Hide()
                card.doneText:Hide()
                card.reroll:Show()
                if GE.contractInfo.rerollsLeft > 0 then
                    card.reroll:Enable()
                else
                    card.reroll:Disable()
                end
            end
            card:Show()
        else
            card:Hide()
        end
    end

    local status = GE.contractInfo.status
    if status == 1 then
        ui.empty:SetText("Join a guild to receive contracts.")
    elseif status == 2 then
        ui.empty:SetText("Contracts are turned off on this server.")
    elseif count == 0 then
        ui.empty:SetText("No contracts right now.")
    else
        ui.empty:SetText("")
    end
end

-- Page ----------------------------------------------------------------------------

local function Build(page)
    page.ui = {}
    local ui = page.ui
    BuildHeader(page)

    ui.cards = {}
    for i = 1, MAX_CARDS do
        ui.cards[i] = BuildCard(page, i)
    end

    ui.empty = page.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    ui.empty:SetPoint("TOP", 0, -(HEADER_HEIGHT + 60))

    ui.hint = page.frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ui.hint:SetPoint("BOTTOMLEFT", 6, 4)
    ui.hint:SetText("Contracts count normal play and pay out the moment they are done. Hover an icon for what counts.")

    page.frame:SetScript("OnShow", function()
        GE.Send("CONTRACTS")
    end)

    -- Keep the reset timer current, and fetch the new day's contracts after the reset.
    local elapsedSince = 0
    page.frame:SetScript("OnUpdate", function(self, elapsed)
        elapsedSince = elapsedSince + elapsed
        if elapsedSince < 1 then
            return
        end
        elapsedSince = 0
        if GE.contractInfo.status == 0 and #GE.contracts > 0 and GE.contractInfo.resetsAt <= GetTime() then
            GE.contractInfo.resetsAt = GetTime() + 30
            GE.Send("CONTRACTS")
        end
        RefreshHeader(page)
    end)
end

local function Refresh(page)
    RefreshHeader(page)
    RefreshCards(page)
end

UI.RegisterPage("contracts", "Contracts", "Guild Contracts", Build, Refresh)
