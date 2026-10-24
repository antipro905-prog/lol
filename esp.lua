--[[
	AimBot + ESP + Меню для Rivals Modded 100x
	Тип: LocalScript
	Куда положить: StarterPlayer > StarterPlayerScripts

	ПК: зажми F — навестись. Q — аим вкл/выкл. M — меню.
	    + / − — быстрее / плавнее наводка. X — мгновенная наводка вкл/выкл.
	Телефон: кнопки «−», «⚡», «+» под кнопкой меню.

	Почему обычный аим не работал в Rivals:
	  1) Камера Rivals каждый кадр сама ставит свой поворот и перебивает наш.
	     Режим "Rivals" ставит камеру ПОСЛЕ их скрипта (приоритет Last).
	  2) Модель оружия (viewmodel) лежит в камере, и проверка стен
	     упиралась в неё. Теперь камера, прозрачные и проходимые детали игнорируются.
	  3) Если все игроки в одной команде Teams (например лобби), проверка
	     команды отсекала всех. Теперь команды учитываются, только если их больше одной,
	     либо по атрибуту игрока (CONFIG.TeamAttribute).

	Исправления «кривого» аима:
	  4) Прицел отставал от бегущего врага: плавность тянула к тому месту,
	     где цель была раньше. Теперь движение цели отслеживается сразу,
	     а сглаживается только ошибка наводки — прицел не волочится сзади.
	  5) Цель перескакивала между игроками каждый кадр, если они рядом.
	     Теперь прицел держит выбранную цель (StickyTarget), пока она в круге.
	  6) На R6-персонажах (нет UpperTorso) режим «Торс» целился в голову.
	     Теперь для R6 берётся Torso.
	  7) Прицел больше не дрожит у самой цели: в пределах доли градуса
	     он встаёт ровно на точку.
	  8) Цель не удерживалась: в режиме Rivals она выбиралась по камере игры,
	     а не по реальному прицелу. Теперь выбирается по прицелу, держится
	     ещё LockGrace секунд после укрытия и ищет видимую часть тела.

	Автострел (по умолчанию только на телефоне): стреляет сам,
	когда прицел на враге. Оружие-Tool работает сразу, для другого
	оружия впиши выстрел в функцию customFire внизу скрипта.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")
local Teams = game:GetService("Teams")

local player = Players.LocalPlayer

--==================== НАСТРОЙКИ ====================--
local CONFIG = {
	GamePassId = 0,            -- ID геймпасса (0 = бесплатно, для теста)

	-- Аим
	AimMode = "Override",      -- "Override" = режим Rivals, "Classic" = обычная камера Roblox
	AimPart = "Head",          -- "Head", "UpperTorso" или "HumanoidRootPart"
	FOV = 150,                 -- радиус круга захвата (пиксели)
	Smoothness = 0.35,         -- скорость наводки: 0.05 = плавно, 1 = мгновенно
	InstantSnap = false,       -- мгновенная наводка (прицел сразу на цели, без плавности)
	SpeedStep = 0.05,          -- насколько меняется скорость одним нажатием + / −
	Prediction = 0,            -- упреждение для медленных снарядов, 0 = выкл
	StickyTarget = true,       -- держать выбранную цель, а не прыгать между игроками
	LockGrace = 0.3,           -- сколько секунд держать цель, если она на миг скрылась

	-- Автострел
	AutoShoot = "Phone",       -- "Off" = выкл, "Phone" = только телефон, "All" = везде
	AutoShootAngle = 2,        -- стрелять, когда прицел ближе этого угла к цели (градусы)
	AutoShootDelay = 0.12,     -- пауза между выстрелами (сек)
	TeamCheck = true,          -- не целиться в своих
	TeamAttribute = "Team",    -- атрибут игрока с командой (если команды сделаны атрибутом)
	WallCheck = true,          -- не целиться сквозь стены
	TargetNPC = false,         -- целиться и в ботов (модели с Humanoid без игрока)
	ShowFOV = true,            -- показывать круг
	ShowTargetInfo = true,     -- показывать сверху, в кого навёлся
	HoldToAim = true,          -- ПК: наводить только при зажатой клавише F

	-- ESP (где находится игрок)
	ESP = true,                -- общий выключатель ESP
	ESPHighlight = true,       -- подсветка силуэта сквозь стены
	ESPNames = true,           -- ник над головой
	ESPDistance = true,        -- расстояние
	ESPHealth = true,          -- полоска здоровья
	ESPTracers = false,        -- линии от низа экрана к игрокам
	ESPTeammates = false,      -- показывать и своих
	ESPMaxDistance = 1000,     -- дальше этого не показывать

	-- Клавиши
	AimKey = Enum.KeyCode.F,   -- клавиша наводки
	ToggleKey = Enum.KeyCode.Q,
	MenuKey = Enum.KeyCode.M,
	SpeedUpKey = Enum.KeyCode.Equals,   -- "+" — быстрее (также + на цифровом блоке)
	SpeedDownKey = Enum.KeyCode.Minus,  -- "−" — плавнее (также − на цифровом блоке)
	SnapKey = Enum.KeyCode.X,           -- мгновенная наводка вкл/выкл
}
--===================================================--

local DEFAULTS = table.clone(CONFIG)

local enabled = true
local holding = false
local hasPass = (CONFIG.GamePassId == 0)
local isMobile = UserInputService.TouchEnabled and not UserInputService.MouseEnabled

if not hasPass then
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, CONFIG.GamePassId)
	end)
	hasPass = ok and owns
end

