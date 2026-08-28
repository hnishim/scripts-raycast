"""Focused HIR-67 tests for the Lua-native Hammerspoon Gemini path."""

import pathlib
import subprocess
import unittest


COMMAND = pathlib.Path(
    "/Users/hnishim/Library/Mobile Documents/com~apple~CloudDocs/Dev/scripts/hammerspoon/ai_command.lua"
)
LUA = pathlib.Path("/opt/homebrew/bin/lua")

LUA_CASE = r'''
local mode, commandPath = arg[1], arg[2]
local state = {
  alerts = {}, bindings = {}, dialogs = 0, tasks = {}, timers = {},
  clipboard = "ORIGINAL", clipboardCount = 40, pasteCount = 0,
  copyCalls = 0, resultCount = 0, httpCallback = nil, httpCalls = 0,
  payload = { candidates = {{ content = { parts = {{ text = "RESPONSE" }} } }} },
}

local hs = {
  hotkey = {}, task = {}, alert = {}, dialog = {}, eventtap = {},
  uielement = {}, application = {}, pasteboard = {}, timer = {},
  http = {}, json = {}, screen = {}, webview = {}, drawing = {},
}

function hs.hotkey.bind(_, key, callback) state.bindings[key] = callback; return {} end
function hs.alert.show(message) table.insert(state.alerts, tostring(message)) end
function hs.dialog.textPrompt() state.dialogs = state.dialogs + 1; return "キャンセル", "" end

function hs.task.new(path, callback, arguments)
  local task = { path = path, callback = callback, arguments = arguments or {}, started = false, terminated = false }
  function task:start() self.started = true; return true end
  function task:terminate() self.terminated = true; return self end
  function task:finish(exitCode, stdout, stderr)
    if self.callback then self.callback(exitCode, stdout or "", stderr or "") end
  end
  table.insert(state.tasks, task)
  return task
end

function hs.timer.doAfter(_, callback)
  local timer = { callback = callback, stopped = false }
  function timer:stop() self.stopped = true; return self end
  table.insert(state.timers, timer)
  return timer
end

local function runTimer()
  while #state.timers > 0 do
    local timer = table.remove(state.timers, 1)
    if not timer.stopped then timer.callback(); return true end
  end
  return false
end

hs.json.encode = function() return "encoded-request" end
hs.json.decode = function()
  if mode == "json_failure" then error("invalid JSON", 0) end
  return state.payload
end
hs.http.asyncPost = function(_, body, headers, callback)
  state.httpCalls = state.httpCalls + 1
  state.httpBody = body
  state.httpHeaders = headers
  state.httpCallback = callback
end

hs.screen.mainScreen = function()
  return { frame = function() return { x = 0, y = 0, w = 1200, h = 800 } end }
end
hs.drawing.windowLevels = { floating = 1 }
hs.webview.new = function()
  local view = {}
  for _, name in ipairs({ "windowStyle", "windowTitle", "level", "allowGestures", "allowTextEntry", "closeOnEscape", "shadow", "html", "windowCallback" }) do
    view[name] = function(self) return self end
  end
  view.show = function(self) state.resultCount = state.resultCount + 1; return self end
  view.delete = function(self) self.deleted = true; return self end
  return view
end

hs.application.frontmostApplication = function()
  return { activate = function() return true end, isFrontmost = function() return true end }
end
hs.uielement.focusedElement = function()
  if mode == "focused_failure" then error("AX failure", 0) end
  if mode == "focused_nil" then return nil end
  return { selectedText = function()
    if mode == "selected_failure" then error("selection failure", 0) end
    if mode == "empty" then return "" end
    if mode == "whitespace" then return "  exact\n  " end
    if mode == "nil_text" then return nil end
    return "selection"
  end }
end

hs.pasteboard.getContents = function() return state.clipboard end
hs.pasteboard.changeCount = function() return state.clipboardCount end
hs.pasteboard.setContents = function(value)
  state.clipboard = value; state.clipboardCount = state.clipboardCount + 1; return true
end
hs.pasteboard.clearContents = function()
  state.clipboard = nil; state.clipboardCount = state.clipboardCount + 1; return true
end
hs.eventtap.keyStroke = function(_, key)
  if key == "v" then state.pasteCount = state.pasteCount + 1 end
  if key == "c" then state.copyCalls = state.copyCalls + 1 end
  return true
end

io.open = function()
  local contents = mode == "invalid_prompt" and "{selection invalid}" or "Prompt: {selection} {argument name=\"Word\"}"
  local handle = {}
  function handle:read() return contents end
  function handle:close() end
  return handle
end

_G.hs = hs
package.path = (commandPath:match("^(.*)/[^/]+$") or ".") .. "/?.lua;" .. package.path
local module = dofile(commandPath)
module.start()

local key = (mode == "b_success" or mode == "json_failure" or mode == "http_failure") and "B"
  or ((mode == "r_success" or mode == "r_timeout") and "R" or "B")
local callback = state.bindings[key]
assert(callback, "missing hotkey " .. key)
callback()

if mode == "empty" then
  assert(state.dialogs == 1 and #state.tasks == 0, "empty selection opened the wrong path")
elseif mode == "whitespace" then
  assert(#state.tasks == 1 and state.tasks[1].path == "/usr/bin/id", "whitespace selection did not start Keychain lookup")
  assert(state.copyCalls == 0, "selection acquisition used synthetic copy")
elseif mode == "focused_nil" or mode == "focused_failure" or mode == "selected_failure" or mode == "nil_text" then
  assert(#state.tasks == 0 and #state.alerts == 1, "invalid selection path mismatch")
elseif mode == "invalid_prompt" then
  assert(#state.tasks == 0 and #state.alerts == 1, "invalid prompt reached Keychain")
elseif mode == "b_success" or mode == "json_failure" or mode == "http_failure" then
  assert(#state.tasks == 1 and state.tasks[1].path == "/usr/bin/id", "B did not start id task")
  state.tasks[1]:finish(0, "test-user\n", "")
  assert(#state.tasks == 2 and state.tasks[2].path == "/usr/bin/security", "security task was not chained")
  assert(state.tasks[2].arguments[1] == "find-generic-password", "wrong security operation")
  assert(state.tasks[2].arguments[5] == "test-user", "wrong Keychain account")
  state.tasks[2]:finish(0, "api-key\n", "")
  assert(state.httpCalls == 1 and state.httpHeaders["x-goog-api-key"] == "api-key", "HTTP was not started safely")
  if mode == "json_failure" then
    state.httpCallback(200, "invalid", {})
  elseif mode == "http_failure" then
    state.httpCallback(-1, "network failure", nil)
  else
    state.httpCallback(200, "response", {})
  end
  assert(state.pasteCount == 0 and state.clipboard == "ORIGINAL", "B touched clipboard")
  assert((mode == "b_success" and state.resultCount == 1) or (mode ~= "b_success" and #state.alerts == 1), "B result/error mismatch")
elseif mode == "r_success" or mode == "r_timeout" then
  callback()
  assert(#state.tasks == 1, "busy operation was not rejected")
  state.tasks[1]:finish(0, "test-user\n", "")
  state.tasks[2]:finish(0, "api-key\n", "")
  assert(state.httpCallback and state.httpCalls == 1, "R HTTP was not started")
  local stale = state.httpCallback
  if mode == "r_timeout" then
    runTimer()
    local before = state.clipboard
    stale(200, "response", {})
    assert(state.clipboard == before and state.pasteCount == 0, "late timeout callback touched clipboard")
  else
    stale(200, "response", {})
    assert(state.clipboard == "RESPONSE" and state.pasteCount == 1, "R did not paste response")
    runTimer()
    assert(state.clipboard == "ORIGINAL", "R did not restore prior clipboard")
  end
end

print("HIR67_REGRESSION_PASS " .. mode)
'''


def run_case(mode):
    result = subprocess.run(
        [str(LUA), "-", mode, str(COMMAND)],
        input=LUA_CASE,
        text=True,
        capture_output=True,
        timeout=12,
    )
    if result.returncode:
        raise AssertionError("%s failed (rc=%s):\n%s" %
                             (mode, result.returncode, result.stdout + result.stderr))
    marker = "HIR67_REGRESSION_PASS " + mode
    if marker not in result.stdout:
        raise AssertionError("missing regression marker for " + mode)


class HammerspoonAcquisitionRegressionTests(unittest.TestCase):
    def test_selection_and_failure_paths(self):
        for mode in ("empty", "whitespace", "focused_nil", "focused_failure", "selected_failure", "nil_text", "invalid_prompt"):
            run_case(mode)

    def test_lua_native_gemini_and_output_paths(self):
        for mode in ("b_success", "json_failure", "http_failure", "r_success", "r_timeout"):
            run_case(mode)


if __name__ == "__main__":
    unittest.main()
