-- @description RadialMenu Tool - 配置管理器
-- @author Lee
-- @about
--   负责配置文件的读取、保存、校验与预设管理。
--
--   Refactor notes (Phase 1):
--   - 默认值迁移至 `src/config_defaults.lua`（纯数据）
--   - load() 时执行“静默补全”：将缺失字段从 defaults deep_merge 进用户配置并自动保存
--   - 提供 Preset System 2.0 API：Blank / Duplicate / Rename

local M = {}

local json = require("json")
local DEFAULTS = require("config_defaults")

-- ============================================================================
-- 文本处理工具
-- ============================================================================

-- 简单的文本分割（支持 \n）
-- 从 wheel.lua 提取，用于配置预处理
function M.split_text_into_lines(text)
  local lines = {}
  if not text then return lines end
  -- 将 "\n" 替换为真实的换行符并在换行符处分割
  for line in (text:gsub("\\n", "\n") .. "\n"):gmatch("(.-)\n") do
    table.insert(lines, line)
  end
  return lines
end

-- 预处理扇区文本缓存
local function preprocess_sector_text_cache(config)
  if not config or not config.sectors then return end
  
  for _, sector in ipairs(config.sectors) do
    if sector.name then
      -- 预处理文本行并缓存
      sector.cached_lines = M.split_text_into_lines(sector.name)
    end
  end
end

-- ============================================================================
-- 路径
-- ============================================================================

function M.get_config_path()
  local script_path = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or ""
  -- 向上两级到 RadialMenu_Tool 根目录
  local root_path = script_path:match("(.*)src[\\/]") or script_path
  return root_path .. "config.json"
end

-- ============================================================================
-- 内部工具：deep copy / deep merge
-- ============================================================================

local function is_array(t)
  return type(t) == "table" and #t > 0
end

-- Robust deep copy with cycle protection.
function M.deep_copy_config(src, memo)
  if type(src) ~= "table" then return src end
  memo = memo or {}
  if memo[src] then return memo[src] end

  local dst = {}
  memo[src] = dst

  for k, v in pairs(src) do
    dst[M.deep_copy_config(k, memo)] = M.deep_copy_config(v, memo)
  end

  return dst
end

-- Deep-merge only MISSING fields from source into target.
-- - Does NOT overwrite existing target values
-- - Does NOT merge arrays (keeps target arrays as-is)
-- Returns: changed:boolean
local function deep_merge_missing(target, source, opts)
  if type(target) ~= "table" or type(source) ~= "table" then return false end
  opts = opts or {}
  local ignore = opts.ignore_keys or {}

  local changed = false

  for key, value in pairs(source) do
    if not ignore[key] then
      if target[key] == nil then
        target[key] = M.deep_copy_config(value)
        changed = true
      elseif type(value) == "table" and type(target[key]) == "table" then
        if not is_array(value) and not is_array(target[key]) then
          if deep_merge_missing(target[key], value, opts) then
            changed = true
          end
        end
      end
    end
  end

  return changed
end

local function schema_version()
  return DEFAULTS.CONFIG_SCHEMA_VERSION or DEFAULTS.version or "1.1.6"
end

local INTERNAL_KEYS = { CONFIG_SCHEMA_VERSION = true }

-- Normalize a config object against defaults.
-- - ensures version exists and matches schema
-- - merges missing fields from defaults
-- Returns: normalized_config, changed:boolean
local function normalize_config(cfg)
  if type(cfg) ~= "table" then
    cfg = {}
  end

  local changed = false

  -- Ensure version
  local sv = schema_version()
  if cfg.version ~= sv then
    cfg.version = sv
    changed = true
  end

  -- Fill missing structure
  if deep_merge_missing(cfg, DEFAULTS, { ignore_keys = INTERNAL_KEYS }) then
    changed = true
  end

  -- 【修复】限制膨胀幅度最大值为 10px，确保旧配置也会被自动修正
  if cfg.menu and cfg.menu.hover_expansion_pixels then
    local old_value = cfg.menu.hover_expansion_pixels
    local clamped_value = math.min(old_value, 10)
    if old_value ~= clamped_value then
      cfg.menu.hover_expansion_pixels = clamped_value
      changed = true
    end
  end

  -- Never persist internal keys
  if cfg.CONFIG_SCHEMA_VERSION ~= nil then
    cfg.CONFIG_SCHEMA_VERSION = nil
    changed = true
  end

  return cfg, changed
end

-- Public: default config (safe copy, no internal keys)
function M.get_default()
  local cfg = M.deep_copy_config(DEFAULTS)
  cfg.CONFIG_SCHEMA_VERSION = nil
  cfg.version = schema_version()
  return cfg
