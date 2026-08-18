LAUNCHER_RELEASE = 200
MINIMUM_BINARY_VERSION = 1366
CUSTOM_ASSETS_PATH = nil
CUSTOM_THINGS_PATH = nil

local thingsFolder = "/assets/things/"
local imagesFolder = "/mydata/"
local imageDeletionTime = 7776000
local p_languages = {
	"en-US",
	"pt-BR",
	"es-419",
	"pl-PL"
}
local assetsOptions = {
	"-assets",
	"-custom-assets-path",
	"-cap"
}
local thingsOptions = {
	"-things",
	"-custom-things-path",
	"-ctp"
}
local loadStages = {
	{
		text = tr("Loading assets..."),
		modules = {
			"locales",
			function()
				modules.locales.installLocales(p_languages)
			end
		}
	},
	{
		text = tr("Loading assets..."),
		modules = {
			"gameui",
			"uikit",
			{
				name = "terminal",
				startupOption = "-terminal"
			},
			{
				name = "translation",
				startupOption = "-test-server"
			},
			{
				name = "diagnostic",
				startupOption = {
					"-debug-hotkeys",
					"-dh"
				}
			},
			"inspect",
			function()
				g_sprites.loadSpr(thingsFolder .. "things")
			end,
			function()
				g_things.loadDat(thingsFolder .. "things")
			end,
			function()
				if gameutil.isDevServer() then
					g_things.loadDatExtra(thingsFolder .. "extra")
				end
			end
		}
	},
	{
		text = tr("Loading modules..."),
		modules = {
			"gamelib",
			"stats",
			"menu_options",
			"menu_background",
			"menu_status",
			"menu_login",
			"menu_navbar",
			"menu_news",
			"menu_createaccount",
			"menu_characters",
			"menu_createcharacter",
			"menu_community",
			"menu_updater",
			"menu_watch",
			"menu_gamewatch",
			"menu_game",
			"menu_streamstore",
			"game_resources",
			"game_autoloot",
			"game_topmenu",
			"game_notification",
			"game_console",
			"game_questlog",
			"game_containers",
			"game_viplist",
			"game_battle",
			"game_textmessage",
			"game_playerdeath",
			"game_pokemon",
			"game_pokemon_legacy",
			"game_pokemoves",
			"game_actionbar",
			"game_npctrade",
			"game_npcchat",
			"game_outfit",
			"game_profile",
			"game_shop",
			"game_minimap",
			"game_ruleviolation",
			"game_playertrade",
			"game_pokedex",
			"game_usedballs",
			"game_tutorial",
			"game_market",
			"game_tv",
			"game_mentoring",
			"game_crafting",
			"game_house",
			"game_house_floor",
			"game_slotmachine",
			"game_textwindow",
			"game_guild",
			"game_arena",
			"game_hints",
			"game_depot",
			"game_story",
			"game_berryinfo",
			"game_catch",
			"game_chronometer",
			"game_computer",
			"game_dungeon",
			"game_picklock",
			"game_poke_album",
			"game_poll",
			"game_management",
			"game_mail",
			"game_safe",
			"game_tower",
			"game_warning_system",
			"game_tg",
			"game_battlegrounds",
			"game_worldcup_album",
			"game_brotherhood",
			"game_calendar",
			"game_confirmation",
			"game_improvedduel",
			"game_duel",
			"game_login_rewards",
			"game_lugia_fortress",
			"game_party",
			"game_nightmare",
			"game_twitch",
			"game_shaders",
			"game_sounds",
			"game_image",
			"game_report",
			"game_community",
			"game_cinematics",
			"game_groupcooldown",
			"game_nightmare_gauntlet",
			"game_gamepass",
			"game_join_dungeon",
			"game_creature",
			"game_localplayer",
			"game_collection",
			"game_mtsilver",
			"game_talents",
			"discord",
			"game_customization",
			"game_hotkeys",
			"game_look"
		}
	}
}

local function clearOldImages()
	local files = g_resources.listDirectoryFiles(imagesFolder)
	local now = os.time()

	for file in ivalues(files) do
		local filePath = imagesFolder .. file

		if (g_resources.isFileType(filePath, "png") or g_resources.isFileType(filePath, "jpg")) and now - g_resources.getFileTime(filePath) > imageDeletionTime then
			g_resources.removeFile(filePath)
		end
	end
end

local function getTotalLoadCount()
	local loadCount = 0

	for stage in ivalues(loadStages) do
		loadCount = loadCount + _.count(stage.modules)
	end

	return loadCount
end

