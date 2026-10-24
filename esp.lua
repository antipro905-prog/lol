--[[
	AimBot + ESP + Меню для Rivals Modded 100x
	Тип: LocalScript
	Куда положить: StarterPlayer > StarterPlayerScripts

	ПК:
	  F — аим вкл/выкл.  G — меню.
	  + / − — быстрее / плавнее наводка.  X — мгновенная наводка вкл/выкл.
	  ПКМ (зажать) — навестись на ближайшего врага, в том числе сквозь стены.
	Телефон: кнопки AIM, МЕНЮ и «−  MAX  +» справа.

	Сохранение настроек:
	  Всё, что игрок поменял в меню, сохраняется само и загружается при
	  следующем входе. Для этого нужен серверный скрипт AimBotConfigServer
	  (Script в ServerScriptService): LocalScript не может сам хранить
	  данные после выхода из игры — это умеет только сервер (DataStore).
	  Без серверного скрипта работает только CONFIG.Preset.

	Автонастройка (CONFIG.Preset):
	  В меню, вкладка «Конфиг», показаны все текущие настройки и их код.
	  Вставь код в CONFIG.Preset ниже — он применится при входе,
	  если у игрока ещё нет своих сохранённых настроек.

	Команды (свой / враг):
	  Скрипт ищет команду игрока по очереди: атрибуты и значения у игрока
	  и персонажа (Team, TeamName, TeamId, Side…), leaderstats, Teams, TeamColor.
	  Если все игроки в одной команде (лобби, каждый за себя) — своих нет.
	  Во вкладке «Аим» → «Проверки» видно, какую команду скрипт нашёл.
	  Если в игре своё имя поля с командой — впиши его в CONFIG.TeamAttribute.

	Почему обычный аим не работал в Rivals:
	  1) Камера Rivals каждый кадр сама ставит свой поворот и перебивает наш.
	     Режим "Rivals" ставит камеру ПОСЛЕ их скрипта (приоритет Last).
	  2) Модель оружия (viewmodel) лежит в камере, и проверка стен
	     упиралась в неё. Теперь камера, прозрачные и проходимые детали игнорируются.

	Исправления аима:
	  3) Прицел не отстаёт от бегущего врага: движение цели отслеживается сразу,
	     а сглаживается только ошибка наводки.
	  4) Прицел держит выбранную цель (StickyTarget), а не прыгает между игроками.
	  5) На R6-персонажах режим «Торс» берёт Torso.
	  6) У самой цели прицел встаёт ровно на точку, без дрожи.
	  7) В режиме Rivals цель выбирается по реальному прицелу, держится
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
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

--==================== НАСТРОЙКИ ====================--
-- Это значения по умолчанию. То, что игрок поменял в меню,
-- сохраняется и при следующем входе загружается само.
local CONFIG = {
	GamePassId = 0,            -- ID геймпасса (0 = бесплатно, для теста)

	-- Автонастройка: вставь сюда код из меню (вкладка «Конфиг»).
	-- Применяется при входе, если у игрока нет своих сохранённых настроек.
	-- "" = не применять.
	Preset = "",

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
	HoldToAim = true,          -- ПК: наводить только пока зажата ПКМ
	HoldThroughWalls = true,   -- ПК: при зажатой ПКМ целиться и сквозь стены

	-- Автострел
	AutoShoot = "Phone",       -- "Off" = выкл, "Phone" = только телефон, "All" = везде
	AutoShootAngle = 2,        -- стрелять, когда прицел ближе этого угла к цели (градусы)
	AutoShootDelay = 0.12,     -- пауза между выстрелами (сек)

	-- Проверки
	TeamCheck = true,          -- не целиться в своих
	TeamMode = "Auto",         -- "Auto" = определять команды сами, "Off" = все игроки враги
	TeamAttribute = "Team",    -- своё имя атрибута/значения с командой (проверяется первым)
	WallCheck = false,         -- false = целиться и сквозь стены, true = только в видимых
	TargetNPC = false,         -- целиться и в ботов (модели с Humanoid без игрока)
	ShowFOV = true,            -- показывать круг
	ShowTargetInfo = true,     -- показывать сверху, в кого навёлся

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
	ToggleKey = Enum.KeyCode.F,                    -- аим вкл/выкл
	MenuKey = Enum.KeyCode.G,                      -- открыть/закрыть меню
	AimHoldButton = Enum.UserInputType.MouseButton2, -- ПКМ: зажать — навестись (если HoldToAim)
	SpeedUpKey = Enum.KeyCode.Equals,              -- "+" — быстрее (также + на цифровом блоке)
	SpeedDownKey = Enum.KeyCode.Minus,             -- "−" — плавнее (также − на цифровом блоке)
	SnapKey = Enum.KeyCode.X,                      -- мгновенная наводка вкл/выкл
}
--===================================================--

local DEFAULTS = table.clone(CONFIG)

local enabled = true
local holding = false
local menuOpen = false
local hasPass = (CONFIG.GamePassId == 0)
local isMobile = UserInputService.TouchEnabled and not UserInputService.MouseEnabled

if not hasPass then
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, CONFIG.GamePassId)
	end)
	hasPass = ok and owns
end

local COLORS = {
	bg = Color3.fromRGB(14, 16, 22),
	bg2 = Color3.fromRGB(24, 28, 38),
	panel = Color3.fromRGB(27, 31, 41),
	panelHover = Color3.fromRGB(36, 41, 54),
	stroke = Color3.fromRGB(50, 57, 74),
	accent = Color3.fromRGB(64, 196, 108),
	off = Color3.fromRGB(58, 64, 80),
	text = Color3.fromRGB(236, 239, 244),
	sub = Color3.fromRGB(138, 147, 166),
	red = Color3.fromRGB(210, 64, 64),
	gold = Color3.fromRGB(236, 172, 44),
	enemy = Color3.fromRGB(255, 70, 70),
	team = Color3.fromRGB(70, 150, 255),
}

