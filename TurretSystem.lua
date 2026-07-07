-- Connected Discord-GitHub | Discord: zyth_galaxy | Roblox: zyth_galaxy

--[[
	Automated Turret Defense & Projectile System
	Demonstrates: OOP (Metatables), CFrame Math, Kinematics, Spatial Queries, constraint-based Physics.
	
	Note : This script is fully self-contained. 
	Simply place in ServerScriptService and run the game. It will automatically build the 
	testing environment, spawn turrets, and generate targets to demonstrate its functionality.
	
	script made by zyth_galaxy
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")


-- CONFIGURATION

local Config = {
	TurretRange = 60, -- the range of the turret
	FireRate = 0.2, -- the fire rate of the turret
	BulletSpeed = 120, -- the bullet speed of the turret
	BulletGravity = Vector3.new(0, -workspace.Gravity * 0.5, 0), -- 50% gravity for slightly arc'd shots
	TargetSpawnRate = 1.5, -- the spawn rate of the targets
	MaxTargets = 8, -- max number of targets on screen at once
}


-- LIGHTWEIGHT SIGNAL CLASS (Custom Events)

-- Using a pure lua signal instead of BindableEvents for better performance
local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ _listeners = {} }, Signal)
end

function Signal:Connect(callback)
	table.insert(self._listeners, callback)
	local index = #self._listeners
	return {
		Disconnect = function()
			self._listeners[index] = nil
		end
	}
end

function Signal:Fire(...)
	for _, listener in pairs(self._listeners) do
		-- Run in separate thread to prevent yielding the main loop
		task.spawn(listener, ...) 
	end
end


-- TARGET CLASS (Physics based entity)

local Target = {}
Target.__index = Target
Target.AllTargets = {} 

function Target.new(spawnPosition)
	local self = setmetatable({}, Target)

	self.Health = 100
	self.Died = Signal.new()
	self.IsDead = false

	-- Build the physical target and setting its properties
	local part = Instance.new("Part")
	part.Size = Vector3.new(3, 3, 3)
	part.Position = spawnPosition
	part.Shape = Enum.PartType.Ball
	part.Color = Color3.fromRGB(255, 50, 50)
	part.Material = Enum.Material.Neon

	-- Using constraint physics for movement instead of BodyMovers since BodyMover class has been deprecated
	local attachment = Instance.new("Attachment", part)
	local linearVel = Instance.new("LinearVelocity", part)
	linearVel.Attachment0 = attachment
	linearVel.MaxForce = 50000
	linearVel.VectorVelocity = Vector3.zero

	self.Instance = part
	self.VelocityMover = linearVel
	self.ChangeTimer = 0

	part.Parent = Workspace
	table.insert(Target.AllTargets, self)

	return self
end

function Target:Wander(dt)
	if self.IsDead then return end

	self.ChangeTimer -= dt
	if self.ChangeTimer <= 0 then
		self.ChangeTimer = math.random(1, 3)
		-- Generate a random direction on the XZ plane
		local randomDir = Vector3.new(math.random(-10, 10), 0, math.random(-10, 10)).Unit
		-- Fallback if unit vector results in NaN
		if randomDir.X ~= randomDir.X then randomDir = Vector3.new(1,0,0) end 

		local speed = math.random(15, 25)
		self.VelocityMover.VectorVelocity = randomDir * speed
	end
end

function Target:TakeDamage(amount)
	if self.IsDead then return end

	self.Health -= amount
	-- Visual feedback
	local flash = self.Instance:Clone()
	flash.Size = self.Instance.Size + Vector3.new(0.5, 0.5, 0.5)
	flash.Color = Color3.new(1, 1, 1)
	flash.Transparency = 0.5
	flash.CanCollide = false
	flash.Parent = Workspace
	Debris:AddItem(flash, 0.1)

	if self.Health <= 0 then
		self.IsDead = true
		self.Died:Fire(self)
		self:Destroy()
	end
end

function Target:Destroy()
	self.Instance:Destroy()
	-- Remove from global tracker to prevent memory leaks
	for i, target in ipairs(Target.AllTargets) do
		if target == self then
			table.remove(Target.AllTargets, i)
			break
		end
	end
end


-- PROJECTILE CLASS (Kinematic, Raycast-based)

local Projectile = {}
Projectile.__index = Projectile
Projectile.ActiveProjectiles = {}

