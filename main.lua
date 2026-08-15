-- The loader is the only supported entry point: it runs the LuaArmor key gate and publishes
-- script_key (which the protected bedwars.lua reads) before any of this downloads or executes.
-- main.lua is re-run directly in two places -- the queued teleport script below, and the GUI's
-- reinject buttons -- and both re-establish that state first, so reaching here without it means
-- the gate was skipped. Checked before the uninject below, so a failed check cannot tear down a
-- working instance on its way out.
if not shared.PistonwareAuthenticated then
	warn('[pistonware] not authenticated -- run the pistonware loader and enter your key')
	return
end

-- pcall'd: after a teleport shared.vape can still point at the previous server's instance,
-- whose GUI and connections no longer exist. An error walking that corpse would abort main.lua
-- on line one and leave the queued re-injection doing nothing at all.
if shared.vape then pcall(function() shared.vape:Uninject() end) end

local vape
local loadstring = function(...)
	local res, err = loadstring(...)
	if err and vape then
		vape:CreateNotification('ClayV1', 'Failed to load : '..err, 30, 'alert')
	end
	return res
end
local queue_on_teleport = queue_on_teleport or syn and syn.queue_on_teleport
local hasQueueOnTeleport = queue_on_teleport ~= nil
queue_on_teleport = queue_on_teleport or function() end
local isfile = isfile or function(file)
	local suc, res = pcall(function()
		return readfile(file)
	end)
	return suc and res ~= nil and res ~= ''
end
local cloneref = cloneref or function(obj)
	return obj
end
local playersService = cloneref(game:GetService('Players'))

-- isfile is not the question. A zero-byte file reads back as PRESENT through every executor's
-- real isfile, and only the fallback above treats empty as absent -- so on executors that ship
-- one (most of them), an interrupted write leaves a truncated file that nothing ever repairs.
--
-- That is not hypothetical: cancelling, crashing or teleporting during the concurrent asset
-- prefetch below leaves a half-written PNG. From then on prefetchFolder skips it, downloadFile
-- skips it, getcustomasset hands the corrupt file to the client, and the resulting invalid
-- content id throws 'ContentId formatting failed' at the assignment -- taking the whole GUI
-- chunk with it. Every route that could have fixed it asked isfile and was told the file was
-- fine, which is why the only known remedy was reinstalling the entire script.
--
-- Treating empty as missing makes it repair itself on the next run instead.
local function hasContent(path)
	if not isfile(path) then return false end
	local ok, body = pcall(readfile, path)
	return ok and type(body) == 'string' and body ~= ''
end

local function downloadFile(path, func)
	if not hasContent(path) then
		-- bedwars.lua only exists in the GitLab repo (kept separate/obfuscated there), at that
		-- repo's ROOT even though it caches locally under games/; everything else lives in the
		-- GitHub repo.
		local relPath = select(1, path:gsub('pistonware/', ''))
		local isBedwars = relPath == 'games/bedwars.lua'
		-- Retried a few times: raw file hosts intermittently fail, returning an empty body that
		-- would otherwise get cached as a corrupt/empty file.
		local content
		for attempt = 1, 4 do
			local suc, res = pcall(function()
				if isBedwars then
					return game:HttpGet('https://gitlab.com/pistonware/pistonware/-/raw/main/bedwars.lua', true)
				end
				return game:HttpGet('https://raw.githubusercontent.com/thecousinsmobile-art/mineasfasgwryhdsfas/main/'..relPath, true)
			end)
			-- For .lua files, a compile check too: an outage can hand back the 503/error page
			-- as the body, and caching that would poison the install silently (cache-first
			-- means it would never be refetched).
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
			content = '--This watermark is used to delete the file if its cached, remove it to make the file persist after vape updates.\n'..content
		end
		writefile(path, content)
	end
	return (func or readfile)(path)
end

