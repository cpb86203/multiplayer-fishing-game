--Gets water surface height and color

--Folders
local waterChunks = game.Workspace:WaitForChild('waterChunks')

--Constants
const correctTriangleVector = Vector2.new(0.7071173787117004, 0.7070961594581604)
const UPDATES_PER_SECOND = 200
const TRANSLATION_NUM = .025

--Water functions--
--Determines the missing grid coordinate for a valid triangle given three closest points
local function findMissingPosition(closestPoints)
	local p1, p2, p3 = closestPoints[1], closestPoints[2], closestPoints[3]

	--Round to stop floating point errors
	local roundedP1X = math.round(p1.X * 10)
	local roundedP2X = math.round(p2.X * 10)
	local roundedP3X = math.round(p3.X * 10)

	local roundedP1Z = math.round(p1.Z * 10)
	local roundedP2Z = math.round(p2.Z * 10)
	local roundedP3Z = math.round(p3.Z * 10)

	local missingX = (roundedP1X == roundedP2X) and roundedP3X or (roundedP1X == roundedP3X) and roundedP2X or roundedP1X
	local missingZ = (roundedP1Z == roundedP2Z) and roundedP3Z or (roundedP1Z == roundedP3Z) and roundedP2Z or roundedP1Z

	return missingX, missingZ
end

--Locates the bone at the missing grid position and returns its world position
local function getFinalPointFromGrid(waterGridPart: MeshPart, boneMagnitudeDict, distanceTable)
	local closestPoints = {}

	for i = 1, 3 do
		table.insert(closestPoints, boneMagnitudeDict[distanceTable[i]][2])
	end

	local missingX, missingZ = findMissingPosition(closestPoints)

	for _, bone in waterGridPart:GetChildren() do
		if bone:IsA('Bone') then
			local boneLocalPos = bone.Position
			if math.round(boneLocalPos.X * 10) == missingX and math.round(boneLocalPos.Z * 10) == missingZ then
				return bone.WorldPosition
			end
		end
	end
end

--Checks whether three points form a correct triangle using dot
local function checkTriangle(points)
	for _, point1 in points do 
		for _, point2 in points do
			local vector: Vector3 = (point1 - point2).Unit
			local TwoDVector = Vector2.new(vector.X, vector.Z)

			local dotProduct = correctTriangleVector:Dot(TwoDVector)
			local roundedDot = math.round(dotProduct * 100) / 100

			if roundedDot == 0 then
				return false
			end
		end
	end
	
	return true
end

--Projects a point vertically onto a plane using a point and unit normal
local function ProjectVertically(vec, p, n)
	local off = vec - p
	local y = -(n.X * off.X + n.Z * off.Z) / n.Y
	
	return p + Vector3.new(off.X, y, off.Z)
end

--Projects a position vertically onto the plane formed by three points a, b, and c
local function ProjectToPlane(pos, a, b, c)
	local ab, bc = b - a, c - b
	local n = ab:Cross(bc).Unit

	if n.Y < 0 then n = -n end -- Ensure normal points upward

	return ProjectVertically(pos, a, n)
end

--Finds the three closest bones to a world position and determines a valid triangle for plane projection
local function getPoints(vector3Pos)
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Include
	rayParams.FilterDescendantsInstances = {waterChunks.physics}

	local rayResult = workspace:Raycast(vector3Pos + Vector3.new(0, 500, 0), Vector3.new(0, -2000, 0), rayParams)
	if not rayResult then return nil end

	local waterGridPart = rayResult.Instance.Parent.waterGridPart

	local boneDataList = {}
	for _, bone: Bone in waterGridPart:GetChildren() do
		if bone:IsA('Bone') then
			local boneWorldPos = bone.WorldCFrame.Position
			local boneLocalPos = bone.Position
			local normalizedBoneWorldPos = Vector3.new(boneWorldPos.X, 0, boneWorldPos.Z)
			local distanceFromPart = (normalizedBoneWorldPos - vector3Pos).Magnitude

			table.insert(boneDataList, {distanceFromPart, boneWorldPos, boneLocalPos})
		end
	end

	table.sort(boneDataList, function(a, b)
		return a[1] < b[1]
	end)

	if #boneDataList < 3 then
		warn("Not enough bones found to form a plane!")
		return nil
	end

	local bone1WorldPos = boneDataList[1][2]
	local bone2WorldPos = boneDataList[2][2]
	local bone3WorldPos = boneDataList[3][2]

	local bone1LocalPos = boneDataList[1][3]
	local bone2LocalPos = boneDataList[2][3]
	local bone3LocalPos = boneDataList[3][3]

	local closestBoneWorldPositions = {bone1WorldPos, bone2WorldPos, bone3WorldPos}
	local closestBoneLocalPositions = {bone1LocalPos, bone2LocalPos, bone3LocalPos}

	local correctTriangleBool = checkTriangle(closestBoneLocalPositions)

	local finalPos
	if correctTriangleBool then
		finalPos = closestBoneWorldPositions[3]
	else
		local tempBoneMagnitudeDict = {
			[boneDataList[1][1]] = {bone1WorldPos, bone1LocalPos},
			[boneDataList[2][1]] = {bone2WorldPos, bone2LocalPos},
			[boneDataList[3][1]] = {bone3WorldPos, bone3LocalPos},
		}
		local tempDistanceTable = {boneDataList[1][1], boneDataList[2][1], boneDataList[3][1]}

		finalPos = getFinalPointFromGrid(waterGridPart, tempBoneMagnitudeDict, tempDistanceTable)
		if finalPos == nil then
			warn('Final water position is NIL, defaulting to best guess')
			finalPos = closestBoneWorldPositions[3]
		end
	end

	return closestBoneWorldPositions[1], closestBoneWorldPositions[2], finalPos, waterGridPart