local COLORS = {
	bg = Color3.fromRGB(22, 22, 28),
	panel = Color3.fromRGB(34, 34, 42),
	accent = Color3.fromRGB(60, 180, 90),
	off = Color3.fromRGB(75, 75, 88),
	text = Color3.fromRGB(235, 235, 240),
	sub = Color3.fromRGB(150, 150, 165),
	red = Color3.fromRGB(180, 40, 40),
	gold = Color3.fromRGB(230, 160, 20),
	enemy = Color3.fromRGB(255, 60, 60),
	team = Color3.fromRGB(60, 140, 255),
}

--==================== ИНТЕРФЕЙС ====================--
local playerGui = player:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "AimBotGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local espFolder = Instance.new("Folder")
espFolder.Name = "AimBotESP"
espFolder.Parent = playerGui

local circle = Instance.new("Frame")
circle.Name = "FOVCircle"
circle.AnchorPoint = Vector2.new(0.5, 0.5)
circle.BackgroundTransparency = 1
circle.Parent = gui
Instance.new("UICorner", circle).CornerRadius = UDim.new(1, 0)
local stroke = Instance.new("UIStroke", circle)
stroke.Color = Color3.fromRGB(255, 255, 255)
stroke.Thickness = 1.5
stroke.Transparency = 0.3

local targetInfo = Instance.new("TextLabel")
targetInfo.Name = "TargetInfo"
targetInfo.AnchorPoint = Vector2.new(0.5, 0)
targetInfo.Position = UDim2.new(0.5, 0, 0, 70)
targetInfo.Size = UDim2.fromOffset(260, 28)
targetInfo.BackgroundColor3 = COLORS.bg
targetInfo.BackgroundTransparency = 0.25
targetInfo.Font = Enum.Font.GothamBold
targetInfo.TextSize = 15
targetInfo.TextColor3 = COLORS.enemy
targetInfo.Visible = false
targetInfo.Parent = gui
Instance.new("UICorner", targetInfo).CornerRadius = UDim.new(0, 8)

local function makeSideButton(name, posY)
	local b = Instance.new("TextButton")
	b.Name = name
	b.AnchorPoint = Vector2.new(1, 0.5)
	b.Position = UDim2.new(1, -20, 0.35, posY)
	b.Size = UDim2.fromOffset(110, 45)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 16
	b.TextColor3 = Color3.new(1, 1, 1)
	b.AutoButtonColor = true
	b.Parent = gui
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 10)
	return b
end

local toggleBtn = makeSideButton("AimToggle", 0)
local menuBtn = makeSideButton("MenuButton", 52)
menuBtn.Text = "⚙ МЕНЮ"
menuBtn.BackgroundColor3 = COLORS.panel

local refreshers = {}
local function refreshAll()
	for _, f in ipairs(refreshers) do
		f()
	end
end

local function updateUI()
	if not hasPass then
		toggleBtn.Text = "AIM: КУПИТЬ"
		toggleBtn.BackgroundColor3 = COLORS.gold
	elseif enabled then
		toggleBtn.Text = "AIM: ВКЛ"
		toggleBtn.BackgroundColor3 = Color3.fromRGB(40, 170, 70)
	else
		toggleBtn.Text = "AIM: ВЫКЛ"
		toggleBtn.BackgroundColor3 = COLORS.red
	end
	circle.Visible = CONFIG.ShowFOV and hasPass and enabled
	refreshAll()
end

local function applyConfig()
	circle.Size = UDim2.fromOffset(CONFIG.FOV * 2, CONFIG.FOV * 2)
	updateUI()
end

local function toggle()
	if not hasPass then
		MarketplaceService:PromptGamePassPurchase(player, CONFIG.GamePassId)
		return
	end
	enabled = not enabled
	updateUI()
end

toggleBtn.Activated:Connect(toggle)

--==================== СКОРОСТЬ НАВОДКИ ====================--
-- Всплывающая надпись с текущей скоростью (под строкой цели)
local speedInfo = Instance.new("TextLabel")
speedInfo.Name = "SpeedInfo"
speedInfo.AnchorPoint = Vector2.new(0.5, 0)
speedInfo.Position = UDim2.new(0.5, 0, 0, 104)
speedInfo.Size = UDim2.fromOffset(220, 26)
speedInfo.BackgroundColor3 = COLORS.bg
speedInfo.BackgroundTransparency = 0.25
speedInfo.Font = Enum.Font.GothamBold
speedInfo.TextSize = 14
speedInfo.TextColor3 = COLORS.accent
speedInfo.Visible = false
speedInfo.Parent = gui
Instance.new("UICorner", speedInfo).CornerRadius = UDim.new(0, 8)

local function isInstant()
	return CONFIG.InstantSnap or CONFIG.Smoothness >= 1
end

local function speedText()
	if isInstant() then
		return "⚡ Мгновенная наводка"
	end
	return string.format("Скорость наводки: %d%%", math.floor(CONFIG.Smoothness * 100 + 0.5))
end

local speedShowId = 0
local function showSpeed()
	speedShowId += 1
	local id = speedShowId
	speedInfo.Text = speedText()
	speedInfo.TextColor3 = isInstant() and COLORS.gold or COLORS.accent
	speedInfo.Visible = true
	task.delay(1.5, function()
		if speedShowId == id then
			speedInfo.Visible = false
		end
	end)
end

-- dir = 1 — быстрее, -1 — плавнее
local function changeSpeed(dir)
	if not hasPass then return end
	if CONFIG.InstantSnap then
		-- из мгновенного режима «−» возвращает к плавной наводке
		if dir < 0 then
			CONFIG.InstantSnap = false
		end
		applyConfig()
		showSpeed()
		return
	end
	local v = CONFIG.Smoothness + dir * CONFIG.SpeedStep
	v = math.floor(v * 100 + 0.5) / 100
	CONFIG.Smoothness = math.clamp(v, 0.05, 1)
	applyConfig()
	showSpeed()
end

