--[[
    SKIN COPIER  |  Roblox (Delta / Android)  |  v1.6

    O QUE FAZ
      - Pesquisa qualquer usuário pelo nome (online, offline ou em outro servidor)
      - Mostra miniatura e prévia do avatar público
      - Transforma seu personagem no avatar alvo (corpo, partes especiais, acessórios,
        layered clothing, roupas, rosto, cores), com plano B via HumanoidDescription
      - Copia animações (Idle, Walk, Run, Jump, Fall, Climb, Swim) com validação
      - Restaura a aparência/animações originais
      - Notificações com o resultado REAL de cada operação

    ATALHO
      Digite o nome de usuário e toque em "Copiar aparência completa" (ou aperte
      Enter): pesquisa e transforma o seu personagem em um passo só.

    SKINS SALVAS
      "Salvar skin do alvo" guarda os itens do avatar num arquivo (pasta SkinCopier do
      executor). Se o dono mudar a skin depois, a sua cópia continua igual. Toque no
      nome na lista para vestir.

    SOCO VISUAL
      Liga/desliga o botão "Soco visual a cada clique". Cada clique do mouse toca uma
      animação de golpe no seu personagem (só local, não aciona nada do jogo). Pode
      colar o ID de outra animação de soco no campo abaixo do botão.

    COMO USAR
      1) Suba este arquivo para um repositório GitHub.
      2) Abra o arquivo > botão "Raw" > copie o link.
      3) No Delta, execute:
           loadstring(game:HttpGet("COLE_AQUI_O_LINK_RAW"))()

    LIMITAÇÕES (leia)
      - As mudanças são LOCAIS (client-side): normalmente só você vê, e o jogo/servidor
        pode reverter a qualquer momento. Ao morrer/respawnar, volta ao normal.
      - Animações públicas são de personagens R15. Em personagens R6 elas não funcionam
        e o script avisa em vez de fingir que aplicou.
      - Animações só são aplicadas se o jogo usar o script padrão "Animate".
      - Animação "Land" não faz parte dos dados públicos do avatar: sem suporte.
      - Nenhuma garantia contra punições/banimentos. Use por sua conta e risco.
]]

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local LP = Players.LocalPlayer
local env = (getgenv and getgenv()) or _G

-- Evita abrir duas vezes
if env.__SkinCopier then
	pcall(function() env.__SkinCopier.Destroy() end)
end

------------------------------------------------------------------------
-- ESTADO
------------------------------------------------------------------------
local State = {
	userId = nil,
	name = nil,
	desc = nil,            -- HumanoidDescription do alvo (cache)
	busy = false,
	originalDesc = nil,    -- aparência antes da 1ª alteração
	animSnapshot = nil,    -- {char=..., entries={{inst=..., id=...}}}
	changed = false,
	morph = nil,           -- transformação ativa
	morphDesc = nil,
	morphName = nil,
	autoMorph = false,     -- reaplicar ao renascer
}
local conns = {}

------------------------------------------------------------------------
-- TEMA
------------------------------------------------------------------------
local C = {
	bg = Color3.fromRGB(22, 24, 31),
	header = Color3.fromRGB(32, 35, 46),
	field = Color3.fromRGB(40, 44, 57),
	text = Color3.fromRGB(235, 237, 245),
	sub = Color3.fromRGB(150, 156, 175),
	accent = Color3.fromRGB(88, 101, 242),
	green = Color3.fromRGB(67, 181, 129),
	red = Color3.fromRGB(237, 66, 69),
	yellow = Color3.fromRGB(250, 166, 26),
	gray = Color3.fromRGB(62, 67, 84),
}
local KIND = { ok = C.green, err = C.red, warn = C.yellow, info = C.accent }

local function corner(inst, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 8)
	c.Parent = inst
	return c
end

local function pad(inst, p)
	local u = Instance.new("UIPadding")
	u.PaddingTop, u.PaddingBottom = UDim.new(0, p), UDim.new(0, p)
	u.PaddingLeft, u.PaddingRight = UDim.new(0, p), UDim.new(0, p)
	u.Parent = inst
end

------------------------------------------------------------------------
-- GUI BASE
------------------------------------------------------------------------
local function resolveParent()
	if typeof(gethui) == "function" then
		local ok, r = pcall(gethui)
		if ok and r then return r end
	end
	local ok = pcall(function()
		local f = Instance.new("Folder")
		f.Parent = game:GetService("CoreGui")
		f:Destroy()
	end)
	if ok then return game:GetService("CoreGui") end
	return LP:WaitForChild("PlayerGui")
end

local gui = Instance.new("ScreenGui")
gui.Name = "SkinCopier_" .. tostring(math.random(1000, 9999))
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 999
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function()
	if syn and syn.protect_gui then syn.protect_gui(gui) end
end)
gui.Parent = resolveParent()

-- Notificações (toasts)
local toastHolder = Instance.new("Frame")
toastHolder.BackgroundTransparency = 1
toastHolder.Size = UDim2.new(0, 280, 0, 10)
toastHolder.Position = UDim2.new(0.5, -140, 0, 8)
toastHolder.ZIndex = 50
toastHolder.Parent = gui
do
	local l = Instance.new("UIListLayout")
	l.Padding = UDim.new(0, 5)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = toastHolder
end

local function notify(kind, msg)
	print("[SkinCopier] " .. tostring(msg))
	if not (toastHolder and toastHolder.Parent) then return end

	local n = 0
	for _, ch in ipairs(toastHolder:GetChildren()) do
		if ch:IsA("TextLabel") then
			n += 1
			if n >= 4 then ch:Destroy() end
		end
	end

	local color = KIND[kind] or KIND.info
	local t = Instance.new("TextLabel")
	t.BackgroundColor3 = C.header
	t.AutomaticSize = Enum.AutomaticSize.Y
	t.Size = UDim2.new(1, 0, 0, 0)
	t.Text = tostring(msg)
	t.TextWrapped = true
	t.TextColor3 = C.text
	t.Font = Enum.Font.Gotham
	t.TextSize = 13
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.ZIndex = 51
	corner(t, 8)
	pad(t, 8)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = 1.5
	s.Parent = t
	t.Parent = toastHolder

	task.delay(4.5, function()
		if t and t.Parent then
			TweenService:Create(t, TweenInfo.new(0.3), { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
			TweenService:Create(s, TweenInfo.new(0.3), { Transparency = 1 }):Play()
			task.wait(0.35)
			if t then t:Destroy() end
		end
	end)
end

-- Arrastar (mouse e toque)
local function makeDraggable(handle, target)
	local dragging, dragInput, dragStart, startPos = false, nil, nil, nil
	local moved = false
	handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging, moved = true, false
			dragStart, startPos = input.Position, target.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then dragging = false end
			end)
		end
	end)
	handle.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then
			dragInput = input
		end
	end)
	table.insert(conns, UIS.InputChanged:Connect(function(input)
		if dragging and input == dragInput then
			local d = input.Position - dragStart
			if d.Magnitude > 8 then moved = true end
			target.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + d.X,
				startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end))
	return function() return moved end
