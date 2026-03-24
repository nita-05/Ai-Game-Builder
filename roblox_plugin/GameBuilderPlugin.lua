local HttpService = game:GetService("HttpService")
local LogService = game:GetService("LogService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local TOOLBAR_NAME = "AI Game Builder"
local BUTTON_NAME = "Game Builder"
local WIDGET_ID = "AIGameBuilderDockWidget"
local WIDGET_TITLE = "AI Game Builder"

local API_BASE_URL = "https://ai-game-build.onrender.com" -- change if your backend is hosted elsewhere
local API_KEY = "" -- keep empty to disable auth; set to APP_API_KEY value if backend enforces auth
local MEMORY_USER_ID = "default"

local plannedToolCalls = nil

local function makeHeaders()
	local headers = { ["Content-Type"] = "application/json" }
	if API_KEY and tostring(API_KEY) ~= "" then
		headers["X-API-Key"] = tostring(API_KEY)
	end
	return headers
end

local function safeJsonDecode(text)
	local ok, result = pcall(function()
		return HttpService:JSONDecode(text)
	end)
	if ok then
		return result
	end
	return nil
end

local TEMPLATES = {
	{
		key = "obby",
		label = "🧱 Obby",
		prompt = "Create an Obby game with increasing difficulty and checkpoints",
	},
	{
		key = "flappy_tap",
		label = "🐤 Flappy",
		prompt = "Create a Flappy-Tap style game: tap to jump, pipes/obstacles scrolling, score counter, and restart on fail",
	},
	{
		key = "survival",
		label = "🧟 Survival",
		prompt = "Create a survival game: resources, simple crafting loop, day/night cycle, and basic enemy waves",
	},
	{
		key = "simulator",
		label = "🎮 Simulator",
		prompt = "Create a simulator game: collect currency, upgrade stats, simple UI, and rebirth mechanic",
	},
	{
		key = "tycoon",
		label = "💰 Tycoon",
		prompt = "Create a tycoon game: droppers generating cash, buy buttons, progressive unlocks, and saving player progress",
	},
}

local selectedTemplateKey = nil
local EXPLORER_PATH_PROMPT_SUFFIX = table.concat({
	"\n\nOutput rules (must follow exactly):",
	"\n- Return steps where every step title is a Roblox Explorer path.",
	"\n- Path format: Service/Folder/SubFolder/ScriptName",
	"\n- Valid service examples: Workspace, ReplicatedStorage, ServerScriptService, ServerStorage, StarterPlayer, StarterGui, StarterPack, Lighting, Teams, SoundService.",
	"\n- Do not use generic titles like 'Step 1' or 'Movement System'. Use only full paths in titles.",
	"\n- Keep each step code Lua/Luau and scoped to its target script path.",
}, "")

local function buildPromptWithTemplate(userText)
	local cleanedUser = tostring(userText or "")
	cleanedUser = string.gsub(cleanedUser, "^%s+", "")
	cleanedUser = string.gsub(cleanedUser, "%s+$", "")

	local templatePrompt = nil
	if selectedTemplateKey then
		for _, t in ipairs(TEMPLATES) do
			if t.key == selectedTemplateKey then
				templatePrompt = t.prompt
				break
			end
		end
	end

	if templatePrompt and cleanedUser ~= "" then
		return templatePrompt .. "\n\nAdditional requirements:\n" .. cleanedUser
	end

	if templatePrompt then
		return templatePrompt
	end

	return cleanedUser
end

local function withExplorerPathRules(promptText)
	local base = tostring(promptText or "")
	return base .. EXPLORER_PATH_PROMPT_SUFFIX
end

local function setCanvasToBottom(scrollingFrame)
	local layout = scrollingFrame:FindFirstChildOfClass("UIListLayout")
	if not layout then
		return
	end
	scrollingFrame.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 12)
end

local function createLabel(parent, text, isTitle)
	local label = Instance.new("TextLabel")	
	label.BackgroundTransparency = isTitle and 1 or 0
	label.BorderSizePixel = 0
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.TextWrapped = true
	label.RichText = false
	label.Font = isTitle and Enum.Font.GothamBold or Enum.Font.Gotham
	label.TextSize = isTitle and 16 or 13
	label.TextColor3 = isTitle and Color3.fromRGB(30, 41, 59) or Color3.fromRGB(30, 41, 59)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.Size = UDim2.new(1, -10, 0, 0)
	label.Text = text
	label.Parent = parent
	if not isTitle then
		label.BackgroundColor3 = Color3.fromRGB(238, 242, 255)
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 10)
		pad.PaddingRight = UDim.new(0, 10)
		pad.PaddingTop = UDim.new(0, 8)
		pad.PaddingBottom = UDim.new(0, 8)
		pad.Parent = label
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = label
	end
	return label
end

local function createStepTitle(parent, text)
	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = Color3.fromRGB(220, 252, 231)
	frame.BorderSizePixel = 0
	frame.Size = UDim2.new(1, -12, 0, 28)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.Parent = parent

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 6)
	pad.Parent = frame

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.TextWrapped = true
	label.RichText = false
	label.Font = Enum.Font.GothamBold
	label.TextSize = 13
	label.TextColor3 = Color3.fromRGB(22, 101, 52)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.Size = UDim2.new(1, 0, 0, 0)
	label.Text = text
	label.Parent = frame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame

	return frame
end

local function addCardStyle(frame)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 16)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.Color = Color3.fromRGB(226, 232, 240)
	stroke.Transparency = 0
	stroke.Parent = frame
end

local function addButtonEffects(button, normalColor, hoverColor, pressedColor)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = button
	button.BackgroundColor3 = normalColor

	button.MouseEnter:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.12), { BackgroundColor3 = hoverColor }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.12), { BackgroundColor3 = normalColor }):Play()
	end)
	button.MouseButton1Down:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.08), { BackgroundColor3 = pressedColor }):Play()
	end)
	button.MouseButton1Up:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.08), { BackgroundColor3 = hoverColor }):Play()
	end)
end

local function clearChildrenExceptLayout(parent)
	for _, child in ipairs(parent:GetChildren()) do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

local scriptOriginalSourceByName = {}
local scriptObjectByDebugKey = {}
local lastFixAttemptAtByName = {}
local debugRetryCountByName = {}
local MAX_DEBUG_RETRIES = 2

local function wrapWithPcall(scriptName, source)
	local safeName = tostring(scriptName or "")
	return table.concat({
		"local __ok, __err = pcall(function()\n",
		source,
		"\nend)\n",
		"if not __ok then\n",
		"\twarn('AI_SCRIPT_ERROR:", safeName, ":' .. tostring(__err))\n",
		"end\n",
	})
end

local function sanitizeInstanceName(name)
	local cleaned = tostring(name or "")
	cleaned = string.gsub(cleaned, "[^%w_ ]", "")
	cleaned = string.gsub(cleaned, "^%s+", "")
	cleaned = string.gsub(cleaned, "%s+$", "")
	cleaned = string.gsub(cleaned, "%s+", "_")
	if cleaned == "" then
		cleaned = "Step"
	end
	return string.sub(cleaned, 1, 60)
end

local function getOrCreateGeneratedFolder()
	local folder = workspace:FindFirstChild("AI_Generated")
	if folder and folder:IsA("Folder") then
		return folder
	end

	folder = Instance.new("Folder")
	folder.Name = "AI_Generated"
	folder.Parent = workspace
	return folder
end

local function getOrCreateToolsFolder()
	local folder = workspace:FindFirstChild("AI_Tools")
	if folder and folder:IsA("Folder") then
		return folder
	end

	folder = Instance.new("Folder")
	folder.Name = "AI_Tools"
	folder.Parent = workspace
	return folder
end

local function splitExplorerPath(rawPath)
	local text = tostring(rawPath or "")
	text = string.gsub(text, "\\", "/")
	text = string.gsub(text, ">", "/")
	text = string.gsub(text, "^%s+", "")
	text = string.gsub(text, "%s+$", "")

	local parts = {}
	if string.find(text, "/", 1, true) then
		for part in string.gmatch(text, "[^/]+") do
			part = string.gsub(part, "^%s+", "")
			part = string.gsub(part, "%s+$", "")
			if part ~= "" then
				table.insert(parts, part)
			end
		end
	else
		for part in string.gmatch(text, "[^%.]+") do
			part = string.gsub(part, "^%s+", "")
			part = string.gsub(part, "%s+$", "")
			if part ~= "" then
				table.insert(parts, part)
			end
		end
	end

	return parts
end

local function tryGetService(name)
	local ok, service = pcall(function()
		return game:GetService(name)
	end)
	if ok then
		return service
	end
	return nil
end

