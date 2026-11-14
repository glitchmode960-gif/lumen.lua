--!nonstrict
--[[
 LUMEN UI v1.0 — GUI-библиотека для executors (один файл, loadstring). Оригинальный дизайн:
 сайдбар со счётчиками, статус-чип, hero-карточка, плоские строки, плавающие чипы, вотермарка.
 Без читерских функций: только интерфейс.

 local Lumen = loadstring(game:HttpGet("ТВОЯ_RAW_ССЫЛКА"))()
 local win = Lumen:CreateWindow({ Title = "lumen", Suffix = ".ui", Subtitle = "welcome back", Status = "Ready" })

 local home = win:Home({ Title = "lumen", Suffix = ".ui", Welcome = "Welcome back", Link = "discord.gg/..." })
 home:Preset({ Name = "Preset", Presets = { Soft = { speed = 20 }, Fast = { speed = 80 } } })

 local tab = win:AddTab("Player")
 tab:Section("Movement")
 local t = tab:Toggle({ Name = "Boost", Flag = "boost", Chip = true, Callback = function(on) end })
 tab:Slider({ Name = "Speed", Flag = "speed", Min = 16, Max = 100, Default = 16, Callback = function(v) end })
 tab:Dropdown({ Name = "Mode", Flag = "mode", Options = { "A", "B" }, Default = "A" })
 win:ConfigTab()                         -- пресеты: сохранить / загрузить / удалить, автозагрузка сессии
 win:Watermark({ Text = "lumen.ui" })    -- вотермарка справа сверху (+ FPS)
]]

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")
local GuiService = game:GetService("GuiService")
local LP = Players.LocalPlayer

local Lumen = { Version = "1.0.0", Animations = true }
local genv = (typeof(getgenv) == "function" and getgenv()) or _G
if genv.__LumenUI and genv.__LumenUI ~= Lumen then pcall(function() genv.__LumenUI:Unload() end) end
genv.__LumenUI = Lumen

