--!strict
-- NairoUI.lua
-- Single-file GUI library for Roblox (Studio-friendly)
-- Features: Theming, Window (draggable, minimize/close), Button, Toggle, Slider, TabBar, Toast notifications
-- Author: ChatGPT (for Nairo)
--
-- How to use (quick):
-- local NairoUI = require(path.to.NairoUI)
-- local app = NairoUI.create({ Name = "MyApp" })
-- local win = app:Window({ Title = "Demo" })
-- local btn = win:Button({ Text = "Click Me" })
-- btn.Click:Connect(function() print("clicked") end)
-- app:Toast({ Title = "Hello", Message = "Welcome!" })
--
-- You can later split this file into separate ModuleScripts by section markers.

local NairoUI = {}

---------------------------------------------------------------------
-- Utility: Type aliases
---------------------------------------------------------------------
export type Color3 = Color3
export type Vector2 = Vector2
export type UDim = UDim
export type UDim2 = UDim2
export type Instance = Instance

export type MaidTask = RBXScriptConnection | Instance | () -> ()
export type Maid = {
	GiveTask: (self: Maid, task: MaidTask) -> (),
	DoCleaning: (self: Maid) -> (),
	Destroy: (self: Maid) -> (),
}

export type Signal<T...> = {
	Connect: (self: Signal<T...>, fn: (T...) -> ()) -> RBXScriptConnection,
	Fire: (self: Signal<T...>, T...) -> (),
	Wait: (self: Signal<T...>) -> (T...),
	Destroy: (self: Signal<T...>) -> (),
}

export type Theme = {
	font: Enum.Font,
	size: { xs: number, sm: number, md: number, lg: number, xl: number },
	radius: number,
	pad: number,
	shadow: number,
	colors: {
		bg: Color3,
		panel: Color3,
		panelAccent: Color3,
		text: Color3,
		subtext: Color3,
		muted: Color3,
		primary: Color3,
		primaryText: Color3,
		accent: Color3,
		good: Color3,
		warn: Color3,
		bad: Color3,
	}
}

export type AppConfig = { Name: string?, Parent: Instance? }
export type App = {
	Theme: Theme,
	Root: ScreenGui,
	Maid: Maid,
	Destroy: (self: App) -> (),
	Window: (self: App, opts: WindowOptions?) -> Window,
	Toast: (self: App, opts: ToastOptions) -> (),
}

export type WindowOptions = { Title: string?, Size: Vector2?, Position: UDim2?, Draggable: boolean? }
export type Window = {
	Frame: Frame,
	Content: Frame,
	Maid: Maid,
	Button: (self: Window, opts: ButtonOptions) -> Button,
	Toggle: (self: Window, opts: ToggleOptions) -> Toggle,
	Slider: (self: Window, opts: SliderOptions) -> Slider,
	TabBar: (self: Window, opts: TabBarOptions) -> TabBar,
	Destroy: (self: Window) -> (),
}

export type ButtonOptions = { Text: string, Icon: string?, OnClick: (() -> ())? }
export type Button = { Instance: TextButton, Click: Signal<> }

export type ToggleOptions = { Label: string, Value: boolean?, OnChanged: ((boolean) -> ())? }
export type Toggle = { Instance: Frame, Changed: Signal<boolean>, Get: (self: Toggle) -> boolean, Set: (self: Toggle, v: boolean) -> () }

export type SliderOptions = { Label: string, Min: number, Max: number, Step: number?, Value: number?, OnChanged: ((number) -> ())? }
export type Slider = { Instance: Frame, Changed: Signal<number>, Get: (self: Slider) -> number, Set: (self: Slider, v: number) -> () }

export type TabBarOptions = { Tabs: { [number]: { Id: string, Text: string } }, Initial: string? }
export type Tab = { Id: string, Button: TextButton, Page: Frame }
export type TabBar = { Instance: Frame, Changed: Signal<string>, AddPage: (self: TabBar, id: string, page: Frame) -> (), Set: (self: TabBar, id: string) -> () }

export type ToastOptions = { Title: string, Message: string, Duration: number? }

