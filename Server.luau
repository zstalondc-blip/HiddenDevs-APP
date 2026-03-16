local RS = game:GetService("ReplicatedStorage")
local CrackEffect = require(RS:WaitForChild("CrackEffect"))

--EXAMPLE OF USAGE--
--EARTHQUAKE SYSTEM MADE FOR HIDDEN DEVS
--EXAMPLE 1: basic usage, all defaults 
local platform1 = workspace.SpawnPart.Mythical
local crack1 = CrackEffect.new(platform1)
crack1:Start()

--EXAMPLE 2: apply to every part in SpawnPart Folder 
--for _, obj in ipairs(workspace.SpawnPart:GetDescendants()) do
--	if obj:IsA("BasePart") then
--		CrackEffect.new(obj):Start()
--		task.wait(1)
--	end
--end

--EXAMPLE 3: with particle effects from EffectHolder
--for _, obj in ipairs(workspace.SpawnPart:GetDescendants()) do
--	if obj:IsA("BasePart") then
--		local crack = CrackEffect.new(obj, {
--			effectHolder = RS:WaitForChild("EffectHolder"),  -- your particle folder/part
--			numArms      = 12,
--			spread       = 1.0,
--		})
--		crack:Start()
--		task.wait(1)
--	end
--end

--EXAMPLE 4: custom config
--for _, obj in ipairs(workspace.SpawnPart:GetDescendants()) do
--	if obj:IsA("BasePart") then
--		local crack = CrackEffect.new(obj, {
--			numArms       = 8,       -- fewer arms, cleaner look
--			segsPerArm    = 20,      -- more segments = smoother curves
--			wiggle        = 0.9,     -- very bendy
--			segDur        = 0.8,     -- fast crack growth
--			thickness     = 1.0,
--			depth         = 8,
--			holdTime      = 5,
--			repeatMin     = 1,
--			repeatMax     = 3,
--		})
--		crack:Start()
--		task.wait(1)
--	end
--end

--EXAMPLE 5: stop and restart
--for _, obj in ipairs(workspace.SpawnPart:GetDescendants()) do
--	if obj:IsA("BasePart") then
--		local crack = CrackEffect.new(obj)
--		crack:Start()

--		task.delay(30, function()
--			crack:Stop()   -- stops after current cycle finishes
--		end)

--		task.delay(60, function()
--			crack:Start()  -- restart it later
--		end)
--	end
--end




