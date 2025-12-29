-- @description RadialMenu Tool - 动作执行模块
-- @author Lee
-- @about
--   执行 Reaper 内置命令和脚本
--   提供统一的动作执行接口

local M = {}

-- 命令历史（最多保留 20 条）
local command_history = {}
local max_history = 20

-- ============================================================================
-- Phase 3 - 执行 Reaper 命令
-- ============================================================================

-- 执行 Reaper 内置命令
function M.execute_command(command_id)
    -- 验证 command_id
    if not command_id then
        return false
    end
    
    -- 转换为数字
    local cmd_id = tonumber(command_id)
    if not cmd_id then
        return false
    end
    
    if cmd_id <= 0 then
        return false
    end
    
    -- 执行命令（直接执行，不使用 defer）
    reaper.Main_OnCommand(cmd_id, 0)
    
    -- 记录日志
    M.log_execution(cmd_id, true, nil)
    
    -- 添加到历史
    M.add_to_history(cmd_id, true)
    
    return true
end

-- ============================================================================
-- Phase 3 - 执行命名命令
-- ============================================================================

-- 通过命令名称执行命令
function M.execute_named_command(command_name)
    if not command_name or command_name == "" then
        -- reaper.ShowConsoleMsg("错误: command_name 为空\n")
        return false
    end
    
    -- 查找命令 ID
    local command_id = reaper.NamedCommandLookup(command_name)
    
    if not command_id or command_id == 0 then
        -- reaper.ShowConsoleMsg("错误: 找不到命令: " .. command_name .. "\n")
        return false
    end
    
    -- 执行命令
    return M.execute_command(command_id)
end

-- ============================================================================
-- Phase 3 - 执行脚本
-- ============================================================================

-- 执行外部 Lua 脚本
function M.execute_script(script_path)
    -- 验证路径
    if not script_path or script_path == "" then
        -- reaper.ShowConsoleMsg("错误: script_path 为空\n")
        return false, "脚本路径为空"
    end
    
    -- 检查文件是否存在
    local file = io.open(script_path, "r")
    if not file then
        local error_msg = "脚本文件不存在: " .. script_path
        -- reaper.ShowConsoleMsg("错误: " .. error_msg .. "\n")
        return false, error_msg
    end
    file:close()
    
    -- 使用 pcall 安全执行脚本
    local success, error_msg = pcall(dofile, script_path)
    
    if not success then
        local msg = "脚本执行失败: " .. tostring(error_msg)
        -- reaper.ShowConsoleMsg("错误: " .. msg .. "\n")
        M.log_execution(script_path, false, error_msg)
        return false, msg
    end
    
    -- 记录日志
    M.log_execution(script_path, true, nil)
    -- reaper.ShowConsoleMsg("✓ 脚本执行成功: " .. script_path .. "\n")
    
    return true, nil
end

-- ============================================================================
-- Phase 3 - 命令历史
-- ============================================================================

-- 添加到历史记录
function M.add_to_history(command_id, success)
    local entry = {
        command_id = command_id,
        timestamp = os.time(),
        success = success
    }
    
    table.insert(command_history, 1, entry)
    
    -- 限制历史记录数量
    if #command_history > max_history then
        table.remove(command_history, #command_history)
    end
end

-- 获取命令历史
function M.get_command_history()
    return command_history
end

-- 清空历史记录
function M.clear_history()
    command_history = {}
end

-- ============================================================================
-- Phase 3 - 命令验证
-- ============================================================================

-- 检查命令是否可用
function M.is_command_available(command_id)
    if not command_id then
        return false
    end
    
    local cmd_id = tonumber(command_id)
    if not cmd_id then
        return false
    end
    
    -- 简单验证：检查是否为有效的数字
    return cmd_id > 0
end

-- ============================================================================
-- Phase 3 - 辅助函数
-- ============================================================================

-- 记录命令执行日志
function M.log_execution(command_id, success, error_msg)
    local status = success and "✓" or "✗"
    local id_str = tostring(command_id)
    
    if success then
        -- reaper.ShowConsoleMsg(string.format("%s 执行命令: %s\n", status, id_str))
    else
        -- reaper.ShowConsoleMsg(string.format("%s 执行失败: %s", status, id_str))
        if error_msg then
            -- reaper.ShowConsoleMsg(" (" .. error_msg .. ")")
        end
        -- reaper.ShowConsoleMsg("\n")
    end
end

-- 获取最近执行的命令
function M.get_recent_commands(count)
    count = count or 5
    local recent = {}
    
    for i = 1, math.min(count, #command_history) do
        table.insert(recent, command_history[i])
    end
    
    return recent
end

return M