---------------------------------------------------------------------
-- Utility: new (Instance helper)
---------------------------------------------------------------------
local function new(className: string, props: { [string]: any }?, children: { Instance }?)
	local inst = Instance.new(className)
	if props then
		for k, v in pairs(props) do
			(inst :: any)[k] = v
		end
	end
	if children then
		for _, c in ipairs(children) do c.Parent = inst end
	end
	return inst
end

---------------------------------------------------------------------
-- Utility: Maid (resource cleanup)
---------------------------------------------------------------------
local Maid = {}
Maid.__index = Maid

function Maid.new(): Maid
	return setmetatable({ _tasks = {} :: { MaidTask } }, Maid) :: any
end

function Maid:GiveTask(task: MaidTask)
	table.insert(self._tasks, task)
end

function Maid:DoCleaning()
	for i = #self._tasks, 1, -1 do
		local task = self._tasks[i]
		local t = typeof(task)
		local ok, err
		if t == "RBXScriptConnection" then
			(task :: RBXScriptConnection):Disconnect()
		elseif t == "Instance" then
			(task :: Instance):Destroy()
		elseif t == "function" then
			ok, err = pcall(task :: any)
			if not ok then warn("Maid task error:", err) end
		end
		self._tasks[i] = nil
	end
end

function Maid:Destroy()
	self:DoCleaning()
	setmetatable(self, nil)
end

---------------------------------------------------------------------
-- Utility: Signal (lightweight)
---------------------------------------------------------------------
local Signal = {}
Signal.__index = Signal

function Signal.new<T...>(): Signal<T...>
	local self = setmetatable({ _bindable = Instance.new("BindableEvent") }, Signal)
	return (self :: any)
end

function Signal:Connect(fn)
	return self._bindable.Event:Connect(fn)
end

function Signal:Fire(...)
	self._bindable:Fire(...)
end

function Signal:Wait()
	return self._bindable.Event:Wait()
end

function Signal:Destroy()
	self._bindable:Destroy()
	setmetatable(self, nil)
end

---------------------------------------------------------------------
-- Utility: Tween helpers
---------------------------------------------------------------------
local TweenService = game:GetService("TweenService")
local function tween(i: Instance, time: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	local ti = TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out)
	TweenService:Create(i, ti, props):Play()
end