local function toggleSnap()
	if not hasPass then return end
	CONFIG.InstantSnap = not CONFIG.InstantSnap
	applyConfig()
	showSpeed()
end

-- Кнопки «−  ⚡  +» под кнопкой меню (удобно на телефоне)
local function makeSpeedButton(name, text, rightOffset)
	local b = makeSideButton(name, 104)
	b.Position = UDim2.new(1, -20 - rightOffset, 0.35, 104)
	b.Size = UDim2.fromOffset(34, 40)
	b.TextSize = 20
	b.Text = text
	b.BackgroundColor3 = COLORS.panel
	return b
end

local speedUpBtn = makeSpeedButton("SpeedUp", "+", 0)
local snapBtn = makeSpeedButton("InstantSnap", "⚡", 38)
local speedDownBtn = makeSpeedButton("SpeedDown", "−", 76)

speedUpBtn.Activated:Connect(function()
	changeSpeed(1)
end)
speedDownBtn.Activated:Connect(function()
	changeSpeed(-1)
end)
snapBtn.Activated:Connect(toggleSnap)

table.insert(refreshers, function()
	local show = hasPass and enabled
	speedUpBtn.Visible = show
	speedDownBtn.Visible = show
	snapBtn.Visible = show
	snapBtn.BackgroundColor3 = CONFIG.InstantSnap and COLORS.gold or COLORS.panel
end)

--==================== МЕНЮ ====================--
local menu = Instance.new("Frame")
menu.Name = "Menu"
menu.AnchorPoint = Vector2.new(0.5, 0.5)
menu.Position = UDim2.fromScale(0.5, 0.5)
menu.Size = UDim2.fromOffset(320, 460)
menu.BackgroundColor3 = COLORS.bg
menu.Visible = false
menu.ZIndex = 10
menu.Parent = gui
Instance.new("UICorner", menu).CornerRadius = UDim.new(0, 12)
local menuStroke = Instance.new("UIStroke", menu)
menuStroke.Color = COLORS.accent
menuStroke.Thickness = 1.5
menuStroke.Transparency = 0.4

local uiScale = Instance.new("UIScale", menu)
local function updateScale()
	local cam = workspace.CurrentCamera
	if cam then
		uiScale.Scale = math.clamp(cam.ViewportSize.Y / 540, 0.6, 1)
	end
end
updateScale()
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)

-- Освобождает курсор в режиме от первого лица, пока меню открыто
local modal = Instance.new("TextButton")
modal.Size = UDim2.fromOffset(0, 0)
modal.BackgroundTransparency = 1
modal.Text = ""
modal.Modal = true
modal.Parent = menu

local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 42)
titleBar.BackgroundTransparency = 1
titleBar.Active = true
titleBar.ZIndex = 11
titleBar.Parent = menu

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(14, 0)
title.Size = UDim2.new(1, -60, 1, 0)
title.Font = Enum.Font.GothamBold
title.TextSize = 17
title.TextColor3 = COLORS.text
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "🎯 Rivals Modded — Настройки"
title.ZIndex = 11
title.Parent = titleBar

local closeBtn = Instance.new("TextButton")
closeBtn.AnchorPoint = Vector2.new(1, 0.5)
closeBtn.Position = UDim2.new(1, -8, 0.5, 0)
closeBtn.Size = UDim2.fromOffset(30, 30)
closeBtn.BackgroundColor3 = COLORS.red
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 16
closeBtn.TextColor3 = Color3.new(1, 1, 1)
closeBtn.Text = "✕"
closeBtn.ZIndex = 12
closeBtn.Parent = titleBar
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 8)

-- Вкладки
local tabBar = Instance.new("Frame")
tabBar.Position = UDim2.fromOffset(10, 44)
tabBar.Size = UDim2.new(1, -20, 0, 32)
tabBar.BackgroundTransparency = 1
tabBar.ZIndex = 11
tabBar.Parent = menu
local tabLayout = Instance.new("UIListLayout", tabBar)
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0, 6)

local pages, tabButtons = {}, {}

local function selectTab(name)
	for n, page in pairs(pages) do
		page.Visible = (n == name)
		tabButtons[n].BackgroundColor3 = (n == name) and COLORS.accent or COLORS.panel
	end
end

local function makePage(name)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(0.5, -3, 1, 0)
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 15
	btn.TextColor3 = Color3.new(1, 1, 1)
	btn.Text = name
	btn.ZIndex = 12
	btn.Parent = tabBar
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)

	local page = Instance.new("ScrollingFrame")
	page.Position = UDim2.fromOffset(10, 82)
	page.Size = UDim2.new(1, -20, 1, -92)
	page.BackgroundTransparency = 1
	page.BorderSizePixel = 0
	page.ScrollBarThickness = 4
	page.ScrollBarImageColor3 = COLORS.accent
	page.CanvasSize = UDim2.new()
	page.AutomaticCanvasSize = Enum.AutomaticSize.Y
	page.ZIndex = 11
	page.Parent = menu
	local layout = Instance.new("UIListLayout", page)
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder

	pages[name] = page
	tabButtons[name] = btn
	btn.Activated:Connect(function()
		selectTab(name)
	end)
	return page
end

local currentPage
local order = 0
local function nextOrder()
	order += 1
	return order
end

local tweenInfo = TweenInfo.new(0.15, Enum.EasingStyle.Quad)

local function makeLabel(parent, text, size, color, bold)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = bold and Enum.Font.GothamBold or Enum.Font.GothamMedium
	l.TextSize = size or 15
	l.TextColor3 = color or COLORS.text
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = text
	l.Position = UDim2.fromOffset(12, 0)
	l.Size = UDim2.new(1, -80, 1, 0)
	l.ZIndex = 12
	l.Parent = parent
	return l
end

