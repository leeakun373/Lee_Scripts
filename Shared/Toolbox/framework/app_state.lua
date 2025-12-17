-- Shared/Toolbox/framework/app_state.lua
-- 把 config/log/terminal 等“运行时状态”拼装在一起。

local Config = require("config")
local Log = require("log")
local Terminal = require("terminal")
local U = require("util")

local M = {}

function M.attach(app)
  app.state = Config.load(app)
  app.log = Log.new(800)
  app.terminal = Terminal.new()

  -- 初始欢迎日志
  Log.info(app.log, "Shared Toolbox: loaded")

  return app
end

function M.save(app)
  Config.save(app, app.state)
end

-- 自动保存：仅在内容变更且超过 interval 秒时写入 ExtState
function M.tick(app, interval)
  interval = interval or 1.0
  app._autosave = app._autosave or {t = 0, last = nil}

  local now = reaper.time_precise()
  if now - app._autosave.t < interval then
    return
  end
  app._autosave.t = now

  local raw = U.serialize(app.state)
  if raw ~= app._autosave.last then
    Config.save(app, app.state)
    app._autosave.last = raw
  end
end

return M
