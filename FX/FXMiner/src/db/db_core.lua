-- FXMiner/src/db/db_core.lua
-- 核心数据库操作：加载、保存、索引、路径转换

local json = require("json")
local Utils = require("db.db_utils")

local Core = {}

-- Initialize core methods on DB instance
function Core.init(DB)
  -- Reindex: rebuild _index from entries
  function DB:_reindex()
    self._index = {}
    if not self.data or not self.data.entries then return end
    for _, e in ipairs(self.data.entries) do
      if e and e.rel_path then
        self._index[e.rel_path] = e
      end
    end
  end

  -- Load database from file
  function DB:load()
    local dir = self:db_dir()
    local path = self:db_path()

    if type(dir) ~= "string" or dir == "" or type(path) ~= "string" or path == "" then
      Utils.show_error(
        "FXMiner DB init failed: invalid config paths.\n\n" ..
        "DB dir: " .. tostring(dir) .. "\n" ..
        "DB path: " .. tostring(path) .. "\n\n" ..
        "Tip: This often happens when module name 'config' conflicts with Toolbox config.lua."
      )
      return false
    end

    Utils.ensure_dir(dir)

    local raw = Utils.read_all(path)
    if not raw or raw == "" then
      self.data = {
        schema_version = self.cfg.SCHEMA_VERSION or "1.0",
        entries = {},
      }
      self:_reindex()
      self:save()
      return true
    end

    local ok, decoded = pcall(function()
      return json.decode(raw)
    end)
    if not ok or type(decoded) ~= "table" then
      -- 如果 DB 损坏：备份并重建（尽量不阻断用户）
      local backup = self:db_path() .. ".bak_" .. tostring(Utils.now_sec())
      pcall(function()
        local f = io.open(backup, "w")
        if f then
          f:write(raw)
          f:close()
        end
      end)
      self.data = {
        schema_version = self.cfg.SCHEMA_VERSION or "1.0",
        entries = {},
        _recovered_from = backup,
      }
      self:_reindex()
      self:save()
      return true
    end

    decoded.entries = decoded.entries or {}
    self.data = decoded
    -- Note: Entry migration is handled in ensure_initialized()
    self:_reindex()
    return true
  end

  -- Save database to file
  function DB:save()
    Utils.ensure_dir(self:db_dir())
    return json.save_to_file(self.data or {}, self:db_path(), true)
  end

  -- Make relative path from absolute path
  function DB:make_relpath(abs_rfx_path)
    local from_dir = self.cfg.norm_slash and self.cfg.norm_slash(self:db_dir()) or tostring(self:db_dir()):gsub("\\", "/")
    local to_path = self.cfg.norm_slash and self.cfg.norm_slash(abs_rfx_path) or tostring(abs_rfx_path):gsub("\\", "/")

    from_dir = from_dir:gsub("/+$", "")
    to_path = to_path:gsub("/+$", "")

    from_dir = from_dir:gsub("/+", "/")
    to_path = to_path:gsub("/+", "/")

    from_dir = from_dir:gsub("/$", "")

    local from_parts = Utils.split_slash(from_dir)
    local to_parts = Utils.split_slash(to_path)

    local i = 1
    while i <= #from_parts and i <= #to_parts and Utils.lower(from_parts[i]) == Utils.lower(to_parts[i]) do
      i = i + 1
    end
    local common = i - 1

    local rel = {}
    for _ = 1, (#from_parts - common) do
      rel[#rel + 1] = ".."
    end
    for j = common + 1, #to_parts do
      rel[#rel + 1] = to_parts[j]
    end

    return table.concat(rel, "/")
  end

  -- Convert relative path to absolute path
  function DB:rel_to_abs(rel_path)
    -- rel_path is relative to DATA_DIR_PATH (e.g. ../Foo.RfxChain)
    local base = tostring(self:db_dir() or "")
    if base == "" then return nil end
    local rel = tostring(rel_path or "")
    if rel == "" then return nil end

    -- join using '/' then normalize
    local joined = base:gsub("\\", "/"):gsub("/+$", "") .. "/" .. rel:gsub("\\", "/")
    return Utils.norm_abs_path(joined)
  end
end

return Core