local function makeRow(height)
	local row = Instance.new("TextButton")
	row.Text = ""
	row.AutoButtonColor = false
	row.Size = UDim2.new(1, -6, 0, height)
	row.BackgroundColor3 = COLORS.panel
	row.BorderSizePixel = 0
	row.LayoutOrder = nextOrder()
	row.ZIndex = 11
	row.Parent = currentPage
	Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)
	return row
end

local function makeHeader(text)
	local h = Instance.new("TextLabel")
	h.BackgroundTransparency = 1
	h.Size = UDim2.new(1, -6, 0, 22)
	h.Font = Enum.Font.GothamBold
	h.TextSize = 13
	h.TextColor3 = COLORS.sub
	h.TextXAlignment = Enum.TextXAlignment.Left
	h.Text = "  " .. string.upper(text)
	h.LayoutOrder = nextOrder()
	h.ZIndex = 11
	h.Parent = currentPage
end

local function makeToggle(text, key)
	local row = makeRow(40)
	makeLabel(row, text)

	local sw = Instance.new("Frame")
	sw.AnchorPoint = Vector2.new(1, 0.5)
	sw.Position = UDim2.new(1, -10, 0.5, 0)
	sw.Size = UDim2.fromOffset(46, 24)
	sw.ZIndex = 12
	sw.Parent = row
	Instance.new("UICorner", sw).CornerRadius = UDim.new(1, 0)

	local knob = Instance.new("Frame")
	knob.AnchorPoint = Vector2.new(0, 0.5)
	knob.Size = UDim2.fromOffset(18, 18)
	knob.BackgroundColor3 = Color3.new(1, 1, 1)
	knob.ZIndex = 13
	knob.Parent = sw
	Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

	-- key = имя поля CONFIG или "enabled"
	local function get()
		if key == "enabled" then return enabled end
		return CONFIG[key]
	end

	local function refresh()
		local on = get()
		TweenService:Create(sw, tweenInfo, {
			BackgroundColor3 = on and COLORS.accent or COLORS.off,
		}):Play()
		TweenService:Create(knob, tweenInfo, {
			Position = on and UDim2.new(1, -21, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
		}):Play()
	end

	row.Activated:Connect(function()
		if key == "enabled" then
			enabled = not enabled
		else
			CONFIG[key] = not CONFIG[key]
		end
		applyConfig()
	end)

	table.insert(refreshers, refresh)
	refresh()
end

local function makeSlider(text, key, min, max, step, decimals)
	local page = currentPage
	local row = makeRow(60)
	local label = makeLabel(row, text)
	label.Size = UDim2.new(1, -90, 0, 30)
	label.Position = UDim2.fromOffset(12, 2)

	local valueLabel = makeLabel(row, "", 15, COLORS.accent, true)
	valueLabel.AnchorPoint = Vector2.new(1, 0)
	valueLabel.Position = UDim2.new(1, -12, 0, 2)
	valueLabel.Size = UDim2.fromOffset(70, 30)
	valueLabel.TextXAlignment = Enum.TextXAlignment.Right

	local bar = Instance.new("Frame")
	bar.Position = UDim2.new(0, 14, 0, 40)
	bar.Size = UDim2.new(1, -28, 0, 6)
	bar.BackgroundColor3 = COLORS.off
	bar.BorderSizePixel = 0
	bar.ZIndex = 12
	bar.Parent = row
	Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)

	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = COLORS.accent
	fill.BorderSizePixel = 0
	fill.ZIndex = 13
	fill.Parent = bar
	Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

	local knob = Instance.new("Frame")
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Size = UDim2.fromOffset(16, 16)
	knob.BackgroundColor3 = Color3.new(1, 1, 1)
	knob.ZIndex = 14
	knob.Parent = bar
	Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

	local hit = Instance.new("TextButton")
	hit.Text = ""
	hit.BackgroundTransparency = 1
	hit.Position = UDim2.fromOffset(4, 28)
	hit.Size = UDim2.new(1, -8, 0, 30)
	hit.ZIndex = 15
	hit.Parent = row

	local fmt = "%." .. decimals .. "f"
	local dragging = false

	local function setFromX(x)
		local rel = math.clamp((x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
		local v = min + (max - min) * rel
		v = math.clamp(math.floor(v / step + 0.5) * step, min, max)
		CONFIG[key] = v
		applyConfig()
	end

	hit.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			page.ScrollingEnabled = false
			setFromX(input.Position.X)
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			setFromX(input.Position.X)
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch) then
			dragging = false
			page.ScrollingEnabled = true
		end
	end)

	local function refresh()
		local rel = (CONFIG[key] - min) / (max - min)
		fill.Size = UDim2.new(rel, 0, 1, 0)
		knob.Position = UDim2.new(rel, 0, 0.5, 0)
		valueLabel.Text = string.format(fmt, CONFIG[key])
	end

	table.insert(refreshers, refresh)
	refresh()
end

