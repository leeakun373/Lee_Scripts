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
        version = "1.0.0",
        
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

-- 从 config.json 加载配置
-- 如果文件不存在，创建并返回默认配置
-- 如果文件格式错误，显示错误并返回默认配置
function M.load()
    local config_path = M.get_config_path()
    
    -- 检查文件是否存在
    local file = io.open(config_path, "r")
    if not file then
        -- reaper.ShowConsoleMsg("配置文件不存在，创建默认配置...\n")
        local default_config = M.get_default()
        M.save(default_config)
        return default_config
    end
    file:close()
    
    -- 加载 JSON 文件
    local config, err = json.load_from_file(config_path)
    
    if not config then
        -- reaper.ShowConsoleMsg("配置文件加载失败: " .. (err or "未知错误") .. "\n")
        -- reaper.ShowConsoleMsg("使用默认配置\n")
        return M.get_default()
    end
    
    -- 验证配置
    local is_valid, error_msg = M.validate(config)
    if not is_valid then
        -- reaper.ShowConsoleMsg("配置文件验证失败: " .. error_msg .. "\n")
        -- reaper.ShowConsoleMsg("使用默认配置\n")
        return M.get_default()
    end
    
    -- 合并默认值（确保所有字段都存在）
    config = M.merge_with_defaults(config)
    
    -- reaper.ShowConsoleMsg("配置文件加载成功\n")
    return config
end

-- ============================================================================
-- 配置保存
-- ============================================================================

-- 将配置保存到 config.json
function M.save(config)
    local config_path = M.get_config_path()
    
    -- 验证配置
    local is_valid, error_msg = M.validate(config)
    if not is_valid then
        reaper.ShowMessageBox("配置验证失败: " .. error_msg, "错误", 0)
        return false
    end
    
    -- 保存到文件（带缩进格式化）
    local success, err = json.save_to_file(config, config_path, true)
    
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
            -- [FIX] Allow "empty" type
            if not slot.type or (slot.type ~= "action" and slot.type ~= "fx" and slot.type ~= "script" and slot.type ~= "empty") then
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

return M