end

-- Painel
local cam = workspace.CurrentCamera
local vp = cam and cam.ViewportSize or Vector2.new(800, 400)
local W = math.clamp(vp.X - 30, 250, 320)
local H = math.clamp(vp.Y - 30, 230, 400)

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Size = UDim2.fromOffset(W, H)
panel.Position = UDim2.new(0.5, -W / 2, 0.5, -H / 2)
panel.BackgroundColor3 = C.bg
panel.BorderSizePixel = 0
panel.Parent = gui
corner(panel, 12)
do
	local s = Instance.new("UIStroke")
	s.Color = C.gray
	s.Thickness = 1
	s.Parent = panel
end

local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 38)
header.BackgroundColor3 = C.header
header.BorderSizePixel = 0
header.Parent = panel
corner(header, 12)

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.new(0, 12, 0, 0)
title.Size = UDim2.new(1, -90, 1, 0)
title.Text = "Skin Copier"
title.TextColor3 = C.text
title.Font = Enum.Font.GothamBold
title.TextSize = 16
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = header

local function headerButton(text, color, xOffset)
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(30, 26)
	b.Position = UDim2.new(1, xOffset, 0.5, -13)
	b.BackgroundColor3 = color
	b.Text = text
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 15
	b.AutoButtonColor = true
	b.Parent = header
	corner(b, 7)
	return b
end
local btnMin = headerButton("-", C.gray, -70)
local btnClose = headerButton("X", C.red, -36)

local dragPanel = makeDraggable(header, panel)

local scroll = Instance.new("ScrollingFrame")
scroll.Position = UDim2.new(0, 0, 0, 42)
scroll.Size = UDim2.new(1, 0, 1, -42)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 4
scroll.CanvasSize = UDim2.new()
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.Parent = panel
pad(scroll, 8)
do
	local l = Instance.new("UIListLayout")
	l.Padding = UDim.new(0, 7)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = scroll
end

local order = 0
local function nextOrder() order += 1 return order end

-- Campo de usuário
local input = Instance.new("TextBox")
input.Size = UDim2.new(1, 0, 0, 40)
input.BackgroundColor3 = C.field
input.PlaceholderText = "Nome de usuário do Roblox"
input.PlaceholderColor3 = C.sub
input.Text = ""
input.TextColor3 = C.text
input.Font = Enum.Font.Gotham
input.TextSize = 15
input.ClearTextOnFocus = false
input.LayoutOrder = nextOrder()
input.Parent = scroll
corner(input, 8)

-- Cartão de informações
local infoCard = Instance.new("Frame")
infoCard.Size = UDim2.new(1, 0, 0, 74)
infoCard.BackgroundColor3 = C.field
infoCard.LayoutOrder = nextOrder()
infoCard.Parent = scroll
corner(infoCard, 8)

local thumb = Instance.new("ImageLabel")
thumb.Size = UDim2.fromOffset(60, 60)
thumb.Position = UDim2.fromOffset(7, 7)
thumb.BackgroundColor3 = C.bg
thumb.Image = ""
thumb.Parent = infoCard
corner(thumb, 8)

local infoText = Instance.new("TextLabel")
infoText.BackgroundTransparency = 1
infoText.Position = UDim2.fromOffset(75, 4)
infoText.Size = UDim2.new(1, -82, 1, -8)
infoText.TextWrapped = true
infoText.TextXAlignment = Enum.TextXAlignment.Left
infoText.TextYAlignment = Enum.TextYAlignment.Center
infoText.TextColor3 = C.text
infoText.Font = Enum.Font.Gotham
infoText.TextSize = 13
infoText.Parent = infoCard

local function setInfo(text) infoText.Text = text end
setInfo("Nenhum jogador selecionado.\nDigite um nome e toque em Pesquisar.")

-- Prévia grande
local preview = Instance.new("ImageLabel")
preview.Size = UDim2.new(1, 0, 0, 200)
preview.BackgroundColor3 = C.field
preview.ScaleType = Enum.ScaleType.Fit
preview.Visible = false
preview.LayoutOrder = 100
preview.Parent = scroll
corner(preview, 8)

------------------------------------------------------------------------
-- UTILIDADES DE PERSONAGEM
------------------------------------------------------------------------
local function getHum()
	local c = LP.Character
	return c and c:FindFirstChildOfClass("Humanoid")
end

local ANIM_MAP = {
	{ key = "Idle",  prop = "IdleAnimation",  paths = { { "idle", "Animation1" }, { "idle", "Animation2" } } },
	{ key = "Walk",  prop = "WalkAnimation",  paths = { { "walk", "WalkAnim" } } },
	{ key = "Run",   prop = "RunAnimation",   paths = { { "run", "RunAnim" } } },
	{ key = "Jump",  prop = "JumpAnimation",  paths = { { "jump", "JumpAnim" } } },
	{ key = "Fall",  prop = "FallAnimation",  paths = { { "fall", "FallAnim" } } },
	{ key = "Climb", prop = "ClimbAnimation", paths = { { "climb", "ClimbAnim" } } },
	{ key = "Swim",  prop = "SwimAnimation",  paths = { { "swim", "Swim" } } },
}

local function findAnimInstance(animate, path)
	local a = animate:FindFirstChild(path[1])
	local b = a and a:FindFirstChild(path[2])
	if b and b:IsA("Animation") then return b end
	return nil
end

local function restartAnimate(hum, animate)
	local animator = hum:FindFirstChildOfClass("Animator")
	if animator then
		for _, t in ipairs(animator:GetPlayingAnimationTracks()) do t:Stop(0) end
	end
	animate.Disabled = true
	task.wait(0.1)
	animate.Disabled = false
end

-- Testa se o jogo realmente consegue carregar a animação
local function testAnim(hum, id)
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then return false end
	local a = Instance.new("Animation")
	a.AnimationId = "rbxassetid://" .. tostring(id)
	local ok, track = pcall(function() return animator:LoadAnimation(a) end)
	if not ok or not track then
		a:Destroy()
		return false
	end
	local t = 0
	while track.Length <= 0 and t < 2.5 do
		task.wait(0.1)
		t += 0.1
	end
	local good = track.Length > 0
	pcall(function() track:Destroy() end)
	a:Destroy()
	return good