local function resolveScriptTarget(title, defaultParent)
	local parts = splitExplorerPath(title)
	if #parts < 2 then
		return defaultParent, sanitizeInstanceName(title), false, nil
	end

	local root = tryGetService(parts[1])
	if not root then
		return defaultParent, sanitizeInstanceName(title), false, nil
	end

	local parent = root
	for i = 2, (#parts - 1) do
		local segmentName = sanitizeInstanceName(parts[i])
		local existing = parent:FindFirstChild(segmentName)
		if existing and not existing:IsA("Folder") then
			return defaultParent, sanitizeInstanceName(title), false, "Path conflict at " .. parent:GetFullName() .. "." .. segmentName
		end
		if not existing then
			existing = Instance.new("Folder")
			existing.Name = segmentName
			existing.Parent = parent
		end
		parent = existing
	end

	local scriptName = sanitizeInstanceName(parts[#parts])
	if scriptName == "" then
		scriptName = "Script"
	end

	return parent, scriptName, true, nil
end

local function buildScriptKey(parentFolder, scriptName)
	local raw = tostring(scriptName or "Script")
	local ok, fullName = pcall(function()
		return parentFolder:GetFullName()
	end)
	if ok and fullName and fullName ~= "" then
		raw = fullName .. "." .. raw
	end
	raw = string.gsub(raw, "[^%w_]", "_")
	return string.sub(raw, 1, 120)
end

local function safeVector3(value, default)
	default = default or Vector3.new(0, 0, 0)
	if typeof(value) == "Vector3" then
		return value
	end
	if type(value) ~= "table" then
		return default
	end
	local x = tonumber(value.x) or tonumber(value[1]) or default.X
	local y = tonumber(value.y) or tonumber(value[2]) or default.Y
	local z = tonumber(value.z) or tonumber(value[3]) or default.Z
	return Vector3.new(x, y, z)
end

local function safeColor3(value, default)
	default = default or Color3.fromRGB(200, 200, 200)
	if typeof(value) == "Color3" then
		return value
	end
	if type(value) ~= "table" then
		return default
	end
	local r = tonumber(value.r) or tonumber(value[1]) or 200
	local g = tonumber(value.g) or tonumber(value[2]) or 200
	local b = tonumber(value.b) or tonumber(value[3]) or 200
	return Color3.fromRGB(math.clamp(r, 0, 255), math.clamp(g, 0, 255), math.clamp(b, 0, 255))
end

local function executeToolCall(callObj)
	if type(callObj) ~= "table" then
		return false, "Invalid tool call"
	end

	local tool = tostring(callObj.tool or "")
	local args = callObj.args
	if type(args) ~= "table" then
		args = {}
	end

	local toolsFolder = getOrCreateToolsFolder()

	if tool == "CreateFolder" then
		local name = sanitizeInstanceName(args.name or "Folder")
		local folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = toolsFolder
		return true, "Created Folder: " .. name
	end

	if tool == "CreateModel" then
		local name = sanitizeInstanceName(args.name or "Model")
		local model = Instance.new("Model")
		model.Name = name
		model.Parent = toolsFolder
		return true, "Created Model: " .. name
	end

	if tool == "CreatePart" then
		local name = sanitizeInstanceName(args.name or "Part")
		local part = Instance.new("Part")
		part.Name = name
		part.Anchored = (args.anchored ~= false)
		part.CanCollide = (args.canCollide ~= false)
		part.Size = safeVector3(args.size, Vector3.new(4, 1, 4))
		part.Position = safeVector3(args.position, Vector3.new(0, 3, 0))
		part.Color = safeColor3(args.color, Color3.fromRGB(180, 180, 180))
		part.Parent = toolsFolder
		return true, "Created Part: " .. name
	end

	if tool == "CreateScreenGui" then
		local name = sanitizeInstanceName(args.name or "ScreenGui")
		local gui = Instance.new("ScreenGui")
		gui.Name = name
		gui.ResetOnSpawn = false
		gui.Parent = game:GetService("StarterGui")
		return true, "Created ScreenGui in StarterGui: " .. name
	end

	return false, "Tool not allowed: " .. tool
end

local function upsertScript(parentFolder, scriptName, source)
	local existing = parentFolder:FindFirstChild(scriptName)
	local scriptObj
	if existing and existing:IsA("Script") then
		scriptObj = existing
	else
		if existing then
			existing:Destroy()
		end
		scriptObj = Instance.new("Script")
		scriptObj.Name = scriptName
		scriptObj.Parent = parentFolder
	end

	local scriptKey = buildScriptKey(parentFolder, scriptName)
	scriptOriginalSourceByName[scriptName] = source
	scriptOriginalSourceByName[scriptKey] = source
	scriptObjectByDebugKey[scriptKey] = scriptObj
	local wrapped = wrapWithPcall(scriptKey, source)

	local ok, err = pcall(function()
		scriptObj.Source = wrapped
	end)

	return ok, err, scriptKey
end

local function insertScriptNoOverwrite(parentFolder, baseName, source)
	local name = tostring(baseName or "Script")
	if name == "" then
		name = "Script"
	end

	local finalName = name
	local n = 2
	while parentFolder:FindFirstChild(finalName) do
		finalName = name .. "_" .. tostring(n)
		n += 1
	end

	local scriptObj = Instance.new("Script")
	scriptObj.Name = finalName
	scriptObj.Parent = parentFolder

	local scriptKey = buildScriptKey(parentFolder, finalName)
	scriptOriginalSourceByName[finalName] = source
	scriptOriginalSourceByName[scriptKey] = source
	scriptObjectByDebugKey[scriptKey] = scriptObj
	local wrapped = wrapWithPcall(scriptKey, source)

	local ok, err = pcall(function()
		scriptObj.Source = wrapped
	end)

	return ok, err, finalName, scriptKey
end

local SCRIPT_SCAN_ROOT_SERVICES = {
	"Workspace",
	"ReplicatedStorage",
	"ServerScriptService",
	"ServerStorage",
	"StarterPlayer",
	"StarterGui",
	"StarterPack",
	"Lighting",
	"Teams",
	"SoundService",
}

local MAX_PREVIOUS_CODE_CHARS = 180000

local function isCodeScript(instance)
	return instance:IsA("Script") or instance:IsA("LocalScript") or instance:IsA("ModuleScript")
end

local function collectAllProjectScripts()
	local scripts = {}
	local seen = {}

	for _, serviceName in ipairs(SCRIPT_SCAN_ROOT_SERVICES) do
		local service = tryGetService(serviceName)
		if service then
			if isCodeScript(service) then
				local fullName = service:GetFullName()
				if not seen[fullName] then
					seen[fullName] = true
					local ok, source = pcall(function()
						return service.Source
					end)
					if ok then
						table.insert(scripts, {
							path = fullName,
							className = service.ClassName,
							source = tostring(source or ""),
						})
					end
				end
			end

			for _, child in ipairs(service:GetDescendants()) do
				if isCodeScript(child) then
					local fullName = child:GetFullName()
					if not seen[fullName] then
						seen[fullName] = true
						local ok, source = pcall(function()
							return child.Source
						end)
						if ok then
							table.insert(scripts, {
								path = fullName,
								className = child.ClassName,
								source = tostring(source or ""),
							})
						end
					end
				end
			end
		end
	end

	return scripts
end

local function collectPreviousCode()
	local scripts = collectAllProjectScripts()
	if #scripts == 0 then
		return nil
	end

	local parts = {}
	local totalChars = 0
	for _, item in ipairs(scripts) do
		local block = table.concat({
			"-- SCRIPT_PATH: ", item.path, "\n",
			"-- SCRIPT_CLASS: ", item.className, "\n",
			item.source, "\n\n",
		})
		totalChars += #block
		if totalChars > MAX_PREVIOUS_CODE_CHARS then
			break
		end
		table.insert(parts, block)
	end

	if #parts == 0 then
		return nil
	end
	return table.concat(parts, "")
end

local function collectScriptsSnapshot()
	local scripts = collectAllProjectScripts()
	local out = {}
	for _, item in ipairs(scripts) do
		table.insert(out, {
			name = item.path,
			source = item.source,
		})
	end
	return out
end

local function appendStreamingText(parent, prefix, fullText)
	local label = createLabel(parent, prefix, false)
	label.Text = prefix .. tostring(fullText or "")
	return label
end

local toolbar = plugin:CreateToolbar(TOOLBAR_NAME)
local toggleButton = toolbar:CreateButton(BUTTON_NAME, "Open AI Game Builder", "")

local widgetInfo = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Right,
	true,
	false,
	420,
	600,
	340,
	500
)

local widget = plugin:CreateDockWidgetPluginGui(WIDGET_ID, widgetInfo)
widget.Title = WIDGET_TITLE

local rootScroll = Instance.new("ScrollingFrame")
rootScroll.BackgroundTransparency = 1
rootScroll.BorderSizePixel = 0
rootScroll.Size = UDim2.new(1, 0, 1, 0)
rootScroll.ScrollBarThickness = 8
rootScroll.ScrollingDirection = Enum.ScrollingDirection.Y
rootScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
rootScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
rootScroll.Parent = widget

local root = Instance.new("Frame")
root.BackgroundColor3 = Color3.fromRGB(248, 250, 252)
root.BorderSizePixel = 0
root.Size = UDim2.new(1, 0, 0, 0)
root.AutomaticSize = Enum.AutomaticSize.Y
root.Parent = rootScroll

local padding = Instance.new("UIPadding")
padding.PaddingLeft = UDim.new(0, 16)
padding.PaddingRight = UDim.new(0, 16)
padding.PaddingTop = UDim.new(0, 16)
padding.PaddingBottom = UDim.new(0, 16)
padding.Parent = root

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Vertical
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 12)
layout.Parent = root

layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	local h = layout.AbsoluteContentSize.Y + 20
	root.Size = UDim2.new(1, 0, 0, h)
	rootScroll.CanvasSize = UDim2.new(0, 0, 0, h)
end)