----------------------------------------------------------------
-- ХЕЛПЕРЫ
----------------------------------------------------------------
local CONNS = {}
local function on(signal, fn)
	local c = signal:Connect(fn)
	CONNS[#CONNS + 1] = c
	return c
end

local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end

local function new(class, props, children)
	local o = Instance.new(class)
	local parent
	for k, v in pairs(props or {}) do
		if k == "Parent" then parent = v else o[k] = v end
	end
	for _, c in ipairs(children or {}) do c.Parent = o end
	if parent then o.Parent = parent end
	return o
end

local function corner(r) return new("UICorner", { CornerRadius = UDim.new(0, r) }) end
local function pill() return new("UICorner", { CornerRadius = UDim.new(1, 0) }) end
local function pad(t, r, b, l)
	return new("UIPadding", { PaddingTop = UDim.new(0, t), PaddingRight = UDim.new(0, r), PaddingBottom = UDim.new(0, b), PaddingLeft = UDim.new(0, l) })
end

local function safe(fn, ...)
	if type(fn) ~= "function" then return end
	local ok, err = pcall(fn, ...)
	if not ok then warn("[Lumen] " .. tostring(err)) end
end

local function isPointer(i) return i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch end
local function isMove(i) return i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch end
local function viewport() return workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(800, 450) end

local function hex(c)
	return string.format("%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

local function tween(o, t, props, style, dir)
	if not Lumen.Animations then
		for k, v in pairs(props) do pcall(function() o[k] = v end) end
		return nil
	end
	local tw = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

----------------------------------------------------------------
-- ТЕМА (изменяемая палитра + привязки)
----------------------------------------------------------------
local T = {
	bg = rgb(13, 14, 18), panel = rgb(18, 19, 24), card = rgb(24, 26, 32), field = rgb(31, 33, 41), line = rgb(42, 45, 55),
	text = rgb(236, 238, 244), sub = rgb(128, 133, 148), accent = rgb(176, 226, 52),
	good = rgb(86, 214, 120), bad = rgb(255, 96, 110), warn = rgb(255, 190, 80),
}

local gui -- ScreenGui, задаётся ниже
local BOUND, HOOKS = {}, {}

-- привязка свойства к значению палитры: fn() -> значение
local function bind(obj, prop, fn)
	BOUND[#BOUND + 1] = { obj = obj, prop = prop, fn = fn }
	pcall(function() obj[prop] = fn() end)
end
local function bindc(obj, prop, key) bind(obj, prop, function() return T[key] end) end
-- произвольный пересчёт при смене акцента (для анимируемых элементов)
local function hookAccent(obj, fn)
	HOOKS[#HOOKS + 1] = { obj = obj, fn = fn }
end

local function tint(color, k) return T.bg:Lerp(color, k) end

function Lumen:SetAccent(color)
	if typeof(color) ~= "Color3" then return end
	T.accent = color
	local alive = {}
	for _, b in ipairs(BOUND) do
		local ok = pcall(function()
			if gui and not b.obj:IsDescendantOf(gui) then error("gone") end
			b.obj[b.prop] = b.fn()
		end)
		if ok then alive[#alive + 1] = b end
	end
	BOUND = alive
	local hk = {}
	for _, h in ipairs(HOOKS) do
		local ok = pcall(function()
			if gui and not h.obj:IsDescendantOf(gui) then error("gone") end
			h.fn()
		end)
		if ok then hk[#hk + 1] = h end
	end
	HOOKS = hk
end

local function txt(parent, text, size, key, props)
	local l = new("TextLabel", {
		BackgroundTransparency = 1, Text = text or "", TextSize = size or 14, Font = Enum.Font.GothamMedium,
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = parent,
	})
	for k, v in pairs(props or {}) do l[k] = v end
	bindc(l, "TextColor3", key or "text")
	return l
end

----------------------------------------------------------------
-- ЭКРАН И СЛОИ
----------------------------------------------------------------
gui = new("ScreenGui", {
	Name = "Lumen_" .. tostring(math.random(1000, 9999)), ResetOnSpawn = false, IgnoreGuiInset = true,
	DisplayOrder = 9000, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})
do
	local placed = false
	if typeof(gethui) == "function" then
		local ok, u = pcall(gethui)
		if ok and u then placed = pcall(function() gui.Parent = u end) and gui.Parent == u end
	end
	if not placed then placed = pcall(function() gui.Parent = CoreGui end) and gui.Parent == CoreGui end
	if not placed then gui.Parent = LP:WaitForChild("PlayerGui") end
end

local function layer(z) return new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = z, Parent = gui }) end
local MainLayer, ChipLayer, PopLayer, ToastLayer = layer(1), layer(2), layer(4), layer(5)

local State = { scale = 1 }

-- перетаскивание: onTap вызывается, если палец не двигался
local function makeDraggable(handle, target, onTap, onDrop)
	local dragging, moved, ds, sp = false, false, nil, nil
	on(handle.InputBegan, function(i)
		if not isPointer(i) then return end
		dragging, moved, ds, sp = true, false, i.Position, target.Position
		local ch
		ch = i.Changed:Connect(function()
			if i.UserInputState == Enum.UserInputState.End then
				dragging = false
				ch:Disconnect()
				if not moved and onTap then onTap() end
				if moved and onDrop then onDrop() end
			end
		end)
	end)
	on(UIS.InputChanged, function(i)
		if dragging and isMove(i) then
			local d = i.Position - ds
			if d.Magnitude > 7 then moved = true end
			if moved then target.Position = UDim2.new(sp.X.Scale, sp.X.Offset + d.X, sp.Y.Scale, sp.Y.Offset + d.Y) end
		end
	end)
end

----------------------------------------------------------------
-- УВЕДОМЛЕНИЯ (снизу по центру)
----------------------------------------------------------------
local toastBox = new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -20), Size = UDim2.fromOffset(320, 300), BackgroundTransparency = 1, Parent = ToastLayer })
new("UIListLayout", { Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Bottom, SortOrder = Enum.SortOrder.LayoutOrder, Parent = toastBox })
local toastN = 0

-- Lumen:Notify({ Title, Text, Type = "Info|Success|Error|Warning", Duration })
function Lumen:Notify(o)
	if type(o) ~= "table" then o = { Text = tostring(o) } end
	toastN += 1
	local col = o.Type == "Error" and T.bad or o.Type == "Warning" and T.warn or o.Type == "Success" and T.good or T.accent
	local f = new("CanvasGroup", {
		Size = UDim2.fromOffset(0, 40), AutomaticSize = Enum.AutomaticSize.X, BorderSizePixel = 0, GroupTransparency = 1,
		LayoutOrder = toastN, Parent = toastBox,
	}, { corner(20), pad(0, 16, 0, 12) })
	bindc(f, "BackgroundColor3", "panel")
	local st = new("UIStroke", { Thickness = 1, Color = col, Transparency = 0.35, Parent = f })
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8), Parent = f })
	new("Frame", { Size = UDim2.fromOffset(8, 8), BackgroundColor3 = col, BorderSizePixel = 0, Parent = f }, { pill() })
	local text = o.Title and (o.Title .. (o.Text and ("  " .. o.Text) or "")) or (o.Text or "")
	txt(f, text, 13, "text", { Size = UDim2.fromOffset(0, 40), AutomaticSize = Enum.AutomaticSize.X, TextTruncate = Enum.TextTruncate.None })
	tween(f, 0.25, { GroupTransparency = 0 })
	task.delay(o.Duration or 3, function()
		tween(f, 0.25, { GroupTransparency = 1 })
		task.wait(0.3)
		f:Destroy()
	end)
	local kids = {}
	for _, c in ipairs(toastBox:GetChildren()) do if c:IsA("CanvasGroup") then kids[#kids + 1] = c end end
	while #kids > 4 do table.remove(kids, 1):Destroy() end
end

----------------------------------------------------------------
-- ВСПЛЫВАЮЩИЕ ПАНЕЛИ: список и выбор цвета
----------------------------------------------------------------
local popup
local function closePopup()
	if popup then
		local p = popup
		popup = nil
		p:Destroy()
	end
end

local function popupFrame(anchor, w, h)
	closePopup()
	local sc = State.scale
	local overlay = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 10, Parent = PopLayer })
	overlay.MouseButton1Click:Connect(closePopup)
	local ap, as = anchor.AbsolutePosition, anchor.AbsoluteSize
	local v = viewport()
	local below = ap.Y + as.Y + 4
	local y = (below + h * sc <= v.Y - 6) and below or math.max(6, ap.Y - h * sc - 4)
	local x = math.clamp(ap.X + as.X - w * sc, 6, math.max(6, v.X - w * sc - 6))
	local card = new("CanvasGroup", {
		Size = UDim2.fromOffset(w, h), Position = UDim2.fromOffset(x, y), BorderSizePixel = 0, GroupTransparency = 1, Active = true, ZIndex = 11, Parent = overlay,
	}, { corner(10), new("UIScale", { Scale = sc }) })
	bindc(card, "BackgroundColor3", "panel")
	local st = new("UIStroke", { Thickness = 1, Parent = card })
	bindc(st, "Color", "line")
	tween(card, 0.15, { GroupTransparency = 0 })
	popup = overlay
	return card
end

