--[[
  REAPER Lua Script: Search Interface Template
  Description: 类似 nvk_PROPAGATE 的图形界面框架（仅界面，无功能）
  - 使用 ReaImGui 创建搜索界面
  - 包含搜索框、标签页、结果列表等UI元素
  - 仅作为界面模板，不包含实际搜索功能
  
  Author: Lee
  Version: 1.0.0
]]

-- 检查 ReaImGui 是否可用
if not reaper.ImGui_CreateContext then
    reaper.ShowMessageBox("此脚本需要 ReaImGui 扩展。\n请从 Extensions > ReaPack > Browse packages 安装 'ReaImGui'", "缺少依赖", 0)
    return
end

local r = reaper

-- 创建 GUI 上下文
local ctx = r.ImGui_CreateContext('Search Interface Template')

-- GUI 状态变量
local gui = {
    visible = true,
    width = 650,
    height = 550,
    pin_window = false
}

-- 搜索相关变量
local search_text = ""
local search_buffer = ""
local first_frame = true

-- 标签页状态
local tabs = {
    {name = "FX", icon = "🔌"},
    {name = "Chains", icon = "🔗"}, 
    {name = "Actions", icon = "⚡"},
    {name = "Projects", icon = "📁"},
    {name = "Other", icon = "📋"}
}
local active_tab = 1

-- 模拟搜索结果（仅用于显示界面）
local search_results = {
    {name = "示例 FX 插件 1", category = "VST", desc = "这是一个示例效果器"},
    {name = "示例 FX 插件 2", category = "VST3", desc = "另一个示例效果器"},
    {name = "示例 FX 插件 3", category = "JS", desc = "JS 效果器示例"},
    {name = "示例 FX 插件 4", category = "AU", desc = "AU 效果器示例"},
    {name = "示例 FX 插件 5", category = "VST", desc = "更多示例效果器"}
}

