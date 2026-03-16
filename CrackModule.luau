

local TweenSvc = game:GetService("TweenService")
local RS = game:GetService("ReplicatedStorage")

local CrackEffect = {}
CrackEffect.__index = CrackEffect

local DEFAULTS = {
	numArms       = 15,  -- how many cracks shoot out from center
	segsPerArm    = 14,  -- pieces per arm, more = smoother path
	spread        = 1.15, -- 1.0 = reaches plate edge, go higher to bleed past it
	segDur        = 1.5,  -- seconds each piece takes to grow
	overlap       = 0.25, -- 0 = choppy, 0.8 = super fluid leading edge
	thickness     = 1.5, -- crack width in studs
	depth         = 10, -- how deep it goes below the surface
	zOffset       = 0.12,  -- tiny lift above the plate so it doesnt flicker
	wiggle        = 0.5, -- how much the cracks curve, higher = more chaotic
	holdTime      = 3, -- seconds it stays fully open before closing
	shrinkDur     = 0.2, -- how fast each piece disappears
	shrinkStagger = 0.01,  -- time between each piece closing, creates the tip-to-center wave
	repeatMin     = 2,  -- min seconds between repeats
	repeatMax     = 6,  -- max seconds between repeats
	startDelayMin = 2,  -- min seconds before first effect
	startDelayMax = 10,  -- max seconds before first effect
	highlightOn   = true,  -- should the part flash when effect runs?
	fillTrans     = 1,  -- transparency of the crack pieces
	outlineTrans  = 0.25,  -- transparency of the crack piece outlines
}
function CrackEffect.new(part, config)
	local self = setmetatable({}, CrackEffect)

	self.part    = part
	self.running = false
	self.thread  = nil

	-- merge config over defaults
	self.cfg = {}
	for k, v in pairs(DEFAULTS) do self.cfg[k] = v end
	if config then
		for k, v in pairs(config) do self.cfg[k] = v end
	end

	-- derive colours from the part once
	local c = part.Color
	self.crackClr   = Color3.new(math.max(0, c.R-.1), math.max(0, c.G-.1), math.max(0, c.B-.1))
	self.outlineClr = Color3.new(math.max(0, c.R-.3), math.max(0, c.G-.3), math.max(0, c.B-.3))

	return self
end

function CrackEffect:_getSurfCF()
	local p, cfg = self.part, self.cfg
	return p.CFrame * CFrame.new(0, p.Size.Y/2 + cfg.zOffset, 0)
end