local function makeChoice(text, key, options)
	local row = makeRow(40)
	makeLabel(row, text)

	local btn = Instance.new("TextButton")
	btn.AnchorPoint = Vector2.new(1, 0.5)
	btn.Position = UDim2.new(1, -10, 0.5, 0)
	btn.Size = UDim2.fromOffset(120, 26)
	btn.BackgroundColor3 = COLORS.accent
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 14
	btn.TextColor3 = Color3.new(1, 1, 1)
	btn.ZIndex = 12
	btn.Parent = row
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)

	local function cycle()
		local idx = 1
		for i, opt in ipairs(options) do
			if opt[1] == CONFIG[key] then
				idx = i
			end
		end
		CONFIG[key] = options[idx % #options + 1][1]
		applyConfig()
	end
	btn.Activated:Connect(cycle)
	row.Activated:Connect(cycle)

	local function refresh()
		for _, opt in ipairs(options) do
			if opt[1] == CONFIG[key] then
				btn.Text = opt[2] .. "  ▸"
			end
		end
	end

	table.insert(refreshers, refresh)
	refresh()
end

local function makeButton(text, color, callback)
	local row = makeRow(38)
	row.BackgroundColor3 = color
	local l = makeLabel(row, text, 15, Color3.new(1, 1, 1), true)
	l.Position = UDim2.new()
	l.Size = UDim2.fromScale(1, 1)
	l.TextXAlignment = Enum.TextXAlignment.Center
	row.Activated:Connect(callback)
end

local function makeHint(text)
	local hint = Instance.new("TextLabel")
	hint.BackgroundTransparency = 1
	hint.Size = UDim2.new(1, -6, 0, 34)
	hint.Font = Enum.Font.Gotham
	hint.TextSize = 12
	hint.TextColor3 = COLORS.sub
	hint.TextWrapped = true
	hint.Text = text
	hint.LayoutOrder = nextOrder()
	hint.ZIndex = 11
	hint.Parent = currentPage
end

--------- Вкладка АИМ ---------
currentPage = makePage("Аим")
makeHeader("Основное")
makeToggle("Аим включён", "enabled")
makeChoice("Режим камеры", "AimMode", {
	{ "Override", "Rivals" },
	{ "Classic", "Обычный" },
})
makeToggle("Наводка по F", "HoldToAim")
makeChoice("Цель", "AimPart", {
	{ "Head", "Голова" },
	{ "UpperTorso", "Торс" },
	{ "HumanoidRootPart", "Центр" },
})

makeHeader("Захват")
makeSlider("Радиус FOV", "FOV", 30, 400, 5, 0)
makeSlider("Скорость наводки", "Smoothness", 0.05, 1, 0.05, 2)
makeToggle("Мгновенная наводка", "InstantSnap")
makeSlider("Упреждение", "Prediction", 0, 0.3, 0.01, 2)
makeToggle("Держать цель", "StickyTarget")
makeSlider("Держать после укрытия (сек)", "LockGrace", 0, 1, 0.05, 2)

makeHeader("Автострел")
makeChoice("Автострел", "AutoShoot", {
	{ "Phone", "Телефон" },
	{ "All", "Везде" },
	{ "Off", "Выкл" },
})
makeSlider("Точность (градусы)", "AutoShootAngle", 0.5, 10, 0.5, 1)
makeSlider("Пауза между выстрелами", "AutoShootDelay", 0.03, 0.5, 0.01, 2)

makeHeader("Проверки")
makeToggle("Не целиться в своих", "TeamCheck")
makeToggle("Не целиться сквозь стены", "WallCheck")
makeToggle("Целиться в ботов", "TargetNPC")
makeToggle("Показывать круг FOV", "ShowFOV")
makeToggle("Показывать цель сверху", "ShowTargetInfo")
makeHint("Q — аим вкл/выкл  •  M — меню  •  F — навестись  •  + / − — скорость  •  X — мгновенно")

--------- Вкладка ESP ---------
currentPage = makePage("ESP")
makeHeader("Где находятся игроки")
makeToggle("ESP включён", "ESP")
makeToggle("Подсветка сквозь стены", "ESPHighlight")
makeToggle("Ники", "ESPNames")
makeToggle("Расстояние", "ESPDistance")
makeToggle("Полоска HP", "ESPHealth")
makeToggle("Линии к игрокам", "ESPTracers")
makeToggle("Показывать своих", "ESPTeammates")
makeSlider("Макс. дистанция", "ESPMaxDistance", 50, 3000, 50, 0)

makeHeader("")
makeButton("Сбросить все настройки", COLORS.off, function()
	for k, v in pairs(DEFAULTS) do
		CONFIG[k] = v
	end
	enabled = true
	applyConfig()
end)

selectTab("Аим")

local function setMenu(open)
	if open and not hasPass then
		MarketplaceService:PromptGamePassPurchase(player, CONFIG.GamePassId)
		return
	end
	menu.Visible = open
	refreshAll()
end

menuBtn.Activated:Connect(function()
	setMenu(not menu.Visible)
end)
closeBtn.Activated:Connect(function()
	setMenu(false)
end)

-- Перетаскивание окна за заголовок
local draggingMenu, dragStart, startPos = false, nil, nil
titleBar.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		draggingMenu = true
		dragStart = input.Position
		startPos = menu.Position
	end
end)
UserInputService.InputChanged:Connect(function(input)
	if draggingMenu and (input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch) then
		local delta = input.Position - dragStart
		menu.Position = UDim2.new(
			startPos.X.Scale, startPos.X.Offset + delta.X,
			startPos.Y.Scale, startPos.Y.Offset + delta.Y
		)
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		draggingMenu = false
	end
end)

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(plr, id, purchased)
	if plr == player and id == CONFIG.GamePassId and purchased then
		hasPass = true
		enabled = true
		updateUI()
	end
end)

applyConfig()

--==================== УПРАВЛЕНИЕ ====================--
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end -- не реагировать, когда пишешь в чат
	if input.KeyCode == CONFIG.AimKey then
		holding = true
	elseif input.KeyCode == CONFIG.ToggleKey then
		toggle()
	elseif input.KeyCode == CONFIG.MenuKey then
		setMenu(not menu.Visible)
	elseif input.KeyCode == CONFIG.SpeedUpKey or input.KeyCode == Enum.KeyCode.KeypadPlus then
		changeSpeed(1)
	elseif input.KeyCode == CONFIG.SpeedDownKey or input.KeyCode == Enum.KeyCode.KeypadMinus then
		changeSpeed(-1)
	elseif input.KeyCode == CONFIG.SnapKey then
		toggleSnap()
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == CONFIG.AimKey then
		holding = false
	end
end)