-- 主循环
local function main_loop()
    -- 设置窗口大小
    r.ImGui_SetNextWindowSize(ctx, gui.width, gui.height, r.ImGui_Cond_FirstUseEver())
    
    -- 窗口标志
    local window_flags = 0
    if gui.pin_window then
        window_flags = r.ImGui_WindowFlags_TopMost()
    end
    
    -- 开始窗口
    local visible, open = r.ImGui_Begin(ctx, 'Search Interface Template', true, window_flags)
    
    if visible then
        -- 标题栏按钮区域
        r.ImGui_BeginGroup(ctx)
        
        -- 标题
        r.ImGui_Text(ctx, "🔍 Search Interface")
        r.ImGui_SameLine(ctx)
        
        -- 固定窗口按钮
        local pin_color = gui.pin_window and 0x00FF00FF or 0x808080FF
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), pin_color)
        if r.ImGui_Button(ctx, "📌", 25, 20) then
            gui.pin_window = not gui.pin_window
        end
        r.ImGui_PopStyleColor(ctx)
        
        r.ImGui_EndGroup(ctx)
        
        r.ImGui_Separator(ctx)
        r.ImGui_Spacing(ctx)
        
        -- 搜索输入框区域
        r.ImGui_BeginGroup(ctx)
        
        -- 首次显示时聚焦到搜索框
        if first_frame then
            r.ImGui_SetKeyboardFocusHere(ctx)
            first_frame = false
        end
        
        -- 搜索输入框（带提示文本）
        local search_width = r.ImGui_GetContentRegionAvail(ctx) - 70
        r.ImGui_SetNextItemWidth(ctx, search_width)
        local retval, buf = r.ImGui_InputTextWithHint(ctx, "##search", "输入搜索关键词...", search_buffer, 
                                                      r.ImGui_InputTextFlags_AutoSelectAll())
        if retval then
            search_buffer = buf
            search_text = buf
        end
        
        -- 清除按钮
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "✕", 25, 0) then
            search_buffer = ""
            search_text = ""
            r.ImGui_SetKeyboardFocusHere(ctx)
        end
        
        -- 刷新按钮
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "↻", 25, 0) then
            -- 这里可以添加刷新逻辑
        end
        
        r.ImGui_EndGroup(ctx)
        
        r.ImGui_Spacing(ctx)
        r.ImGui_Separator(ctx)
        r.ImGui_Spacing(ctx)
        
        -- 标签页
        if r.ImGui_BeginTabBar(ctx, "##tabs", r.ImGui_TabBarFlags_None()) then
            for i, tab in ipairs(tabs) do
                local tab_label = string.format("%s %s", tab.icon, tab.name)
                local tab_flags = 0
                
                if r.ImGui_BeginTabItem(ctx, tab_label, nil, tab_flags) then
                    active_tab = i
                    r.ImGui_EndTabItem(ctx)
                end
            end
            r.ImGui_EndTabBar(ctx)
        end
        
        r.ImGui_Spacing(ctx)
        r.ImGui_Separator(ctx)
        r.ImGui_Spacing(ctx)
        
        -- 结果显示区域
        local current_tab = tabs[active_tab]
        r.ImGui_Text(ctx, string.format("当前: %s %s", current_tab.icon, current_tab.name))
        r.ImGui_Spacing(ctx)
        
        -- 创建子窗口用于显示结果列表
        local child_height = r.ImGui_GetContentRegionAvail(ctx) - 70
        if r.ImGui_BeginChild(ctx, "##results", 0, child_height, true) then
            if search_text == "" or search_text == nil then
                r.ImGui_TextColored(ctx, 0x808080FF, "💡 输入搜索关键词以显示结果...")
                r.ImGui_Spacing(ctx)
                r.ImGui_TextColored(ctx, 0x606060FF, "提示: 支持模糊搜索和关键词匹配")
            else
                -- 显示搜索结果
                if #search_results > 0 then
                    for i, result in ipairs(search_results) do
                        -- 结果项（可点击）
                        local result_text = string.format("%s [%s]", result.name, result.category)
                        local is_selected = false
                        
                        if r.ImGui_Selectable(ctx, result_text, is_selected, 0, 0, 0) then
                            -- 这里可以添加点击结果的处理逻辑
                            r.ShowMessageBox(string.format("选择了: %s\n%s", result.name, result.desc), "提示", 0)
                        end
                        
                        -- 鼠标悬停时显示描述
                        if r.ImGui_IsItemHovered(ctx) then
                            r.ImGui_BeginTooltip(ctx)
                            r.ImGui_Text(ctx, result.name)
                            r.ImGui_Separator(ctx)
                            r.ImGui_Text(ctx, string.format("类别: %s", result.category))
                            r.ImGui_Text(ctx, string.format("描述: %s", result.desc))
                            r.ImGui_EndTooltip(ctx)
                        end
                    end
                else
                    r.ImGui_TextColored(ctx, 0xFF8080FF, "❌ 未找到匹配的结果")
                end
            end
            r.ImGui_EndChild(ctx)
        end
        
        r.ImGui_Spacing(ctx)
        r.ImGui_Separator(ctx)
        
        -- 底部按钮区域
        r.ImGui_BeginGroup(ctx)
        
        -- 应用按钮（带颜色）
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x00AA00FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x00CC00FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x008800FF)
        if r.ImGui_Button(ctx, "✓ Apply", 110, 30) then
            r.ShowMessageBox("Apply 按钮被点击", "提示", 0)
        end
        r.ImGui_PopStyleColor(ctx, 3)
        
        r.ImGui_SameLine(ctx)
        
        -- 取消按钮
        if r.ImGui_Button(ctx, "✕ Cancel", 110, 30) then
            gui.visible = false
        end
        
        r.ImGui_SameLine(ctx)
        
        -- 设置按钮
        if r.ImGui_Button(ctx, "⚙ Settings", 110, 30) then
            r.ShowMessageBox("Settings 按钮被点击", "提示", 0)
        end
        
        r.ImGui_EndGroup(ctx)
        
        -- 状态栏
        r.ImGui_Separator(ctx)
        local result_count = (search_text == "" or search_text == nil) and 0 or #search_results
        local status_text = string.format("状态: 就绪 | 结果: %d | 标签: %s %s", 
                                         result_count, current_tab.icon, current_tab.name)
        r.ImGui_TextColored(ctx, 0x808080FF, status_text)
        
        r.ImGui_End(ctx)
    end
    
    -- 继续循环
    if open and gui.visible then
        r.defer(main_loop)
    else
        return
    end
end

-- 启动 GUI
main_loop()