function CrackEffect:_runOnce()
	local cfg      = self.cfg
	local part     = self.part
	local surfCF   = self:_getSurfCF()
	local heightX  = part.Size.X / 2
	local heightZ  = part.Size.Z / 2

	local model = Instance.new("Model")
	model.Name = "CrackModel"
	model.Parent = workspace

	if cfg.highlightOn then
		local hl = Instance.new("Highlight")
		hl.Adornee             = model
		hl.DepthMode           = Enum.HighlightDepthMode.Occluded
		hl.FillColor           = Color3.new(0, 0, 0)
		hl.OutlineColor        = self.outlineClr
		hl.FillTransparency    = cfg.fillTrans
		hl.OutlineTransparency = cfg.outlineTrans
		hl.Parent              = model
	end

	local spawnedParts = {}

	local function spawnSeg(lx1, lz1, lx2, lz2, dur)
		local dlx, dlz = lx2-lx1, lz2-lz1
		local len = math.sqrt(dlx*dlx + dlz*dlz)
		if len < 0.04 then return end

		local yaw = math.atan2(dlx, dlz)
		local midLx, midLz = lx1 + dlx*.5, lz1 + dlz*.5
		local dropY = CFrame.new(0, -cfg.depth*.5, 0)
		local rot   = CFrame.Angles(0, yaw, 0)

		local fromCF = surfCF * CFrame.new(lx1, 0, lz1) * dropY * rot
		local toCF   = surfCF * CFrame.new(midLx, 0, midLz) * dropY * rot

		local p = Instance.new("Part")
		p.Anchored    = true
		p.CanCollide  = false
		p.CastShadow  = false
		p.Material    = Enum.Material.Plastic
		p.MaterialVariant = "Studs"
		p.Color       = self.crackClr
		p.Size        = Vector3.new(cfg.thickness, cfg.depth, 0.01)
		p.CFrame      = fromCF
		p.Parent      = model

		-- clone any particle emitters from EffectHolder if provided
		if cfg.effectHolder then
			for _, fx in ipairs(cfg.effectHolder:GetDescendants()) do
				if fx:IsA("ParticleEmitter") then
					local clone = fx:Clone()
					clone.Enabled = true
					clone.Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0, part.Color),
						ColorSequenceKeypoint.new(1, part.Color)
					})
					clone.Parent = p
				end
			end
		end

		TweenSvc:Create(p, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = toCF,
			Size   = Vector3.new(cfg.thickness, cfg.depth, len)
		}):Play()

		local dist = math.sqrt(midLx*midLx + midLz*midLz)
		table.insert(spawnedParts, { part = p, originCF = fromCF, dist = dist })
	end

	local function buildArm(sx, sz, ang, n, slen, startT)
		local segs = {}
		local x, z   = sx, sz
		local angle  = ang
		local t      = startT

		for i = 1, n do
			local nx = math.clamp(x + math.cos(angle)*slen, -heightX*.93, heightX*.93)
			local nz = math.clamp(z + math.sin(angle)*slen, -heightZ*.93, heightZ*.93)

			local cx1, cz1 = x, z
			local cx2, cz2 = nx, nz
			local ft = t

			task.delay(ft, function()
				spawnSeg(cx1, cz1, cx2, cz2, cfg.segDur)
			end)

			table.insert(segs, { x=nx, z=nz, tip=t+cfg.segDur })
			t = t + cfg.segDur * (1-cfg.overlap)
			x, z = nx, nz
			angle = angle + (math.random()-.5) * cfg.wiggle*2
		end

		return segs
	end

	local latestT = 0

	for i = 1, cfg.numArms do
		local ang = (i/cfg.numArms) * math.pi*2 + (math.random()-.5) * 0.42
		local ca  = math.abs(math.cos(ang))
		local sa  = math.abs(math.sin(ang))
		local maxReach = (ca < 0.0001) and heightZ or (sa < 0.0001) and heightX or math.min(heightX/ca, heightZ/sa)
		local reach = maxReach * cfg.spread * (0.8 + math.random()*.2)
		local slen  = reach / cfg.segsPerArm

		local main = buildArm(0, 0, ang, cfg.segsPerArm, slen, 0)

		local bi      = math.random(2, cfg.segsPerArm-1)
		local branch  = main[bi]
		local subAng  = ang + (math.random() > .5 and 0.6 or -0.6)
		buildArm(branch.x, branch.z, subAng, 4, slen*.55, branch.tip)

		local subEnd = branch.tip + cfg.segDur*(1-cfg.overlap)*3 + cfg.segDur
		latestT = math.max(latestT, main[#main].tip, subEnd)
	end

	task.wait(latestT + cfg.holdTime)

	table.sort(spawnedParts, function(a, b) return a.dist > b.dist end)

	for i, entry in ipairs(spawnedParts) do
		task.delay((i-1) * cfg.shrinkStagger, function()
			local p = entry.part
			if not p or not p.Parent then return end
			local tw = TweenSvc:Create(p, TweenInfo.new(cfg.shrinkDur, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				CFrame = entry.originCF,
				Size   = Vector3.new(cfg.thickness, cfg.depth, 0.01)
			})
			tw.Completed:Connect(function()
				if p and p.Parent then p:Destroy() end
			end)
			tw:Play()
		end)
	end

	task.wait((#spawnedParts-1) * cfg.shrinkStagger + cfg.shrinkDur)
	model:Destroy()
end

function CrackEffect:Start()
	if self.running then return end
	self.running = true

	self.thread = task.spawn(function()
		math.randomseed(tick())
		task.wait(math.random(self.cfg.startDelayMin, self.cfg.startDelayMax))

		while self.running do
			math.randomseed(tick())
			self:_runOnce()
			if not self.running then break end
			task.wait(math.random(self.cfg.repeatMin, self.cfg.repeatMax))
		end
	end)
end

function CrackEffect:Stop()
	self.running = false
end

return CrackEffect