--==================== ПОМОЩНИКИ ИНТЕРФЕЙСА ====================--
local function corner(inst, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = inst
	return c
end

local function outline(inst, color, thickness, transparency)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness or 1
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = inst
	return s
end

local function tween(inst, props, time, style, dir)
	local t = TweenService:Create(inst, TweenInfo.new(
		time or 0.15,
		style or Enum.EasingStyle.Quad,
		dir or Enum.EasingDirection.Out
	), props)
	t:Play()
	return t
end

-- Плавная подсветка при наведении мыши
local function hoverable(obj, base, hover)
	obj.MouseEnter:Connect(function()
		tween(obj, { BackgroundColor3 = hover })
	end)
	obj.MouseLeave:Connect(function()
		tween(obj, { BackgroundColor3 = base })
	end)
end

local function keyName(key)
	if key == Enum.KeyCode.Equals then return "+" end
	if key == Enum.KeyCode.Minus then return "−" end
	return key.Name
end

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
outline(circle, Color3.fromRGB(255, 255, 255), 1.5, 0.35)

local targetInfo = Instance.new("TextLabel")
targetInfo.Name = "TargetInfo"
targetInfo.AnchorPoint = Vector2.new(0.5, 0)
targetInfo.Position = UDim2.new(0.5, 0, 0, 70)
targetInfo.Size = UDim2.fromOffset(260, 28)
targetInfo.BackgroundColor3 = COLORS.bg
targetInfo.BackgroundTransparency = 0.15
targetInfo.Font = Enum.Font.GothamBold
targetInfo.TextSize = 15
targetInfo.TextColor3 = COLORS.enemy
targetInfo.Visible = false
targetInfo.Parent = gui
corner(targetInfo, 8)
outline(targetInfo, COLORS.enemy, 1, 0.6)

local function makeSideButton(name, posY)
	local b = Instance.new("TextButton")
	b.Name = name
	b.AnchorPoint = Vector2.new(1, 0.5)
	b.Position = UDim2.new(1, -20, 0.35, posY)
	b.Size = UDim2.fromOffset(110, 45)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 15
	b.TextColor3 = Color3.new(1, 1, 1)
	b.BackgroundColor3 = COLORS.panel
	b.AutoButtonColor = true
	b.Parent = gui
	corner(b, 10)
	outline(b, COLORS.stroke, 1, 0.1)
	return b
end

local toggleBtn = makeSideButton("AimToggle", 0)
local menuBtn = makeSideButton("MenuButton", 52)
menuBtn.Text = isMobile and "МЕНЮ" or ("МЕНЮ (" .. keyName(CONFIG.MenuKey) .. ")")

local refreshers = {}
local function refreshAll()
	for _, f in ipairs(refreshers) do
		f()
	end
end

-- Вызывается при любом изменении настроек (нужен для автосохранения)
local onSettingsChanged = function() end

local function updateUI()
	local suffix = isMobile and "" or (" (" .. keyName(CONFIG.ToggleKey) .. ")")
	if not hasPass then
		toggleBtn.Text = "AIM: КУПИТЬ"
		toggleBtn.BackgroundColor3 = COLORS.gold
	elseif enabled then
		toggleBtn.Text = "AIM: ВКЛ" .. suffix
		toggleBtn.BackgroundColor3 = Color3.fromRGB(40, 160, 75)
	else
		toggleBtn.Text = "AIM: ВЫКЛ" .. suffix
		toggleBtn.BackgroundColor3 = COLORS.red
	end
	circle.Visible = CONFIG.ShowFOV and hasPass and enabled
	refreshAll()
	onSettingsChanged()
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
speedInfo.Size = UDim2.fromOffset(230, 26)
speedInfo.BackgroundColor3 = COLORS.bg
speedInfo.BackgroundTransparency = 0.15
speedInfo.Font = Enum.Font.GothamBold
speedInfo.TextSize = 14
speedInfo.TextColor3 = COLORS.accent
speedInfo.Visible = false
speedInfo.Parent = gui
corner(speedInfo, 8)

local function isInstant()
	return CONFIG.InstantSnap or CONFIG.Smoothness >= 1
end

local function speedText()
	if isInstant() then
		return "Мгновенная наводка"
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

-- Кнопки «−  MAX  +» под кнопкой меню (удобно на телефоне)
local function makeSpeedButton(name, text, rightOffset)
	local b = makeSideButton(name, 104)
	b.Position = UDim2.new(1, -20 - rightOffset, 0.35, 104)
	b.Size = UDim2.fromOffset(34, 40)
	b.TextSize = 20
	b.Text = text
	return b
end

local speedUpBtn = makeSpeedButton("SpeedUp", "+", 0)
local snapBtn = makeSpeedButton("InstantSnap", "MAX", 38)
snapBtn.TextSize = 12
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

--==================== КОНФИГ (ядро) ====================--
-- Какие настройки входят в конфиг: все простые значения из CONFIG,
-- кроме служебных (геймпасс, имя атрибута команды, сам код) и клавиш.
local SAVE_KEYS = {}
for k, v in pairs(DEFAULTS) do
	local t = typeof(v)
	if (t == "boolean" or t == "number" or t == "string")
		and k ~= "GamePassId" and k ~= "TeamAttribute" and k ~= "Preset" then
		table.insert(SAVE_KEYS, k)
	end
end
table.sort(SAVE_KEYS)

-- Допустимые значения для настроек-выборов
local CHOICES = {
	AimMode = { Override = true, Classic = true },
	AimPart = { Head = true, UpperTorso = true, HumanoidRootPart = true },
	AutoShoot = { Phone = true, All = true, Off = true },
	TeamMode = { Auto = true, Off = true },
}

-- Настройки -> код вида "enabled=1;AimMode=Override;FOV=150;..."
local function exportCode()
	local parts = { "enabled=" .. (enabled and "1" or "0") }
	for _, k in ipairs(SAVE_KEYS) do
		local v = CONFIG[k]
		if type(v) == "boolean" then
			v = v and "1" or "0"
		elseif type(v) == "number" then
			v = string.format("%g", v)
		end
		table.insert(parts, k .. "=" .. tostring(v))
	end
	return table.concat(parts, ";")
end

-- Код -> настройки. Возвращает, сколько параметров применено
local function importCode(code)
	if type(code) ~= "string" then return 0 end
	local applied = 0
	for pair in string.gmatch(code, "[^;]+") do
		local k, v = string.match(pair, "^%s*([%w_]+)%s*=%s*(.-)%s*$")
		if k == "enabled" then
			if v == "1" or v == "0" then
				enabled = (v == "1")
				applied += 1
			end
		elseif k and table.find(SAVE_KEYS, k) then
			local def = DEFAULTS[k]
			if type(def) == "boolean" and (v == "1" or v == "0" or v == "true" or v == "false") then
				CONFIG[k] = (v == "1" or v == "true")
				applied += 1
			elseif type(def) == "number" and tonumber(v) then
				CONFIG[k] = tonumber(v)
				applied += 1
			elseif type(def) == "string" and (not CHOICES[k] or CHOICES[k][v]) then
				CONFIG[k] = v
				applied += 1
			end
		end
	end
	return applied
end

-- Как показывать настройки в списке «Текущие настройки»
local SETTING_VIEW = {
	{ "enabled", "Аим" },
	{ "AimMode", "Режим камеры" },
	{ "AimPart", "Цель" },
	{ "HoldToAim", "Только по ПКМ" },
	{ "HoldThroughWalls", "ПКМ сквозь стены" },
	{ "Smoothness", "Скорость наводки" },
	{ "InstantSnap", "Мгновенная наводка" },
	{ "FOV", "Радиус FOV" },
	{ "Prediction", "Упреждение" },
	{ "StickyTarget", "Держать цель" },
	{ "LockGrace", "Держать после укрытия" },
	{ "AutoShoot", "Автострел" },
	{ "AutoShootAngle", "Точность автострела" },
	{ "AutoShootDelay", "Пауза выстрелов" },
	{ "TeamCheck", "Не целиться в своих" },
	{ "TeamMode", "Команды" },
	{ "WallCheck", "Проверка стен" },
	{ "TargetNPC", "Боты" },
	{ "ESP", "ESP" },
	{ "ESPHighlight", "Подсветка" },
	{ "ESPNames", "Ники" },
	{ "ESPDistance", "Расстояние" },
	{ "ESPHealth", "Полоска HP" },
	{ "ESPTracers", "Линии" },
	{ "ESPTeammates", "Показывать своих" },
	{ "ESPMaxDistance", "Дальность ESP" },
}

local VALUE_NAMES = {
	Override = "Rivals", Classic = "Обычный",
	Head = "Голова", UpperTorso = "Торс", HumanoidRootPart = "Центр",
	Phone = "Телефон", All = "Везде", Off = "Выкл", Auto = "Авто",
}

local UNITS = {
	FOV = " px", LockGrace = " с", AutoShootAngle = "°",
	AutoShootDelay = " с", ESPMaxDistance = " м",
}

local function formatSetting(key)
	local v
	if key == "enabled" then
		v = enabled
	else
		v = CONFIG[key]
	end
	if type(v) == "boolean" then
		return v and "Вкл" or "Выкл", v
	end
	if key == "Smoothness" then
		if CONFIG.InstantSnap then
			return "мгновенно", true
		end
		return math.floor(v * 100 + 0.5) .. "%", true
	end
	if type(v) == "number" then
		return string.format("%g", v) .. (UNITS[key] or ""), true
	end
	if key == "TeamMode" and v == "Off" then
		return "Все враги", true
	end
	return VALUE_NAMES[v] or tostring(v), v ~= "Off"
end

local configStatus = nil     -- строка статуса во вкладке «Конфиг»
local teamInfoLabel = nil    -- строка «Твоя команда…» во вкладке «Аим»

local function setStatus(text, color)
	if configStatus then
		configStatus.Text = text
		configStatus.TextColor3 = color or COLORS.sub
	end
end

-- Автосохранение: любое изменение настроек отмечает время,
-- а через 1.5 с после последнего изменения настройки уходят на сервер.
local persistReady = false   -- true, когда сохранённые настройки уже загружены
local dirtyAt = nil
onSettingsChanged = function()
	if persistReady then
		dirtyAt = os.clock()
	end
end

--==================== МЕНЮ ====================--
local menu = Instance.new("Frame")
menu.Name = "Menu"
menu.AnchorPoint = Vector2.new(0.5, 0.5)
menu.Position = UDim2.fromScale(0.5, 0.5)
menu.Size = UDim2.fromOffset(380, 520)
menu.BackgroundColor3 = Color3.new(1, 1, 1)
menu.Visible = false
menu.ZIndex = 10
menu.Parent = gui
corner(menu, 14)
outline(menu, COLORS.accent, 1.5, 0.55)
local bgGradient = Instance.new("UIGradient")
bgGradient.Color = ColorSequence.new(COLORS.bg2, COLORS.bg)
bgGradient.Rotation = 90
bgGradient.Parent = menu

local uiScale = Instance.new("UIScale")
uiScale.Parent = menu
local baseScale = 1
local function updateScale()
	local cam = workspace.CurrentCamera
	if cam then
		baseScale = math.clamp(cam.ViewportSize.Y / 560, 0.6, 1)
		if menuOpen then
			uiScale.Scale = baseScale
		end
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

-- Заголовок
local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 58)
titleBar.BackgroundTransparency = 1
titleBar.Active = true
titleBar.ZIndex = 11
titleBar.Parent = menu

