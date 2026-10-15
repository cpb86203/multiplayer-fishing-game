--Applies boat buoyancy, pitch, and roll based on water surface

--Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--Modules
local getWaterHeightModule = require(ReplicatedStorage.waterInfoModules.getWaterHeightModule)
local serverMessageModule = require(ReplicatedStorage.modules.GUI.serverMessageModule)

--Player
local player = Players.LocalPlayer
local boatOBJValue = player:WaitForChild('boatOBJValue')

--Constants
local MAX_NIL_RETRIES = 50

local DEPTH_BEFORE_SUBMERGED = 7
local DISPLACEMENT_MULTIPLIER = 6
local DRAG_COEFFICIENT = 20
local BUOYANCY_RAMP_RATE = 4 --Limits how fast buoyancy can increase per second (prevents spikes at low FPS)

local DESPAWN_MESSAGE_COLOR = Color3.fromRGB(255, 126, 128)

--State
local boat: Model = nil
local nilCount = 0
local destroyCon = nil

--Averages water height across all boat buoys. Destroys the boat after repeated failures (the player is likely too far away)
local function boatY()
    local yTotal = 0
    local buoys = boat.buoys:GetChildren()
    local buoyCount = #buoys

    if buoyCount == 0 then
        return nil
    end

    for _, part in buoys do
        local waterPosition = getWaterHeightModule:getWaterHeight(part.Position)

        while not waterPosition do
            task.wait()

            if not boat then
                return nil
            end

            waterPosition = getWaterHeightModule:getWaterHeight(part.Position)

            nilCount += 1
            if nilCount >= MAX_NIL_RETRIES then
                nilCount = 0
                if boat then
                    boat:Destroy()
                end
                return nil
            end
        end

        nilCount = 0
        yTotal += waterPosition.Y
    end

    return yTotal / buoyCount
end

--Calculates pitch angle from the height difference between bow and stern
local function pitch(bow, stern)
    local bowWave = getWaterHeightModule:getWaterHeight(bow.Position)
    local sternWave = getWaterHeightModule:getWaterHeight(stern.Position)
    if not (bowWave and sternWave) then
        return nil
    end

    local h = bowWave.Y - sternWave.Y
    local b = (bowWave - sternWave).Magnitude
    return math.atan(h / b)
end

--Calculates roll angle from the height difference between port and starboard
local function roll(port, starboard)
    local portWave = getWaterHeightModule:getWaterHeight(port.Position)
    local starboardWave = getWaterHeightModule:getWaterHeight(starboard.Position)
    if not (portWave and starboardWave) then
        return nil
    end

    local h = portWave.Y - starboardWave.Y
    local b = (portWave - starboardWave).Magnitude
    return math.atan(h / b)
end

--Returns average water height, pitch, and roll for the current boat
local function getBoatOrientation(bow, stern, port, starboard)
    return boatY(), pitch(bow, stern), roll(port, starboard)
end

--Enables forces/orientation constraints and runs per-frame buoyancy + orientation physics
local function boatPhysics()
    local buoyantVectorForce = boat.primary.buoyantVectorForce
    buoyantVectorForce.Enabled = true

    local dragVectorForce = boat.primary.dragVectorForce
    dragVectorForce.Enabled = true

    local alignOrin = boat.primary.AlignOrientation
    alignOrin.Enabled = true

    local displacementAmount = (boat.PrimaryPart:GetMass() + boat.ballast:GetMass()) * DISPLACEMENT_MULTIPLIER
    local yRotationValue = boat.values.yRotation

    local corePositions = boat:WaitForChild('corePositions')
    local bow = corePositions:WaitForChild('bow')
    local stern = corePositions:WaitForChild('stern')
    local port = corePositions:WaitForChild('port')
    local starboard = corePositions:WaitForChild('starboard')

    if destroyCon then
        destroyCon:Disconnect()
    end

    destroyCon = boat.Destroying:Once(function()
        serverMessageModule.customMessage('Boat has been despawned.', DESPAWN_MESSAGE_COLOR)
        boatOBJValue.Value = nil
        boat = nil
    end)

    local previousDisplacement = 0

    local con
    con = RunService.Heartbeat:Connect(function(dt)
        if not boat or boat.Parent == nil or boat.PrimaryPart == nil then
            con:Disconnect()
            return
        end

        local currentBoatY, currentPitch, currentRoll = getBoatOrientation(bow, stern, port, starboard)

        --Skip frame if any value is missing or NaN. We have to compare the number to itself to detect NAN.
        if not (currentBoatY and currentPitch and currentRoll)
            or (currentBoatY ~= currentBoatY)
            or (currentPitch ~= currentPitch)
            or (currentRoll ~= currentRoll) then
            return
        end

        local prim = boat.primary
        if not prim then
            con:Disconnect()
            return
        end

        local cf = CFrame.Angles(currentPitch, math.rad(yRotationValue.Value), currentRoll)
        prim.AlignOrientation.CFrame = cf

        local boatPrimaryPos = prim.Position
        local waterPos = getWaterHeightModule:getWaterHeight(boatPrimaryPos)
        if not waterPos then
            return
        end

        local waterYHeight = waterPos.Y
        local velocity = prim.AssemblyLinearVelocity
        local predictedY = boatPrimaryPos.Y + velocity.Y * dt
        local depth = waterYHeight - predictedY

        if depth > 0 then
            local targetDisplacement = math.clamp(depth / DEPTH_BEFORE_SUBMERGED, 0, 1) * displacementAmount

            --Ramp buoyancy to avoid spikes at low frame rates
            local maxIncrease = displacementAmount * BUOYANCY_RAMP_RATE * dt
            local displacementMultiplier = math.min(targetDisplacement, previousDisplacement + maxIncrease)
            previousDisplacement = displacementMultiplier

            buoyantVectorForce.Force = Vector3.new(0, workspace.Gravity * displacementMultiplier, 0)
            dragVectorForce.Force = Vector3.new(0, -velocity.Y * DRAG_COEFFICIENT * displacementMultiplier, 0)
        else
            previousDisplacement = 0
            buoyantVectorForce.Force = Vector3.zero
            dragVectorForce.Force = Vector3.zero
        end
    end)
end

--Listens for the boatOBJvalue to update
boatOBJValue.Changed:Connect(function(newValue)
    if newValue then
        boat = newValue
        boatPhysics()
    else
        boat = nil
    end
end)