-- Standalone progress label for the prefetch phase, since it runs before the GUI framework
-- (and its own downloader label) exists yet.
local downloaderGui, downloaderLabel
local function updateDownloader(text)
	if not downloaderGui then
		downloaderGui = Instance.new('ScreenGui')
		downloaderGui.Name = 'ClayV1Downloader'
		downloaderGui.ResetOnSpawn = false
		downloaderGui.Parent = cloneref(game:GetService('CoreGui'))
		downloaderLabel = Instance.new('TextLabel')
		downloaderLabel.Size = UDim2.new(1, 0, 0, 40)
		downloaderLabel.BackgroundTransparency = 1
		downloaderLabel.TextStrokeTransparency = 0
		downloaderLabel.TextSize = 20
		downloaderLabel.TextColor3 = Color3.new(1, 1, 1)
		downloaderLabel.Parent = downloaderGui
	end
	downloaderLabel.Text = text
end
local function destroyDownloader()
	if downloaderGui then
		downloaderGui:Destroy()
		downloaderGui, downloaderLabel = nil, nil
	end
end

-- Downloads every file in a repo folder concurrently instead of one HttpGet per getcustomasset call,
-- so GUI construction reads already-cached files instead of blocking on ~190 sequential round trips.
local function prefetchFolder(folder)
	local reqSuc, res = pcall(function()
		return game:HttpGet('https://api.github.com/repos/thecousinsmobile-art/mineasfasgwryhdsfas/contents/'..folder, true)
	end)
	if not (reqSuc and res and res ~= '404: Not Found') then return end
	local bodySuc, body = pcall(function()
		return cloneref(game:GetService('HttpService')):JSONDecode(res)
	end)
	if not (bodySuc and body and typeof(body) == 'table') then return end

	local toFetch = {}
	for _, v in body do
		-- hasContent, not isfile: a truncated asset from an interrupted prefetch must be picked
		-- up again here rather than skipped forever. See the note on hasContent.
		if v.type == 'file' and not hasContent('pistonware/'..folder..'/'..v.name) then
			table.insert(toFetch, v.name)
		end
	end
	if #toFetch <= 0 then return end

	local completed, total = 0, #toFetch
	local done = Instance.new('BindableEvent')
	updateDownloader('Downloading '..folder..' ('..completed..'/'..total..')')

	-- A fixed pool rather than one task per file. assets/new alone holds 63 files, and a user
	-- on any other theme prefetches their theme AND assets/new -- so spawning per file put
	-- 60+ HttpGets in flight at once, each holding its response body, each able to retry four
	-- times. That is a large memory and socket spike at boot on a device that has not even
	-- built the GUI yet. Same files, same order, same completion signal; just a ceiling on how
	-- many are outstanding at once.
	local PREFETCH_WORKERS = 6
	local nextIndex = 1
	local workers = math.min(PREFETCH_WORKERS, total)
	local active = workers

	for _ = 1, workers do
		task.spawn(function()
			while true do
				-- Claiming an index takes no yield between the read and the increment, so
				-- two workers can never be handed the same file.
				local index = nextIndex
				nextIndex += 1
				if index > total then break end

				pcall(downloadFile, 'pistonware/'..folder..'/'..toFetch[index])
				completed += 1
				-- pcall'd and after the counter: if this ever threw, the worker would die
				-- before releasing the wait below and the boot would hang on a GUI error
				pcall(updateDownloader, 'Downloading '..folder..' ('..completed..'/'..total..')')
			end
			active -= 1
			if active <= 0 then
				done:Fire()
			end
		end)
	end
	-- Only wait when a worker is still outstanding. task.spawn runs each task inline until it
	-- yields, so on executors where HttpGet does NOT yield the scheduler every worker drains
	-- the whole queue inside the loop above -- done:Fire() then lands with nothing listening
	-- yet, and an unconditional Wait() blocks forever with the label frozen at total/total.
	-- Same guard the loader's downloaders already use.
	if active > 0 then
		done.Event:Wait()
	end
	done:Destroy()
end