local logo = Instance.new("TextLabel")
logo.Position = UDim2.fromOffset(14, 12)
logo.Size = UDim2.fromOffset(34, 34)
logo.BackgroundColor3 = COLORS.accent
logo.Font = Enum.Font.GothamBlack
logo.TextSize = 18
logo.Text = "R"
logo.TextColor3 = Color3.new(1, 1, 1)
logo.ZIndex = 12
logo.Parent = titleBar
corner(logo, 10)

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(58, 11)
title.Size = UDim2.new(1, -110, 0, 20)
title.Font = Enum.Font.GothamBlack
title.TextSize = 17
title.TextColor3 = COLORS.text
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "RIVALS MODDED"
title.ZIndex = 12
title.Parent = titleBar

local subtitle = Instance.new("TextLabel")
subtitle.BackgroundTransparency = 1
subtitle.Position = UDim2.fromOffset(58, 31)
subtitle.Size = UDim2.new(1, -110, 0, 16)
subtitle.Font = Enum.Font.GothamMedium
subtitle.TextSize = 12
subtitle.TextColor3 = COLORS.sub
subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.Text = "Аим  •  ESP  •  Конфиг"
subtitle.ZIndex = 12
subtitle.Parent = titleBar

local closeBtn = Instance.new("TextButton")
closeBtn.AnchorPoint = Vector2.new(1, 0.5)
closeBtn.Position = UDim2.new(1, -14, 0.5, 0)
closeBtn.Size = UDim2.fromOffset(30, 30)
closeBtn.BackgroundColor3 = COLORS.panel
closeBtn.AutoButtonColor = false
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 15
closeBtn.TextColor3 = COLORS.text
closeBtn.Text = "X"
closeBtn.ZIndex = 12
closeBtn.Parent = titleBar
corner(closeBtn, 8)
hoverable(closeBtn, COLORS.panel, COLORS.red)