local function openList(anchor, options, isSelected, onPick, multi)
	local itemH = 30
	local rows = math.min(#options, 8)
	local card = popupFrame(anchor, math.max(anchor.AbsoluteSize.X / State.scale, 150), rows * (itemH + 2) + 10)
	local list = new("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, Parent = card,
	}, { pad(5, 5, 5, 5) })
	bindc(list, "ScrollBarImageColor3", "accent")
	new("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
	local buttons = {}
	local function paint()
		for opt, b in pairs(buttons) do
			local sel = isSelected(opt)
			b.BackgroundTransparency = sel and 0 or 1
			b.TextColor3 = sel and T.accent or T.text
		end
	end
	for i, opt in ipairs(options) do
		local b = new("TextButton", {
			Size = UDim2.new(1, 0, 0, itemH), BackgroundColor3 = T.field, BorderSizePixel = 0, Text = tostring(opt),
			Font = Enum.Font.GothamMedium, TextSize = 13, AutoButtonColor = false, LayoutOrder = i, Parent = list,
		}, { corner(7), pad(0, 8, 0, 10) })
		b.TextXAlignment = Enum.TextXAlignment.Left
		buttons[opt] = b
		b.MouseButton1Click:Connect(function()
			onPick(opt)
			paint()
			if not multi then closePopup() end
		end)
	end
	paint()
end

-- выбор цвета: три полосы H / S / V
local function openColor(anchor, color, onChange)
	local card = popupFrame(anchor, 230, 130)
	local h, s, v = Color3.toHSV(color)
	local function apply() onChange(Color3.fromHSV(h, s, v)) end
	local function bar(y, label, getKeys, setValue)
		txt(card, label, 12, "sub", { Position = UDim2.fromOffset(12, y - 2), Size = UDim2.fromOffset(16, 18) })
		local track = new("Frame", { Position = UDim2.fromOffset(32, y + 3), Size = UDim2.new(1, -46, 0, 8), BorderSizePixel = 0, BackgroundColor3 = Color3.new(1, 1, 1), Parent = card }, { pill() })
		new("UIGradient", { Color = getKeys(), Parent = track })
		local knob = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(14, 14), BorderSizePixel = 0, BackgroundColor3 = Color3.new(1, 1, 1), Parent = track }, { pill() })
		local hit = new("TextButton", { Position = UDim2.fromOffset(32, y - 6), Size = UDim2.new(1, -46, 0, 28), BackgroundTransparency = 1, Text = "", Parent = card })
		local dragging = false
		local function fromInput(i)
			local f = math.clamp((i.Position.X - track.AbsolutePosition.X) / math.max(1, track.AbsoluteSize.X), 0, 1)
			setValue(f)
			apply()
		end
		hit.InputBegan:Connect(function(i) if isPointer(i) then dragging = true; fromInput(i) end end)
		local c1 = UIS.InputChanged:Connect(function(i) if dragging and isMove(i) then fromInput(i) end end)
		local c2 = UIS.InputEnded:Connect(function(i) if isPointer(i) then dragging = false end end)
		card.Destroying:Connect(function() c1:Disconnect(); c2:Disconnect() end)
		return knob
	end
	local kh = bar(18, "H", function()
		local pts = {}
		for i = 0, 6 do pts[#pts + 1] = ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(i / 6, 1, 1)) end
		return ColorSequence.new(pts)
	end, function(f) h = f end)
	local ks = bar(54, "S", function() return ColorSequence.new(Color3.new(1, 1, 1), Color3.fromHSV(h, 1, 1)) end, function(f) s = f end)
	local kv = bar(90, "V", function() return ColorSequence.new(Color3.new(0, 0, 0), Color3.fromHSV(h, s, 1)) end, function(f) v = f end)
	local function place()
		kh.Position = UDim2.fromScale(h, 0.5)
		ks.Position = UDim2.fromScale(s, 0.5)
		kv.Position = UDim2.fromScale(v, 0.5)
	end
	place()
	local conn = RunService.RenderStepped:Connect(place)
	card.Destroying:Connect(function() conn:Disconnect() end)
end

----------------------------------------------------------------
-- ОКНО И ВКЛАДКИ
----------------------------------------------------------------
local Window, Tab = {}, {}
Window.__index = Window
Tab.__index = Tab

local function fsOk()
	return typeof(writefile) == "function" and typeof(readfile) == "function" and typeof(isfile) == "function"
end

local function decodeFile(path)
	if not fsOk() or not isfile(path) then return nil end
	local ok, data = pcall(function() return HttpService:JSONDecode(readfile(path)) end)
	return ok and type(data) == "table" and data or nil
end

function Window:_saveSettings()
	if not fsOk() then return end
	local a = T.accent
	pcall(function()
		writefile(self.fileSettings, HttpService:JSONEncode({ autoload = self.settings.autoload, accent = { r = a.R, g = a.G, b = a.B } }))
	end)
end

-- сессия сохраняется после каждого изменения (с задержкой) и поднимается при запуске, если включена автозагрузка
function Window:_queueSession()
	if not fsOk() then return end
	self._sesTok = (self._sesTok or 0) + 1
	local my = self._sesTok
	task.delay(1, function()
		if my == self._sesTok then pcall(function() writefile(self.fileSession, HttpService:JSONEncode(self.flags)) end) end
	end)
end

function Window:_set(flag, value)
	if not flag then return end
	self.flags[flag] = value
	self:_queueSession()
end

function Window:_register(flag, setter)
	if flag then self.setters[flag] = setter end
end

function Window:_lo()
	self._order += 1
	return self._order
end

function Lumen:CreateWindow(o)
	o = o or {}
	local title, suffix = o.Title or "lumen", o.Suffix or ".ui"
	local id = (tostring(o.Id or title):gsub("[^%w_%-]", "_"))
	local win = setmetatable({
		id = id, tabs = {}, flags = {}, setters = {}, chips = {}, keybinds = {}, session = {}, settings = { autoload = false },
		_order = 1, current = nil, open = true,
		fileSettings = "Lumen_" .. id .. "_settings.json", fileSession = "Lumen_" .. id .. "_session.json", cfgPrefix = "Lumen_" .. id .. "_cfg_",
	}, Window)
	Lumen.Window = win

	-- сохранённые настройки: акцент и автозагрузка сессии
	local st = decodeFile(win.fileSettings)
	if st then
		win.settings.autoload = st.autoload == true
		if type(st.accent) == "table" and st.accent.r then Lumen:SetAccent(Color3.new(st.accent.r, st.accent.g, st.accent.b)) end
	end
	if o.Accent then Lumen:SetAccent(o.Accent) end
	if win.settings.autoload then win.session = decodeFile(win.fileSession) or {} end

	local W, H = o.Width or 620, o.Height or 360
	local main = new("CanvasGroup", {
		Size = UDim2.fromOffset(W, H), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), BorderSizePixel = 0, Parent = MainLayer,
	}, { corner(14) })
	bindc(main, "BackgroundColor3", "bg")
	local mstroke = new("UIStroke", { Thickness = 1, Parent = main })
	bindc(mstroke, "Color", "line")
	local scale = new("UIScale", { Parent = main })
	local function fit()
		local v = viewport()
		local s = math.clamp(math.min((v.X - 16) / W, (v.Y - 16) / H, 1), 0.5, 1) * (o.Scale or 1)
		scale.Scale, State.scale = s, s
	end
	fit()
	if workspace.CurrentCamera then on(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"), fit) end
	win.main = main

	-- сайдбар
	local SIDE = 184
	local side = new("Frame", { Size = UDim2.new(0, SIDE, 1, 0), BackgroundTransparency = 1, Parent = main })
	local logo = new("TextLabel", {
		Position = UDim2.fromOffset(22, 12), Size = UDim2.new(1, -30, 0, 34), BackgroundTransparency = 1, RichText = true,
		Font = Enum.Font.GothamMedium, TextSize = 24, TextXAlignment = Enum.TextXAlignment.Left, Parent = side,
	})
	bindc(logo, "TextColor3", "text")
	local function paintLogo() logo.Text = string.format('%s<font color="#%s">%s</font>', title, hex(T.accent), suffix) end
	paintLogo()
	hookAccent(logo, paintLogo)
	local vline = new("Frame", { Position = UDim2.fromOffset(SIDE, 0), Size = UDim2.new(0, 1, 1, 0), BorderSizePixel = 0, Parent = main })
	bindc(vline, "BackgroundColor3", "line")
	win.nav = new("ScrollingFrame", {
		Position = UDim2.fromOffset(10, 56), Size = UDim2.new(0, SIDE - 20, 1, -66), BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 0, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, Parent = side,
	})
	new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = win.nav })

	-- содержимое
	local content = new("Frame", { Position = UDim2.fromOffset(SIDE + 1, 0), Size = UDim2.new(1, -SIDE - 1, 1, 0), BackgroundTransparency = 1, ClipsDescendants = true, Parent = main })
	local header = new("Frame", { Size = UDim2.new(1, 0, 0, 74), BackgroundTransparency = 1, Parent = content })
	win.pageTitle = txt(header, "", 26, "text", { Position = UDim2.fromOffset(24, 12), Size = UDim2.new(1, -90, 0, 30) })
	win.pageSub = txt(header, "", 14, "sub", { Position = UDim2.fromOffset(24, 42), Size = UDim2.new(1, -90, 0, 18), Font = Enum.Font.Gotham })
	local hline = new("Frame", { Position = UDim2.new(0, 24, 1, -1), Size = UDim2.new(1, -48, 0, 1), BorderSizePixel = 0, Parent = header })
	bindc(hline, "BackgroundColor3", "line")
	local hide = new("TextButton", {
		Position = UDim2.new(1, -44, 0, 14), Size = UDim2.fromOffset(28, 28), BackgroundTransparency = 1, Text = "✕", TextSize = 15,
		Font = Enum.Font.GothamBold, Parent = header,
	})
	bindc(hide, "TextColor3", "sub")
	win.body = new("Frame", { Position = UDim2.fromOffset(0, 74), Size = UDim2.new(1, 0, 1, -74), BackgroundTransparency = 1, Parent = content })

	makeDraggable(header, main)
	makeDraggable(logo, main)

	-- кнопка-лаунчер: меню скрывается, пока играешь
	local launcher = new("TextButton", {
		Position = UDim2.new(0, 14, 0.5, -60), Size = UDim2.fromOffset(40, 40), BorderSizePixel = 0, Text = "≡", TextSize = 22,
		Font = Enum.Font.GothamBold, AutoButtonColor = false, Parent = ChipLayer,
	}, { corner(12) })
	bindc(launcher, "BackgroundColor3", "panel")
	bindc(launcher, "TextColor3", "accent")
	local lst = new("UIStroke", { Thickness = 1.5, Parent = launcher })
	bindc(lst, "Color", "accent")
	makeDraggable(launcher, launcher, function() win:Toggle() end)
	hide.MouseButton1Click:Connect(function() win:Toggle(false) end)
	win.launcher = launcher

	local toggleKey = o.ToggleKey or Enum.KeyCode.RightShift
	on(UIS.InputBegan, function(i, processed)
		if processed or i.UserInputType ~= Enum.UserInputType.Keyboard then return end
		if i.KeyCode == toggleKey then win:Toggle(); return end
		for _, fn in ipairs(win.keybinds) do pcall(fn, i) end
	end)

	if o.Status then win:SetStatus(o.Status, o.StatusColor) end
	return win
