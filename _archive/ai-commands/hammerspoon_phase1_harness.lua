-- HIR-67 test-only harness for the Lua-native Hammerspoon Gemini path.
local scenario, commandPath = arg[1] or "", arg[2] or ""
local observed = {
  bindings = {}, tasks = {}, timers = {}, alerts = {}, results = 0,
  clipboard = "ORIGINAL", clipboardCount = 40, pasteCount = 0,
  httpCallback = nil, httpCalls = 0, unexpected = {},
}

local function fail(message) observed.unexpected[#observed.unexpected + 1] = message end
local function eq(actual, expected, message)
  if actual ~= expected then fail(message .. " expected=" .. tostring(expected) .. " actual=" .. tostring(actual)) end
end

local function configureHs()
  local hs = {
    hotkey = {}, task = {}, timer = {}, alert = {}, dialog = {}, eventtap = {},
    uielement = {}, application = {}, pasteboard = {}, http = {}, json = {},
    screen = {}, webview = {}, drawing = {},
  }
  function hs.hotkey.bind(modifiers, key, callback)
    observed.bindings[key] = observed.bindings[key] or {}
    table.insert(observed.bindings[key], { modifiers = modifiers, callback = callback })
    return {}
  end
  function hs.alert.show(message) table.insert(observed.alerts, tostring(message)) end
  function hs.dialog.textPrompt() return "キャンセル", "" end
  function hs.task.new(path, callback, arguments)
    local task = { path = path, callback = callback, arguments = arguments or {}, started = false }
    function task:start() self.started = true; return true end
    function task:terminate() self.terminated = true; return self end
    function task:finish(exitCode, stdout, stderr)
      if self.callback then self.callback(exitCode, stdout or "", stderr or "") end
    end
    table.insert(observed.tasks, task)
    return task
  end
  function hs.timer.doAfter(_, callback)
    local timer = { callback = callback, stopped = false }
    function timer:stop() self.stopped = true; return self end
    table.insert(observed.timers, timer)
    return timer
  end
  function hs.json.encode() return "encoded-request" end
  function hs.json.decode() return { candidates = {{ content = { parts = {{ text = "RESPONSE" }} } }} } end
  function hs.http.asyncPost(_, _, _, callback)
    observed.httpCalls = observed.httpCalls + 1
    observed.httpCallback = callback
  end
  function hs.screen.mainScreen()
    return { frame = function() return { x = 0, y = 0, w = 1200, h = 800 } end }
  end
  hs.drawing.windowLevels = { floating = 1 }
  function hs.webview.new()
    local view = {}
    for _, name in ipairs({ "windowStyle", "windowTitle", "level", "allowGestures", "allowTextEntry", "closeOnEscape", "shadow", "html", "windowCallback" }) do
      view[name] = function(self) return self end
    end
    view.show = function(self) observed.results = observed.results + 1; return self end
    view.delete = function(self) return self end
    return view
  end
  function hs.application.frontmostApplication()
    return { activate = function() return true end, isFrontmost = function() return true end }
  end
  function hs.uielement.focusedElement()
    return { selectedText = function() return "selection" end }
  end
  function hs.pasteboard.getContents() return observed.clipboard end
  function hs.pasteboard.changeCount() return observed.clipboardCount end
  function hs.pasteboard.setContents(value)
    observed.clipboard = value; observed.clipboardCount = observed.clipboardCount + 1; return true
  end
  function hs.pasteboard.clearContents()
    observed.clipboard = nil; observed.clipboardCount = observed.clipboardCount + 1; return true
  end
  function hs.eventtap.keyStroke(_, key)
    if key == "v" then observed.pasteCount = observed.pasteCount + 1 end
    return true
  end
  _G.hs = hs
end

local function runTimer()
  while #observed.timers > 0 do
    local timer = table.remove(observed.timers, 1)
    if not timer.stopped then timer.callback(); return true end
  end
  return false
end

local function activeBinding(key)
  local list = observed.bindings[key] or {}
  if #list ~= 1 then fail(key .. " binding count expected=1 actual=" .. #list); return nil end
  local binding = list[1]
  eq(#binding.modifiers, 3, key .. " modifier count")
  return binding
end

local function finishGemini()
  local start = #observed.tasks
  eq(observed.tasks[start].path, "/usr/bin/id", "account task path")
  observed.tasks[start]:finish(0, "test-user\n", "")
  eq(#observed.tasks, start + 1, "Keychain task chain")
  eq(observed.tasks[start + 1].path, "/usr/bin/security", "security task path")
  eq(observed.tasks[start + 1].arguments[1], "find-generic-password", "security operation")
  eq(observed.tasks[start + 1].arguments[5], "test-user", "security account")
  observed.tasks[start + 1]:finish(0, "api-key\n", "")
  eq(observed.httpCalls, 1 + (start > 1 and 1 or 0), "HTTP call count")
  observed.httpCallback(200, "response", {})
end

local function registrationCheck()
  for _, key in ipairs({ "B", "R", "T" }) do activeBinding(key) end
end

local function nativePathCheck()
  local b = activeBinding("B")
  b.callback()
  finishGemini()
  eq(observed.results, 1, "B result")
  eq(observed.pasteCount, 0, "B paste count")
  eq(observed.clipboard, "ORIGINAL", "B clipboard")

  local r = activeBinding("R")
  r.callback()
  finishGemini()
  eq(observed.clipboard, "RESPONSE", "R response clipboard")
  eq(observed.pasteCount, 1, "R paste count")
  runTimer()
  eq(observed.clipboard, "ORIGINAL", "R restore")
end

configureHs()
io.open = function()
  local handle = {}
  function handle:read() return "Prompt: {selection}" end
  function handle:close() end
  return handle
end
package.path = (commandPath:match("^(.*)/[^/]+$") or ".") .. "/?.lua;" .. package.path
local module = dofile(commandPath)
module.start()

if scenario == "registration_and_legacy_cleanup" then
  registrationCheck()
elseif scenario == "runner_contract" then
  registrationCheck()
  nativePathCheck()
else
  fail("unknown scenario: " .. scenario)
end

if #observed.unexpected > 0 then
  for _, message in ipairs(observed.unexpected) do print("HIR67_UNEXPECTED_FAIL " .. message) end
  os.exit(1)
end
print("HIR67_HARNESS_PASS " .. scenario)
print("HIR67_FIXTURE_TEARDOWN PASS")
