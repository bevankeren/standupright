-- Blizzard Hub / Stand Upright: Rebooted
-- Version 1.0.8. Public distribution is separate; no Auto Execute.
-- Stand actions are bound from the character's native input source, never guessed.
local VERSION = "1.0.8"
-- Pinned Airflow UI (joustingmatch/-3, fork of PookiePepelsss/Airflow-UI).
local UI_REVISION = "3d74124f1d3fbc653cef118088c006b394b87867"
local UI_URL = "https://raw.githubusercontent.com/joustingmatch/-3/" .. UI_REVISION .. "/Source.luau"
local STORAGE = "BlizzardHub/StandUpright"
local Players = game:GetService("Players")
local Http = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local NetworkClient = game:GetService("NetworkClient")
local TeleportService = game:GetService("TeleportService")
local function networkReady()
    return NetworkClient:FindFirstChildOfClass("ClientReplicator")~=nil
end
local JOB_IDS = {"AutoFarmLevel", "AutoSkill", "AutoFarmMob", "AutoLair", "AutoPickup", "AntiAFK", "AntiVoid", "Noclip", "AutoRejoin", "AutoPlay", "BringMob", "Fly", "SpeedBoost"}
local player = assert(Players.LocalPlayer, "Local player is unavailable.")
local env = getgenv()
local bootReceipt={Version=VERSION,PlaceId=game.PlaceId,JobId=game.JobId,State="Starting"}
env.BlizzardStandUprightBootReceipt=bootReceipt
if game.PlaceId ~= 8540168650 or game.GameId ~= 3258251641 then
    bootReceipt.State="Unsupported place"
    warn("Blizzard Hub: this place is not supported. No automation started.")
    return
end
local previous = env.BlizzardStandUprightControl
if type(previous) == "table" and type(previous.Cleanup) == "function" then previous:Cleanup() end
if not networkReady()then
    bootReceipt.State="Game server disconnected"
    if type(previous)=="table"then previous.DisconnectReason="Game server disconnected"end
    local runtime=env.BlizzardStandUprightRuntimeCache
    if type(runtime)=="table"then runtime.Bindings={} end
    warn("Blizzard Hub: the game server is disconnected. Join a server before running the hub.")
    return
end
local C = {
    Version = VERSION, Ready = false, Closed = false,
    Jobs = {}, JobArmed = {}, Connections = {}, Controls = {}, ToggleElements = {},
    Features = {}, Held = {}, Tabs = {}, JobFactories = {}, Tasks = {},
    Settings = {QuestPosition = "Below NPC", AutoFarmLevel = false, AutoSummon = false, AutoSkill = false, AutoFarmMob = false, AntiVoid = false,
        Screen = "Off", Skills = {}, SkillDelay = 0.6, HideName = false, FarmMob = "", FarmDistance = 5,
        AutoLair = false, LairNpc = "", LairSkills = {}, LairDelay = 0.6, LairDistance=8,
        AutoPickup = false, PickupRadius = 1500, PickupInterval = 0.8,
        AppearancePreset = "Blizzard", AccentHex = "64CDD7", SurfaceHex = "101118",
        UIScale = 110, Snow = true, SnowArea = "UI",
        LairWebhook = false, LevelWebhook = false, WebhookHideName = true, Noclip = false,
        AutoQuestFarm = false, QuestId = "", MerchantNpc = "", MerchantOption = "",
        AutoRejoin = false, RejoinMinutes = 120, AutoPlay=false, AntiAFK=false, BringMob=false, BringDepth=20,
        Fly=false, FlySpeed=45, SpeedBoost=false, WalkSpeed=32},
    Config = {Loaded = nil, Autoload = nil},
    Evidence = {
        AutoSummon = {Stands = {"WhiteSnake","TA4"}, Level = "server SummonPacket", Date = "2026-10-11"},
        AutoSkill = {Stand = "TA4", Skill = "Barrage", Damage = 39.225120544434, ReleasedOnStop = true, Date = "2026-10-11"},
        AutoFarmMob = {Stand = "TA4", Target = "Wooden Dummy", Movement = "TP + under attach",
            UnderDistance = 5, BeforeHP = 100, AfterHP = -43.615997314453,
            MovementRestored = true, Date = "2026-10-11"},
    },
}
env.BlizzardStandUprightControl = C
local cache = env.BlizzardStandUprightRuntimeCache
if type(cache) ~= "table" or cache.GameId ~= game.GameId then cache = {GameId=game.GameId,LairLabels={}} end
cache.LairLabels = type(cache.LairLabels)=="table" and cache.LairLabels or {}
if cache.JobId~=game.JobId then cache.Bindings={};cache.JobId=game.JobId end
cache.Bindings=type(cache.Bindings)=="table"and cache.Bindings or {}
env.BlizzardStandUprightRuntimeCache = cache
C.RuntimeCache = cache
C.LairStats = {Starts=0,Clears=0}
C.LevelFarmStats = {Accepted=0,Completed=0}
C.LairMinimumSeconds=2 -- Minimum current-run age before the boss death action; not a detection guarantee.
C.LairRepeatLevels={[40]=true,[100]=true} -- Server clears observed; actual eligibility still comes from the fresh NPC prompt.
C.PickupStats={Confirmed=0,Attempts=0}
C.PickupCooldowns=setmetatable({}, {__mode="k"})
C.Webhook={Queue={},Seen={},SeenOrder={},Generation=0,Sent=0,Failed=0,Dropped=0,NextAt=0,Status="Off"}
C.WebhookURL="";C.WebhookArmed=false;C.WebhookArmedEvents={};C.WebhookLevelSequence=0
C.CollisionScopes={};C.CollisionLeases=setmetatable({}, {__mode="k"})
C.MerchantCatalogue={}
C.NpcPromptEpoch=0
C.Session={Transition=nil,Status="Off"}
local function connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(C.Connections, connection)
    return connection
end
local function copy(value)
    if type(value) ~= "table" then return value end
    local out = {}; for k, v in pairs(value) do out[k] = copy(v) end; return out
end
local function alive()
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not humanoid or humanoid.Health <= 0 or not root then return nil end
    return character, humanoid, root
end
local function standName()
    local data = player:FindFirstChild("Data")
    local stand = data and data:FindFirstChild("Stand")
    return stand and stand.Value or "None"