-- Линия под заголовком, тающая к краям
local divider = Instance.new("Frame")
divider.Position = UDim2.fromOffset(14, 58)
divider.Size = UDim2.new(1, -28, 0, 1)
divider.BackgroundColor3 = COLORS.accent
divider.BorderSizePixel = 0
divider.ZIndex = 11
divider.Parent = menu
local divGradient = Instance.new("UIGradient")
divGradient.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.5, 0.2),
	NumberSequenceKeypoint.new(1, 1),
})
divGradient.Parent = divider

-- Вкладки (переключатель-сегмент)
local tabBar = Instance.new("Frame")
tabBar.Position = UDim2.fromOffset(14, 70)
tabBar.Size = UDim2.new(1, -28, 0, 36)
tabBar.BackgroundColor3 = COLORS.panel
tabBar.ZIndex = 11
tabBar.Parent = menu
corner(tabBar, 10)
local tabPadding = Instance.new("UIPadding")
tabPadding.PaddingTop = UDim.new(0, 4)
tabPadding.PaddingBottom = UDim.new(0, 4)
tabPadding.PaddingLeft = UDim.new(0, 4)
tabPadding.PaddingRight = UDim.new(0, 4)
tabPadding.Parent = tabBar
local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0, 4)
tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
tabLayout.Parent = tabBar

local TAB_COUNT = 3
local pages, tabButtons = {}, {}
local tabOrder = 0

local function selectTab(name)
	for n, page in pairs(pages) do
		local on = (n == name)
		page.Visible = on
		tween(tabButtons[n], {
			BackgroundTransparency = on and 0 or 1,
			TextColor3 = on and Color3.new(1, 1, 1) or COLORS.sub,
		})
	end
end

local function makePage(name, label)
	tabOrder += 1
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1 / TAB_COUNT, -3, 1, 0)
	btn.BackgroundColor3 = COLORS.accent
	btn.BackgroundTransparency = 1
	btn.AutoButtonColor = false
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 14
	btn.TextColor3 = COLORS.sub
	btn.Text = label
	btn.LayoutOrder = tabOrder
	btn.ZIndex = 12
	btn.Parent = tabBar
	corner(btn, 7)

	local page = Instance.new("ScrollingFrame")
	page.Position = UDim2.fromOffset(14, 116)
	page.Size = UDim2.new(1, -28, 1, -158)
	page.BackgroundTransparency = 1
	page.BorderSizePixel = 0
	page.ScrollBarThickness = 3
	page.ScrollBarImageColor3 = COLORS.accent
	page.CanvasSize = UDim2.new()
	page.AutomaticCanvasSize = Enum.AutomaticSize.Y
	page.Visible = false
	page.ZIndex = 11
	page.Parent = menu
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = page
	local pad = Instance.new("UIPadding")
	pad.PaddingRight = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 6)
	pad.Parent = page

	pages[name] = page
	tabButtons[name] = btn
	btn.Activated:Connect(function()
		selectTab(name)
	end)
	return page
end