function Projectile.new(startCFrame, velocity, damage)
	local self = setmetatable({}, Projectile)

	self.CurrentCFrame = startCFrame
	self.Velocity = velocity
	self.Damage = damage
	self.Age = 0
	self.MaxLifetime = 4
	self.IsActive = true

	-- The visual part is used, but the actual hit detection is done via raycasting
	local visual = Instance.new("Part")
	visual.Size = Vector3.new(0.2, 0.2, 2)
	visual.Color = Color3.fromRGB(255, 200, 0)
	visual.Material = Enum.Material.Neon
	visual.Anchored = true
	visual.CanCollide = false
	visual.CFrame = startCFrame

	self.Visual = visual
	self.Visual.Parent = Workspace

	-- Ignore targets list is built when firing, but for now we just use a basic RaycastParams
	self.RayParams = RaycastParams.new()
	self.RayParams.FilterType = Enum.RaycastFilterType.Exclude

	table.insert(Projectile.ActiveProjectiles, self)
	return self
end

function Projectile:Update(dt)
	if not self.IsActive then return end

	self.Age += dt
	if self.Age >= self.MaxLifetime then
		self:Destroy()
		return
	end

	-- Kinematics: apply gravity to velocity
	self.Velocity += Config.BulletGravity * dt
	local stepDisplacement = self.Velocity * dt

	-- Raycast for hit detection this frame
	local result = Workspace:Raycast(self.CurrentCFrame.Position, stepDisplacement, self.RayParams)

	if result and result.Instance then
		self:OnHit(result.Instance, result.Position)
	else
		-- Move bullet forward if no hit
		local nextPos = self.CurrentCFrame.Position + stepDisplacement
		-- CFrame.lookAt aligns the bullet with its velocity vector
		self.CurrentCFrame = CFrame.lookAt(nextPos, nextPos + self.Velocity)
		self.Visual.CFrame = self.CurrentCFrame
	end
end

function Projectile:OnHit(hitInstance, hitPosition)
	self.IsActive = false

	-- Check if we hit a valid Target object
	for _, target in ipairs(Target.AllTargets) do
		if target.Instance == hitInstance then
			target:TakeDamage(self.Damage)
			break
		end
	end

	self:Destroy()
end

function Projectile:Destroy()
	self.IsActive = false
	self.Visual:Destroy()

	for i, proj in ipairs(Projectile.ActiveProjectiles) do
		if proj == self then
			table.remove(Projectile.ActiveProjectiles, i)
			break
		end
	end
end


-- TURRET CLASS (CFrame math, Spatial queries)

local Turret = {}
Turret.__index = Turret
Turret.AllTurrets = {}

function Turret.new(position)
	local self = setmetatable({}, Turret)

	self.LastFired = 0
	self.CurrentTarget = nil
	self.BasePosition = position

	-- Construct The Turret Model
	local base = Instance.new("Part")
	base.Size = Vector3.new(4, 1, 4)
	base.Position = position
	base.Anchored = true
	base.Color = Color3.fromRGB(50, 50, 50)

	local pivot = Instance.new("Part")
	pivot.Size = Vector3.new(2, 2, 2)
	pivot.CFrame = CFrame.new(position + Vector3.new(0, 1.5, 0))
	pivot.Anchored = true
	pivot.Color = Color3.fromRGB(100, 100, 100)

	local barrel = Instance.new("Part")
	barrel.Size = Vector3.new(0.5, 0.5, 4)
	-- Offset barrel from pivot
	barrel.CFrame = pivot.CFrame * CFrame.new(0, 0, -2)
	barrel.Anchored = true
	barrel.Color = Color3.fromRGB(20, 20, 20)

	self.Pivot = pivot
	self.Barrel = barrel
	self.Base = base

	base.Parent = Workspace
	pivot.Parent = Workspace
	barrel.Parent = Workspace

	-- Setup params for spatial query 
	self.OverlapParams = OverlapParams.new()
	self.OverlapParams.FilterType = Enum.RaycastFilterType.Include

	table.insert(Turret.AllTurrets, self)
	return self
end

