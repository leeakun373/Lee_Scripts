-- @description RadialMenu Tool - 配置管理器
-- @author Lee
-- @about
--   负责配置文件的读取、保存和验证
--   使用 JSON 格式存储配置

local M = {}

-- 加载 JSON 库（使用 dkjson）
local json = require("json")

-- ============================================================================
-- 配置文件路径
-- ============================================================================

-- 获取配置文件路径
function M.get_config_path()
    local script_path = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or ""
    -- 向上两级到 RadialMenu_Tool 根目录
    local root_path = script_path:match("(.*)src[\\/]") or script_path
    return root_path .. "config.json"
end

-- ============================================================================
-- 默认配置结构
-- ============================================================================

-- 返回默认配置表结构
-- 包含 6 个扇区，每个扇区 12 个空槽位
function M.get_default()
    return {
        version = "1.1.0",
        
        -- 菜单外观设置
        menu = {
            outer_radius = 90,            -- 轮盘外半径
            inner_radius = 25,            -- 中心圆半径（死区）
            sector_border_width = 2,      -- 扇区边框宽度
            hover_brightness = 1.3,       -- 悬停时亮度增加倍数
            animation_speed = 0.2,        -- 动画速度
            max_slots_per_sector = 9,     -- 每个扇区最大槽位数
            hover_to_open = false,        -- 悬停打开子菜单（false = 点击打开）
            -- Sector Expansion Settings
            enable_sector_expansion = true, -- 启用扇区膨胀动画
            hover_expansion_pixels = 10,   -- 悬停时扇区向外扩展的像素数
            hover_animation_speed = 4,     -- 悬停扩展动画速度 (1-10 整数刻度，默认 4 = 平衡)
            slot_width = 65,              -- 子菜单插槽宽度（像素）
            slot_height = 25,             -- 子菜单插槽高度（像素）
            animation = {
                enable = true,             -- 是否启用动画
                duration_open = 0.06,      -- 轮盘展开时间（秒）- 极速模式
                duration_submenu = 0.05    -- 子菜单弹出时间（秒）- 极速模式
            }
        },
        
        -- 颜色配置（RGBA格式，0-255）
        colors = {
            background = {30, 30, 30, 240},
            center_circle = {50, 50, 50, 255},
            border = {100, 100, 100, 200},
            hover_overlay = {255, 255, 255, 50},
            text = {255, 255, 255, 255},
            text_shadow = {0, 0, 0, 150}
        },
        
        -- 扇区配置（6个扇区）
        sectors = {
            {
                id = 1,
                name = "Actions",
                icon = "⚡",
                color = {70, 130, 180, 200},  -- Steel Blue
                slots = {}  -- 空槽位，用户可自定义
            },
            {
                id = 2,
                name = "FX",
                icon = "🎛️",
                color = {138, 43, 226, 200},  -- Blue Violet
                slots = {}
            },
            {
                id = 3,
                name = "Scripts",
                icon = "📜",
                color = {220, 20, 60, 200},   -- Crimson
                slots = {}
            },
            {
                id = 4,
                name = "Tracks",
                icon = "🎵",
                color = {34, 139, 34, 200},   -- Forest Green
                slots = {}
            },
            {
                id = 5,
                name = "Markers",
                icon = "🏷️",
                color = {255, 140, 0, 200},   -- Dark Orange
                slots = {}
            },
            {
                id = 6,
                name = "Tools",
                icon = "🔧",
                color = {128, 128, 128, 200}, -- Gray
                slots = {}
            }
        }
    }
end

-- ============================================================================
-- 配置加载
-- ============================================================================

-- 内部函数：加载完整的配置文件结构（包含 presets）
local function load_full_config()
    local config_path = M.get_config_path()
    
    -- 检查文件是否存在
    local file = io.open(config_path, "r")
    if not file then
        -- 文件不存在，创建新结构
        local default_config = M.get_default()
        local full_config = {
            active_config = default_config,
            presets = {
                Default = default_config
            },
            current_preset_name = "Default"
        }
        -- 保存新结构
        local success, err = json.save_to_file(full_config, config_path, true)
        return full_config
    end
    file:close()
    
    -- 加载 JSON 文件
    local full_config, err = json.load_from_file(config_path)
    
    if not full_config then
        -- 加载失败，返回默认结构
        local default_config = M.get_default()
        return {
            active_config = default_config,
            presets = {
                Default = default_config
            },
            current_preset_name = "Default"
        }
    end
    
    -- 检测旧版配置（没有 presets 字段）
    if not full_config.presets then
        -- 旧版配置，进行迁移
        local old_config = full_config
        local default_config = M.get_default()
        
        -- 合并旧配置与默认值
        old_config = M.merge_with_defaults(old_config)
        
        -- 创建新结构
        full_config = {
            active_config = old_config,
            presets = {
                Default = old_config
            },
            current_preset_name = "Default"
        }
        
        -- 保存迁移后的配置
        json.save_to_file(full_config, config_path, true)
    end
    
    -- 确保结构完整
    if not full_config.active_config then
        local default_config = M.get_default()
        full_config.active_config = default_config
    end
    
    if not full_config.presets then
        full_config.presets = {}
    end
    
    if not full_config.presets.Default then
        local default_config = M.get_default()
        full_config.presets.Default = default_config
    end
    
    if not full_config.current_preset_name then
        full_config.current_preset_name = "Default"
    end
    
    -- 验证 active_config
    local is_valid, error_msg = M.validate(full_config.active_config)
    if not is_valid then
        -- 验证失败，使用默认配置
        local default_config = M.get_default()
        full_config.active_config = default_config
        full_config.presets.Default = default_config
    else
        -- 合并默认值确保完整性
        full_config.active_config = M.merge_with_defaults(full_config.active_config)
    end
    
    return full_config
