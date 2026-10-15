--Handles water chunk creation, removal, and level of detail (LOD) based on player distance

--Player, services
local player = game.Players.LocalPlayer
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

--Char
local char = player.Character or player.CharacterAdded:Wait()
local HRP = char:WaitForChild("HumanoidRootPart")

player.CharacterAdded:Connect(function(newChar)
	char = newChar
	HRP = newChar:WaitForChild("HumanoidRootPart")
end)

--Water folders
local waterChunks = workspace:WaitForChild('waterChunks')
local physicsFolder = waterChunks:WaitForChild('physics')
local renderFolder = waterChunks:WaitForChild('render')

--Animation folders
local physicsEnv = physicsFolder:WaitForChild('environment')
local physicsOcean = physicsFolder:WaitForChild('ocean')

local chunkPart = ReplicatedStorage:WaitForChild('Objects'):WaitForChild('waterGridPartModel')
local chunkPartSize = chunkPart.waterGridPart.Size.X

--Settings
local RENDER_DISTANCE = 10
local CHUNK_PHYSICS_DISTANCE = 4
local centerPosX, centerPosZ = 0, 0

local chunkMap = {} --Key: "x,z" Value: Model
local chunksTable = {} --waterGridParts

--Helpers--
--Converts a world position vector into grid chunk coordinates
local function getCoords(pos)
	return math.round(pos.X / chunkPartSize), math.round(pos.Z / chunkPartSize)
end

--Updates the center chunk coordinates based on the player's position
local function updateCenterPos()
	if not HRP then return end
	local pos = HRP.Position
	centerPosX, centerPosZ = getCoords(pos)
end

--Checks if grid coordinates are out of range from the center position
local function isOutOfRange(x, z, range)
	return math.abs(x - centerPosX) > range or math.abs(z - centerPosZ) > range
end

--Water functions--
--Adds a water model to chunkMap dictionary and adds the water part to chunksTable
local function registerChunk(model)
	local gridPart = model:FindFirstChild("waterGridPart")
	if not gridPart then return end

	local cx, cz = getCoords(gridPart.Position)
	local key = cx .. "," .. cz

	chunkMap[key] = model
	if not table.find(chunksTable, gridPart) then
		table.insert(chunksTable, gridPart)
	end
end

--Creates a chunk at the gizen coordinates
local function createChunk(x, z)
	task.wait()
	
	local key = x .. "," .. z
	if chunkMap[key] then return end 

	local chunkClone = chunkPart:Clone()
	chunkClone:PivotTo(CFrame.new(x * chunkPartSize, 4, z * chunkPartSize) * CFrame.Angles(math.rad(90), 0, 0))

	--Start in render (unanimated)
	chunkClone.Parent = renderFolder

	chunkMap[key] = chunkClone
	table.insert(chunksTable, chunkClone.waterGridPart)
end

--Loads, animates, and unloads chunks based on player distance
local function updateChunkLOD()
	updateCenterPos()

	--Look for manual chunks that have may have streamed in
	for _, child in waterChunks:GetDescendants() do
		if child:IsA("Model") and child:FindFirstChild("waterGridPart") then
			registerChunk(child)
		end
	end

	--Create ocean chunks
	for x = centerPosX - RENDER_DISTANCE, centerPosX + RENDER_DISTANCE do
		for z = centerPosZ - RENDER_DISTANCE, centerPosZ + RENDER_DISTANCE do
			if not chunkMap[x .. "," .. z] then
				createChunk(x, z)
			end
		end
	end

	--Update chunks to be animated or still
	for i = #chunksTable, 1, -1 do
		local gridPart = chunksTable[i]
		local model = gridPart.Parent

		--If model is gone, then remove from the table
		if not model or not model:IsDescendantOf(workspace) then
			table.remove(chunksTable, i)
			continue
		end

		local cx, cz = getCoords(gridPart.Position)
		local waterType = model:GetAttribute("waterType") or "ocean"

		if isOutOfRange(cx, cz, RENDER_DISTANCE) then
			task.wait()
			
			--Destroy ocean, keep manual environment chunks
			if waterType ~= "environment" then
				chunkMap[cx .. "," .. cz] = nil
				model:Destroy()
				table.remove(chunksTable, i)
			else
				model.Parent = renderFolder --Stop animating environment
			end
		else
			--Check if outside physics distance
			if isOutOfRange(cx, cz, CHUNK_PHYSICS_DISTANCE) then
				if model.Parent ~= renderFolder then
					model.Parent = renderFolder
				end
			else
				--Inside physics distance, move folder to animate
				local target = (waterType == "environment") and physicsEnv or physicsOcean
				if model.Parent ~= target then
					model.Parent = target
				end
			end
		end
	end
end

--Run
task.spawn(function()
	while true do
		updateChunkLOD()
		task.wait(0.5)
	end
end)