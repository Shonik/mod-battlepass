--[[
    Battle Pass System - Rewards Module
    BP_Rewards.lua

    Reward distribution: items, gold, titles, spells.
]]

-- ============================================================================
-- Namespace
-- ============================================================================

BattlePass = BattlePass or {}
BattlePass.Rewards = BattlePass.Rewards or {}

-- ============================================================================
-- Reward Handlers by Type
-- ============================================================================

function BattlePass.Rewards.GrantItemReward(player, rewardData)
    local itemId = rewardData.reward_id
    local count = rewardData.reward_count or 1

    local itemTemplate = GetItemTemplate(itemId)
    if not itemTemplate then
        return false
    end

    local existingCount = player:GetItemCount(itemId)
    if existingCount > 0 then
        local query = WorldDBQuery(string.format(
            "SELECT maxcount FROM item_template WHERE entry = %d", itemId))

        if query then
            local maxCount = query:GetInt32(0)

            if maxCount == 1 then
                local itemLink = GetItemLink(itemId)
                return false -- unique item
            end

            if maxCount > 0 and (existingCount + count) > maxCount then
                local itemLink = GetItemLink(itemId)
                return false -- limit reached
            end
        end
    end

    if not player:AddItem(itemId, count) then
        return false -- inventory full
    end

    local itemLink = GetItemLink(itemId)

    return true
end

function BattlePass.Rewards.GrantGoldReward(player, rewardData)
    local copper = rewardData.reward_count or 0

    player:ModifyMoney(copper)

    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local copperRem = copper % 100

    local amountStr = ""
    if gold > 0 then
        amountStr = amountStr .. gold .. "g "
    end
    if silver > 0 then
        amountStr = amountStr .. silver .. "s "
    end
    if copperRem > 0 then
        amountStr = amountStr .. copperRem .. "c"
    end


    return true
end

function BattlePass.Rewards.GrantTitleReward(player, rewardData)
    local titleId = rewardData.reward_id

    if player:HasTitle(titleId) then
        return false -- already owned
    end

    player:SetKnownTitle(titleId)

    return true
end

function BattlePass.Rewards.GrantSpellReward(player, rewardData)
    local spellId = rewardData.reward_id

    if player:HasSpell(spellId) then
        return false -- already known
    end

    player:LearnSpell(spellId)

    return true
end

function BattlePass.Rewards.GrantCurrencyReward(player, rewardData)
    return BattlePass.Rewards.GrantItemReward(player, rewardData)
end

-- ============================================================================
-- Handler Table by Type
-- ============================================================================

local REWARD_HANDLERS = {
    [1] = BattlePass.Rewards.GrantItemReward,
    [2] = BattlePass.Rewards.GrantGoldReward,
    [3] = BattlePass.Rewards.GrantTitleReward,
    [4] = BattlePass.Rewards.GrantSpellReward,
    [5] = BattlePass.Rewards.GrantCurrencyReward,
}

-- ============================================================================
-- Main Interface
-- ============================================================================

function BattlePass.Rewards.ClaimReward(player, level)
    if not BattlePass.IsEnabled() then
        return false
    end

    local guid = player:GetGUIDLow()
    local data = BattlePass.DB.GetOrCreatePlayerData(player)

    local levelData = BattlePass.LevelCache[level]

    if data.current_level < level then
        return false
    end

    if BattlePass.DB.IsLevelClaimed(guid, level) then
        return false
    end

    local rewardType = levelData.reward_type
    local handler = REWARD_HANDLERS[rewardType]

    local success = handler(player, levelData)

    if success then
        BattlePass.DB.MarkLevelClaimed(guid, level)
        BattlePass.DB.SavePlayerProgress(guid, data)

        BattlePass.Communication.SendClaimConfirmation(player, level)

        return true
    else
        return false
    end
end

function BattlePass.Rewards.ClaimAllRewards(player)
    local availableRewards = BattlePass.Progress.GetAvailableRewards(player)

    for _, rewardData in ipairs(availableRewards) do
        BattlePass.Rewards.ClaimReward(player, rewardData.level)
    end
end

-- ============================================================================
-- Reward Preview
-- ============================================================================

function BattlePass.Rewards.GetRewardInfo(level)
    return BattlePass.LevelCache[level]
end

function BattlePass.Rewards.GetRewardTypeName(typeId)
    local typeInfo = BattlePass.RewardTypeCache[typeId]
    if typeInfo then
        return typeInfo.name
    end
    return "unknown"
end

function BattlePass.Rewards.PlayerOwnsReward(player, levelData)
    local rewardType = levelData.reward_type
    local rewardId = levelData.reward_id
    local rewardCount = levelData.reward_count

    if rewardType == 1 or rewardType == 5 then
        -- Item or Currency: only check if it's a UNIQUE item
        local itemCount = player:GetItemCount(rewardId)

        if itemCount > 0 then
            local query = WorldDBQuery(string.format(
                "SELECT maxcount FROM item_template WHERE entry = %d", rewardId))

            if query then
                local maxCount = query:GetInt32(0)
                if maxCount == 1 then
                    return true
                end
            end
        end

        return false
    elseif rewardType == 2 then
        -- Gold: always false
        return false
    elseif rewardType == 3 then
        -- Title: check if player has the title
        return player:HasTitle(rewardId)
    elseif rewardType == 4 then
        -- Spell: check if player knows the spell
        return player:HasSpell(rewardId)
    end

    return false
end

function BattlePass.Rewards.FormatRewardDescription(levelData)
    local typeName = BattlePass.Rewards.GetRewardTypeName(levelData.reward_type)

    local desc = string.format("Level %d: |cffffd700%s|r",
        levelData.level, levelData.reward_name)

    if levelData.description and levelData.description ~= "" then
        desc = desc .. " - " .. levelData.description
    end

    return desc
end