-- Подсказка по клавишам внизу окна
local footer = Instance.new("TextLabel")
footer.BackgroundTransparency = 1
footer.AnchorPoint = Vector2.new(0, 1)
footer.Position = UDim2.new(0, 14, 1, -8)
footer.Size = UDim2.new(1, -28, 0, 28)
footer.Font = Enum.Font.GothamMedium
footer.TextSize = 11
footer.TextWrapped = true
footer.TextColor3 = COLORS.sub
footer.Text = string.format(
	"%s — аим  •  %s — меню  •  %s / %s — скорость  •  %s — мгновенно",
	keyName(CONFIG.ToggleKey), keyName(CONFIG.MenuKey),
	keyName(CONFIG.SpeedUpKey), keyName(CONFIG.SpeedDownKey), keyName(CONFIG.SnapKey)
)
footer.ZIndex = 11
footer.Parent = menu

local currentPage
local order = 0
local function nextOrder()
	order += 1
	return order
end

local function makeLabel(parent, text, size, color, bold)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = bold and Enum.Font.GothamBold or Enum.Font.GothamMedium
	l.TextSize = size or 14
	l.TextColor3 = color or COLORS.text
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.Text = text
	l.Position = UDim2.fromOffset(14, 0)
	l.Size = UDim2.new(1, -84, 1, 0)
	l.ZIndex = 12
	l.Parent = parent
	return l
end

local function makeRow(height)
	local row = Instance.new("TextButton")
	row.Text = ""
	row.AutoButtonColor = false
	row.Size = UDim2.new(1, 0, 0, height)
	row.BackgroundColor3 = COLORS.panel
	row.BorderSizePixel = 0
	row.LayoutOrder = nextOrder()
	row.ZIndex = 11
	row.Parent = currentPage
	corner(row, 9)
	hoverable(row, COLORS.panel, COLORS.panelHover)
	return row
end

local function makeHeader(text)
	local h = Instance.new("Frame")
	h.BackgroundTransparency = 1
	h.Size = UDim2.new(1, 0, 0, 26)
	h.LayoutOrder = nextOrder()
	h.ZIndex = 11
	h.Parent = currentPage

	local bar = Instance.new("Frame")
	bar.AnchorPoint = Vector2.new(0, 0.5)
	bar.Position = UDim2.new(0, 2, 0.5, 2)
	bar.Size = UDim2.fromOffset(3, 12)
	bar.BackgroundColor3 = COLORS.accent
	bar.BorderSizePixel = 0
	bar.ZIndex = 12
	bar.Parent = h
	corner(bar, 2)

	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Position = UDim2.fromOffset(12, 2)
	l.Size = UDim2.new(1, -12, 1, 0)
	l.Font = Enum.Font.GothamBold
	l.TextSize = 12
	l.TextColor3 = COLORS.sub
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = string.upper(text)
	l.ZIndex = 12
	l.Parent = h
end

local function makeToggle(text, key)
	local row = makeRow(42)
	makeLabel(row, text)

	local sw = Instance.new("Frame")
	sw.AnchorPoint = Vector2.new(1, 0.5)
	sw.Position = UDim2.new(1, -12, 0.5, 0)
	sw.Size = UDim2.fromOffset(44, 24)
	sw.BackgroundColor3 = COLORS.off
	sw.ZIndex = 12
	sw.Parent = row
	Instance.new("UICorner", sw).CornerRadius = UDim.new(1, 0)

	local knob = Instance.new("Frame")
	knob.AnchorPoint = Vector2.new(0, 0.5)
	knob.Position = UDim2.new(0, 3, 0.5, 0)
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
		tween(sw, { BackgroundColor3 = on and COLORS.accent or COLORS.off })
		tween(knob, { Position = on and UDim2.new(1, -21, 0.5, 0) or UDim2.new(0, 3, 0.5, 0) })
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

local function makeSlider(text, key, min, max, step, decimals, suffix)
	local page = currentPage
	local row = makeRow(62)
	local label = makeLabel(row, text)
	label.Size = UDim2.new(1, -100, 0, 30)
	label.Position = UDim2.fromOffset(14, 4)

	local pill = Instance.new("TextLabel")
	pill.AnchorPoint = Vector2.new(1, 0)
	pill.Position = UDim2.new(1, -12, 0, 8)
	pill.Size = UDim2.fromOffset(64, 22)
	pill.BackgroundColor3 = COLORS.bg
	pill.Font = Enum.Font.GothamBold
	pill.TextSize = 13
	pill.TextColor3 = COLORS.accent
	pill.ZIndex = 12
	pill.Parent = row
	corner(pill, 6)

	local bar = Instance.new("Frame")
	bar.Position = UDim2.new(0, 14, 0, 44)
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
	outline(knob, COLORS.accent, 2, 0)

	local hit = Instance.new("TextButton")
	hit.Text = ""
	hit.BackgroundTransparency = 1
	hit.Position = UDim2.fromOffset(4, 32)
	hit.Size = UDim2.new(1, -8, 0, 30)
	hit.ZIndex = 15
	hit.Parent = row

	local fmt = "%." .. decimals .. "f" .. (suffix or "")
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
		local rel = math.clamp((CONFIG[key] - min) / (max - min), 0, 1)
		fill.Size = UDim2.new(rel, 0, 1, 0)
		knob.Position = UDim2.new(rel, 0, 0.5, 0)
		pill.Text = string.format(fmt, CONFIG[key])
	end

	table.insert(refreshers, refresh)
	refresh()
end

