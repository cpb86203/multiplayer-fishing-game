--Handles world events (solar eclipses, harvest moons, auroras, etc.)

--Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--Modules
local EventData = require(ReplicatedStorage.modules.gameData.EventData)
local timeDataModule = require(ReplicatedStorage.dataModules.timeDataModule)

--Data
local worldEventData = EventData.worldEventData
local eventRarityOrder = {
    'Blue Moon',
    'Solar Eclipse',
    'Aurora',
    'Blood Moon',
    'Rainbow',
    'Super Moon',
    'Harvest Moon',
}

--Integer offset per time period (used for event rolls)
local TIME_OFFSETS = {
    Sunrise = 1000,
    Day = 2000,
    Sunset = 3000,
    Night = 4000,
}

--State
local currentWorldEvent = nil
local oldWorldEvent = nil

--Adds event stat modifiers to a player
local function applyStatsToPlr(plr: Player, statDict)
    if not plr or not statDict then return end

    for statSTR, newStatNum in statDict do
        local currentStatNum = plr:GetAttribute(statSTR) or 0
        plr:SetAttribute(statSTR, currentStatNum + newStatNum)
    end
end

--Removes event stat modifiers from a player
local function removeStatsFromPlr(plr: Player, statDict)
    if not plr or not statDict then return end

    for statSTR, newStatNum in statDict do
        local currentStatNum = plr:GetAttribute(statSTR) or 0
        plr:SetAttribute(statSTR, currentStatNum - newStatNum)
    end
end

--Rolls for a world event that matches the current time period (deterministic)
local function getWorldEvent(currentTime)
    local currentDay = timeDataModule.getCurrentDay()
    local periodOffset = TIME_OFFSETS[currentTime] or 0

    for i, eventName in eventRarityOrder do
        local data = worldEventData[eventName]

        if data.Conditions.time ~= currentTime then
            continue
        end

        --Unique seed per day, time period, and event index
        local seed = currentDay + periodOffset + (i * 50000)
        local rng = Random.new(seed)

        if rng:NextNumber() <= data.Chance then
            return eventName
        end
    end

    return nil
end

--Listeners--
--Adds/removes player stats when the world event updates
workspace:GetAttributeChangedSignal('worldEvent'):Connect(function()
    if oldWorldEvent then
        local statDict = worldEventData[oldWorldEvent].Stats
        for _, plr in Players:GetPlayers() do
            removeStatsFromPlr(plr, statDict)
        end
    end

    currentWorldEvent = workspace:GetAttribute('worldEvent')
    if currentWorldEvent then
        local statDict = worldEventData[currentWorldEvent].Stats
        for _, plr in Players:GetPlayers() do
            applyStatsToPlr(plr, statDict)
        end
    end

    oldWorldEvent = currentWorldEvent
end)

--Clears current event and rolls for a new one when the time of day changes
workspace:GetAttributeChangedSignal('time'):Connect(function()
    local currentTime = workspace:GetAttribute('time')

    workspace:SetAttribute('worldEvent', nil)

    currentWorldEvent = getWorldEvent(currentTime)
    workspace:SetAttribute('worldEvent', currentWorldEvent)
end)

--Applies event stats to players who join mid-event
Players.PlayerAdded:Connect(function(plr)
    if currentWorldEvent then
        local statDict = worldEventData[currentWorldEvent].Stats
        applyStatsToPlr(plr, statDict)
    end
end)