local header = Instance.new("TextLabel")
header.LayoutOrder = 1
header.BackgroundTransparency = 1
header.Size = UDim2.new(1, 0, 0, 30)
header.TextXAlignment = Enum.TextXAlignment.Left
header.Font = Enum.Font.GothamBold
header.TextSize = 22
header.TextColor3 = Color3.fromRGB(15, 23, 42)
header.Text = "AI Game Builder ✨"
header.Parent = root

local profilePlaceholder = Instance.new("Frame")
profilePlaceholder.BackgroundColor3 = Color3.fromRGB(99, 102, 241)
profilePlaceholder.BorderSizePixel = 0
profilePlaceholder.Size = UDim2.new(0, 28, 0, 28)
profilePlaceholder.Position = UDim2.new(1, -30, 0, 2)
profilePlaceholder.Parent = header
local profileCorner = Instance.new("UICorner")
profileCorner.CornerRadius = UDim.new(1, 0)
profileCorner.Parent = profilePlaceholder

local memoryHeader = Instance.new("TextLabel")
memoryHeader.LayoutOrder = 1.5
memoryHeader.BackgroundTransparency = 1
memoryHeader.Size = UDim2.new(1, 0, 0, 20)
memoryHeader.TextXAlignment = Enum.TextXAlignment.Left
memoryHeader.Font = Enum.Font.GothamBold
memoryHeader.TextSize = 16
memoryHeader.TextColor3 = Color3.fromRGB(30, 41, 59)
memoryHeader.Text = "Build Memory"
memoryHeader.Parent = root

local memoryRow = Instance.new("Frame")
memoryRow.LayoutOrder = 1.6
memoryRow.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
memoryRow.BorderSizePixel = 0
memoryRow.Size = UDim2.new(1, 0, 0, 40)
memoryRow.Parent = root

local memoryRowLayout = Instance.new("UIListLayout")
memoryRowLayout.FillDirection = Enum.FillDirection.Horizontal
memoryRowLayout.SortOrder = Enum.SortOrder.LayoutOrder
memoryRowLayout.Padding = UDim.new(0, 8)
memoryRowLayout.Parent = memoryRow

local refreshBuildsButton = Instance.new("TextButton")
refreshBuildsButton.LayoutOrder = 1
refreshBuildsButton.BackgroundColor3 = Color3.fromRGB(99, 102, 241)
refreshBuildsButton.BorderSizePixel = 0
refreshBuildsButton.Size = UDim2.new(0, 120, 1, 0)
refreshBuildsButton.Font = Enum.Font.GothamBold
refreshBuildsButton.TextSize = 12
refreshBuildsButton.TextColor3 = Color3.fromRGB(255, 255, 255)
refreshBuildsButton.Text = "Refresh Builds"
refreshBuildsButton.Parent = memoryRow
do
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = refreshBuildsButton
end

local buildsStatusLabel = Instance.new("TextLabel")
buildsStatusLabel.LayoutOrder = 2
buildsStatusLabel.BackgroundTransparency = 1
buildsStatusLabel.BorderSizePixel = 0
buildsStatusLabel.Size = UDim2.new(1, -128, 1, 0)
buildsStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
buildsStatusLabel.Font = Enum.Font.Gotham
buildsStatusLabel.TextSize = 12
buildsStatusLabel.TextColor3 = Color3.fromRGB(100, 116, 139)
buildsStatusLabel.Text = ""
buildsStatusLabel.Parent = memoryRow

local buildsList = Instance.new("Frame")
buildsList.LayoutOrder = 1.7
buildsList.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
buildsList.BorderSizePixel = 0
buildsList.Size = UDim2.new(1, 0, 0, 102)
buildsList.Parent = root
do
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = buildsList
end

local buildsScroll = Instance.new("ScrollingFrame")
buildsScroll.BackgroundTransparency = 1
buildsScroll.BorderSizePixel = 0
buildsScroll.Size = UDim2.new(1, 0, 1, 0)
buildsScroll.ScrollBarThickness = 6
buildsScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
buildsScroll.Parent = buildsList

local buildsScrollLayout = Instance.new("UIListLayout")
buildsScrollLayout.FillDirection = Enum.FillDirection.Vertical
buildsScrollLayout.SortOrder = Enum.SortOrder.LayoutOrder
buildsScrollLayout.Padding = UDim.new(0, 6)
buildsScrollLayout.Parent = buildsScroll

local buildsScrollPad = Instance.new("UIPadding")
buildsScrollPad.PaddingLeft = UDim.new(0, 8)
buildsScrollPad.PaddingRight = UDim.new(0, 8)
buildsScrollPad.PaddingTop = UDim.new(0, 8)
buildsScrollPad.PaddingBottom = UDim.new(0, 8)
buildsScrollPad.Parent = buildsScroll

buildsScrollLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	buildsScroll.CanvasSize = UDim2.new(0, 0, 0, buildsScrollLayout.AbsoluteContentSize.Y + 12)
end)

local toolsHeader = Instance.new("TextLabel")
toolsHeader.LayoutOrder = 1.8
toolsHeader.BackgroundTransparency = 1
toolsHeader.Size = UDim2.new(1, 0, 0, 20)
toolsHeader.TextXAlignment = Enum.TextXAlignment.Left
toolsHeader.Font = Enum.Font.GothamBold
toolsHeader.TextSize = 16
toolsHeader.TextColor3 = Color3.fromRGB(30, 41, 59)
toolsHeader.Text = "Tools"
toolsHeader.Parent = root

local toolsRow = Instance.new("Frame")
toolsRow.LayoutOrder = 1.9
toolsRow.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
toolsRow.BorderSizePixel = 0
toolsRow.Size = UDim2.new(1, 0, 0, 40)
toolsRow.Parent = root

local toolsRowLayout = Instance.new("UIListLayout")
toolsRowLayout.FillDirection = Enum.FillDirection.Horizontal
toolsRowLayout.SortOrder = Enum.SortOrder.LayoutOrder
toolsRowLayout.Padding = UDim.new(0, 8)
toolsRowLayout.Parent = toolsRow

local planToolsButton = Instance.new("TextButton")
planToolsButton.LayoutOrder = 1
planToolsButton.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
planToolsButton.BorderSizePixel = 0
planToolsButton.Size = UDim2.new(0, 120, 1, 0)
planToolsButton.Font = Enum.Font.GothamBold
planToolsButton.TextSize = 12
planToolsButton.TextColor3 = Color3.fromRGB(30, 41, 59)
planToolsButton.Text = "Plan"
planToolsButton.Parent = toolsRow
do
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = planToolsButton
end

local executeToolsButton = Instance.new("TextButton")
executeToolsButton.LayoutOrder = 2
executeToolsButton.BackgroundColor3 = Color3.fromRGB(241, 245, 249)
executeToolsButton.BorderSizePixel = 0
executeToolsButton.Size = UDim2.new(0, 120, 1, 0)
executeToolsButton.Font = Enum.Font.GothamBold
executeToolsButton.TextSize = 12
executeToolsButton.TextColor3 = Color3.fromRGB(100, 116, 139)
executeToolsButton.Text = "Execute"
executeToolsButton.Parent = toolsRow
do
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = executeToolsButton
end

local toolsStatusLabel = Instance.new("TextLabel")
toolsStatusLabel.LayoutOrder = 3
toolsStatusLabel.BackgroundTransparency = 1
toolsStatusLabel.BorderSizePixel = 0
toolsStatusLabel.Size = UDim2.new(1, -256, 1, 0)
toolsStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
toolsStatusLabel.Font = Enum.Font.Gotham
toolsStatusLabel.TextSize = 12
toolsStatusLabel.TextColor3 = Color3.fromRGB(100, 116, 139)
toolsStatusLabel.Text = ""
toolsStatusLabel.Parent = toolsRow

