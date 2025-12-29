-- @description Lee Radial Menu Tool
-- @version 1.1.14
-- @author Lee
-- @changelog
--   + Implemented safe DPI fix: hybrid positioning system with real-time calibration
--   + Added target_screen_pos as absolute anchor point while maintaining target_gui_pos compatibility
--   + Fixed window position drift on high-DPI screens and multi-monitor setups
--   + Enhanced positioning stability: window position automatically adapts to DPI changes
-- @about
--   Powerful customizable radial menu tool for REAPER
--   
--   Performance Optimizations:
--   - ListClipper for high-performance list rendering (Actions & FX browsers)
--   - ValidatePtr validation to avoid frequent ListClipper recreation
--   - Preview area caching mechanism with signature-based invalidation
--   - Text line caching for wheel rendering
--   - Pre-bake system for submenu layout (zero-cost rendering after first frame)
-- @provides
--   [main] .
--   [main] Lee_RadialMenu_Setup.lua
--   config.example.json
--   src/**/*.lua
--   utils/**/*.lua

-- ============================================================================
-- 配置初始化：从示例文件创建配置文件（如果不存在）
-- ============================================================================

do
    -- 获取脚本所在目录
    local script_path = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or ""
    
    local config_path = script_path .. "config.json"
    local example_path = script_path .. "config.example.json"
    
    -- 检查 config.json 是否存在
    local config_file = io.open(config_path, "r")
    if not config_file then
        -- config.json 不存在，尝试从示例文件复制
        local example_file = io.open(example_path, "r")
        if example_file then
            -- 读取示例文件内容
            local content = example_file:read("*all")
            example_file:close()
            
            -- 写入 config.json
            local new_config_file = io.open(config_path, "w")
            if new_config_file then
                new_config_file:write(content)
                new_config_file:close()
            end
        end
    else
        config_file:close()
    end
end

-- ============================================================================
-- 版本信息
-- ============================================================================

-- ============================================================================
-- Version Information (Update BUILD_NUMBER after each modification)
-- ============================================================================
local VERSION = "1.1.14"
local BUILD_DATE = "2025-01-21"  -- Update this date after each modification
local BUILD_NUMBER = "014"  -- Increment this number after each modification (001, 002, 003...)

-- ============================================================================
-- Development Log
-- ============================================================================
-- v1.1.10 (2025-01-20):
--   - Fixed window position stability: window stays at initial invocation point when switching modes
--   - Added reposition freeze protection (0.1s) to prevent submenu flicker during transitions
--   - Improved preset creation: blank presets now start with 2 sectors (minimum)
--   - Extended right-click detection to entire inner circle area
--   - Removed redundant coordinate capture on mode switches

-- ============================================================================
-- Phase 1 - 依赖检查
-- ============================================================================

-- 检查 ReaImGui 是否已安装
function check_dependencies()
    -- 检查 ReaImGui 是否可用
    if not reaper.ImGui_CreateContext then
        reaper.ShowMessageBox(
            "错误: 需要安装 ReaImGui 扩展！\n\n" ..
            "请通过以下步骤安装:\n" ..
            "1. 打开 Extensions > ReaPack > Browse Packages\n" ..
            "2. 搜索 'ReaImGui'\n" ..
            "3. 右键点击 'ReaImGui: ReaScript binding for Dear ImGui'\n" ..
            "4. 选择 'Install'\n" ..
            "5. 重启 REAPER",
            "缺少依赖", 0
        )
        return false
    end
    
    -- 检查 REAPER 版本（可选）
    local reaper_version = tonumber(reaper.GetAppVersion():match("^(%d+%.%d+)"))
    if reaper_version and reaper_version < 6.0 then
        reaper.ShowMessageBox(
            "警告: 建议使用 REAPER 6.0 或更高版本\n" ..
            "当前版本: " .. reaper.GetAppVersion(),
            "版本警告", 0
        )
    end
    
    return true
end

-- ============================================================================
-- Phase 1 - 路径设置
-- ============================================================================

-- 设置模块搜索路径
function setup_paths()
    -- 获取脚本所在目录
    local script_path = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or ""
    
    -- 添加模块搜索路径
    package.path = package.path .. ";" .. script_path .. "?.lua"
    package.path = package.path .. ";" .. script_path .. "src/?.lua"
    package.path = package.path .. ";" .. script_path .. "src/gui/?.lua"
    package.path = package.path .. ";" .. script_path .. "src/logic/?.lua"
    package.path = package.path .. ";" .. script_path .. "utils/?.lua"
end

-- ============================================================================
-- Phase 1 - 加载主模块
-- ============================================================================

-- 主入口函数
function main()
    -- 检查依赖
    if not check_dependencies() then
        return
    end
    
    -- 设置路径
    setup_paths()
    
    -- 加载配置管理器
    local success, config_manager = pcall(require, "config_manager")
    if not success then
        local error_msg = "错误: 无法加载配置管理器\n" .. tostring(config_manager)
        reaper.ShowMessageBox(error_msg, "加载错误", 0)
        return
    end
    
    -- 加载配置
    local config = config_manager.load()
    if not config then
        local error_msg = "错误: 无法加载配置文件"
        reaper.ShowMessageBox(error_msg, "配置错误", 0)
        return
    end
    
    -- 加载主运行时
    local success_runtime, main_runtime = pcall(require, "main_runtime")
    if not success_runtime then
        local error_msg = "错误: 无法加载主运行时\n" .. tostring(main_runtime)
        reaper.ShowMessageBox(error_msg, "加载错误", 0)
        return
    end
    
    -- 启动主运行时
    main_runtime.run()
end

-- ============================================================================
-- 执行入口
-- ============================================================================

-- 使用 pcall 捕获所有错误
local success, error_msg = pcall(main)

if not success then
    local error_display = "RadialMenu Tool 启动失败:\n\n" .. tostring(error_msg)
    reaper.ShowMessageBox(error_display, "错误", 0)
end
