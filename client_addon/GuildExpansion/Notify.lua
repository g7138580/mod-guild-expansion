--[[ Guild Expansion: level-up splash and guild XP gain text ]]

local GE = GuildExpansion

local Notify = {}
GE.Notify = Notify

local SPLASH_HOLD = 5
local SPLASH_FADE = 1.5
local XP_DURATION = 2.5
local XP_RISE = 40

local splash
local xpFrame

local function BuildSplash()
    splash = CreateFrame("Frame", nil, UIParent)
    splash:SetWidth(520)
    splash:SetHeight(120)
    splash:SetPoint("TOP", UIParent, "TOP", 0, -150)
    splash:SetFrameStrata("HIGH")
    splash:Hide()

    splash.icon = splash:CreateTexture(nil, "ARTWORK")
    splash.icon:SetWidth(40)
    splash.icon:SetHeight(40)
    splash.icon:SetPoint("TOP", splash, "TOP", 0, 0)

    splash.title = splash:CreateFontString(nil, "OVERLAY", "BossEmoteNormalHuge")
    splash.title:SetPoint("TOP", splash.icon, "BOTTOM", 0, -4)

    splash.sub = splash:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    splash.sub:SetPoint("TOP", splash.title, "BOTTOM", 0, -6)
    splash.sub:SetWidth(520)

    splash.note = splash:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    splash.note:SetPoint("TOP", splash.sub, "BOTTOM", 0, -4)

    splash:SetScript("OnUpdate", function(self, elapsed)
        self.t = self.t + elapsed
        if self.t >= SPLASH_HOLD + SPLASH_FADE then
            self:Hide()
        elseif self.t > SPLASH_HOLD then
            self:SetAlpha(1 - (self.t - SPLASH_HOLD) / SPLASH_FADE)
        end
    end)
end

local function BuildXpFrame()
    xpFrame = CreateFrame("Frame", nil, UIParent)
    xpFrame:SetWidth(300)
    xpFrame:SetHeight(24)
    xpFrame:SetFrameStrata("HIGH")
    xpFrame:Hide()

    xpFrame.text = xpFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    xpFrame.text:SetPoint("CENTER")
    xpFrame.text:SetTextColor(0.45, 0.8, 1.0)

    xpFrame:SetScript("OnUpdate", function(self, elapsed)
        self.t = self.t + elapsed
        if self.t >= XP_DURATION then
            self:Hide()
            return
        end
        local p = self.t / XP_DURATION
        self:SetPoint("CENTER", UIParent, "CENTER", 0, 140 + XP_RISE * p)
        self:SetAlpha(p < 0.6 and 1 or (1 - (p - 0.6) / 0.4))
    end)
end

function Notify.LevelUp(oldLevel, newLevel, guildName, whileAway)
    local unlocked = GE.PerksBetween(oldLevel, newLevel)
    local names = {}
    for i, perk in ipairs(unlocked) do
        names[i] = perk.name
    end
    local perkText = #names > 0
        and ("New perk" .. (#names > 1 and "s" or "") .. ": |cff88ff88" .. table.concat(names, ", ") .. "|r")
        or nil

    GE.Print(string.format("Your guild reached level %d!", newLevel) .. (perkText and (" " .. perkText) or ""))

    if not GE.Options().levelAlert then
        return
    end

    if not splash then
        BuildSplash()
    end

    splash.title:SetText(string.format("Guild Level %d!", newLevel))
    if #unlocked > 0 then
        splash.icon:SetTexture(GE.IconPath(unlocked[#unlocked]))
        splash.sub:SetText(perkText)
    else
        splash.icon:SetTexture("Interface\\Icons\\INV_Shirt_GuildTabard_01")
        splash.sub:SetText(guildName or "")
    end
    splash.note:SetText(whileAway and "Reached while you were away" or "")

    splash.t = 0
    splash:SetAlpha(1)
    splash:Show()
    PlaySoundFile("Sound\\Interface\\LevelUp.wav")
end

local toast

-- Alert near the top of the screen (mission or contract complete).
function Notify.Toast(text, sound)
    PlaySoundFile(sound or "Sound\\Interface\\iQuestComplete.wav")

    if not toast then
        toast = CreateFrame("Frame", nil, UIParent)
        toast:SetWidth(400)
        toast:SetHeight(40)
        toast:SetPoint("TOP", UIParent, "TOP", 0, -110)
        toast:SetFrameStrata("HIGH")
        toast.text = toast:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        toast.text:SetPoint("CENTER")
        toast:SetScript("OnUpdate", function(self, elapsed)
            self.t = self.t + elapsed
            if self.t >= 5 then
                self:Hide()
            elseif self.t > 4 then
                self:SetAlpha(5 - self.t)
            end
        end)
    end
    toast.text:SetText(text)
    toast.t = 0
    toast:SetAlpha(1)
    toast:Show()
end

-- "Mission complete" alert plus a chat line.
function Notify.MissionDone(name)
    GE.Print("Mission complete: |cffffffff" .. name .. "|r. Open /gl missions to collect.")
    Notify.Toast("Mission complete: |cffffffff" .. name .. "|r")
end

function Notify.XpGain(amount)
    if not GE.Options().xpText or amount <= 0 then
        return
    end
    if not xpFrame then
        BuildXpFrame()
    end
    xpFrame.text:SetText("+" .. GE.FormatNumber(amount) .. " Guild XP")
    xpFrame.t = 0
    xpFrame:SetAlpha(1)
    xpFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 140)
    xpFrame:Show()
end