end

-- 从 config.json 加载配置
-- 返回当前激活的配置（active_config）
function M.load()
    local full_config = load_full_config()
    return full_config.active_config
end

-- ============================================================================
-- 配置保存
-- ============================================================================

-- 将配置保存到 config.json
-- 同时更新 active_config 和当前预设
function M.save(config)
    local config_path = M.get_config_path()
    
    -- 验证配置
    local is_valid, error_msg = M.validate(config)
    if not is_valid then
        reaper.ShowMessageBox("配置验证失败: " .. error_msg, "错误", 0)
        return false
    end
    
    -- 加载完整配置结构
    local full_config = load_full_config()
    
    -- 更新 active_config
    full_config.active_config = config
    
    -- 更新当前预设（如果存在）
    local current_preset_name = full_config.current_preset_name or "Default"
    if full_config.presets[current_preset_name] then
        full_config.presets[current_preset_name] = config
    end
    
    -- 保存到文件（带缩进格式化）
    local success, err = json.save_to_file(full_config, config_path, true)
    
    if not success then
        reaper.ShowMessageBox("配置保存失败: " .. (err or "未知错误"), "错误", 0)
        return false
    end
    
    -- 发出配置更新信号，通知运行中的轮盘重新加载配置
    reaper.SetExtState("RadialMenu", "ConfigUpdated", tostring(os.time()), false)
    
    -- reaper.ShowConsoleMsg("配置文件已保存: " .. config_path .. "\n")
    return true
end

-- ============================================================================
-- 配置验证
-- ============================================================================

-- 验证配置表结构是否正确
function M.validate(config)
    if not config then
        return false, "配置为空"
    end
    
    -- 检查版本号
    if not config.version then
        return false, "缺少版本号"
    end
    
    -- 检查 menu 配置
    if not config.menu then
        return false, "缺少 menu 配置"
    end
    
    if not config.menu.outer_radius or type(config.menu.outer_radius) ~= "number" then
        return false, "menu.outer_radius 必须是数字"
    end
    
    if not config.menu.inner_radius or type(config.menu.inner_radius) ~= "number" then
        return false, "menu.inner_radius 必须是数字"
    end
    
    -- 检查 colors 配置
    if not config.colors then
        return false, "缺少 colors 配置"
    end
    
    -- 检查 sectors 配置
    if not config.sectors then
        return false, "缺少 sectors 配置"
    end
    
    if type(config.sectors) ~= "table" then
        return false, "sectors 必须是数组"
    end
    
    if #config.sectors == 0 then
        return false, "至少需要一个扇区"
    end
    
    -- 验证每个扇区
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
        
        -- 验证槽位
        for j, slot in ipairs(sector.slots) do
            -- [FIX] Allow "empty", "chain", "template" types
            if not slot.type or (slot.type ~= "action" and slot.type ~= "fx" and slot.type ~= "chain" and slot.type ~= "template" and slot.type ~= "empty") then
                return false, string.format("扇区 %d 槽位 %d 的 type 无效: %s", i, j, tostring(slot.type))
            end
            
            -- [FIX] Skip detailed validation for empty slots
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
-- 配置合并
-- ============================================================================

