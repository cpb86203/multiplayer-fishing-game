--Handles player boat piloting (PC/mobile)

--Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")

--Modules
local serverMessageModule = require(ReplicatedStorage.modules.GUI.serverMessageModule)

--Player
local player = Players.LocalPlayer
local char = player.Character or player.CharacterAdded:Wait()
local HRP: Part = char:WaitForChild('HumanoidRootPart')
local hum: Humanoid = char:WaitForChild('Humanoid')

--Objects
local boatOBJValue = player:WaitForChild('boatOBJValue')
local equippedFishFolder = workspace:WaitForChild('EquippedFish')

--Settings
local CONFIG = {
    BaseRotationSpeed = 15,
    ControlAttributeScale = 10,
    SideDragMultiplier = 8,

    NormalCameraZoom = 40,
    LargeCameraZoom = 60,

    MaxDistanceFromPilot = 3,

    DefaultWalkSpeed = 16,
    DefaultJumpPower = 50,
    PilotJumpPower = 0.001,

    ExitPromptDelay = 1,
    ErrorCooldown = 1,

    InputDeadzone = 0.1,
    VelocityDeadzone = 0.1,
}

--Updating boat references (added+changed when calling setupBoat)
local refs = {}

--Boat connections
local cons = {
    moveForward = nil,
    moveBackward = nil,
    rotateLeft = nil,
    rotateRight = nil,
    mobile = nil,
    jumpRequest = nil,
    sailPrompt = nil,
    drag = nil,
    destroy = nil,
}

local pilotTrack: AnimationTrack = nil
local lastError = 0

--Disconnects connections
local function disconnect(name)
    if cons[name] then
        cons[name]:Disconnect()
        cons[name] = nil
    end
end

--Saves boat references (forces, mass, etc)
local function setupBoat(boatModel: Model)
    refs.model = boatModel
    refs.primary = boatModel.primary
    refs.values = boatModel.values
    refs.pilotPart = boatModel:WaitForChild('pilotPositionPart')
    refs.prompt = boatModel.proximityPart.sailProximityPrompt
    refs.prompt.Enabled = true
    refs.values.owner.Value = player

    local sailPart1 = boatModel:FindFirstChild('sailPart1')
    refs.sailAtt = sailPart1 and sailPart1:FindFirstChildOfClass('Attachment')

    refs.lookForce = refs.primary.lookVectorForce
    refs.lookForce.Enabled = true
    refs.dragForce = refs.primary.lookVectorDragForce
    refs.dragForce.Enabled = true

    refs.alignPos = refs.pilotPart.pilotAlignPosition
    refs.alignOri = refs.pilotPart.pilotAlignOrientation
    refs.yRotation = refs.values.yRotation

    local control = boatModel:GetAttribute('control') or CONFIG.ControlAttributeScale
    refs.rotationPerSecond = CONFIG.BaseRotationSpeed * (control / CONFIG.ControlAttributeScale)

    local ballastMass = boatModel.ballast:GetMass()
    refs.mass = refs.primary:GetMass() + ballastMass
    refs.acceleration = boatModel:GetAttribute('acceleration')
    refs.maxSpeed = boatModel:GetAttribute('maxSpeed')
    refs.drag = refs.mass * refs.acceleration / refs.maxSpeed
end

