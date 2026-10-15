--Calculates wave physics for visible water by using frustum culling

--Player, services
local player = game.Players.LocalPlayer
local ReplicatedStorage = game:GetService("ReplicatedStorage")


--Modules
local frustumCullingModule = require(ReplicatedStorage:WaitForChild('waterInfoModules').frustumCullingModule)

--Folders, values
local physicsChunks = workspace:WaitForChild('waterChunks'):WaitForChild('physics')
local waterTranslationNum = ReplicatedStorage:WaitForChild('values'):WaitForChild('waterTranslationNum')

--Camera
local camera = workspace.Camera

--Wave Settings
local OCEAN_SCALE = 2000
local OCEAN_FREQUENCY = 200
local OCEAN_AMPLITUDE = 5

local ENV_SCALE = 2000
local ENV_FREQUENCY = 100
local ENV_AMPLITUDE = 3

local waveTime = 0.05

--Bone storage and original position tracking
local oceanBoneTable = {}
local environmentBoneTable = {}
local boneOriginalPositions = {} --Key: Bone, Value: {x = number, z = number}

--Water functions--
--Initializes environment water bones and saves their original positions and default heights
local function setupEnvironmentBones(chunk)
	local gridPart = chunk:FindFirstChild("waterGridPart")
	if not gridPart then return end

	local rawWaterHeight = gridPart.CFrame.Position.Y
	local roundedWaterHeight = math.round(rawWaterHeight * 100) / 100

	for _, object in gridPart:GetChildren() do
		if object:IsA('Bone') then
			--Ignore edge pieces (waterfall edges, etc)
			if object:GetAttribute('edge') then continue end

			object:SetAttribute('defaultY', roundedWaterHeight)

			local bonePos = object.WorldCFrame.Position
			boneOriginalPositions[object] = {x = bonePos.X, z = bonePos.Z}

			table.insert(environmentBoneTable, object)
		end
	end
end

--Applies procedural wave height displacement to bones visible within the camera frustum
local function updateBones(boneTable, planes, translation, scale, frequency, amplitude)
	local char = player.Character
	if not char then return end

	local HRP = char:FindFirstChild('HumanoidRootPart')
	if not HRP then return end

	for _, bone in boneTable do
		local bonePos = bone.WorldCFrame.Position

		--If visible, then compute
		if frustumCullingModule:findInFrustum(planes, bonePos) then
			local originalPos = boneOriginalPositions[bone]
			if not originalPos then continue end
			
			--Get height using world coordinates
			local x, z = originalPos.x, originalPos.z
			local noise = math.noise((((x + translation) % scale) / scale) * frequency, ((z % scale) / scale) * frequency)

			--Normalize and scale based on amplitude
			noise = math.clamp(noise, -1, 1) * amplitude

			--Apply
			local defaultYPos = bone:GetAttribute('defaultY') or 4
			bone.WorldCFrame = CFrame.new(x, defaultYPos + noise, z)
		end
	end
end

--Listeners--
physicsChunks.environment.ChildAdded:Connect(setupEnvironmentBones)

--Removes bones and tracking data when an environment chunk is removed
physicsChunks.environment.ChildRemoved:Connect(function(child)
	local waterGridPart = child:FindFirstChild('waterGridPart')
	if not waterGridPart then return end

	for i = #environmentBoneTable, 1, -1 do
		local bone = environmentBoneTable[i]
		if bone.Parent == waterGridPart then
			boneOriginalPositions[bone] = nil
			table.remove(environmentBoneTable, i)
		end
	end
end)

--Registers newly added ocean chunk bones and stores their original positions
physicsChunks.ocean.ChildAdded:Connect(function(child)
	local gridPart = child:FindFirstChild('waterGridPart')
	if not gridPart then return end

	for _, object in gridPart:GetChildren() do
		if object:IsA('Bone') then
			--Save default position (for offset and setting it back later)
			local bonePos = object.WorldCFrame.Position
			boneOriginalPositions[object] = {x = bonePos.X, z = bonePos.Z}
			table.insert(oceanBoneTable, object)
		end
	end
end)

--Resets bone positions and cleans up tracking data when an ocean chunk is removed
physicsChunks.ocean.ChildRemoved:Connect(function(child)
	local waterGridPart = child:FindFirstChild('waterGridPart')
	if not waterGridPart then return end

	for i = #oceanBoneTable, 1, -1 do
		local bone = oceanBoneTable[i]
		if bone.Parent == waterGridPart then
			--Set back to default height
			local originalPos = boneOriginalPositions[bone]
			if originalPos then
				bone.WorldCFrame = CFrame.new(originalPos.x, 4, originalPos.z)
			end

			boneOriginalPositions[bone] = nil
			table.remove(oceanBoneTable, i)
		end
	end
end)

--Run
local function main()
	--Setup existing environment chunks
	for _, chunk in physicsChunks.environment:GetChildren() do
		setupEnvironmentBones(chunk)
	end

	--
	while true do
		task.wait(waveTime)

		--Get view frustum planes up to 400 distance
		local planes = frustumCullingModule:getFrustum(camera, 400)
		local translation = waterTranslationNum.Value

		--Update bone positions
		updateBones(oceanBoneTable, planes, translation, OCEAN_SCALE, OCEAN_FREQUENCY, OCEAN_AMPLITUDE)
		updateBones(environmentBoneTable, planes, translation, ENV_SCALE, ENV_FREQUENCY, ENV_AMPLITUDE)
	end
end

main()