-- Если окно игры потеряло фокус с зажатой F — отпускаем наводку
UserInputService.WindowFocusReleased:Connect(function()
	holding = false
end)

--==================== ЦЕЛИ ====================--
local function isTeammate(plr)
	if not plr then return false end
	local myAttr = player:GetAttribute(CONFIG.TeamAttribute)
	if myAttr ~= nil then
		return plr:GetAttribute(CONFIG.TeamAttribute) == myAttr
	end
	if player.Team ~= nil and #Teams:GetTeams() > 1 then
		return plr.Team == player.Team
	end
	return false
end

local npcCache, lastNpcScan = {}, 0
local function scanNPCs()
	npcCache = {}
	local function check(m)
		if m:IsA("Model") and m:FindFirstChildOfClass("Humanoid")
			and not Players:GetPlayerFromCharacter(m) then
			table.insert(npcCache, m)
		end
	end
	for _, obj in ipairs(workspace:GetChildren()) do
		check(obj)
		if obj:IsA("Folder") or (obj:IsA("Model") and not obj:FindFirstChildOfClass("Humanoid")) then
			for _, sub in ipairs(obj:GetChildren()) do
				check(sub)
			end
		end
	end
end

-- Список всех возможных целей на этот кадр: { char, plr, name }
local function getTargets()
	local list = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= player and plr.Character then
			table.insert(list, { char = plr.Character, plr = plr, name = plr.DisplayName })
		end
	end
	if CONFIG.TargetNPC then
		if os.clock() - lastNpcScan > 2 then
			scanNPCs()
			lastNpcScan = os.clock()
		end
		for _, m in ipairs(npcCache) do
			if m.Parent and m ~= player.Character then
				table.insert(list, { char = m, name = m.Name })
			end
		end
	end
	return list
end

local function aliveHumanoid(char)
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 then
		return hum
	end
	return nil
end

--==================== ESP ====================--
local espObjects = {}

local function createESP(char)
	local o = {}

	local hl = Instance.new("Highlight")
	hl.Name = "AimBotHighlight"
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.FillTransparency = 0.65
	hl.OutlineTransparency = 0
	hl.Adornee = char
	hl.Parent = char
	o.highlight = hl

	local bb = Instance.new("BillboardGui")
	bb.Name = "ESP_" .. char.Name
	bb.AlwaysOnTop = true
	bb.Size = UDim2.fromOffset(200, 46)
	bb.StudsOffset = Vector3.new(0, 2.6, 0)
	bb.LightInfluence = 0
	bb.Parent = espFolder
	o.billboard = bb

	local function textLabel(y, h, size)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromOffset(0, y)
		l.Size = UDim2.new(1, 0, 0, h)
		l.Font = Enum.Font.GothamBold
		l.TextSize = size
		l.TextStrokeTransparency = 0.3
		l.TextColor3 = Color3.new(1, 1, 1)
		l.Parent = bb
		return l
	end
	o.name = textLabel(0, 18, 15)
	o.info = textLabel(18, 16, 13)

	local hpBack = Instance.new("Frame")
	hpBack.AnchorPoint = Vector2.new(0.5, 0)
	hpBack.Position = UDim2.new(0.5, 0, 0, 37)
	hpBack.Size = UDim2.fromOffset(70, 5)
	hpBack.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	hpBack.BorderSizePixel = 0
	hpBack.Parent = bb
	local hpFill = Instance.new("Frame")
	hpFill.BorderSizePixel = 0
	hpFill.Parent = hpBack
	o.hpBack, o.hpFill = hpBack, hpFill

	local tracer = Instance.new("Frame")
	tracer.AnchorPoint = Vector2.new(0.5, 0.5)
	tracer.BorderSizePixel = 0
	tracer.BackgroundTransparency = 0.2
	tracer.Visible = false
	tracer.Parent = gui
	o.tracer = tracer

	espObjects[char] = o
	return o
end

local function destroyESP(char)
	local o = espObjects[char]
	if not o then return end
	o.highlight:Destroy()
	o.billboard:Destroy()
	o.tracer:Destroy()
	espObjects[char] = nil
end

local function drawLine(frame, a, b)
	local d = b - a
	frame.Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2)
	frame.Size = UDim2.fromOffset(d.Magnitude, 1.5)
	frame.Rotation = math.deg(math.atan2(d.Y, d.X))
end

local function updateESP(camera, targets)
	local seen = {}

	if hasPass and CONFIG.ESP then
		local myRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local origin = myRoot and myRoot.Position or camera.CFrame.Position
		local vs = camera.ViewportSize

		for _, t in ipairs(targets) do
			local char = t.char
			local hum = aliveHumanoid(char)
			local root = char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
			if hum and root then
				local mate = isTeammate(t.plr)
				local dist = (root.Position - origin).Magnitude
				if (CONFIG.ESPTeammates or not mate) and dist <= CONFIG.ESPMaxDistance then
					seen[char] = true
					local o = espObjects[char] or createESP(char)
					local color = mate and COLORS.team or COLORS.enemy

					o.highlight.Enabled = CONFIG.ESPHighlight
					o.highlight.FillColor = color
					o.highlight.OutlineColor = color

					o.billboard.Adornee = char:FindFirstChild("Head") or root
					o.billboard.Enabled = CONFIG.ESPNames or CONFIG.ESPDistance or CONFIG.ESPHealth

					o.name.Visible = CONFIG.ESPNames
					o.name.Text = t.name
					o.name.TextColor3 = color

					o.info.Visible = CONFIG.ESPDistance
					o.info.Text = math.floor(dist + 0.5) .. " м"

					o.hpBack.Visible = CONFIG.ESPHealth
					local hp = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
					o.hpFill.Size = UDim2.fromScale(hp, 1)
					o.hpFill.BackgroundColor3 = Color3.fromHSV(hp * 0.33, 0.9, 0.95)

					if CONFIG.ESPTracers then
						local sp = camera:WorldToViewportPoint(root.Position)
						if sp.Z > 0 then
							o.tracer.BackgroundColor3 = color
							drawLine(o.tracer, Vector2.new(vs.X / 2, vs.Y), Vector2.new(sp.X, sp.Y))
							o.tracer.Visible = true
						else
							o.tracer.Visible = false
						end
					else
						o.tracer.Visible = false
					end
				end
			end
		end
	end

	for char in pairs(espObjects) do
		if not seen[char] then
			destroyESP(char)
		end
	end
