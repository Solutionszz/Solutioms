--[[
    SKIN COPIER  |  Roblox (Delta / Android)  |  v1.0

    O QUE FAZ
      - Pesquisa qualquer usuário pelo nome (online, offline ou em outro servidor)
      - Mostra miniatura e prévia do avatar público
      - Copia a aparência (roupas, acessórios, layered clothing, cores, proporções,
        rosto, partes do corpo) via HumanoidDescription
      - Copia animações (Idle, Walk, Run, Jump, Fall, Climb, Swim) com validação
      - Restaura a aparência/animações originais
      - Notificações com o resultado REAL de cada operação

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
local function resolveUser(text)
	text = text:match("^%s*(.-)%s*$") or ""
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
	local text = input.Text
	if (text:match("^%s*(.-)%s*$") or "") == "" then
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

-- Plano B: copia peças do modelo de aparência quando ApplyDescription falha
local function manualApply(userId)
	local ok, model = pcall(Players.GetCharacterAppearanceAsync, Players, userId)
	if not ok or not model then return false, tostring(model) end
	local char, hum = LP.Character, getHum()
	if not (char and hum) then return false, "personagem não encontrado" end

	for _, v in ipairs(char:GetChildren()) do
		if v:IsA("Accessory") or v:IsA("Shirt") or v:IsA("Pants")
			or v:IsA("ShirtGraphic") or v:IsA("BodyColors") then
			v:Destroy()
		end
	end
	local head = char:FindFirstChild("Head")
	for _, v in ipairs(model:GetChildren()) do
		if v:IsA("Accessory") then
			pcall(function() hum:AddAccessory(v) end)
		elseif v:IsA("Shirt") or v:IsA("Pants") or v:IsA("ShirtGraphic") or v:IsA("BodyColors") then
			v.Parent = char
		end
	end
	local mHead = model:FindFirstChild("Head")
	if head and mHead then
		local newFace = mHead:FindFirstChildOfClass("Decal")
		if newFace then
			local old = head:FindFirstChildOfClass("Decal")
			if old then old:Destroy() end
			newFace:Clone().Parent = head
		end
	end
	return true
end

local function verifyApplied(hum, desc)
	local ok, applied = pcall(function() return hum:GetAppliedDescription() end)
	if not ok or not applied then return nil end
	for _, p in ipairs({ "Shirt", "Pants", "GraphicTShirt", "Face" }) do
		local a, x = pcall(function() return applied[p] end)
		local b, y = pcall(function() return desc[p] end)
		if a and b and x ~= y then return false end
	end
	return true
end

local function copyAppearance()
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

	local ok, e = pcall(function() hum:ApplyDescription(desc) end)
	if ok then
		State.changed = true
		local v = verifyApplied(hum, desc)
		if v == false then
			notify("warn", "Comando executado, mas NÃO consegui confirmar a mudança. O jogo pode ter bloqueado.")
		else
			notify("ok", "Aparência de " .. State.name .. " aplicada" .. (v and " (verificada)." or "."))
		end
		if hum.RigType == Enum.HumanoidRigType.R6 then
			notify("info", "Seu personagem é R6: proporções e partes especiais do corpo podem não aparecer.")
		end
		return
	end

	-- Plano B
	local ok2, e2 = manualApply(State.userId)
	if ok2 then
		State.changed = true
		notify("warn", "Aplicado em modo compatível (parcial): roupas, acessórios, cores e rosto.")
	else
		notify("err", "Falha ao aplicar alterações: " .. tostring(e2 or e))
	end
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
		notify("warn", "Função não suportada: seu personagem é R6 e as animações públicas são R15.")
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
			table.insert(failed, e.key)
		else
			local any = false
			for _, p in ipairs(e.paths) do
				local inst = findAnimInstance(animate, p)
				if inst then
					inst.AnimationId = "rbxassetid://" .. tostring(id)
					any = true
				end
			end
			if any then table.insert(applied, e.key) else table.insert(failed, e.key) end
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
		notify("info", "Sem animação personalizada (padrão): " .. table.concat(default, ", ") .. ".")
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
makeButton("Restaurar aparência original", C.yellow, restoreOriginal)
makeButton("Limpar pesquisa", C.gray, clearSearch)

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
table.insert(conns, LP.CharacterAdded:Connect(function()
	if State.changed then
		notify("warn", "Personagem reiniciou: as alterações locais foram perdidas.")
	end
	State.originalDesc, State.animSnapshot, State.changed = nil, nil, false
end))

notify("ok", "Skin Copier carregado. Digite um usuário e toque em Pesquisar.")