end

------------------------------------------------------------------------
-- PESQUISA
------------------------------------------------------------------------
-- aceita "usuario", ":char me usuario", "char me usuario" ou ":char usuario"
local function cleanName(text)
	text = text:match("^%s*(.-)%s*$") or ""
	local n = text:match("^:?[Cc][Hh][Aa][Rr]%s+[Mm][Ee]%s+(.+)$") or text:match("^:?[Cc][Hh][Aa][Rr]%s+(.+)$")
	return ((n or text):match("^%s*(.-)%s*$")) or ""
end

local function resolveUser(text)
	text = cleanName(text)
	if text == "" then return nil, "empty" end

	local ok, id = pcall(Players.GetUserIdFromNameAsync, Players, text)
	if ok and id then
		local ok2, name = pcall(Players.GetNameFromUserIdAsync, Players, id)
		return id, (ok2 and name) or text
	end

	local errMsg = tostring(id):lower()
	if text:match("^%d+$") then
		local n = tonumber(text)
		local ok3, name = pcall(Players.GetNameFromUserIdAsync, Players, n)
		if ok3 and name then return n, name end
	end
	if errMsg:find("http") or errMsg:find("timed") or errMsg:find("throttl") or errMsg:find("service") then
		return nil, "network", errMsg
	end
	return nil, "notfound"
end