end

--==================== АИМ ====================--
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function getAimCenter(camera)
	local vs = camera.ViewportSize
	if isMobile or UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
		return Vector2.new(vs.X / 2, vs.Y / 2)
	end
	return UserInputService:GetMouseLocation()
end

-- Какие детали искать для каждого режима (R15 и R6)
local PART_NAMES = {
	Head = { "Head" },
	UpperTorso = { "UpperTorso", "Torso" },
	HumanoidRootPart = { "HumanoidRootPart", "Torso" },
}

local function getAimPart(char)
	for _, name in ipairs(PART_NAMES[CONFIG.AimPart] or { CONFIG.AimPart }) do
		local p = char:FindFirstChild(name)
		if p and p:IsA("BasePart") then
			return p
		end
	end
	return char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
end

-- Проверка стен: пропускает камеру (там модель оружия), прозрачные и проходимые детали
local function isVisible(camera, part, targetChar)
	if not CONFIG.WallCheck then return true end
	local origin = camera.CFrame.Position
	local dir = part.Position - origin
	local ignore = { targetChar, player.Character, camera }

	for _ = 1, 10 do
		rayParams.FilterDescendantsInstances = ignore
		local result = workspace:Raycast(origin, dir, rayParams)
		if not result then
			return true
		end
		local hit = result.Instance
		local model = hit:FindFirstAncestorOfClass("Model")
		local isCharacter = model and model:FindFirstChildOfClass("Humanoid")
		if hit.Transparency > 0.6 or not hit.CanCollide or isCharacter then
			table.insert(ignore, isCharacter and model or hit)
		else
			return false
		end
	end
	return false
end

-- Части тела, по которым проверяем, виден ли враг
local VISIBLE_PARTS = { "Head", "UpperTorso", "Torso", "HumanoidRootPart" }

-- Подходит ли цель: жива, не своя, на экране, в радиусе и видна
local function checkTarget(camera, t, center, maxDist)
	local char = t.char
	if not char.Parent or not aliveHumanoid(char) then return nil end
	if char:FindFirstChildOfClass("ForceField") then return nil end
	if CONFIG.TeamCheck and isTeammate(t.plr) then return nil end

	local part = getAimPart(char)
	if not part then return nil end

	local sp, onScreen = camera:WorldToViewportPoint(part.Position)
	if not onScreen then return nil end

	local dist = (Vector2.new(sp.X, sp.Y) - center).Magnitude
	if dist >= maxDist then return nil end

	-- Если нужная часть за укрытием, а другая видна — целимся в видимую
	if not isVisible(camera, part, char) then
		local alt = nil
		for _, n in ipairs(VISIBLE_PARTS) do
			local p = char:FindFirstChild(n)
			if p and p ~= part and p:IsA("BasePart") and isVisible(camera, p, char) then
				alt = p
				break
			end
		end
		if not alt then return nil end
		part = alt
	end

	return part, dist
end

local lockSeenAt = 0

local function getClosestTarget(camera, targets, current)
	local center = getAimCenter(camera)

	if current and CONFIG.StickyTarget then
		-- Держим прежнюю цель, пока она в круге (с запасом), чтобы прицел не прыгал
		local part = checkTarget(camera, current, center, CONFIG.FOV * 2)
		if part then
			lockSeenAt = os.clock()
			return part, current
		end
		-- Цель на миг пропала (укрытие, прыжок) — держим ещё немного
		if os.clock() - lockSeenAt < CONFIG.LockGrace
			and current.char.Parent and aliveHumanoid(current.char) then
			local p = getAimPart(current.char)
			if p then
				return p, current
			end
		end
	end

	local bestPart, bestTarget, bestDist = nil, nil, CONFIG.FOV
	for _, t in ipairs(targets) do
		local part, dist = checkTarget(camera, t, center, bestDist)
		if part then
			bestPart, bestTarget, bestDist = part, t, dist
		end
	end

	if bestTarget then
		lockSeenAt = os.clock()
	end
	return bestPart, bestTarget
end

local function wantsAim()
	if not (hasPass and enabled) or menu.Visible then return false end
	if CONFIG.HoldToAim and not isMobile and not holding then return false end
	return aliveHumanoid(player.Character) ~= nil
end

local function aimPosition(part)
	local pos = part.Position
	if CONFIG.Prediction > 0 then
		pos += part.AssemblyLinearVelocity * CONFIG.Prediction
	end
	return pos
end

local function smoothAlpha(dt)
	if CONFIG.InstantSnap then
		return 1 -- мгновенно: прицел встаёт на цель в тот же кадр
	end
	return 1 -(1 - math.clamp(CONFIG.Smoothness, 0.01, 1)) ^ (dt * 60)
end

-- Поворот, переводящий направление a в направление b
local function rotationBetween(a, b)
	local axis = a:Cross(b)
	if axis.Magnitude < 1e-6 then
		return CFrame.identity
	end
	local angle = math.acos(math.clamp(a:Dot(b), -1, 1))
	return CFrame.fromAxisAngle(axis.Unit, angle)
end