-- False while a game script is still registering its modules on its own thread. A fast game
-- script sets this back to true before runGameScript even returns, so the common path never
-- observes it as false. finishLoading needs it because two of the things it starts are unsafe
-- until every module exists: the autosave loop, and the profile it applies.
local gameScriptFinished = true

-- Set once the profile has been applied against the full module set. Every Save() is gated on
-- this rather than on gameScriptFinished: a protected payload never sets that flag, so gating
-- saves on it would mean BedWars never autosaved or persisted a config change at all.
local profileApplied = false

local function finishLoading()
	vape.Init = nil
	local customProfile = shared.VapeCustomProfile
	shared.VapeCustomProfile = nil
	if customProfile == '' then customProfile = nil end

	local function applyProfile()
		if shared.PistonwareSessionRejected then
			warn('[pistonware] session was not authorised -- leaving profiles untouched')
			return
		end
		vape:Load(nil, customProfile)
		profileApplied = true
		if customProfile then
			pcall(function() vape:Save() end)
		end
		task.spawn(function()
			while vape.Loaded and not shared.PistonwareSessionRejected do
				vape:Save()
				for _ = 1, 10 do
					task.wait(1)
					if not vape.Loaded or shared.PistonwareSessionRejected then break end
				end
			end
		end)
	end

	local function waitForModules()
		if gameScriptFinished then return end
		local started = os.clock()
		repeat
			task.wait(0.1)
		until gameScriptFinished
			or shared.PistonwareBedwarsLoaded
			or os.clock() - started > 120
		local count = 0
		for _ in vape.Modules do count += 1 end
		local how = shared.PistonwareBedwarsLoaded and 'payload signalled'
			or gameScriptFinished and 'game script returned'
			or 'TIMED OUT after 120s -- re-upload bedwars.lua to LuaArmor so it can signal when it is done'
		warn(('[pistonware] %d modules in %.1fs (%s) -- applying profile'):format(count, os.clock() - started, how))
	end

	if gameScriptFinished then
		applyProfile()
	else
		task.spawn(function()
			waitForModules()
			applyProfile()
		end)
	end

	local teleportedServers
	vape:Clean(playersService.LocalPlayer.OnTeleport:Connect(function()
		if (not teleportedServers) and (not shared.VapeIndependent) then
			teleportedServers = true
			-- ============================================================
			-- MODIFIED TELEPORT SCRIPT – now loads celebrations after re-inject
			-- ============================================================
			local teleportScript = [[
				shared.vapereload = true
				local cached = isfile and isfile('pistonware/main.lua') and readfile('pistonware/main.lua')
				local mainCode = cached and cached ~= '' and cached or game:HttpGet('https://raw.githubusercontent.com/thecousinsmobile-art/mineasfasgwryhdsfas/main/main.lua', true)
				loadstring(mainCode, 'main')()
				-- Wait for cheat to settle then load celebrations
				task.wait(1)
				pcall(function()
					local emoteScript = loadstring(game:HttpGet('https://raw.githubusercontent.com/thecousinsmobile-art/mineasfasgwryhdsfas/main/libraries/celebrations.lua', true), 'celebrations')
					if emoteScript then emoteScript() end
				end)
			]]
			if shared.PistonwareKey then
				local quoted = string.format('%q', shared.PistonwareKey)
				teleportScript = 'script_key = '..quoted..'\nshared.PistonwareKey = '..quoted..'\nshared.PistonwareAuthenticated = true\n'..teleportScript
			end
			if shared.PistonwareDeveloper then
				teleportScript = 'shared.PistonwareDeveloper = true\n'..teleportScript
			end
			if shared.VapeSmoothBoot then
				teleportScript = 'shared.VapeSmoothBoot = true\n'..teleportScript
			end
			teleportScript = 'shared.VapeCustomProfile = '..string.format('%q', vape.Profile or customProfile or 'default')..'\n'..teleportScript
			if profileApplied then
				vape:Save()
			end
			if not hasQueueOnTeleport then
				vape:CreateNotification('ClayV1', 'queue_on_teleport is not supported by your executor -- Vape will not re-inject automatically after this teleport (e.g. queueing into a match). You will need to re-run your loadstring manually.', 15, 'alert')
			end
			queue_on_teleport(teleportScript)
		end
	end))

	if shared.PistonwareSyncResult then
		vape:CreateNotification('ClayV1', shared.PistonwareSyncResult, 15, shared.PistonwareSyncResult:find('failed') and 'alert' or nil)
		shared.PistonwareSyncResult = nil
	end

	if not shared.vapereload then
		if not vape.Categories then return end
		if vape.Categories.Main.Options['GUI bind indicator'].Enabled then
			vape:CreateNotification('ClayV1 | Finished Loading', vape.VapeButton and 'Press the button in the top right to open GUI' or 'Press '..table.concat(vape.Keybind, ' + '):upper()..' to open GUI', 5)
		end
	end