local function makeChoice(text, key, options)
	local row = makeRow(42)
	makeLabel(row, text).Size = UDim2.new(1, -150, 1, 0)

	local btn = Instance.new("TextButton")
	btn.AnchorPoint = Vector2.new(1, 0.5)
	btn.Position = UDim2.new(1, -12, 0.5, 0)
	btn.Size = UDim2.fromOffset(124, 26)
	btn.BackgroundColor3 = COLORS.bg
	btn.AutoButtonColor = false
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 13
	btn.TextColor3 = COLORS.accent
	btn.ZIndex = 12
	btn.Parent = row
	corner(btn, 7)
	outline(btn, COLORS.accent, 1, 0.5)

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
				btn.Text = opt[2] .. "  ›"
			end
		end
	end

	table.insert(refreshers, refresh)
	refresh()
end

local function makeButton(text, color, callback)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, 0, 0, 40)
	b.BackgroundColor3 = color
	b.AutoButtonColor = false
	b.Font = Enum.Font.GothamBold
	b.TextSize = 14
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Text = text
	b.LayoutOrder = nextOrder()
	b.ZIndex = 12
	b.Parent = currentPage
	corner(b, 9)
	hoverable(b, color, color:Lerp(Color3.new(1, 1, 1), 0.12))
	b.Activated:Connect(callback)
	return b
end

local function makeHint(text)
	local hint = Instance.new("TextLabel")
	hint.BackgroundTransparency = 1
	hint.Size = UDim2.new(1, 0, 0, 0)
	hint.AutomaticSize = Enum.AutomaticSize.Y
	hint.Font = Enum.Font.Gotham
	hint.TextSize = 12
	hint.TextColor3 = COLORS.sub
	hint.TextWrapped = true
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.Text = text
	hint.LayoutOrder = nextOrder()
	hint.ZIndex = 11
	hint.Parent = currentPage
	return hint
end

-- Список «Текущие настройки»: название слева, значение справа
local function makeSettingsList()
	local box = Instance.new("Frame")
	box.Size = UDim2.new(1, 0, 0, 0)
	box.AutomaticSize = Enum.AutomaticSize.Y
	box.BackgroundColor3 = COLORS.panel
	box.LayoutOrder = nextOrder()
	box.ZIndex = 11
	box.Parent = currentPage
	corner(box, 9)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.Parent = box
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 2)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = box

	for i, item in ipairs(SETTING_VIEW) do
		local key, title = item[1], item[2]
		local line = Instance.new("Frame")
		line.BackgroundTransparency = 1
		line.Size = UDim2.new(1, 0, 0, 22)
		line.LayoutOrder = i
		line.ZIndex = 12
		line.Parent = box

		local name = Instance.new("TextLabel")
		name.BackgroundTransparency = 1
		name.Size = UDim2.new(0.62, 0, 1, 0)
		name.Font = Enum.Font.GothamMedium
		name.TextSize = 13
		name.TextColor3 = COLORS.sub
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.Text = title
		name.ZIndex = 12
		name.Parent = line

		local value = Instance.new("TextLabel")
		value.BackgroundTransparency = 1
		value.AnchorPoint = Vector2.new(1, 0)
		value.Position = UDim2.fromScale(1, 0)
		value.Size = UDim2.new(0.38, 0, 1, 0)
		value.Font = Enum.Font.GothamBold
		value.TextSize = 13
		value.TextXAlignment = Enum.TextXAlignment.Right
		value.ZIndex = 12
		value.Parent = line

		table.insert(refreshers, function()
			local text, active = formatSetting(key)
			value.Text = text
			value.TextColor3 = active and COLORS.text or COLORS.sub
		end)
	end
end

-- Поле с кодом (можно выделить и скопировать, или вставить свой)
local function makeCodeBox(placeholder, height)
	local box = Instance.new("TextBox")
	box.Size = UDim2.new(1, 0, 0, height)
	box.BackgroundColor3 = COLORS.bg
	box.ClearTextOnFocus = false
	box.MultiLine = true
	box.TextWrapped = true
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.TextYAlignment = Enum.TextYAlignment.Top
	box.Font = Enum.Font.Code
	box.TextSize = 12
	box.TextColor3 = COLORS.text
	box.PlaceholderText = placeholder
	box.PlaceholderColor3 = COLORS.sub
	box.Text = ""
	box.LayoutOrder = nextOrder()
	box.ZIndex = 12
	box.Parent = currentPage
	corner(box, 9)
	outline(box, COLORS.stroke, 1, 0)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = box
	return box
end

--------- Вкладка АИМ ---------
currentPage = makePage("aim", "Аим")
makeHeader("Основное")
makeToggle("Аим включён", "enabled")
makeChoice("Режим камеры", "AimMode", {
	{ "Override", "Rivals" },
	{ "Classic", "Обычный" },
})
makeChoice("Цель", "AimPart", {
	{ "Head", "Голова" },
	{ "UpperTorso", "Торс" },
	{ "HumanoidRootPart", "Центр" },
})
makeToggle("Наводка только по ПКМ", "HoldToAim")
makeToggle("ПКМ: сквозь стены", "HoldThroughWalls")

makeHeader("Скорость наводки")
makeSlider("Скорость", "Smoothness", 0.05, 1, 0.05, 2)
makeToggle("Мгновенная наводка", "InstantSnap")

makeHeader("Захват")
makeSlider("Радиус FOV", "FOV", 30, 400, 5, 0, " px")
makeSlider("Упреждение", "Prediction", 0, 0.3, 0.01, 2)
makeToggle("Держать цель", "StickyTarget")
makeSlider("Держать после укрытия", "LockGrace", 0, 1, 0.05, 2, " с")

makeHeader("Автострел")
makeChoice("Автострел", "AutoShoot", {
	{ "Phone", "Телефон" },
	{ "All", "Везде" },
	{ "Off", "Выкл" },
})
makeSlider("Точность", "AutoShootAngle", 0.5, 10, 0.5, 1, "°")
makeSlider("Пауза между выстрелами", "AutoShootDelay", 0.03, 0.5, 0.01, 2, " с")

