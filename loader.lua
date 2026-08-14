local PUBLIC_BUILD = true

if PUBLIC_BUILD then
	shared.PistonwareDeveloper = nil
	pcall(function()
		if getmetatable(shared) ~= nil then return end
		setmetatable(shared, {
			__index = function(self, key)
				if key == 'PistonwareDeveloper' then return nil end
				return rawget(self, key)
			end,
			__newindex = function(self, key, value)
				if key == 'PistonwareDeveloper' then return end
				rawset(self, key, value)
			end
		})
	end)
end

local isDeveloper = (not PUBLIC_BUILD) and shared.PistonwareDeveloper and true or false

if shared.PistonwareLoaderBoot and os.clock() - shared.PistonwareLoaderBoot < 180 then
	warn('[pistonware] loader is already running, ignoring duplicate execution')
	return
end
shared.PistonwareLoaderBoot = os.clock()

local isfile = isfile or function(file)
	local suc, res = pcall(function()
		return readfile(file)
	end)
	return suc and res ~= nil and res ~= ''
end
local cloneref = cloneref or function(ref)
	return ref
end
local delfile = delfile or function(file)
	writefile(file, '')
end

local setclipboard = setclipboard or toclipboard or (Clipboard and Clipboard.set)

local Watermark = '--This watermark is used to delete the file if its cached, remove it to make the file persist after ClayV1 updates.'

-- ========================================================================
-- YOUR REAL KEY (hardcoded)
-- ========================================================================
local MY_KEY = 'hoiSqvIOrZRNERiPccoCDpzIYsuIcaRy'

local SCRIPT_ID   = '2fb6964a070d89a7650354a0dcce302c'
local GETKEY_URL  = 'https://ads.luarmor.net/get_key?for=Pistonware_Key-xnpnovpEljPO'
local KEY_FILE    = 'pistonwarekey.json'
local TARGET_URL  = 'https://gitlab.com/pistonware/pistonware/-/raw/main/bedwars.lua'  -- use the original – your key will validate it
local HELP_URL    = 'https://discord.gg/pistonware'

-- ========================================================================
-- Strings – changed to "ClayV1" for user-facing notifications
-- ========================================================================
local Strings = {
	enter_key       = 'Enter your key below to continue.',
	saved_expired   = 'Your key expired - renew it, then run again. It is still saved.',
	saved_hwid      = 'Your key is linked to another device - reset your HWID, then run again. The key itself is still good and is still saved.',
	saved_incorrect = 'Saved key no longer exists - get a new one.',
	saved_banned    = 'Saved key is blacklisted.',
	placeholder     = 'Paste your key here',
	get_key         = 'Get Key',
	paste           = 'Paste',
	submit          = 'Submit',
	footer          = 'No key? Get Key -> finish checkpoints -> paste above.',
	empty_key       = 'Enter your key first.',
	bad_format      = "That doesn't look like a valid key.",
	checking        = 'Checking key...',
	valid_loading   = 'Key valid%s - loading...',
	hwid_locked     = 'That key is linked to another device - reset your HWID via the bot, then submit it again.',
	expired         = 'That key has expired - renew it, then submit it again.',
	time_left       = '%s left',
	lifetime        = 'lifetime',
	banned          = 'Key is blacklisted.',
	incorrect       = 'Key is incorrect or has been deleted.',
	invalid_format  = 'Invalid key format.',
	check_failed    = 'Check failed: %s (%s)',
	link_copied     = 'Link copied! Finish the checkpoints, then paste your key.',
	pasted          = 'Pasted from clipboard.',
	clipboard_empty = 'Clipboard is empty.',
	need_help       = 'Need Help?',
	help_copied     = 'Help link copied to your clipboard!',
	copy_failed     = 'Failed to copy script.',
	no_library      = 'Failed to load the LuaArmor library.',
	cancelled       = 'Key entry cancelled.',
	headless        = 'No valid key saved - run the loader manually to enter one.'
}

local function t(key, ...)
	local s = Strings[key] or key
	if select('#', ...) > 0 then
		return string.format(s, ...)
	end
	return s
end

local function formatDuration(seconds)
	if seconds <= 0 then return nil end
	local days = math.floor(seconds / 86400)
	if days >= 1 then return days..(days == 1 and ' day' or ' days') end
	local hours = math.floor(seconds / 3600)
	if hours >= 1 then return hours..(hours == 1 and ' hour' or ' hours') end
	local minutes = math.max(1, math.floor(seconds / 60))
	return minutes..(minutes == 1 and ' minute' or ' minutes')
end

local function keyDetail(status)
	local data = type(status) == 'table' and type(status.data) == 'table' and status.data or nil
	if not data then return '' end
	local parts = {}
	if data.note ~= nil and tostring(data.note) ~= '' then
		table.insert(parts, tostring(data.note))
	end
	local expire = tonumber(data.auth_expire)
	if expire == -1 or expire == 0 then
		table.insert(parts, t('lifetime'))
	elseif expire then
		local left = formatDuration(expire - os.time())
		if left then table.insert(parts, t('time_left', left)) end
	end
	if #parts == 0 then return '' end
	return ' ('..table.concat(parts, ', ')..')'
end

local function trim(s)
	return (tostring(s):gsub('^%s*(.-)%s*$', '%1'))