end

function Window:Toggle(v)
	if v == nil then v = not self.open end
	self.open = v
	closePopup()
	if v then
		self.main.Visible = true
		self.main.GroupTransparency = 1
		tween(self.main, 0.2, { GroupTransparency = 0 })
	else
		tween(self.main, 0.15, { GroupTransparency = 1 })
		task.delay(0.16, function() if not self.open then self.main.Visible = false end end)
	end
end

-- строка статуса в сайдбаре: «● текст ————»
function Window:SetStatus(text, color)
	if not self.statusRow then
		local r = new("Frame", { Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, LayoutOrder = 1, Parent = self.nav })
		self.statusDot = new("Frame", { Position = UDim2.fromOffset(16, 10), Size = UDim2.fromOffset(8, 8), BorderSizePixel = 0, Parent = r }, { pill() })
		self.statusText = txt(r, "", 14, "sub", { Position = UDim2.fromOffset(32, 0), Size = UDim2.fromOffset(100, 28), AutomaticSize = Enum.AutomaticSize.X, TextTruncate = Enum.TextTruncate.None })
		local line = new("Frame", { Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.fromOffset(0, 1), BorderSizePixel = 0, Parent = r })
		bindc(line, "BackgroundColor3", "line")
		self.statusLine = line
		self.statusText:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			local x = 32 + self.statusText.AbsoluteSize.X / State.scale + 8
			line.Position = UDim2.new(0, x, 0.5, 0)
			line.Size = UDim2.new(1, -x - 4, 0, 1)
		end)
		self.statusRow = r
	end
	self.statusText.Text = tostring(text)
	self.statusDot.BackgroundColor3 = color or T.good
end

function Window:Select(tab)
	closePopup()
	for _, t in ipairs(self.tabs) do
		local active = t == tab
		t.page.Visible = active
		tween(t.btn, 0.15, { BackgroundTransparency = active and 0 or 1 })
		t.bar.BackgroundTransparency = active and 0 or 1
		t.label.TextColor3 = active and T.text or T.sub
	end
	self.current = tab
	self.pageTitle.Text = tab.name
	self.pageSub.Text = tab.subtitle or ""
	tab.page.Position = UDim2.fromOffset(0, 10)
	tween(tab.page, 0.22, { Position = UDim2.fromOffset(0, 0) })
end