makeHeader("Проверки")
makeToggle("Не целиться в своих", "TeamCheck")
makeChoice("Команды", "TeamMode", {
	{ "Auto", "Авто" },
	{ "Off", "Все враги" },
})
teamInfoLabel = makeHint("Открой меню на секунду — здесь появится твоя команда")
makeToggle("Не целиться сквозь стены", "WallCheck")
makeToggle("Целиться в ботов", "TargetNPC")
makeToggle("Показывать круг FOV", "ShowFOV")
makeToggle("Показывать цель сверху", "ShowTargetInfo")

--------- Вкладка ESP ---------
currentPage = makePage("esp", "ESP")
makeHeader("Где находятся игроки")
makeToggle("ESP включён", "ESP")
makeToggle("Подсветка сквозь стены", "ESPHighlight")
makeToggle("Ники", "ESPNames")
makeToggle("Расстояние", "ESPDistance")
makeToggle("Полоска HP", "ESPHealth")
makeToggle("Линии к игрокам", "ESPTracers")
makeToggle("Показывать своих", "ESPTeammates")
makeSlider("Макс. дистанция", "ESPMaxDistance", 50, 3000, 50, 0, " м")

--------- Вкладка КОНФИГ ---------
currentPage = makePage("cfg", "Конфиг")
makeHeader("Текущие настройки")
makeSettingsList()

makeHeader("Автонастройка")
makeHint("Настройки сохраняются сами и загружаются при следующем входе. Ниже код текущих настроек: его можно вставить в CONFIG.Preset в начале скрипта — тогда он применится у игроков, у которых ещё нет своих сохранённых настроек.")
local exportBox = makeCodeBox("", 92)
exportBox.Text = exportCode()
table.insert(refreshers, function()
	if not exportBox:IsFocused() then
		exportBox.Text = exportCode()
	end
end)
-- Поле только для копирования: после правки возвращаем настоящий код
exportBox.FocusLost:Connect(function()
	exportBox.Text = exportCode()
end)

makeHeader("Применить код")
local importBox = makeCodeBox("Вставь сюда код конфига", 64)
makeButton("Применить код", COLORS.accent, function()
	local n = importCode(importBox.Text)
	if n > 0 then
		applyConfig()
		importBox.Text = ""
		setStatus("Код применён: " .. n .. " параметров", COLORS.accent)
	else
		setStatus("Код не распознан — скопируй его целиком из поля выше", COLORS.red)
	end
end)
configStatus = makeHint("")
configStatus.Font = Enum.Font.GothamBold

makeHeader("Сброс")
makeButton("Сбросить к стандартным настройкам", COLORS.red, function()
	for _, k in ipairs(SAVE_KEYS) do
		CONFIG[k] = DEFAULTS[k]
	end
	enabled = true
	applyConfig()
	setStatus("Настройки сброшены к стандартным", COLORS.sub)
end)

selectTab("aim")

local function setMenu(open)
	if open and not hasPass then
		MarketplaceService:PromptGamePassPurchase(player, CONFIG.GamePassId)
		return
	end
	if open == menuOpen then return end
	menuOpen = open
	if open then
		menu.Visible = true
		uiScale.Scale = baseScale * 0.9
		tween(uiScale, { Scale = baseScale }, 0.2, Enum.EasingStyle.Back)
		refreshAll()
	else
		local t = tween(uiScale, { Scale = baseScale * 0.9 }, 0.12)
		t.Completed:Connect(function()
			if not menuOpen then
				menu.Visible = false
			end
		end)
	end
end

menuBtn.Activated:Connect(function()
	setMenu(not menuOpen)
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

--==================== СОХРАНЕНИЕ И АВТОНАСТРОЙКА ====================--
-- Что применяется при входе (по порядку):
--   1) сохранённые настройки игрока (если есть серверный скрипт AimBotConfigServer);
--   2) код из CONFIG.Preset;
--   3) значения по умолчанию.
local function applyPreset()
	if CONFIG.Preset == "" then return false end
	local n = importCode(CONFIG.Preset)
	applyConfig()
	return n > 0
end

task.spawn(function()
	local remote = ReplicatedStorage:WaitForChild("AimBotConfig", 8)
	if not remote then
		if applyPreset() then
			setStatus("Применён CONFIG.Preset. Чтобы настройки сохранялись между входами, добавь AimBotConfigServer", COLORS.gold)
		else
			setStatus("Настройки не сохранятся после выхода: нет серверного скрипта AimBotConfigServer", COLORS.gold)
		end
		return
	end

	local ok, res = pcall(function()
		return remote:InvokeServer("load")
	end)
	if not (ok and type(res) == "table" and res.ok) then
		applyPreset()
		setStatus("Хранилище недоступно — настройки не сохранятся. В Studio включи доступ к API (см. серверный скрипт)", COLORS.red)
		return
	end

	if type(res.code) == "string" and res.code ~= "" then
		local n = importCode(res.code)
		applyConfig()
		setStatus("Загружены твои сохранённые настройки (" .. n .. " параметров)", COLORS.accent)
	elseif applyPreset() then
		setStatus("Применён CONFIG.Preset. Дальше настройки сохраняются сами", COLORS.accent)
	else
		setStatus("Настройки сохраняются автоматически", COLORS.sub)
	end

	local lastSaved = exportCode()
	persistReady = true

	while true do
		task.wait(1)
		if dirtyAt and os.clock() - dirtyAt > 1.5 then
			dirtyAt = nil
			local code = exportCode()
			if code ~= lastSaved then
				local okSave, saved = pcall(function()
					return remote:InvokeServer("save", code)
				end)
				if okSave and saved then
					lastSaved = code
					setStatus("Сохранено в " .. os.date("%H:%M"), COLORS.accent)
				else
					dirtyAt = os.clock() -- повторим через пару секунд
					setStatus("Не удалось сохранить, пробую ещё раз", COLORS.red)
				end
			end
		end
	end
end)