---------------------------------------------------------------------
-- Style & Theme tokens
---------------------------------------------------------------------
local function c3(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local DEFAULT_THEME: Theme = {
	font = Enum.Font.Gotham,
	size = { xs = 10, sm = 12, md = 14, lg = 18, xl = 22 },
	radius = 8,
	pad = 8,
	shadow = 0.08,
	colors = {
		bg = c3(18, 18, 20),
		panel = c3(28, 28, 32),
		panelAccent = c3(38, 38, 44),
		text = c3(235, 235, 240),
		subtext = c3(180, 180, 188),
		muted = c3(100, 100, 110),
		primary = c3(88, 101, 242),
		primaryText = c3(255, 255, 255),
		accent = c3(56, 189, 248),
		good = c3(34, 197, 94),
		warn = c3(234, 179, 8),
		bad = c3(239, 68, 68),
	}
}

---------------------------------------------------------------------
-- Root App
---------------------------------------------------------------------
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local function getDefaultParent(): Instance
	if RunService:IsStudio() or RunService:IsRunning() then
		local plr = Players.LocalPlayer
		if plr then
			local pg = plr:FindFirstChildOfClass("PlayerGui")
			if pg then return pg end
		end
	end
	return game:GetService("CoreGui")
end

function NairoUI.create(config: AppConfig?): App
	config = config or {}
	local maid = Maid.new()
	local root = new("ScreenGui", {
		Name = config.Name or "NairoUI",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		IgnoreGuiInset = false,
		Parent = config.Parent or getDefaultParent(),
	})
	maid:GiveTask(root)

	-- Global toast layer
	local toastLayer = new("Frame", {
		Name = "ToastLayer",
		Parent = root,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.new(1, 0, 1, 0),
		ZIndex = 1000,
	}, {
		new("UIListLayout", { Padding = UDim.new(0, 8), HorizontalAlignment = Enum.HorizontalAlignment.Right, VerticalAlignment = Enum.VerticalAlignment.Bottom, SortOrder = Enum.SortOrder.LayoutOrder }),
		new("UIPadding", { PaddingBottom = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }),
	})

	maid:GiveTask(function()
		toastLayer:Destroy()
	end)

	local app: App = {
		Theme = DEFAULT_THEME,
		Root = root,
		Maid = maid,
	} :: any

	function app:Destroy()
		maid:DoCleaning()
	end

	-----------------------------------------------------------------
	-- App: Toast notifications
	-----------------------------------------------------------------
	function app:Toast(opts: ToastOptions)
		local t = self.Theme
		local life = opts.Duration or 3
		local frame = new("Frame", {
			Name = "Toast",
			Parent = toastLayer,
			BackgroundColor3 = t.colors.panel,
			BackgroundTransparency = 0,
			Size = UDim2.fromOffset(320, 72),
			AutomaticSize = Enum.AutomaticSize.Y,
			ClipsDescendants = true,
			BorderSizePixel = 0,
			ZIndex = 1001,
		}, {
			new("UICorner", { CornerRadius = UDim.new(0, t.radius) }),
			new("UIStroke", { Color = t.colors.panelAccent, Thickness = 1, Transparency = 0.25 }),
			new("UIPadding", { PaddingTop = UDim.new(0, t.pad), PaddingBottom = UDim.new(0, t.pad), PaddingLeft = UDim.new(0, t.pad), PaddingRight = UDim.new(0, t.pad) }),
			new("UIListLayout", { Padding = UDim.new(0, 4), FillDirection = Enum.FillDirection.Vertical, SortOrder = Enum.SortOrder.LayoutOrder }),
		})

		local title = new("TextLabel", {
			Parent = frame,
			Text = opts.Title,
			Font = t.font,
			TextSize = t.size.md,
			TextColor3 = t.colors.text,
			BackgroundTransparency = 1,
			AutomaticSize = Enum.AutomaticSize.Y,
			TextXAlignment = Enum.TextXAlignment.Left,
		})

		local body = new("TextLabel", {
			Parent = frame,
			Text = opts.Message,
			Font = t.font,
			TextSize = t.size.sm,
			TextColor3 = t.colors.subtext,
			BackgroundTransparency = 1,
			AutomaticSize = Enum.AutomaticSize.Y,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
		})

		frame.BackgroundTransparency = 1
		frame.Position = UDim2.fromOffset(8, 8)
		tween(frame, 0.25, { BackgroundTransparency = 0 })

		task.delay(life, function()
			if frame.Parent then
				tween(frame, 0.2, { BackgroundTransparency = 1 })
				task.delay(0.2, function()
					frame:Destroy()
				end)
			end
		end)
	end

	-----------------------------------------------------------------
	-- App: Window factory
	-----------------------------------------------------------------
	function app:Window(opts: WindowOptions?): Window
		opts = opts or {}
		local t = self.Theme
		local maid = Maid.new()

		local frame = new("Frame", {
			Name = "Window",
			Parent = self.Root,
			BackgroundColor3 = t.colors.panel,
			Size = UDim2.fromOffset((opts.Size and opts.Size.X) or 420, (opts.Size and opts.Size.Y) or 320),
			Position = opts.Position or UDim2.fromOffset(60, 60),
			BorderSizePixel = 0,
			ClipsDescendants = false,
			Active = true,
			ZIndex = 10,
		}, {
			new("UICorner", { CornerRadius = UDim.new(0, t.radius) }),
			new("UIStroke", { Color = t.colors.panelAccent, Thickness = 1, Transparency = 0.3 }),
			new("UIPadding", { PaddingTop = UDim.new(0, 36) }),
		})

		local shadow = new("ImageLabel", {
			Parent = frame,
			BackgroundTransparency = 1,
			Image = "rbxassetid://1316045217", -- soft shadow circle (built-in asset ok to swap)
			ImageColor3 = Color3.new(0,0,0),
			ImageTransparency = 1 - t.shadow,
			ScaleType = Enum.ScaleType.Slice,
			SliceScale = 0.9,
			Size = UDim2.new(1, 24, 1, 24),
			Position = UDim2.fromOffset(-12, -12),
			ZIndex = 5,
		})

		local titleBar = new("Frame", {
			Parent = frame,
			BackgroundColor3 = t.colors.panelAccent,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 36),
			Position = UDim2.fromOffset(0, 0),
			ZIndex = 11,
		}, {
			new("UICorner", { CornerRadius = UDim.new(0, t.radius), Name = "TopLeft" }),
			new("UIStroke", { Transparency = 0.5, Color = t.colors.panelAccent }),
			new("UIPadding", { PaddingLeft = UDim.new(0, t.pad), PaddingRight = UDim.new(0, t.pad) }),
		})

		-- Title text
		local title = new("TextLabel", {
			Parent = titleBar,
			BackgroundTransparency = 1,
			Text = opts.Title or "Window",
			Font = t.font,
			TextSize = t.size.md,
			TextColor3 = t.colors.text,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -90, 1, 0),
		})

		-- Controls (minimize & close)
		local btnClose = new("TextButton", {
			Parent = titleBar,
			Text = "✕",
			Font = t.font,
			TextSize = t.size.md,
			BackgroundTransparency = 1,
			TextColor3 = t.colors.subtext,
			Size = UDim2.fromOffset(28, 28),
			Position = UDim2.new(1, -28, 0.5, -14),
			ZIndex = 12,
		})

		local btnMin = new("TextButton", {
			Parent = titleBar,
			Text = "—",
			Font = t.font,
			TextSize = t.size.md,
			BackgroundTransparency = 1,
			TextColor3 = t.colors.subtext,
			Size = UDim2.fromOffset(28, 28),
			Position = UDim2.new(1, -60, 0.5, -14),
			ZIndex = 12,
		})

		local content = new("Frame", {
			Parent = frame,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -t.pad*2, 1, -t.pad*2 - 36),
			Position = UDim2.fromOffset(t.pad, 36 + t.pad),
			ClipsDescendants = false,
			ZIndex = 10,
		}, {
			new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
		})

		-- Draggable
		local dragging = false
		local dragStart: Vector2 = Vector2.new()
		local startPos: UDim2 = frame.Position
		if opts.Draggable ~= false then
			maid:GiveTask(titleBar.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					dragging = true
					dragStart = input.Position
					startPos = frame.Position
					input.Changed:Connect(function()
						if input.UserInputState == Enum.UserInputState.End then dragging = false end
					end)
				end
			end))

			maid:GiveTask(titleBar.InputChanged:Connect(function(input)
				if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
					local delta = input.Position - dragStart
					frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
				end
			end))
		end

		-- Close/Minimize
		maid:GiveTask(btnClose.MouseButton1Click:Connect(function()
			frame.Visible = false
		end))
		maid:GiveTask(btnMin.MouseButton1Click:Connect(function()
			local target = frame.Size.Y.Offset > 36 and 36 or ((opts.Size and opts.Size.Y) or 320)
			tween(frame, 0.18, { Size = UDim2.new(frame.Size.X.Scale, frame.Size.X.Offset, 0, target) })
		end))

		local window: Window = {
			Frame = frame,
			Content = content,
			Maid = maid,
		} :: any

		function window:Destroy()
			maid:DoCleaning()
			frame:Destroy()
		end

		-----------------------------------------------------------------
		-- Window Widgets
		-----------------------------------------------------------------
		local function applyButtonStates(btn: TextButton, t: Theme)
			btn.MouseEnter:Connect(function()
				tween(btn, 0.08, { BackgroundColor3 = t.colors.primary })
				btn.TextColor3 = t.colors.primaryText
			end)
			btn.MouseLeave:Connect(function()
				tween(btn, 0.12, { BackgroundColor3 = t.colors.panelAccent })
				btn.TextColor3 = t.colors.text
			end)
			btn.MouseButton1Down:Connect(function()
				tween(btn, 0.06, { BackgroundColor3 = t.colors.accent })
			end)
			btn.MouseButton1Up:Connect(function()
				tween(btn, 0.06, { BackgroundColor3 = t.colors.primary })
			end)
		end

		function window:Button(opts: ButtonOptions): Button
			local t = app.Theme
			local holder = new("Frame", { Parent = content, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 36) })
			local btn = new("TextButton", {
				Parent = holder,
				BackgroundColor3 = t.colors.panelAccent,
				BorderSizePixel = 0,
				Size = UDim2.new(1, 0, 1, 0),
				Text = opts.Text,
				Font = t.font,
				TextSize = t.size.md,
				TextColor3 = t.colors.text,
				AutoButtonColor = false,
			}, {
				new("UICorner", { CornerRadius = UDim.new(0, t.radius) }),
				new("UIStroke", { Color = t.colors.panelAccent, Transparency = 0.3, Thickness = 1 }),
			})

			applyButtonStates(btn, t)

			local click = Signal.new()
			local conn = btn.MouseButton1Click:Connect(function()
				click:Fire()
				if opts.OnClick then
					local ok, err = pcall(opts.OnClick)
					if not ok then warn("Button OnClick error:", err) end
				end
			end)
			maid:GiveTask(conn)

			local api: Button = { Instance = btn, Click = click }
			return api
		end

		function window:Toggle(opts: ToggleOptions): Toggle
			local t = app.Theme
			local value = if opts.Value ~= nil then opts.Value else false

			local row = new("Frame", { Parent = content, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 32) }, {
				new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), VerticalAlignment = Enum.VerticalAlignment.Center })
			})

			local box = new("Frame", { Parent = row, Size = UDim2.fromOffset(28, 18), BackgroundColor3 = t.colors.panelAccent, BorderSizePixel = 0 }, {
				new("UICorner", { CornerRadius = UDim.new(1, 0) }),
				new("UIStroke", { Color = t.colors.muted, Transparency = 0.4 })
			})
			local knob = new("Frame", { Parent = box, Size = UDim2.fromOffset(16, 16), Position = UDim2.fromOffset(1,1), BackgroundColor3 = t.colors.text, BorderSizePixel = 0 }, {
				new("UICorner", { CornerRadius = UDim.new(1, 0) })
			})

			local label = new("TextLabel", { Parent = row, BackgroundTransparency = 1, Text = opts.Label, Font = t.font, TextSize = t.size.md, TextColor3 = t.colors.text, Size = UDim2.new(1, -36, 1, 0), TextXAlignment = Enum.TextXAlignment.Left })

			local function render()
				if value then
					TweenService:Create(knob, TweenInfo.new(0.1), { Position = UDim2.fromOffset(11,1), BackgroundColor3 = t.colors.primaryText }):Play()
					TweenService:Create(box, TweenInfo.new(0.1), { BackgroundColor3 = t.colors.primary }):Play()
				else
					TweenService:Create(knob, TweenInfo.new(0.1), { Position = UDim2.fromOffset(1,1), BackgroundColor3 = t.colors.text }):Play()
					TweenService:Create(box, TweenInfo.new(0.1), { BackgroundColor3 = t.colors.panelAccent }):Play()
				end
			end
			render()

			local changed = Signal.new()
			local function set(v: boolean)
				if value == v then return end
				value = v
				render()
				changed:Fire(value)
				if opts.OnChanged then
					local ok, err = pcall(opts.OnChanged, value)
					if not ok then warn("Toggle OnChanged error:", err) end
				end
			end

			maid:GiveTask(box.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					set(not value)
				end
			end))

			local api: Toggle = {
				Instance = row,
				Changed = changed,
				Get = function() return value end,
				Set = set,
			}
			return api
		end

		function window:Slider(opts: SliderOptions): Slider
			local t = app.Theme
			local min, max = opts.Min, opts.Max
			local step = opts.Step or 1
			local value = math.clamp(opts.Value or min, min, max)

			local row = new("Frame", { Parent = content, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40) }, {
				new("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, Padding = UDim.new(0, 4) })
			})
			local label = new("TextLabel", { Parent = row, BackgroundTransparency = 1, Text = string.format("%s: %d", opts.Label, value), Font = t.font, TextSize = t.size.sm, TextColor3 = t.colors.subtext, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1,0,0,16) })
			local bar = new("Frame", { Parent = row, BackgroundColor3 = t.colors.panelAccent, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 8) }, {
				new("UICorner", { CornerRadius = UDim.new(0, t.radius) }),
				new("UIStroke", { Color = t.colors.muted, Transparency = 0.4 })
			})
			local fill = new("Frame", { Parent = bar, BackgroundColor3 = t.colors.primary, BorderSizePixel = 0, Size = UDim2.fromScale((value-min)/(max-min), 1) }, {
				new("UICorner", { CornerRadius = UDim.new(0, t.radius) })
			})

			local dragging = false
			local function updateFromX(x: number)
				local rel = math.clamp((x - bar.AbsolutePosition.X)/bar.AbsoluteSize.X, 0, 1)
				local raw = min + rel * (max - min)
				local snapped = math.round(raw/step)*step
				value = math.clamp(snapped, min, max)
				fill.Size = UDim2.fromScale((value-min)/(max-min), 1)
				label.Text = string.format("%s: %d", opts.Label, value)
			end

			maid:GiveTask(bar.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					dragging = true
					updateFromX(input.Position.X)
				end
			end))
			maid:GiveTask(bar.InputChanged:Connect(function(input)
				if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
					updateFromX(input.Position.X)
				end
			end))
			maid:GiveTask(bar.InputEnded:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					dragging = false
				end
			end))

			local changed = Signal.new()
			maid:GiveTask(bar.InputEnded:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					changed:Fire(value)
					if opts.OnChanged then
						local ok, err = pcall(opts.OnChanged, value)
						if not ok then warn("Slider OnChanged error:", err) end
					end
				end
			end))

			local function set(v: number)
				value = math.clamp(math.round(v/step)*step, min, max)
				fill.Size = UDim2.fromScale((value-min)/(max-min), 1)
				label.Text = string.format("%s: %d", opts.Label, value)
			end

			local api: Slider = { Instance = row, Changed = changed, Get = function() return value end, Set = set }
			return api
		end

		function window:TabBar(opts: TabBarOptions): TabBar
			local t = app.Theme
			local selected = opts.Initial or (opts.Tabs[1] and opts.Tabs[1].Id) or "tab1"
			local container = new("Frame", { Parent = content, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -content.UIListLayout.AbsoluteContentSize.Y) })
			local tabsRow = new("Frame", { Parent = container, BackgroundTransparency = 1, Size = UDim2.new(1,0,0,32) }, {
				new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) })
			})
			local pages = new("Frame", { Parent = container, BackgroundTransparency = 1, Size = UDim2.new(1,0,1,-36), Position = UDim2.fromOffset(0,36) })

			local changed = Signal.new()
			local index: { [string]: Tab } = {}

			local function renderActive()
				for id, tab in pairs(index) do
					tab.Page.Visible = (id == selected)
					tab.Button.TextColor3 = if id == selected then t.colors.primaryText else t.colors.subtext
					tab.Button.BackgroundColor3 = if id == selected then t.colors.primary else t.colors.panelAccent
				end
				changed:Fire(selected)
			end

			local function addTab(def: { Id: string, Text: string })
				local b = new("TextButton", { Parent = tabsRow, Text = def.Text, Size = UDim2.fromOffset(100, 28), AutoButtonColor = false, Font = t.font, TextSize = t.size.sm, BackgroundColor3 = t.colors.panelAccent, TextColor3 = t.colors.subtext, BorderSizePixel = 0 }, {
					new("UICorner", { CornerRadius = UDim.new(0, t.radius) }),
					new("UIStroke", { Color = t.colors.panelAccent, Transparency = 0.4 })
				})
				local page = new("Frame", { Parent = pages, BackgroundTransparency = 1, Size = UDim2.new(1,0,1,0), Visible = false }, {
					new("UIListLayout", { Padding = UDim.new(0, 8) })
				})
				index[def.Id] = { Id = def.Id, Button = b, Page = page }
				b.MouseButton1Click:Connect(function()
					selected = def.Id
					renderActive()
				end)
			end

			for _, def in ipairs(opts.Tabs) do addTab(def) end
			if not index[selected] and opts.Tabs[1] then selected = opts.Tabs[1].Id end
			renderActive()

			local api: TabBar = {
				Instance = container,
				Changed = changed,
				AddPage = function(self, id: string, page: Frame)
					local tab = index[id]
					assert(tab, "Unknown tab id: " .. id)
					page.Parent = pages
					tab.Page:Destroy()
					tab.Page = page
				end,
				Set = function(self, id: string)
					assert(index[id], "Unknown tab id: " .. id)
					selected = id
					renderActive()
				end,
			}
			return api
		end

		return window
	end

	return app
end

return NairoUI