--Toggle player mass (the player's weight can interfere with boat movement)
local function togglePlrMass(enabled)
    for _, part in char:GetDescendants() do
        if part:IsA('BasePart') then
            part.Massless = enabled
        end
    end
end

--Move forward
local function moveForward(_, inputState)
    if inputState == Enum.UserInputState.Begin then
        disconnect('moveBackward')
        if cons.moveForward then return end

        cons.moveForward = RunService.RenderStepped:Connect(function()
            local lv = refs.primary.CFrame.LookVector
            local force = lv * (refs.mass * refs.acceleration)
            refs.lookForce.Force = Vector3.new(force.X, 0, force.Z)
        end)
    else
        disconnect('moveForward')
        refs.lookForce.Force = Vector3.zero
    end
end

--Move backward
local function moveBackward(_, inputState)
    if inputState == Enum.UserInputState.Begin then
        disconnect('moveForward')
        if cons.moveBackward then return end

        cons.moveBackward = RunService.RenderStepped:Connect(function()
            local lv = refs.primary.CFrame.LookVector
            local velXZ = Vector3.new(refs.primary.AssemblyLinearVelocity.X, 0, refs.primary.AssemblyLinearVelocity.Z)

            if velXZ.Magnitude < refs.maxSpeed then
                local force = lv * (refs.mass * refs.acceleration)
                refs.lookForce.Force = -Vector3.new(force.X, 0, force.Z)
            else
                refs.lookForce.Force = Vector3.zero
            end
        end)
    else
        disconnect('moveBackward')
        refs.lookForce.Force = Vector3.zero
    end
end

--Rotates left while held
local function rotateLeft(_, inputState)
    if inputState == Enum.UserInputState.Begin then
        disconnect('rotateRight')
        if cons.rotateLeft then return end

        cons.rotateLeft = RunService.RenderStepped:Connect(function(dt)
            refs.yRotation.Value += dt * refs.rotationPerSecond
        end)
    else
        disconnect('rotateLeft')
    end
end

--Rotates right while held
local function rotateRight(_, inputState)
    if inputState == Enum.UserInputState.Begin then
        disconnect('rotateLeft')
        if cons.rotateRight then return end

        cons.rotateRight = RunService.RenderStepped:Connect(function(dt)
            refs.yRotation.Value -= dt * refs.rotationPerSecond
        end)
    else
        disconnect('rotateRight')
    end
end

--Mobile controls
local function startMobileControls()
    disconnect('mobile')

    cons.mobile = RunService.RenderStepped:Connect(function(dt)
        local localMove = refs.primary.CFrame:VectorToObjectSpace(hum.MoveDirection)

        if math.abs(localMove.X) > CONFIG.InputDeadzone then
            refs.yRotation.Value -= localMove.X * refs.rotationPerSecond * dt
        end

        if localMove.Z < -CONFIG.InputDeadzone then
            local lv = refs.primary.CFrame.LookVector
            local force = lv * (refs.mass * refs.acceleration)
            refs.lookForce.Force = Vector3.new(force.X, 0, force.Z)
        elseif localMove.Z > CONFIG.InputDeadzone then
            local lv = refs.primary.CFrame.LookVector
            local velXZ = Vector3.new(refs.primary.AssemblyLinearVelocity.X, 0, refs.primary.AssemblyLinearVelocity.Z)

            if velXZ.Magnitude < refs.maxSpeed then
                local force = lv * (refs.mass * refs.acceleration)
                refs.lookForce.Force = -Vector3.new(force.X, 0, force.Z)
            else
                refs.lookForce.Force = Vector3.zero
            end
        else
            refs.lookForce.Force = Vector3.zero
        end
    end)
end

--Exits the boat
local function exit(_, inputState)
    if inputState and typeof(inputState) == "EnumItem" and inputState ~= Enum.UserInputState.Begin then
        return
    end

    togglePlrMass(false)

    if pilotTrack and pilotTrack.IsPlaying then
        pilotTrack:Stop()
    end

    player:SetAttribute('inBoat', nil)
    player:SetAttribute('emotesDisabled', nil)
    player:SetAttribute('equipsDisabled', nil)
    player.CameraMaxZoomDistance = game.StarterPlayer.CameraMaxZoomDistance

    for _, desc in refs.model:GetDescendants() do
        if desc:IsA('BasePart') then
            desc.CollisionGroup = 'Default'
        end
    end

    refs.alignPos.Attachment0 = nil
    refs.alignOri.Attachment0 = nil

    for _, name in {'mobile', 'jumpRequest', 'moveForward', 'moveBackward', 'rotateLeft', 'rotateRight'} do
        disconnect(name)
    end

    refs.lookForce.Force = Vector3.zero

    ContextActionService:UnbindAction('moveForward')
    ContextActionService:UnbindAction('moveBackward')
    ContextActionService:UnbindAction('rotateLeft')
    ContextActionService:UnbindAction('rotateRight')
    ContextActionService:UnbindAction('exit')

    hum.WalkSpeed = CONFIG.DefaultWalkSpeed
    hum.JumpPower = CONFIG.DefaultJumpPower

    task.wait(CONFIG.ExitPromptDelay)
    refs.prompt.Enabled = true
end

--Bind PC or mobile controls
local function enableControls()
    if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
        startMobileControls()
    else
        ContextActionService:BindAction('moveForward', moveForward, false, Enum.KeyCode.W)
        ContextActionService:BindAction('moveBackward', moveBackward, false, Enum.KeyCode.S)
        ContextActionService:BindAction('rotateLeft', rotateLeft, false, Enum.KeyCode.A)
        ContextActionService:BindAction('rotateRight', rotateRight, false, Enum.KeyCode.D)
        ContextActionService:BindAction('exit', exit, false, Enum.KeyCode.Space, Enum.KeyCode.ButtonA)
    end

    cons.jumpRequest = UserInputService.JumpRequest:Connect(function()
        exit()
    end)
end

--Send error message to player
local function errorMessage(str)
    if tick() - lastError < CONFIG.ErrorCooldown then return end
    lastError = tick()
    serverMessageModule.errorMessage(str)
end

--Validates then seats the player and enables controls
local function setupPilot()
    if refs.values.owner.Value ~= player then
        errorMessage("You don't own this boat.")
        return
    end

    if equippedFishFolder:FindFirstChild(player.Name) then
        errorMessage('Unequip fish to pilot.')
        return
    end

    refs.prompt.Enabled = false

    player:SetAttribute('inBoat', true)
    player:SetAttribute('emotesDisabled', true)
    player:SetAttribute('equipsDisabled', true)

    local boatSize = refs.model:GetAttribute('size') or 'normal'
    player.CameraMaxZoomDistance = (boatSize == 'normal') and CONFIG.NormalCameraZoom or CONFIG.LargeCameraZoom

    for _, desc in refs.model:GetDescendants() do
        if desc:IsA('BasePart') then
            desc.CollisionGroup = 'Boats'
        end
    end

    char:PivotTo(refs.pilotPart.CFrame)

    local pilotAnim = refs.pilotPart:FindFirstChild('pilotAnim')
    if pilotAnim then
        pilotTrack = hum:FindFirstChildOfClass('Animator'):LoadAnimation(pilotAnim)
        pilotTrack.Priority = Enum.AnimationPriority.Action4
        pilotTrack:Play(0)
    end

    refs.alignPos.Attachment0 = HRP.RootAttachment
    refs.alignOri.Attachment0 = HRP.RootAttachment

    hum.WalkSpeed = 0
    hum.JumpPower = CONFIG.PilotJumpPower

    togglePlrMass(true)
    enableControls()
end

--Exits the player if they're too far from the pilot position
local function exitIfTooFar()
    if not player:GetAttribute('inBoat') then return end

    local distance = (refs.pilotPart.Position - HRP.Position).Magnitude
    if distance > CONFIG.MaxDistanceFromPilot then
        exit(nil, Enum.UserInputState.Begin)
    end
end

--Update a boat change (new boat, no boat)
boatOBJValue.Changed:Connect(function(boatModel: Model)
    disconnect('sailPrompt')
    disconnect('drag')
    disconnect('destroy')

    if not boatModel then return end

    cons.destroy = boatModel.Destroying:Once(function()
        boatOBJValue.Value = nil
    end)

    setupBoat(boatModel)
    cons.sailPrompt = refs.prompt.Triggered:Connect(setupPilot)

    cons.drag = RunService.RenderStepped:Connect(function()
        if not boatModel or not boatModel.PrimaryPart then
            disconnect('drag')
            return
        end

        exitIfTooFar()

        local primary = boatModel.PrimaryPart
        local velocity = primary.AssemblyLinearVelocity
        local velXZ = Vector3.new(velocity.X, 0, velocity.Z)

        if velXZ.Magnitude < CONFIG.VelocityDeadzone then
            refs.dragForce.Force = Vector3.zero
            return
        end

        --Longitudinal drag
        local forward = primary.CFrame.LookVector
        local forwardDrag = -forward * (velXZ:Dot(forward) * refs.drag)

        --Lateral resistance
        local side = primary.CFrame.RightVector
        local sideDrag = -side * (velXZ:Dot(side) * refs.drag * CONFIG.SideDragMultiplier)

        refs.dragForce.Force = forwardDrag + sideDrag
    end)
end)