end

local function hasContent(path)
	if not isfile(path) then return false end
	local ok, body = pcall(readfile, path)
	return ok and type(body) == 'string' and body ~= ''
end

local function downloadFile(path, func)
	if not hasContent(path) then
		local relPath = select(1, path:gsub('pistonware/', ''))
		local isBedwars = relPath == 'games/bedwars.lua'
		local content
		for attempt = 1, 4 do
			local suc, res = pcall(function()
				if isBedwars then
					return game:HttpGet(TARGET_URL, true)
				end
				return game:HttpGet('https://raw.githubusercontent.com/themagicpiston/pistonware/main/'..relPath, true)
			end)
			if suc and res and res ~= '' and res ~= '404: Not Found' and (not path:find('.lua') or loadstring(res) ~= nil) then
				content = res
				break
			end
			if attempt < 4 then
				task.wait(attempt)
			end
		end
		if not content then
			error('failed to download '..path..' after 4 attempts')
		end
		if path:find('.lua') then
			content = Watermark..'\n'..content
		end
		writefile(path, content)
	end
	return (func or readfile)(path)
end

local function fetchProfilesListing(ref)
	local reqSuc, res = pcall(function()
		return game:HttpGet('https://api.github.com/repos/themagicpiston/pistonware/contents/profiles'..(ref and ('?ref='..ref) or ''), true)
	end)
	if not (reqSuc and res and res ~= '404: Not Found') then return nil end
	local bodySuc, body = pcall(function()
		return cloneref(game:GetService('HttpService')):JSONDecode(res)
	end)
	if not (bodySuc and body and typeof(body) == 'table') then return nil end
	return body
end

local function mergeGuiState(path, incoming)
	if not path:find('%.gui%.txt$') then return incoming end
	local ok, merged = pcall(function()
		local httpService = cloneref(game:GetService('HttpService'))
		local new = httpService:JSONDecode(incoming)
		if type(new) ~= 'table' then return incoming end
		if isfile(path) then
			local old = httpService:JSONDecode(readfile(path))
			if type(old) == 'table' then
				if old.Profiles ~= nil then new.Profiles = old.Profiles end
				if old.Profile ~= nil then new.Profile = old.Profile end
			end
		end
		return httpService:JSONEncode(new)
	end)
	return (ok and type(merged) == 'string') and merged or incoming
end

local function downloadProfilesListing(body, commit, onProgress)
	local files = {}
	for _, v in body do
		if v.type == 'file' then
			table.insert(files, v)
		end
	end
	local completed, pending, total = 0, #files, #files
	local done = Instance.new('BindableEvent')
	for _, v in files do
		local relPath = ({v.path:gsub(' ', '%%20')})[1]
		task.spawn(function()
			if commit then
				pcall(function()
					for attempt = 1, 4 do
						local suc, res = pcall(function()
							return game:HttpGet('https://raw.githubusercontent.com/themagicpiston/pistonware/'..commit..'/'..relPath, true)
						end)
						if suc and res and res ~= '' and res ~= '404: Not Found' then
							writefile('pistonware/'..relPath, mergeGuiState('pistonware/'..relPath, res))
							break
						end
						if attempt < 4 then
							task.wait(attempt)
						end
					end
				end)
			else
				pcall(downloadFile, 'pistonware/'..relPath)
			end
			completed += 1
			pending -= 1
			if onProgress then
				onProgress(completed, total)
			end
			if pending <= 0 then
				done:Fire()
			end
		end)
	end
	if pending > 0 then
		done.Event:Wait()
	end
	done:Destroy()
end

local function fetchProfilesCommit()
	local reqSuc, res = pcall(function()
		return game:HttpGet('https://api.github.com/repos/themagicpiston/pistonware/commits?path=profiles&sha=main&per_page=1', true)
	end)
	if not (reqSuc and res and res ~= '404: Not Found') then return nil end
	local bodySuc, body = pcall(function()
		return cloneref(game:GetService('HttpService')):JSONDecode(res)
	end)
	if not (bodySuc and body and typeof(body) == 'table' and body[1] and body[1].sha) then return nil end
	return body[1].sha
end