end

--Returns a bone's position at a future point in time
local function getFutureBonePosition(currentPos, waterGridPart, scale, frequency, amplitude, futureTranslation)
	local x, z = currentPos.X, currentPos.Z

	local defaultYPos = 4
	for _, bone in waterGridPart:GetChildren() do
		if bone:IsA('Bone') and bone.WorldCFrame.Position == currentPos then
			defaultYPos = bone:GetAttribute('defaultY') or 4
			break
		end
	end

	local noise = math.noise(
		(((x + futureTranslation) % scale) / scale) * frequency,
		((z % scale) / scale) * frequency
	)
	noise = math.clamp(noise, -1, 1) * amplitude

	return Vector3.new(x, defaultYPos + noise, z)
end

--Module
local waterSurfaceModule = {}

--Returns the color of the water grid at the given world position
function waterSurfaceModule:getWaterColor(vector3Pos)
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Include
	rayParams.FilterDescendantsInstances = {waterChunks.physics}

	local rayResult = workspace:Raycast(vector3Pos + Vector3.new(0, 500, 0), Vector3.new(0, -2000, 0), rayParams)
	if not rayResult then return nil end

	local waterGridPart: Part = rayResult.Instance.Parent.waterGridPart

	return waterGridPart.Color
end

--Calculates the current water surface height at a world position by projecting onto the nearest triangle
function waterSurfaceModule:getWaterHeight(vector3Pos)
	local bone1, bone2, finalPos, waterGridPart = getPoints(vector3Pos)
	if not bone1 then return end

	local positionOnWater = ProjectToPlane(vector3Pos, bone1, bone2, finalPos)

	if positionOnWater.Y ~= positionOnWater.Y then
		warn('Water position is NAN')
	end

	return Vector3.new(vector3Pos.X, positionOnWater.Y, vector3Pos.Z), waterGridPart.Parent
end

--Predicts the future water surface height at a world position after a given time
function waterSurfaceModule:predictWaterHeight(vector3Pos, timeInFuture)
	local bone1, bone2, finalPos, waterGridPart = getPoints(vector3Pos)
	if not bone1 then return end

	local model = waterGridPart.Parent
	local scale = model:GetAttribute('scale')
	local frequency = model:GetAttribute('frequency')
	local amplitude = model:GetAttribute('amplitude')
	local futureTranslation = game.ReplicatedStorage.values.waterTranslationNum.Value + (timeInFuture * UPDATES_PER_SECOND) * TRANSLATION_NUM

	local future1 = getFutureBonePosition(bone1, waterGridPart, scale, frequency, amplitude, futureTranslation)
	local future2 = getFutureBonePosition(bone2, waterGridPart, scale, frequency, amplitude, futureTranslation)
	local future3 = getFutureBonePosition(finalPos, waterGridPart, scale, frequency, amplitude, futureTranslation)

	local positionOnWater = ProjectToPlane(vector3Pos, future1, future2, future3)

	if positionOnWater.Y ~= positionOnWater.Y then
		return nil, waterGridPart
	end

	return Vector3.new(vector3Pos.X, positionOnWater.Y, vector3Pos.Z), waterGridPart
end

return waterSurfaceModule