local toolsPreview = Instance.new("TextBox")
toolsPreview.LayoutOrder = 2.0
toolsPreview.BackgroundColor3 = Color3.fromRGB(249, 250, 251)
toolsPreview.BorderSizePixel = 0
toolsPreview.Size = UDim2.new(1, 0, 0, 70)
toolsPreview.TextXAlignment = Enum.TextXAlignment.Left
toolsPreview.TextYAlignment = Enum.TextYAlignment.Top
toolsPreview.ClearTextOnFocus = false
toolsPreview.MultiLine = true
toolsPreview.TextEditable = false
toolsPreview.Font = Enum.Font.Code
toolsPreview.TextSize = 12
toolsPreview.TextColor3 = Color3.fromRGB(30, 41, 59)
toolsPreview.Text = ""
toolsPreview.Parent = root
do
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = toolsPreview
end

local templatesHeader = Instance.new("TextLabel")
templatesHeader.LayoutOrder = 2
templatesHeader.BackgroundTransparency = 1
templatesHeader.Size = UDim2.new(1, 0, 0, 20)
templatesHeader.TextXAlignment = Enum.TextXAlignment.Left
templatesHeader.Font = Enum.Font.GothamBold
templatesHeader.TextSize = 16
templatesHeader.TextColor3 = Color3.fromRGB(30, 41, 59)
templatesHeader.Text = "Templates"
templatesHeader.Parent = root

local templatesRow = Instance.new("Frame")
templatesRow.LayoutOrder = 3
templatesRow.BackgroundTransparency = 1
templatesRow.BorderSizePixel = 0
templatesRow.Size = UDim2.new(1, 0, 0, 32)
templatesRow.Parent = root

local templatesLayout = Instance.new("UIListLayout")
templatesLayout.FillDirection = Enum.FillDirection.Horizontal
templatesLayout.SortOrder = Enum.SortOrder.LayoutOrder
templatesLayout.Padding = UDim.new(0, 6)
templatesLayout.Parent = templatesRow

local function makeTemplateButton(text)
	local b = Instance.new("TextButton")
	b.BackgroundColor3 = Color3.fromRGB(241, 245, 249)
	b.BorderSizePixel = 0
	b.Size = UDim2.new(0, 86, 1, 0)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 12
	b.TextColor3 = Color3.fromRGB(51, 65, 85)
	b.Text = text
	b.AutoButtonColor = true
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = b
	return b
end

local templateButtonsByKey = {}

local promptBox

local function updateTemplateButtonStyles()
	for key, btn in pairs(templateButtonsByKey) do
		if key == selectedTemplateKey then
			btn.BackgroundColor3 = Color3.fromRGB(79, 70, 229)
			btn.TextColor3 = Color3.fromRGB(255, 255, 255)
		else
			btn.BackgroundColor3 = Color3.fromRGB(241, 245, 249)
			btn.TextColor3 = Color3.fromRGB(51, 65, 85)
		end
	end
end

for _, t in ipairs(TEMPLATES) do
	local btn = makeTemplateButton(t.label)
	btn.Parent = templatesRow
	templateButtonsByKey[t.key] = btn
	btn.MouseButton1Click:Connect(function()
		selectedTemplateKey = t.key
		updateTemplateButtonStyles()
		if promptBox then
			promptBox.Text = tostring(t.prompt or "")
		end
	end)
end

local clearTemplateButton = makeTemplateButton("Clear")
clearTemplateButton.Size = UDim2.new(0, 60, 1, 0)
clearTemplateButton.BackgroundColor3 = Color3.fromRGB(226, 232, 240)
clearTemplateButton.Parent = templatesRow
clearTemplateButton.MouseButton1Click:Connect(function()
	selectedTemplateKey = nil
	updateTemplateButtonStyles()
	if promptBox then
		promptBox.Text = ""
	end
end)

updateTemplateButtonStyles()

promptBox = Instance.new("TextBox")
promptBox.LayoutOrder = 4
promptBox.BackgroundColor3 = Color3.fromRGB(249, 250, 251)
promptBox.BorderSizePixel = 0
promptBox.Size = UDim2.new(1, 0, 0, 120)
promptBox.TextXAlignment = Enum.TextXAlignment.Left
promptBox.TextYAlignment = Enum.TextYAlignment.Top
promptBox.ClearTextOnFocus = false
promptBox.MultiLine = true
promptBox.Font = Enum.Font.Gotham
promptBox.TextSize = 14
promptBox.TextColor3 = Color3.fromRGB(15, 23, 42)
promptBox.PlaceholderText = "Describe your game idea..."
promptBox.PlaceholderColor3 = Color3.fromRGB(148, 163, 184)
promptBox.Text = ""
promptBox.Parent = root

local buttonRow = Instance.new("Frame")
buttonRow.LayoutOrder = 5
buttonRow.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
buttonRow.BorderSizePixel = 0
buttonRow.Size = UDim2.new(1, 0, 0, 36)
buttonRow.Parent = root

local buttonLayout = Instance.new("UIListLayout")
buttonLayout.FillDirection = Enum.FillDirection.Horizontal
buttonLayout.SortOrder = Enum.SortOrder.LayoutOrder
buttonLayout.Padding = UDim.new(0, 8)
buttonLayout.Parent = buttonRow

local generateButton = Instance.new("TextButton")
generateButton.LayoutOrder = 1
generateButton.BackgroundColor3 = Color3.fromRGB(79, 70, 229)
generateButton.BorderSizePixel = 0
generateButton.Size = UDim2.new(0, 140, 1, 0)
generateButton.Font = Enum.Font.GothamBold
generateButton.TextSize = 14
generateButton.TextColor3 = Color3.fromRGB(255, 255, 255)
generateButton.Text = "Generate"
generateButton.Parent = buttonRow

local refineButton = Instance.new("TextButton")
refineButton.LayoutOrder = 2
refineButton.BackgroundColor3 = Color3.fromRGB(34, 197, 94)
refineButton.BorderSizePixel = 0
refineButton.Size = UDim2.new(0, 120, 1, 0)
refineButton.Font = Enum.Font.GothamBold
refineButton.TextSize = 14
refineButton.TextColor3 = Color3.fromRGB(255, 255, 255)
refineButton.Text = "Refine"
refineButton.Parent = buttonRow

local stopButton = Instance.new("TextButton")
stopButton.LayoutOrder = 3
stopButton.BackgroundColor3 = Color3.fromRGB(251, 146, 60)
stopButton.BorderSizePixel = 0
stopButton.Size = UDim2.new(0, 84, 1, 0)
stopButton.Font = Enum.Font.GothamBold
stopButton.TextSize = 13
stopButton.TextColor3 = Color3.fromRGB(255, 255, 255)
stopButton.Text = "Stop"
stopButton.Parent = buttonRow

local clearAllButton = Instance.new("TextButton")
clearAllButton.LayoutOrder = 4
clearAllButton.BackgroundColor3 = Color3.fromRGB(226, 232, 240)
clearAllButton.BorderSizePixel = 0
clearAllButton.Size = UDim2.new(0, 96, 1, 0)
clearAllButton.Font = Enum.Font.GothamBold
clearAllButton.TextSize = 13
clearAllButton.TextColor3 = Color3.fromRGB(51, 65, 85)
clearAllButton.Text = "Clear All"
clearAllButton.Parent = buttonRow

local statusLabel = Instance.new("TextLabel")
statusLabel.LayoutOrder = 5
statusLabel.BackgroundTransparency = 1
statusLabel.BorderSizePixel = 0
statusLabel.Size = UDim2.new(1, -468, 1, 0)
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextSize = 12
statusLabel.TextColor3 = Color3.fromRGB(100, 116, 139)
statusLabel.Text = "🧠 AI is ready"
statusLabel.Parent = buttonRow

local outputHeader = Instance.new("TextLabel")
outputHeader.LayoutOrder = 4
outputHeader.BackgroundTransparency = 1
outputHeader.Size = UDim2.new(1, 0, 0, 20)
outputHeader.TextXAlignment = Enum.TextXAlignment.Left
outputHeader.Font = Enum.Font.GothamBold
outputHeader.TextSize = 16
outputHeader.TextColor3 = Color3.fromRGB(30, 41, 59)
outputHeader.Text = "Output (Chat)"
outputHeader.Parent = root

local outputFrame = Instance.new("Frame")
outputFrame.LayoutOrder = 5
outputFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
outputFrame.BorderSizePixel = 0
outputFrame.Size = UDim2.new(1, 0, 0, 260)
outputFrame.Parent = root

local outputPadding = Instance.new("UIPadding")
outputPadding.PaddingLeft = UDim.new(0, 8)
outputPadding.PaddingRight = UDim.new(0, 8)
outputPadding.PaddingTop = UDim.new(0, 8)
outputPadding.PaddingBottom = UDim.new(0, 8)
outputPadding.Parent = outputFrame