local function doSearch()
	local text = cleanName(input.Text)
	if text == "" then
		notify("warn", "Digite um nome de usuário primeiro.")
		return
	end
	notify("info", "Pesquisando \"" .. text .. "\"...")
	local id, nameOrErr, detail = resolveUser(text)
	if not id then
		if nameOrErr == "notfound" then
			notify("err", "Usuário não encontrado.")
		else
			notify("err", "Falha na busca: " .. tostring(detail or nameOrErr))
		end
		return
	end

	State.userId, State.name, State.desc = id, nameOrErr, nil
	preview.Visible = false
	preview.Image = ""
	thumb.Image = ""
	setInfo("Nome: " .. nameOrErr .. "\nID: " .. id .. "\nAvatar: ainda não carregado")
	notify("ok", "Jogador encontrado: " .. nameOrErr .. " (ID " .. id .. ")")

	local ok, content = pcall(Players.GetUserThumbnailAsync, Players, id,
		Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
	if ok and content then thumb.Image = content end
end

local function ensureDesc()
	if State.desc then return State.desc end
	local ok, d = pcall(Players.GetHumanoidDescriptionFromUserId, Players, State.userId)
	if ok and d then
		State.desc = d
		return d
	end
	return nil, tostring(d)
end

local function describeDesc(desc)
	local acc, layered, parts = 0, 0, {}
	local ok, list = pcall(function() return desc:GetAccessories(true) end)
	if ok and list then
		for _, a in ipairs(list) do
			acc += 1
			if a.IsLayered then layered += 1 end
		end
	end
	for _, p in ipairs({ "Head", "Torso", "LeftArm", "RightArm", "LeftLeg", "RightLeg" }) do
		local okp, v = pcall(function() return desc[p] end)
		if okp and v and v ~= 0 then table.insert(parts, p) end
	end
	return acc, layered, parts
end

local function showPreview()
	if not State.userId then notify("warn", "Pesquise um jogador primeiro.") return end
	notify("info", "Carregando avatar de " .. State.name .. "...")
	local desc, err = ensureDesc()
	if not desc then
		notify("err", "Falha ao carregar o avatar: " .. tostring(err))
		return
	end

	local shown = false
	for _ = 1, 6 do
		local ok, content, ready = pcall(Players.GetUserThumbnailAsync, Players, State.userId,
			Enum.ThumbnailType.AvatarThumbnail, Enum.ThumbnailSize.Size420x420)
		if ok and content then
			preview.Image = content
			preview.Visible = true
			shown = true
			if ready then break end
		end
		task.wait(1)
	end
	setInfo("Nome: " .. State.name .. "\nID: " .. State.userId .. "\nAvatar: carregado")
	local acc, layered, parts = describeDesc(desc)
	notify("info", string.format("Itens: %d acessórios (%d em camadas) | Partes de corpo personalizadas: %s",
		acc, layered, #parts > 0 and table.concat(parts, ", ") or "nenhuma"))
	if shown then
		notify("ok", "Avatar carregado.")
	else
		notify("warn", "Avatar carregado, mas a prévia visual não está disponível.")
	end
end

------------------------------------------------------------------------
-- APARÊNCIA
------------------------------------------------------------------------
local function snapshotOriginal()
	if State.originalDesc then return true end
	local hum = getHum()
	if not hum then return false end
	local ok, d = pcall(function() return hum:GetAppliedDescription() end)
	if ok and d then
		State.originalDesc = d
		return true
	end
	return false
end

-- Copia peças do modelo de aparência (acessórios, roupas, cores, rosto, cabeça R6).
-- Retorna true + relatório do que REALMENTE ficou no personagem.
local function manualApply(userId)
	local ok, model = pcall(Players.GetCharacterAppearanceAsync, Players, userId)
	if not ok or not model then return false, tostring(model) end
	local char, hum = LP.Character, getHum()
	if not (char and hum) then return false, "personagem não encontrado" end

	local rep = { acc = 0, accTotal = 0, clothes = false, colors = false, face = false, head = false,
		meshes = 0, r15parts = false }
	local R15NAMES = { UpperTorso = 1, LowerTorso = 1, LeftUpperLeg = 1, LeftLowerLeg = 1, LeftFoot = 1,
		RightUpperLeg = 1, RightLowerLeg = 1, RightFoot = 1, LeftUpperArm = 1, LeftLowerArm = 1,
		LeftHand = 1, RightUpperArm = 1, RightLowerArm = 1, RightHand = 1 }

	for _, v in ipairs(char:GetChildren()) do
		if v:IsA("Accessory") or v:IsA("Shirt") or v:IsA("Pants")
			or v:IsA("ShirtGraphic") or v:IsA("BodyColors") or v:IsA("CharacterMesh") then
			v:Destroy()
		end
	end

	for _, v in ipairs(model:GetChildren()) do
		if v:IsA("Accessory") then
			rep.accTotal += 1
			pcall(function() hum:AddAccessory(v:Clone()) end)
		elseif v:IsA("Shirt") or v:IsA("Pants") or v:IsA("ShirtGraphic") then
			v:Clone().Parent = char
			rep.clothes = true
		elseif v:IsA("BodyColors") then
			v:Clone().Parent = char
			rep.colors = true
		elseif v:IsA("CharacterMesh") then
			-- partes de corpo (pacotes) no rig R6, ex.: perna zumbi/esqueleto
			v:Clone().Parent = char
			rep.meshes += 1
		elseif v:IsA("BasePart") and R15NAMES[v.Name] then
			rep.r15parts = true
		end
	end

	-- conta o que realmente ficou no personagem
	for _, v in ipairs(char:GetChildren()) do
		if v:IsA("Accessory") then rep.acc += 1 end
	end

	local head, mHead = char:FindFirstChild("Head"), model:FindFirstChild("Head")
	if head and mHead then
		local newFace = mHead:FindFirstChildOfClass("Decal")
		if newFace then
			local old = head:FindFirstChildOfClass("Decal")
			if old then old:Destroy() end
			newFace:Clone().Parent = head
			rep.face = true
		end
		if hum.RigType == Enum.HumanoidRigType.R6 then
			local newMesh = mHead:FindFirstChildOfClass("SpecialMesh")
			local oldMesh = head:FindFirstChildOfClass("SpecialMesh")
			if newMesh and oldMesh then
				oldMesh:Destroy()
				newMesh:Clone().Parent = head
				rep.head = true
			end
		end
	end
	return true, rep
end

local function summarize(rep)
	return string.format("Acessórios: %d/%d | Roupas: %s | Cores: %s | Rosto: %s | Partes do corpo: %d",
		rep.acc, rep.accTotal, rep.clothes and "sim" or "não",
		rep.colors and "sim" or "não", rep.face and "sim" or "não", rep.meshes)
end

-- TRANSFORMAÇÃO COMPLETA: constrói um modelo completo do avatar alvo e o "veste"
-- sobre o seu personagem (soldado às suas partes), escondendo o seu corpo original.
-- Assim o jogo não precisa permitir ApplyDescription: corpo, perna de zumbi,
-- acessórios, camadas, roupas, rosto e cores vêm do modelo do alvo.
local function clearMorph()
	local m = State.morph
	if not m then return false end
	State.morph = nil
	for _, c in ipairs(m.conns) do pcall(function() c:Disconnect() end) end
	for inst, tr in pairs(m.originals) do
		if inst and inst.Parent then pcall(function() inst.Transparency = tr end) end
	end
	if m.model then pcall(function() m.model:Destroy() end) end
	return true
end

local function fullMorph(desc)
	local char, hum = LP.Character, getHum()
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not (char and hum and hrp) then return false, "personagem não encontrado" end

	local okM, model = pcall(Players.CreateHumanoidModelFromDescription, Players, desc, hum.RigType)
	if not okM or typeof(model) ~= "Instance" then return false, tostring(model) end
	if LP.Character ~= char or not char.Parent then
		model:Destroy()
		return false, "o personagem mudou durante o carregamento"
	end

	clearMorph()
	model.Name = "SC_" .. tostring(math.random(1000, 9999))

	-- remove juntas e scripts do modelo; cada parte será soldada ao seu personagem
	local remove = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Motor6D") or d:IsA("Script") or d:IsA("LocalScript") then
			table.insert(remove, d)
		end
	end
	for _, d in ipairs(remove) do d:Destroy() end

	local cloneHum = model:FindFirstChildOfClass("Humanoid")
	if cloneHum then
		pcall(function() cloneHum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None end)
		pcall(function() cloneHum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff end)
		pcall(function() cloneHum.BreakJointsOnDeath = false end)
		pcall(function() cloneHum.RequiresNeck = false end)
		pcall(function() cloneHum.EvaluateStateMachine = false end)
	end

	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.Massless = true
		end
	end

	model.Parent = workspace

	local bodyParts = 0
	for _, cp in ipairs(model:GetChildren()) do
		if cp:IsA("BasePart") then
			local rp = char:FindFirstChild(cp.Name)
			if not (rp and rp:IsA("BasePart")) then rp = hrp end
			cp.CFrame = rp.CFrame
			local w = Instance.new("Weld")
			w.Name = "SC_Weld"
			w.Part0 = rp
			w.Part1 = cp
			w.Parent = cp
			bodyParts += 1
		end
	end

	-- esconde o corpo original (e mantém escondido se o jogo tentar mostrar)
	local originals = {}
	local function hide(inst)
		if (inst:IsA("BasePart") or inst:IsA("Decal")) and inst.Name ~= "HumanoidRootPart"
			and not inst:FindFirstAncestorOfClass("Tool") then
			if originals[inst] == nil then originals[inst] = inst.Transparency end
			inst.Transparency = 1
		end
	end
	for _, d in ipairs(char:GetDescendants()) do hide(d) end

	local m = { model = model, originals = originals, conns = {} }
	table.insert(m.conns, char.DescendantAdded:Connect(hide))
	table.insert(m.conns, RunService.Heartbeat:Connect(function()
		for inst in pairs(originals) do
			if inst.Parent and inst.Transparency ~= 1 then inst.Transparency = 1 end
		end
	end))
	table.insert(m.conns, hum.Died:Connect(function() clearMorph() end))
	State.morph = m

	local acc, hasShirt, hasPants = 0, false, false
	for _, v in ipairs(model:GetChildren()) do
		if v:IsA("Accessory") then acc += 1
		elseif v:IsA("Shirt") then hasShirt = true
		elseif v:IsA("Pants") then hasPants = true end
	end
	return true, string.format("Partes do corpo: %d | Acessórios: %d | Camisa: %s | Calça: %s",
		bodyParts, acc, hasShirt and "sim" or "não", hasPants and "sim" or "não")
end

local function copyAppearanceClassic()
	if not State.userId then notify("warn", "Pesquise um jogador primeiro.") return end
	local hum = getHum()
	if not hum then notify("err", "Falha ao aplicar: seu personagem não foi encontrado.") return end

	notify("info", "Copiando aparência de " .. State.name .. "...")
	local desc, err = ensureDesc()
	if not desc then
		notify("err", "Falha ao carregar o avatar: " .. tostring(err))
		return
	end
	if not snapshotOriginal() then
		notify("warn", "Não consegui salvar sua aparência original; a restauração pode ser limitada.")
	end

	-- Etapa 1: método oficial (cobre proporções e partes do corpo em R15)
	local ok1, e1 = pcall(function() hum:ApplyDescription(desc) end)

	-- Etapa 2: sempre completa com acessórios/cores/rosto, porque em alguns jogos
	-- o ApplyDescription feito pelo cliente só aplica roupas.
	local ok2, rep = manualApply(State.userId)

	if ok2 then
		State.changed = true
		notify(rep.acc < rep.accTotal and "warn" or "ok", "Aparência aplicada. " .. summarize(rep))
		if rep.acc < rep.accTotal then
			notify("warn", "O jogo bloqueou " .. (rep.accTotal - rep.acc) .. " acessório(s).")
		end
		if hum.RigType == Enum.HumanoidRigType.R6 then
			if rep.r15parts and rep.meshes == 0 then
				notify("warn", "O avatar alvo usa partes de corpo R15 (ex.: perna personalizada). Elas não encaixam no seu personagem R6.")
			end
			notify("info", "Personagem R6: proporções (scale) não são suportadas.")
		end
	elseif ok1 then
		State.changed = true
		notify("warn", "Só o método básico funcionou (provavelmente apenas roupas): " .. tostring(rep))
	else
		notify("err", "Falha ao aplicar alterações: " .. tostring(rep or e1))
	end
end

local function copyAppearance()
	-- um toque: se o nome digitado ainda não foi pesquisado, pesquisa antes de transformar
	local typed = cleanName(input.Text)
	if typed ~= "" and (not State.name or typed:lower() ~= State.name:lower()) then
		State.userId, State.name, State.desc = nil, nil, nil
		doSearch()
	end
	if not State.userId then notify("warn", "Digite um usuário primeiro.") return end
	if not getHum() then notify("err", "Falha ao aplicar: seu personagem não foi encontrado.") return end

	notify("info", "Transformando seu personagem em " .. State.name .. "...")
	local desc, err = ensureDesc()
	if not desc then
		notify("err", "Falha ao carregar o avatar: " .. tostring(err))
		return
	end

	local ok, res = fullMorph(desc)
	if ok then
		State.changed = true
		State.morphDesc, State.morphName = desc, State.name
		notify("ok", "Você virou " .. State.name .. ". " .. res)
		notify("info", "Efeito visual local: só você (e a sua gravação) vê a transformação.")
		return
	end

	notify("warn", "Transformação falhou (" .. tostring(res) .. "). Usando método alternativo...")
	copyAppearanceClassic()
end

------------------------------------------------------------------------
-- ANIMAÇÕES
------------------------------------------------------------------------
local function snapshotAnims(char, animate)
	if State.animSnapshot and State.animSnapshot.char == char then return end
	local entries = {}
	for _, e in ipairs(ANIM_MAP) do
		for _, p in ipairs(e.paths) do
			local inst = findAnimInstance(animate, p)
			if inst then table.insert(entries, { inst = inst, id = inst.AnimationId }) end
		end
	end
	State.animSnapshot = { char = char, entries = entries }
end

local function copyAnimations()
	if not State.userId then notify("warn", "Pesquise um jogador primeiro.") return end
	local char, hum = LP.Character, getHum()
	if not (char and hum) then notify("err", "Falha ao aplicar: personagem não encontrado.") return end

	if hum.RigType == Enum.HumanoidRigType.R6 then
		local d = ensureDesc()
		local have = {}
		if d then
			for _, e in ipairs(ANIM_MAP) do
				local okp, id = pcall(function() return d[e.prop] end)
				if okp and id and id ~= 0 then table.insert(have, e.key) end
			end
		end
		notify("warn", "Função não suportada: seu personagem é R6 e as animações públicas são R15. "
			.. "Animações personalizadas do alvo: "
			.. (#have > 0 and table.concat(have, ", ") or "nenhuma (ele usa as padrão)") .. ".")
		return
	end
	local animate = char:FindFirstChild("Animate")
	if not animate then
		notify("warn", "Função não suportada pelo jogo: o personagem não tem o script Animate.")
		return
	end

	notify("info", "Lendo animações de " .. State.name .. "...")
	local desc, err = ensureDesc()
	if not desc then
		notify("err", "Falha ao carregar o avatar: " .. tostring(err))
		return
	end

	snapshotAnims(char, animate)
	local applied, default, failed = {}, {}, {}

	for _, e in ipairs(ANIM_MAP) do
		local okp, id = pcall(function() return desc[e.prop] end)
		if not okp or not id or id == 0 then
			table.insert(default, e.key)
		elseif not testAnim(hum, id) then
			table.insert(failed, e.key .. "(" .. tostring(id) .. ")")
		else
			local any = false
			for _, p in ipairs(e.paths) do
				local inst = findAnimInstance(animate, p)
				if inst then
					inst.AnimationId = "rbxassetid://" .. tostring(id)
					any = true
				end
			end
			if any then table.insert(applied, e.key .. "=" .. tostring(id)) else table.insert(failed, e.key .. "(" .. tostring(id) .. ")") end
		end
	end

	if #applied > 0 then
		restartAnimate(hum, animate)
		State.changed = true
		notify("ok", "Animações aplicadas: " .. table.concat(applied, ", ") .. ".")
	else
		notify("warn", "Nenhuma animação foi aplicada.")
	end
	if #default > 0 then
		notify("info", "O alvo usa a animação padrão (nada para copiar): " .. table.concat(default, ", ") .. ".")
	end
	if #failed > 0 then
		notify("err", "Falha ao carregar/aplicar: " .. table.concat(failed, ", ") .. ".")
	end
	notify("info", "Land: sem suporte (não faz parte dos dados públicos do avatar).")
end

------------------------------------------------------------------------
-- RESTAURAR / LIMPAR
------------------------------------------------------------------------
local function restoreOriginal()
	local hum, char = getHum(), LP.Character
	if not (hum and char) then notify("err", "Falha ao restaurar: personagem não encontrado.") return end
	if not State.changed and not State.originalDesc and not State.animSnapshot then
		notify("warn", "Nada para restaurar: você ainda não alterou nada.")
		return
	end

	local hadMorph = clearMorph()
	State.morphDesc, State.morphName = nil, nil
	local appearanceOk, animOk = nil, nil

	if State.originalDesc then
		local ok = pcall(function() hum:ApplyDescription(State.originalDesc) end)
		if ok then
			appearanceOk = true
		else
			local ok2 = manualApply(LP.UserId)
			appearanceOk = ok2 and "partial" or false
		end
	end

	if State.animSnapshot and State.animSnapshot.char == char then
		local animate = char:FindFirstChild("Animate")
		if animate then
			for _, en in ipairs(State.animSnapshot.entries) do
				if en.inst and en.inst.Parent then en.inst.AnimationId = en.id end
			end
			restartAnimate(hum, animate)
			animOk = true
		else
			animOk = false
		end
	end

	if appearanceOk == true then
		notify("ok", "Aparência original restaurada.")
	elseif appearanceOk == "partial" then
		notify("warn", "Restaurado em modo compatível: apliquei o avatar da sua conta (parcial).")
	elseif appearanceOk == false then
		notify("err", "Falha ao restaurar a aparência.")
	end
	if animOk == true then
		notify("ok", "Animações originais restauradas.")
	elseif animOk == false then
		notify("err", "Falha ao restaurar animações: script Animate ausente.")
	end

	if hadMorph then
		notify("ok", "Transformação removida: seu personagem original voltou.")
	end
	if appearanceOk ~= false and animOk ~= false then
		State.originalDesc, State.animSnapshot, State.changed = nil, nil, false
	end
end

local function clearSearch()
	input.Text = ""
	State.userId, State.name, State.desc = nil, nil, nil
	thumb.Image = ""
	preview.Image = ""
	preview.Visible = false
	setInfo("Nenhum jogador selecionado.\nDigite um nome e toque em Pesquisar.")
	notify("info", "Pesquisa limpa.")
end

------------------------------------------------------------------------
-- BOTÕES
------------------------------------------------------------------------
local function guarded(fn)
	return function()
		if State.busy then
			notify("warn", "Aguarde a operação atual terminar.")
			return
		end
		State.busy = true
		local ok, e = pcall(fn)
		State.busy = false
		if not ok then notify("err", "Erro inesperado: " .. tostring(e)) end
	end
end

local function makeButton(text, color, callback)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, 0, 0, 40)
	b.BackgroundColor3 = color
	b.Text = text
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 14
	b.AutoButtonColor = true
	b.LayoutOrder = nextOrder()
	b.Parent = scroll
	corner(b, 8)
	b.Activated:Connect(guarded(callback))
	return b
end

makeButton("Pesquisar jogador", C.accent, doSearch)
makeButton("Visualizar avatar", C.accent, showPreview)
makeButton("Copiar aparência completa", C.green, copyAppearance)
makeButton("Copiar animações", C.green, copyAnimations)
local autoBtn
autoBtn = makeButton("Reaplicar ao renascer: DESLIGADO", C.gray, function()
	State.autoMorph = not State.autoMorph
	autoBtn.Text = "Reaplicar ao renascer: " .. (State.autoMorph and "LIGADO" or "DESLIGADO")
	autoBtn.BackgroundColor3 = State.autoMorph and C.accent or C.gray
	notify("info", State.autoMorph and "A transformação será reaplicada quando você renascer."
		or "A transformação não será mais reaplicada ao renascer.")
end)
makeButton("Restaurar aparência original", C.yellow, restoreOriginal)
makeButton("Limpar pesquisa", C.gray, clearSearch)

------------------------------------------------------------------------
-- SKINS SALVAS (snapshot: guarda os itens, não o usuário)
------------------------------------------------------------------------
local SKIN_DIR = "SkinCopier"
local NUM_PROPS = { "Head", "Torso", "LeftArm", "RightArm", "LeftLeg", "RightLeg", "Shirt", "Pants",
	"GraphicTShirt", "Face", "ClimbAnimation", "FallAnimation", "IdleAnimation", "JumpAnimation",
	"MoodAnimation", "RunAnimation", "SwimAnimation", "WalkAnimation",
	"BodyTypeScale", "DepthScale", "HeadScale", "HeightScale", "ProportionScale", "WidthScale" }
local COLOR_PROPS = { "HeadColor", "LeftArmColor", "RightArmColor", "LeftLegColor", "RightLegColor", "TorsoColor" }

local function fsOk()
	return type(writefile) == "function" and type(readfile) == "function" and type(isfile) == "function"
		and type(listfiles) == "function" and type(isfolder) == "function" and type(makefolder) == "function"
end

local function skinPath(name) return SKIN_DIR .. "/" .. name .. ".json" end

local function sanitize(text)
	text = (text or ""):gsub("[^%w_%-]", "_")
	return text:sub(1, 40)
end

local function serializeDesc(desc, name, userId)
	local data = { name = name, userId = userId, saved = os.time(), props = {}, colors = {}, acc = {} }
	for _, p in ipairs(NUM_PROPS) do
		local ok, v = pcall(function() return desc[p] end)
		if ok and type(v) == "number" then data.props[p] = v end
	end
	for _, p in ipairs(COLOR_PROPS) do
		local ok, c = pcall(function() return desc[p] end)
		if ok and typeof(c) == "Color3" then data.colors[p] = { c.R, c.G, c.B } end
	end
	local ok, list = pcall(function() return desc:GetAccessories(true) end)
	if ok and list then
		for _, a in ipairs(list) do
			table.insert(data.acc, {
				id = a.AssetId, type = a.AccessoryType and a.AccessoryType.Name or "Hat",
				layered = a.IsLayered and true or false, order = a.Order, puff = a.Puffiness,
			})
		end
	end
	return data
end

local function buildDesc(data)
	local d = Instance.new("HumanoidDescription")
	for p, v in pairs(data.props or {}) do pcall(function() d[p] = v end) end
	for p, c in pairs(data.colors or {}) do pcall(function() d[p] = Color3.new(c[1], c[2], c[3]) end) end
	local list = {}
	for _, a in ipairs(data.acc or {}) do
		local okT, accType = pcall(function() return Enum.AccessoryType[a.type] end)
		if okT and accType then
			local item = { AssetId = a.id, AccessoryType = accType, IsLayered = a.layered }
			if a.layered then
				item.Order = a.order or 1
				item.Puffiness = a.puff or 1
			end
			table.insert(list, item)
		end
	end
	pcall(function() d:SetAccessories(list, true) end)
	return d
end

local function wearSaved(name)
	if not getHum() then notify("err", "Seu personagem não foi encontrado.") return end
	local ok, raw = pcall(readfile, skinPath(name))
	if not ok or not raw then notify("err", "Não consegui ler a skin salva.") return end
	local okj, data = pcall(function() return HttpService:JSONDecode(raw) end)
	if not okj or type(data) ~= "table" then notify("err", "O arquivo da skin está corrompido.") return end

	notify("info", "Vestindo a skin salva \"" .. name .. "\"...")
	local desc = buildDesc(data)
	local okm, res = fullMorph(desc)
	if okm then
		State.changed = true
		State.morphDesc, State.morphName = desc, name
		notify("ok", "Skin \"" .. name .. "\" vestida. " .. res)
	else
		notify("err", "Falha ao vestir a skin: " .. tostring(res))
	end
end

-- UI da lista
local saveName = Instance.new("TextBox")
saveName.Size = UDim2.new(1, 0, 0, 36)
saveName.BackgroundColor3 = C.field
saveName.PlaceholderText = "Nome da skin (opcional)"
saveName.PlaceholderColor3 = C.sub
saveName.Text = ""
saveName.TextColor3 = C.text
saveName.Font = Enum.Font.Gotham
saveName.TextSize = 14
saveName.ClearTextOnFocus = false
saveName.LayoutOrder = 10
saveName.Parent = scroll
corner(saveName, 8)

local savedTitle = Instance.new("TextLabel")
savedTitle.BackgroundTransparency = 1
savedTitle.Size = UDim2.new(1, 0, 0, 22)
savedTitle.Text = "Skins salvas (toque para vestir)"
savedTitle.TextColor3 = C.sub
savedTitle.Font = Enum.Font.GothamBold
savedTitle.TextSize = 12
savedTitle.TextXAlignment = Enum.TextXAlignment.Left
savedTitle.LayoutOrder = 150
savedTitle.Parent = scroll

local savedBox = Instance.new("Frame")
savedBox.BackgroundTransparency = 1
savedBox.Size = UDim2.new(1, 0, 0, 0)
savedBox.AutomaticSize = Enum.AutomaticSize.Y
savedBox.LayoutOrder = 151
savedBox.Parent = scroll
do
	local l = Instance.new("UIListLayout")
	l.Padding = UDim.new(0, 5)
	l.SortOrder = Enum.SortOrder.Name
	l.Parent = savedBox
end

local refreshSaved

local function addRow(name)
	local row = Instance.new("Frame")
	row.Name = name
	row.Size = UDim2.new(1, 0, 0, 38)
	row.BackgroundTransparency = 1
	row.Parent = savedBox

	local use = Instance.new("TextButton")
	use.Size = UDim2.new(1, -44, 1, 0)
	use.BackgroundColor3 = C.field
	use.Text = name
	use.TextColor3 = C.text
	use.Font = Enum.Font.GothamBold
	use.TextSize = 13
	use.TextTruncate = Enum.TextTruncate.AtEnd
	use.Parent = row
	corner(use, 8)
	use.Activated:Connect(guarded(function() wearSaved(name) end))

	local del = Instance.new("TextButton")
	del.Size = UDim2.fromOffset(38, 38)
	del.Position = UDim2.new(1, -38, 0, 0)
	del.BackgroundColor3 = C.gray
	del.Text = "X"
	del.TextColor3 = Color3.new(1, 1, 1)
	del.Font = Enum.Font.GothamBold
	del.TextSize = 14
	del.Parent = row
	corner(del, 8)
	local armed = false
	del.Activated:Connect(function()
		if not armed then
			armed = true
			del.Text, del.BackgroundColor3 = "?", C.red
			notify("warn", "Toque de novo no botão vermelho para apagar \"" .. name .. "\".")
			task.delay(3, function()
				if del.Parent and armed then
					armed = false
					del.Text, del.BackgroundColor3 = "X", C.gray
				end
			end)
			return
		end
		if type(delfile) ~= "function" then
			notify("err", "Seu executor não permite apagar arquivos.")
			return
		end
		local ok = pcall(delfile, skinPath(name))
		notify(ok and "ok" or "err", ok and ("Skin \"" .. name .. "\" apagada.") or "Falha ao apagar a skin.")
		refreshSaved()
	end)
end

local function infoRow(text)
	local l = Instance.new("TextLabel")
	l.Name = "~info"
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, 0, 0, 20)
	l.Text = text
	l.TextColor3 = C.sub
	l.Font = Enum.Font.Gotham
	l.TextSize = 12
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = savedBox
end

refreshSaved = function()
	for _, c in ipairs(savedBox:GetChildren()) do
		if c:IsA("Frame") or c:IsA("TextLabel") then c:Destroy() end
	end
	if not fsOk() then
		infoRow("Seu executor não suporta salvar arquivos.")
		return
	end
	local names = {}
	if isfolder(SKIN_DIR) then
		local ok, list = pcall(listfiles, SKIN_DIR)
		if ok and list then
			for _, path in ipairs(list) do
				local n = tostring(path):match("([^/\\]+)%.json$")
				if n then table.insert(names, n) end
			end
		end
	end
	if #names == 0 then
		infoRow("Nenhuma skin salva ainda.")
		return
	end
	for _, n in ipairs(names) do addRow(n) end
end

local function saveSkin()
	if not fsOk() then
		notify("err", "Seu executor não permite salvar arquivos; não dá para guardar skins.")
		return
	end
	local typed = cleanName(input.Text)
	if typed ~= "" and (not State.name or typed:lower() ~= State.name:lower()) then
		State.userId, State.name, State.desc = nil, nil, nil
		doSearch()
	end
	if not State.userId then notify("warn", "Digite um usuário primeiro.") return end

	local desc, err = ensureDesc()
	if not desc then notify("err", "Falha ao carregar o avatar: " .. tostring(err)) return end

	local base = sanitize(saveName.Text ~= "" and saveName.Text or State.name)
	if base == "" then base = "skin" end
	local okF = pcall(function()
		if not isfolder(SKIN_DIR) then makefolder(SKIN_DIR) end
	end)
	if not okF then notify("err", "Não consegui criar a pasta de skins.") return end

	local name, n = base, 1
	while isfile(skinPath(name)) do
		n += 1
		name = base .. "_" .. n
	end

	local data = serializeDesc(desc, State.name, State.userId)
	local ok, e = pcall(function() writefile(skinPath(name), HttpService:JSONEncode(data)) end)
	if ok then
		notify("ok", "Skin salva como \"" .. name .. "\" (" .. #data.acc .. " acessórios). "
			.. "Ela fica igual mesmo se o dono mudar o avatar.")
		saveName.Text = ""
		refreshSaved()
	else
		notify("err", "Falha ao salvar a skin: " .. tostring(e))
	end
end

local saveBtn = makeButton("Salvar skin do alvo", C.accent, saveSkin)
saveBtn.LayoutOrder = 11
refreshSaved()

------------------------------------------------------------------------
-- SOCO VISUAL: toca uma animação local a cada clique do mouse.
-- Só visual: não aciona nenhum botão/remote do jogo e não causa dano.
------------------------------------------------------------------------
-- Animações padrão de golpe da própria Roblox (balanço de braço do Animate padrão)
local PUNCH_DEFAULT = { R6 = 129967390, R15 = 522635514 }
local punch = { on = false, track = nil, char = nil, conn = nil, id = nil, preparing = false }

local punchId = Instance.new("TextBox")
punchId.Size = UDim2.new(1, 0, 0, 36)
punchId.BackgroundColor3 = C.field
punchId.PlaceholderText = "ID da animação de soco (opcional)"
punchId.PlaceholderColor3 = C.sub
punchId.Text = ""
punchId.TextColor3 = C.text
punchId.Font = Enum.Font.Gotham
punchId.TextSize = 14
punchId.ClearTextOnFocus = false
punchId.LayoutOrder = 12
punchId.Parent = scroll
corner(punchId, 8)
punchId.FocusLost:Connect(function()
	-- força recarregar com o novo ID no próximo clique
	if punch.track then pcall(function() punch.track:Stop(0) end) end
	punch.track, punch.char = nil, nil
end)

local function preparePunch()
	local char, hum = LP.Character, getHum()
	if not (char and hum) then return false, "personagem não encontrado" end
	if punch.track and punch.char == char then return true end
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then return false, "personagem sem Animator" end

	local custom = (punchId.Text or ""):match("%d+")
	local id = custom or tostring(hum.RigType == Enum.HumanoidRigType.R6 and PUNCH_DEFAULT.R6 or PUNCH_DEFAULT.R15)
	local a = Instance.new("Animation")
	a.AnimationId = "rbxassetid://" .. id
	local ok, track = pcall(function() return animator:LoadAnimation(a) end)
	if not ok or not track then return false, "não consegui carregar a animação " .. id end

	local t = 0
	while track.Length <= 0 and t < 2.5 do
		task.wait(0.1)
		t += 0.1
	end
	if track.Length <= 0 then
		pcall(function() track:Destroy() end)
		return false, "a animação " .. id .. " não carregou neste jogo"
	end
	track.Priority = Enum.AnimationPriority.Action4
	track.Looped = false
	punch.track, punch.char, punch.id = track, char, id
	return true
end

local function doPunch()
	if punch.preparing then return end
	if not punch.track or punch.char ~= LP.Character then
		punch.preparing = true
		local ok, e = preparePunch()
		punch.preparing = false
		if not ok then notify("err", "Soco visual: " .. tostring(e)) return end
	end
	local tr = punch.track
	if tr.IsPlaying then tr:Stop(0.05) end
	tr:Play(0.05)
end

local punchBtn
punchBtn = makeButton("Soco visual a cada clique: DESLIGADO", C.gray, function()
	if punch.on then
		punch.on = false
		if punch.conn then punch.conn:Disconnect() punch.conn = nil end
		if punch.track then pcall(function() punch.track:Stop(0) end) end
		punchBtn.Text = "Soco visual a cada clique: DESLIGADO"
		punchBtn.BackgroundColor3 = C.gray
		notify("info", "Soco visual desligado.")
		return
	end
	local ok, e = preparePunch()
	if not ok then notify("err", "Soco visual: " .. tostring(e)) return end
	punch.on = true
	punch.conn = UIS.InputBegan:Connect(function(inputObj, processed)
		if processed then return end
		if inputObj.UserInputType == Enum.UserInputType.MouseButton1 then doPunch() end
	end)
	table.insert(conns, punch.conn)
	punchBtn.Text = "Soco visual a cada clique: LIGADO"
	punchBtn.BackgroundColor3 = C.accent
	notify("ok", "Soco visual ligado (animação " .. punch.id .. "): cada clique toca o golpe. É só visual e local.")
end)
punchBtn.LayoutOrder = 13

-- Enter no teclado = transformar
input.FocusLost:Connect(function(enterPressed)
	if enterPressed then guarded(copyAppearance)() end
end)

-- Rodapé com aviso real
local foot = Instance.new("TextLabel")
foot.BackgroundTransparency = 1
foot.Size = UDim2.new(1, 0, 0, 0)
foot.AutomaticSize = Enum.AutomaticSize.Y
foot.TextWrapped = true
foot.TextXAlignment = Enum.TextXAlignment.Left
foot.TextColor3 = C.sub
foot.Font = Enum.Font.Gotham
foot.TextSize = 11
foot.Text = "Mudanças são locais e o servidor pode reverter. Respawn volta ao normal. "
	.. "Sem garantia contra banimento."
foot.LayoutOrder = 200
foot.Parent = scroll

------------------------------------------------------------------------
-- MINIMIZAR / FECHAR
------------------------------------------------------------------------
local bubble = Instance.new("TextButton")
bubble.Size = UDim2.fromOffset(46, 46)
bubble.BackgroundColor3 = C.accent
bubble.Text = "SC"
bubble.TextColor3 = Color3.new(1, 1, 1)
bubble.Font = Enum.Font.GothamBold
bubble.TextSize = 15
bubble.Visible = false
bubble.Parent = gui
corner(bubble, 23)
local bubbleMoved = makeDraggable(bubble, bubble)

btnMin.Activated:Connect(function()
	local p = panel.AbsolutePosition
	bubble.Position = UDim2.fromOffset(p.X, p.Y)
	panel.Visible = false
	bubble.Visible = true
end)

bubble.Activated:Connect(function()
	if bubbleMoved() then return end
	local p = bubble.AbsolutePosition
	panel.Position = UDim2.fromOffset(
		math.clamp(p.X, 0, math.max(0, gui.AbsoluteSize.X - W)),
		math.clamp(p.Y, 0, math.max(0, gui.AbsoluteSize.Y - H)))
	bubble.Visible = false
	panel.Visible = true
end)

local function destroy()
	for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
	table.clear(conns)
	if gui then gui:Destroy() end
	env.__SkinCopier = nil
end
btnClose.Activated:Connect(destroy)
env.__SkinCopier = { Destroy = destroy }

-- Respawn: o jogo recria o personagem e as mudanças locais se perdem
table.insert(conns, LP.CharacterAdded:Connect(function(newChar)
	clearMorph()
	State.originalDesc, State.animSnapshot = nil, nil
	if State.autoMorph and State.morphDesc then
		task.spawn(function()
			newChar:WaitForChild("Humanoid", 10)
			newChar:WaitForChild("HumanoidRootPart", 10)
			task.wait(1.5)
			if LP.Character ~= newChar then return end
			local ok, res = fullMorph(State.morphDesc)
			if ok then
				State.changed = true
				notify("ok", "Transformação reaplicada. " .. res)
			else
				State.changed = false
				notify("err", "Falha ao reaplicar a transformação: " .. tostring(res))
			end
		end)
	else
		if State.changed then
			notify("warn", "Personagem reiniciou: as alterações locais foram perdidas.")
		end
		State.changed = false
	end
end))

notify("ok", "Skin Copier carregado. Digite um usuário e toque em Pesquisar.")