--==================== УПРАВЛЕНИЕ ====================--
UserInputService.InputBegan:Connect(function(input, processed)
	if input.UserInputType == CONFIG.AimHoldButton then
		holding = true
		return
	end
	if processed then return end -- не реагировать, когда пишешь в чат
	local key = input.KeyCode
	if key == CONFIG.ToggleKey then
		toggle()
	elseif key == CONFIG.MenuKey then
		setMenu(not menuOpen)
	elseif key == CONFIG.SpeedUpKey or key == Enum.KeyCode.KeypadPlus then
		changeSpeed(1)
	elseif key == CONFIG.SpeedDownKey or key == Enum.KeyCode.KeypadMinus then
		changeSpeed(-1)
	elseif key == CONFIG.SnapKey then
		toggleSnap()
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == CONFIG.AimHoldButton then
		holding = false
	end
end)

-- Если окно игры потеряло фокус с зажатой кнопкой — отпускаем наводку
UserInputService.WindowFocusReleased:Connect(function()
	holding = false
end)

--==================== ЦЕЛИ ====================--
-- Определение команды. Игры делают команды по-разному, поэтому проверяем
-- по очереди: атрибуты и значения (StringValue и т.п.) у игрока и персонажа,
-- leaderstats, затем Teams и TeamColor.
local TEAM_FIELDS = { CONFIG.TeamAttribute, "Team", "TeamName", "TeamId", "TeamID", "TeamColor", "Side", "Squad" }

local function readTeam(inst)
	if not inst then return nil end
	for _, field in ipairs(TEAM_FIELDS) do
		local ok, attr = pcall(inst.GetAttribute, inst, field)
		if ok and attr ~= nil and attr ~= "" then
			return tostring(attr)
		end
		local v = inst:FindFirstChild(field)
		if v and v:IsA("ValueBase") then
			local val = v.Value
			if typeof(val) == "Instance" then
				return val.Name
			elseif val ~= nil and val ~= "" then
				return tostring(val)
			end
		end
	end
	return nil
end

-- Ключ команды игрока и как он найден (nil, если команды нет)
local function teamOf(plr)
	if not plr then return nil, nil end
	local k = readTeam(plr)
	if k then return "a:" .. k, "атрибут игрока" end
	k = readTeam(plr.Character)
	if k then return "a:" .. k, "атрибут персонажа" end
	k = readTeam(plr:FindFirstChild("leaderstats"))
	if k then return "a:" .. k, "leaderstats" end
	if plr.Team then return "t:" .. plr.Team.Name, "Teams" end
	if not plr.Neutral then return "c:" .. plr.TeamColor.Name, "TeamColor" end
	return nil, nil
end

-- Команды всех игроков пересчитываются 4 раза в секунду, а не на каждую проверку
local teamCache = { at = -1, keys = {}, mine = nil, ffa = false }
local function updateTeamCache()
	if os.clock() - teamCache.at < 0.25 then return end
	teamCache.at = os.clock()
	local keys = {}
	local mine = teamOf(player)
	local all, same = 0, 0
	for _, plr in ipairs(Players:GetPlayers()) do
		local k = teamOf(plr)
		keys[plr] = k or false
		all += 1
		if k ~= nil and k == mine then
			same += 1
		end
	end
	teamCache.keys = keys
	teamCache.mine = mine
	-- Все игроки в одной «команде» (лобби, каждый за себя) — значит своих нет
	teamCache.ffa = all >= 3 and same == all
end

local function isTeammate(plr)
	if not plr or plr == player then return false end
	if CONFIG.TeamMode == "Off" then return false end
	updateTeamCache()
	if teamCache.ffa or not teamCache.mine then return false end
	local theirs = teamCache.keys[plr]
	if theirs == nil then
		theirs = teamOf(plr) or false
	end
	return theirs ~= false and theirs == teamCache.mine
end

-- Строка во вкладке «Аим»: какую команду нашёл скрипт
task.spawn(function()
	while true do
		task.wait(1)
		if teamInfoLabel and menuOpen then
			local text
			if CONFIG.TeamMode == "Off" then
				text = "Команды выключены: все игроки — враги"
			else
				updateTeamCache()
				local key, how = teamOf(player)
				local mates, foes = 0, 0
				for _, plr in ipairs(Players:GetPlayers()) do
					if plr ~= player then
						if isTeammate(plr) then
							mates += 1
						else
							foes += 1
						end
					end
				end
				if not key then
					text = "Команда не найдена — все игроки считаются врагами"
				else
					text = string.format("Твоя команда: %s (%s)%s\nСвоих: %d  •  Врагов: %d",
						string.sub(key, 3), how,
						teamCache.ffa and ", все в одной — каждый за себя" or "",
						mates, foes)
				end
			end
			teamInfoLabel.Text = text
		end
	end
end)

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
	-- Зажата ПКМ и включено «сквозь стены» — стены не мешают
	if holding and CONFIG.HoldThroughWalls and not isMobile then return true end
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
	if not (hasPass and enabled) or menuOpen then return false end
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
		targetInfo.Text = "Цель: " .. lockedTarget.name .. "  •  " .. d .. " м"
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