-- 将加载的配置与默认配置合并，确保所有必需字段都存在
function M.merge_with_defaults(config)
    local default = M.get_default()
    
    -- 深度合并函数
    local function deep_merge(target, source)
        for key, value in pairs(source) do
            if target[key] == nil then
                target[key] = value
            elseif type(value) == "table" and type(target[key]) == "table" then
                -- 递归合并表（但不合并数组）
                if not (#value > 0) then  -- 不是数组
                    deep_merge(target[key], value)
                end
            end
        end
        return target
    end
    
    return deep_merge(config, default)
end

-- ============================================================================
-- 辅助函数
-- ============================================================================

-- 重置为默认配置
function M.reset_to_default()
    local default_config = M.get_default()
    M.save(default_config)
    return default_config
end

-- 获取扇区数量
function M.get_sector_count(config)
    return config and config.sectors and #config.sectors or 0
end

-- 根据 ID 获取扇区
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

-- 添加槽位到扇区
function M.add_slot_to_sector(config, sector_id, slot)
    local sector = M.get_sector_by_id(config, sector_id)
    if not sector then
        return false, "扇区不存在"
    end
    
    -- 检查槽位数量限制
    local max_slots = config.menu.max_slots_per_sector or 9
    if #sector.slots >= max_slots then
        return false, "扇区槽位已满"
    end
    
    table.insert(sector.slots, slot)
    return true
end

-- 从扇区删除槽位
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

-- ============================================================================
-- 预设管理函数
-- ============================================================================

-- 加载完整的预设列表
function M.load_presets()
    local full_config = load_full_config()
    return full_config.presets or {}
end

-- 保存预设
-- @param name string: 预设名称
-- @param config_data table: 配置数据
function M.save_preset(name, config_data)
    if not name or name == "" then
        return false, "预设名称不能为空"
    end
    
    -- 验证配置
    local is_valid, error_msg = M.validate(config_data)
    if not is_valid then
        return false, "配置验证失败: " .. error_msg
    end
    
    local config_path = M.get_config_path()
    local full_config = load_full_config()
    
    -- 确保 presets 表存在
    if not full_config.presets then
        full_config.presets = {}
    end
    
    -- 保存预设（深拷贝）
    full_config.presets[name] = M.deep_copy_config(config_data)
    
    -- 保存到文件
    local success, err = json.save_to_file(full_config, config_path, true)
    if not success then
        return false, "保存失败: " .. (err or "未知错误")
    end
    
    return true
end

-- 删除预设
-- @param name string: 预设名称
function M.delete_preset(name)
    if not name or name == "" then
        return false, "预设名称不能为空"
    end
    
    -- 禁止删除 Default 预设
    if name == "Default" then
        return false, "不能删除默认预设"
    end
    
    local config_path = M.get_config_path()
    local full_config = load_full_config()
    
    -- 检查预设是否存在
    if not full_config.presets or not full_config.presets[name] then
        return false, "预设不存在"
    end
    
    -- 删除预设
    full_config.presets[name] = nil
    
    -- 如果删除的是当前预设，切换到 Default
    if full_config.current_preset_name == name then
        full_config.current_preset_name = "Default"
        if full_config.presets.Default then
            full_config.active_config = M.deep_copy_config(full_config.presets.Default)
        end
    end
    
    -- 保存到文件
    local success, err = json.save_to_file(full_config, config_path, true)
    if not success then
        return false, "保存失败: " .. (err or "未知错误")
    end
    
    return true
end

-- 应用预设
-- @param name string: 预设名称
function M.apply_preset(name)
    if not name or name == "" then
        return nil, "预设名称不能为空"
    end
    
    local config_path = M.get_config_path()
    local full_config = load_full_config()
    
    -- 检查预设是否存在
    if not full_config.presets or not full_config.presets[name] then
        return nil, "预设不存在"
    end
    
    -- 应用预设到 active_config
    local preset_config = full_config.presets[name]
    full_config.active_config = M.deep_copy_config(preset_config)
    full_config.current_preset_name = name
    
    -- 保存到文件
    local success, err = json.save_to_file(full_config, config_path, true)
    if not success then
        return nil, "保存失败: " .. (err or "未知错误")
    end
    
    -- 发出配置更新信号
    reaper.SetExtState("RadialMenu", "ConfigUpdated", tostring(os.time()), false)
    
    return full_config.active_config
end

-- 获取预设列表（返回名称数组）
function M.get_preset_list()
    local presets = M.load_presets()
    local preset_names = {}
    
    for name, _ in pairs(presets) do
        table.insert(preset_names, name)
    end
    
    -- 排序（Default 排在第一位）
    table.sort(preset_names, function(a, b)
        if a == "Default" then return true end
        if b == "Default" then return false end
        return a < b
    end)
    
    return preset_names
end

-- 获取当前预设名称
function M.get_current_preset_name()
    local full_config = load_full_config()
    return full_config.current_preset_name or "Default"
end

-- 设置当前预设名称
function M.set_current_preset_name(name)
    if not name or name == "" then
        return false, "预设名称不能为空"
    end
    
    local config_path = M.get_config_path()
    local full_config = load_full_config()
    
    -- 检查预设是否存在
    if not full_config.presets or not full_config.presets[name] then
        return false, "预设不存在"
    end
    
    full_config.current_preset_name = name
    
    -- 保存到文件
    local success, err = json.save_to_file(full_config, config_path, true)
    if not success then
        return false, "保存失败: " .. (err or "未知错误")
    end
    
    return true
end

-- 深拷贝配置（用于预设管理）
function M.deep_copy_config(src)
    if type(src) ~= "table" then
        return src
    end
    
    local dst = {}
    for key, value in pairs(src) do
        if type(value) == "table" then
            dst[key] = M.deep_copy_config(value)
        else
            dst[key] = value
        end
    end
    
    -- 处理数组部分
    if #src > 0 then
        for i = 1, #src do
            if type(src[i]) == "table" then
                dst[i] = M.deep_copy_config(src[i])
            else
                dst[i] = src[i]
            end
        end
    end
    
    return dst
end

return M