function Turret:ScanForTarget()
	-- Build a table of valid parts to query against (Target instances)
	local targetParts = {}
	for _, target in ipairs(Target.AllTargets) do
		table.insert(targetParts, target.Instance)
	end

	self.OverlapParams.FilterDescendantsInstances = targetParts

	-- Find parts within radius
	local partsInRadius = Workspace:GetPartBoundsInRadius(self.Pivot.Position, Config.TurretRange, self.OverlapParams)

	local closestTarget = nil
	local closestDist = Config.TurretRange

	for _, part in ipairs(partsInRadius) do
		local dist = (self.Pivot.Position - part.Position).Magnitude
		if dist < closestDist then
			closestDist = dist
			closestTarget = part
		end
	end

	self.CurrentTarget = closestTarget
end

function Turret:AimAndFire(dt)
	-- CFrame interpolation for smooth aiming
	if self.CurrentTarget and self.CurrentTarget.Parent then
		local targetPos = self.CurrentTarget.Position
		-- Calculate the CFrame pointing from the pivot to the target
		local targetCFrame = CFrame.lookAt(self.Pivot.Position, targetPos)

		-- Lerp for smooth rotation rather than instant snapping
		self.Pivot.CFrame = self.Pivot.CFrame:Lerp(targetCFrame, dt * 10)
		self.Barrel.CFrame = self.Pivot.CFrame * CFrame.new(0, 0, -2)

		-- Check firing cooldown
		if tick() - self.LastFired >= Config.FireRate then
			self:FireProjectile()
		end
	else
		-- Return to resting position if no target
		local restingCFrame = CFrame.new(self.Pivot.Position) * CFrame.Angles(0, 0, 0)
		self.Pivot.CFrame = self.Pivot.CFrame:Lerp(restingCFrame, dt * 2)
		self.Barrel.CFrame = self.Pivot.CFrame * CFrame.new(0, 0, -2)
	end
end

function Turret:FireProjectile()
	self.LastFired = tick()

	local spawnPos = self.Barrel.CFrame * CFrame.new(0, 0, -2.5)
	local fireDirection = self.Barrel.CFrame.LookVector

	-- Calculate velocity factoring in the config speed
	local velocity = fireDirection * Config.BulletSpeed

	Projectile.new(spawnPos, velocity, 25)
end

function Turret:Update(dt)
	-- Periodically scan to save performance (we don't need to scan every single frame)
	-- Using tick() here as a simple throttle
	if math.round(tick() * 10) % 5 == 0 then 
		self:ScanForTarget()
	end

	self:AimAndFire(dt)
end


-- MAIN ORCHESTRATOR / DEMO SETUP

local function SetupDemoEnvironment()
	-- Create a flat baseplate so physics targets don't fall into the void
	local baseplate = Instance.new("Part")
	baseplate.Size = Vector3.new(200, 1, 200)
	baseplate.Position = Vector3.new(0, -0.5, 0)
	baseplate.Anchored = true
	baseplate.Color = Color3.fromRGB(100, 150, 100)
	baseplate.Material = Enum.Material.Grass
	baseplate.Parent = Workspace

	-- Spawn a couple of turrets
	Turret.new(Vector3.new(20, 0, 20))
	Turret.new(Vector3.new(-20, 0, -20))
	Turret.new(Vector3.new(0, 0, 0))
end

-- Initialize Demo
SetupDemoEnvironment()

local lastTargetSpawn = tick()

-- The single Heartbeat connection that drives the entire system
RunService.Heartbeat:Connect(function(dt)
	-- Manage Target Spawning (Demo purpose)
	if #Target.AllTargets < Config.MaxTargets and (tick() - lastTargetSpawn >= Config.TargetSpawnRate) then
		lastTargetSpawn = tick()
		local randomSpawn = Vector3.new(math.random(-80, 80), 5, math.random(-80, 80))
		Target.new(randomSpawn)
	end

	-- Update all active targets (Physics steering)
	for _, target in ipairs(Target.AllTargets) do
		target:Wander(dt)
	end

	-- Update all turrets (Aiming and Target Acquisition)
	for _, turret in ipairs(Turret.AllTurrets) do
		turret:Update(dt)
	end

	-- Update all projectiles (Kinematics and Raycasting)
	-- Iterate backwards so we can safely remove from the table during iteration if a bullet dies
	for i = #Projectile.ActiveProjectiles, 1, -1 do
		local proj = Projectile.ActiveProjectiles[i]
		proj:Update(dt)
	end
end)