function Window:_newTab(name, subtitle, order)
	local tab = setmetatable({ win = self, name = name, subtitle = subtitle, count = 0, _order = 0 }, Tab)
	local btn = new("TextButton", {
		Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1, BorderSizePixel = 0, Text = "", AutoButtonColor = false,
		LayoutOrder = order, Parent = self.nav,
	}, { corner(9) })
	bindc(btn, "BackgroundColor3", "field")
	local bar = new("Frame", { Position = UDim2.fromOffset(2, 10), Size = UDim2.fromOffset(3, 16), BorderSizePixel = 0, BackgroundTransparency = 1, Parent = btn }, { pill() })
	bindc(bar, "BackgroundColor3", "accent")
	local label = txt(btn, name, 15, "sub", { Position = UDim2.fromOffset(18, 0), Size = UDim2.new(1, -62, 1, 0) })
	local countL = txt(btn, "", 13, "sub", { Position = UDim2.new(1, -44, 0, 0), Size = UDim2.fromOffset(34, 36), TextXAlignment = Enum.TextXAlignment.Right, Font = Enum.Font.Gotham })
	tab.btn, tab.bar, tab.label, tab.countL = btn, bar, label, countL
	tab.page = new("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y,
		Visible = false, Parent = self.body,
	})
	bindc(tab.page, "ScrollBarImageColor3", "line")
	new("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = tab.page })
	new("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 20), PaddingLeft = UDim.new(0, 24), PaddingRight = UDim.new(0, 24), Parent = tab.page })
	btn.MouseButton1Click:Connect(function() self:Select(tab) end)
	self.tabs[#self.tabs + 1] = tab
	if not self.current then self:Select(tab) end
	return tab
end

-- вкладка со счётчиком элементов справа, как в сайдбаре референса
function Window:AddTab(name, o)
	local order = self:_lo() + 1
	return self:_newTab(name, o and o.Subtitle or "", order)
end

-- домашняя вкладка: hero-карточка + (по желанию) пресеты и автозагрузка
function Window:Home(o)
	o = o or {}
	local tab = self:_newTab(o.Name or "Home", o.Subtitle or o.Welcome or "welcome back", 0)
	tab:Hero(o)
	if o.AutoLoad ~= false then
		tab:Toggle({
			Name = "Auto load last session", Default = self.settings.autoload,
			Callback = function(v) self.settings.autoload = v; self:_saveSettings() end,
		})
	end
	tab.countL.Text = ""
	tab.count = -1000
	return tab
end

function Tab:_lo()
	self._order += 1
	return self._order
end

function Tab:_added()
	self.count += 1
	if self.count > 0 then self.countL.Text = tostring(self.count) end
end

function Tab:Hero(o)
	local card = new("Frame", { Size = UDim2.new(1, 0, 0, 134), BorderSizePixel = 0, LayoutOrder = self:_lo(), Parent = self.page }, { corner(14) })
	bind(card, "BackgroundColor3", function() return tint(T.accent, 0.1) end)
	local st = new("UIStroke", { Thickness = 1.5, Parent = card })
	bind(st, "Color", function() return tint(T.accent, 0.5) end)
	local title, suffix = o.Title or "lumen", o.Suffix or ".ui"
	local big = new("TextLabel", {
		Position = UDim2.fromOffset(0, 16), Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1, RichText = true,
		Font = Enum.Font.GothamMedium, TextSize = 36, Parent = card,
	})
	bindc(big, "TextColor3", "text")
	local function paint() big.Text = string.format('%s<font color="#%s">%s</font>', title, hex(T.accent), suffix) end
	paint()
	hookAccent(big, paint)
	local greet = txt(card, o.Welcome or "Welcome back", 20, "sub", { Position = UDim2.fromOffset(0, 66), Size = UDim2.new(1, 0, 0, 26), TextXAlignment = Enum.TextXAlignment.Center, Font = Enum.Font.Gotham })
	if o.Link then
		txt(card, o.Link, 17, "accent", { Position = UDim2.fromOffset(0, 94), Size = UDim2.new(1, 0, 0, 24), TextXAlignment = Enum.TextXAlignment.Center })
	end
	new("Frame", { Size = UDim2.new(1, 0, 0, 10), BackgroundTransparency = 1, LayoutOrder = self:_lo(), Parent = self.page })
	return card
end

----------------------------------------------------------------
-- ЭЛЕМЕНТЫ УПРАВЛЕНИЯ
----------------------------------------------------------------
local function mkRow(tab, h)
	local r = new("Frame", { Size = UDim2.new(1, 0, 0, h or 40), BackgroundTransparency = 1, BorderSizePixel = 0, LayoutOrder = tab:_lo(), Parent = tab.page }, { corner(8) })
	bindc(r, "BackgroundColor3", "field")
	local line = new("Frame", { Position = UDim2.new(0, 0, 1, -1), Size = UDim2.new(1, 0, 0, 1), BorderSizePixel = 0, BackgroundTransparency = 0.55, Parent = r })
	bindc(line, "BackgroundColor3", "line")
	return r
end

local function fieldBox(parent, w, h)
	local b = new("TextButton", {
		Position = UDim2.new(1, -w, 0.5, -h / 2), Size = UDim2.fromOffset(w, h), BorderSizePixel = 0, Text = "", AutoButtonColor = false, Parent = parent,
	}, { corner(9) })
	bindc(b, "BackgroundColor3", "field")
	local st = new("UIStroke", { Thickness = 1, Parent = b })
	bindc(st, "Color", "line")
	return b
end

-- сохранённое значение сессии (если автозагрузка включена и тип совпал)
function Tab:_flag(o, default)
	local f = o.Flag
	local v = f and self.win.session[f]
	if v ~= nil and type(v) == type(default) then return v, true end
	return default, false
end

function Tab:Section(text)
	local f = new("Frame", { Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1, LayoutOrder = self:_lo(), Parent = self.page })
	txt(f, string.upper(text), 11, "sub", { Position = UDim2.fromOffset(2, 12), Size = UDim2.new(1, 0, 0, 16), Font = Enum.Font.GothamBold })
end

function Tab:Label(text)
	local f = new("Frame", { Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1, LayoutOrder = self:_lo(), Parent = self.page })
	local l = txt(f, text, 13, "sub", { Position = UDim2.fromOffset(2, 0), Size = UDim2.new(1, -4, 1, 0), Font = Enum.Font.Gotham })
	return { Set = function(_, v) l.Text = tostring(v) end }
end

function Tab:Button(o)
	local r = mkRow(self, 40)
	txt(r, o.Name, 14, "text", { Position = UDim2.fromOffset(2, 0), Size = UDim2.new(1, -44, 1, 0) })
	txt(r, o.Text or "›", 20, "accent", { Position = UDim2.new(1, -34, 0, -1), Size = UDim2.fromOffset(30, 40), TextXAlignment = Enum.TextXAlignment.Center })
	local b = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", Parent = r })
	b.MouseEnter:Connect(function() tween(r, 0.12, { BackgroundTransparency = 0.7 }) end)
	b.MouseLeave:Connect(function() tween(r, 0.15, { BackgroundTransparency = 1 }) end)
	b.MouseButton1Click:Connect(function() safe(o.Callback) end)
	self:_added()
	return { Fire = function() safe(o.Callback) end }
end

function Tab:Toggle(o)
	local win = self.win
	local r = mkRow(self, 40)
	txt(r, o.Name, 14, "text", { Position = UDim2.fromOffset(2, 0), Size = UDim2.new(1, -70, 1, 0) })
	local sw = new("Frame", { Position = UDim2.new(1, -46, 0.5, -11), Size = UDim2.fromOffset(40, 22), BorderSizePixel = 0, Parent = r }, { pill() })
	local sst = new("UIStroke", { Thickness = 1, Parent = sw })
	bindc(sst, "Color", "line")
	local knob = new("Frame", { Size = UDim2.fromOffset(16, 16), Position = UDim2.fromOffset(3, 3), BorderSizePixel = 0, Parent = sw }, { pill() })
	local state = false
	local obj = {}
	local function paint(animate)
		local col, kcol = state and T.accent or T.field, state and T.bg or T.sub
		local pos = state and UDim2.fromOffset(21, 3) or UDim2.fromOffset(3, 3)
		if animate then
			tween(sw, 0.15, { BackgroundColor3 = col })
			tween(knob, 0.2, { Position = pos, BackgroundColor3 = kcol }, Enum.EasingStyle.Back)
		else
			sw.BackgroundColor3, knob.Position, knob.BackgroundColor3 = col, pos, kcol
		end
	end
	hookAccent(sw, function() paint(false) end)
	local function set(v, silent)
		state = v and true or false
		win:_set(o.Flag, state)
		paint(true)
		win:_repaintChips()
		if not silent then safe(o.Callback, state) end
	end
	function obj:Set(v, s) set(v, s) end
	function obj:Get() return state end
	local hit = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", Parent = r })
	hit.MouseButton1Click:Connect(function() set(not state) end)
	local init, restored = self:_flag(o, o.Default == true)
	state = init
	paint(false)
	win:_register(o.Flag, function(v, silent) set(v == true, silent) end)
	if o.Chip then win:AddChip({ Name = o.Name, Toggle = obj }) end
	if restored and init then task.defer(function() safe(o.Callback, true) end) end
	self:_added()
	return obj
end

function Tab:Slider(o)
	local win = self.win
	local min, max, inc = o.Min or 0, o.Max or 100, o.Increment or 1
	local r = mkRow(self, 54)
	txt(r, o.Name, 14, "text", { Position = UDim2.fromOffset(2, 5), Size = UDim2.new(1, -96, 0, 22) })
	local vl = txt(r, "", 14, "accent", { Position = UDim2.new(1, -94, 0, 5), Size = UDim2.fromOffset(92, 22), TextXAlignment = Enum.TextXAlignment.Right })
	local track = new("Frame", { Position = UDim2.fromOffset(2, 37), Size = UDim2.new(1, -4, 0, 5), BorderSizePixel = 0, Parent = r }, { pill() })
	bindc(track, "BackgroundColor3", "field")
	local fill = new("Frame", { Size = UDim2.fromScale(0, 1), BorderSizePixel = 0, Parent = track }, { pill() })
	bindc(fill, "BackgroundColor3", "accent")
	local knob = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(1, 0.5), Size = UDim2.fromOffset(14, 14), BorderSizePixel = 0, Parent = fill }, { pill() })
	bindc(knob, "BackgroundColor3", "text")
	local hit = new("TextButton", { Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, Text = "", Parent = r })
	local dec = #((tostring(inc):match("%.(%d+)")) or "")
	local fmt = "%." .. dec .. "f"
	local value = o.Default or min
	local function set(v, silent)
		v = math.floor((v - min) / inc + 0.5) * inc + min
		v = math.clamp(math.floor(v * 10000 + 0.5) / 10000, min, max)
		value = v
		win:_set(o.Flag, v)
		fill.Size = UDim2.fromScale(max > min and (v - min) / (max - min) or 0, 1)
		vl.Text = string.format(fmt, v) .. (o.Suffix or "")
		if not silent then safe(o.Callback, v) end
	end
	local function fromInput(i)
		set(min + (max - min) * math.clamp((i.Position.X - track.AbsolutePosition.X) / math.max(1, track.AbsoluteSize.X), 0, 1))
	end
	-- тач: горизонталь двигает слайдер, вертикаль листает страницу
	local drag, pending, start = false, false, nil
	hit.InputBegan:Connect(function(i)
		if not isPointer(i) then return end
		if i.UserInputType == Enum.UserInputType.Touch then
			pending, start = true, i.Position
		else
			drag = true
			self.page.ScrollingEnabled = false
			fromInput(i)
		end
	end)
	on(UIS.InputChanged, function(i)
		if not isMove(i) then return end
		if pending then
			local d = i.Position - start
			if d.Magnitude > 8 then
				pending = false
				if math.abs(d.X) >= math.abs(d.Y) then
					drag = true
					self.page.ScrollingEnabled = false
					fromInput(i)
				end
			end
		elseif drag then
			fromInput(i)
		end
	end)
	on(UIS.InputEnded, function(i)
		if not isPointer(i) then return end
		if pending then pending = false; fromInput(i) end
		if drag then drag = false; self.page.ScrollingEnabled = true end
	end)
	local init, restored = self:_flag(o, value)
	set(init, true)
	win:_register(o.Flag, function(v, silent) if type(v) == "number" then set(v, silent) end end)
	if restored then task.defer(function() safe(o.Callback, value) end) end
	self:_added()
	return { Set = function(_, v, s) set(v, s) end, Get = function() return value end }
end

function Tab:Dropdown(o)
	local win = self.win
	local options = o.Options or {}
	local multi = o.Multi == true
	local r = mkRow(self, 44)
	txt(r, o.Name, 14, "text", { Position = UDim2.fromOffset(2, 0), Size = UDim2.new(1, -182, 1, 0) })
	local box = fieldBox(r, 172, 30)
	local valL = txt(box, "", 13, "text", { Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -34, 1, 0) })
	txt(box, "⌄", 15, "sub", { Position = UDim2.new(1, -24, 0, -3), Size = UDim2.fromOffset(18, 30), TextXAlignment = Enum.TextXAlignment.Center })
	local current, selected = o.Default, {}
	if multi then
		current = nil
		for _, v in ipairs(o.Default or {}) do selected[v] = true end
	end
	local function getList()
		local l = {}
		for _, opt in ipairs(options) do if selected[opt] then l[#l + 1] = opt end end
		return l
	end
	local function paint()
		if multi then
			local l = getList()
			valL.Text = #l == 0 and "None" or (#l <= 2 and table.concat(l, ", ") or (#l .. " selected"))
		else
			valL.Text = tostring(current == nil and "-" or current)
		end
	end
	local function set(v, silent)
		if multi then
			selected = {}
			for _, x in ipairs(type(v) == "table" and v or {}) do selected[x] = true end
			win:_set(o.Flag, getList())
		else
			current = v
			win:_set(o.Flag, v)
		end
		paint()
		if not silent then safe(o.Callback, multi and getList() or current) end
	end
	box.MouseButton1Click:Connect(function()
		openList(box, options, function(opt) return multi and selected[opt] == true or opt == current end, function(opt)
			if multi then
				selected[opt] = (not selected[opt]) or nil
				win:_set(o.Flag, getList())
				paint()
				safe(o.Callback, getList())
			else
				set(opt)
			end
		end, multi)
	end)
	local init, restored = self:_flag(o, multi and (o.Default or {}) or current)
	if init ~= nil then
		if multi then
			selected = {}
			for _, v in ipairs(init) do selected[v] = true end
		else
			current = init
		end
	end
	paint()
	win:_set(o.Flag, multi and getList() or current)
	win:_register(o.Flag, function(v, silent) set(v, silent) end)
	if restored then task.defer(function() safe(o.Callback, multi and getList() or current) end) end
	self:_added()
	return {
		Get = function() return multi and getList() or current end,
		Set = function(_, v, s) set(v, s) end,
		Refresh = function(_, newOptions) options = newOptions; paint() end,
	}
end

-- пресеты: выбор применяет сразу несколько флагов (Presets = { Имя = { flag = значение } })
function Tab:Preset(o)
	local names = { "Custom" }
	local list = {}
	for n in pairs(o.Presets or {}) do list[#list + 1] = n end
	table.sort(list)
	for _, n in ipairs(list) do names[#names + 1] = n end
	return self:Dropdown({
		Name = o.Name or "Preset", Options = names, Default = "Custom",
		Callback = function(v)
			local p = (o.Presets or {})[v]
			if p then
				for flag, val in pairs(p) do
					local setter = self.win.setters[flag]
					if setter then pcall(setter, val) end
				end
			end
			safe(o.Callback, v)
		end,
	})
end

function Tab:Input(o)
	local win = self.win
	local r = mkRow(self, 44)
	txt(r, o.Name, 14, "text", { Position = UDim2.fromOffset(2, 0), Size = UDim2.new(1, -182, 1, 0) })
	local holder = fieldBox(r, 172, 30)
	local box = new("TextBox", {
		Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -20, 1, 0), BackgroundTransparency = 1, Text = tostring(o.Default or ""),
		PlaceholderText = o.Placeholder or "", Font = Enum.Font.Gotham, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = false, TextTruncate = Enum.TextTruncate.AtEnd, Parent = holder,
	})
	bindc(box, "TextColor3", "text")
	bindc(box, "PlaceholderColor3", "sub")
	local function set(v, silent)
		box.Text = tostring(v)
		win:_set(o.Flag, box.Text)
		if not silent then safe(o.Callback, box.Text) end
	end
	box.FocusLost:Connect(function()
		if o.Numeric then box.Text = (box.Text:gsub("[^%d%.%-]", "")) end
		win:_set(o.Flag, box.Text)
		safe(o.Callback, box.Text)
	end)
	local init, restored = self:_flag(o, tostring(o.Default or ""))
	box.Text = init
	win:_set(o.Flag, box.Text)
	win:_register(o.Flag, function(v, silent) set(v, silent) end)
	if restored then task.defer(function() safe(o.Callback, box.Text) end) end
	self:_added()
	return { Get = function() return box.Text end, Set = function(_, v, s) set(v, s) end }
end

function Tab:Keybind(o)
	local win = self.win
	local r = mkRow(self, 44)
	txt(r, o.Name, 14, "text", { Position = UDim2.fromOffset(2, 0), Size = UDim2.new(1, -132, 1, 0) })
	local box = fieldBox(r, 120, 30)
	local lbl = txt(box, "", 13, "accent", { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
	local key = o.Default
	local listening = false
	local function paint() lbl.Text = listening and "..." or (key and key.Name or "None") end
	local function set(k, silent)
		key = k
		win:_set(o.Flag, key and key.Name or "")
		paint()
		if not silent then safe(o.OnChanged, key) end
	end
	box.MouseButton1Click:Connect(function()
		if listening then return end
		listening = true
		paint()
		local conn
		conn = UIS.InputBegan:Connect(function(i)
			if i.UserInputType ~= Enum.UserInputType.Keyboard then return end
			conn:Disconnect()
			listening = false
			set(i.KeyCode ~= Enum.KeyCode.Escape and i.KeyCode or nil)
		end)
	end)
	win.keybinds[#win.keybinds + 1] = function(i)
		if not listening and key and i.KeyCode == key then safe(o.Callback, key) end
	end
	local init, restored = self:_flag(o, key and key.Name or "")
	if restored then
		local ok, k = pcall(function() return Enum.KeyCode[init] end)
		key = ok and k or nil
	end
	paint()
	win:_set(o.Flag, key and key.Name or "")
	win:_register(o.Flag, function(v, silent)
		local ok, k = pcall(function() return Enum.KeyCode[v] end)
		set(ok and k or nil, silent)
	end)
	self:_added()
	return { Get = function() return key end, Set = function(_, k, s) set(k, s) end }
end

function Tab:Color(o)
	local win = self.win
	local r = mkRow(self, 44)
	txt(r, o.Name, 14, "text", { Position = UDim2.fromOffset(2, 0), Size = UDim2.new(1, -72, 1, 0) })
	local sw = fieldBox(r, 56, 26)
	local fillF = new("Frame", { Position = UDim2.fromOffset(4, 4), Size = UDim2.new(1, -8, 1, -8), BorderSizePixel = 0, Parent = sw }, { corner(6) })
	local color = o.Default or Color3.new(1, 1, 1)
	local function set(c, silent)
		color = c
		fillF.BackgroundColor3 = c
		win:_set(o.Flag, { r = c.R, g = c.G, b = c.B })
		if not silent then safe(o.Callback, c) end
	end
	sw.MouseButton1Click:Connect(function() openColor(sw, color, function(c) set(c) end) end)
	local saved = o.Flag and win.session[o.Flag]
	local restored = type(saved) == "table" and saved.r ~= nil
	if restored then color = Color3.new(saved.r, saved.g, saved.b) end
	set(color, true)
	win:_register(o.Flag, function(v, silent)
		if type(v) == "table" and v.r then set(Color3.new(v.r, v.g, v.b), silent) end
	end)
	if restored then task.defer(function() safe(o.Callback, color) end) end
	self:_added()
	return { Get = function() return color end, Set = function(_, c, s) set(c, s) end }
end

----------------------------------------------------------------
-- ПЛАВАЮЩИЕ ЧИПЫ, ВОТЕРМАРКА, КОНФИГИ
----------------------------------------------------------------
-- чип: кнопка на экране; тап включает/выключает связанный тумблер (или вызывает Callback(state))
function Window:AddChip(o)
	local obj = o.Toggle
	local state = o.Default == true
	local btn = new("TextButton", {
		Size = UDim2.fromOffset(0, 36), AutomaticSize = Enum.AutomaticSize.X, Position = UDim2.new(0, 14, 0.5, -10 + #self.chips * 44),
		BorderSizePixel = 0, Text = tostring(o.Name), Font = Enum.Font.GothamMedium, TextSize = 15, AutoButtonColor = false, Parent = ChipLayer,
	}, { corner(12), pad(0, 16, 0, 16) })
	local st = new("UIStroke", { Thickness = 1.5, Parent = btn })
	local function paint()
		local active
		if obj then active = obj:Get() else active = state end
		btn.BackgroundColor3 = active and tint(T.accent, 0.22) or T.panel
		st.Color = active and T.accent or T.line
		btn.TextColor3 = active and T.text or T.sub
	end
	hookAccent(btn, paint)
	makeDraggable(btn, btn, function()
		if obj then obj:Set(not obj:Get()) else state = not state; safe(o.Callback, state) end
		paint()
	end)
	paint()
	self.chips[#self.chips + 1] = { btn = btn, paint = paint }
	return { Button = btn, Destroy = function() btn:Destroy() end }
end

function Window:_repaintChips()
	for _, c in ipairs(self.chips) do pcall(c.paint) end
end

function Window:SetChipsVisible(v)
	for _, c in ipairs(self.chips) do c.btn.Visible = v end
end

-- вотермарка справа сверху (+ FPS)
function Window:Watermark(o)
	o = o or {}
	if self.wm then self.wm:Destroy() end
	local f = new("Frame", {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 10), Size = UDim2.fromOffset(0, 34), AutomaticSize = Enum.AutomaticSize.X,
		BorderSizePixel = 0, Parent = ChipLayer,
	}, { corner(17), pad(0, 14, 0, 14) })
	bindc(f, "BackgroundColor3", "panel")
	local st = new("UIStroke", { Thickness = 1, Parent = f })
	bindc(st, "Color", "line")
	local l = new("TextLabel", {
		Size = UDim2.fromOffset(0, 34), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, RichText = true,
		Font = Enum.Font.GothamMedium, TextSize = 14, Parent = f,
	})
	bindc(l, "TextColor3", "text")
	local frames, acc, fps = 0, 0, 0
	local function paint()
		local extra = o.ShowFps ~= false and string.format('  <font color="#%s">|</font>  %d fps', hex(T.accent), fps) or ""
		l.Text = tostring(o.Text or "lumen.ui") .. extra
	end
	paint()
	hookAccent(l, paint)
	on(RunService.Heartbeat, function(dt)
		frames += 1
		acc += dt
		if acc >= 0.5 then
			fps, frames, acc = math.floor(frames / acc + 0.5), 0, 0
			paint()
		end
	end)
	self.wm = f
	return f
end

local function cfgName(n) return (tostring(n):gsub("[^%w_%-]", "_")) end

function Window:SaveConfig(name)
	if not fsOk() then return false end
	return (pcall(function() writefile(self.cfgPrefix .. cfgName(name) .. ".json", HttpService:JSONEncode(self.flags)) end))
end

function Window:LoadConfig(name)
	local data = decodeFile(self.cfgPrefix .. cfgName(name) .. ".json")
	if not data then return false end
	for flag, value in pairs(data) do
		local setter = self.setters[flag]
		if setter then pcall(setter, value) end
	end
	return true
end

function Window:DeleteConfig(name)
	if typeof(delfile) ~= "function" then return false end
	return (pcall(delfile, self.cfgPrefix .. cfgName(name) .. ".json"))
end

function Window:ListConfigs()
	local out = {}
	if typeof(listfiles) ~= "function" then return out end
	local ok, files = pcall(listfiles, "")
	if not ok or type(files) ~= "table" then return out end
	for _, f in ipairs(files) do
		f = tostring(f)
		local i = string.find(f, self.cfgPrefix, 1, true)
		if i then
			local rest = f:sub(i + #self.cfgPrefix)
			local n = rest:match("^(.+)%.json$")
			if n then out[#out + 1] = n end
		end
	end
	table.sort(out)
	return out
end

-- готовая вкладка: имя пресета, список, Save / Load / Delete, автозагрузка последней сессии
function Window:ConfigTab(name)
	local tab = self:AddTab(name or "Config", { Subtitle = "presets and session" })
	local current = "default"
	tab:Section("Presets")
	tab:Input({ Name = "Name", Default = current, Callback = function(t) if t ~= "" then current = t end end })
	local dd
	dd = tab:Dropdown({ Name = "Saved", Options = self:ListConfigs(), Callback = function(v) if v then current = v end end })
	local function note(ok, what)
		Lumen:Notify({ Type = ok and "Success" or "Error", Title = what, Text = ok and current or "writefile / readfile unavailable or file not found" })
	end
	tab:Button({ Name = "Save", Callback = function()
		local ok = self:SaveConfig(current)
		dd:Refresh(self:ListConfigs())
		note(ok, "Saved")
	end })
	tab:Button({ Name = "Load", Callback = function() note(self:LoadConfig(current), "Loaded") end })
	tab:Button({ Name = "Delete", Callback = function()
		local ok = self:DeleteConfig(current)
		dd:Refresh(self:ListConfigs())
		note(ok, "Deleted")
	end })
	tab:Section("Session")
	tab:Toggle({
		Name = "Auto load last session", Default = self.settings.autoload,
		Callback = function(v) self.settings.autoload = v; self:_saveSettings() end,
	})
	return tab
end

function Lumen:Unload()
	closePopup()
	for _, c in ipairs(CONNS) do pcall(function() c:Disconnect() end) end
	pcall(function() gui:Destroy() end)
	if genv.__LumenUI == Lumen then genv.__LumenUI = nil end
end

return Lumen