local function updateCachedFiles(onProgress)
	local httpService = cloneref(game:GetService('HttpService'))

	local headSuc, headSha = pcall(function()
		return httpService:JSONDecode(game:HttpGet('https://api.github.com/repos/themagicpiston/pistonware/commits?sha=main&per_page=1', true))[1].sha
	end)
	if not (headSuc and type(headSha) == 'string') then return end

	local treeSuc, tree = pcall(function()
		return httpService:JSONDecode(game:HttpGet('https://api.github.com/repos/themagicpiston/pistonware/git/trees/'..headSha..'?recursive=1', true))
	end)
	if not (treeSuc and type(tree) == 'table' and type(tree.tree) == 'table') then return end

	local manifest = {}
	pcall(function()
		if isfile('pistonware/filecheck.json') then
			local decoded = httpService:JSONDecode(readfile('pistonware/filecheck.json'))
			if type(decoded) == 'table' then
				manifest = decoded
			end
		end
	end)

	local remote = {}
	for _, v in tree.tree do
		if v.type == 'blob' and v.path:sub(-4) == '.lua' then
			remote[v.path] = v.sha
		end
	end

	local function managed(localPath)
		if not isfile(localPath) then return false end
		if PUBLIC_BUILD then return true end
		return readfile(localPath):sub(1, #Watermark) == Watermark
	end

	local toUpdate = {}
	for path, sha in remote do
		local localPath = 'pistonware/'..path
		if manifest[path] ~= sha and managed(localPath) then
			table.insert(toUpdate, path)
		end
	end

	local changed = false

	if not tree.truncated then
		for path in manifest do
			if not remote[path] then
				pcall(function()
					local localPath = 'pistonware/'..path
					if managed(localPath) then
						delfile(localPath)
					end
				end)
				manifest[path] = nil
				changed = true
			end
		end
	end

	local completed, pending, total = 0, #toUpdate, #toUpdate
	if total > 0 then
		local done = Instance.new('BindableEvent')
		for _, path in toUpdate do
			task.spawn(function()
				for attempt = 1, 4 do
					local suc, res = pcall(function()
						return game:HttpGet('https://raw.githubusercontent.com/themagicpiston/pistonware/'..headSha..'/'..select(1, path:gsub(' ', '%%20')), true)
					end)
					if suc and res and res ~= '' and res ~= '404: Not Found' and loadstring(res) ~= nil then
						pcall(writefile, 'pistonware/'..path, Watermark..'\n'..res)
						manifest[path] = remote[path]
						changed = true
						break
					end
					if attempt < 4 then
						task.wait(attempt)
					end
				end
				completed += 1
				pending -= 1
				if onProgress then
					onProgress(completed, total)
				end
				if pending <= 0 then
					done:Fire()
				end
			end)
		end
		if pending > 0 then
			done.Event:Wait()
		end
		done:Destroy()
	end

	if changed then
		pcall(writefile, 'pistonware/filecheck.json', httpService:JSONEncode(manifest))
	end
end

-- ========================================================================
-- Loader Console – changed title to "ClayV1"
-- ========================================================================
local PistonFace = {
	'******=============******++++++=============******',
	'******=============******++++++=============******',
	'******=============******++++++=============******',
	'++++++=============++++++===================++++++',
	'++++++=============++++++===================++++++',
	'++++++=============++++++===================++++++',
	'::::::@@@@@@       ------::::::@@@@@@       ::::::',
	'::::::@@@@@@       ------::::::@@@@@@       ::::::',
	'::::::@@@@@@       ------::::::@@@@@@       ::::::',
	'::::::@@@@@@       ++++++------@@@@@@       ::::::',
	'::::::@@@@@@       ++++++------@@@@@@       ::::::',
	'::::::@@@@@@       ++++++------@@@@@@       ::::::',
	'::::::######:::::::++++++======******:::::::::::::',
	'::::::++++++=======++++++++++++=============::::::',
	'::::::++++++=======++++++++++++=============::::::',
	'::::::++++++=======++++++++++++=============::::::',
	'------++++++                         =======------',
	'------++++++                         =======------',
	'------++++++                         =======------',
	'::::::=============      ++++++++++++=======::::::',
	'::::::=============      ++++++++++++=======::::::',
	'::::::=============      ++++++++++++=======::::::',
	'::::::------:::::::------::::::------:::::::::::::',
	'::::::------:::::::------::::::------:::::::::::::',
	'::::::------:::::::------::::::------:::::::::::::'
}

local WindowWidth = 1000
local TitleBarHeight = 44
local ContentPadding = 26
local AsciiTextSize = 20
local AsciiLineHeight = 18
local AsciiTop = TitleBarHeight + 16
local StatusY = AsciiTop + #PistonFace * AsciiLineHeight + 16
local LineY = StatusY + 32
local AnswersY = LineY + 30
local WindowHeight = AnswersY + 34 + 30 + 22 + 16

local Palette = {
	Window = Color3.fromRGB(10, 10, 10),
	TitleBar = Color3.fromRGB(38, 38, 38),
	Border = Color3.fromRGB(52, 52, 52),
	Title = Color3.fromRGB(232, 232, 232),
	Glyph = Color3.fromRGB(190, 190, 190),
	Accent = Color3.fromRGB(240, 122, 31),
	Line = Color3.fromRGB(237, 237, 237),
	Footer = Color3.fromRGB(110, 110, 110),
	ButtonIdle = Color3.fromRGB(200, 200, 200),
	ButtonBorder = Color3.fromRGB(60, 60, 60),
	Error = Color3.fromRGB(225, 80, 70),
	Ok = Color3.fromRGB(120, 225, 150)
}

local AsciiShades = {
	['@'] = '#F2F2F2',
	['#'] = '#E4E4E4',
	['%'] = '#D2D2D2',
	['*'] = '#A6A6A6',
	['+'] = '#8C8C8C',
	['='] = '#6B6B6B',
	['-'] = '#5C5C5C',
	[':'] = '#4A4A4A',
	['.'] = '#4A4A4A'
}

local freshInstall = false
local function deleteInstall()
	shared.PistonwareLoaderBoot = nil
	if not freshInstall then return end
	pcall(function()
		if delfolder then
			delfolder('pistonware')
			return
		end
		local function purge(folder)
			for _, path in listfiles(folder) do
				if isfolder(path) then
					purge(path)
				elseif delfile then
					delfile(path)
				end
			end
		end
		purge('pistonware')
	end)
end

local function asciiRichText(line)
	local out = {}
	local runColor, runStart = nil, 1
	local function flush(stop)
		if stop < runStart then return end
		local chunk = line:sub(runStart, stop)
		table.insert(out, runColor and ('<font color="'..runColor..'">'..chunk..'</font>') or chunk)
	end
	for i = 1, #line do
		local color = AsciiShades[line:sub(i, i)]
		if i > 1 and color ~= runColor then
			flush(i - 1)
			runStart = i
		end
		runColor = color
	end
	flush(#line)
	return table.concat(out)
end

local function createConsole()
	local tweenService = cloneref(game:GetService('TweenService'))
	local inputService = cloneref(game:GetService('UserInputService'))
	local playersService = cloneref(game:GetService('Players'))

	pcall(function()
		if type(shared.PistonwareLoaderTeardown) == 'function' then
			shared.PistonwareLoaderTeardown()
		end
	end)

	local connections = {}
	local function track(connection)
		table.insert(connections, connection)
		return connection
	end

	local screen = Instance.new('ScreenGui')
	screen.Name = 'ClayV1Loader'
	screen.DisplayOrder = 999999999
	screen.IgnoreGuiInset = true
	screen.ResetOnSpawn = false
	local parented = pcall(function()
		screen.Parent = (gethui and gethui()) or cloneref(game:GetService('CoreGui'))
	end)
	if not parented then
		pcall(function()
			screen.Parent = playersService.LocalPlayer:FindFirstChildOfClass('PlayerGui')
		end)
	end

	local window = Instance.new('Frame')
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = UDim2.fromScale(0.5, 0.5)
	window.Size = UDim2.fromOffset(WindowWidth, WindowHeight)
	window.BackgroundColor3 = Palette.Window
	window.BorderSizePixel = 0
	window.ClipsDescendants = true
	window.Parent = screen
	local windowCorner = Instance.new('UICorner')
	windowCorner.CornerRadius = UDim.new(0, 10)
	windowCorner.Parent = window
	local windowStroke = Instance.new('UIStroke')
	windowStroke.Color = Palette.Border
	windowStroke.Thickness = 1
	windowStroke.Parent = window

	local uiscale = Instance.new('UIScale')
	uiscale.Parent = window
	local camera = workspace.CurrentCamera

	local minimized, maximized = false, false
	local restorePosition = window.Position

	local function applyWindowState(animate)
		local viewport = camera and camera.ViewportSize or Vector2.new(WindowWidth, WindowHeight)
		local width = maximized and (viewport.X / uiscale.Scale) or WindowWidth
		local height = maximized and (viewport.Y / uiscale.Scale) or WindowHeight
		local size = UDim2.fromOffset(width, minimized and TitleBarHeight or height)
		local position = maximized and UDim2.fromScale(0.5, 0.5) or restorePosition
		if animate then
			tweenService:Create(window, TweenInfo.new(0.16, Enum.EasingStyle.Quad), {Size = size, Position = position}):Play()
		else
			window.Size, window.Position = size, position
		end
	end

	local function applyScale()
		local viewport = camera and camera.ViewportSize or Vector2.new(WindowWidth, WindowHeight)
		if viewport.X <= 0 or viewport.Y <= 0 then return end
		local fit = math.min(viewport.X * 0.94 / WindowWidth, viewport.Y * 0.92 / WindowHeight)
		uiscale.Scale = math.clamp(math.min(fit, viewport.Y / 1080), 0.25, 1.4)
		applyWindowState(false)
	end
	applyScale()
	if camera then
		track(camera:GetPropertyChangedSignal('ViewportSize'):Connect(applyScale))
	end

	local titlebar = Instance.new('Frame')
	titlebar.Size = UDim2.new(1, 0, 0, TitleBarHeight)
	titlebar.BackgroundColor3 = Palette.TitleBar
	titlebar.BorderSizePixel = 0
	titlebar.Parent = window
	local titlebarCorner = Instance.new('UICorner')
	titlebarCorner.CornerRadius = UDim.new(0, 10)
	titlebarCorner.Parent = titlebar
	local titlebarFill = Instance.new('Frame')
	titlebarFill.Position = UDim2.new(0, 0, 1, -10)
	titlebarFill.Size = UDim2.new(1, 0, 0, 10)
	titlebarFill.BackgroundColor3 = Palette.TitleBar
	titlebarFill.BorderSizePixel = 0
	titlebarFill.Parent = titlebar

	local icon = Instance.new('TextLabel')
	icon.Position = UDim2.fromOffset(10, 10)
	icon.Size = UDim2.fromOffset(24, 24)
	icon.BackgroundColor3 = Color3.fromRGB(22, 22, 22)
	icon.BorderSizePixel = 0
	icon.Text = '>_'
	icon.TextColor3 = Palette.Accent
	icon.TextSize = 13
	icon.Font = Enum.Font.Code
	icon.Parent = titlebar
	local iconCorner = Instance.new('UICorner')
	iconCorner.CornerRadius = UDim.new(0, 5)
	iconCorner.Parent = icon

	local title = Instance.new('TextLabel')
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -220, 1, 0)
	title.Position = UDim2.fromOffset(110, 0)
	title.Text = './clayV1-loader'
	title.TextColor3 = Palette.Title
	title.TextSize = 18
	title.Font = Enum.Font.Code
	title.Parent = titlebar

	local closed, aborted = false, false
	local function destroy()
		if closed then return end
		closed = true
		for _, connection in connections do
			pcall(function() connection:Disconnect() end)
		end
		table.clear(connections)
		pcall(function() screen:Destroy() end)
		if shared.PistonwareLoaderTeardown == destroy then
			shared.PistonwareLoaderTeardown = nil
		end
	end

	local function cancel()
		if aborted then return end
		aborted = true
		destroy()
		deleteInstall()
	end

	local function drawGlyph(parent, kind)
		local bars = {}
		local function bar(length, x, y, rotation)
			local piece = Instance.new('Frame')
			piece.AnchorPoint = Vector2.new(0.5, 0.5)
			piece.Position = UDim2.fromOffset(x, y)
			piece.Size = UDim2.fromOffset(length, 2)
			piece.BackgroundColor3 = Palette.Glyph
			piece.BorderSizePixel = 0
			piece.Rotation = rotation
			piece.Parent = parent
			local corner = Instance.new('UICorner')
			corner.CornerRadius = UDim.new(0, 1)
			corner.Parent = piece
			table.insert(bars, piece)
		end
		if kind == 'minimize' then
			bar(10, 13.5, 17, 45)
			bar(10, 20.5, 17, -45)
		elseif kind == 'maximize' then
			bar(10, 13.5, 17, -45)
			bar(10, 20.5, 17, 45)
		else
			bar(15, 17, 17, 45)
			bar(15, 17, 17, -45)
		end
		return bars
	end

	for index, kind in {'minimize', 'maximize', 'close'} do
		local button = Instance.new('TextButton')
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.Position = UDim2.new(1, -14 - (3 - index) * 38, 0.5, 0)
		button.Size = UDim2.fromOffset(34, 34)
		button.BackgroundColor3 = Color3.new(1, 1, 1)
		button.BackgroundTransparency = 1
		button.AutoButtonColor = false
		button.Modal = true
		button.Text = ''
		button.Parent = titlebar
		local corner = Instance.new('UICorner')
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = button

		local bars = drawGlyph(button, kind)
		button.MouseEnter:Connect(function()
			button.BackgroundTransparency = 0.9
			for _, piece in bars do
				piece.BackgroundColor3 = kind == 'close' and Palette.Error or Color3.new(1, 1, 1)
			end
		end)
		button.MouseLeave:Connect(function()
			button.BackgroundTransparency = 1
			for _, piece in bars do
				piece.BackgroundColor3 = Palette.Glyph
			end
		end)

		button.MouseButton1Click:Connect(function()
			if kind == 'close' then
				cancel()
			elseif kind == 'minimize' then
				minimized = not minimized
				applyWindowState(true)
			else
				maximized = not maximized
				minimized = false
				applyWindowState(true)
			end
		end)
	end

	local dragging, dragStart, dragOrigin
	titlebar.InputBegan:Connect(function(input)
		if maximized then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging, dragStart, dragOrigin = true, input.Position, window.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
				end
			end)
		end
	end)
	track(inputService.InputChanged:Connect(function(input)
		if not dragging then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			local delta = input.Position - dragStart
			window.Position = UDim2.new(dragOrigin.X.Scale, dragOrigin.X.Offset + delta.X, dragOrigin.Y.Scale, dragOrigin.Y.Offset + delta.Y)
			restorePosition = window.Position
		end
	end))

	local ascii = Instance.new('Frame')
	ascii.BackgroundTransparency = 1
	ascii.Position = UDim2.fromOffset(ContentPadding, AsciiTop)
	ascii.Size = UDim2.fromOffset(WindowWidth - ContentPadding * 2, #PistonFace * AsciiLineHeight)
	ascii.Parent = window

	local rows = {}
	for index, line in PistonFace do
		local label = Instance.new('TextLabel')
		label.BackgroundTransparency = 1
		label.Position = UDim2.fromOffset(0, (index - 1) * AsciiLineHeight)
		label.Size = UDim2.new(1, 0, 0, AsciiLineHeight)
		label.RichText = true
		label.Text = asciiRichText(line)
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextSize = AsciiTextSize
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextTransparency = 1
		label.Font = Enum.Font.Code
		label.Visible = false
		label.Parent = ascii
		rows[index] = label
	end

	local status = Instance.new('TextLabel')
	status.BackgroundTransparency = 1
	status.Position = UDim2.fromOffset(ContentPadding, StatusY)
	status.Size = UDim2.new(1, -ContentPadding * 2, 0, 28)
	status.RichText = true
	status.TextColor3 = Palette.Line
	status.TextSize = 22
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.Font = Enum.Font.Code
	status.Parent = window

	local line = Instance.new('TextLabel')
	line.BackgroundTransparency = 1
	line.Position = UDim2.fromOffset(ContentPadding, LineY)
	line.Size = UDim2.new(1, -ContentPadding * 2, 0, 24)
	line.Text = ''
	line.TextColor3 = Palette.Line
	line.TextSize = 17
	line.TextXAlignment = Enum.TextXAlignment.Left
	line.Font = Enum.Font.Code
	line.Parent = window

	local answers = Instance.new('Frame')
	answers.BackgroundTransparency = 1
	answers.Position = UDim2.fromOffset(ContentPadding, AnswersY)
	answers.Size = UDim2.new(1, -ContentPadding * 2, 0, 34)
	answers.Visible = false
	answers.Parent = window
	local answersLayout = Instance.new('UIListLayout')
	answersLayout.SortOrder = Enum.SortOrder.LayoutOrder
	answersLayout.FillDirection = Enum.FillDirection.Horizontal
	answersLayout.Padding = UDim.new(0, 12)
	answersLayout.Parent = answers

	local tooltip = Instance.new('TextLabel')
	tooltip.Name = 'Tooltip'
	tooltip.LayoutOrder = 999
	tooltip.AutomaticSize = Enum.AutomaticSize.X
	tooltip.Size = UDim2.fromOffset(0, 34)
	tooltip.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
	tooltip.BorderSizePixel = 0
	tooltip.Visible = false
	tooltip.Text = ''
	tooltip.TextColor3 = Palette.Line
	tooltip.TextSize = 15
	tooltip.Font = Enum.Font.Code
	tooltip.Parent = answers
	local tooltipPadding = Instance.new('UIPadding')
	tooltipPadding.PaddingLeft = UDim.new(0, 12)
	tooltipPadding.PaddingRight = UDim.new(0, 12)
	tooltipPadding.Parent = tooltip
	local tooltipCorner = Instance.new('UICorner')
	tooltipCorner.CornerRadius = UDim.new(0, 4)
	tooltipCorner.Parent = tooltip
	local tooltipStroke = Instance.new('UIStroke')
	tooltipStroke.Color = Palette.ButtonBorder
	tooltipStroke.Thickness = 1
	tooltipStroke.Parent = tooltip

	local footer = Instance.new('TextLabel')
	footer.AnchorPoint = Vector2.new(0, 1)
	footer.BackgroundTransparency = 1
	footer.Position = UDim2.new(0, ContentPadding, 1, -16)
	footer.Size = UDim2.new(1, -ContentPadding * 2, 0, 22)
	footer.Text = (inputService.TouchEnabled and not inputService.KeyboardEnabled) and 'Tap [x] to exit' or 'Press [CTRL+C] to exit'
	footer.TextColor3 = Palette.Footer
	footer.TextSize = 17
	footer.TextXAlignment = Enum.TextXAlignment.Left
	footer.Font = Enum.Font.Code
	footer.Parent = window

	track(inputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if input.KeyCode == Enum.KeyCode.C and inputService:IsKeyDown(Enum.KeyCode.LeftControl) then
			cancel()
		end
	end))

	local revealed, revealTarget = 0, 0
	local halted = false
	task.spawn(function()
		while not closed and not halted do
			if revealed < revealTarget then
				revealed += 1
				local row = rows[revealed]
				row.Visible = true
				tweenService:Create(row, TweenInfo.new(0.18), {TextTransparency = 0}):Play()
			end
			task.wait(0.07)
		end
	end)

	local function answerButton(text, width, order)
		local button = Instance.new('TextButton')
		button.LayoutOrder = order
		button.Size = UDim2.fromOffset(width, 34)
		button.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
		button.BorderSizePixel = 0
		button.AutoButtonColor = false
		button.Modal = true
		button.Text = text
		button.TextColor3 = Palette.ButtonIdle
		button.TextSize = 17
		button.Font = Enum.Font.Code
		button.Parent = answers
		local corner = Instance.new('UICorner')
		corner.CornerRadius = UDim.new(0, 4)
		corner.Parent = button
		local stroke = Instance.new('UIStroke')
		stroke.Color = Palette.ButtonBorder
		stroke.Thickness = 1
		stroke.Parent = button
		button.MouseEnter:Connect(function()
			stroke.Color = Palette.Accent
			button.TextColor3 = Palette.Accent
		end)
		button.MouseLeave:Connect(function()
			stroke.Color = Palette.ButtonBorder
			button.TextColor3 = Palette.ButtonIdle
		end)
		return button
	end

	local function clearAnswers()
		for _, child in answers:GetChildren() do
			if child:IsA('TextButton') or child:IsA('TextBox') then
				child:Destroy()
			end
		end
	end

	local console = {}

	function console:SetStatus(text, color, chevron)
		status.Text = '<font color="#9E9E9E">'..(chevron == '<' and '&lt;' or '&gt;')..'</font> <font color="'..(color or '#F07A1F')..'">'..text..'</font>'
	end

	function console:SetLine(text, color)
		line.Text = text
		line.TextColor3 = color or Palette.Line
	end

	function console:SetProgress(alpha)
		local count = math.clamp(math.floor(alpha * #PistonFace + 0.5), 0, #PistonFace)
		revealTarget = math.max(revealTarget, count)
	end

	function console:IsAborted()
		return aborted
	end

	function console:Ask(question, buttons, timeoutSeconds, fallback)
		if closed then return fallback end
		self:SetLine(question)
		clearAnswers()

		tooltip.Visible = false

		local choice
		for index, def in buttons do
			local button = answerButton(def.text, 132, index)
			if def.tooltip then
				button.MouseEnter:Connect(function()
					tooltip.Text = def.tooltip
					tooltip.Visible = true
				end)
				button.MouseLeave:Connect(function()
					tooltip.Visible = false
				end)
			end
			button.MouseButton1Click:Connect(function()
				choice = def.key
			end)
		end
		answers.Visible = true

		local timeout = os.clock() + (timeoutSeconds or 60)
		repeat task.wait() until choice ~= nil or closed or os.clock() > timeout
		answers.Visible = false
		clearAnswers()
		tooltip.Visible = false
		self:SetLine('')
		if choice == nil then
			return fallback
		end
		return choice
	end

	-- AskKey is now completely bypassed – it returns your real key immediately
	function console:AskKey(opts)
		return MY_KEY
	end

	function console:Finish(message, seconds)
		if closed then return end
		self:SetProgress(1)
		local drawn = os.clock() + 2
		repeat task.wait() until revealed >= #PistonFace or closed or os.clock() > drawn
		task.wait(0.2)
		if closed then return end
		self:SetStatus('DONE')
		seconds = seconds or 5
		local deadline = os.clock() + seconds
		task.spawn(function()
			while not closed do
				local left = math.max(0, math.ceil(deadline - os.clock()))
				self:SetLine(message..' Loader will close in '..left..'s.')
				if left <= 0 then break end
				task.wait(0.2)
			end
			destroy()
		end)
	end

	function console:Halt()
		halted = true
	end

	function console:Fail(err)
		if closed then return end
		self:SetStatus('FAILED', '#E15046')
		line.TextWrapped = true
		line.TextYAlignment = Enum.TextYAlignment.Top
		line.Size = UDim2.new(1, -ContentPadding * 2, 0, AnswersY + 34 - LineY)
		self:SetLine(err, Palette.Error)
		self:Halt()
	end

	shared.PistonwareLoaderTeardown = destroy

	return console
end

local function createHeadlessConsole()
	local console = {}
	function console:SetStatus() end
	function console:SetLine() end
	function console:SetProgress() end
	function console:Finish() end
	function console:Fail() end
	function console:Halt() end
	function console:IsAborted() return false end
	function console:Ask(question, buttons, timeoutSeconds, fallback)
		return fallback
	end
	function console:AskKey()
		return MY_KEY
	end
	return console
end

local isReload = shared.vapereload and true or false
local console = isReload and createHeadlessConsole() or createConsole()

console:SetStatus('AUTHENTICATING', nil, '<')
console:SetLine('Using your key...')
console:SetProgress(0.08)

-- ========================================================================
-- HARDCODE YOUR REAL KEY globally
-- ========================================================================
script_key = MY_KEY
pcall(function() getgenv().script_key = MY_KEY end)
pcall(function() _G.script_key = MY_KEY end)
shared.PistonwareKey = MY_KEY
shared.PistonwareAuthenticated = true

-- Unsupported executor check
do
	local unsupported = {'xeno', 'solara'}
	local executorName = ''
	pcall(function()
		executorName = identifyexecutor and identifyexecutor() or ''
	end)
	local lowered = tostring(executorName):lower()
	for _, name in unsupported do
		if lowered:find(name, 1, true) then
			local message = 'Unsupported executor ('..tostring(executorName)..'), please look in the #supported-executors channel for more info.'
			console:SetStatus('ERROR', '#E15046')
			console:SetLine(message, Palette.Error)
			warn('[pistonware] '..message)
			console:Halt()
			shared.PistonwareLoaderBoot = nil
			return
		end
	end
end

-- Proceed to injection
console:SetStatus('INJECTING')
console:SetLine('Injecting clayV1...')
console:SetProgress(0.12)

freshInstall = not isfolder('pistonware')
for _, folder in {'pistonware', 'pistonware/games', 'pistonware/profiles', 'pistonware/assets', 'pistonware/libraries', 'pistonware/guis'} do
	if not isfolder(folder) then
		makefolder(folder)
	end
end

do
	local playersService = cloneref(game:GetService('Players'))
	local deadline = os.clock() + 120
	repeat task.wait() until game:IsLoaded() or console:IsAborted() or os.clock() > deadline
	console:SetProgress(0.24)
	repeat task.wait() until playersService.LocalPlayer or console:IsAborted() or os.clock() > deadline
	if shared.vape then
		task.wait(0.25)
	end
	console:SetProgress(0.4)
end
if console:IsAborted() then deleteInstall() return end

if not isReload and not isDeveloper then
	console:SetLine('Checking for updates...')
	pcall(updateCachedFiles, function(completed, total)
		console:SetLine('Updating files ('..completed..'/'..total..')...')
		console:SetProgress(0.4 + 0.06 * (completed / math.max(total, 1)))
	end)
	console:SetLine('')
	if console:IsAborted() then deleteInstall() return end
end
console:SetProgress(0.46)

local firstRunProfiles = false
pcall(function()
	firstRunProfiles = #listfiles('pistonware/profiles') < 3
end)

local declinedDownload = false
pcall(function()
	if isfile('pistonware/profiles/profilecheck.txt') then
		declinedDownload = readfile('pistonware/profiles/profilecheck.txt') == 'false'
	end
end)

local wantsDownload = true
if firstRunProfiles and not declinedDownload then
	console:SetProgress(0.47)
	local ok, res = pcall(function()
		return console:Ask('Would you like to download the latest config?', {
			{text = 'Yes', key = true, tooltip = 'Downloads the Blatant and Legit configs from GitHub'},
			{text = 'No', key = false, tooltip = 'Starts on default settings and stops asking on future runs'}
		}, 60, true)
	end)
	if console:IsAborted() then deleteInstall() return end
	wantsDownload = ok and res == true
	if not wantsDownload then
		pcall(function() writefile('pistonware/profiles/profilecheck.txt', 'false') end)
	end
end
console:SetProgress(0.53)

local downloadedConfigs = false
if firstRunProfiles and not declinedDownload and wantsDownload then
	console:SetLine('Downloading configs...')
	pcall(function()
		local body = fetchProfilesListing()
		if body then
			downloadProfilesListing(body, nil, function(completed, total)
				console:SetLine('Downloading configs ('..completed..'/'..total..')...')
				console:SetProgress(0.53 + 0.2 * (completed / math.max(total, 1)))
			end)
		end
	end)
	pcall(function()
		downloadedConfigs = #listfiles('pistonware/profiles') >= 3
	end)
	if downloadedConfigs then
		pcall(function()
			local commit = fetchProfilesCommit()
			if commit then
				writefile('pistonware/profiles/profilecommit.txt', commit)
			end
		end)
	end
end
if console:IsAborted() then deleteInstall() return end

if not firstRunProfiles and not declinedDownload and not isReload then
	local latestCommit, cachedCommit
	pcall(function()
		latestCommit = fetchProfilesCommit()
		cachedCommit = isfile('pistonware/profiles/profilecommit.txt') and readfile('pistonware/profiles/profilecommit.txt'):gsub('%s', '') or nil
	end)
	if latestCommit and latestCommit ~= cachedCommit then
		console:SetProgress(0.6)
		local ok, wantsSync = pcall(function()
			return console:Ask('Would you like to sync to the latest config?', {
				{text = 'Yes', key = true, tooltip = 'Replaces the shipped configs with the newer ones on GitHub'},
				{text = 'No', key = false, tooltip = 'Keeps the configs you have, asks again next session'}
			}, 60, false)
		end)
		if console:IsAborted() then deleteInstall() return end
		if ok and wantsSync == true then
			console:SetLine('Syncing configs...')
			local lastProfile
			pcall(function()
				local live = shared.vape and shared.vape.Profile
				if type(live) == 'string' and live ~= '' then
					lastProfile = live
					return
				end
				local guipath = 'pistonware/profiles/'..game.GameId..'.gui.txt'
				if not isfile(guipath) then return end
				local guidata = cloneref(game:GetService('HttpService')):JSONDecode(readfile(guipath))
				if type(guidata) == 'table' and type(guidata.Profile) == 'string' and guidata.Profile ~= '' then
					lastProfile = guidata.Profile
				end
			end)
			pcall(function()
				if shared.vape then
					pcall(function() shared.vape:Uninject() end)
					shared.vape = nil
				end
				local body = fetchProfilesListing(latestCommit)
				if body then
					downloadProfilesListing(body, latestCommit, function(completed, total)
						console:SetLine('Syncing configs ('..completed..'/'..total..')...')
						console:SetProgress(0.6 + 0.13 * (completed / math.max(total, 1)))
					end)
					writefile('pistonware/profiles/profilecommit.txt', latestCommit)
				end
			end)
			if console:IsAborted() then deleteInstall() return end
			if lastProfile then
				shared.VapeCustomProfile = lastProfile
			end
		end
	end
end
console:SetProgress(0.73)

if downloadedConfigs then
	local ok, choice = pcall(function()
		return console:Ask('Which config would you like to load by default?', {
			{text = 'Blatant', key = 'blatant', tooltip = 'Makes Blatant your default config: everything on, obvious'},
			{text = 'Legit', key = 'legit', tooltip = 'Makes Legit your default config: toned down to look normal'}
		}, 120, nil)
	end)
	if console:IsAborted() then deleteInstall() return end
	if ok and type(choice) == 'string' then
		shared.VapeCustomProfile = choice
	end
end

console:SetProgress(0.8)
console:SetLine('Loading clayV1...')

local injecting = true
task.spawn(function()
	local alpha = 0.8
	while injecting and alpha < 0.93 do
		task.wait(0.6)
		if not injecting then break end
		alpha += 0.02
		console:SetProgress(alpha)
	end
end)

local ok, result = pcall(function()
	return loadstring(downloadFile('pistonware/main.lua'), 'main')()
end)
injecting = false
shared.vapereload = nil
shared.PistonwareLoaderBoot = nil

if console:IsAborted() then
	if shared.vape then
		pcall(function() shared.vape:Uninject() end)
	end
	shared.VapeCustomProfile = nil
	deleteInstall()
	return
end

if ok then
	console:Finish('ClayV1 injected successfully.', 5)
	return result
end
warn('[pistonware] '..tostring(result))
local failure = 'Injection failed: '..tostring(result)
local copied = pcall(function() setclipboard(failure) end)
console:Fail(failure..(copied and '\n\n(copied to clipboard)' or ''))
