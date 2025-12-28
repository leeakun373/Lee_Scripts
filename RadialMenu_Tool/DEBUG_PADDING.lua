-- @description 调试 Padding 参数
-- @about
--   临时调试脚本：检查 padding 参数是否被正确使用

local script_path = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or ""
package.path = package.path .. ";" .. script_path .. "?.lua"
package.path = package.path .. ";" .. script_path .. "src/?.lua"
package.path = package.path .. ";" .. script_path .. "src/gui/?.lua"

-- 读取 list_view.lua 中的 padding 值
local list_view_path = script_path .. "src/gui/list_view.lua"
local file = io.open(list_view_path, "r")
if file then
    local content = file:read("*all")
    file:close()
    
    local padding_match = content:match("DEFAULT_WINDOW_PADDING%s*=%s*(%d+)")
    if padding_match then
        reaper.ShowConsoleMsg("list_view.lua 中的 padding = " .. padding_match .. "\n")
    else
        reaper.ShowConsoleMsg("未找到 DEFAULT_WINDOW_PADDING\n")
    end
end

-- 读取 submenu_bake_cache.lua 中的 padding 值
local bake_cache_path = script_path .. "src/gui/submenu_bake_cache.lua"
local file2 = io.open(bake_cache_path, "r")
if file2 then
    local content2 = file2:read("*all")
    file2:close()
    
    -- 查找 padding = 后面的数字
    for line in content2:gmatch("[^\r\n]+") do
        if line:match("local padding%s*=%s*(%d+)") then
            local padding_val = line:match("local padding%s*=%s*(%d+)")
            reaper.ShowConsoleMsg("submenu_bake_cache.lua 中的 padding = " .. padding_val .. "\n")
            break
        end
    end
end

-- 清除缓存
local success, submenu_bake_cache = pcall(require, "gui.submenu_bake_cache")
if success and submenu_bake_cache then
    submenu_bake_cache.clear()
    reaper.ShowConsoleMsg("已清除烘焙缓存\n")
end

local success2, submenu_cache = pcall(require, "gui.submenu_cache")
if success2 and submenu_cache then
    submenu_cache.clear()
    reaper.ShowConsoleMsg("已清除普通缓存\n")
end

reaper.ShowConsoleMsg("\n请重新打开轮盘菜单查看效果\n")