end

if not isfile('pistonware/profiles/gui.txt') then
	writefile('pistonware/profiles/gui.txt', 'new')
end
local gui = readfile('pistonware/profiles/gui.txt')

if not isfolder('pistonware/assets/'..gui) then
	makefolder('pistonware/assets/'..gui)
end
pcall(prefetchFolder, 'assets/'..gui)
if gui ~= 'new' then
	pcall(prefetchFolder, 'assets/new')
end
destroyDownloader()
vape = loadstring(downloadFile('pistonware/guis/'..gui..'.lua'), 'gui')()
shared.vape = vape

if not shared.VapeIndependent then
	if not game:IsLoaded() then
		local loadDeadline = os.clock() + 120
		repeat task.wait() until game:IsLoaded() or os.clock() > loadDeadline
		local executorName = ''
		pcall(function() executorName = identifyexecutor and identifyexecutor() or '' end)
		task.wait(executorName == 'Opiumware' and 30 or 5)
	end
	pcall(function()
		loadstring(downloadFile('pistonware/games/universal.lua'), 'universal')()
	end)

	local gameArgs = table.pack(...)
	local function runGameScript(source, chunkname)
		local fn = loadstring(source, chunkname)
		if not fn then return end
		gameScriptFinished = false
		shared.PistonwareBedwarsLoaded = nil
		shared.PistonwareSessionRejected = nil

		if type(shared.PistonwareKey) == 'string' and shared.PistonwareKey ~= '' then
			local key = shared.PistonwareKey
			script_key = key
			pcall(function() getgenv().script_key = key end)
			pcall(function() _G.script_key = key end)
		end

		local started = os.clock()
		task.spawn(function()
			local ok, err = pcall(fn, table.unpack(gameArgs, 1, gameArgs.n))
			gameScriptFinished = true
			local elapsed = os.clock() - started
			if elapsed > 5 then
				warn(('[pistonware] %s finished in %.1fs -- its modules now have their saved settings'):format(chunkname, elapsed))
			end
			if not ok then
				warn('[pistonware] '..chunkname..' errored: '..tostring(err))
			end
		end)
	end

	local gamePath = 'pistonware/games/'..game.PlaceId..'.lua'
	local cached = isfile(gamePath) and readfile(gamePath) or nil
	if cached and cached:gsub('%s', '') ~= '' then
		runGameScript(cached, tostring(game.PlaceId))
	elseif not shared.PistonwareDeveloper then
		local suc, res = pcall(function()
			return game:HttpGet('https://raw.githubusercontent.com/thecousinsmobile-art/mineasfasgwryhdsfas/main/games/'..game.PlaceId..'.lua', true)
		end)
		if suc and res and res ~= '' and res ~= '404: Not Found' then
			pcall(writefile, gamePath, '--This watermark is used to delete the file if its cached, remove it to make the file persist after vape updates.\n'..res)
			runGameScript(res, tostring(game.PlaceId))
		end
	end
	finishLoading()
else
	vape.Init = finishLoading
	return vape
end
