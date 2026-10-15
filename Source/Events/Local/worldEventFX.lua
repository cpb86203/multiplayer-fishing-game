--Handles client-side world event visuals (sky, color correction, messages)

--Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

--Modules
local serverMessageModule = require(ReplicatedStorage.modules.GUI.serverMessageModule)
local EventData = require(ReplicatedStorage.modules.gameData.EventData)

--Player
local plr = Players.LocalPlayer

--Objects
local skyBox = Lighting:WaitForChild('Sky')
local CCFolder = ReplicatedStorage.Lighting.colorCorrections.worldEvents

--Data
local worldEventData = EventData.worldEventData

--Constants
local DEFAULT_MOON_TEXTURE_ID = 'rbxasset://sky/moon.jpg'
local DEFAULT_SUN_TEXTURE_ID = 'rbxasset://sky/sun.jpg'

local CC_TWEEN_TIME = 10
local CC_TWEEN_INFO = TweenInfo.new(CC_TWEEN_TIME, Enum.EasingStyle.Quad)
local CC_PROPERTIES = {"Brightness", "Contrast", "Saturation", "TintColor"}

--State
local CCTweenDict = {}
local CCCLNE = nil
local oldEvent = nil

--Fades a ColorCorrectionEffect in or out
local function fadeCC(colorCorrection: ColorCorrectionEffect, fadeIn)
    if not colorCorrection then
        warn('NO COLOR CORRECTION')
        return
    end

    local existingTween = CCTweenDict[colorCorrection]
    if existingTween and existingTween.PlaybackState == Enum.PlaybackState.Playing then
        existingTween:Cancel()
    end

    local propertyDict = {}

    if fadeIn then
        for _, property in CC_PROPERTIES do
            local defaultValue = colorCorrection[property]
            propertyDict[property] = defaultValue

            if typeof(defaultValue) == 'number' then
                colorCorrection[property] = 0
            elseif typeof(defaultValue) == 'Color3' then
                colorCorrection[property] = Color3.new(1, 1, 1)
            end
        end

        local goal = {}
        for _, property in CC_PROPERTIES do
            goal[property] = propertyDict[property]
        end

        local tween = TweenService:Create(colorCorrection, CC_TWEEN_INFO, goal)
        tween:Play()
        CCTweenDict[colorCorrection] = tween
    else
        for _, property in CC_PROPERTIES do
            local defaultValue = colorCorrection[property]

            if typeof(defaultValue) == 'number' then
                propertyDict[property] = 0
            elseif typeof(defaultValue) == 'Color3' then
                propertyDict[property] = Color3.new(1, 1, 1)
            end
        end

        local goal = {}
        for _, property in CC_PROPERTIES do
            goal[property] = propertyDict[property]
        end

        local tween = TweenService:Create(colorCorrection, CC_TWEEN_INFO, goal)
        tween:Play()
        CCTweenDict[colorCorrection] = tween

        --Wait here so that the CC is destroyed after the tween ends
        task.wait(CC_TWEEN_TIME)
    end
end

--Cleans up previous event and applies visuals for the new one
local function initEvent(worldEventSTR)
    if oldEvent then
        local eventData = worldEventData[oldEvent]
        local ToggleFunction = eventData.ToggleFunction
        if ToggleFunction then
            ToggleFunction(false)
        end
    end

    if CCCLNE then
        task.spawn(function()
            local savedCCCLNE = CCCLNE
            fadeCC(savedCCCLNE, false)
            CCTweenDict[savedCCCLNE] = nil
            savedCCCLNE:Destroy()
        end)
    end

    oldEvent = worldEventSTR

    if not worldEventSTR then
        skyBox.MoonTextureId = DEFAULT_MOON_TEXTURE_ID
        skyBox.SunTextureId = DEFAULT_SUN_TEXTURE_ID
        return
    end

    local eventData = worldEventData[worldEventSTR]

    skyBox.MoonTextureId = eventData.MoonTextureId or DEFAULT_MOON_TEXTURE_ID
    skyBox.SunTextureId = eventData.SunTextureId or DEFAULT_SUN_TEXTURE_ID

    local ToggleFunction = eventData.ToggleFunction
    if ToggleFunction then
        ToggleFunction(true)
    end

    CCCLNE = CCFolder:FindFirstChild(worldEventSTR)
    if CCCLNE then
        CCCLNE.Parent = Lighting
    end

    if plr:GetAttribute('inside') then
        CCCLNE.Enabled = false
    end

    fadeCC(CCCLNE, true)

    local messageData = eventData.MessageData
    serverMessageModule.customMessage(messageData.str, messageData.color)
end

--Listeners--
--Inits new world event
workspace:GetAttributeChangedSignal('worldEvent'):Connect(function()
    local worldEventSTR = workspace:GetAttribute('worldEvent')
    initEvent(worldEventSTR)
end)

--Toggle CC if player is inside/outside
plr:GetAttributeChangedSignal('inside'):Connect(function()
    if not CCCLNE then return end
    CCCLNE.Enabled = not plr:GetAttribute('inside')
end)

--Applies event effects if a player joins after it started
local function main()
    local worldEventSTR = workspace:GetAttribute('worldEvent')
    initEvent(worldEventSTR)
end

main()