local scrolling = Instance.new("ScrollingFrame")
scrolling.BackgroundTransparency = 1
scrolling.BorderSizePixel = 0
scrolling.Size = UDim2.new(1, 0, 1, 0)
scrolling.ScrollBarThickness = 6
scrolling.CanvasSize = UDim2.new(0, 0, 0, 0)
scrolling.Parent = outputFrame

local scrollingLayout = Instance.new("UIListLayout")
scrollingLayout.FillDirection = Enum.FillDirection.Vertical
scrollingLayout.SortOrder = Enum.SortOrder.LayoutOrder
scrollingLayout.Padding = UDim.new(0, 10)
scrollingLayout.Parent = scrolling

local scrollingPad = Instance.new("UIPadding")
scrollingPad.PaddingRight = UDim.new(0, 6)
scrollingPad.Parent = scrolling

scrollingLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	setCanvasToBottom(scrolling)
end)

addCardStyle(memoryRow)
addCardStyle(buildsList)
addCardStyle(toolsRow)
addCardStyle(toolsPreview)
addCardStyle(promptBox)
addCardStyle(buttonRow)
addCardStyle(outputFrame)

local promptStroke = promptBox:FindFirstChildOfClass("UIStroke")
if promptStroke then
	promptBox.Focused:Connect(function()
		promptStroke.Color = Color3.fromRGB(99, 102, 241)
	end)
	promptBox.FocusLost:Connect(function()
		promptStroke.Color = Color3.fromRGB(226, 232, 240)
	end)
end

addButtonEffects(refreshBuildsButton, Color3.fromRGB(99, 102, 241), Color3.fromRGB(79, 70, 229), Color3.fromRGB(67, 56, 202))
addButtonEffects(planToolsButton, Color3.fromRGB(255, 255, 255), Color3.fromRGB(248, 250, 252), Color3.fromRGB(241, 245, 249))
addButtonEffects(executeToolsButton, Color3.fromRGB(241, 245, 249), Color3.fromRGB(226, 232, 240), Color3.fromRGB(203, 213, 225))
addButtonEffects(generateButton, Color3.fromRGB(79, 70, 229), Color3.fromRGB(67, 56, 202), Color3.fromRGB(55, 48, 163))
addButtonEffects(refineButton, Color3.fromRGB(34, 197, 94), Color3.fromRGB(22, 163, 74), Color3.fromRGB(21, 128, 61))
addButtonEffects(stopButton, Color3.fromRGB(251, 146, 60), Color3.fromRGB(249, 115, 22), Color3.fromRGB(234, 88, 12))
addButtonEffects(clearAllButton, Color3.fromRGB(226, 232, 240), Color3.fromRGB(203, 213, 225), Color3.fromRGB(148, 163, 184))

local generateGradient = Instance.new("UIGradient")
generateGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(99, 102, 241)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(79, 70, 229)),
})
generateGradient.Rotation = 15
generateGradient.Parent = generateButton

widget.Enabled = false

toggleButton.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)

local activeRunToken = 0
local isRunActive = false

local function setBusy(isBusy, mode)
	local runningGenerate = isBusy and mode == "generate"
	local runningRefine = isBusy and mode == "refine"
	isRunActive = isBusy
	generateButton.Active = not isBusy
	generateButton.AutoButtonColor = not isBusy
	generateButton.BackgroundColor3 = isBusy and Color3.fromRGB(148, 163, 184) or Color3.fromRGB(79, 70, 229)
	generateButton.Text = runningGenerate and "Generating..." or "Generate"
	refineButton.Active = not isBusy
	refineButton.AutoButtonColor = not isBusy
	refineButton.BackgroundColor3 = isBusy and Color3.fromRGB(148, 163, 184) or Color3.fromRGB(34, 197, 94)
	refineButton.Text = runningRefine and "Refining..." or "Refine"
	stopButton.Active = isBusy
	stopButton.AutoButtonColor = isBusy
	stopButton.BackgroundColor3 = isBusy and Color3.fromRGB(251, 146, 60) or Color3.fromRGB(148, 163, 184)
	stopButton.TextColor3 = isBusy and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(241, 245, 249)
	if runningRefine then
		statusLabel.Text = "🧠 AI is refining..."
	elseif runningGenerate then
		statusLabel.Text = "🧠 AI is generating..."
	else
		statusLabel.Text = "🧠 AI is ready"
	end
end

setBusy(false)

local progressAnimToken = 0