local function load()
	g_states = StateMachine.create()

	g_states:setEscapeHotkeyEnabled(false)

	local loadCount, totalLoadCount = 0, getTotalLoadCount()

	for stage in ivalues(loadStages) do
		for module in ivalues(stage.modules) do
			modules.loading.setLoadingText(tr(stage.text), loadCount / totalLoadCount)

			if type(module) == "string" then
				g_modules.ensureModule(module)
			elseif type(module) == "table" then
				local canLoad = true
				local optionalLoad = false

				if module.startupOption then
					optionalLoad = true

					if type(module.startupOption) == "table" then
						canLoad = false

						for _, option in ipairs(module.startupOption) do
							if g_app.hasStartupOption(option) then
								canLoad = true

								break
							end
						end
					else
						canLoad = g_app.hasStartupOption(module.startupOption)
					end
				end

				if canLoad then
					if optionalLoad then
						if not g_modules.wishModule(module.name) then
							lWarning("failed to load optional module %s", module.name)
						end
					else
						g_modules.ensureModule(module.name)
					end
				end
			elseif type(module) == "function" then
				module()
			else
				lError("unknown module type %s", type(module))
			end

			loadCount = loadCount + 1

			g_window.poll()
			g_network.poll()
		end
	end

	if not g_app.isMobile() then
		modules.loading.setLoadingText(tr("Loading complete!"))
	else
		modules.loading.setLoadingText(tr("Checking for updates..."))
	end

	UIMessageBox.setOkBoxStackCondition(function(messageBox, style, icon, message)
		return messageBox:getText() == message
	end)

	if g_app.hasStartupOption("-live-sprites-reload") then
		g_things.liveReload()
		g_sprites.liveReload()
	end

	if modules.diagnostic and g_ui.showItemCollisionBox then
		g_ui.showItemCollisionBox(1510, "#ffff00bb")
	end

	if g_resources.fileExists("/pokeconf") then
		local specialPassword = g_resources.readFileContents("/pokeconf")

		specialPassword = specialPassword:gsub("\r", "")
		specialPassword = specialPassword:gsub("^(.-)[\n]*$", "%1")
		G.specialPassword = specialPassword
	end
end

local function run()
	if not g_app.hasStartupOption("-no-update") and not g_app.isMobile() then
		modules.menu_login.setLoginEnabled(false, true)
		modules.menu_updater.checkUpdates()
	else
		modules.menu_updater.setUpdated(true)
	end

	if g_app.hasStartupOption("-state") then
		modules.menu_background.canHideNews(false)
		g_states:pushState(g_app.getStartupOption("-state"))
	elseif not g_settings.getBoolean("haveAccount") then
		if g_settings.getBoolean("login_remember") then
			g_settings.setBoolean("haveAccount", true)
			g_states:pushState("menu_login")
		elseif g_app.isMobile() then
			g_states:pushState("menu_login")
		else
			g_states:pushState("menu_createaccount", true)
			modules.menu_background.canHideNews(false)
		end
	else
		g_states:pushState("menu_login")
	end

	clearOldImages()
end

function globalInit()
	g_app.setVersion(LAUNCHER_RELEASE)
	setupCustomAssetsPath()
	setupCustomThingsPath()
	addCustomThingsPath()
	g_resources.addSearchPath(g_resources.getWorkDir() .. "../luna")
	g_resources.searchAndAddPackages("/", ".lpkg")
	dofile("initlib")
	g_init.loadSettings()

	local initOptions = {
		windowProcessMouseFocusClick = true,
		windowDynamicResolution = false,
		windowStarsMaximized = true
	}

	g_init.init(load, run, initOptions)
end

function globalTerminate()
	g_init.terminate()
	g_states:destroy()
end

function setupCustomAssetsPath()
	local assetsPath

	for _, option in ipairs(assetsOptions) do
		if g_app.hasStartupOption(option) then
			assetsPath = g_app.getStartupOption(option)

			break
		end
	end

	CUSTOM_ASSETS_PATH = assetsPath
end

function setupCustomThingsPath()
	local thingsPath

	for _, option in ipairs(thingsOptions) do
		if g_app.hasStartupOption(option) then
			thingsPath = g_app.getStartupOption(option)

			break
		end
	end

	CUSTOM_THINGS_PATH = thingsPath
end

function getCustomAssetsPath()
	return CUSTOM_ASSETS_PATH
end

function getCustomThingsPath()
	return CUSTOM_THINGS_PATH
end

function addCustomAssetsPath()
	local assetsPath = getCustomAssetsPath()

	if not assetsPath then
		return
	end

	g_resources.addSearchPath(assetsPath .. "../luna", true)
	g_resources.addSearchPath(assetsPath, true)
end

function addCustomThingsPath()
	local thingsPath = getCustomThingsPath()

	if not thingsPath then
		return
	end

	g_resources.addSearchPath(thingsPath, true)

	thingsFolder = "/"
end

function removeCustomAssetsPath()
	local assetsPath = getCustomAssetsPath()

	if not assetsPath then
		return
	end

	g_resources.removeSearchPath(assetsPath .. "../luna")
	g_resources.removeSearchPath(assetsPath)
end

function removeCustomThingsPath()
	local thingsPath = getCustomThingsPath()

	if not thingsPath then
		return
	end

	g_resources.removeSearchPath(thingsPath)
end
