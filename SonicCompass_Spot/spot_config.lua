--[[
  SonicCompass Spot — 共享配置常量

  说明：
    - 所有 Lua 脚本均从这里读取常量，便于一处修改全局生效。
    - BASE_DIR / TMP_DIR 必须与 SonicCompass Python 端 services 写入路径完全一致。
]]

local M = {}

-- ── 协议与端口 ───────────────────────────────
M.PROTOCOL_VERSION = "reaper_spot_v1"
M.SC_PORT          = 18765
M.SC_BASE_URL      = "http://127.0.0.1:" .. tostring(M.SC_PORT)
M.FOCUS_PATH       = "/api/reaper/focus-search"

-- ── Listener ExtState（运行时开关）───────────
M.LISTENER_SECTION       = "SonicCompass_Spot"
M.LISTENER_ENABLED_KEY   = "listener_enabled"
M.LISTENER_POLL_MS_KEY   = "listener_poll_ms"
M.LISTENER_HEARTBEAT_KEY = "listener_heartbeat"   -- 每 tick 写入 time_precise，防双开判活
M.HEARTBEAT_STALE_SEC    = 1.5                     -- 超过此时长认为旧 listener 已死，可接管

-- ── 监听节流参数 ─────────────────────────────
-- 250ms 轮询 + 每 tick 最多 2 条，目标是不超过 5 次/秒，避免拖慢 REAPER UI 帧率
M.DEFAULT_POLL_MS         = 250
M.MIN_POLL_MS             = 200
M.MAX_COMMANDS_PER_TICK   = 2

-- 单条命令在 IO 锁/解析失败时最多重试多少个 tick 才放弃
-- 250ms × 12 = 3 秒，足以覆盖 SC 写盘抖动
M.MAX_PARSE_RETRIES       = 12

-- ── 文件路径 ─────────────────────────────────
local sep = package.config:sub(1, 1)
M.PATH_SEP = sep
M.BASE_DIR = reaper.GetResourcePath() .. sep .. "Scripts" .. sep
                .. "Lee_Scripts" .. sep .. "SonicCompass_Spot"
M.TMP_DIR  = M.BASE_DIR .. sep .. "tmp"

return M
