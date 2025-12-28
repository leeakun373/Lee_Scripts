-- @description Lee Radial Menu Tool - 清除缓存脚本
-- @version 1.0.0
-- @author Lee
-- @about
--   清除子菜单缓存，用于在修改代码参数后强制重新计算布局
--   运行此脚本后，下次打开轮盘菜单时会重新烘焙所有子菜单数据

-- 设置模块搜索路径
local script_path = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or ""
package.path = package.path .. ";" .. script_path .. "?.lua"
package.path = package.path .. ";" .. script_path .. "src/?.lua"
package.path = package.path .. ";" .. script_path .. "src/gui/?.lua"

-- 清除缓存
local success, submenu_bake_cache = pcall(require, "gui.submenu_bake_cache")
if success and submenu_bake_cache then
    submenu_bake_cache.clear()
end

local success2, submenu_cache = pcall(require, "gui.submenu_cache")
if success2 and submenu_cache then
    submenu_cache.clear()
end

reaper.ShowMessageBox(
    "缓存已清除！\n\n" ..
    "下次打开轮盘菜单时会重新计算所有布局数据。\n\n" ..
    "如果修改了代码中的硬编码参数（如 padding、gap 等），\n" ..
    "需要运行此脚本清除缓存才能看到效果。",
    "缓存清除", 0
)

