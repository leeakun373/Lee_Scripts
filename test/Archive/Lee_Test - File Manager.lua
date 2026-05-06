-- 查看当前环境所有 DragDrop 相关 API
local r = reaper
r.ClearConsole()
r.ShowConsoleMsg("=== 正在扫描内存中已加载的 ReaImGui API ===\n\n")

local found_count = 0
local keys = {}

-- 收集所有函数名
for key, _ in pairs(r) do
    if key:match("ImGui_.*DragDrop") then
        table.insert(keys, key)
    end
end

-- 排序输出
table.sort(keys)
for _, key in ipairs(keys) do
    r.ShowConsoleMsg(key .. "\n")
    found_count = found_count + 1
end

r.ShowConsoleMsg("\n------------------------------------------------\n")
if found_count == 0 then
    r.ShowConsoleMsg("❌ 结果: 一个相关函数都没找到！API完全未加载。")
else
    r.ShowConsoleMsg("������ 结果: 找到了 " .. found_count .. " 个相关函数。")
end

-- 重点检查目标
if r.ImGui_SetDragDropPayloadFile then
    r.ShowConsoleMsg("\n✅ ImGui_SetDragDropPayloadFile: 存在 (可以拖拽)")
else
    r.ShowConsoleMsg("\n❌ ImGui_SetDragDropPayloadFile: 缺失 (无法拖拽)")
end