end

-- Convenience: merge an existing config with defaults (returns merged copy)
function M.merge_with_defaults(config)
  local cfg = M.deep_copy_config(config or {})
  cfg, _ = normalize_config(cfg)
  return cfg
end

-- ============================================================================
-- 配置校验
-- ============================================================================

function M.validate(config)
  if not config then
    return false, "配置为空"
  end

  if not config.version then
    return false, "缺少版本号"
  end

  if not config.menu then
    return false, "缺少 menu 配置"
  end

  if not config.menu.outer_radius or type(config.menu.outer_radius) ~= "number" then
    return false, "menu.outer_radius 必须是数字"
  end

  if not config.menu.inner_radius or type(config.menu.inner_radius) ~= "number" then
    return false, "menu.inner_radius 必须是数字"
  end

  if not config.colors then
    return false, "缺少 colors 配置"
  end

  if not config.sectors then
    return false, "缺少 sectors 配置"
  end

  if type(config.sectors) ~= "table" then
    return false, "sectors 必须是数组"
  end

  if #config.sectors == 0 then
    return false, "至少需要一个扇区"
  end

  for i, sector in ipairs(config.sectors) do
    if not sector.id then
      return false, "扇区 " .. i .. " 缺少 id"
    end

    if not sector.name or type(sector.name) ~= "string" then
      return false, "扇区 " .. i .. " 的 name 必须是字符串"
    end

    if not sector.color or type(sector.color) ~= "table" or #sector.color < 3 then
      return false, "扇区 " .. i .. " 的 color 格式错误"
    end

    if not sector.slots or type(sector.slots) ~= "table" then
      return false, "扇区 " .. i .. " 的 slots 必须是数组"
    end

    for j, slot in ipairs(sector.slots) do
      if not slot.type or (slot.type ~= "action" and slot.type ~= "fx" and slot.type ~= "chain" and slot.type ~= "template" and slot.type ~= "empty") then
        return false, string.format("扇区 %d 槽位 %d 的 type 无效: %s", i, j, tostring(slot.type))
      end

      if slot.type ~= "empty" then
        if not slot.name or type(slot.name) ~= "string" then
          return false, string.format("扇区 %d 槽位 %d 的 name 必须是字符串", i, j)
        end

        if not slot.data or type(slot.data) ~= "table" then
          return false, string.format("扇区 %d 槽位 %d 的 data 必须是表", i, j)
        end
      end
    end
  end

  return true, nil
end

-- ============================================================================
-- 内部：Full config（active_config + presets）读写
-- ============================================================================

local function persist_full_config(full_config)
  local config_path = M.get_config_path()
  return json.save_to_file(full_config, config_path, true)
end

local function new_full_config_with_default()
  local default_config = M.get_default()
  return {
    active_config = M.deep_copy_config(default_config),
    presets = {
      Default = M.deep_copy_config(default_config),
    },
    current_preset_name = "Default",
  }
end

-- 加载完整配置结构（包含 presets）
local function load_full_config()
  local config_path = M.get_config_path()

  -- File missing → create new
  local f = io.open(config_path, "r")
  if not f then
    local full = new_full_config_with_default()
    persist_full_config(full)
    return full
  end
  f:close()

  local full_config = json.load_from_file(config_path)
  if not full_config or type(full_config) ~= "table" then
    local full = new_full_config_with_default()
    persist_full_config(full)
    return full
  end

  local dirty = false

  -- Old format migration: config.json directly stores config without presets
  if not full_config.presets then
    local old_cfg = full_config
    old_cfg, dirty = normalize_config(old_cfg)

    full_config = {
      active_config = M.deep_copy_config(old_cfg),
      presets = {
        Default = M.deep_copy_config(old_cfg),
      },
      current_preset_name = "Default",
    }

    dirty = true
  end

  -- Ensure wrapper fields
  if type(full_config.presets) ~= "table" then
    full_config.presets = {}
    dirty = true
  end

  if type(full_config.current_preset_name) ~= "string" or full_config.current_preset_name == "" then
    full_config.current_preset_name = "Default"
    dirty = true
  end

  -- Ensure Default preset exists
  if not full_config.presets.Default or type(full_config.presets.Default) ~= "table" then
    full_config.presets.Default = M.get_default()
    dirty = true
  else
    local normalized, changed = normalize_config(full_config.presets.Default)
    full_config.presets.Default = normalized
    if changed then dirty = true end
  end

  -- Normalize all presets
  for name, preset_cfg in pairs(full_config.presets) do
    if type(preset_cfg) ~= "table" then
      full_config.presets[name] = M.get_default()
      dirty = true
    else
      local normalized, changed = normalize_config(preset_cfg)
      full_config.presets[name] = normalized
      if changed then dirty = true end
    end
  end

  -- Ensure current preset exists
  if not full_config.presets[full_config.current_preset_name] then
    full_config.current_preset_name = "Default"
    dirty = true
  end

  -- Ensure active_config
  if not full_config.active_config or type(full_config.active_config) ~= "table" then
    full_config.active_config = M.deep_copy_config(full_config.presets[full_config.current_preset_name])
    dirty = true
  else
    local normalized, changed = normalize_config(full_config.active_config)
    full_config.active_config = normalized
    if changed then dirty = true end
  end

  -- 预处理所有预设的文本缓存
  for name, preset_cfg in pairs(full_config.presets) do
    if type(preset_cfg) == "table" then
      preprocess_sector_text_cache(preset_cfg)
    end
  end
  
  -- 预处理 active_config 的文本缓存
  preprocess_sector_text_cache(full_config.active_config)

  -- Save silently if we had to补全/迁移
  if dirty then
    persist_full_config(full_config)
  end

  return full_config
