local TweenSvc = game:GetService("TweenService")
local RS = game:GetService("ReplicatedStorage")

-- module that handles the crack animation on a part's surface
-- to use it: local fx = CrackEffect.new(somePart, config) then fx:Start()
local CrackEffect = {}
CrackEffect.__index = CrackEffect

-- all the default settings, you can override any of these when creating a new effect
local DEFAULTS = {
	numArms       = 15,   -- how many cracks shoot out from the center
	segsPerArm    = 14,   -- how many pieces make up each arm, more = smoother looking
	spread        = 1.15, -- 1.0 stops at the edge, go higher and itll bleed past it
	segDur        = 1.5,  -- how long each piece takes to grow out
	overlap       = 0.25, -- how much pieces overlap in time, 0 feels choppy, 0.8 feels really smooth
	thickness     = 1.5,  -- how wide the crack is in studs
	depth         = 10,   -- how far down the crack goes below the surface
	zOffset       = 0.12, -- tiny lift so the crack doesnt flicker against the surface
	wiggle        = 0.5,  -- how much the crack curves, crank this up for chaos
	holdTime      = 3,    -- how long the crack stays open before it closes
	shrinkDur     = 0.2,  -- how fast each piece disappears when closing
	shrinkStagger = 0.01, -- tiny delay between each piece closing, makes it wave from tip to center
	repeatMin     = 2,    -- shortest wait between each cycle
	repeatMax     = 6,    -- longest wait between each cycle
	startDelayMin = 2,    -- earliest the first crack can appear after starting
	startDelayMax = 10,   -- latest the first crack can appear after starting
	highlightOn   = true, -- whether the model gets a highlight glow when it runs
	fillTrans     = 1,    -- fill transparency, 1 means no fill just the outline
	outlineTrans  = 0.25, -- how visible the outline is
}

-- pass in the part you want to crack and optionally a config table to tweak the settings
function CrackEffect.new(part, config)
	local self = setmetatable({}, CrackEffect)

	self.part    = part   -- the part the cracks will show up on
	self.running = false  -- used to track if the loop is currently going
	self.thread  = nil    -- holds the task thread so we can stop it later

	-- start with all the defaults then overwrite with whatever the user passed in
	self.cfg = {}
	for k, v in pairs(DEFAULTS) do self.cfg[k] = v end
	if config then
		for k, v in pairs(config) do self.cfg[k] = v end
	end

	-- make the crack color slightly darker than the part so it looks natural
	-- the outline goes even darker for a bit more contrast
	local c = part.Color
	self.crackClr   = Color3.new(math.max(0, c.R-.1), math.max(0, c.G-.1), math.max(0, c.B-.1))
	self.outlineClr = Color3.new(math.max(0, c.R-.3), math.max(0, c.G-.3), math.max(0, c.B-.3))

	return self
end

-- figures out where the top surface of the part is and adds the z offset so nothing flickers
function CrackEffect:_getSurfCF()
	local p, cfg = self.part, self.cfg
	return p.CFrame * CFrame.new(0, p.Size.Y/2 + cfg.zOffset, 0)
end

