local constants = require("constants")
local settings = require("config.settings")

local frontApps = {}

sbar.add("bracket", constants.items.FRONT_APPS, {}, { position = "left" })

local frontAppWatcher = sbar.add("item", {
  drawing = false,
  updates = true,
})

local function selectFocusedWindow(frontAppName)
  for appName, app in pairs(frontApps) do
    local isSelected = appName == frontAppName
    local color = isSelected and settings.colors.orange or settings.colors.white
    app:set(
      {
        label = { color = color },
        icon = { color = color },
      }
    )
  end
end

local function updateWindows(windows)
  sbar.remove("/" .. constants.items.FRONT_APPS .. "\\.*/")

  frontApps = {}

  -- Count windows per app
  local appCounts = {}
  local appFirstWindowId = {}
  local foundWindows = string.gmatch(windows, "[^\n]+")

  for window in foundWindows do
    local parsedWindow = {}
    for key, value in string.gmatch(window, "(%w+)=([%w%s]+)") do
      parsedWindow[key] = value
    end

    local windowId = parsedWindow["id"]
    local windowName = parsedWindow["name"]

    if windowName then
      appCounts[windowName] = (appCounts[windowName] or 0) + 1
      if not appFirstWindowId[windowName] then
        appFirstWindowId[windowName] = windowId
      end
    end
  end

  -- Create items for each app with window count
  for appName, count in pairs(appCounts) do
    local icon = settings.icons.apps[appName] or settings.icons.apps["default"]
    local displayLabel = count > 1 and appName .. " (" .. count .. ")" or appName

    frontApps[appName] = sbar.add("item", constants.items.FRONT_APPS .. "." .. appName, {
      label = {
        padding_left = 0,
        string = displayLabel,
      },
      icon = {
        string = icon,
        font = settings.fonts.icons(),
      },
      click_script = "aerospace focus --window-id " .. appFirstWindowId[appName],
    })

    frontApps[appName]:subscribe(constants.events.FRONT_APP_SWITCHED, function(env)
      selectFocusedWindow(env.INFO)
    end)
  end

  sbar.exec(constants.aerospace.GET_CURRENT_WINDOW, function(frontAppName)
    selectFocusedWindow(frontAppName:gsub("[\n\r]", ""))
  end)
end

local function getWindows()
  sbar.exec(constants.aerospace.LIST_WINDOWS, updateWindows)
end

frontAppWatcher:subscribe(constants.events.UPDATE_WINDOWS, function()
  getWindows()
end)

getWindows()