end

-- ============================================================================
-- 对外：load/save
-- ============================================================================

function M.load()
  local full_config = load_full_config()
  local config = full_config.active_config
  -- 确保文本缓存已创建（向后兼容）
  if config and config.sectors then
    for _, sector in ipairs(config.sectors) do
      if sector.name and not sector.cached_lines then
        sector.cached_lines = M.split_text_into_lines(sector.name)
      end
    end
  end
  return config
end

function M.save(config)
  -- Normalize before validate so version/fields are present
  local normalized = M.merge_with_defaults(config)

  local is_valid, error_msg = M.validate(normalized)
  if not is_valid then
    reaper.ShowMessageBox("配置验证失败: " .. error_msg, "错误", 0)
    return false
  end

  -- 预处理文本缓存
  preprocess_sector_text_cache(normalized)

  local full_config = load_full_config()

  full_config.active_config = normalized

  local current_preset_name = full_config.current_preset_name or "Default"
  if full_config.presets and full_config.presets[current_preset_name] then
    full_config.presets[current_preset_name] = M.deep_copy_config(normalized)
  end

  local success, err = persist_full_config(full_config)
  if not success then
    reaper.ShowMessageBox("配置保存失败: " .. (err or "未知错误"), "错误", 0)
    return false
  end

  -- 发出配置更新信号，通知运行中的轮盘重新加载配置
  reaper.SetExtState("RadialMenu", "ConfigUpdated", tostring(os.time()), false)

  return true
end

-- ============================================================================
-- Preset System 2.0
-- ============================================================================

-- A) Return a clean config template (does NOT save)
function M.create_blank_config()
  -- 创建一个真正的空白配置，使用默认值的基本结构
  local cfg = M.get_default()

  -- 创建3个空扇区（每个扇区12个空槽位）
  local sectors = {}
  for i = 1, 3 do
    local slots = {}
    for _ = 1, 12 do
      table.insert(slots, { type = "empty" })
    end
    
    local default_sector_color = (DEFAULTS.sectors and DEFAULTS.sectors[i] and DEFAULTS.sectors[i].color) or { 70, 130, 180, 200 }
    local default_sector_icon = (DEFAULTS.sectors and DEFAULTS.sectors[i] and DEFAULTS.sectors[i].icon) or ""
    
    table.insert(sectors, {
      id = i,
      name = "Sector " .. i,  -- 使用固定格式，避免语言依赖
      icon = default_sector_icon,
      color = M.deep_copy_config(default_sector_color),
      slots = slots,
    })
  end

  cfg.sectors = sectors
  return cfg
end

-- B) Rename an existing preset key (persists to config.json)
function M.rename_preset(old_name, new_name)
  if not old_name or old_name == "" then
    return false, "旧预设名称不能为空"
  end
  if not new_name or new_name == "" then
    return false, "新预设名称不能为空"
  end

  if old_name == "Default" then
    return false, "不能重命名默认预设"
  end

  local full_config = load_full_config()
  full_config.presets = full_config.presets or {}

  if not full_config.presets[old_name] then
    return false, "预设不存在"
  end

  if full_config.presets[new_name] then
    return false, "目标名称已存在，已阻止覆盖"
  end

  full_config.presets[new_name] = full_config.presets[old_name]
  full_config.presets[old_name] = nil

  if full_config.current_preset_name == old_name then
    full_config.current_preset_name = new_name
  end

  local success, err = persist_full_config(full_config)
  if not success then
    return false, "保存失败: " .. (err or "未知错误")
  end

  return true