-- CFrame камеры без переворота, если смотрим строго вверх/вниз
local function lookCFrame(pos, look)
	if math.abs(look.Y) > 0.999 then
		look = Vector3.new(look.X + 0.001, math.sign(look.Y) * 0.999, look.Z).Unit
	end
	return CFrame.lookAt(pos, pos + look)
end

local lockedPart, lockedTarget = nil, nil
local aimLook = nil -- направление камеры для режима Rivals

-- Следящее сглаживание: движение цели повторяется сразу,
-- а плавно убирается только ошибка наводки. Поэтому прицел не отстаёт.
local SNAP_COS = math.cos(math.rad(0.15))
local prevWant, prevChar = nil, nil

local function trackLook(current, want, dt)
	local char = lockedTarget and lockedTarget.char
	if prevWant and prevChar == char then
		current = rotationBetween(prevWant, want):VectorToWorldSpace(current)
	end
	prevWant, prevChar = want, char

	local newLook = current:Lerp(want, smoothAlpha(dt))
	if newLook.Magnitude < 1e-3 then
		return want
	end
	newLook = newLook.Unit
	if newLook:Dot(want) > SNAP_COS then
		return want -- почти на цели: встаём ровно, без дрожи
	end
	return newLook
end

-- Шаг 1: цели, ESP, круг и обычный режим аима
RunService:BindToRenderStep("AimBotMain", Enum.RenderPriority.Camera.Value + 1, function(dt)
	local camera = workspace.CurrentCamera
	if not camera then return end

	-- Режим Rivals: выбираем цель по тому, куда реально смотрит прицел,
	-- а не по повороту камеры игры. Раньше из-за этого цель сбрасывалась,
	-- как только враг отходил от места, куда смотрела камера игры.
	if CONFIG.AimMode == "Override" and aimLook then
		camera.CFrame = lookCFrame(camera.CFrame.Position, aimLook)
	end

	local targets = getTargets()
	updateESP(camera, targets)

	if circle.Visible then
		local c = getAimCenter(camera)
		circle.Position = UDim2.fromOffset(c.X, c.Y)
	end

	local prevTarget = lockedTarget
	lockedPart, lockedTarget = nil, nil
	if wantsAim() then
		lockedPart, lockedTarget = getClosestTarget(camera, targets, prevTarget)
	end
	if not lockedPart then
		prevWant, prevChar = nil, nil
	end

	if lockedTarget and CONFIG.ShowTargetInfo then
		local myRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local d = myRoot and math.floor((lockedPart.Position - myRoot.Position).Magnitude + 0.5) or 0
		targetInfo.Text = "🎯 " .. lockedTarget.name .. "  •  " .. d .. " м"
		targetInfo.Visible = true
	else
		targetInfo.Visible = false
	end

	if CONFIG.AimMode == "Classic" and lockedPart then
		local camPos = camera.CFrame.Position
		local want = (aimPosition(lockedPart) - camPos).Unit
		local look = trackLook(camera.CFrame.LookVector, want, dt)
		camera.CFrame = lookCFrame(camPos, look)
	end
end)

-- Шаг 2: режим Rivals — ставим камеру последними, после их камерного скрипта
local function applyOverride(camera)
	camera.CFrame = lookCFrame(camera.CFrame.Position, aimLook)
end

RunService:BindToRenderStep("AimBotOverride", Enum.RenderPriority.Last.Value, function(dt)
	if CONFIG.AimMode ~= "Override" or not lockedPart then
		aimLook = nil
		return
	end
	local camera = workspace.CurrentCamera
	if not camera then return end

	local camPos = camera.CFrame.Position
	local want = (aimPosition(lockedPart) - camPos).Unit
	aimLook = trackLook(aimLook or camera.CFrame.LookVector, want, dt)

	applyOverride(camera)
end)

-- Запасной вариант: если их камера ставится через RenderStepped:Connect
RunService.RenderStepped:Connect(function()
	if CONFIG.AimMode == "Override" and aimLook and lockedPart then
		local camera = workspace.CurrentCamera
		if camera then
			applyOverride(camera)
		end
	end
end)

--==================== АВТОСТРЕЛ ====================--
-- Стреляет сам, когда прицел наведён на врага.
-- Оружие-Tool нажимается через tool:Activate().
-- Если оружие в игре сделано НЕ через Tool, впиши сюда свой выстрел
-- (например, вызов функции или RemoteEvent стрельбы).
-- down = true — нажать курок, false — отпустить.
local function customFire(down)
end

local firing, lastShot = false, 0

local function setTrigger(down)
	local char = player.Character
	local tool = char and char:FindFirstChildOfClass("Tool")
	if tool then
		if down then
			tool:Activate()
		else
			tool:Deactivate()
		end
	end
	customFire(down)
end

local function autoShootAllowed()
	if CONFIG.AutoShoot == "All" then return true end
	if CONFIG.AutoShoot == "Phone" then return isMobile end
	return false
end

-- Ставится после камеры, чтобы выстрел шёл туда, куда уже навёлся прицел
RunService:BindToRenderStep("AimBotAutoShoot", Enum.RenderPriority.Last.Value + 1, function()
	local camera = workspace.CurrentCamera
	local shouldFire = false

	if camera and lockedPart and autoShootAllowed() and wantsAim() then
		local dir = (aimPosition(lockedPart) - camera.CFrame.Position).Unit
		local dot = math.clamp(camera.CFrame.LookVector:Dot(dir), -1, 1)
		shouldFire = math.deg(math.acos(dot)) <= CONFIG.AutoShootAngle
	end

	if shouldFire then
		local now = os.clock()
		if now - lastShot >= CONFIG.AutoShootDelay then
			if firing then
				setTrigger(false)
			end
			setTrigger(true)
			firing = true
			lastShot = now
		end
	elseif firing then
		setTrigger(false)
		firing = false
	end
end)
