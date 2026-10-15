--Randomly triggers random water events on nearby chunks for players

--Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

--Modules
local EventData = require(ReplicatedStorage.modules.gameData.EventData)

--Events
local getRandomChunkRF = ReplicatedStorage.Events.player.getRandomChunkRF

--Objects, data
local waterEventModel = ReplicatedStorage.Objects.waterEventModel
local waterEventDataDict = EventData.waterEventData

--Settings
local eventRarityOrder = {'Enchanted Waters', 'Whirlpool', 'Bubbles'}

--Combination of these two values targets roughly one event every ~6 minutes
const TIME_UNTIL_NEXT_EVENT = 36
const EVENT_CHANCE = 0.1

const CHECK_RADIUS = 800
const DEFAULT_WATER_SIZE = 300

--Applies a water event model to a random chunk near a player, including FX and scaling
local function applyEventToRandomChunk(waterEventSTR)
    local plrs = Players:GetPlayers()
    if #plrs == 0 then
        return
    end
    
    local randomPlr = plrs[math.random(#plrs)]
    if not randomPlr then
        return
    end
    
    --Request a random chunk CFrame and size from the client within CHECK_RADIUS
    local randomChunkINFO = getRandomChunkRF:InvokeClient(randomPlr, CHECK_RADIUS)
    if not randomChunkINFO then
        return
    end
    
    local randomChunkCF: CFrame, randomChunkSize: Vector3 = table.unpack(randomChunkINFO)
    
    local waterEventModelCLNE = waterEventModel:Clone()
    local plrDetector = waterEventModelCLNE.PlrDetector
    local waterEventPart = waterEventModelCLNE.PrimaryPart
    
    waterEventModelCLNE:SetAttribute('waterEvent', waterEventSTR)
    
    local waterEventData = waterEventDataDict[waterEventSTR]
    if not waterEventData then
        warn('no water event data')
        waterEventModelCLNE:Destroy()
        return
    end
    
    --Clone and parent, play sounds immediately
    local FXFolder: Folder = waterEventData.FXFolder
    for _, child in FXFolder:GetChildren() do
        local FXCLNE = child:Clone()
        FXCLNE.Parent = waterEventPart
        
        if FXCLNE:IsA('Sound') then
            FXCLNE:Play()
        end
    end
    
    --Re-bind beam attachments after cloning
    for _, child in waterEventPart:GetChildren() do
        if child:IsA('Beam') then
            local att0Name = child.Attachment0.Name
            local att1Name = child.Attachment1.Name
            
            if att0Name then
                local newAtt = waterEventPart:FindFirstChild(att0Name)
                child.Attachment0 = newAtt
            end
            
            if att1Name then
                local newAtt = waterEventPart:FindFirstChild(att1Name)
                child.Attachment1 = newAtt
            end
        end
    end
    
    --Scale particles to chunk size if needed
    if FXFolder:GetAttribute('scaleWithWater') then
        local multiplier = math.clamp(randomChunkSize.X / DEFAULT_WATER_SIZE, 0.01, 50)
        
        for _, particle in waterEventPart:GetDescendants() do
            if particle:IsA('ParticleEmitter') and not particle:GetAttribute('constantRate') then
                local sizeNumberSequence = particle.Size
                local newNumberSequenceKeypoints = {}
                
                for _, keypoint: NumberSequenceKeypoint in sizeNumberSequence.Keypoints do
                    local newValue = keypoint.Value * multiplier
                    local newEnvelope = keypoint.Envelope * multiplier
                    local newKeypoint = NumberSequenceKeypoint.new(keypoint.Time, newValue, newEnvelope)
                    table.insert(newNumberSequenceKeypoints, newKeypoint)
                end
                
                particle.Size = NumberSequence.new(newNumberSequenceKeypoints)
            end
        end
    end
    
    --Finalize placement and size
    waterEventPart.CFrame = randomChunkCF
    waterEventPart.Size = Vector3.new(randomChunkSize.X, 0.25, randomChunkSize.Z)
    plrDetector.Size = Vector3.new(randomChunkSize.X, plrDetector.Size.Y, randomChunkSize.Z)
    waterEventModelCLNE.Parent = workspace.waterEventParts
    
    --Destroy after 3–9 minutes
    local eventDuration = math.random(180, 540)
    task.delay(eventDuration, function()
        waterEventModelCLNE:Destroy()
    end)
end

--Selects a water event based on rarity order, chance rolls, and time-of-day
local function getWaterEvent()
    local roll = math.random()
    
    for _, waterEventSTR in eventRarityOrder do
        local eventData = waterEventDataDict[waterEventSTR]
        
        local currentTime = workspace:GetAttribute('time')
        local timeCondition = eventData.Conditions.time
        
        if timeCondition and currentTime ~= timeCondition then
            continue
        end
        
        local chance = eventData.Chance
        if roll <= chance then
            return waterEventSTR
        end
    end
end

--Wait randomized time then roll a water event
local function main()
    while true do
        local waitTime = TIME_UNTIL_NEXT_EVENT + math.random(-5, 5)
        task.wait(waitTime)
        
        local roll = math.random()
        if roll <= EVENT_CHANCE then
            local waterEventSTR = getWaterEvent()
            if not waterEventSTR then
                warn('no water event: ', waterEventSTR)
            end
            applyEventToRandomChunk(waterEventSTR)
        end
    end
end

main()