-- runs one full crack cycle, grow out, hold, then shrink back and clean up
function CrackEffect:_runOnce()
	local cfg      = self.cfg
	local part     = self.part
	local surfCF   = self:_getSurfCF()

	-- half sizes of the plate so we can keep cracks from going outside it
	local heightX  = part.Size.X / 2
	local heightZ  = part.Size.Z / 2

	-- everything gets parented here so we can destroy it all at once when done
	local model = Instance.new("Model")
	model.Name = "CrackModel"
	model.Parent = workspace

	-- slap a highlight on the model if the setting is on
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

	-- keeps track of every part we spawn so we can sort and shrink them later
	local spawnedParts = {}

	-- creates one segment of a crack between two points
	-- starts as a super thin sliver then tweens out to full length
	local function spawnSeg(lx1, lz1, lx2, lz2, dur)
		local dlx, dlz = lx2-lx1, lz2-lz1
		local len = math.sqrt(dlx*dlx + dlz*dlz)
		if len < 0.04 then return end  -- too short to bother with, just skip it

		-- work out which way this segment is pointing so we can rotate it correctly
		local yaw = math.atan2(dlx, dlz)

		local midLx, midLz = lx1 + dlx*.5, lz1 + dlz*.5

		-- push it down so the wall goes below the surface
		local dropY = CFrame.new(0, -cfg.depth*.5, 0)
		local rot   = CFrame.Angles(0, yaw, 0)

		-- part starts at the base point and tweens out toward the midpoint
		local fromCF = surfCF * CFrame.new(lx1, 0, lz1) * dropY * rot
		local toCF   = surfCF * CFrame.new(midLx, 0, midLz) * dropY * rot

		-- the actual crack wall part
		local p = Instance.new("Part")
		p.Anchored    = true
		p.CanCollide  = false
		p.CastShadow  = false
		p.Material    = Enum.Material.Plastic
		p.MaterialVariant = "Studs"
		p.Color       = self.crackClr
		p.Size        = Vector3.new(cfg.thickness, cfg.depth, 0.01)  -- basically flat to start
		p.CFrame      = fromCF
		p.Parent      = model

		-- if someone gave us an effect holder, grab any particle emitters from it and stick them on
		-- tint them to match the part color so they dont look out of place
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

		-- grow it from a sliver to full size
		TweenSvc:Create(p, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = toCF,
			Size   = Vector3.new(cfg.thickness, cfg.depth, len)
		}):Play()

		-- store the distance from center so we can shrink from the outside in later
		local dist = math.sqrt(midLx*midLx + midLz*midLz)
		table.insert(spawnedParts, { part = p, originCF = fromCF, dist = dist })
	end

	-- builds one arm as a chain of segments, each one scheduled slightly after the last
	-- also returns the segment data so branches know where to fork off from
	local function buildArm(sx, sz, ang, n, slen, startT)
		local segs  = {}
		local x, z  = sx, sz    -- where the tip currently is
		local angle = ang        -- which direction its heading
		local t     = startT     -- time offset so segments spawn one after another

		for i = 1, n do
			-- next point, clamped so it doesnt go outside the plate
			local nx = math.clamp(x + math.cos(angle)*slen, -heightX*.93, heightX*.93)
			local nz = math.clamp(z + math.sin(angle)*slen, -heightZ*.93, heightZ*.93)

			-- snapshot these so the closure doesnt capture the wrong values
			local cx1, cz1 = x, z
			local cx2, cz2 = nx, nz
			local ft = t

			-- schedule this segment to appear after its delay
			task.delay(ft, function()
				spawnSeg(cx1, cz1, cx2, cz2, cfg.segDur)
			end)

			-- save where this segment ends up and when it finishes growing
			table.insert(segs, { x=nx, z=nz, tip=t+cfg.segDur })

			-- step the timer forward, minus the overlap so the next one starts before this finishes
			t = t + cfg.segDur * (1-cfg.overlap)
			x, z = nx, nz

			-- bend the arm a little each step so it looks organic
			angle = angle + (math.random()-.5) * cfg.wiggle*2
		end

		return segs
	end

	-- need to know when the last segment finishes so we know when to start the hold timer
	local latestT = 0

	for i = 1, cfg.numArms do
		-- spread arms evenly around the circle with a tiny random nudge so it doesnt look too perfect
		local ang = (i/cfg.numArms) * math.pi*2 + (math.random()-.5) * 0.42

		-- figure out how far this arm can go before it hits the edge of the plate
		local ca  = math.abs(math.cos(ang))
		local sa  = math.abs(math.sin(ang))
		local maxReach = (ca < 0.0001) and heightZ or (sa < 0.0001) and heightX or math.min(heightX/ca, heightZ/sa)
		local reach = maxReach * cfg.spread * (0.8 + math.random()*.2)
		local slen  = reach / cfg.segsPerArm

		-- build the main arm
		local main = buildArm(0, 0, ang, cfg.segsPerArm, slen, 0)

		-- pick a random segment along the arm and fork a smaller branch off it
		local bi      = math.random(2, cfg.segsPerArm-1)
		local branch  = main[bi]
		local subAng  = ang + (math.random() > .5 and 0.6 or -0.6)
		buildArm(branch.x, branch.z, subAng, 4, slen*.55, branch.tip)

		local subEnd = branch.tip + cfg.segDur*(1-cfg.overlap)*3 + cfg.segDur
		latestT = math.max(latestT, main[#main].tip, subEnd)
	end

	-- wait for all the cracks to finish growing then hold for a bit
	task.wait(latestT + cfg.holdTime)

	-- sort from furthest to closest so the shrink goes tip to center
	table.sort(spawnedParts, function(a, b) return a.dist > b.dist end)

	for i, entry in ipairs(spawnedParts) do
		task.delay((i-1) * cfg.shrinkStagger, function()
			local p = entry.part
			if not p or not p.Parent then return end

			-- shrink each piece back to a sliver then delete it
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

	-- wait for everything to finish shrinking then nuke the whole model
	task.wait((#spawnedParts-1) * cfg.shrinkStagger + cfg.shrinkDur)
	model:Destroy()
end

function CrackEffect:Start()
	if self.running then return end  -- dont start if its already going
	self.running = true

	self.thread = task.spawn(function()
		math.randomseed(tick())

		-- wait a random amount before the first crack so things dont all pop at once on load
		task.wait(math.random(self.cfg.startDelayMin, self.cfg.startDelayMax))

		while self.running do
			math.randomseed(tick())
			self:_runOnce()
			if not self.running then break end  -- check again after the cycle in case Stop was called during it
			task.wait(math.random(self.cfg.repeatMin, self.cfg.repeatMax))
		end
	end)
end

function CrackEffect:Stop()
	self.running = false  -- this will let the loop exit naturally on its next check
end

return CrackEffect