end
-- Parse a deliberately small native call grammar. Never execute decompiled source.
-- Unsupported expressions are retained as unavailable actions, not guessed payloads.
function C:ParseNativeInput(source)
    assert(type(source) == "string" and #source <= 200000, "Invalid native input source.")
    source = source:gsub("%-%-%[%[.-%]%]", ""):gsub("%-%-[^\n]*", "")
    local direct = source:match('local%s+([%w_]+)%s*=%s*script%.Parent:WaitForChild%(["\']StandEvents["\']%)')
        or source:match('local%s+([%w_]+)%s*=%s*script%.Parent%.StandEvents')
    local actions, unavailable, positions = {}, {}, {}
    for variable, distance in source:gmatch('local%s+([%w_]+)%s*=%s*[%w_]+:GetMousePosition%(%s*(%d+)%s*,%s*nil%s*,') do
        positions[variable] = tonumber(distance)
    end
    if direct then
        for prefix, name, call in source:gmatch('([%w_]+)%.([%w_]+)%s*:%s*FireServer%s*(%b())') do
            if prefix == direct then
                local args = call:sub(2,-2):match('^%s*(.-)%s*$')
                local action = actions[name] or {RemoteName = name}
                if args == "" then action.Kind = "Empty"
                elseif args == "true" then action.Kind = "Boolean"; action.Begin = {true}
                elseif args == "false" then action.End = {false}
                else
                    local distance = positions[args] or tonumber(args:match('^[%w_]+:GetMousePosition%(%s*(%d+)%s*,%s*nil%s*,%s*[%w_]+%s*%)$'))
                    if distance and distance > 0 and distance <= 1000000 then
                        action.Kind = "Position"; action.Range = distance
                    else unavailable[name] = "Native payload not supported" end
                end
                actions[name] = action
            end
        end
    end
    local shared, remoteName = source:match('local%s+([%w_]+)%s*=%s*script%.Parent:WaitForChild%(["\']StandEvents["\']%)%.([%w_]+)')
    if shared then
        local labels = {Q = "Summon", E = "Barrage", G = "Block", P = "Pose", MouseButton1 = "M1", MouseButton2 = "M2"}
        for alias, call in source:gmatch('([%w_]+)%s*:%s*FireServer%s*(%b())') do
            if alias == shared then
                local mode, enumType, key = call:match('^%(%s*["\']([%w_]+)["\']%s*,%s*Enum%.([%w_]+)%.([%w_]+)%s*%)$')
                if mode and (enumType == "KeyCode" or enumType == "UserInputType") then
                    local label = labels[key] or ("Key_" .. key)
                    local action = actions[label] or {RemoteName = remoteName, Kind = "Shared", EnumType = enumType, Key = key}
                    if mode == "Beg" or mode == "Begin" then action.BeginMode = mode
                    elseif mode == "End" then action.EndMode = mode end
                    actions[label] = action
                end
            end
        end
    end
    for name, action in pairs(actions) do
        if unavailable[name] or not action.Kind or (action.Kind == "Boolean" and not action.End)
            or (action.Kind == "Shared" and not action.BeginMode) then
            unavailable[name] = unavailable[name] or "Native input is incomplete"; actions[name] = nil
        end
    end
    return actions, unavailable
end
function C:RefreshNativeInput(force)
    local character = alive()
    local input = character and character:FindFirstChild("StandInput")
    local events = character and character:FindFirstChild("StandEvents")
    local name = standName()
    local old = self.NativeInput
    if not force and old and old.Character == character and old.Script == input and old.Stand == name and old.Events == events then return old end
    if self.NativeBusy then return nil end
    if not force and os.clock() < (self.NativeRetryAt or 0) then return nil end
    self.NativeRetryAt = os.clock() + 3
    if not input or not events then self.NativeReason = "Waiting for stand input"; return nil end
    if type(decompile) ~= "function" then self.NativeReason = "Native input reader unavailable"; return nil end
    self.NativeBusy = true
    local ok, result = pcall(function()
        local text = decompile(input)
        assert(player.Character == character and standName() == name and input.Parent == character, "Stand changed during refresh.")
        local actions, unavailable = self:ParseNativeInput(text)
        -- Native StandInput inspected via MCP on 2026-10-13: CrazyDiamond and TA4 Q/M1
        -- both call their named StandEvents RemoteEvents with no arguments.
        -- Executor decompile currently returns unsupported bytecode v14; no other
        -- stand or skill is inferred from this narrow, independently read adapter.
        if not next(actions) and (name=="CrazyDiamond"or name=="TA4") then
            actions.Summon={RemoteName="Summon",Kind="Empty",Begin={}}
            actions.M1={RemoteName="M1",Kind="Empty",Begin={}}
        end
        assert(next(actions), "Native input has no verified actions.")
        local values = {}
        for id, action in pairs(actions) do
            local remote = events:FindFirstChild(action.RemoteName)
            if remote and remote:IsA("RemoteEvent") then
                action.Remote = remote
                if action.Kind == "Shared" then
                    local key = Enum[action.EnumType][action.Key]
                    action.Begin = {action.BeginMode, key}
                    action.End = action.EndMode and {action.EndMode, key} or nil
                end
                if id ~= "Summon" then table.insert(values, id) end
            else actions[id] = nil; unavailable[id] = "Native remote unavailable" end
        end
        table.sort(values)
        return {Character = character, Stand = name, Script = input, Events = events, Actions = actions, Values = values, Unavailable = unavailable}
    end)
    self.NativeBusy = false
    if not ok then self.NativeReason = "Could not refresh native input"; self.NativeError = tostring(result); return nil end
    self:ReleaseInputs()
    self.NativeInput = result; self.NativeReason = nil
    if self.RefreshSkillUI then self.RefreshSkillUI(result.Values) end
    return result
end
function C:GetNativeInput()
    local native = self.NativeInput
    local character = alive()
    if native and native.Character == character and native.Stand == standName()
        and native.Script.Parent == character and native.Events.Parent == character then return native end
    return self:RefreshNativeInput(false)
end
function C:StandSummary()
    local function words(value,limit)
        local out={};for word in tostring(value):gmatch("%S+")do if #out>=limit then break end;table.insert(out,word)end
        return table.concat(out," ")
    end
    local data=player:FindFirstChild("Data");local attribute=data and data:FindFirstChild("Attri")
    local boost=player.Character and player.Character:FindFirstChild("DamageBoostM")
    local value=boost and tonumber(boost.Value)
    return words(standName(),3).." / "..words(attribute and attribute.Value or "Unknown",1).." | Damage boost "..(value and string.format("x%.2f",value)or"â€”")
end
function C:UseSkill(id, target, owner)
    if self.Closed or not networkReady()then return false,"Game server disconnected"end
    if owner=="AutoFarmLevel" and self.Movement and self.Movement.PreparingStand and id~="Summon" then
        return false,"Preparing the stand"
    end
    if id=="Summon"then
        local move=self.Movement
        if not move or not self:IsCombatAttached(move.Target,move.Owner)then
            return false,"Waiting for UNDER attachment before summon"
        end
        if self:IsStandSummoned(player.Character)then return false,"Stand summoned"end
    end
    local native = self:GetNativeInput()
    local action = native and native.Actions[id]
    if not action then return false, self.NativeReason or "Selected skill unavailable for this stand" end
    if not action.Remote.Parent then return false, "Waiting for stand input" end
    if self.Held[action] then return false, "Waiting for held skill" end
    -- Native input refresh may yield. Recheck the live attachment immediately
    -- before sending any combat packet, not only before requesting a summon.
    if id=="Summon"or owner=="AutoFarmMob"or owner=="AutoSkill"or owner=="AutoLair"or owner=="BringMob"or owner=="AutoFarmLevel"then
        local move=self.Movement
        local attachedTarget=id=="Summon"and move and move.Target or target
        if not move or not self:IsCombatAttached(attachedTarget,move.Owner)then
            return false,"Waiting for UNDER attachment before stand input"
        end
    end
    self.ActionAt = self.ActionAt or {}
    if self.ActionAt[action] and os.clock()-self.ActionAt[action] < 0.3 then return false, "Waiting for skill interval" end
    self.ActionAt[action] = os.clock()
    if action.Kind == "Position" then
        local _, _, root = alive()
        local targetRoot = target and target:FindFirstChild("HumanoidRootPart")
        if not root or not targetRoot or (root.Position-targetRoot.Position).Magnitude > action.Range then
            return false, "Waiting for target in skill range"
        end
        action.Remote:FireServer(targetRoot.Position)
    else
        local args = action.Begin or {}
        if action.End then
            local held = {Owner = owner, Remote = action.Remote, Args = action.End}
            self.Held[action] = held
            action.Remote:FireServer(unpack(args))
            task.wait(id == "Barrage" and 0.35 or 0.12)
            if self.Held[action] == held then
                self.Held[action] = nil
                if held.Remote.Parent then held.Remote:FireServer(unpack(held.Args)) end
            end
        else action.Remote:FireServer(unpack(args)) end
    end
    return true, "Using " .. id
end
function C:ReleaseInputs(owner)
    for key, held in pairs(self.Held) do
        if not owner or held.Owner == owner then
            if held.Remote.Parent then pcall(function() held.Remote:FireServer(unpack(held.Args)) end) end
            self.Held[key] = nil
        end
    end
end
-- Quest requirements from primary local game Trello, not combat level.
local MOB_QUEST_LEVELS={
 ["Bad Gi"]=1,["Scary Monster"]=10,["Giorno Giovanna"]=20,["Rker Dummy"]=30,
 ["Yoshikage Kira"]=40,["Heaven Ascension Dio Brando"]=50,["DIO Over Heaven"]=50,["Dio Over Heaven"]=50,
 ["Angelo"]=75,["Mikitaka Hazekura"]=100,["Jotaro Part 4"]=125,["Jotaro P4"]=125,
 ["Kakyoin"]=150,["Jungle Bandit"]=175,["Vampire"]=200,["Pillerman"]=275,["Jimbo"]=500,
}
function C:TargetNames()
    local names, seen = {}, {}
    local living = workspace:FindFirstChild("Living")
    if not living then return names end
    for _, h in ipairs(living:QueryDescendants("Model > Humanoid")) do
        local model = h.Parent
        local training=model.Name:lower():find("dummy",1,true)and model.Name~="Rker Dummy"
        if not training and not Players:GetPlayerFromCharacter(model) and model:FindFirstChild("HumanoidRootPart") and not seen[model.Name] then
            seen[model.Name] = true; table.insert(names, model.Name)
        end
    end
    table.sort(names); return names
end
function C:MobChoices()
    local names=self:TargetNames();local labels={};self.MobByLabel={};self.MobLabelByName={}
    table.sort(names,function(a,b)
        local x,y=MOB_QUEST_LEVELS[a]or math.huge,MOB_QUEST_LEVELS[b]or math.huge
        return x==y and a<b or x<y
    end)
    for _,name in ipairs(names)do
        local level=MOB_QUEST_LEVELS[name]
        local label=name..(level and(" (Quest Lv "..level..")")or" (Quest level unverified)")
        self.MobByLabel[label]=name;self.MobLabelByName[name]=label;table.insert(labels,label)
    end
    return labels
end
function C:FindTarget(name, limit)
    local _, _, root = alive()
    local living = workspace:FindFirstChild("Living")
    if not root or not living then return nil end
    local target, distance = nil, limit or math.huge
    for _, h in ipairs(living:QueryDescendants("Model > Humanoid")) do
        local model = h.Parent; local r = model:FindFirstChild("HumanoidRootPart")
        if r and h.Health > 0 and not Players:GetPlayerFromCharacter(model) and (not name or model.Name == name) then
            local d = (root.Position-r.Position).Magnitude
            if d < distance then target, distance = model, d end
        end
    end
    return target, distance
end
-- Character collision is leased by owners; manual Noclip and combat may overlap.
function C:AcquireCollisions(owner,character)
    assert(type(owner)=="string" and character==player.Character,"Collision scope must be the current character.")
    local existing=self.CollisionScopes[owner]
    if existing and existing.Character==character then return end
    self:ReleaseCollisions(owner)
    local scope={Character=character,Parts=setmetatable({}, {__mode="k"})}
    self.CollisionScopes[owner]=scope
    local function acquire(part)
        if self.Closed or self.CollisionScopes[owner]~=scope or not part:IsA("BasePart")then return end
        local lease=self.CollisionLeases[part]
        if not lease then lease={Original=part.CanCollide,Owners={}};self.CollisionLeases[part]=lease end
        lease.Owners[owner]=true;scope.Parts[part]=true;part.CanCollide=false
    end
    for _,part in ipairs(character:QueryDescendants("BasePart"))do acquire(part)end
    scope.Added=character.DescendantAdded:Connect(acquire)
    scope.Removing=character.DescendantRemoving:Connect(function(part)
        if scope.Parts[part]then self:ReleaseCollisionPart(owner,scope,part)end
    end)
end
function C:ReleaseCollisionPart(owner,scope,part)
    scope.Parts[part]=nil
    local lease=self.CollisionLeases[part]
    if not lease then return end
    lease.Owners[owner]=nil
    if not next(lease.Owners)then
        self.CollisionLeases[part]=nil
        if part.Parent and part.CanCollide==false then part.CanCollide=lease.Original end
    end
end
function C:ReleaseCollisions(owner)
    if not owner then
        local owners={};for id in pairs(self.CollisionScopes)do table.insert(owners,id)end
        for _,id in ipairs(owners)do self:ReleaseCollisions(id)end
        return
    end
    local scope=self.CollisionScopes[owner]
    if not scope then return end
    self.CollisionScopes[owner]=nil
    if scope.Added then scope.Added:Disconnect()end
    if scope.Removing then scope.Removing:Disconnect()end
    for part in pairs(scope.Parts)do self:ReleaseCollisionPart(owner,scope,part)end
end
function C:MaintainCollisions()
    if self.Closed then return end
    if self.BringRadius then
        if self.Settings.AutoFarmLevel then self:AcquireBringRadius()else self:ReleaseBringRadius()end
    end
    local stale={}
    for owner,scope in pairs(self.CollisionScopes)do
        local humanoid=scope.Character:FindFirstChildOfClass("Humanoid")
        if scope.Character~=player.Character or not scope.Character.Parent or not humanoid or humanoid.Health<=0 then
            table.insert(stale,owner)
        end
    end
    for _,owner in ipairs(stale)do self:ReleaseCollisions(owner)end
    for part in pairs(self.CollisionLeases)do if part.Parent then
        local stance=self.BringState and self.BringState.StancePart==part and not self.Settings.Noclip
        part.CanCollide=stance==true
    end end
end
function C:ReleaseMovement(owner)
    local move = self.Movement
    if owner=="AutoFarmLevel" or (not owner and move and move.Owner=="AutoFarmLevel")then self:ReleaseBringRadius()end
    if not move or (owner and move.Owner ~= owner) then return end
    self.Movement = nil
    -- Only NPC interaction sets this hook; baseline farm movement stays unchanged.
    if move.QuestPoseCleanup then move.QuestPoseCleanup();move.QuestPoseCleanup=nil end
    self:ReleaseBring(move.Owner)
    if move.FlightInstances then for _,instance in ipairs(move.FlightInstances)do instance:Destroy()end end
    if move.AttachConnection then move.AttachConnection:Disconnect() end
    if move.FloatConnection then move.FloatConnection:Disconnect() end
    self:ReleaseCollisions(move.Owner)
    if move.Humanoid.Parent then
        if move.AppliedAutoRotate ~= nil and move.Humanoid.AutoRotate == move.AppliedAutoRotate then
            move.Humanoid.AutoRotate = move.AutoRotate
        end
        move.Humanoid:Move(Vector3.zero)
        if move.Root.Parent then
            if move.ReturnCFrame and move.LastApplied and (move.Root.Position-move.LastApplied.Position).Magnitude < 8
                and player.Character == move.Character then move.Root.CFrame = move.ReturnCFrame end
            move.Humanoid:MoveTo(move.Root.Position)
            move.Root.AssemblyLinearVelocity = Vector3.zero
            move.Root.AssemblyAngularVelocity = Vector3.zero
        end
    end
end
function C:ClaimMovement(owner)
    local character, humanoid, root = alive()
    if not character then return nil end
    if self.Movement and (self.Movement.Owner ~= owner or self.Movement.Character ~= character) then return nil end
    if not self.Movement then
        self.Movement = {Owner = owner, Character = character, Humanoid = humanoid, Root = root, AutoRotate = humanoid.AutoRotate}
    end
    return self.Movement
end
function C:UnderCFrame(targetCFrame, distance, maximum)
    local position = targetCFrame.Position - Vector3.new(0,math.clamp(distance,3,maximum or 6),0)
    local up = Vector3.new(targetCFrame.LookVector.X,0,targetCFrame.LookVector.Z)
    if up.Magnitude < 0.01 then up = Vector3.new(0,0,1) end
    return CFrame.lookAt(position,targetCFrame.Position,up.Unit)
end
function C:AttachUnderTarget(target, job, owner, skipBring)
    owner = owner or "AutoFarmMob"
    if owner=="AutoLair"then return self:FloatUnderLair(job,nil,target)end
    if (self.Settings.BringMob or owner=="AutoFarmLevel") and not skipBring then return self:BringTarget(target,job,owner)end
    local move = self:ClaimMovement(owner)
    if not move then return false, "Waiting for movement" end
    local targetRoot = target:FindFirstChild("HumanoidRootPart")
    local targetHumanoid = target:FindFirstChildOfClass("Humanoid")
    if not targetRoot or not targetHumanoid or targetHumanoid.Health<=0 or Players:GetPlayerFromCharacter(target) then
        self:ReleaseMovement(owner); return false,"Waiting for target"
    end
    move.Target = target; move.TargetRoot = targetRoot; move.TargetHumanoid=targetHumanoid
    if not move.ReturnCFrame then move.ReturnCFrame = move.Root.CFrame end
    self:AcquireCollisions(owner,move.Character)
    local function follow()
        if owner=="AutoFarmLevel"and not self.Closed and not job.Cancelled and self.Settings[owner]
            and self.Movement==move and player.Character==move.Character and move.Humanoid.Health>0
            and(not move.Target.Parent or not move.TargetRoot.Parent or move.TargetHumanoid.Health<=0)then
            self:WaitLevelUnderground(job);return
        end
        if self.Closed or job.Cancelled or not self.Settings[owner] or self.Movement~=move
            or player.Character~=move.Character or move.Humanoid.Health<=0 or not move.Target.Parent
            or not move.TargetRoot.Parent or not move.TargetHumanoid.Parent or move.TargetHumanoid.Health<=0 then
            self:ReleaseMovement(owner);return
        end
        local cf=self:UnderCFrame(move.TargetRoot.CFrame,self.Settings.FarmDistance)
        if cf.Position.Y<=workspace.FallenPartsDestroyHeight+12 then
            job.Reason="Waiting: target is near the void";self:ReleaseMovement(owner);return
        end
        move.Humanoid.AutoRotate=false;move.AppliedAutoRotate=false
        self:MaintainCollisions()
        move.Root.CFrame=cf
        move.Root.AssemblyLinearVelocity=Vector3.zero;move.Root.AssemblyAngularVelocity=Vector3.zero
        move.LastApplied=cf
    end
    if not move.AttachConnection then move.AttachConnection=RunService.Heartbeat:Connect(follow) end
    follow()
    if self.Movement~=move then return false,job.Reason or "Waiting for target" end
    return true,"Attached below target"
end
function C:HasNPCControl(root,playerRoot)
    if not root or not playerRoot then return false,false end
    local apiSupported=false
    if type(isnetworkowner)=="function" then
        local ok,owned=pcall(isnetworkowner,root)
        if ok and type(owned)=="boolean" then
            apiSupported=true
            if owned then return not root.Anchored,true end
        end
    end
    if type(gethiddenproperty)=="function" then
        local a,own=pcall(gethiddenproperty,playerRoot,"NetworkOwnerV3")
        local b,peer=pcall(gethiddenproperty,root,"NetworkOwnerV3")
        if a and b and type(own)=="number"and type(peer)=="number" then
            return not root.Anchored and own>1 and peer==own,true
        end
    end
    return false,apiSupported -- A mobile API returning false must not hide a valid peer-ID check.
end
function C:AcquireBringRadius()
    if not self.Settings.AutoFarmLevel or self.Closed or type(gethiddenproperty)~="function"or type(sethiddenproperty)~="function" then return end
    local ok,current=pcall(gethiddenproperty,player,"SimulationRadius")
    local valid,maximum=pcall(gethiddenproperty,player,"MaximumSimulationRadius")
    if not ok or not valid or type(current)~="number"or type(maximum)~="number" then return end
    local lease=self.BringRadius
    if not lease then lease={Original=current,Applied=math.min(math.max(current,64),maximum),NextAt=0};self.BringRadius=lease end
    if os.clock()>=lease.NextAt then
        lease.NextAt=os.clock()+.2
        if current<lease.Applied then pcall(sethiddenproperty,player,"SimulationRadius",lease.Applied)end
    end
end
function C:ReleaseBringRadius()
    local lease=self.BringRadius;self.BringRadius=nil
    if not lease then return end
    local ok,current=pcall(gethiddenproperty,player,"SimulationRadius")
    if ok and current==lease.Applied then pcall(sethiddenproperty,player,"SimulationRadius",lease.Original)end
end
function C:ReleaseBring(owner)
    local state=self.BringState
    if not state or(owner and state.Owner~=owner)then return end
    self.BringState=nil
    if state.Platform then state.Platform:Destroy()end
    local stance=state.StancePart;local lease=stance and self.CollisionLeases[stance]
    if stance and stance.Parent and lease and stance.CanCollide==true then stance.CanCollide=lease.Original end
    for _,item in pairs(state.Items)do
        if item.Root.Parent and item.Humanoid.Parent then
            if item.Humanoid.AutoRotate==false then item.Humanoid.AutoRotate=item.AutoRotate end
            if item.Humanoid.Health>0 and item.LastApplied and self:HasNPCControl(item.Root,state.PlayerRoot)
                and(item.Root.Position-item.LastApplied.Position).Magnitude<8 then
                item.Root.CFrame=item.Original;item.Root.AssemblyLinearVelocity=Vector3.zero
                item.Root.AssemblyAngularVelocity=Vector3.zero
            end
        end
    end
end
function C:BringTarget(target,job,owner)
    if not self.Settings.BringMob and owner~="AutoFarmLevel" then return false,"Bring mob is off"end
    local character,_,root=alive();local tr=target and target:FindFirstChild("HumanoidRootPart")
    local th=target and target:FindFirstChildOfClass("Humanoid")
    if not character or not tr or not th or th.Health<=0 or Players:GetPlayerFromCharacter(target)then return false,"Waiting for NPC"end
    local state=self.BringState
    if not state or state.Owner~=owner then
        local controlled,supported=self:HasNPCControl(tr,root)
        if owner=="AutoFarmLevel" and not controlled then
            self:ReleaseInputs(owner)
            local move=self:ClaimMovement(owner);if not move then return false,"Waiting for movement"end
            if move.PendingBringTarget~=target then
                local origin=tr.Position-Vector3.new(0,self.Settings.BringDepth,0)
                if origin.Y<=workspace.FallenPartsDestroyHeight+30 then return false,"Bring position is too close to the void"end
                local look=Vector3.new(tr.CFrame.LookVector.X,0,tr.CFrame.LookVector.Z)
                if look.Magnitude<.01 then look=Vector3.new(0,0,-1)end
                move.PendingBringTarget=target;move.PendingBringPose=CFrame.lookAt(origin,origin+look.Unit)
            end
            if not move.ReturnCFrame then move.ReturnCFrame=root.CFrame end
            self:AcquireCollisions(owner,character)
            move.LastApplied=move.PendingBringPose;self:WaitLevelUnderground(job)
            job.WaitingForBring=true
            return false,supported and "Waiting underground for the mob"or "Bring is unavailable in this executor. Farming is paused."
        end
        if owner=="AutoFarmLevel" then self:ResumeLevelMovement()end
        local attached,reason=self:AttachUnderTarget(target,job,owner,true)
        if not attached then return false,reason end
        if not self:HasNPCControl(tr,root)then
            job.BringWaitAt=job.BringWaitAt or os.clock()
            if os.clock()-job.BringWaitAt>8 then return false,"NPC is server-controlled; bring unavailable"end
            return false,"Attached below: waiting for NPC control"
        end
        job.BringWaitAt=nil
        local look=Vector3.new(root.CFrame.LookVector.X,0,root.CFrame.LookVector.Z)
        if look.Magnitude<0.01 then look=Vector3.new(0,0,-1)end
        local origin=tr.Position-Vector3.new(0,self.Settings.BringDepth,0)
        if origin.Y<=workspace.FallenPartsDestroyHeight+30 then return false,"Bring position is too close to the void"end
        local platform=Instance.new("Part");platform.Name="BlizzardStandUprightBringFloor"
        platform.Size=Vector3.new(24,1,20);platform.Anchored=true;platform.Transparency=1
        platform.CanCollide=true;platform.CanTouch=false;platform.CanQuery=true
        platform.CFrame=CFrame.new(origin-Vector3.new(0,root.Size.Y/2+character.Humanoid.HipHeight+.5,0));platform.Parent=workspace
        state={Owner=owner,PlayerRoot=root,Anchor=CFrame.lookAt(origin,origin+look.Unit),Items={},NextScan=0,
            Platform=platform,StancePart=character:FindFirstChild("Torso")or character:FindFirstChild("LowerTorso")}
        self.BringState=state
        local move=self.Movement
        if move.AttachConnection then move.AttachConnection:Disconnect();move.AttachConnection=nil end
    end
    local move=self:ClaimMovement(owner)
    if not move then return false,"Waiting for movement"end
    local function enroll(model)
        if state.Items[model]then return end
        local r=model:FindFirstChild("HumanoidRootPart");local h=model:FindFirstChildOfClass("Humanoid")
        if not r or not h or h.Health<=0 or Players:GetPlayerFromCharacter(model)or not self:HasNPCControl(r,root)then return end
        local count=0;local used={}
        for model,item in pairs(state.Items)do
            if not item.Root.Parent or item.Humanoid.Health<=0 then
                if item.Humanoid.Parent and item.Humanoid.AutoRotate==false then item.Humanoid.AutoRotate=item.AutoRotate end
                state.Items[model]=nil
            else count+=1;used[item.Slot]=true end
        end
        if count>=6 then return end
        local slot=0;while used[slot]do slot+=1 end
        state.Items[model]={Root=r,Humanoid=h,Original=r.CFrame,AutoRotate=h.AutoRotate,Slot=slot}
    end
    enroll(target)
    if os.clock()>=state.NextScan then
        state.NextScan=os.clock()+1
        local living=workspace:FindFirstChild("Living")
        if living then for _,h in ipairs(living:QueryDescendants("Model > Humanoid"))do
            local m=h.Parent;local r=m:FindFirstChild("HumanoidRootPart")
            if m.Name==target.Name and r and(r.Position-root.Position).Magnitude<=150 then enroll(m)end
        end end
    end
    move.Target=target;move.Behind=true
    self:AcquireCollisions(owner,character)
    local function follow()
        if self.Closed or job.Cancelled or not self.Settings[owner]or (not self.Settings.BringMob and owner~="AutoFarmLevel")
            or not networkReady()or self.Movement~=move or self.BringState~=state or player.Character~=character then
            self:ReleaseMovement(owner);return
        end
        local primary=state.Items[move.Target]
        if not primary or not primary.Root.Parent or primary.Humanoid.Health<=0 then
            if owner=="AutoFarmLevel"then self:WaitLevelUnderground(job)end
            return
        end
        local count=0
        for _,item in pairs(state.Items)do
            if item.Root.Parent and item.Humanoid.Health>0 and self:HasNPCControl(item.Root,root)then
                local slot=item.Slot;local cf=state.Anchor*CFrame.new((slot%3-1)*5,0,-math.floor(slot/3)*5)
                item.Humanoid.AutoRotate=false;item.Root.CFrame=cf
                item.Root.AssemblyLinearVelocity=Vector3.zero;item.Root.AssemblyAngularVelocity=Vector3.zero
                item.LastApplied=cf;count+=1
            end
        end
        -- Keep the player at the underground anchor even if the server corrects the mob upward.
        -- Never derive player Y from the mob's replicated/rollback position.
        local slot=primary.Slot
        local held=state.Anchor*CFrame.new((slot%3-1)*5,0,-math.floor(slot/3)*5)
        local controlled=self:HasNPCControl(primary.Root,root)
        local distance=controlled and (move.BehindDistance or 4) or 12
        local position=held.Position-held.LookVector*distance
        local cf=CFrame.lookAt(position,held.Position)
        move.Humanoid.AutoRotate=false;move.AppliedAutoRotate=false;self:MaintainCollisions()
        root.CFrame=cf;root.AssemblyLinearVelocity=Vector3.zero;root.AssemblyAngularVelocity=Vector3.zero
        if state.Platform then state.Platform.CFrame=CFrame.new(position-Vector3.new(0,root.Size.Y/2+move.Humanoid.HipHeight+.5,0))end
        local humanoidState=move.Humanoid:GetState()
        if not self.Settings.Noclip and not move.Humanoid.PlatformStand and not move.Humanoid.Sit
            and (humanoidState==Enum.HumanoidStateType.Freefall or humanoidState==Enum.HumanoidStateType.GettingUp) then
            move.Humanoid:ChangeState(Enum.HumanoidStateType.Running)
        end
        move.LastApplied=cf;state.Count=count
        if not controlled then
            job.WaitingForBring=true
            job.Reason="Waiting underground for the mob";self:ReleaseInputs(owner);return
        end
        if job.WaitingForBring then job.QuestProgressAt=os.clock()end
        job.WaitingForBring=nil
    end
    if not move.AttachConnection then move.AttachConnection=RunService.Heartbeat:Connect(follow)end
    follow()
    if job.WaitingForBring then return false,job.Reason or "Waiting underground for the mob"end
    if not self:IsCombatAttached(target,owner)then return false,"Waiting for behind attachment"end
    return true,"Behind attachment | "..tostring(state.Count or 0).." mobs held"
end
function C:ReleaseSpeed()
    local state=self.SpeedState;self.SpeedState=nil
    if state and state.Humanoid.Parent and state.Humanoid.WalkSpeed==state.Applied then state.Humanoid.WalkSpeed=state.Original end
end
function C:FlyStep(job)
    local move=self:ClaimMovement("Fly")
    if not move then return false,"Waiting: combat owns movement"end
    if not move.FlightInstances then
        local attachment=Instance.new("Attachment");attachment.Name="BlizzardStandUprightFlight";attachment.Parent=move.Root
        local velocity=Instance.new("LinearVelocity");velocity.Attachment0=attachment;velocity.RelativeTo=Enum.ActuatorRelativeTo.World
        velocity.MaxForce=math.huge;velocity.VectorVelocity=Vector3.zero;velocity.Parent=move.Root
        local orientation=Instance.new("AlignOrientation");orientation.Mode=Enum.OrientationAlignmentMode.OneAttachment
        orientation.Attachment0=attachment;orientation.MaxTorque=math.huge;orientation.Responsiveness=30;orientation.Parent=move.Root
        move.FlightInstances={velocity,orientation,attachment};move.FlightVelocity=velocity;move.FlightOrientation=orientation
        move.AttachConnection=RunService.Heartbeat:Connect(function()
            if self.Closed or job.Cancelled or not self.Settings.Fly or not networkReady()or self.Movement~=move
                or player.Character~=move.Character or move.Humanoid.Health<=0 then self:ReleaseMovement("Fly");return end
            local camera=workspace.CurrentCamera;local direction=Vector3.zero
            if camera and not UserInputService:GetFocusedTextBox()then
                direction=move.Humanoid.MoveDirection
                direction+=Vector3.yAxis*(self.FlyVertical or 0)
                local function down(key)return UserInputService:IsKeyDown(key)end
                if down(Enum.KeyCode.W)or down(Enum.KeyCode.S)or down(Enum.KeyCode.A)or down(Enum.KeyCode.D)then
                    direction=Vector3.zero
                    if down(Enum.KeyCode.W)then direction+=camera.CFrame.LookVector end
                    if down(Enum.KeyCode.S)then direction-=camera.CFrame.LookVector end
                    if down(Enum.KeyCode.D)then direction+=camera.CFrame.RightVector end
                    if down(Enum.KeyCode.A)then direction-=camera.CFrame.RightVector end
                end
                if down(Enum.KeyCode.Space)or down(Enum.KeyCode.E)then direction+=Vector3.yAxis end
                if down(Enum.KeyCode.LeftControl)or down(Enum.KeyCode.Q)then direction-=Vector3.yAxis end
                move.FlightOrientation.CFrame=CFrame.lookAt(Vector3.zero,camera.CFrame.LookVector)
            end
            if direction.Magnitude>1 then direction=direction.Unit end
            move.Humanoid.AutoRotate=false;move.AppliedAutoRotate=false
            move.FlightVelocity.VectorVelocity=direction*self.Settings.FlySpeed
        end)
    end
    return true,"Flying | WASD, Space/E up, Ctrl/Q down"
end
function C:IsCombatAttached(target,owner)
    local move=self.Movement
    local job=move and self.Jobs[move.Owner]
    local character,humanoid,root=alive()
    local tr=target and target:FindFirstChild("HumanoidRootPart")
    local th=target and target:FindFirstChildOfClass("Humanoid")
    if self.Closed or not networkReady()or not move or move.Owner~=owner or move.Target~=target
        or move.Character~=character or move.Root~=root or not move.LastApplied
        or not job or job.Cancelled or not self.Settings[owner]
        or not tr or not th or th.Health<=0 or Players:GetPlayerFromCharacter(target)then return false end
    local delta=root.Position-tr.Position
    if owner=="AutoFarmLevel" and move.PreparingStand then
        return delta.Y<=-10 and delta.Y>=-64 and Vector2.new(delta.X,delta.Z).Magnitude<=2
    end
    if move.Behind and (self.Settings.BringMob or owner=="AutoFarmLevel") and self.BringState and self.BringState.Items[target]then
        if not self:HasNPCControl(tr,root)then return false end
        local localPos=tr.CFrame:PointToObjectSpace(root.Position)
        return math.abs(localPos.X)<=2 and math.abs(localPos.Y)<=2 and localPos.Z>=3 and localPos.Z<=6
    end
    if owner=="AutoLair"then
        return delta.Y<=-6 and delta.Y>=-(self.Settings.LairDistance+1.5)and Vector2.new(delta.X,delta.Z).Magnitude<=2
    end
    return delta.Y<=-3 and delta.Y>=-6.5 and Vector2.new(delta.X,delta.Z).Magnitude<=2
end
function C:EnsureCombatStand(target,owner)
    if not self:IsCombatAttached(target,owner)then return false,"Waiting for UNDER attachment before summon"end
    if self:IsStandSummoned(player.Character)then
        self.CombatSummon=nil;return true,"Stand summoned"
    end
    local native=self:GetNativeInput()
    if not native or not native.Actions.Summon then return false,self.NativeReason or "Summon input unavailable"end
    local state=self.CombatSummon
    if not state or state.Character~=player.Character then
        state={Character=player.Character,Owner=owner,Attempts=0,NextAt=0};self.CombatSummon=state
    end
    if os.clock()<state.NextAt then return false,"Attached below: waiting for summon"end
    if state.Attempts>=3 then
        state.Batches=(state.Batches or 0)+1
        if state.Batches>=3 then
            local job=self.Jobs[owner];if job then job.Cancelled=true end
            return false,"Stand could not summon. Turn farming off and on to retry."
        end
        state.Attempts=0;state.NextAt=os.clock()+8
        return false,"Waiting for the stand to recover"
    end
    local fired,reason=self:UseSkill("Summon",target,owner)
    if fired then state.Attempts+=1;state.NextAt=os.clock()+3 end
    return false,fired and "Attached below: summoning stand"or reason
end
function C:ObserveFarmDamage(job)
    local target=job and job.Target
    local humanoid=target and target:FindFirstChildOfClass("Humanoid")
    if not humanoid or not job.Health then return end
    local hp=math.max(0,humanoid.Health)
    if hp<job.Health then
        job.ConfirmedDamage=(job.ConfirmedDamage or 0)+(job.Health-hp)
        job.DamageUpdates=(job.DamageUpdates or 0)+1
        job.ProgressAt=os.clock();job.Stalls=0;job.RangeAdjusted=nil
    end
    job.Health=hp
end
function C:FarmTargetStep(target,job,owner)
    if owner=="AutoFarmLevel"then self:ResumeLevelMovement()end
    local humanoid=target:FindFirstChildOfClass("Humanoid")
    self:ObserveFarmDamage(job)
    if job.Target~=target then
        job.Target=target;job.Health=humanoid.Health;job.ProgressAt=os.clock();job.Stalls=0;job.RetryAt=nil;job.RangeAdjusted=nil;job.AttackAt=nil
        job.WaitingForBring=nil
    end
    job.Health=math.max(0,humanoid.Health)
    if job.RetryAt and os.clock()<job.RetryAt then return false,"Waiting before retry" end
    if owner=="AutoFarmLevel" then
        self:AcquireBringRadius()
        if not self:IsStandSummoned(player.Character) then
            local move=self:ClaimMovement(owner);if not move then return false,"Waiting for movement"end
            local tr=target:FindFirstChild("HumanoidRootPart")
            if not tr then return false,"Waiting for the mob"end
            if self.BringState then self:ReleaseBring(owner)end
            local origin=tr.Position-Vector3.new(0,math.max(10,self.Settings.BringDepth),0)
            if origin.Y<=workspace.FallenPartsDestroyHeight+30 then return false,"Bring position is too close to the void"end
            if not move.ReturnCFrame then move.ReturnCFrame=move.Root.CFrame end
            move.LastApplied=CFrame.new(origin);self:AcquireCollisions(owner,move.Character)
            self:WaitLevelUnderground(job);move.Target=target;move.PreparingStand=true
            job.WaitingForBring=true
            local ready,reason=self:EnsureCombatStand(target,owner)
            return false,ready and "Stand ready; gathering mobs"or reason
        end
        if self.Movement then self.Movement.PreparingStand=nil end
    end
    local inRange,reason=self:AttachUnderTarget(target,job,owner)
    if not inRange then job.ProgressAt=os.clock();return false,reason end
    local summoned,summonReason=self:EnsureCombatStand(target,owner)
    if not summoned then job.ProgressAt=os.clock();return false,summonReason end
    if job.AttackAt and os.clock()-job.ProgressAt>3 and self.Movement and self.Movement.Behind and not job.RangeAdjusted then
        self.Movement.BehindDistance=3;job.RangeAdjusted=true;self:ReleaseInputs(owner)
        return false,"No confirmed damage: moving closer behind"
    end
    local invinc=target:FindFirstChild("Invinc")
    local beatdown=target:FindFirstChild("InBeatdown")
    if (invinc and invinc:IsA("BoolValue") and invinc.Value)
        or (beatdown and beatdown:IsA("BoolValue") and beatdown.Value) then
        self:ReleaseInputs(owner);job.ProgressAt=os.clock()
        return false,"Waiting: target is invulnerable"
    end
    if os.clock()-job.ProgressAt>12 then
        self:ReleaseMovement(owner);self:ReleaseInputs(owner)
        job.Stalls=(job.Stalls or 0)+1;job.RetryAt=os.clock()+5*2^(job.Stalls-1);job.ProgressAt=os.clock()
        if job.Stalls>=3 then job.Cancelled=true;return false,"Stopped: target health did not change" end
        return false,"Target did not respond; waiting"
    end
    local fired,message=self:UseSkill("M1",target,owner)
    if fired then job.AttackAt=os.clock()end
    return fired,fired and ("Attacking "..target.Name..string.format(" | Damage %.1f",job.ConfirmedDamage or 0)) or message
end
local function inLair()
    local character = player.Character
    local value = character and character:FindFirstChild("InLair")
    return value and value:IsA("BoolValue") and value.Value or false
end
function C:IsStandSummoned(character)
    local stand = character and character:FindFirstChild("Stand")
    if not stand then return false end
    for _, part in ipairs(stand:QueryDescendants("BasePart")) do
        if part.Name ~= "HumanoidRootPart" and part.Transparency < 0.8 then return true end
    end
    return false
end
-- NPC names are observed map identities. Kill targets come only from server quests.
local LEVEL_QUEST_NPCS={{1,"Giorno"},{10,"Scared Noob"},{20,"Koichi"},
    {40,"Okayasu"},{50,"Joseph Joestar"},{75,"Josuke"},{100,"Rohan"},
    {125,"DIO"},{150,"Muhammed Avdol"},{175,"Giorno2"},{200,"Zeppeli"},{275,"Young Joseph"}}
function C:LevelQuestNPC()
    local d=player:FindFirstChild("Data");local level=d and d:FindFirstChild("Level")
    local n=level and tonumber(level.Value);if not n then return nil end
    local name
    for _,row in ipairs(LEVEL_QUEST_NPCS)do if n>=row[1]then name=row[2]end end
    local map=workspace:FindFirstChild("Map");local f=map and map:FindFirstChild("NPCs")
    return f and f:FindFirstChild(name),n
end
function C:ReadLevelQuest(q)
    if not q or not q.Parent then return nil end
    local function value(name,class)
        local v=q:FindFirstChild(name);if v and v:IsA(class)then return v.Value end
    end
    local enemy=value("Enemy","StringValue");local kind=value("Type","StringValue")
    local kills=value("Kills","NumberValue");local maximum=value("MaxKills","NumberValue")
    local completed=value("Completed","BoolValue")
    if kind~="Kill"or type(enemy)~="string"or enemy==""or not kills or not maximum
        or maximum<1 or kills<0 or completed==nil then return nil end
    return {Instance=q,Enemy=enemy,Kills=kills,Maximum=maximum,Completed=completed or kills>=maximum}
end
function C:EnsureLevelQuestNPC(job,npc)
    if npc:FindFirstChild("HumanoidRootPart") and npc:FindFirstChildOfClass("ProximityPrompt") then
        job.QuestNPCWaitAt=nil;job.QuestNPCStreamAttempts=nil;return true
    end
    if job.QuestNPCStreamNpc~=npc then
        job.QuestNPCStreamNpc=npc;job.QuestNPCWaitAt=os.clock();job.QuestNPCStreamAttempts=0
    end
    job.QuestNPCWaitAt=job.QuestNPCWaitAt or os.clock()
    if os.clock()-job.QuestNPCWaitAt>15 then
        job.Cancelled=true;return false,"Quest giver did not load. Turn Auto farm level off and on to retry."
    end
    if workspace.StreamingEnabled and not job.QuestNPCStreamThread and (job.QuestNPCStreamAttempts or 0)<2
        and (not job.QuestNPCStreamAt or os.clock()-job.QuestNPCStreamAt>=3) then
        -- WorldPivot remains available when the server has not streamed the NPC's body.
        local ok,pivot=pcall(npc.GetPivot,npc)
        if ok and pivot.Position.Magnitude>1 then
            job.QuestNPCStreamAt=os.clock();job.QuestNPCStreamAttempts=(job.QuestNPCStreamAttempts or 0)+1
            job.QuestNPCStreamThread=task.defer(function()
                local loaded,err=pcall(function()player:RequestStreamAroundAsync(pivot.Position,3)end)
                if not self.Closed and not job.Cancelled then
                    job.QuestNPCStreamOK=loaded;job.QuestNPCStreamError=not loaded and tostring(err)or nil
                end
                job.QuestNPCStreamThread=nil
            end)
        end
    end
    return false,"Loading quest giver"
end
function C:LevelStandOff(job)
    local character=player.Character
    if not self:IsStandSummoned(character)then job.UnsummonAttempts=nil;return true end
    self:ReleaseInputs("AutoFarmLevel")
    if job.UnsummonNext and os.clock()<job.UnsummonNext then return false end
    local native=self:GetNativeInput();local action=native and native.Actions.Summon
    if not action or not action.Remote.Parent then
        job.Reason=self.NativeReason or "Waiting for native summon input";return false
    end
    if (job.UnsummonAttempts or 0)>=3 then job.Cancelled=true;job.Reason="Stopped: stand did not despawn";return false end
    if self.Closed or job.Cancelled or player.Character~=character or not networkReady()then return false end
    -- Q is the same observed native toggle for summon and despawn, with no guessed args.
    action.Remote:FireServer(unpack(action.Begin or {}))
    job.UnsummonAttempts=(job.UnsummonAttempts or 0)+1;job.UnsummonNext=os.clock()+2
    return false
end
function C:TrackLevelQuest(job,q)
    if job.QuestConnections then for _,v in ipairs(job.QuestConnections)do v:Disconnect()end end
    job.Quest=q;job.QuestConnections={}
    local observed=self:ReadLevelQuest(q)
    self.RuntimeCache.Bindings.LevelFarmQuest={Id=q.Name,Enemy=observed.Enemy,
        NPC=job.NPC and job.NPC.Name or "Giorno"}
    local function observe()
        local value=self:ReadLevelQuest(q)
        if not job.Cancelled and value and value.Completed then job.CompletionSeen=true end
    end
    for _,name in ipairs({"Kills","Completed"})do
        local value=q:FindFirstChild(name)
        table.insert(job.QuestConnections,value:GetPropertyChangedSignal("Value"):Connect(observe))
    end
    observe()
end
function C:WaitLevelUnderground(job)
    local move=self.Movement
    if not move or move.Owner~="AutoFarmLevel"or self.Closed or job.Cancelled
        or not self.Settings.AutoFarmLevel or player.Character~=move.Character or move.Humanoid.Health<=0 then return false end
    if move.UndergroundWaiting then return true end
    if move.AttachConnection then move.AttachConnection:Disconnect();move.AttachConnection=nil end
    local pose=move.LastApplied or move.Root.CFrame
    move.Target=nil;move.Behind=nil;move.UndergroundWaiting=true;move.LastApplied=pose
    move.Root.CFrame=pose;move.Root.AssemblyLinearVelocity=Vector3.zero;move.Root.AssemblyAngularVelocity=Vector3.zero
    -- Keep the existing platform/collision lease and original ReturnCFrame.
    -- Only replace the dead-target writer; no movement release/reacquire here.
    move.AttachConnection=RunService.Heartbeat:Connect(function()
        if self.Closed or job.Cancelled or not self.Settings.AutoFarmLevel or not networkReady()
            or self.Movement~=move or player.Character~=move.Character or move.Humanoid.Health<=0 then
            self:ReleaseMovement("AutoFarmLevel");return
        end
        self:MaintainCollisions();move.Root.CFrame=pose
        move.Root.AssemblyLinearVelocity=Vector3.zero;move.Root.AssemblyAngularVelocity=Vector3.zero
    end)
    return true
end
function C:ResumeLevelMovement()
    local move=self.Movement
    if not move or move.Owner~="AutoFarmLevel"or not move.UndergroundWaiting then return end
    if move.AttachConnection then move.AttachConnection:Disconnect();move.AttachConnection=nil end
    if move.QuestPoseCleanup then move.QuestPoseCleanup();move.QuestPoseCleanup=nil end
    self:ReleaseBring("AutoFarmLevel")
    move.UndergroundWaiting=nil
end
function C:AcceptLevelQuest(npc,job)
    if self.Interaction then return nil,"Waiting for NPC interaction"end
    local prompt=npc and npc:FindFirstChildOfClass("ProximityPrompt")
    local root=npc and npc:FindFirstChild("HumanoidRootPart")
    if not prompt or not root then return nil,"Waiting for quest NPC"end
    local move=self:ClaimMovement("AutoFarmLevel");if not move then return nil,"Waiting for movement"end
    self:ResumeLevelMovement()
    local before={};local folder=player.Data:FindFirstChild("Quests")
    if not folder then self:ReleaseMovement("AutoFarmLevel");return nil,"Waiting for quest data"end
    for _,q in ipairs(folder:GetChildren())do local v=self:ReadLevelQuest(q);if v then before[q]={Kills=v.Kills,Completed=v.Completed}end end
    local request={Npc=npc,Owner="AutoFarmLevel",Job=job};self.Interaction=request
    if not move.ReturnCFrame then move.ReturnCFrame=move.Root.CFrame end
    move.LastApplied=root.CFrame*CFrame.new(2,0,0)
    local below=self.Settings.QuestPosition=="Below NPC"
    if below then
        local depth=math.min(4.9,prompt.MaxActivationDistance-.1)
        if depth<3 or root.Position.Y-depth<=workspace.FallenPartsDestroyHeight+12 then
            self.Interaction=nil;self:ReleaseMovement("AutoFarmLevel")
            return nil,"Below-NPC interaction is unavailable here; choose Original position"
        end
        local base=self:UnderCFrame(root.CFrame,depth);local best,bestTop=base,math.huge
        local parts={}
        for _,part in ipairs(move.Character:QueryDescendants("BasePart"))do
            if part.Transparency<.99 then table.insert(parts,{Relative=move.Root.CFrame:ToObjectSpace(part.CFrame),Half=part.Size*.5})end
        end
        for turn=0,3 do
            local pose=base*CFrame.Angles(0,turn*math.pi/2,0);local top=-math.huge
            for _,part in ipairs(parts)do
                local cf=pose*part.Relative;local half=part.Half
                local extent=math.abs(cf.RightVector.Y)*half.X+math.abs(cf.UpVector.Y)*half.Y+math.abs(cf.LookVector.Y)*half.Z
                top=math.max(top,cf.Position.Y+extent)
            end
            if top<bestTop then best,bestTop=pose,top end
        end
        local state=move.Humanoid:GetState();local autoRotate=move.Humanoid.AutoRotate
        move.QuestPoseCleanup=function()
            if move.Humanoid.Parent then
                if move.Humanoid:GetState()==Enum.HumanoidStateType.Physics and move.Humanoid.Health>0 then move.Humanoid:ChangeState(state)end
                if move.Humanoid.AutoRotate==false then move.Humanoid.AutoRotate=autoRotate end
            end
        end
        self:AcquireCollisions("AutoFarmLevel",move.Character)
        move.Humanoid.AutoRotate=false;move.Humanoid:ChangeState(Enum.HumanoidStateType.Physics)
        move.LastApplied=best;move.Root.CFrame=best
    end
    move.Root.CFrame=move.LastApplied
    move.AttachConnection=(below and RunService.PreSimulation or RunService.Heartbeat):Connect(function()
        if self.Interaction==request and not self.Closed and not job.Cancelled
            and player.Character==move.Character and move.Root.Parent then
            move.Root.CFrame=move.LastApplied;move.Root.AssemblyLinearVelocity=Vector3.zero
        end
    end)
    local function valid()return not self.Closed and not job.Cancelled and self.Settings.AutoFarmLevel
        and networkReady()and player.Character==move.Character and move.Humanoid.Health>0 end
    task.wait(.3)
    if below and valid()then
        local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances={move.Character,npc,workspace:FindFirstChild("Living"),workspace.Map.NPCs}
        local floor=workspace:Raycast(root.Position+Vector3.yAxis,Vector3.new(0,-20,0),params)
        local top=-math.huge
        for _,part in ipairs(move.Character:QueryDescendants("BasePart"))do if part.Transparency<.99 then
            local cf=part.CFrame;local half=part.Size*.5
            top=math.max(top,part.Position.Y+math.abs(cf.RightVector.Y)*half.X+math.abs(cf.UpVector.Y)*half.Y+math.abs(cf.LookVector.Y)*half.Z)
        end end
        job.QuestClearance=floor and floor.Position.Y-top or nil
        if not floor or top>floor.Position.Y-.15 then
            self.Interaction=nil;self:ReleaseMovement("AutoFarmLevel");job.Cancelled=true
            return nil,"Stopped: below-NPC pose does not fit; choose Original position"
        end
    end
    if valid()then fireproximityprompt(prompt)end
    local deadline=os.clock()+5
    repeat task.wait(.05)until request.Data or not valid()or os.clock()>deadline
    local data=request.Data;local accepted
    local text=data and type(data[3])=="table"and data[3][1]
    -- Scared Noob's inspected offer says "scary ... cave ... help", not "kill".
    local offer=type(text)=="string"and(text:lower():find("kill",1,true)
        or(npc.Name=="Scared Noob"and text:find("cave",1,true)and data[3][2]=="Okay!")
        or(npc.Name=="DIO"and text:find("finish him off",1,true)and data[3][2]=="Yes!"))
    self.LastLevelPrompt={NPC=npc.Name,Received=data~=nil,Allowed=offer and true or false,
        Text=type(text)=="string"and text:sub(1,180)or nil,Position=self.Settings.QuestPosition,Clearance=job.QuestClearance}
    if valid()and data and request.Epoch==self.NpcPromptEpoch and not data[4]
        and type(data[3])=="table"and type(data[3][1])=="string"
        and offer and data[2]:IsDescendantOf(npc)then
        -- NpcDialouge native Yes branch sends the fresh scoped Done with no arguments.
        data[2]:FireServer();job.AcceptRequests=(job.AcceptRequests or 0)+1
        deadline=os.clock()+6
        repeat
            task.wait(.1)
            for _,q in ipairs(folder:GetChildren())do
                local v=self:ReadLevelQuest(q);local old=before[q]
                if v and not v.Completed and(not old or old.Completed or v.Kills<old.Kills)then accepted=q;break end
            end
        until accepted or not valid()or os.clock()>deadline
    end
    local gui=player.PlayerGui:FindFirstChild("NpcDialouge");local frame=gui and gui:FindFirstChild("Frame")
    local no=frame and frame:FindFirstChild("No");local title=frame and frame:FindFirstChild("Namee")
    if valid()and data and request.Epoch==self.NpcPromptEpoch and title and title.Text==data[1]
        and no and type(firesignal)=="function"then firesignal(no.MouseButton1Click)end
    if self.Interaction==request then self.Interaction=nil end
    if below and valid()then self:WaitLevelUnderground(job)else self:ReleaseMovement("AutoFarmLevel")end
    return accepted,accepted and "Quest accepted"or "Quest acceptance not confirmed"
end
function C:AutoFarmLevelStep(job)
    local owner="AutoFarmLevel"
    if standName()=="None" or standName()=="" then
        self:ReleaseInputs(owner);self:WaitLevelUnderground(job)
        return false,"Equip a stand before starting level farming"
    end
    if inLair()then return false,"Waiting: leave the lair"end
    for _,id in ipairs({"AutoFarmMob","AutoLair","AutoSkill","BringMob","Fly"})do
        local other=self.Jobs[id];if other and not other.Cancelled and self.JobArmed[id]then
            self:ReleaseInputs(owner);self:ReleaseMovement(owner);return false,"Waiting: stop "..id
        end
    end
    local npc,level=self:LevelQuestNPC();if not npc then return false,"Waiting for level quest NPC"end
    local quest=self:ReadLevelQuest(job.Quest)
    if not job.InitialChecked then
        job.InitialChecked=true
        local record=self.RuntimeCache.Bindings.LevelFarmQuest
        if record then
            local q=player.Data.Quests:FindFirstChild(record.Id);local v=self:ReadLevelQuest(q)
            if v and v.Enemy==record.Enemy and not v.Completed then
                job.NPC=workspace.Map.NPCs:FindFirstChild(record.NPC)
                self:TrackLevelQuest(job,q);quest=v
            end
        end
        -- A single existing kill quest is safe to resume from its replicated target/counter.
        -- Do not abandon quests or guess among multiple active tasks after a reconnect.
        if not quest then
            local existing
            for _,q in ipairs(player.Data.Quests:GetChildren())do
                local v=self:ReadLevelQuest(q)
                if v and not v.Completed then
                    if existing then job.Cancelled=true;return false,"Several kill quests are active. Finish one before starting level farming." end
                    existing=v
                end
            end
            if existing then
                job.NPC=npc;self:TrackLevelQuest(job,existing.Instance);quest=existing;job.QuestProgressAt=os.clock()
            end
        end
    end
    if job.Quest and(not quest or quest.Completed)then
        if not quest and not job.CompletionSeen then
            job.Cancelled=true;return false,"Stopped: quest disappeared before completion was observed"
        end
        self:ReleaseInputs(owner)
        job.CompletionSeen=true
        self:WaitLevelUnderground(job)
        if not self:LevelStandOff(job)then return false,job.Reason or "Despawning stand"end
        self.LevelFarmStats.Completed+=1
        self.LevelFarmStats.LastDespawnConfirmed=os.clock()
        self.RuntimeCache.Bindings.LevelFarmQuest=nil
        if job.QuestConnections then for _,v in ipairs(job.QuestConnections)do v:Disconnect()end;job.QuestConnections=nil end
        job.Quest=nil;job.Target=nil;job.CompletionSeen=nil;job.LastKills=nil;job.QuestProgressAt=nil
        job.UnsummonNext=nil;job.NextAccept=os.clock()+1;job.AcceptFailures=0
        return true,"Quest complete; taking the next quest"
    end
    if not quest then
        if job.NextAccept and os.clock()<job.NextAccept then return false,"Waiting before quest interaction"end
        local ready,reason=self:EnsureLevelQuestNPC(job,npc)
        if not ready then return false,reason end
        if not self:LevelStandOff(job)then return false,job.Reason or "Despawning stand before quest"end
        local q,reason=self:AcceptLevelQuest(npc,job)
        if q then job.NPC=npc;self:TrackLevelQuest(job,q);job.QuestProgressAt=os.clock();job.AcceptFailures=0
            self.LevelFarmStats.Accepted+=1;return true,"Quest accepted"
        end
        job.AcceptFailures=(job.AcceptFailures or 0)+1;job.NextAccept=os.clock()+math.min(15,3*2^(job.AcceptFailures-1))
        if job.AcceptFailures>=3 then job.Cancelled=true end
        return false,reason
    end
    if quest.Kills~=job.LastKills then job.LastKills=quest.Kills;job.QuestProgressAt=os.clock()end
    if not job.WaitingForBring and os.clock()-(job.QuestProgressAt or os.clock())>120 then
        job.Cancelled=true;return false,"Stopped: quest counter did not progress"
    end
    local target=job.Target;local h=target and target:FindFirstChildOfClass("Humanoid")
    if not target or not target.Parent or not h or h.Health<=0 or target.Name~=quest.Enemy then
        self:WaitLevelUnderground(job);target=self:FindTarget(quest.Enemy);job.Target=nil
    end
    if not target then return false,"Waiting for "..quest.Enemy end
    local active,reason=self:FarmTargetStep(target,job,owner)
    return active,string.format("%s %d/%d | %s",quest.Enemy,quest.Kills,quest.Maximum,reason)
end
local function npcRoot(npc)
    local root=npc:FindFirstChild("HumanoidRootPart") or npc.PrimaryPart or npc:FindFirstChild("Torso") or npc:FindFirstChild("Head")
    return root and root:IsA("BasePart")and root or nil
end
function C:NpcKey(npc)
    local root=npcRoot(npc);local position=root and root.Position or npc:GetPivot().Position
    return npc.Name.."@"..string.format("%.1f,%.1f",position.X,position.Z)
end
function C:LairNPCs()
    local map=workspace:FindFirstChild("Map");local folder=map and map:FindFirstChild("NPCs");local out={}
    if folder then for _,npc in ipairs(folder:GetChildren())do
        if npc:IsA("Model") and npc.Name=="i_stabman" and self:ReadLairLevel(npc)then
            table.insert(out,npc)
        end
    end end
    table.sort(out,function(a,b)return self:NpcKey(a)<self:NpcKey(b)end)
    return out
end
local LAIR_LEVELS={15,40,80,100,200}
local LAIR_DIFFICULTY_LEVEL={easy=15,hard=40,extreme=80,impossible=100}
-- Observed native map markers (2026-10-11); matched tightly, never by arbitrary NPC order.
local LAIR_MARKERS={
    {Level=15,X=-727.0069,Z=-939.0004},{Level=40,X=-730.8390,Z=-387.3200},
    {Level=80,X=-326.2880,Z=-131.7776},{Level=100,X=-90.1790,Z=-884.9810},
    {Level=200,X=28082.2109,Z=-234.0059},
}
local function lairLevel(text)
    if type(text)~="string"then return nil end
    text=text:lower()
    local value=tonumber(text:match("level%s*[:%-]?%s*(%d+)")or text:match("lvl%.?%s*[:%-]?%s*(%d+)")or text:match("(%d+)%s*%+"))
    return table.find(LAIR_LEVELS,value)and value or nil
end
function C:ReadLairLevel(npc,data)
    if type(data)=="table"then
        local level=lairLevel(data[1])or(type(data[3])=="table"and lairLevel(data[3][1]))
        if level then return level end
        local text=type(data[3])=="table"and data[3][1]
        local difficulty=type(text)=="string"and text:match("%(([^%)]+)%)")
        if difficulty and LAIR_DIFFICULTY_LEVEL[difficulty:lower()]then return LAIR_DIFFICULTY_LEVEL[difficulty:lower()]end
    end
    local humanoid=npc:FindFirstChildOfClass("Humanoid")
    local prompt=npc:FindFirstChildOfClass("ProximityPrompt")
    local level=lairLevel(npc.Name)or(humanoid and lairLevel(humanoid.DisplayName))
        or(prompt and(lairLevel(prompt.ObjectText)or lairLevel(prompt.ActionText)))
    if level then return level end
    for _,label in ipairs(npc:QueryDescendants("TextLabel"))do
        level=lairLevel(label.Text);if level then return level end
    end
    local root=npcRoot(npc);local position=root and root.Position or npc:GetPivot().Position
    for _,marker in ipairs(LAIR_MARKERS)do
        if math.abs(position.X-marker.X)<2 and math.abs(position.Z-marker.Z)<2 then return marker.Level end
    end
    local known=self.RuntimeCache.LairLabels[self:NpcKey(npc)]
    return known and(known.RequiredLevel or(known.Label and LAIR_DIFFICULTY_LEVEL[known.Label:lower()]))or nil
end
function C:LairChoices()
    local values,byLabel,byKey={}, {}, {}
    for _,level in ipairs(LAIR_LEVELS)do
        local label=tostring(level).."+";table.insert(values,label);byLabel[label]="level:"..level
    end
    for _,npc in ipairs(self:LairNPCs())do
        local key=self:NpcKey(npc);byKey[key]=npc
        local level=self:ReadLairLevel(npc)
        if level and not byKey["level:"..level]then byKey["level:"..level]=npc end
    end
    self.LairByLabel=byLabel;self.LairByKey=byKey
    return values
end
function C:RecordLairPrompt(npc,data)
    local remote=type(data)=="table"and data[2]
    if typeof(remote)~="Instance"or not remote:IsA("RemoteEvent")or not remote:IsDescendantOf(npc)then return false end
    local text=type(data[3])=="table"and data[3][1]
    if type(text)~="string"then return false end
    local lower=text:lower()
    if not lower:find("dungeon",1,true)and not lower:find("lair",1,true)then return false end
    local key=self:NpcKey(npc);if not key then return false end
    local required=self:ReadLairLevel(npc,data)
    local allowed=not data[4] and lower:find("enter this dungeon",1,true)~=nil
    self.RuntimeCache.LairLabels[key]={Label=text:match("%(([^%)]+)%)"),Text=text:sub(1,256),
        CanEnter=allowed,RequiredLevel=required}
    self.RuntimeCache.Bindings[key]=allowed and {NPC=npc,Remote=remote,JobId=game.JobId,
        Level=required or player.Data.Level.Value}or nil
    return true
end
function C:SelectedLairNPC()
    self:LairChoices()
    if self.Settings.LairNpc~="_auto"then
        local required=tonumber(self.Settings.LairNpc:match("^level:(%d+)$"))
        if required and player.Data.Level.Value<required then return nil,"Requires level "..required end
        return self.LairByKey[self.Settings.LairNpc]
    end
    -- Legacy profiles may still contain _auto; it is no longer a dropdown option.
    for i=#LAIR_LEVELS,1,-1 do
        local level=LAIR_LEVELS[i];local npc=self.LairByKey["level:"..level]
        local known=npc and self.RuntimeCache.LairLabels[self:NpcKey(npc)]
        if level<=player.Data.Level.Value and known and known.CanEnter then return npc end
    end
end
function C:RequestLairStream(job,position)
    if not workspace.StreamingEnabled or job.StreamThread or(job.StreamAttempts or 0)>=2 then return end
    if not job.StreamAt or os.clock()-job.StreamAt>3 then
        job.StreamAt=os.clock();job.StreamAttempts=(job.StreamAttempts or 0)+1
        job.StreamThread=task.defer(function()
            local ok,err=pcall(function()player:RequestStreamAroundAsync(position,3)end)
            if not self.Closed and not job.Cancelled then job.StreamOK=ok;job.StreamError=not ok and tostring(err)or nil end
            job.StreamThread=nil
        end)
    end
end
function C:FloatUnderLair(job,npc,target)
    local move=self:ClaimMovement("AutoLair")
    if not move then return false,"Waiting for movement"end
    if not move.ReturnCFrame then move.ReturnCFrame=move.Root.CFrame end
    if npc then move.LairNPC=npc end
    if target then move.Target=target end
    self:AcquireCollisions("AutoLair",move.Character)
    local function follow()
        if self.Closed or job.Cancelled or not self.Settings.AutoLair or not networkReady()
            or self.Movement~=move or player.Character~=move.Character or move.Humanoid.Health<=0 then
            self:ReleaseMovement("AutoLair");return
        end
        local inside=inLair();local reference
        local jumped=move.LastApplied and(move.Root.Position-move.LastApplied.Position).Magnitude>128
        if jumped then
            local entering=job.EntryPending or(job.RunStartedAt and not job.InstaFirstAt)
            move.ServerTransition=entering and "entry"or"exit"
            move.ServerPosition=move.Root.Position;job.LastServerPosition=move.Root.Position
            job.LastServerTransition=move.ServerTransition;job.LastServerJumpAt=os.clock()
            if entering then self:RequestLairStream(job,move.ServerPosition)end
        end
        if move.ServerTransition=="exit"and not inside then move.ServerTransition=nil end
        local arriving=move.ServerTransition=="entry"and(not inside or not self:GetLairRoom())
        if arriving then self:RequestLairStream(job,move.ServerPosition)end
        if inside and not arriving and move.ServerTransition~="exit"then
            local room=self:GetLairRoom()
            local locked=job.InstaTarget
            local boss=locked and locked.Parent and locked:FindFirstChild("HumanoidRootPart")and locked or(room and self:FindLairTarget(room))
            local root=boss and boss:FindFirstChild("HumanoidRootPart")
            if root then move.Target=boss;reference=root.CFrame end
        elseif not arriving and move.ServerTransition~="exit"then
            local selected=move.LairNPC
            if not selected or not selected.Parent then selected=self:SelectedLairNPC();move.LairNPC=selected end
            local root=selected and npcRoot(selected)
            if root then reference=root.CFrame end
        end
        local cf
        if arriving or move.ServerTransition=="exit"then
            local depth=arriving and self.Settings.LairDistance or 5
            cf=CFrame.new(move.ServerPosition-Vector3.new(0,depth,0));move.FloatReferenceY=move.ServerPosition.Y
        elseif reference then
            move.ServerTransition=nil
            cf=self:UnderCFrame(reference,inside and self.Settings.LairDistance or 5,12);move.FloatReferenceY=reference.Position.Y
        elseif move.FloatInside~=inside or not move.LastApplied
            or (move.Root.Position-move.LastApplied.Position).Magnitude>12 then
            -- Adopt a server teleport instead of pulling back into the previous room.
            cf=move.Root.CFrame-Vector3.new(0,inside and self.Settings.LairDistance or 5,0);move.FloatReferenceY=move.Root.Position.Y
        else cf=move.LastApplied end
        if cf.Position.Y<=workspace.FallenPartsDestroyHeight+12 then
            job.Cancelled=true;job.Reason="Stopped: floating position is near the void"
            self:ReleaseMovement("AutoLair");return
        end
        move.FloatInside=inside;move.Humanoid.AutoRotate=false;move.AppliedAutoRotate=false
        self:MaintainCollisions();move.Root.CFrame=cf
        move.Root.AssemblyLinearVelocity=Vector3.zero;move.Root.AssemblyAngularVelocity=Vector3.zero
        move.LastApplied=cf;move.FloatActive=true
    end
    if not move.FloatConnection then
        if move.AttachConnection then move.AttachConnection:Disconnect();move.AttachConnection=nil end
        move.FloatConnection=RunService.PreSimulation:Connect(follow)
        move.AttachConnection=RunService.Heartbeat:Connect(follow)
    end
    follow()
    return self.Movement==move,"Floating below lair"
end
function C:InteractWithLair(npc,accept,job,owner)
    if self.Closed or not networkReady()then return false,"Game server disconnected"end
    assert(type(fireproximityprompt)=="function","NPC interaction is unavailable.")
    if self.Interaction then return false,"Waiting for NPC interaction"end
    local move=self:ClaimMovement(owner);if not move then return false,"Waiting for movement"end
    local targetRoot=npcRoot(npc);local prompt=npc:FindFirstChildOfClass("ProximityPrompt")
    if not targetRoot or not prompt then self:ReleaseMovement(owner);return false,"Lair NPC unavailable"end
    local request={Npc=npc,Owner=owner,Job=job};self.Interaction=request
    if not move.ReturnCFrame then move.ReturnCFrame=move.Root.CFrame end
    local pos=targetRoot.Position+Vector3.new(2,0,0)
    if owner=="AutoLair"then self:FloatUnderLair(job,npc)else
    move.LastApplied=CFrame.lookAt(pos,targetRoot.Position);move.Root.CFrame=move.LastApplied
    move.AttachConnection=RunService.Heartbeat:Connect(function()
        if self.Interaction==request and not self.Closed and not job.Cancelled and not inLair()
            and player.Character==move.Character then
            move.Root.CFrame=move.LastApplied;move.Root.AssemblyLinearVelocity=Vector3.zero
        end
    end)
    end
    local function requestEntry(remote)
        remote:FireServer();job.EntryAt=os.clock();job.EntryPending=true
        local finish=os.clock()+8
        repeat task.wait(0.05)until inLair()or job.Cancelled or self.Closed or os.clock()>finish
        local confirmed=inLair()and not job.Cancelled and not self.Closed
        job.EntryPending=false
        return confirmed
    end
    task.wait(0.3)
    if job.Cancelled or self.Closed then self.Interaction=nil;self:ReleaseMovement(owner);return false,"Stopped"end
    -- Every entry must receive a fresh scoped server prompt. Replaying a cached Done
    -- callback after a clear is not proof of current authorization and triggered a live kick.
    fireproximityprompt(prompt)
    local untilAt=os.clock()+5
    repeat task.wait(0.05)until request.Data or job.Cancelled or self.Closed or os.clock()>untilAt
    local data=request.Data;local promptEpoch=request.Epoch
    local valid=data and self:RecordLairPrompt(npc,data)
    local allowed=valid and not data[4] and type(data[3][1])=="string"and data[3][1]:lower():find("enter this dungeon",1,true)
    self.LastNPCInteraction={Key=self:NpcKey(npc),Received=data~=nil,Valid=valid==true,Allowed=allowed and true or false,
        Kind=data and data[4],Text=data and type(data[3])=="table"and tostring(data[3][1]):sub(1,256)or nil}
    local entered=false
    if accept and allowed and not job.Cancelled and not self.Closed then
        -- Native NpcDialouge Yes callback sends this exact scoped remote with no args.
        entered=requestEntry(data[2])
    end
    local gui=player.PlayerGui:FindFirstChild("NpcDialouge")
    local frame=gui and gui:FindFirstChild("Frame")
    local no=frame and frame:FindFirstChild("No");local title=frame and frame:FindFirstChild("Namee")
    if valid and not job.Cancelled and not self.Closed and promptEpoch==self.NpcPromptEpoch
        and title and title:IsA("TextLabel")and title.Text==data[1]and no and type(firesignal)=="function"then
        firesignal(no.MouseButton1Click)
    end
    self.Interaction=nil
    if owner~="AutoLair"or job.Cancelled or self.Closed then self:ReleaseMovement(owner)end
    if self.RefreshLairUI then self.RefreshLairUI()end
    if not valid then return false,"No verified lair prompt received"end
    if accept and not allowed then return false,"Lair entry is unavailable for this character"end
    if accept then return entered,entered and "Lair entry confirmed"or"No confirmed lair entry"end
    return true,"Lair discovered"
end
function C:StopTask(id)
    local taskInfo=self.Tasks[id]
    if taskInfo then
        taskInfo.Cancelled=true;taskInfo.Active=false
        if taskInfo.Thread and coroutine.status(taskInfo.Thread)~="dead"and taskInfo.Thread~=coroutine.running()then pcall(task.cancel,taskInfo.Thread)end
    end
    if self.Interaction and self.Interaction.Owner==id then self.Interaction=nil end
    self:ReleaseMovement(id)
end
local MERCHANT_MODELS={Merchant1st=true,Merchant120=true,Merchant500=true,MerchantAU=true,Homeless=true}
local MERCHANT_LAYOUTS={Merchant1=4,Merchantlvl120=4,Merchantlvl500=2,MerchantHomeless=1,MerchantAU=4,GalacticalMerchant=4}
function C:MerchantNPCs()
    local map=workspace:FindFirstChild("Map");local folder=map and map:FindFirstChild("NPCs");local out={}
    if folder then for _,npc in ipairs(folder:GetChildren())do
        if npc:IsA("Model")and MERCHANT_MODELS[npc.Name]and npcRoot(npc)and npc:FindFirstChildOfClass("ProximityPrompt")then table.insert(out,npc)end
    end end
    table.sort(out,function(a,b)return self:NpcKey(a)<self:NpcKey(b)end)
    return out
end
function C:MerchantChoices()
    local labels={};self.MerchantByLabel={};self.MerchantByKey={}
    for _,npc in ipairs(self:MerchantNPCs())do
        local key=self:NpcKey(npc);local label=npc.Name.." ["..key.."]"
        table.insert(labels,label);self.MerchantByLabel[label]=key;self.MerchantByKey[key]=npc
    end
    return labels
end
function C:RecordMerchantPrompt(npc,data)
    if not npc or type(data)~="table"or typeof(data[2])~="Instance"or not data[2]:IsA("RemoteEvent")
        or not data[2]:IsDescendantOf(npc)or type(data[3])~="table"then return false,"Unverified merchant packet"end
    local count=MERCHANT_LAYOUTS[data[4]]
    if not count then return false,"This merchant layout is not implemented yet"end
    local key=self:NpcKey(npc)
    if not key then return false,"Merchant root is unavailable"end
    -- Native layouts put the exit label immediately after the purchase labels.
    -- Never include that exit label as a purchasable item (500 has two; Homeless one).
    if type(data[3][count+2])~="string"then return false,"Incomplete native merchant layout"end
    local options={}
    for index=1,count do
        local label=data[3][index+1]
        if type(label)~="string"or #label>512 or not utf8.len(label)then return false,"Invalid merchant option label"end
        label=label:gsub("%c"," ")
        if label:match("%S")then
            local boundary=utf8.offset(label,121);if boundary then label=label:sub(1,boundary-1)end
            table.insert(options,{Id="Option"..index,Label=label})
        end
    end
    if #options==0 then return false,"No native merchant options received"end
    self.MerchantCatalogue[key]={NPC=npc,JobId=game.JobId,Tag=data[4],Options=options,At=os.clock()}
    return true,"Merchant catalogue received"
end
function C:MerchantOptionChoices()
    local labels={};self.MerchantOptionByLabel={}
    local entry=self.MerchantCatalogue[self.Settings.MerchantNpc]
    if entry and entry.NPC.Parent and entry.JobId==game.JobId then
        for _,option in ipairs(entry.Options)do
            local label=option.Label.." ["..option.Id.."]"
            table.insert(labels,label);self.MerchantOptionByLabel[label]=option.Id
        end
    end
    table.sort(labels);return labels
end
function C:PreviewMerchant(npc,job)
    local owner="MerchantPreview"
    if self.Closed or not networkReady()then return false,"Game server disconnected"end
    if inLair()or self.Interaction then return false,"Waiting for dungeon or NPC interaction"end
    for _,id in ipairs({"AutoFarmMob","AutoLair","AutoPickup"})do
        local worker=self.Jobs[id]
        if worker and not worker.Cancelled then return false,"Pause automation before merchant preview"end
    end
    if type(fireproximityprompt)~="function"then return false,"NPC interaction is unavailable"end
    local targetRoot=npcRoot(npc);local prompt=npc:FindFirstChildOfClass("ProximityPrompt")
    if not targetRoot or not prompt or not prompt.Enabled then return false,"Merchant NPC unavailable"end
    local move=self:ClaimMovement(owner);if not move then return false,"Waiting for movement"end
    local request={Npc=npc,Owner=owner,Job=job};self.Interaction=request
    move.ReturnCFrame=move.Root.CFrame
    move.LastApplied=CFrame.lookAt(targetRoot.Position+Vector3.new(2,0,0),targetRoot.Position)
    local function cancelled()return self.Closed or job.Cancelled or not networkReady()or player.Character~=move.Character end
    move.AttachConnection=RunService.Heartbeat:Connect(function()
        if self.Interaction==request and not cancelled()then move.Root.CFrame=move.LastApplied;move.Root.AssemblyLinearVelocity=Vector3.zero end
    end)
    move.Root.CFrame=move.LastApplied
    local valid,reason=false,"No verified merchant prompt received"
    local success=pcall(function()
        task.wait(0.3)
        if cancelled()then reason="Stopped";return end
        fireproximityprompt(prompt)
        local deadline=os.clock()+5
        repeat task.wait(0.05)until request.Data or cancelled()or os.clock()>deadline
        if cancelled()then reason="Stopped";return end
        valid,reason=self:RecordMerchantPrompt(npc,request.Data)
        if valid then
            -- In these inspected native merchant branches No closes the dialogue, never buys.
            local gui=player.PlayerGui:FindFirstChild("NpcDialouge")
            local frame=gui and gui:FindFirstChild("Frame");local no=frame and frame:FindFirstChild("No")
            local title=frame and frame:FindFirstChild("Namee");local epoch=request.Epoch
            if no and type(firesignal)=="function"then
                task.wait(3.5)
                if not cancelled()and self.Interaction==request and epoch==self.NpcPromptEpoch
                    and title and title:IsA("TextLabel")and title.Text==request.Data[1]then firesignal(no.MouseButton1Click)end
            end
        end
    end)
    if self.Interaction==request then self.Interaction=nil end
    self:ReleaseMovement(owner)
    if not success then return false,"Merchant preview failed; no purchase sent"end
    return valid,reason
end
function C:StartMerchantPreview()
    assert(not self.Closed and networkReady(),"Game server disconnected.")
    self:MerchantChoices()
    local npc=assert(self.MerchantByKey[self.Settings.MerchantNpc],"Select a merchant NPC.")
    local active=self.Tasks.MerchantPreview
    assert(not active or not active.Active,"A merchant preview is already running.")
    self.MerchantCatalogue[self:NpcKey(npc)]=nil
    if self.RefreshMerchantUI then self.RefreshMerchantUI()end
    local info={Active=true,Cancelled=false,Reason="Previewing merchant"};self.Tasks.MerchantPreview=info
    info.Thread=task.spawn(function()
        local ok,valid,reason=pcall(self.PreviewMerchant,self,npc,info)
        if not info.Cancelled then info.Reason=ok and reason or "Merchant preview failed; no purchase sent"end
        info.Valid=ok and valid==true;info.Active=false
        self:ReleaseMovement("MerchantPreview")
        if self.Interaction and self.Interaction.Owner=="MerchantPreview"then self.Interaction=nil end
        if self.RefreshMerchantUI and not self.Closed then self.RefreshMerchantUI()end
    end)
end
function C:DiscoverLairs()
    assert(not inLair(),"Finish the current lair before discovery.")
    self:StopTask("LairDiscovery")
    local taskInfo={Active=true,Cancelled=false,Completed=0,Reason="Discovering lairs"};self.Tasks.LairDiscovery=taskInfo
    taskInfo.Thread=task.spawn(function()
        local ok,err=xpcall(function()
            local npcs=self:LairNPCs()
            for i,npc in ipairs(npcs)do
                if self.Closed or taskInfo.Cancelled then break end
                taskInfo.Reason="Discovering lair "..i.."/"..#npcs
                local found=self:InteractWithLair(npc,false,taskInfo,"LairDiscovery")
                if found then taskInfo.Completed+=1 end
                task.wait(1.5)
            end
        end,debug.traceback)
        self:ReleaseMovement("LairDiscovery");self.Interaction=nil
        taskInfo.Active=false;taskInfo.Error=not ok and err or nil
        taskInfo.Reason=ok and(taskInfo.Completed>0 and "Discovery complete"or"No new lair responses")or "Discovery failed"
    end)
end
function C:GetLairRoom()
    if not inLair()then return nil end
    local _,_,root=alive();local map=workspace:FindFirstChild("Map");local spawns=map and map:FindFirstChild("LairSpawns")
    if not root or not spawns then return nil end
    for _,spawn in ipairs(spawns:GetChildren())do for _,room in ipairs(spawn:GetChildren())do
        if room:IsA("Model")then
            local cf,size=room:GetBoundingBox();local pos=cf:PointToObjectSpace(root.Position)
            if math.abs(pos.X)<=size.X/2+12 and math.abs(pos.Y)<=size.Y/2+15 and math.abs(pos.Z)<=size.Z/2+12 then
                return {Model=room,CFrame=cf,Size=size}
            end
        end
    end end
    return nil
end
function C:FindLairTarget(room)
    local _,_,root=alive();local living=workspace:FindFirstChild("Living")
    if not root or not living or not room or not room.Model.Parent then return nil end
    local selected,best,bestBoss,bestHealth=nil,math.huge,false,-1
    local level=tonumber(self.Settings.LairNpc:match("^level:(%d+)$"))
    local bossNames={[15]="bad gi",[40]="dio",[80]="homeless",[100]="diavolo",[200]="jotaro"}
    for _,humanoid in ipairs(living:QueryDescendants("Model > Humanoid"))do
        local model=humanoid.Parent;local part=model:FindFirstChild("HumanoidRootPart")
        if part and humanoid.Health>0 and not Players:GetPlayerFromCharacter(model)then
            local pos=room.CFrame:PointToObjectSpace(part.Position)
            if math.abs(pos.X)<=room.Size.X/2+12 and math.abs(pos.Y)<=room.Size.Y/2+15 and math.abs(pos.Z)<=room.Size.Z/2+12 then
                local distance=(root.Position-part.Position).Magnitude
                local name=model.Name:lower()
                local boss=name:find("boss",1,true)~=nil or(level and bossNames[level]and name:find(bossNames[level],1,true)~=nil)or false
                local health=humanoid.MaxHealth
                if (boss and not bestBoss)or(boss==bestBoss and(health>bestHealth or(health==bestHealth and distance<best)))then
                    selected,best,bestBoss,bestHealth=model,distance,boss,health
                end
            end
        end
    end
    return selected
end
function C:TryLairInstantKill(target,job)
    if job.Cancelled or self.Closed or not networkReady()or not inLair()then return false,"Stopped"end
    -- A source reexecution inside a lair may have missed LairStart. In that case
    -- start a conservative fresh timer, never reuse the previous run's timestamp.
    if not job.RunStartedAt then job.RunStartedAt=os.clock();job.RunClockSource="Observed inside lair"end
    local remaining=self.LairMinimumSeconds-(os.clock()-job.RunStartedAt)
    if remaining>0 then return false,string.format("Under boss: waiting %.1fs",remaining)end
    if job.InstaFirstAt and os.clock()-job.InstaFirstAt>6 then
        job.Cancelled=true;return false,"Stopped: no server-confirmed clear within 6s"
    end
    if type(gethiddenproperty)~="function"then return false,"Executor ownership check is unavailable"end
    local character,_,root=alive();local room=self:GetLairRoom()
    local humanoid=target and target:FindFirstChildOfClass("Humanoid")
    local targetRoot=target and target:FindFirstChild("HumanoidRootPart")
    if not character or not room or not targetRoot or not humanoid
        or Players:GetPlayerFromCharacter(target)then return false,"Waiting for boss"end
    if humanoid.Health<=0 then return false,"Waiting for server clear"end
    local pos=room.CFrame:PointToObjectSpace(targetRoot.Position)
    if math.abs(pos.X)>room.Size.X/2+12 or math.abs(pos.Y)>room.Size.Y/2+15 or math.abs(pos.Z)>room.Size.Z/2+12 then
        return false,"Waiting for own dungeon boss"
    end
    local ownOK,ownPeer=pcall(gethiddenproperty,root,"NetworkOwnerV3")
    local targetOK,targetPeer=pcall(gethiddenproperty,targetRoot,"NetworkOwnerV3")
    if not ownOK or not targetOK or type(ownPeer)~="number"or ownPeer<=1 or ownPeer~=targetPeer or targetRoot.Anchored then
        job.OwnershipStableAt=nil;job.OwnershipRoot=nil
        if not job.OwnershipAt then job.OwnershipAt=os.clock()end
        if os.clock()-job.OwnershipAt>8 then job.Cancelled=true;return false,"Stopped: boss ownership is unavailable"end
        return false,"Waiting for boss control"
    end
    job.OwnershipAt=nil
    if job.OwnershipRoot~=targetRoot then job.OwnershipRoot=targetRoot;job.OwnershipStableAt=os.clock()end
    if not job.OwnershipStableAt then job.OwnershipStableAt=os.clock()end
    if os.clock()-job.OwnershipStableAt<.25 then return false,"Waiting for stable boss control"end
    if not humanoid:GetStateEnabled(Enum.HumanoidStateType.Dead)then return false,"Waiting: boss death state is unavailable"end
    if job.InstaTarget==target and job.InstaAt then
        if (job.InstaAttempts or 0)>=2 or os.clock()-job.InstaAt<1.5
            or humanoid:GetState()==Enum.HumanoidStateType.Dead then return false,"Waiting for server clear"end
        -- Retry only an observed still-living boss, with stable natural control.
        -- Never revive a boss, reset state to Running, write Health, or fabricate a clear.
    end
    -- No Health writes, local deletion or fabricated reward. Native state transition
    -- after ownership; server LairClear is the success event.
    job.InstaTarget=target;job.InstaAt=os.clock();job.InstaFirstAt=job.InstaFirstAt or job.InstaAt;job.InstaAttempts=(job.InstaAttempts or 0)+1
    humanoid:ChangeState(Enum.HumanoidStateType.Dead)
    return true,"Waiting for server clear"
end
function C:InventoryCounts()
    local out,containers={},{}
    local backpack=player:FindFirstChild("Backpack")
    if backpack then table.insert(containers,backpack)end
    if player.Character then table.insert(containers,player.Character)end
    for _,container in ipairs(containers)do
        for _,tool in ipairs(container:GetChildren())do
            if tool:IsA("Tool")then
                local amount=tool:GetAttribute("ItemAmount")
                if type(amount)~="number"then amount=1 end
                if amount>=0 and amount==amount and amount<math.huge then out[tool.Name]=(out[tool.Name]or 0)+amount end
            end
        end
    end
    return out
end
function C:PickupCandidate()
    local _,_,root=alive();if not root then return nil end
    local best,bestDistance=nil,self.Settings.PickupRadius
    for _,holder in ipairs(workspace:QueryDescendants("#ItemPromptHolder"))do
        if holder:IsA("BasePart")and holder.Position.Y>workspace.FallenPartsDestroyHeight+12 then
            local prompt=holder:FindFirstChildOfClass("ProximityPrompt")
            local cooldown=self.PickupCooldowns[holder]
            if prompt and prompt.Enabled and prompt.ActionText:lower():find("pick up",1,true)
                and (not cooldown or os.clock()>=cooldown.Until)then
                local distance=(root.Position-holder.Position).Magnitude
                if distance<bestDistance then best,bestDistance={Holder=holder,Prompt=prompt},distance end
            end
        end
    end
    return best
end
function C:TryPickup(candidate,job)
    if self.Closed or not networkReady()then return false,"Game server disconnected"end
    local holder,prompt=candidate.Holder,candidate.Prompt
    if not holder.Parent or not prompt.Parent or not prompt.Enabled then return false,"Item is no longer available"end
    if type(fireproximityprompt)~="function"then return false,"Pickup interaction is unavailable"end
    local move=self:ClaimMovement("AutoPickup")
    if not move then return false,"Waiting for movement"end
    local before=self:InventoryCounts()
    move.ReturnCFrame=move.Root.CFrame
    local pos=holder.Position+Vector3.new(0,3,0)
    move.LastApplied=CFrame.new(pos)*move.Root.CFrame.Rotation
    local function holdPosition()
        if self.Movement==move and not job.Cancelled and not self.Closed and player.Character==move.Character then
            move.Root.CFrame=move.LastApplied;move.Root.AssemblyLinearVelocity=Vector3.zero
        end
    end
    move.AttachConnection=RunService.Heartbeat:Connect(holdPosition);holdPosition()
    task.wait(0.25)
    if job.Cancelled or self.Closed then self:ReleaseMovement("AutoPickup");return false,"Stopped"end
    self.PickupStats.Attempts+=1
    -- Only a world pickup prompt. Never activates a Tool or confirms an item-use GUI.
    fireproximityprompt(prompt)
    local untilAt=os.clock()+3
    local gains={}
    repeat
        task.wait(0.1)
        local current=self:InventoryCounts()
        gains={}
        for name,count in pairs(current)do
            local delta=count-(before[name]or 0)
            if delta>0 then gains[name]=delta end
        end
    until (not holder.Parent and next(gains)~=nil)or job.Cancelled or self.Closed or os.clock()>untilAt
    self:ReleaseMovement("AutoPickup")
    if not holder.Parent and next(gains)~=nil then
        self.PickupStats.Confirmed+=1;self.PickupStats.LastGains=gains
        self.PickupCooldowns[holder]=nil
        return true,"Item collected"
    end
    local previous=self.PickupCooldowns[holder]
    local attempts=(previous and previous.Attempts or 0)+1
    self.PickupCooldowns[holder]={Attempts=attempts,Until=os.clock()+(attempts>=3 and 60 or 5*2^(attempts-1))}
    return false,"Waiting for pickup confirmation"
end
function C:StopJob(id)
    self:ObserveFarmDamage(self.Jobs[id])
    if id=="AutoFarmLevel"then self:ReleaseBringRadius()end
    if id=="Fly"then self.FlyVertical=0 end
    if id=="SpeedBoost"then self:ReleaseSpeed()end
    if id=="BringMob"then self:ReleaseBring()end
    if self.CombatSummon and self.CombatSummon.Owner==id then self.CombatSummon=nil end
    local job = self.Jobs[id]
    if job then
        if job.IdleConnection then job.IdleConnection:Disconnect();job.IdleConnection=nil end
        if job.QuestConnections then for _,v in ipairs(job.QuestConnections)do v:Disconnect()end;job.QuestConnections=nil end
        job.StopRequested=true
        if job.StreamThread then pcall(task.cancel,job.StreamThread);job.StreamThread=nil end
        job.Cancelled = true; job.Active = false
        job.Reason = self.Closed and "Unloaded" or (self.Settings[id] and "Paused" or "Off")
        if job.Thread and coroutine.status(job.Thread) ~= "dead" and job.Thread ~= coroutine.running() then
            pcall(task.cancel, job.Thread)
        end
    end
    self:ReleaseInputs(id)
    self:ReleaseMovement(id)
    self:ReleaseCollisions(id)
    if self.Interaction and self.Interaction.Owner==id then self.Interaction=nil end
end
function C:FailJob(id,reason)
    local job=self.Jobs[id];if not job then return end
    self.Settings[id]=false;self.JobArmed[id]=nil
    if self.Controls[id]then self.Controls[id]:Set(false,true)end
    self:StopJob(id);job.Reason=reason;job.FailureReason=reason
    if self.Library and not job.FailureNotified then
        job.FailureNotified=true
        self.Library:Notify({Title="Auto lair stopped",Description=reason,Time=6})
    end
end
function C:StartJob(id, step, delay)
    self:StopJob(id)
    self.JobArmed[id]=true
    local job = {Cancelled = false, Active = false, Reason = "Starting", Failures = 0, Ticks = 0}
    self.Jobs[id] = job
    job.Thread = task.spawn(function()
        while not self.Closed and not job.Cancelled and self.Settings[id] do
            job.Active = false
            if not networkReady()then self.DisconnectReason="Game server disconnected";self:Cleanup();break
            elseif id~="AutoPlay"and id~="AutoRejoin"and not alive() then job.Reason = "Waiting for character"
            elseif UserInputService:GetFocusedTextBox() then job.Reason = "Waiting for text input"
            else
                local ok, active, reason = pcall(step, job)
                if ok then
                    job.Active = active == true; job.Reason = reason or "Idle"; job.Failures = 0
                else
                    job.Failures += 1; job.Reason = "Action failed; retrying"
                    job.Error = tostring(active)
                    if job.Failures >= 3 then
                        job.Reason = "Stopped after repeated errors"; job.Cancelled = true
                        self:ReleaseInputs(id)
                        self:ReleaseMovement(id)
                        if self.Library then self.Library:Notify({Title = "Action stopped", Description = id .. ": check game state.", Time = 5}) end
                    end
                end
            end
            job.Ticks += 1
            task.wait(math.min(8, delay() * 2 ^ job.Failures))
        end
        job.Active = false
        if job.QuestConnections then for _,v in ipairs(job.QuestConnections)do v:Disconnect()end;job.QuestConnections=nil end
        if (id=="AutoLair"or id=="AutoFarmLevel")and job.Cancelled and not job.StopRequested and not self.Closed and self.Settings[id]then
            self:FailJob(id,job.Reason)
        end
        self:ReleaseInputs(id); self:ReleaseMovement(id)
        if id=="SpeedBoost"then self:ReleaseSpeed()end
        if not job.Cancelled then job.Reason = "Off" end
    end)
end
function C:StopEverything()
    local transition=self.Session.Transition
    if transition and transition.Pending and transition.State=="Searching"then
        transition.Pending=false;transition.State="Cancelled"
    end
    if not self.Session.Transition or not self.Session.Transition.Pending then self.Session.Status="Off"end
    for id in pairs(self.Tasks)do self:StopTask(id)end
    self:ClearWebhookQueue();self.WebhookArmed=false;table.clear(self.WebhookArmedEvents)
    self.Settings.LairWebhook=false;self.Settings.LevelWebhook=false
    if self.Controls.LairWebhook then self.Controls.LairWebhook:Set(false,true)end
    if self.Controls.LevelWebhook then self.Controls.LevelWebhook:Set(false,true)end
    for id in pairs(self.Jobs) do self:StopJob(id) end
    table.clear(self.JobArmed);self:ReleaseCollisions()
    for _, id in ipairs(JOB_IDS) do
        self.Settings[id] = false
        if self.Controls[id] then self.Controls[id]:Set(false,true) end
    end
    self.Settings.Screen = "Off"
    if self.Controls.Screen then self.Controls.Screen:Set("Off",true) end
    if self.ScreenOverlay then self.ScreenOverlay.Visible = false end
    self:ReleaseInputs()
    self:ReleaseMovement()
end
function C:OnCharacterLost(character)
    if character and player.Character and character~=player.Character then return end
    for id in pairs(self.Jobs)do self:StopJob(id)end
    for id in pairs(self.Tasks)do self:StopTask(id)end
    self:ClearWebhookQueue()
    self:ReleaseInputs();self:ReleaseMovement();self.Interaction=nil
    self:ReleaseCollisions()
    self.LastSafe=nil;self.NativeInput=nil
end
function C:ResumeCharacterJobs(character)
    if self.Closed or player.Character~=character then return end
    for _,id in ipairs(JOB_IDS)do
        if self.Settings[id] and self.JobArmed[id] and self.JobFactories[id]then self.JobFactories[id](true)end
    end
end
function C:Cleanup()
    if self.Closed then return end
    self.Closed = true; self.Ready = false
    for id in pairs(self.Tasks)do self:StopTask(id)end
    self:ClearWebhookQueue();self.WebhookArmed=false;table.clear(self.WebhookArmedEvents);self.WebhookURL=""
    for id in pairs(self.Jobs) do self:StopJob(id) end
    self:ReleaseInputs()
    self:ReleaseMovement()
    self:ReleaseCollisions();table.clear(self.JobArmed)
    for flag,entry in pairs(self.NativeConfigFlags or {})do
        if self.Airflow and self.Airflow.Flags[flag]==entry then self.Airflow.Flags[flag]=nil end
    end
    for _, connection in ipairs(self.Connections) do connection:Disconnect() end
    table.clear(self.Connections)
    if self.Library and not self.Library.Unloaded then self.Library:Unload() end
    if self.UI and self.UI.Parent then self.UI:Destroy() end
    self.LastSafe = nil
    if self.DisconnectReason then self.RuntimeCache.Bindings={} end
end

local SKILLS = {"Acid", "Barrage", "Block", "Heavy", "Jump", "M1", "Pose", "PowerPunch", "Quote", "Shoot"}
local SPEC = {
    AutoSummon = {kind = "boolean"}, AutoSkill = {kind = "boolean"}, AutoFarmMob = {kind = "boolean"}, AutoLair = {kind="boolean"}, AntiVoid = {kind = "boolean"},
    HideName = {kind = "boolean"}, Screen = {kind = "choice", values = {"Off", "Black", "White"}},
    Skills = {kind = "array", values = SKILLS, dynamic = true}, SkillDelay = {kind = "number", min = 0.3, max = 3},
    FarmMob = {kind = "string"}, FarmDistance = {kind = "number", min = 3, max = 6},
    LairNpc={kind="string"},LairSkills={kind="array",dynamic=true,values=SKILLS},LairDelay={kind="number",min=0.3,max=3},
    AutoPickup={kind="boolean"},PickupRadius={kind="number",min=25,max=3000},PickupInterval={kind="number",min=0.5,max=5},
}
local AIRFLOW_PRESET_NAMES = {"Abyss","Amber","Aurora","Christmas","Coffee","Crimson","Cyber","Dracula",
    "Emerald","Frost","Gold","Halloween","Haunted","Lunar","Matcha","Midnight","Mono","Nebula",
    "Ocean","Rose","Sakura","Sunset","Synthwave","Toxic","Tropical","Valentine","Velvet"}
local appearanceNames = {"Blizzard"}
for _,name in ipairs(AIRFLOW_PRESET_NAMES) do table.insert(appearanceNames,name) end
table.insert(appearanceNames,"Custom")
SPEC.AppearancePreset = {kind="choice",values=appearanceNames}
SPEC.UIScale = {kind="number",min=80,max=140}
SPEC.Snow = {kind="boolean"}
SPEC.SnowArea = {kind="choice",values={"Screen","UI"}}
SPEC.AccentHex = {kind="hex",role="accent"}
SPEC.SurfaceHex = {kind="hex",role="surface"}
SPEC.LairWebhook={kind="boolean"};SPEC.LevelWebhook={kind="boolean"};SPEC.WebhookHideName={kind="boolean"}
SPEC.LairDistance={kind="number",min=6,max=12}
SPEC.Noclip={kind="boolean"}
SPEC.AntiAFK={kind="boolean"}
SPEC.BringMob={kind="boolean"};SPEC.BringDepth={kind="number",min=10,max=60}
SPEC.Fly={kind="boolean"};SPEC.FlySpeed={kind="number",min=10,max=120}
SPEC.SpeedBoost={kind="boolean"};SPEC.WalkSpeed={kind="number",min=16,max=100}
SPEC.QuestPosition={kind="choice",values={"Below NPC","Original position"}};SPEC.AutoFarmLevel={kind="boolean"};SPEC.AutoQuestFarm={kind="boolean"};SPEC.QuestId={kind="string"}
SPEC.MerchantNpc={kind="string"};SPEC.MerchantOption={kind="choice",values={"","Option1","Option2","Option3","Option4"}}
SPEC.AutoRejoin={kind="boolean"};SPEC.RejoinMinutes={kind="number",min=1,max=1440}
SPEC.AutoPlay={kind="boolean"}
local APPEARANCE_PRESETS = {
    Blizzard={AccentHex="64CDD7",SurfaceHex="101118"},
    Frost={AccentHex="8FDFE4",SurfaceHex="161C25"},
    Ocean={AccentHex="50BCEB",SurfaceHex="0E1923"},
}
local function hexColor(hex)
    assert(type(hex)=="string" and #hex==6 and hex:match("^%x+$"),"Use a six-digit RGB color.")
    return Color3.fromRGB(tonumber(hex:sub(1,2),16),tonumber(hex:sub(3,4),16),tonumber(hex:sub(5,6),16))
end
local function colorHex(color)
    return string.format("%02X%02X%02X",math.round(color.R*255),math.round(color.G*255),math.round(color.B*255))
end
function C:ValidateAppearanceColor(hex,role)
    local color=hexColor(hex)
    local maximum=math.max(color.R,color.G,color.B)*255
    if role=="surface" then assert(maximum<=64,"Choose a dark surface (RGB channels at most 64).")
    else assert(maximum>=100,"Choose a brighter accent (one RGB channel at least 100).") end
    return color
end
function C:ApplyAppearance()
    local lib=self.Library
    if not lib or self.Closed then return end
    local surface=self:ValidateAppearanceColor(self.Settings.SurfaceHex,"surface")
    local accent=self:ValidateAppearanceColor(self.Settings.AccentHex,"accent")
    local function shifted(delta)
        return Color3.new(math.clamp(surface.R+delta/255,0,1),math.clamp(surface.G+delta/255,0,1),math.clamp(surface.B+delta/255,0,1))
    end
    local text=Color3.fromRGB(235,239,245);local muted=Color3.fromRGB(165,175,190)
    self.Appearance={Surface=surface,Accent=accent,Stroke=shifted(26),Text=text,Muted=muted}
    -- Airflow theme keys: dark charcoal surfaces, cyan accent, readable white labels.
    if self.Airflow then
        -- Instant repaint: the library's cross-fade driver would repaint the
        -- toggle outline with the theme stroke and undo the ON accent outline.
        local theme = {Background=shifted(-6),Surface=surface,Surface2=shifted(-2),Surface3=shifted(8),
            Stroke=shifted(26),StrokeHover=shifted(34),Accent=accent,
            AccentDark=accent:Lerp(Color3.new(0,0,0),0.35),Text=text,Muted=muted}
        local preset = self.Airflow.ThemePresets[self.Settings.AppearancePreset]
        if preset then
            theme = table.clone(preset)
            theme.Muted = preset.Muted:Lerp(preset.Text,0.25)
            self.Appearance={Surface=theme.Surface,Accent=theme.Accent,Stroke=theme.Stroke,Text=theme.Text,Muted=theme.Muted}
            surface,accent,text=theme.Surface,theme.Accent,theme.Text
        end
        self.Airflow:SetTheme(theme, true)
    end
    if self.Window then
        self.Window:SetAdaptiveSize(false) -- Do not silently shrink labels on ordinary laptop screens.
        self.Window:SetUIScale(self.Settings.UIScale/100)
        self.Window:SetWeatherMode(self.Settings.SnowArea)
        self.Window:SetWeather(self.Settings.Snow and "Snow" or "None")
    end
    -- The toggle adapter repaints ON state from the real toggle value, never hover or theme.
    if self.RefreshToggleState then self:RefreshToggleState() end
    local wasApplying=self.Applying;self.Applying=true
    for _,id in ipairs({"AppearancePreset","AccentHex","SurfaceHex"}) do
        local control=self.Controls[id]
        if control then
            if id=="AppearancePreset" then control:Set(self.Settings[id],true)
            else control:Set(hexColor(self.Settings[id]),true) end
        end
    end
    self.Applying=wasApplying
end
function C:SetAppearancePreset(name)
    assert(APPEARANCE_PRESETS[name],"Unknown appearance preset.")
    self.Settings.AppearancePreset=name
    for key,value in pairs(APPEARANCE_PRESETS[name])do self.Settings[key]=value end
    local wasApplying=self.Applying;self.Applying=true
    self:ApplyAppearance();self.Applying=wasApplying
end
-- Presentation only: retain original job reasons for diagnostics and simplify what players see.
function C:PlayerText(value)
    local text=tostring(value or "")
    local phrases={
        ["Waiting before quest interaction"]="Waiting for the next quest",
        ["Waiting before retry"]="Trying again shortly",
        ["Waiting for verified level-to-NPC binding"]="No quest found for this level yet",
        ["Waiting for level quest NPC"]="Waiting for the quest giver",
        ["Waiting for quest data"]="Checking your quest",
        ["Quest acceptance not confirmed"]="The quest has not started yet",
        ["Waiting for native input"]="Waiting for your stand",
        ["Waiting for native stand input"]="Waiting for your stand",
        ["Waiting for native summon input"]="Cannot summon this stand yet",
        ["Summon input unavailable"]="Cannot summon this stand yet",
        ["Waiting for stand input"]="Waiting for your stand",
        ["Waiting for UNDER attachment before summon"]="Getting into position",
        ["Waiting for UNDER attachment before stand input"]="Getting into position",
        ["Waiting for behind attachment"]="Getting into position",
        ["Waiting for farm attachment"]="Getting into position",
        ["Waiting for boss control"]="Getting the boss ready",
        ["Waiting for stable boss control"]="Getting the boss ready",
        ["Waiting: NPC control lost"]="Waiting for the mob to move closer",
        ["Waiting: combat owns movement"]="Paused while farming",
        ["Waiting for server clear receipt"]="Waiting for the lair reward",
        ["Waiting for own dungeon room"]="Loading your lair",
        ["Waiting for lair discovery"]="Checking available lairs",
        ["Waiting for held skill"]="Finishing the current skill",
        ["Waiting for pickup confirmation"]="Collecting item",
        ["Character collision off"]="Walk through walls enabled",
        ["Paused after profile load"]="Paused — press Resume when ready",
        ["This lair level awaits gameplay validation"]="This lair is not ready yet. Try 40+ or 100+.",
        ["Stopped: below-NPC pose does not fit; choose Original position"]="Not enough room below this NPC. Choose Original position.",
        ["Below-NPC interaction is unavailable here; choose Original position"]="Choose Original position for this NPC.",
        ["Stopped: boss ownership is unavailable"]="Could not reach the boss. Turn this off and try again.",
        ["Stopped: missing server clear receipt"]="Stopped: the lair reward did not arrive",
        ["Stopped: no server-confirmed clear within 6s"]="Stopped: the lair did not finish",
        ["Stopped: own lair room did not stream within 15s"]="Stopped: your lair did not load",
        ["Stopped: target health did not change"]="Stopped: attacks are not hitting the mob",
        ["Stopped: quest counter did not progress"]="Stopped: the quest is not progressing",
        ["Native skill list refreshed."]="Skills updated.",
        ["Native input unavailable."]="Skills are unavailable for this stand right now.",
    }
    local lines={}
    for line in (text.."\n"):gmatch("(.-)\n") do
        line=phrases[line] or line
        line=line:gsub(" | Damage [%d%.]+",""):gsub(" | Hits [%d%.]+","")
        line=line:gsub("natural NPC control","mobs to move closer"):gsub("server%-confirmed","completed")
        line=line:gsub("[Nn]ative stand input","your stand"):gsub("[Nn]ative input","stand controls")
        line=line:gsub("[Ss]erver clear receipt","lair reward"):gsub("UNDER attachment","farming position")
        line=line:gsub("client control required","some mobs may need to move closer")
        table.insert(lines,line)
    end
    return table.concat(lines,"\n")
end
local function readableAirflowSource(source)
    -- Exact, version-bound adapter patches; the cached upstream source stays untouched.
    local function replaceOnce(old,new)
        local first,last=source:find(old,1,true)
        assert(first and not source:find(old,last+1,true),"Pinned UI adapter needs an update.")
        source=source:sub(1,first-1)..new..source:sub(last+1)
    end
    replaceOnce("local am=Instance.new(aj)for an,ao in pairs(ak)",
        "local am=Instance.new(aj)if (aj=='TextLabel' or aj=='TextButton' or aj=='TextBox') and ak.TextSize then ak.TextSize=math.max(15,ak.TextSize) end for an,ao in pairs(ak)")
    replaceOnce("Row={Compact=true,Height=E and 40 or 32,DescHeight=E and 54 or 46,Chip=E and 30 or 24,Option=E and 34 or 28,TextSize=13,DescSize=12,TitleHeight=16,DescGap=17,DescLine=15,Slider=E and 54 or 46}",
        "Row={Compact=true,Height=42,DescHeight=62,Chip=30,Option=36,TextSize=15,DescSize=15,TitleHeight=20,DescGap=21,DescLine=20,Slider=62}")
    replaceOnce("local bR=bQ<O","local bR=false") -- User preference: always left/right columns.
    -- The native footer opens Home. Use account identity instead of the executor name.
    replaceOnce("local M=64","local M=76")
    replaceOnce("task.spawn(function()b2.Text=aZ()end)bY.MouseEnter",
        "self:_trackName(b2,'User')bY.MouseEnter")
    replaceOnce("Position=UDim2.new(0,48,0.5,-15),Size=UDim2.new(1,-74,0,15)",
        "Position=UDim2.new(0,48,0.5,-20),Size=UDim2.new(1,-74,0,20)")
    replaceOnce("Position=UDim2.new(0,48,0.5,1),Size=UDim2.new(1,-74,0,13)",
        "Position=UDim2.new(0,48,0.5,2),Size=UDim2.new(1,-74,0,18)")
    return source
end
local fileAPI = type(readfile) == "function" and type(writefile) == "function"
    and type(isfile) == "function" and type(isfolder) == "function"
    and type(makefolder) == "function" and type(listfiles) == "function" and type(delfile) == "function"
function C:Snapshot()
    return {Schema = 1, Hub = "BlizzardStandUpright", PlaceId = game.PlaceId, Settings = copy(self.Settings)}
end
function C:Validate(data)
    assert(type(data) == "table" and data.Schema == 1 and data.Hub == "BlizzardStandUpright"
        and data.PlaceId == 8540168650 and type(data.Settings) == "table", "Incompatible config.")
    local values = copy(self.Settings)
    for key, value in pairs(data.Settings) do
        local spec = assert(SPEC[key], "Unknown setting: " .. tostring(key))
        if spec.kind == "boolean" then assert(type(value) == "boolean", "Invalid toggle: " .. key)
        elseif spec.kind == "string" then assert(type(value)=="string" and #value<=96 and not value:find("%c"),"Invalid name: "..key)
        elseif spec.kind == "number" then
            assert(type(value) == "number" and value == value and value >= spec.min and value <= spec.max, "Invalid number: " .. key)
        elseif spec.kind == "hex" then self:ValidateAppearanceColor(value,spec.role)
        elseif spec.kind == "choice" then assert(table.find(spec.values, value), "Invalid option: " .. key)
        elseif spec.kind == "array" then
            assert(type(value) == "table" and #value <= (spec.dynamic and 64 or #spec.values), "Invalid selection: " .. key)
            local n, seen = 0, {}
            for i, selected in pairs(value) do
                local allowed = spec.dynamic and type(selected) == "string" and #selected <= 64 and selected:match("^[%w_]+$")
                if not spec.dynamic then allowed = table.find(spec.values, selected) end
                assert(type(i) == "number" and i % 1 == 0 and i >= 1 and i <= #value
                    and allowed and not seen[selected], "Invalid selection: " .. key)
                seen[selected] = true; n += 1
            end
            assert(n == #value, "Selection must be an array.")
        end
        values[key] = copy(value)
    end
    values.AutoSummon=false;values.AutoQuestFarm=false -- Ignore retired profile intent.
    return values
end
function C:Apply(data)
    local values = self:Validate(data)
    self:StopEverything()
    -- Apply is also used for snapshots; only an explicit config load starts jobs.
    self.Settings = values
    self.Applying = true
    for id, control in pairs(self.Controls) do
        if SPEC[id] then
            local value = values[id]
            if SPEC[id].kind == "array" then
                local list = {}; for _, v in ipairs(value) do list[#list+1] = v end; value = list
            end
            if id == "FarmMob" and value == "" then value = nil end
            if id == "SnowArea" then value = value == "UI" and "Window" or "Screen" end
            if id=="LairNpc"then
                local label=nil
                for display,key in pairs(self.LairByLabel or {})do if key==value then label=display;break end end
                value=label
            end
            if id=="MerchantNpc"or id=="MerchantOption"then
                local labels=id=="MerchantNpc"and self.MerchantByLabel or self.MerchantOptionByLabel
                local label;for display,key in pairs(labels or {})do if key==value then label=display;break end end
                value=label
            end
            local kind=SPEC[id].kind
            if kind=="hex" then control:Set(hexColor(value),true)
            elseif kind=="boolean" then control:Set(value==true,true)
            else control:Set(value,true) end
        end
    end
    self:ApplyAppearance()
    self.Applying = false
    if self.UpdateIdentity then self.UpdateIdentity()end
    if self.RefreshMerchantUI then self.RefreshMerchantUI()end
    for _, id in ipairs(JOB_IDS) do
        if values[id] then self.Jobs[id] = {Cancelled=true,Active=false,Reason="Paused after profile load",Ticks=0} end
    end
end
function C:ResumeConfiguredJobs()
    assert(not self.Closed,"Hub is unloaded.")
    for _, id in ipairs(JOB_IDS) do
        local job=self.Jobs[id]
        if self.Settings[id] and self.JobFactories[id] and (not job or job.Cancelled) then
            self.JobFactories[id](true)
        end
    end
    self.WebhookArmedEvents.LairComplete=self.Settings.LairWebhook==true
    self.WebhookArmedEvents.LevelUp=self.Settings.LevelWebhook==true
    self.WebhookArmed=self.Settings.LairWebhook==true or self.Settings.LevelWebhook==true
end
-- Airflow owns config storage, sharing, CRUD and autoload. This bridge only
-- supplies stable game values and applies them atomically before starting jobs.
function C:InstallNativeConfigs(window,airflow)
    self.ConfigDefaults=self:Snapshot()
    self.NativeConfigFlags={}
    local prefix="BlizzardStandUpright_"
    local types={boolean="Toggle",number="Slider",string="Input",hex="Input",choice="Dropdown",array="Dropdown"}
    for id,spec in pairs(SPEC)do
        local flag=prefix..id
        local entry={_type=assert(types[spec.kind]),_defaultEntry={Type=types[spec.kind],Value=copy(self.ConfigDefaults.Settings[id])}}
        function entry:Get()return copy(C.Settings[id])end
        airflow.Flags[flag]=entry
        self.NativeConfigFlags[flag]=entry
    end
    local function configData(flags)
        assert(not C.Closed,"Hub is unloaded.")
        assert(type(flags)=="table","Invalid config.")
        local data=copy(C.ConfigDefaults)
        local count=0
        local size
        for flag,entry in pairs(flags)do
            if flag==prefix.."WindowSize"then
                assert(type(entry)=="table"and entry.Type=="WindowSize"and type(entry.Value)=="table","Invalid window size.")
                size=entry.Value
                for _,key in ipairs({"Width","Height"})do
                    local value=size[key]
                    assert(type(value)=="number"and value==value and value>=1 and value<=10000,"Invalid window size.")
                end
            else
                local control=C.NativeConfigFlags[flag]
                assert(control and type(entry)=="table" and entry.Type==control._type,"Incompatible config setting.")
                local id=flag:sub(#prefix+1)
                data.Settings[id]=copy(entry.Value)
                -- Missing Value must fail validation, never inherit an ON setting.
                assert(entry.Value~=nil,"Missing config value: "..id)
                count+=1
            end
        end
        assert(count>0,"This config has no Stand Upright settings.")
        C:Validate(data) -- Validate everything before stopping the current jobs.
        return data,size
    end
    function window:_applyFlags(flags,silent)
        local data,size=configData(flags)
        C:Apply(data)   -- Sync every control, dropdown label and backend first.
        if size then self:SetSize(Vector2.new(size.Width,size.Height),true)end
        if silent~=true then C:ResumeConfiguredJobs()end
    end
    local nativeLoad=window.LoadConfig
    function window:LoadConfig(name,silent)
        name=name or self.ConfigName
        if not self:ConfigExists(name)then return false,"Config is unavailable."end
        local ok,loaded,err=pcall(function()
            local raw=readfile(self.ConfigFolder.."/"..name..".json")
            assert(type(raw)=="string"and #raw<=65536,"Config is too large.")
            return nativeLoad(self,name,silent)
        end)
        if not ok then return false,tostring(loaded)end
        return loaded,err
    end
    local nativeImport=window.ImportConfig
    function window:ImportConfig(code,name,allowForeignFolder)
        if type(code)~="string"or #code>65536 then return false,"Config code is too large or invalid."end
        local flags,decodeError=self:DecodeConfig(code)
        if not flags then return false,decodeError end
        local valid,validationError=pcall(configData,flags)
        if not valid then return false,tostring(validationError)end
        local ok,imported,err,importName=pcall(nativeImport,self,code,name,allowForeignFolder)
        if not ok then return false,tostring(imported)end
        return imported,err,importName
    end
    function window:ResetConfig()
        C:Apply(copy(C.ConfigDefaults))
        self._pendingFlags={}
        self:_configChanged()
        return true
    end
    window:OnConfigChanged(function()
        C.Config.Loaded=window.LoadedConfig
        C.Config.Autoload=window:GetAutoload()
    end)
end

-- Event-driven anti-idle: one owned listener, no background clicking loop,
-- no held mouse input across yields and no modification of other scripts' listeners.
function C:AntiAFKIdle(job)
    if self.Closed or job.Cancelled or self.Jobs.AntiAFK~=job
        or not self.Settings.AntiAFK or not self.JobArmed.AntiAFK then return end
    if not networkReady()then self.DisconnectReason="Game server disconnected";self:Cleanup();return end
    if UserInputService:GetFocusedTextBox()then job.Reason="Waiting while you type";return end
    local camera=workspace.CurrentCamera
    if not camera then job.Reason="Waiting for the game camera";return end
    local now=os.clock()
    if job.LastPulseAt and now-job.LastPulseAt<60 then return end
    job.LastPulseAt=now;job.Active=true
    local ok,err=pcall(function()
        local controller=game:GetService("VirtualUser")
        controller:CaptureController()
        controller:ClickButton2(Vector2.new(0,0),camera.CFrame)
    end)
    job.Active=false;job.Ticks+=1
    if ok then
        job.Pulses+=1;job.Failures=0;job.Error=nil
        job.Reason="On; idle input sent"
    else
        job.Failures+=1;job.Error=tostring(err)
        job.Reason="Anti-AFK input unavailable; waiting to retry"
        if job.Failures>=3 then
            self:StopJob("AntiAFK");self.JobArmed.AntiAFK=nil
            job.Reason="Anti-AFK unavailable; turn it off and on to retry"
            if self.Library then self.Library:Notify({Title="Anti-AFK unavailable",Description="This executor could not send the idle input.",Time=5})end
        end
    end
end
function C:StartAntiAFK()
    assert(not self.Closed,"Hub is unloaded.")
    self:StopJob("AntiAFK")
    if not self.Settings.AntiAFK then return end
    local job={Cancelled=false,Active=false,Reason="On; waiting for idle",Ticks=0,Pulses=0,Failures=0}
    self.Jobs.AntiAFK=job;self.JobArmed.AntiAFK=true
    job.IdleConnection=player.Idled:Connect(function()self:AntiAFKIdle(job)end)
end

-- Server hopping is explicit/opt-in. A request is not proof of arrival.
-- Only the two observed entry buttons are allowed; never match arbitrary "Play" text.
function C:MenuObjectVisible(object)
    if not object or not object:IsDescendantOf(player.PlayerGui)then return false end
    local node=object
    while node and node~=player.PlayerGui do
        if node:IsA("GuiObject")and not node.Visible then return false end
        if node:IsA("ScreenGui")and not node.Enabled then return false end
        node=node.Parent
    end
    return true
end
function C:MenuEntryStep(job)
    if self.Closed or job.Cancelled or not self.Settings.AutoPlay then return false,"Off"end
    local pg=player:FindFirstChild("PlayerGui")
    local loaded=player:FindFirstChild("LoadedIn")
    if not pg or not loaded or not loaded.Value then return false,"Waiting for game to load"end
    local changelog=pg:FindFirstChild("Changelogs")
    local menu=pg:FindFirstChild("MenuGUI")
    local phase,button
    if self:MenuObjectVisible(changelog)then
        phase="Close"
        local frame=changelog:FindFirstChild("Frame")
        if frame and self:MenuObjectVisible(frame)then
            button=frame:FindFirstChild("TextButton")
        end
    end
    if not phase then
        local play=menu and menu:FindFirstChild("Play")
        if self:MenuObjectVisible(menu)then
            phase="Play";button=play
        else
            job.MenuAttempt=nil
            return false,menu and "In game; waiting for the next menu"or "Waiting for the game menu"
        end
    end
    if not button or not button:IsA("TextButton")or not self:MenuObjectVisible(button)then
        return false,phase=="Close"and "Waiting for Close button"or "Waiting for Play button"
    end
    local text=button.Text:lower():match("^%s*(.-)%s*$")
    if text~=(phase=="Close"and "close"or "play")then return false,"Waiting for the game menu"end
    local attempt=job.MenuAttempt
    if not attempt or attempt.Button~=button or attempt.Phase~=phase then
        attempt={Button=button,Phase=phase,Count=0,NextAt=0};job.MenuAttempt=attempt
    end
    if attempt.Count>=3 then return false,"Menu did not respond; toggle Auto enter game off and on to retry"end
    if os.clock()<attempt.NextAt then return false,phase=="Close"and "Waiting for changelog to close"or "Waiting to enter the game"end
    -- Both real buttons bind MouseButton1Click; do not fire Activated as well.
    if type(firesignal)~="function"then return false,"This executor cannot press menu buttons"end
    attempt.Count+=1
    attempt.NextAt=os.clock()+2^(attempt.Count-1)
    local ok=pcall(firesignal,button.MouseButton1Click)
    if not ok then return false,"Menu click failed; waiting to retry"end
    self.MenuEntryStats=self.MenuEntryStats or {Close=0,Play=0}
    self.MenuEntryStats[phase]+=1
    return true,phase=="Close"and "Closing changelog"or "Pressing Play"
end
function C:OnRejoinFailure(who,placeId)
    local transition=self.Session.Transition
    if self.Closed or who~=player or placeId~=game.PlaceId or not transition or not transition.Pending then return end
    transition.Pending=false;transition.State="Failed"
    self.Session.Status="Server hop failed; toggle your features off and on to resume."
    if self.Library then self.Library:Notify({Title="Server hop failed",Description="Check Roblox, then turn your features off and on to resume.",Time=5})end
end
function C:ObserveRejoinState(state,placeId)
    local transition=self.Session.Transition
    if self.Closed or placeId~=game.PlaceId or not transition or not transition.Pending then return end
    if state==Enum.TeleportState.Failed then self:OnRejoinFailure(player,placeId)
    else
        transition.State=state.Name
        self.Session.Status="Server hop: "..state.Name..". Arrival is not yet confirmed."
    end
end
-- The game's native newStatsGUI ServerTime module reads Workspace.Age.
-- DistributedGameTime and os.clock are client/session elapsed, not server age.
function C:GetServerAge()
    local value=workspace:FindFirstChild("Age")
    if not value or not(value:IsA("NumberValue")or value:IsA("IntValue"))then return nil end
    local age=value.Value
    if type(age)~="number"or age~=age or age<0 or age==math.huge then return nil end
    return age
end
function C:FindHopServer(info)
    local cursor
    local transport=request or http_request or(http and http.request)or(syn and syn.request)
    for _=1,3 do
        if self.Closed or info.Cancelled or not networkReady()then return nil,"Search cancelled"end
        local url="https://games.roblox.com/v1/games/"..game.PlaceId.."/servers/Public?sortOrder=Asc&excludeFullGames=true&limit=100"
        if cursor then url..="&cursor="..Http:UrlEncode(cursor)end
        local ok,response=pcall(function()
            if type(transport)=="function"then return transport({Url=url,Method="GET",Timeout=10})end
            return {StatusCode=200,Body=game:HttpGet(url)}
        end)
        if self.Closed or info.Cancelled or not networkReady()then return nil,"Search cancelled"end
        if not ok or type(response)~="table"then return nil,"Cannot load the server list"end
        if tonumber(response.StatusCode or response.Status)~=200 then return nil,"Server list is unavailable; try again later"end
        if type(response.Body)~="string"or #response.Body>262144 then return nil,"Invalid server list"end
        local decoded,data=pcall(Http.JSONDecode,Http,response.Body)
        if not decoded or type(data)~="table"or type(data.data)~="table"or #data.data>100 then return nil,"Invalid server list"end
        for _,server in ipairs(data.data)do
            if type(server)=="table"and type(server.id)=="string"and #server.id==36
                and server.id:match("^[%x%-]+$")and server.id~=game.JobId
                and type(server.playing)=="number"and type(server.maxPlayers)=="number"
                and server.playing>=0 and server.playing<server.maxPlayers then
                return server.id
            end
        end
        cursor=data.nextPageCursor
        if type(cursor)~="string"or cursor==""or #cursor>1024 then break end
    end
    return nil,"No other server with space was found"
end
function C:RejoinSession(origin)
    if self.Closed or not networkReady()then return false,"Game server disconnected"end
    if game.PlaceId~=8540168650 or game.GameId~=3258251641 then return false,"Unsupported experience"end
    if origin~="manual"and origin~="timer"then return false,"Invalid server hop request"end
    if origin=="timer"then
        if not self.Settings.AutoRejoin or not self.JobArmed.AutoRejoin then return false,"Auto server hop is paused"end
        local age=self:GetServerAge()
        if not age then return false,"Waiting for server age"end
        if age<self.Settings.RejoinMinutes*60 then return false,"Server has not reached the selected age"end
    end
    local session=self.Session;local previous=session.Transition
    if previous and previous.Pending then return false,"A server hop is already pending"end
    if previous and os.clock()-previous.At<15 then return false,"Wait before requesting another hop"end
    local transition={Pending=true,State="Searching",Origin=origin,At=os.clock(),FromJob=game.JobId}
    session.Transition=transition;session.Status="Finding another server"
    -- Do not keep re-requesting while HTTP/Roblox is pending; other jobs continue
    -- until an actual destination is found, then all inputs/movement are released.
    self:StopJob("AutoRejoin");self.JobArmed.AutoRejoin=nil
    local info={Active=true,Cancelled=false,Started=os.clock()};self.Tasks.SessionTeleport=info
    info.Thread=task.spawn(function()
        local destination,reason=self:FindHopServer(info)
        if info.Cancelled or self.Closed or session.Transition~=transition then info.Active=false;return end
        if origin=="timer"and not self.Settings.AutoRejoin then
            info.Active=false;transition.Pending=false;transition.State="Cancelled";session.Status="Off";return
        end
        if not destination then
            info.Active=false;transition.Pending=false;transition.State="SearchFailed"
            session.Status=(reason or "Server search failed").."; turn Auto server hop off and on to retry"
            return
        end
        if not networkReady()or game.JobId~=transition.FromJob then info.Active=false;return end
        transition.DestinationJob=destination;transition.State="Requested"
        session.Status="Server hop requested; waiting for Roblox"
        for id in pairs(self.Jobs)do self:StopJob(id)end
        for id in pairs(self.Tasks)do if id~="SessionTeleport"then self:StopTask(id)end end
        table.clear(self.JobArmed);self:ClearWebhookQueue();self.WebhookArmed=false;table.clear(self.WebhookArmedEvents)
        self:ReleaseInputs();self:ReleaseMovement();self:ReleaseCollisions()
        local sent=pcall(TeleportService.TeleportToPlaceInstance,TeleportService,game.PlaceId,destination,player)
        if info.Cancelled or self.Closed or session.Transition~=transition then info.Active=false;return end
        info.Active=false
        if not sent then self:OnRejoinFailure(player,game.PlaceId)
        elseif transition.Pending and transition.State=="Requested"then
            transition.State="Dispatched";session.Status="Server hop dispatched; arrival is not confirmed"
        end
    end)
    return true,"Finding another server"
end
function C:PollRejoin()
    if self.Closed then return end
    local transition=self.Session.Transition
    if transition and transition.Pending and os.clock()-transition.At>45 then
        self:StopTask("SessionTeleport");transition.Pending=false;transition.State="Unconfirmed"
        self.Session.Status="No confirmed hop; no automatic retry. Check Roblox before retrying."
    end
end
function C:ServerAgeHopStep()
    local age=self:GetServerAge()
    if not age then self.Session.Status="Waiting for server age";return false,self.Session.Status end
    local remaining=math.max(0,math.ceil(self.Settings.RejoinMinutes*60-age))
    if remaining==0 then
        local queued,reason=self:RejoinSession("timer")
        if not queued then
            self.Session.Status=reason;self:StopJob("AutoRejoin");self.JobArmed.AutoRejoin=nil
        end
        return false,self.Session.Status
    end
    local text=string.format("Server age: %dh %02dm | Hop in %dh %02dm %02ds",
        math.floor(age/3600),math.floor(age/60)%60,math.floor(remaining/3600),math.floor(remaining/60)%60,remaining%60)
    self.Session.Status=text;return true,text
end
function C:StartRejoinTimer()
    assert(not self.Closed and networkReady(),"Game server disconnected.")
    self.Session.Status="Reading server age"
    self:StartJob("AutoRejoin",function()return self:ServerAgeHopStep()end,function()return 1 end)
end

-- Webhook secrets stay in this runtime only; profiles contain opt-in flags, never URLs.
function C:ClearWebhookQueue()
    self:StopTask("Webhook")
    local state=self.Webhook
    if not state then return end
    state.Generation+=1;table.clear(state.Queue)
    state.Status="Paused"
    if self.WebhookPreview then self.WebhookPreview:SetText("Preview has not been generated.")end
end
function C:SetWebhookURL(url)
    assert(type(url)=="string" and #url<=400,"Invalid webhook URL.")
    url=url:match("^%s*(.-)%s*$")
    if url~="" then
        local id,token=url:match("^https://discord%.com/api/webhooks/(%d+)/([%w_%-]+)$")
        if not id then id,token=url:match("^https://discord%.com/api/v%d+/webhooks/(%d+)/([%w_%-]+)$")end
        assert(id and #id<=22 and token and #token<=200,"Use a Discord HTTPS webhook URL without query parameters.")
    end
    if url~=self.WebhookURL then self:ClearWebhookQueue();self.WebhookURL=url end
    self.Webhook.Status=url==""and "Waiting for webhook URL"or "Ready; no message sent"
end
local function webhookText(value,limit)
    local text=tostring(value or "Unknown")
    if not utf8.len(text)then return "Invalid text"end
    text=text:gsub("[%z\1-\8\11\12\14-\31]","")
    -- Slice on a UTF-8 boundary, not in the middle of a codepoint.
    local boundary=utf8.offset(text,limit+1)
    if boundary then text=text:sub(1,boundary-1)end
    return text~=""and text or "None"
end
function C:WebhookEnabled(event)
    local kind=event.Kind or "LairComplete"
    local setting=kind=="LevelUp" and "LevelWebhook" or kind=="LairComplete" and "LairWebhook" or nil
    return setting~=nil and self.Settings[setting]==true and self.WebhookArmedEvents[kind]==true and self.WebhookArmed
end
function C:SetWebhookEventArmed(kind,value)
    assert(kind=="LairComplete" or kind=="LevelUp","Unknown webhook event.")
    self.WebhookArmedEvents[kind]=value==true
    self.WebhookArmed=self.WebhookArmedEvents.LairComplete==true or self.WebhookArmedEvents.LevelUp==true
    if not value then
        local active=self.Tasks.Webhook
        if active and active.Active and not active.Entry.Manual and (active.Entry.Event.Kind or "LairComplete")==kind then
            self.Webhook.Generation+=1;self:StopTask("Webhook")
        end
        for i=#self.Webhook.Queue,1,-1 do
            local entry=self.Webhook.Queue[i]
            if not entry.Manual and (entry.Event.Kind or "LairComplete")==kind then table.remove(self.Webhook.Queue,i)end
        end
        if #self.Webhook.Queue==0 then self.Webhook.Status=self.WebhookArmed and "Waiting for events" or "Off" end
    end
end
function C:WebhookEvent(reward,test,kind)
    local data=player:FindFirstChild("Data")
    local function val(key)local v=data and data:FindFirstChild(key);return v and v.Value or "Unknown"end
    return {Reward=webhookText(reward,500),Stand=webhookText(val("Stand"),64),
        Attribute=webhookText(val("Attri"),64),Level=webhookText(val("Level"),24),
        Kind=kind or "LairComplete",Test=test==true,Timestamp=DateTime.now():ToIsoDate()}
end
function C:ObserveWebhookLevel(value)
    local level=tonumber(value)
    if not level or level~=level or level<1 or level==math.huge or level%1~=0 then self.WebhookLastLevel=nil;return false,"No level available"end
    local previous=self.WebhookLastLevel;self.WebhookLastLevel=level
    if not previous or level<=previous then return false,"No level increase"end
    self.WebhookLevelSequence+=1
    local event=self:WebhookEvent("Level "..previous.." → "..level,false,"LevelUp")
    event.PreviousLevel=tostring(previous);event.Level=tostring(level)
    return self:EnqueueWebhook(event,game.JobId..":level:"..self.WebhookLevelSequence,false)
end
function C:PollLevelWebhook()
    local data=player:FindFirstChild("Data");local level=data and data:FindFirstChild("Level")
    self:ObserveWebhookLevel(level and level.Value)
end
function C:WebhookPayload(event)
    local hidden=self.Settings.WebhookHideName or self.Settings.HideName
    local identity=hidden and "**** / @****"or webhookText(player.DisplayName.." / @"..player.Name,96)
    return {username="Blizzard Hub",allowed_mentions={parse={}},embeds={{
        title=event.Test and "Webhook test"or event.Kind=="LevelUp" and "Level up" or "Lair complete",color=6606295,
        description=event.Test and "This is a test message. No gameplay reward is claimed."or webhookText(event.Reward,500),
        fields={{name="Player",value=identity,inline=false},
            {name="Stand",value=webhookText(event.Stand,64).." / "..webhookText(event.Attribute,64),inline=true},
            {name="Level",value=webhookText(event.Level,24),inline=true}},
        footer={text="Stand Upright: Rebooted | Blizzard Hub "..VERSION},timestamp=event.Timestamp,
    }}}
end
function C:EnqueueWebhook(event,key,manual)
    local state=self.Webhook
    if self.Closed or not networkReady()then return false,"Game server disconnected"end
    if not manual and not self:WebhookEnabled(event)then return false,"Off or paused"end
    if self.WebhookURL==""then state.Status="Waiting for webhook URL";return false,state.Status end
    if state.Seen[key]then return false,"Duplicate event"end
    if #state.Queue>=20 then state.Dropped+=1;state.Status="Queue full; event skipped";return false,state.Status end
    state.Seen[key]=true;table.insert(state.SeenOrder,key)
    if #state.SeenOrder>100 then state.Seen[table.remove(state.SeenOrder,1)]=nil end
    table.insert(state.Queue,{Event=copy(event),Key=key,Manual=manual==true,Attempts=0,Created=os.clock()})
    state.Status="Queued";return true,"Queued"
end
function C:WebhookResponse(response)
    if type(response)~="table"then return "failed","Invalid transport response"end
    local status=tonumber(response.StatusCode or response.Status)
    if status==429 then
        local delay
        if type(response.Body)=="string" and #response.Body<=8192 then
            local valid,body=pcall(Http.JSONDecode,Http,response.Body)
            if valid and type(body)=="table"then delay=tonumber(body.retry_after)end
        end
        if not delay then
            for key,value in pairs(type(response.Headers)=="table"and response.Headers or {})do
                if type(key)=="string"and key:lower()=="retry-after"then delay=tonumber(value);break end
            end
        end
        if not delay or delay~=delay or delay<0 or delay==math.huge then return "failed","Invalid rate-limit response"end
        return "rate",math.max(0.5,delay)
    end
    if status==200 and type(response.Body)=="string"and #response.Body<=65536 then
        local valid,body=pcall(Http.JSONDecode,Http,response.Body)
        if valid and type(body)=="table"and type(body.id)=="string"and body.id:match("^%d+$")then return "sent",body.id end
    end
    if status and status>=200 and status<300 then return "failed","Delivery unconfirmed; not retried"end
    return "failed",status and ("HTTP "..tostring(status).."; check webhook access")or "Transport failed; not retried"
end
function C:PumpWebhook()
    local state=self.Webhook;local active=self.Tasks.Webhook
    if self.Closed or not networkReady()then return end
    if active and active.Active then
        if os.clock()-active.Started>20 then
            self:StopTask("Webhook")
            if state.Queue[1]==active.Entry then table.remove(state.Queue,1)end
            state.Failed+=1;state.Status="Delivery timeout; not retried"
        end
        return
    end
    if #state.Queue==0 or os.clock()<state.NextAt then return end
    local entry=state.Queue[1]
    if os.clock()-entry.Created>300 or(not entry.Manual and not self:WebhookEnabled(entry.Event))then
        table.remove(state.Queue,1);state.Dropped+=1;state.Status="Expired or paused event skipped";return
    end
    local transport=request or http_request or(http and http.request)or(syn and syn.request)
    if type(transport)~="function"then
        table.remove(state.Queue,1);state.Failed+=1;state.Status="Executor HTTP request is unavailable";return
    end
    local info={Active=true,Cancelled=false,Started=os.clock(),Entry=entry}
    self.Tasks.Webhook=info
    local generation=state.Generation;local url=self.WebhookURL
    info.Thread=task.spawn(function()
        local encodedOk,body=pcall(function()return Http:JSONEncode(self:WebhookPayload(entry.Event))end)
        local valid,response=false,nil
        if encodedOk and #body<=16384 then
            entry.Attempts+=1;state.Status="Sending"
            valid,response=pcall(transport,{Url=url.."?wait=true",Method="POST",Headers={["Content-Type"]="application/json"},Body=body})
        end
        if info.Cancelled or self.Closed or state.Generation~=generation then info.Active=false;return end
        local outcome,detail
        if valid then outcome,detail=self:WebhookResponse(response)
        else outcome,detail="failed","Delivery failed or unknown; not retried"end
        state.NextAt=os.clock()+1.2
        if outcome=="rate"then
            state.NextAt=os.clock()+detail
            if entry.Attempts>=3 then
                table.remove(state.Queue,1);state.Failed+=1;state.Status="Rate-limit retry limit reached"
            else state.Status="Rate limited; waiting"end
        else
            table.remove(state.Queue,1)
            if outcome=="sent"then state.Sent+=1;state.Status="Message delivery confirmed"
            else
                state.Failed+=1;state.Status=detail
                if self.Library and os.clock()-(state.WarnAt or -math.huge)>15 then
                    state.WarnAt=os.clock();self.Library:Notify({Title="Webhook not sent",Description=detail,Time=5})
                end
            end
        end
        info.Active=false
    end)
end

local ok, failure = xpcall(function()
    connect(TeleportService.TeleportInitFailed,function(who,result,message,placeId)C:OnRejoinFailure(who,placeId)end)
    connect(player.OnTeleport,function(state,placeId)C:ObserveRejoinState(state,placeId)end)
    connect(NetworkClient.ChildRemoved,function(child)
        if child:IsA("ClientReplicator")and not networkReady()then
            C.DisconnectReason="Game server disconnected";C:Cleanup()
        end
    end)
    connect(ReplicatedStorage.Events.NpcPrompt.OnClientEvent,function(data)
        C.NpcPromptEpoch+=1
        local request=C.Interaction
        if request and not request.Job.Cancelled and type(data)=="table"and typeof(data[2])=="Instance"
            and data[2]:IsA("RemoteEvent")and data[2]:IsDescendantOf(request.Npc)then
            request.Data=data;request.Epoch=C.NpcPromptEpoch
        end
    end)
    connect(ReplicatedStorage.Events.LairStart.OnClientEvent,function(a,b,c)
        C.LairStats.Starts+=1;C.LairStats.LastStart={tostring(a),tostring(b),tostring(c)}
        C.LairStats.StartAt=os.clock()
        local job=C.Jobs.AutoLair
        if job and not job.Cancelled then
            job.RunStartedAt=C.LairStats.StartAt;job.RunClockSource="Server LairStart"
            job.InstaAt=nil;job.InstaTarget=nil;job.InstaFirstAt=nil;job.InstaAttempts=0;job.OwnershipAt=nil;job.OwnershipStableAt=nil;job.OwnershipRoot=nil;job.RoomWaitAt=nil;job.StreamAttempts=0;job.StreamAt=nil
        end
    end)
    connect(ReplicatedStorage.Events.LairClear.OnClientEvent,function(reward)
        C.LairStats.Clears+=1;C.LairStats.LastReward=tostring(reward):sub(1,500);C.LairStats.ClearAt=os.clock()
        C:ReleaseInputs("AutoLair")
        if C.LairStats.StartAt then C.LairStats.LastDuration=os.clock()-C.LairStats.StartAt end
        local job=C.Jobs.AutoLair
        if job then job.EntryAt=nil;job.EntryPending=false;job.Room=nil;job.Target=nil;job.InstaAt=nil;job.InstaTarget=nil;job.RunStartedAt=nil;job.RunClockSource=nil;job.OwnershipAt=nil;job.OwnershipStableAt=nil;job.OwnershipRoot=nil;job.InstaFirstAt=nil;job.InstaAttempts=0;job.RoomWaitAt=nil;job.StreamAttempts=0;job.StreamAt=nil end
        C.LairStats.StartAt=nil
        C:EnqueueWebhook(C:WebhookEvent(reward,false),game.JobId..":lair:"..tostring(C.LairStats.Clears),false)
    end)
    -- Pinned Airflow UI; native autoload uses the hub's validated config adapter.
    -- Keep one config UI and retain the existing typed schema and appearance.
    -- The native sidebar profile shares the Home identity/privacy controls.
    local uiSource=C.RuntimeCache.AirflowSource
    if C.RuntimeCache.AirflowRevision~=UI_REVISION or type(uiSource)~="string"then
        uiSource=game:HttpGet(UI_URL)
        assert(type(uiSource)=="string"and #uiSource>10000,"Pinned UI source is unavailable.")
        C.RuntimeCache.AirflowSource=uiSource;C.RuntimeCache.AirflowRevision=UI_REVISION
    end
    local Airflow = assert(loadstring(readableAirflowSource(uiSource)))()
    assert(type(Airflow)=="table" and type(Airflow.CreateWindow)=="function","UI library did not initialise.")
    pcall(function()Airflow:PreloadIcons()end)
    for _,name in ipairs(AIRFLOW_PRESET_NAMES) do
        local preset=assert(Airflow.ThemePresets[name],"Missing theme: "..name)
        APPEARANCE_PRESETS[name]={AccentHex=colorHex(preset.Accent),SurfaceHex=colorHex(preset.Surface)}
    end
    local window = Airflow:CreateWindow({
        Name = "BlizzardStandUprightUI", Title = "Blizzard Hub", Icon = "rbxassetid://74093118428711",
        Parent = player:WaitForChild("PlayerGui"), ToggleUIKeybind = "RightControl",
        Size = UDim2.fromOffset(920, 610), AdaptiveSize = false, UIScale = 1.1,
        MinSize = Vector2.new(880, 420), MaxSize = Vector2.new(1200, 950),
        ConfigurationSaving = {Enabled = false, FolderName = STORAGE .. "/Airflow"},
        SaveSize = "BlizzardStandUpright_WindowSize",
        Home = {Name = "Home", Title = "Blizzard Hub", Tier = false,
            Stats = {"Players", "Session", "FPS", "Ping"}, StatsFolder = STORAGE,
            Discord = "https://discord.gg/Tgjuuh8fh", Features = false},
        Profile = true, SidebarWidth = 220, ToggleButton = false, OpenButton = false,
        Backdrop = {Weather="Snow",Mode="UI",Dim=false,Tint=0,Density=0.55,Speed=0.65},
        Loading = {Enabled = false}, UnsupportedExecutor = false})
    C.Airflow = Airflow; C.Window = window; C.UI = window.Gui
    C.UI.Name = "BlizzardStandUprightUI"
    local mainFrame = window.Root
    -- Small facade so job/webhook/session messages keep one notification path.
    C.Library = {
        Unloaded = false,
        Notify = function(_, options)
            window:Notify({Title = options.Title or "Blizzard Hub", Content = C:PlayerText(options.Description or ""),
                Duration = options.Time or 4})
        end,
        Unload = function(self) self.Unloaded = true; window:Destroy() end,
    }
    local function notify(text)
        window:Notify({Title = "Blizzard Hub", Content = C:PlayerText(text), Duration = 4})
    end
    local function toggleOutline(element)
        local frame = element and element._frame
        if not frame then return nil end
        for _, child in ipairs(frame:GetChildren()) do
            if child:IsA("Frame") then
                local outline = child:FindFirstChildOfClass("UIStroke")
                if outline then return child, outline end
            end
        end
        return nil
    end
    -- ON reads as accent fill plus accent outline; Airflow owns the fill tween,
    -- so only the outline is stamped here and it follows the real toggle value.
    function C:RefreshToggleElement(element)
        local appearance = self.Appearance
        if not appearance or self.Closed then return end
        local outline = element and element._pillStroke
        if outline then outline.Color = element.Value and appearance.Accent or appearance.Stroke end
    end
    function C:RefreshToggleState()
        for _, element in ipairs(self.ToggleElements) do self:RefreshToggleElement(element) end
    end
    local function plainText(value)
        local text = tostring(value or "")
        if text:find("[<>&]") then
            text = (text:gsub("&", "&amp;")):gsub("<", "&lt;"):gsub(">", "&gt;")
        end
        return text
    end
    -- Airflow's fixed-height label clips, so all hub status text uses a wrapped
    -- paragraph row and every call site updates it with :Set().
    local function textRow(group, text)
        local handle = group:CreateParagraph({Name = "", Content = plainText(C:PlayerText(text))})
        -- Native Paragraph reserves a blank heading; remove that dead space.
        for _,child in ipairs(handle._frame:GetChildren()) do
            if child:IsA("TextLabel") and child.LayoutOrder==1 then child:Destroy() end
        end
        function handle:SetText(value) handle:Set(plainText(C:PlayerText(value))) end
        return handle
    end
    local function button(group, text, callback)
        return group:CreateButton({Name = text, Callback = function()
            local success, err = pcall(callback)
            if not success then notify(tostring(err):gsub("^.-:%d+: ", "")) end
        end})
    end
    local TAB_ICONS = {Automation = "bot", Shop = "shopping-cart", Tools = "wrench",
        Webhook = "webhook", Settings = "settings"}
    local function tab(title)
        local t = window:CreateTab({Name = title, Icon = TAB_ICONS[title]})
        C.Tabs[title] = t
        function t:Show() if window.CurrentTab ~= t then window:SelectTab(t) end end
        local function group(name, side)
            return t:CreateGroupbox({Name = name, Side = side or "Left", PopOut=false})
        end
        return t, group
    end
    local function toggle(group, id, name, callback, persistentSetting)
        C.JobFactories[id] = callback
        local control
        control = group:CreateToggle({Name = name, Default = id == "Snow" and C.Settings.Snow == true,
            Flag = "BlizzardStandUpright_" .. id, Callback = function(value)
                if C.Closed then return end
                if persistentSetting ~= false then C.Settings[id] = value end
                C:RefreshToggleElement(control)
                if not C.Applying then
                    if table.find(JOB_IDS, id) then
                        if value then C.JobArmed[id] = true else C.JobArmed[id] = nil end
                    end
                    callback(value)
                end
            end})
        C.Controls[id] = control
        local _, outline = toggleOutline(control)
        control._pillStroke = outline
        table.insert(C.ToggleElements, control)
        C:RefreshToggleElement(control)
        return control
    end
    local home = assert(window.Home, "Built-in Home is unavailable.")
    C.Tabs.Home = home
    -- Keep the native Home player card; share its privacy choice with hub profiles.
    local renderIdentity = window._renderIdentity
    function window:_renderIdentity(instant)
        renderIdentity(self, instant)
        if self._hideName then
            for _, entry in ipairs(self._identity.Names) do
                entry.Label.Text = entry.Kind == "User" and "@****" or "****"
            end
        end
    end
    local setHideName = window.SetHideName
    function window:SetHideName(hidden)
        if C.Closed then return end
        C.Settings.HideName = hidden == true
        setHideName(self, hidden)
        if C.WebhookPreview then C.WebhookPreview:SetText("Preview has not been generated.") end
    end
    C.Controls.HideName = {Set = function(_, value) window:SetHideName(value) end}
    C.UpdateIdentity = function() window:SetHideName(C.Settings.HideName) end
    C.UpdateIdentity()
    local _, automationGroup = tab("Automation")
    local levelFarm = automationGroup("Level farming")
    local levelFarmStatus = textRow(levelFarm, "Off")
    C.Controls.QuestPosition=levelFarm:CreateDropdown({Name="Take quests from",Options={"Below NPC","Original position"},
        CurrentOption="Below NPC",Callback=function(value)C.Settings.QuestPosition=value end})
    toggle(levelFarm, "AutoFarmLevel", "Auto farm level", function(value)
        if not value then C:StopJob("AutoFarmLevel");return end
        C:StartJob("AutoFarmLevel",function(job)return C:AutoFarmLevelStep(job)end,function()return .35 end)
    end)
    textRow(levelFarm, "Picks a quest for your level, defeats the mobs, then repeats. Waits underground between mobs and quests.")
    local combat = automationGroup("Stand controls")
    local nativeStatus = textRow(combat, C:StandSummary())
    C.NativeStatus = nativeStatus
    local native = C:RefreshNativeInput(true)
    C.Controls.Skills = combat:CreateDropdown({Name = "Skills", Options = native and native.Values or {},
        MultipleOptions = true, AllowNone = true, CurrentOption = {}, Callback = function(value)
            if C.Applying then return end
            local list = {}; for skill, selected in pairs(value) do if selected then table.insert(list, skill) end end
            table.sort(list)
            C.Settings.Skills = list
        end})
    C.RefreshSkillUI = function(values)
        local applying = C.Applying; C.Applying = true
        for _,id in ipairs({"Skills","LairSkills"})do if C.Controls[id]then
            local handle=C.Controls[id]
            handle:Refresh(values, true, true)
            local selected = {}; for _, skill in ipairs(C.Settings[id]) do if table.find(values, skill) then selected[#selected+1] = skill end end
            handle:Set(selected, true)
        end end
        C.Applying = applying
    end
    C.Controls.SkillDelay = combat:CreateSlider({Range = {0.3, 3},Name = "Skill interval", CurrentValue = 0.6,
          Increment = 0.1, Suffix = "s", Callback = function(value) C.Settings.SkillDelay = value end})
    toggle(combat, "AutoSkill", "Auto skill", function(value)
        if not value then C:StopJob("AutoSkill"); return end
        C:StartJob("AutoSkill", function(job)
            if not C:GetNativeInput() then return false, C.NativeReason or "Waiting for native stand input" end
            local skills = C.Settings.Skills
            if #skills == 0 then return false, "Select at least one skill" end
            local name = C.Settings.AutoFarmMob and C.Settings.FarmMob or nil
            local target
            if inLair()then
                local room=C:GetLairRoom();target=room and C:FindLairTarget(room)
                local _,_,r=alive();local tr=target and target:FindFirstChild("HumanoidRootPart")
                if not tr or (tr.Position-r.Position).Magnitude>12 then target=nil end
            else target=C:FindTarget(name,12)end
            if not target then return false, "Waiting for nearby NPC" end
            local movement=C.Movement
            local farmChosen=C.Settings.AutoFarmMob or C.Settings.AutoLair
            if farmChosen then
                if not movement or movement.Target~=target then return false,"Waiting for farm attachment"end
            else
                local attached,reason=C:AttachUnderTarget(target,job,"AutoSkill")
                if not attached then return false,reason end
                movement=C.Movement
            end
            local summoned,reason=C:EnsureCombatStand(target,movement.Owner)
            if not summoned then return false,reason end
            job.Index = (job.Index or 0) % #skills + 1
            local skill = skills[job.Index]
            return C:UseSkill(skill, target, "AutoSkill")
        end, function() return C.Settings.SkillDelay end)
    end)
    local farming = automationGroup("Mob farm", "Right")
    textRow(farming, "Farm the mob you choose below. Your stand is summoned automatically.")
    local farmStatus = textRow(farming, "Off")
    C.FarmStatus = farmStatus
    C.Controls.FarmMob = farming:CreateDropdown({Name = "Mob / quest level", Options = C:MobChoices(), AllowNone = true,
        Callback = function(value)if not C.Applying then C.Settings.FarmMob=C.MobByLabel[value]or""end end})
    C.RefreshMobUI=function()
        local applying=C.Applying;C.Applying=true
        C.Controls.FarmMob:Refresh(C:MobChoices(), true, true)
        C.Controls.FarmMob:Set(C.MobLabelByName[C.Settings.FarmMob], true)
        C.Applying=applying
    end
    C.Controls.FarmDistance = farming:CreateSlider({Range = {3, 6},Name="Distance below mob", CurrentValue=5,
        Increment = 1,Suffix=" studs",Callback=function(value)C.Settings.FarmDistance=value end})
    button(farming,"Refresh mobs",function()C.RefreshMobUI()end)
    toggle(farming,"AutoFarmMob","Auto farm mob",function(value)
        if not value then C:StopJob("AutoFarmMob");return end
        C:StartJob("AutoFarmMob",function(job)
            local lairJob=C.Jobs.AutoLair;local scan=C.Tasks.LairDiscovery
            if (lairJob and not lairJob.Cancelled)or(scan and scan.Active)or C.Interaction then
                C:ReleaseMovement("AutoFarmMob");return false,"Waiting for lair automation"
            end
            if C.Settings.FarmMob=="" then C:ReleaseMovement("AutoFarmMob");return false,"Select a mob" end
            if not C:GetNativeInput() then C:ReleaseMovement("AutoFarmMob");return false,C.NativeReason or "Waiting for native input" end
            local target = C:FindTarget(C.Settings.FarmMob)
            if not target then C:ObserveFarmDamage(job);C:ReleaseMovement("AutoFarmMob");return false,"Waiting for selected mob to spawn" end
            return C:FarmTargetStep(target,job,"AutoFarmMob")
        end,function()return 0.4 end)
    end)
    toggle(farming,"BringMob","Bring mob",function(value)
        if not value then
            C:StopJob("BringMob")
            local move=C.Movement
            if move and move.Behind then C:ReleaseMovement(move.Owner)end
            return
        end
        C:StartJob("BringMob",function(job)
            if inLair()then C:ReleaseMovement("BringMob");return false,"Bring is for world mobs; lairs stay UNDER"end
            if C.Settings.AutoFarmMob then
                if C.Movement and C.Movement.Owner=="BringMob"then C:ReleaseMovement("BringMob")end
                return false,C.BringState and("Active farm holds "..tostring(C.BringState.Count or 0).." mobs")or"Waiting for farm attachment"
            end
            if C.Settings.FarmMob==""then return false,"Select a mob above"end
            local target=C:FindTarget(C.Settings.FarmMob)
            if not target then return false,"Waiting for selected mob"end
            local attached,reason=C:AttachUnderTarget(target,job,"BringMob")
            if not attached then return false,reason end
            local summoned,summonReason=C:EnsureCombatStand(target,"BringMob")
            return summoned,summoned and reason or summonReason
        end,function()return 0.2 end)
    end)
    C.Controls.BringDepth=farming:CreateSlider({Range = {10, 60},Name="Underground depth",CurrentValue=20,Increment = 1,Suffix=" studs",
        Callback=function(value)C.Settings.BringDepth=value end})
    textRow(farming, "Bring gathers up to 6 of your chosen mobs. Enable Auto farm mob to attack them too.")
    local lairs=automationGroup("Lair")
    textRow(lairs, "Repeat lairs for rewards. Choose 40+ or 100+; other levels are not ready yet.")
    local lairStatus=textRow(lairs, "Off")
    C.Controls.LairNpc=lairs:CreateDropdown({Name="Dungeon",Options=C:LairChoices(),AllowNone=true,
        Callback=function(value)if not C.Applying then C.Settings.LairNpc=C.LairByLabel[value]or""end end})
    C.RefreshLairUI=function()
        local applying=C.Applying;C.Applying=true
        C.Controls.LairNpc:Refresh(C:LairChoices(), true, true)
        local selected=nil;for label,key in pairs(C.LairByLabel)do if key==C.Settings.LairNpc then selected=label;break end end
        C.Controls.LairNpc:Set(selected,true);C.Applying=applying
    end
    C.Controls.LairDistance=lairs:CreateSlider({Range = {6, 12},Name="Distance below boss",CurrentValue=8,Increment = 1,Suffix=" studs",
        Callback=function(value)C.Settings.LairDistance=value end})
    button(lairs,"Check available lairs",function()C:DiscoverLairs()end)
    toggle(lairs,"AutoLair","Auto lair",function(value)
        if not value then C:StopJob("AutoLair");return end
        local level=tonumber(tostring(C.Settings.LairNpc):match("^level:(%d+)$"))
        if not C.LairRepeatLevels[level]then
            C.Jobs.AutoLair={Active=false,Cancelled=true,Ticks=0,Reason="This lair level awaits gameplay validation"}
            return
        end
        C:ReleaseMovement("AutoFarmMob")
        C:StartJob("AutoLair",function(job)
            local selectedLevel=tonumber(tostring(C.Settings.LairNpc):match("^level:(%d+)$"))
            if not C.LairRepeatLevels[selectedLevel]then
                C:ReleaseInputs("AutoLair");C:ReleaseMovement("AutoLair")
                return false,"This lair level awaits gameplay validation"
            end
            local scan=C.Tasks.LairDiscovery
            if scan and scan.Active then return false,"Waiting for lair discovery"end
            if not inLair()then
                if job.InstaFirstAt then
                    if os.clock()-job.InstaFirstAt>6 then job.Cancelled=true;return false,"Stopped: missing server clear receipt"end
                    return false,"Waiting for server clear receipt"
                end
                C:ReleaseInputs("AutoLair");C:FloatUnderLair(job)
                job.Room=nil;job.Target=nil;job.RunStartedAt=nil;job.RunClockSource=nil;job.OwnershipAt=nil
                if job.EntryAt and os.clock()-job.EntryAt<8 then return false,"Waiting for lair entry"end
                if job.EntryPending then
                    job.EntryPending=false;job.EntryFailures=(job.EntryFailures or 0)+1
                    if job.EntryFailures>=3 then job.Cancelled=true;return false,"Stopped: no confirmed lair entry"end
                end
                local npc,selectionReason=C:SelectedLairNPC()
                if not npc then
                    if selectionReason then return false,selectionReason end
                    if C.Settings.LairNpc~=""and not job.DiscoveryAttempted then job.DiscoveryAttempted=true;C:DiscoverLairs()end
                    return false,C.Settings.LairNpc==""and "Select a lair level"or"Waiting for verified level-to-NPC binding"
                end
                local entered,reason=C:InteractWithLair(npc,true,job,"AutoLair")
                C.LairStats.LastEntryReason=reason
                if not entered then job.EntryAt=os.clock();job.EntryFailures=(job.EntryFailures or 0)+1 end
                if (job.EntryFailures or 0)>=3 then job.Cancelled=true;return false,"Stopped: lair entry failed repeatedly"end
                if not entered then return false,reason end
            end
            job.EntryFailures=0;job.EntryPending=false
            job.Room=job.Room and job.Room.Model.Parent and job.Room or C:GetLairRoom()
            if not job.Room then
                job.RoomWaitAt=job.RoomWaitAt or os.clock()
                if job.LastServerPosition then C:RequestLairStream(job,job.LastServerPosition)end
                if os.clock()-job.RoomWaitAt>15 then job.Cancelled=true;return false,"Stopped: own lair room did not stream within 15s"end
                return false,"Waiting for own dungeon room"
            end
            job.RoomWaitAt=nil
            if job.InstaAt then return C:TryLairInstantKill(job.InstaTarget,job)end
            local target=C:FindLairTarget(job.Room)
            if not target then C:FloatUnderLair(job);return false,"Floating below: waiting for boss"end
            local attached,reason=C:AttachUnderTarget(target,job,"AutoLair")
            if not attached then return false,reason end
            local summoned,summonReason=C:EnsureCombatStand(target,"AutoLair")
            if not summoned then return false,summonReason end
            return C:TryLairInstantKill(target,job)
        end,function()return 0.05 end)
    end)
    local _, shopGroup=tab("Shop")
    local merchant=shopGroup("Regular merchants")
    textRow(merchant, "View a merchant's items without buying anything. Auto-buy is not available yet.")
    local merchantStatus=textRow(merchant, "Select a merchant and preview its catalogue.")
    C.Controls.MerchantNpc=merchant:CreateDropdown({
        Name="Merchant NPC",Options=C:MerchantChoices(),AllowNone=true,
        Callback=function(value)
            if C.Applying then return end
            C:StopTask("MerchantPreview")
            C.Settings.MerchantNpc=C.MerchantByLabel[value]or"";C.Settings.MerchantOption=""
            if C.RefreshMerchantUI then C.RefreshMerchantUI()end
        end})
    C.Controls.MerchantOption=merchant:CreateDropdown({
        Name="Item",Options=C:MerchantOptionChoices(),AllowNone=true,
        Callback=function(value)if not C.Applying then C.Settings.MerchantOption=C.MerchantOptionByLabel[value]or""end end})
    C.RefreshMerchantUI=function()
        local wasApplying=C.Applying;C.Applying=true
        C.Controls.MerchantNpc:Refresh(C:MerchantChoices(), true, true)
        local selected
        for label,key in pairs(C.MerchantByLabel)do if key==C.Settings.MerchantNpc then selected=label;break end end
        C.Controls.MerchantNpc:Set(selected, true)
        C.Controls.MerchantOption:Refresh(C:MerchantOptionChoices(), true, true);selected=nil
        for label,key in pairs(C.MerchantOptionByLabel)do if key==C.Settings.MerchantOption then selected=label;break end end
        C.Controls.MerchantOption:Set(selected, true);C.Applying=wasApplying
    end
    button(merchant,"Refresh merchants",function()C.RefreshMerchantUI()end)
    button(merchant,"Visit merchant and view items",function()C:StartMerchantPreview()end)
    button(merchant,"Stop preview",function()C:StopTask("MerchantPreview");notify("Merchant preview stopped.")end)
    textRow(merchant, "Returns you after the preview. Stock trading is not available yet.")
    local _, toolsGroup = tab("Tools")
    local safety = toolsGroup("Safety and display")
    toggle(safety,"AntiAFK","Anti-AFK",function(value)
        if not value then C:StopJob("AntiAFK");return end
        C:StartAntiAFK()
    end)
    textRow(safety,"Helps prevent idle disconnects. Requires executor support; it cannot prevent server shutdowns or connection loss.")
    local antiAFKStatus=textRow(safety,"Off")
    local sessionGroup=toolsGroup("Session","Right")
    textRow(sessionGroup,"Close the changelog, then press Play when the game menu appears.")
    toggle(sessionGroup,"AutoPlay","Auto enter game",function(value)
        if not value then C:StopJob("AutoPlay");return end
        C:StartJob("AutoPlay",function(job)return C:MenuEntryStep(job)end,function()return 0.3 end)
    end)
    local menuEntryStatus=textRow(sessionGroup,"Off")
    textRow(sessionGroup, "Hop to another server when this server reaches the age you choose. Missing server age pauses the timer. The next server may not be younger.")
    local sessionStatus=textRow(sessionGroup, "Off")
    C.Controls.RejoinMinutes=sessionGroup:CreateSlider({Range = {1, 1440},
        Name="Hop at server age",CurrentValue=120,Increment = 1,Suffix=" min",
        Callback=function(value)
            C.Settings.RejoinMinutes=value
        end})
    toggle(sessionGroup,"AutoRejoin","Auto server hop",function(value)
        if value then C:StartRejoinTimer()
        else
            C:StopJob("AutoRejoin");C.JobArmed.AutoRejoin=nil
            local transition=C.Session.Transition
            if transition and transition.Pending and transition.Origin=="timer"and transition.State=="Searching"then
                C:StopTask("SessionTeleport");transition.Pending=false;transition.State="Cancelled"
            end
            if not C.Session.Transition or not C.Session.Transition.Pending then C.Session.Status="Off"end
        end
    end)
    local rejoinConfirmAt
    button(sessionGroup,"Server hop now (click twice)",function()
        if not rejoinConfirmAt or os.clock()-rejoinConfirmAt>5 then
            rejoinConfirmAt=os.clock();notify("Click again within 5 seconds to move to a different server.");return
        end
        rejoinConfirmAt=nil;local queued,reason=C:RejoinSession("manual");assert(queued,reason);notify(reason)
    end)
    toggle(safety,"Noclip","Noclip",function(value)
        if not value then C:StopJob("Noclip");return end
        C:StartJob("Noclip",function()
            local character=alive()
            C:AcquireCollisions("Noclip",character)
            return true,"Character collision off"
        end,function()return 0.25 end)
    end)
    textRow(safety, "Walk through walls. Normal movement returns when this and farming are off. Still being tested.")
    local noclipStatus=textRow(safety, "Off")
    local mobility=toolsGroup("Movement")
    toggle(mobility,"Fly","Fly",function(value)
        if not value then C:StopJob("Fly");return end
        C:StartJob("Fly",function(job)return C:FlyStep(job)end,function()return 0.2 end)
    end)
    C.Controls.FlySpeed=mobility:CreateSlider({Range = {10, 120},Name="Fly speed",CurrentValue=45,Increment = 1,Suffix=" studs/s",
        Callback=function(value)C.Settings.FlySpeed=value end})
    textRow(mobility, "WASD to fly. Space/E goes up, Ctrl/Q goes down. Pauses while farming.")
    button(mobility,"Rise",function()if C.Settings.Fly then C.FlyVertical=1 end end)
    button(mobility,"Descend",function()if C.Settings.Fly then C.FlyVertical=-1 end end)
    button(mobility,"Level flight",function()C.FlyVertical=0 end)
    toggle(mobility,"SpeedBoost","Speed boost",function(value)
        if not value then C:StopJob("SpeedBoost");return end
        C:StartJob("SpeedBoost",function()
            local _,humanoid=alive();local state=C.SpeedState
            if not state or state.Humanoid~=humanoid then C:ReleaseSpeed();state={Humanoid=humanoid,Original=humanoid.WalkSpeed};C.SpeedState=state end
            state.Applied=C.Settings.WalkSpeed;humanoid.WalkSpeed=state.Applied
            return true,"Walk speed "..tostring(state.Applied)
        end,function()return 0.2 end)
    end)
    C.Controls.WalkSpeed=mobility:CreateSlider({Range = {16, 100},Name="Walk speed",CurrentValue=32,Increment = 1,Suffix=" studs/s",
        Callback=function(value)C.Settings.WalkSpeed=value end})
    local mobilityStatus=textRow(mobility, "Off")
    local pickup=toolsGroup("Item pickup","Right")
    textRow(pickup, "Pick up nearby items without using them. Still being tested.")
    local pickupStatus=textRow(pickup, "Off")
    C.Controls.PickupRadius=pickup:CreateSlider({Range = {25, 3000},Name="Pickup radius",CurrentValue=1500,Increment = 1,Suffix=" studs",
        Callback=function(value)C.Settings.PickupRadius=value end})
    C.Controls.PickupInterval=pickup:CreateSlider({Range = {0.5, 5},Name="Pickup interval",CurrentValue=0.8,Increment = 0.1,Suffix="s",
        Callback=function(value)C.Settings.PickupInterval=value end})
    toggle(pickup,"AutoPickup","Auto pick up item",function(value)
        if not value then C:StopJob("AutoPickup");return end
        C:StartJob("AutoPickup",function(job)
            local farmingJob=C.Jobs.AutoFarmMob;local lairJob=C.Jobs.AutoLair;local scan=C.Tasks.LairDiscovery
            if inLair()or(farmingJob and not farmingJob.Cancelled)or(lairJob and not lairJob.Cancelled)
                or(scan and scan.Active)or C.Interaction then
                C:ReleaseMovement("AutoPickup");return false,"Waiting for combat or dungeon to finish"
            end
            local gui=player.PlayerGui:FindFirstChild("newPromptGUI")
            if gui and gui:GetAttribute("ItemPromptActive")then return false,"Waiting for item-use dialog to close"end
            local candidate=C:PickupCandidate()
            if not candidate then return false,"Waiting for world items"end
            return C:TryPickup(candidate,job)
        end,function()return C.Settings.PickupInterval end)
    end)
    toggle(safety, "AntiVoid", "Anti void", function(value)
        C.LastSafe = nil
        if not value then C:StopJob("AntiVoid"); return end
        C:StartJob("AntiVoid", function()
            local character, _, root = alive()
            local params = RaycastParams.new(); params.FilterType = Enum.RaycastFilterType.Exclude
            params.FilterDescendantsInstances = {character, workspace:FindFirstChild("Living") or character}
            local hit = workspace:Raycast(root.Position, Vector3.new(0,-8,0), params)
            if hit and hit.Normal.Y > 0.6 and root.AssemblyLinearVelocity.Magnitude < 100 then
                C.LastSafe = {Character = character, Position = root.CFrame, At = os.clock()}
            end
            if root.Position.Y < workspace.FallenPartsDestroyHeight + 50 then
                local safe = C.LastSafe
                if safe and safe.Character == character and os.clock() - safe.At < 60 then
                    character:PivotTo(safe.Position); root.AssemblyLinearVelocity = Vector3.zero
                    return true, "Recovered from void"
                end
                return false, "Waiting for safe ground"
            end
            return true, "Watching for falls"
        end, function() return 0.2 end)
    end)
    local screen = Instance.new("Frame")
    screen.Name = "BlizzardStandUprightScreen"; screen.Size = UDim2.fromScale(1,1)
    screen.BorderSizePixel = 0; screen.ZIndex = 0; screen.Visible = false; screen.Active = false
    screen.Parent = C.UI; C.ScreenOverlay = screen
    C.Controls.Screen = safety:CreateDropdown({Name = "Screen overlay", Options = {"Off","Black","White"}, CurrentOption = "Off",
        Callback = function(value)
            C.Settings.Screen = value; screen.Visible = value ~= "Off"
            screen.BackgroundColor3 = value == "White" and Color3.new(1,1,1) or Color3.new(0,0,0)
        end})
    button(combat, "Refresh skills", function()
        C:ReleaseInputs(); local refreshed = C:RefreshNativeInput(true)
        assert(refreshed, C.NativeReason or "Native input unavailable.")
        notify("Native skill list refreshed.")
    end)
    local _, webhookGroup=tab("Webhook")
    local destination=webhookGroup("Destination")
    textRow(destination, "Send rewards to Discord. Your link is not saved, and messages never ping anyone.")
    local pendingURL=""
    local urlInput=destination:CreateInput({
        Name="Discord webhook URL",CurrentValue="",Callback=function(value)pendingURL=value end})
    button(destination,"Apply URL",function()
        C:SetWebhookURL(pendingURL);pendingURL="";urlInput:Set("", true)
        notify("Webhook URL set for this session only.")
    end)
    button(destination,"Clear URL and queue",function()
        C:SetWebhookURL("");pendingURL="";urlInput:Set("", true);notify("Webhook URL and queue cleared.")
    end)
    toggle(destination,"WebhookHideName","Hide name in webhooks",function()
        if C.WebhookPreview then C.WebhookPreview:SetText("Preview has not been generated.")end
    end)
    C.Controls.WebhookHideName:Set(true, true)
    toggle(destination,"LairWebhook","Lair complete",function(value)C:SetWebhookEventArmed("LairComplete",value)end)
    toggle(destination,"LevelWebhook","Level up",function(value)
        C:PollLevelWebhook();C:SetWebhookEventArmed("LevelUp",value)
    end)
    textRow(destination, "Choose when to send a message. Both options can be on together. Discord delivery is still being tested.")
    local webhookStatus=textRow(destination, "Off")
    local preview=textRow(destination, "Preview has not been generated.")
    C.WebhookPreview=preview
    button(destination,"Preview (no delivery)",function()
        local kind=C.Settings.LevelWebhook and not C.Settings.LairWebhook and "LevelUp" or "LairComplete"
        local payload=C:WebhookPayload(C:WebhookEvent("Preview only",true,kind));local embed=payload.embeds[1]
        preview:SetText(embed.title.."\n"..embed.fields[1].value.."\n"..embed.fields[2].value.." | Level "..embed.fields[3].value)
    end)
    local testConfirmAt
    button(destination,"Send test (click twice)",function()
        assert(C.WebhookURL~="","Set the webhook URL first.")
        if not testConfirmAt or os.clock()-testConfirmAt>5 then
            testConfirmAt=os.clock();notify("Click again within 5 seconds to send one test message.");return
        end
        testConfirmAt=nil
        local queued,reason=C:EnqueueWebhook(C:WebhookEvent("Test only",true),"manual:"..Http:GenerateGUID(false),true)
        assert(queued,reason);notify("Test message queued; delivery is not yet confirmed.")
    end)
    local _, settingsGroup = tab("Settings")
    local about = settingsGroup("Your session")
    local status = textRow(about, "Loading current game state...")
    textRow(about, "Some features are still being tested. Turn off a feature if it gets stuck.")
    button(about, "Stop Everything", function() C:StopEverything(); notify("All Blizzard Hub jobs stopped.") end)
    local appearance=settingsGroup("Appearance","Right")
    C.Controls.AppearancePreset=appearance:CreateDropdown({
        Name="Theme",Options=appearanceNames,CurrentOption="Blizzard",
        Callback=function(value)
            if C.Applying then return end
            if value=="Custom" then C.Settings.AppearancePreset=value
            else C:SetAppearancePreset(value) end
        end})
    local function appearancePicker(id,text,role)
        C.Controls[id]=appearance:CreateColorPicker({
            Name=text,Color=hexColor(C.Settings[id]),
            Callback=function(value)
                if C.Applying then return end
                local hex=colorHex(value)
                local valid,err=pcall(function()C:ValidateAppearanceColor(hex,role)end)
                if valid then C.Settings[id]=hex;C.Settings.AppearancePreset="Custom"
                else
                    if not C.AppearanceWarningAt or os.clock()-C.AppearanceWarningAt>4 then
                        C.AppearanceWarningAt=os.clock();notify(tostring(err):match("[^:]+$") or "Invalid color.")
                    end
                end
                C:ApplyAppearance()
            end})
    end
    appearancePicker("AccentHex","Accent color","accent")
    appearancePicker("SurfaceHex","Dark surface","surface")
    C.Controls.UIScale=appearance:CreateSlider({Name="Interface size",Range={80,140},CurrentValue=110,Increment=5,Suffix="%",
        Callback=function(value)C.Settings.UIScale=value;if not C.Applying then window:SetUIScale(value/100) end end})
    toggle(appearance,"Snow","Falling snow",function(value)window:SetWeather(value and "Snow" or "None")end)
    C.Controls.SnowArea=appearance:CreateDropdown({Name="Snow area",Options={"Window","Screen"},CurrentOption="Window",
        Callback=function(value)C.Settings.SnowArea=value=="Window" and "UI" or "Screen";window:SetWeatherMode(C.Settings.SnowArea)end})
    textRow(appearance, "Theme, size and snow are saved with your config. Snow hides when the hub is closed.")
    button(appearance,"Reset appearance",function()C:SetAppearancePreset("Blizzard");notify("Appearance reset.")end)
    C:InstallNativeConfigs(window,Airflow)
    local configs=settingsGroup("Configs")
    textRow(configs,"Save your setup, then Set autoload. Saved ON features start when the hub opens.")
    C.ConfigManager=configs:CreateConfigManager({Name="Configs"})
    if not fileAPI then textRow(configs,"Executor file storage is unavailable.")end
    local layout = settingsGroup("Layout", "Right")
    local defaultPosition = mainFrame.Position
    button(layout, "Reset Layout", function()
        mainFrame.Position = defaultPosition
        window:ResetIslandPosition()
        notify("Layout reset.")
    end)
    button(layout, "Unload", function() C:Cleanup() end)
    -- Airflow keeps the window clamped on screen; the header and Reset Layout stay reachable.
    -- Complete reference inventory retained; these handlers are not yet implemented/verified.
    local pending = {
        {"Automation", "Quest gameplay QC and NPC accept/decline/claim loop; mob bring/reset; boss bring/legit positioning; selected bosses; Miasma HP threshold"},
        {"Roll", "Auto roll; 2x orb; storage; safe zone; stand/attribute/Kars modes; arrow/Rokakaka selection; delay; target stands/attributes; blacklist; specific stand-attribute pairs"},
        {"Lair", "All-difficulty gameplay QC; instant kill and delay; webhook delivery QC"},
        {"Shop", "Merchant preview gameplay QC; regular auto buy; stock item/amount; auto buy/sell; sell-at price"},
        {"Tools", "Pickup gameplay QC; open storage; anti time stop; anti ragdoll; infinite Hamon; server-hop destination age selection; genuine hop arrival QC; reset timer/manual"},
        {"Webhook", "Roll events and target-only/all mode; genuine Discord delivery QC"},
        {"Settings", "Appearance runtime QC; Auto Execute"},
    }
    local coverage = textRow(about, "")
    local lines = {}
    for _, row in ipairs(pending) do
        table.insert(lines, row[1] .. ": " .. row[2])
        C.Features[row[1]] = {Implemented = false, Verified = false, Remaining = row[2]}
    end
    coverage:SetText("Coming later: auto-buy, stock trading, rolling and Auto Execute.")
    connect(player.CharacterRemoving, function(character)
        C:OnCharacterLost(character)
    end)
    connect(player.CharacterAdded, function(character)
        local humanoid = character:WaitForChild("Humanoid", 10)
        if C.Closed or player.Character~=character then return end
        C.NativeInput = nil; C.NativeRetryAt = 0
        if humanoid then connect(humanoid.Died, function() C:OnCharacterLost(character) end) end
        C:ResumeCharacterJobs(character)
    end)
    local character, humanoid = alive()
    if character then connect(humanoid.Died, function() C:OnCharacterLost(character) end) end
    connect(RunService.Stepped,function()C:MaintainCollisions()end)
    connect(Players.PlayerRemoving, function(leaving) if leaving == player then C:Cleanup() end end)
    local elapsed = 0
    connect(RunService.Heartbeat, function(dt)
        elapsed += dt; if elapsed < 0.5 or C.Closed then return end; elapsed = 0
        if not networkReady()then C.DisconnectReason="Game server disconnected";C:Cleanup();return end
        local data = player:FindFirstChild("Data")
        local function val(key) local v = data and data:FindFirstChild(key); return v and tostring(v.Value) or "Unknown" end
        status:SetText("Stand Upright: Rebooted\nv" .. VERSION .. " | Level " .. val("Level") .. "\n" .. standName() .. " / " .. val("Attri"))
        local native = C:GetNativeInput()
        nativeStatus:SetText(C:StandSummary())
        local levelJob=C.Jobs.AutoFarmLevel
        levelFarmStatus:SetText((levelJob and levelJob.Reason or "Off").."\nQuests completed: "..C.LevelFarmStats.Completed)
        local noclipJob=C.Jobs.Noclip
        noclipStatus:SetText(noclipJob and noclipJob.Reason or "Off")
        local flyJob=C.Jobs.Fly;local speedJob=C.Jobs.SpeedBoost
        mobilityStatus:SetText("Fly: "..(flyJob and flyJob.Reason or "Off").."\nSpeed: "..(speedJob and speedJob.Reason or "Off"))
        C:PollRejoin()
        local idleJob=C.Jobs.AntiAFK
        antiAFKStatus:SetText(idleJob and idleJob.Reason or "Off")
        local entryJob=C.Jobs.AutoPlay
        menuEntryStatus:SetText(entryJob and entryJob.Reason or "Off")
        local sessionText=C.Session.Status
        if C.Settings.AutoRejoin and not C.JobArmed.AutoRejoin and not C.Session.Transition then sessionText="Auto server hop paused; turn it off and on to retry"end
        sessionStatus:SetText(sessionText)
        local merchantTask=C.Tasks.MerchantPreview
        merchantStatus:SetText(merchantTask and(merchantTask.Cancelled and "Preview stopped"or merchantTask.Reason)or "Select a merchant and preview its catalogue.")
        local job=C.Jobs.AutoFarmMob
        farmStatus:SetText(job and job.Reason or "Off")
        local lairJob=C.Jobs.AutoLair;local scan=C.Tasks.LairDiscovery
        local description=lairJob and lairJob.Reason or"Off"
        if scan and scan.Active then description=scan.Reason end
        if C.LairStats.LastReward then description..="\nLast clear: "..C.LairStats.LastReward end
        if C.LairStats.LastDuration then description..=string.format("\nLast server-confirmed run: %.2fs",C.LairStats.LastDuration)end
        lairStatus:SetText(description)
        local pickupJob=C.Jobs.AutoPickup
        local pickupDescription=pickupJob and pickupJob.Reason or"Off"
        if C.PickupStats.LastGains then
            local entries={};for name,count in pairs(C.PickupStats.LastGains)do table.insert(entries,name.." +"..tostring(count))end
            table.sort(entries);pickupDescription..="\nLast pickup: "..table.concat(entries,", ")
        end
        pickupStatus:SetText(pickupDescription)
        C:PollLevelWebhook();C:PumpWebhook()
        local ws=C.Webhook
        local chosen=C.Settings.LairWebhook or C.Settings.LevelWebhook
        local webhookReason=chosen and(C.WebhookArmed and ws.Status or "Paused; use Resume")or ws.Status
        webhookStatus:SetText(webhookReason.."\nQueue "..#ws.Queue.." | Sent "..ws.Sent.." | Failed "..ws.Failed)
    end)
    C:ApplyAppearance()
    window:SelectTab(home); C.Ready = true;bootReceipt.State="Ready"
    if fileAPI then
        local autoloadOk,autoloadError=pcall(function()
            local name=window:GetAutoload()
            C.Config.Autoload=name
            if name then
                local loaded,err=window:LoadAutoload()
                if not loaded then C.Config.AutoloadError=tostring(err)end
            end
        end)
        if not autoloadOk then
            C.Config.AutoloadError=tostring(autoloadError)
            notify("Autoload could not be read. Check your saved config.")
        end
    end
end, debug.traceback)
if not ok then bootReceipt.State="Failed";C.BootError = failure; C:Cleanup(); error(failure) end
return C