end

-- C) Optional helper: deep copy config for duplication workflows
function M.duplicate_preset(source_config)
  local cfg = M.deep_copy_config(source_config or {})
  cfg, _ = normalize_config(cfg)
  return cfg
end

-- ============================================================================
-- 预设管理（兼容旧 API）
-- ============================================================================

function M.load_presets()
  local full_config = load_full_config()
  return full_config.presets or {}
end

function M.save_preset(name, config_data)
  if not name or name == "" then
    return false, "预设名称不能为空"
  end

  local cfg = M.merge_with_defaults(config_data)
  local is_valid, error_msg = M.validate(cfg)
  if not is_valid then
    return false, "配置验证失败: " .. error_msg
  end

  local full_config = load_full_config()
  full_config.presets = full_config.presets or {}

  full_config.presets[name] = M.deep_copy_config(cfg)

  local success, err = persist_full_config(full_config)
  if not success then
    return false, "保存失败: " .. (err or "未知错误")
  end

  return true
end

function M.delete_preset(name)
  if not name or name == "" then
    return false, "预设名称不能为空"
  end

  if name == "Default" then
    return false, "不能删除默认预设"
  end

  local full_config = load_full_config()

  if not full_config.presets or not full_config.presets[name] then
    return false, "预设不存在"
  end

  full_config.presets[name] = nil

  if full_config.current_preset_name == name then
    full_config.current_preset_name = "Default"
    full_config.active_config = M.deep_copy_config(full_config.presets.Default)
  end

  local success, err = persist_full_config(full_config)
  if not success then
    return false, "保存失败: " .. (err or "未知错误")
  end

  return true
end

function M.apply_preset(name)
  if not name or name == "" then
    return nil, "预设名称不能为空"
  end

  local full_config = load_full_config()

  if not full_config.presets or not full_config.presets[name] then
    return nil, "预设不存在"
  end

  full_config.active_config = M.deep_copy_config(full_config.presets[name])
  full_config.current_preset_name = name
  
  -- 确保文本缓存已创建
  preprocess_sector_text_cache(full_config.active_config)

  local success, err = persist_full_config(full_config)
  if not success then
    return nil, "保存失败: " .. (err or "未知错误")
  end

  reaper.SetExtState("RadialMenu", "ConfigUpdated", tostring(os.time()), false)

  return full_config.active_config
end

function M.get_preset_list()
  local presets = M.load_presets()
  local names = {}
  for name, _ in pairs(presets) do
    table.insert(names, name)
  end

  table.sort(names, function(a, b)
    if a == "Default" then return true end
    if b == "Default" then return false end
    return a < b
  end)

  return names
end

function M.get_current_preset_name()
  local full_config = load_full_config()
  return full_config.current_preset_name or "Default"
end

function M.set_current_preset_name(name)
  if not name or name == "" then
    return false, "预设名称不能为空"
  end

  local full_config = load_full_config()

  if not full_config.presets or not full_config.presets[name] then
    return false, "预设不存在"
  end

  full_config.current_preset_name = name

  local success, err = persist_full_config(full_config)
  if not success then
    return false, "保存失败: " .. (err or "未知错误")
  end

  return true
end

-- ============================================================================
-- 其它工具函数（供 GUI/运行时使用）
-- ============================================================================

function M.reset_to_default()
  local default_config = M.get_default()
  M.save(default_config)
  return default_config
end

function M.get_sector_count(config)
  return config and config.sectors and #config.sectors or 0
end

function M.get_sector_by_id(config, sector_id)
  if not config or not config.sectors then
    return nil
  end

  for _, sector in ipairs(config.sectors) do
    if sector.id == sector_id then
      return sector
    end
  end

  return nil
end

function M.add_slot_to_sector(config, sector_id, slot)
  local sector = M.get_sector_by_id(config, sector_id)
  if not sector then
    return false, "扇区不存在"
  end

  local max_slots = (config and config.menu and config.menu.max_slots_per_sector) or 12
  if #sector.slots >= max_slots then
    return false, "扇区槽位已满"
  end

  table.insert(sector.slots, slot)
  return true
end

function M.remove_slot_from_sector(config, sector_id, slot_index)
  local sector = M.get_sector_by_id(config, sector_id)
  if not sector then
    return false, "扇区不存在"
  end

  if slot_index < 1 or slot_index > #sector.slots then
    return false, "槽位索引无效"
  end

  table.remove(sector.slots, slot_index)
  return true
end

return M