local function startProgressAnimation(baseText)
	progressAnimToken += 1
	local token = progressAnimToken

	task.spawn(function()
		local dots = { "", ".", "..", "..." }
		local i = 1
		while token == progressAnimToken do
			statusLabel.Text = baseText .. dots[i]
			i = (i % #dots) + 1
			task.wait(0.25)
		end
	end)
end

local function stopProgressAnimation(finalText)
	progressAnimToken += 1
	statusLabel.Text = finalText or ""
end

local function clearGeneratedArtifacts()
	local generatedFolder = workspace:FindFirstChild("AI_Generated")
	if generatedFolder and generatedFolder:IsA("Folder") then
		for _, child in ipairs(generatedFolder:GetChildren()) do
			child:Destroy()
		end
	end

	local toolsFolder = workspace:FindFirstChild("AI_Tools")
	if toolsFolder and toolsFolder:IsA("Folder") then
		for _, child in ipairs(toolsFolder:GetChildren()) do
			child:Destroy()
		end
	end
end

local currentStepFrame = nil

local function highlightStep(frame)
	if currentStepFrame and currentStepFrame:IsA("Frame") then
		currentStepFrame.BackgroundColor3 = Color3.fromRGB(220, 252, 231)
	end
	currentStepFrame = frame
	if currentStepFrame and currentStepFrame:IsA("Frame") then
		currentStepFrame.BackgroundColor3 = Color3.fromRGB(187, 247, 208)
	end
end

local function showError(message)
	createLabel(scrolling, "Error", true)
	appendStreamingText(scrolling, "-- ", tostring(message) .. "\n")
end

local function callGenerate(prompt, previousCode)
	if (not HttpService.HttpEnabled) and (not RunService:IsStudio()) then
		return nil, "HttpService is disabled. Enable it in Game Settings > Security (Studio Access to API Services)."
	end

	local url = API_BASE_URL .. "/generate"
	local payload = { prompt = prompt }
	if previousCode then
		payload.previous_code = previousCode
	end
	local body = HttpService:JSONEncode(payload)

	local ok, response = pcall(function()
		return HttpService:RequestAsync({
			Url = url,
			Method = "POST",
			Headers = makeHeaders(),
			Body = body,
		})
	end)

	if not ok then
		return nil, "HTTP request failed (pcall): " .. tostring(response)
	end

	if not response.Success then
		return nil, "HTTP error: " .. tostring(response.StatusCode) .. " " .. tostring(response.StatusMessage) .. "\n" .. tostring(response.Body)
	end

	local decoded = safeJsonDecode(response.Body)
	if not decoded then
		return nil, "Failed to decode JSON response"
	end

	return decoded, nil
end

local function callMemorySaveBuild(promptText, mode)
	if (not HttpService.HttpEnabled) and (not RunService:IsStudio()) then
		return nil, "HttpService is disabled. Enable it in Game Settings > Security (Studio Access to API Services)."
	end

	local scripts = collectScriptsSnapshot()
	local metadata = {
		user_id = MEMORY_USER_ID,
		mode = mode,
		template = selectedTemplateKey,
	}

	local url = API_BASE_URL .. "/memory/save_build"
	local body = HttpService:JSONEncode({
		prompt = promptText,
		scripts = scripts,
		metadata = metadata,
		status = "success",
	})

	local ok, response = pcall(function()
		return HttpService:RequestAsync({
			Url = url,
			Method = "POST",
			Headers = makeHeaders(),
			Body = body,
		})
	end)

	if not ok then
		return nil, "Memory save failed (pcall): " .. tostring(response)
	end
	if not response.Success then
		return nil, "Memory save HTTP error: " .. tostring(response.StatusCode) .. " " .. tostring(response.StatusMessage) .. "\n" .. tostring(response.Body)
	end

	local decoded = safeJsonDecode(response.Body)
	if not decoded or not decoded.build_id then
		return nil, "Memory save decode failed"
	end

	return tostring(decoded.build_id), nil
end

local function callMemoryListBuilds()
	if (not HttpService.HttpEnabled) and (not RunService:IsStudio()) then
		return nil, "HttpService is disabled. Enable it in Game Settings > Security (Studio Access to API Services)."
	end

	local url = API_BASE_URL .. "/memory/builds?limit=10&offset=0"
	local ok, response = pcall(function()
		return HttpService:RequestAsync({
			Url = url,
			Method = "GET",
			Headers = makeHeaders(),
		})
	end)

	if not ok then
		return nil, "Memory list failed (pcall): " .. tostring(response)
	end
	if not response.Success then
		return nil, "Memory list HTTP error: " .. tostring(response.StatusCode) .. " " .. tostring(response.StatusMessage) .. "\n" .. tostring(response.Body)
	end

	local decoded = safeJsonDecode(response.Body)
	if not decoded then
		return nil, "Memory list decode failed"
	end
	return decoded, nil
end

local function callMemoryGetBuild(buildId)
	if (not HttpService.HttpEnabled) and (not RunService:IsStudio()) then
		return nil, "HttpService is disabled. Enable it in Game Settings > Security (Studio Access to API Services)."
	end

	local url = API_BASE_URL .. "/memory/build/" .. tostring(buildId)
	local ok, response = pcall(function()
		return HttpService:RequestAsync({
			Url = url,
			Method = "GET",
			Headers = makeHeaders(),
		})
	end)

	if not ok then
		return nil, "Memory get failed (pcall): " .. tostring(response)
	end
	if not response.Success then
		return nil, "Memory get HTTP error: " .. tostring(response.StatusCode) .. " " .. tostring(response.StatusMessage) .. "\n" .. tostring(response.Body)
	end

	local decoded = safeJsonDecode(response.Body)
	if not decoded then
		return nil, "Memory get decode failed"
	end
	return decoded, nil
end

local function clearBuildButtons()
	for _, child in ipairs(buildsScroll:GetChildren()) do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

local function addBuildButton(build)
	local id = tostring(build.id or "")
	local promptText = tostring(build.prompt or "")
	local btn = Instance.new("TextButton")
	btn.BackgroundColor3 = Color3.fromRGB(241, 245, 249)
	btn.BorderSizePixel = 0
	btn.Size = UDim2.new(1, 0, 0, 28)
	btn.Font = Enum.Font.Gotham
	btn.TextSize = 12
	btn.TextColor3 = Color3.fromRGB(51, 65, 85)
	btn.TextXAlignment = Enum.TextXAlignment.Left
	btn.Text = "Load: " .. string.sub(id, 1, 8) .. "  |  " .. string.sub(promptText, 1, 40)
	btn.Parent = buildsScroll
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = btn
	addButtonEffects(btn, Color3.fromRGB(241, 245, 249), Color3.fromRGB(226, 232, 240), Color3.fromRGB(203, 213, 225))

	btn.MouseButton1Click:Connect(function()
		buildsStatusLabel.Text = "Loading..."
		local data, err = callMemoryGetBuild(id)
		if err then
			buildsStatusLabel.Text = "Load failed"
			createLabel(scrolling, "Memory", true)
			appendStreamingText(scrolling, "-- ", err .. "\n")
			return
		end

		local scripts = data.scripts_json
		if type(scripts) ~= "table" or #scripts == 0 then
			local steps = data.steps_json
			if type(steps) == "table" and #steps > 0 then
				scripts = {}
				for i, step in ipairs(steps) do
					table.insert(scripts, {
						name = tostring(step.title or ("Step_" .. tostring(i))),
						source = tostring(step.code or ""),
					})
				end
			end
		end

		if type(scripts) ~= "table" or #scripts == 0 then
			buildsStatusLabel.Text = "No scripts in build"
			createLabel(scrolling, "Memory", true)
			appendStreamingText(scrolling, "-- ", "Selected build has prompt/history but no script snapshot to restore.\n")
			return
		end

		local folder = getOrCreateGeneratedFolder()
		local loadedCount = 0
		for _, s in ipairs(scripts) do
			local name = sanitizeInstanceName(s.name or "Script")
			local source = tostring(s.source or "")
			local ok = upsertScript(folder, name, source)
			if ok then
				loadedCount += 1
			end
		end

		buildsStatusLabel.Text = "Loaded (" .. tostring(loadedCount) .. ")"
	end)
end

refreshBuildsButton.MouseButton1Click:Connect(function()
	buildsStatusLabel.Text = "Refreshing..."
	clearBuildButtons()
	local data, err = callMemoryListBuilds()
	if err then
		buildsStatusLabel.Text = "Failed"
		return
	end

	local items = data.items
	if type(items) ~= "table" then
		buildsStatusLabel.Text = "No data"
		return
	end

	for _, b in ipairs(items) do
		addBuildButton(b)
	end
	buildsStatusLabel.Text = "Ready"
end)

local function callToolsPlan(promptText)
	if (not HttpService.HttpEnabled) and (not RunService:IsStudio()) then
		return nil, "HttpService is disabled. Enable it in Game Settings > Security (Studio Access to API Services)."
	end

	local url = API_BASE_URL .. "/tools/plan"
	local body = HttpService:JSONEncode({ prompt = promptText })

	local ok, response = pcall(function()
		return HttpService:RequestAsync({
			Url = url,
			Method = "POST",
			Headers = makeHeaders(),
			Body = body,
		})
	end)

	if not ok then
		return nil, "Tools plan failed (pcall): " .. tostring(response)
	end
	if not response.Success then
		return nil, "Tools plan HTTP error: " .. tostring(response.StatusCode) .. " " .. tostring(response.StatusMessage) .. "\n" .. tostring(response.Body)
	end

	local decoded = safeJsonDecode(response.Body)
	if not decoded then
		return nil, "Tools plan decode failed"
	end
	return decoded, nil
end

local function updateExecuteButton()
	local enabled = plannedToolCalls ~= nil and type(plannedToolCalls.tool_calls) == "table" and #plannedToolCalls.tool_calls > 0
	executeToolsButton.Active = enabled
	executeToolsButton.AutoButtonColor = enabled
	executeToolsButton.BackgroundColor3 = enabled and Color3.fromRGB(34, 197, 94) or Color3.fromRGB(241, 245, 249)
	executeToolsButton.TextColor3 = enabled and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(100, 116, 139)
end

updateExecuteButton()

planToolsButton.MouseButton1Click:Connect(function()
	toolsStatusLabel.Text = "Planning..."
	plannedToolCalls = nil
	toolsPreview.Text = ""
	updateExecuteButton()

	local promptText = buildPromptWithTemplate(promptBox.Text)
	if string.gsub(promptText, "%s+", "") == "" then
		toolsStatusLabel.Text = "Empty prompt"
		return
	end

	local result, err = callToolsPlan(promptText)
	if err then
		toolsStatusLabel.Text = "Plan failed"
		toolsPreview.Text = err
		return
	end

	plannedToolCalls = result
	toolsStatusLabel.Text = "Planned"
	toolsPreview.Text = HttpService:JSONEncode(result)
	updateExecuteButton()
end)

executeToolsButton.MouseButton1Click:Connect(function()
	if not plannedToolCalls or type(plannedToolCalls.tool_calls) ~= "table" then
		toolsStatusLabel.Text = "Nothing to execute"
		return
	end

	toolsStatusLabel.Text = "Executing..."
	local okCount = 0
	local failCount = 0

	for _, callObj in ipairs(plannedToolCalls.tool_calls) do
		local ok, msg = executeToolCall(callObj)
		if ok then
			okCount += 1
		else
			failCount += 1
			createLabel(scrolling, "Tool Error", true)
			appendStreamingText(scrolling, "-- ", tostring(msg) .. "\n")
		end
	end

	toolsStatusLabel.Text = "Done (" .. tostring(okCount) .. " ok, " .. tostring(failCount) .. " failed)"
end)

local function callStart(prompt)
	if (not HttpService.HttpEnabled) and (not RunService:IsStudio()) then
		return nil, "HttpService is disabled. Enable it in Game Settings > Security (Studio Access to API Services)."
	end

	local url = API_BASE_URL .. "/start"
	local body = HttpService:JSONEncode({ prompt = prompt })

	local ok, response = pcall(function()
		return HttpService:RequestAsync({
			Url = url,
			Method = "POST",
			Headers = makeHeaders(),
			Body = body,
		})
	end)

	if not ok then
		return nil, "HTTP request failed (pcall): " .. tostring(response)
	end

	if not response.Success then
		return nil, "HTTP error: " .. tostring(response.StatusCode) .. " " .. tostring(response.StatusMessage) .. "\n" .. tostring(response.Body)
	end

	local decoded = safeJsonDecode(response.Body)
	if not decoded or not decoded.session_id then
		return nil, "Failed to decode /start response"
	end

	return tostring(decoded.session_id), nil
end

local function callRefineStart(prompt, previousCode)
	if (not HttpService.HttpEnabled) and (not RunService:IsStudio()) then
		return nil, "HttpService is disabled. Enable it in Game Settings > Security (Studio Access to API Services)."
	end

	local url = API_BASE_URL .. "/refine_start"
	local body = HttpService:JSONEncode({
		prompt = prompt,
		previous_code = previousCode,
	})

	local ok, response = pcall(function()
		return HttpService:RequestAsync({
			Url = url,
			Method = "POST",
			Headers = makeHeaders(),
			Body = body,
		})
	end)

	if not ok then
		return nil, "HTTP request failed (pcall): " .. tostring(response)
	end

	if not response.Success then
		return nil, "HTTP error: " .. tostring(response.StatusCode) .. " " .. tostring(response.StatusMessage) .. "\n" .. tostring(response.Body)
	end

	local decoded = safeJsonDecode(response.Body)
	if not decoded or not decoded.session_id then
		return nil, "Failed to decode /refine_start response"
	end

	return tostring(decoded.session_id), nil
end

local function callStartLive(prompt)
	if (not HttpService.HttpEnabled) and (not RunService:IsStudio()) then
		return nil, "HttpService is disabled. Enable it in Game Settings > Security (Studio Access to API Services)."
	end

	local url = API_BASE_URL .. "/start_live"
	local body = HttpService:JSONEncode({ prompt = prompt })

	local ok, response = pcall(function()
		return HttpService:RequestAsync({
			Url = url,
			Method = "POST",
			Headers = makeHeaders(),
			Body = body,
		})
	end)

	if not ok then
		return nil, "HTTP request failed (pcall): " .. tostring(response)
	end

	if not response.Success then
		return nil, "HTTP error: " .. tostring(response.StatusCode) .. " " .. tostring(response.StatusMessage) .. "\n" .. tostring(response.Body)
	end

	local decoded = safeJsonDecode(response.Body)
	if not decoded or not decoded.session_id then
		return nil, "Failed to decode /start_live response"
	end

	return tostring(decoded.session_id), nil
end

local function callStream(sessionId)
	if (not HttpService.HttpEnabled) and (not RunService:IsStudio()) then
		return nil, "HttpService is disabled. Enable it in Game Settings > Security (Studio Access to API Services)."
	end

	local url = API_BASE_URL .. "/stream/" .. tostring(sessionId)
	local ok, response = pcall(function()
		return HttpService:RequestAsync({
			Url = url,
			Method = "GET",
			Headers = makeHeaders(),
		})
	end)

	if not ok then
		return nil, "HTTP request failed (pcall): " .. tostring(response)
	end

	if not response.Success then
		return nil, "HTTP error: " .. tostring(response.StatusCode) .. " " .. tostring(response.StatusMessage) .. "\n" .. tostring(response.Body)
	end

	local decoded = safeJsonDecode(response.Body)
	if not decoded then
		return nil, "Failed to decode /stream response"
	end

	return decoded, nil
end

local function callFix(errorMessage, code)
	if (not HttpService.HttpEnabled) and (not RunService:IsStudio()) then
		return nil, "HttpService is disabled. Enable it in Game Settings > Security (Studio Access to API Services)."
	end

	local url = API_BASE_URL .. "/fix"
	local body = HttpService:JSONEncode({
		error_message = errorMessage,
		code = code,
	})

	local ok, response = pcall(function()
		return HttpService:RequestAsync({
			Url = url,
			Method = "POST",
			Headers = makeHeaders(),
			Body = body,
		})
	end)

	if not ok then
		return nil, "HTTP request failed (pcall): " .. tostring(response)
	end

	if not response.Success then
		return nil, "HTTP error: " .. tostring(response.StatusCode) .. " " .. tostring(response.StatusMessage) .. "\n" .. tostring(response.Body)
	end

	return tostring(response.Body or ""), nil
end

local function callDebug(errorMessage, code)
	if (not HttpService.HttpEnabled) and (not RunService:IsStudio()) then
		return nil, "HttpService is disabled. Enable it in Game Settings > Security (Studio Access to API Services)."
	end

	local url = API_BASE_URL .. "/debug"
	local body = HttpService:JSONEncode({
		error_message = errorMessage,
		code = code,
	})

	local ok, response = pcall(function()
		return HttpService:RequestAsync({
			Url = url,
			Method = "POST",
			Headers = makeHeaders(),
			Body = body,
		})
	end)

	if not ok then
		return nil, "HTTP request failed (pcall): " .. tostring(response)
	end

	if not response.Success then
		return nil, "HTTP error: " .. tostring(response.StatusCode) .. " " .. tostring(response.StatusMessage) .. "\n" .. tostring(response.Body)
	end

	return tostring(response.Body or ""), nil
end

local function runGenerate(isRefine)
	activeRunToken += 1
	local runToken = activeRunToken
	local function isCancelled()
		return runToken ~= activeRunToken
	end

	local prompt = withExplorerPathRules(buildPromptWithTemplate(promptBox.Text))
	if string.gsub(prompt, "%s+", "") == "" then
		clearChildrenExceptLayout(scrolling)
		showError("Prompt is empty")
		return
	end

	clearChildrenExceptLayout(scrolling)
	setBusy(true, isRefine and "refine" or "generate")
	startProgressAnimation(isRefine and "Refining" or "Generating")

	task.spawn(function()
		if isCancelled() then
			return
		end
		if isRefine then
			local previousCode = collectPreviousCode()
			if not previousCode then
				stopProgressAnimation("Failed")
				showError("No scripts found in project scan to refine")
				setBusy(false)
				return
			end

			local sessionId, startErr = callRefineStart(prompt, previousCode)
			if isCancelled() then
				return
			end
			if startErr then
				stopProgressAnimation("Failed")
				showError(startErr)
				setBusy(false)
				return
			end

			stopProgressAnimation("Streaming...")
			startProgressAnimation("Streaming")

			local liveFrame = createStepTitle(scrolling, "Live Output")
			highlightStep(liveFrame)
			local liveLabel = createLabel(scrolling, "", false)
			liveLabel.Text = ""

			local lastLen = 0
			local finalText = ""
			while true do
				if isCancelled() then
					return
				end
				local snapshot, streamErr = callStream(sessionId)
				if streamErr then
					stopProgressAnimation("Failed")
					showError(streamErr)
					setBusy(false)
					return
				end

				if snapshot.error then
					stopProgressAnimation("Failed")
					showError(snapshot.error)
					setBusy(false)
					return
				end

				local text = tostring(snapshot.text or "")
				finalText = text
				if #text > lastLen then
					local newText = string.sub(text, lastLen + 1)
					liveLabel.Text = liveLabel.Text .. newText
					lastLen = #text
				end

				if snapshot.done then
					break
				end

				task.wait(0.3)
			end

			stopProgressAnimation("Parsing...")
			startProgressAnimation("Parsing")

			local decoded = safeJsonDecode(finalText)
			if not decoded then
				stopProgressAnimation("Failed")
				showError("Failed to decode final streamed JSON")
				setBusy(false)
				return
			end

			local steps = decoded.steps
			if type(steps) ~= "table" then
				stopProgressAnimation("Failed")
				showError("Response missing 'steps'")
				setBusy(false)
				return
			end

			stopProgressAnimation("Building...")
			startProgressAnimation("Building")

			local generatedFolder = getOrCreateGeneratedFolder()

			for i, step in ipairs(steps) do
				local title = tostring(step.title or ("Step " .. tostring(i)))
				local code = tostring(step.code or "")

				local stepFrame = createStepTitle(scrolling, title)
				highlightStep(stepFrame)
				stopProgressAnimation("")
				startProgressAnimation("" .. title)
				appendStreamingText(scrolling, "", code .. "\n")

				local targetParent, scriptName, usedExplorerPath, targetErr = resolveScriptTarget(title, generatedFolder)
				if targetErr then
					local pathErrFrame = createStepTitle(scrolling, "Path Warning")
					highlightStep(pathErrFrame)
					appendStreamingText(scrolling, "-- ", targetErr .. ". Using Workspace.AI_Generated fallback.\n")
				end
				local ok, insertErr = upsertScript(targetParent, scriptName, code)
				if not ok then
					local errFrame = createStepTitle(scrolling, "Insertion Error")
					highlightStep(errFrame)
					appendStreamingText(scrolling, "-- ", tostring(insertErr) .. "\n")
				elseif usedExplorerPath then
					appendStreamingText(scrolling, "-- ", "Updated " .. targetParent:GetFullName() .. "." .. scriptName .. "\n")
				end
			end

			stopProgressAnimation("Done")
			buildsStatusLabel.Text = "Saving build..."
			local buildId, memErr = callMemorySaveBuild(prompt, "refine")
			if memErr then
				buildsStatusLabel.Text = "Save failed"
			else
				buildsStatusLabel.Text = "Saved " .. string.sub(buildId, 1, 8)
			end
			setBusy(false)
			return
		end

		local sessionId, startErr = callStartLive(prompt)
		if isCancelled() then
			return
		end
		if startErr then
			stopProgressAnimation("Failed")
			showError(startErr)
			setBusy(false)
			return
		end

		stopProgressAnimation("Streaming...")
		startProgressAnimation("Streaming")

		local generatedFolder = getOrCreateGeneratedFolder()
		local usedNames = {}
		local liveFrame = createStepTitle(scrolling, "Live Stream")
		highlightStep(liveFrame)
		local liveLabel = createLabel(scrolling, "", false)
		liveLabel.Text = ""

		local lastLen = 0
		local buffer = ""
		local currentTitle = nil
		local currentCode = ""
		local currentFrame = nil
		local currentCodeLabel = nil
		local stepIndex = 0

		local function finalizeStep()
			if not currentTitle then
				return
			end
			local targetParent, scriptName, usedExplorerPath, targetErr = resolveScriptTarget(currentTitle, generatedFolder)
			if targetErr then
				local pathErrFrame = createStepTitle(scrolling, "Path Warning")
				highlightStep(pathErrFrame)
				appendStreamingText(scrolling, "-- ", targetErr .. ". Using Workspace.AI_Generated fallback.\n")
			end
			local baseName = usedExplorerPath and scriptName or ("Step" .. tostring(stepIndex) .. "_" .. sanitizeInstanceName(currentTitle))
			local ok, insertErr, createdName = insertScriptNoOverwrite(targetParent, baseName, currentCode)
			if not ok then
				local errFrame = createStepTitle(scrolling, "Insertion Error")
				highlightStep(errFrame)
				appendStreamingText(scrolling, "-- ", tostring(insertErr) .. "\n")
			else
				usedNames[createdName] = true
				if usedExplorerPath then
					appendStreamingText(scrolling, "-- ", "Created " .. targetParent:GetFullName() .. "." .. createdName .. "\n")
				end
			end
		end

		local function startNewStep(title)
			finalizeStep()
			stepIndex += 1
			currentTitle = title
			currentCode = ""
			currentFrame = createStepTitle(scrolling, title)
			highlightStep(currentFrame)
			stopProgressAnimation("")
			startProgressAnimation(title)
			currentCodeLabel = createLabel(scrolling, "", false)
			currentCodeLabel.Text = ""
		end

		local function processBuffer()
			while true do
				local headerStart = string.find(buffer, "[Step ", 1, true)
				if not headerStart then
					return
				end

				if headerStart ~= 1 then
					local before = string.sub(buffer, 1, headerStart - 1)
					if currentCodeLabel then
						currentCode = currentCode .. before
						currentCodeLabel.Text = currentCode
					end
					buffer = string.sub(buffer, headerStart)
				end

				local lineEnd = string.find(buffer, "\n", 1, true)
				if not lineEnd then
					return
				end

				local headerLine = string.sub(buffer, 1, lineEnd - 1)
				local title = string.match(headerLine, "^%[Step%s+%d+%]%s*(.-)%.%.%.$")
				if title then
					startNewStep(title)
				end
				buffer = string.sub(buffer, lineEnd + 1)
			end
		end

		while true do
			if isCancelled() then
				return
			end
			local snapshot, streamErr = callStream(sessionId)
			if streamErr then
				stopProgressAnimation("Failed")
				showError(streamErr)
				setBusy(false)
				return
			end

			if snapshot.error then
				stopProgressAnimation("Failed")
				showError(snapshot.error)
				setBusy(false)
				return
			end

			local text = tostring(snapshot.text or "")
			if #text > lastLen then
				local delta = string.sub(text, lastLen + 1)
				lastLen = #text
				liveLabel.Text = liveLabel.Text .. delta
				buffer = buffer .. delta
				processBuffer()
				if currentCodeLabel and buffer ~= "" and string.find(buffer, "[Step ", 1, true) == nil then
					currentCode = currentCode .. buffer
					currentCodeLabel.Text = currentCode
					buffer = ""
				end
			end

			if snapshot.done then
				if buffer ~= "" and currentCodeLabel then
					currentCode = currentCode .. buffer
					currentCodeLabel.Text = currentCode
					buffer = ""
				end
				finalizeStep()
				break
			end

			task.wait(0.3)
		end

		-- Generate flow now creates new modular scripts per step and does not overwrite/delete previous scripts.

		stopProgressAnimation("Done")
		buildsStatusLabel.Text = "Saving build..."
		local buildId, memErr = callMemorySaveBuild(prompt, "generate")
		if memErr then
			buildsStatusLabel.Text = "Save failed"
		else
			buildsStatusLabel.Text = "Saved " .. string.sub(buildId, 1, 8)
		end
		setBusy(false)
	end)

end

generateButton.MouseButton1Click:Connect(function()
	runGenerate(false)
end)

refineButton.MouseButton1Click:Connect(function()
	runGenerate(true)
end)

stopButton.MouseButton1Click:Connect(function()
	if not isRunActive then
		return
	end
	activeRunToken += 1
	stopProgressAnimation("Stopped")
	setBusy(false)
	createLabel(scrolling, "Stopped", true)
	appendStreamingText(scrolling, "-- ", "Current generation/refine was cancelled by user.\n")
end)

clearAllButton.MouseButton1Click:Connect(function()
	activeRunToken += 1
	stopProgressAnimation("Cleared")
	setBusy(false)
	clearGeneratedArtifacts()
	clearChildrenExceptLayout(scrolling)
	promptBox.Text = ""
	selectedTemplateKey = nil
	updateTemplateButtonStyles()
	plannedToolCalls = nil
	toolsPreview.Text = ""
	toolsStatusLabel.Text = "Cleared"
	buildsStatusLabel.Text = "Cleared"
	statusLabel.Text = "🧠 AI is ready"
end)

local function tryAutoFixFromMessage(message)
	local msg = tostring(message or "")
	local scriptName = string.match(msg, "Workspace%.AI_Generated%.([%w_]+)")
	if not scriptName then
		scriptName = string.match(msg, "AI_SCRIPT_ERROR:([%w_]+):")
	end
	if not scriptName or scriptName == "" then
		return
	end

	local now = os.clock()
	local last = lastFixAttemptAtByName[scriptName] or 0
	if (now - last) < 3 then
		return
	end
	lastFixAttemptAtByName[scriptName] = now

	local scriptObj = scriptObjectByDebugKey[scriptName]
	if not scriptObj or not scriptObj:IsA("Script") then
		local folder = workspace:FindFirstChild("AI_Generated")
		if not folder or not folder:IsA("Folder") then
			return
		end
		scriptObj = folder:FindFirstChild(scriptName)
		if not scriptObj or not scriptObj:IsA("Script") then
			return
		end
	end

	local original = scriptOriginalSourceByName[scriptName]
	if not original then
		original = scriptObj.Source
	end

	local retryCount = debugRetryCountByName[scriptName] or 0
	if retryCount >= MAX_DEBUG_RETRIES then
		createLabel(scrolling, "Auto Debug", true)
		appendStreamingText(scrolling, "-- ", "Max retries reached for " .. scriptName .. "\n")
		return
	end

	statusLabel.Text = "Fixing " .. scriptName .. "..."
	startProgressAnimation("Fixing scripts")
	local fixFrame = createStepTitle(scrolling, "Fixing " .. scriptName)
	highlightStep(fixFrame)
	appendStreamingText(scrolling, "-- ", "Detected error in " .. scriptName .. "\n")

	task.spawn(function()
		debugRetryCountByName[scriptName] = retryCount + 1
		local fixed, err = callDebug(msg, original)
		if err then
			appendStreamingText(scrolling, "-- ", "Fix failed: " .. tostring(err) .. "\n")
			stopProgressAnimation("Fix failed")
			return
		end

		scriptOriginalSourceByName[scriptName] = fixed
		local wrapped = wrapWithPcall(scriptName, fixed)
		local ok, setErr = pcall(function()
			scriptObj.Source = wrapped
			if scriptObj.Disabled then
				scriptObj.Disabled = false
			else
				scriptObj.Disabled = true
				scriptObj.Disabled = false
			end
		end)

		if not ok then
			appendStreamingText(scrolling, "-- ", "Failed to apply fix: " .. tostring(setErr) .. "\n")
			stopProgressAnimation("Fix apply failed")
			return
		end

		appendStreamingText(scrolling, "-- ", "Applied debug fix for " .. scriptName .. " (attempt " .. tostring(debugRetryCountByName[scriptName]) .. ")\n")
		stopProgressAnimation("Fixed " .. scriptName)
	end)
end

LogService.MessageOut:Connect(function(message, messageType)
	if messageType == Enum.MessageType.MessageError then
		tryAutoFixFromMessage(message)
	end
end)

createLabel(scrolling, "Tips", true)
createLabel(scrolling, "- Enable HttpService in Game Settings", false)
createLabel(scrolling, "- If calls fail, verify Studio can reach the API_BASE_URL", false)
