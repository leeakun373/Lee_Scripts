-- @description RadialMenu Tool - 资源浏览器模块
-- @author Lee
-- @about
--   资源浏览器：Action 和 FX 浏览器，支持拖放

local M = {}

-- ============================================================================
-- 模块依赖
-- ============================================================================

local utils_fx = require("utils_fx")

-- ============================================================================
-- 模块状态变量
-- ============================================================================

local actions_cache = nil  -- Action 列表缓存
local actions_by_id = {}  -- [PERF] Action ID -> Name 映射表，用于 O(1) 查找
local actions_filtered = {}  -- 过滤后的 Action 列表
local action_search_text = ""  -- Action 搜索文本
local browser_tab = 0  -- 浏览器标签页 (0=Actions, 1=FX)
local fx_search_text = ""  -- FX 搜索文本
local current_fx_filter = "All"  -- 当前 FX 过滤器 (All, VST, VST3, JS, AU, CLAP, LV2, Chain, Template)
local action_list_clipper = nil  -- ListClipper 缓存（使用 ValidatePtr 验证有效性）
local fx_list_clipper = nil  -- FX ListClipper 缓存
local selected_browser_action = nil  -- 浏览器中选中的 Action（用于运行功能）

-- ============================================================================
-- Action 加载和过滤
-- ============================================================================

-- 加载 Actions 列表
function M.load_actions()
    if actions_cache then
        return actions_cache
    end
    
    actions_cache = {}
    local i = 0
    
    -- 使用 CF_EnumerateActions 枚举所有 Actions
    while true do
        local command_id, name = reaper.CF_EnumerateActions(0, i, '')
        if not command_id or command_id <= 0 then
            break
        end
        table.insert(actions_cache, {
            command_id = command_id,
            name = name or ""
        })
        i = i + 1
    end
    
    -- 按名称排序
    table.sort(actions_cache, function(a, b)
        return (a.name or "") < (b.name or "")
    end)
    
    -- [PERF] 构建 ID -> Name 映射表，用于 O(1) 查找
    actions_by_id = {}
    for _, action in ipairs(actions_cache) do
        if action.command_id then
            actions_by_id[action.command_id] = action.name or "Unknown Action"
        end
    end
    
    return actions_cache
end

-- 过滤 Actions
-- @param search_text string: 搜索文本
-- @return table: 过滤后的 Action 列表
function M.filter_actions(search_text)
    if not actions_cache then
        M.load_actions()
    end
    
    if not search_text or search_text == "" then
        return actions_cache
    end
    
    local filtered = {}
    
    -- Split search text into tokens (by space)
    local tokens = {}
    for token in string.gmatch(string.lower(search_text), "%S+") do
        table.insert(tokens, token)
    end
    
    for _, action in ipairs(actions_cache) do
        local name_lower = string.lower(action.name or "")
        local id_str = tostring(action.command_id)
        
        local match_all = true
        for _, token in ipairs(tokens) do
            -- Check if token exists in Name OR Command ID
            local found_in_name = string.find(name_lower, token, 1, true)
            local found_in_id = string.find(id_str, token, 1, true)
            
            if not (found_in_name or found_in_id) then
                match_all = false
                break
            end
        end
        
        if match_all then
            table.insert(filtered, action)
        end
    end
    
    return filtered
end

-- ============================================================================
-- 绘制函数
-- ============================================================================

-- 绘制资源浏览器（简化版：固定头部，防止搜索栏滚动）
-- @param ctx ImGui context
-- @param sector table: 当前扇区
-- @param state table: 状态对象（包含 selected_slot_index, is_modified 等）
function M.draw(ctx, sector, state)
    -- 标签栏（直接绘制在父窗口中，不滚动）
    if reaper.ImGui_BeginTabBar(ctx, "##ResourceTabs", reaper.ImGui_TabBarFlags_None()) then
        -- Actions 标签页
        if reaper.ImGui_BeginTabItem(ctx, "Actions") then
            browser_tab = 0
            reaper.ImGui_EndTabItem(ctx)
        end
        
        -- FX 标签页
        if reaper.ImGui_BeginTabItem(ctx, "FX") then
            browser_tab = 1
            reaper.ImGui_EndTabItem(ctx)
        end
        
        reaper.ImGui_EndTabBar(ctx)
    end
    
    -- 绘制标签页内容（搜索栏和列表在各自的函数中处理）
    if browser_tab == 0 then
        -- Actions 标签页内容
        M.draw_action_browser(ctx, sector, state)
    else
        -- FX 标签页内容
        M.draw_fx_browser(ctx, sector, state)
    end
end

-- 绘制 Action 浏览器（高性能，使用 ListClipper，固定头部）
-- @param ctx ImGui context
-- @param sector table: 当前扇区
-- @param state table: 状态对象
function M.draw_action_browser(ctx, sector, state)
    -- Toolbar Row: [Native List] [Run] [Search Bar]
    
    -- 1. Open Native List Button (Icon style or small text)
    if reaper.ImGui_Button(ctx, "列表", 0, 0) then
        reaper.Main_OnCommand(40605, 0) -- Show action list
    end
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "打开 Reaper 原生 Action List")
    end
    
    reaper.ImGui_SameLine(ctx, 0, 4)
    
    -- 2. Run Button (Green)
    local can_run = selected_browser_action ~= nil
    if not can_run then reaper.ImGui_BeginDisabled(ctx) end
    
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x2E7D32FF)
    if reaper.ImGui_Button(ctx, "运行", 0, 0) then
        if selected_browser_action then
            local execution = require("execution")
            -- Create a temp slot object to reuse execution logic
            local temp_slot = { type = "action", data = { command_id = selected_browser_action.command_id } }
            execution.trigger_slot(temp_slot)
        end
    end
    reaper.ImGui_PopStyleColor(ctx)
    
    if not can_run then reaper.ImGui_EndDisabled(ctx) end
    if reaper.ImGui_IsItemHovered(ctx) and can_run then
        reaper.ImGui_SetTooltip(ctx, "运行选中的 Action: " .. tostring(selected_browser_action.command_id))
    end

    reaper.ImGui_SameLine(ctx, 0, 4)

    -- 3. Search Bar (Fill remaining width)
    reaper.ImGui_SetNextItemWidth(ctx, -1)
    local search_changed, new_search = reaper.ImGui_InputText(ctx, "##ActionSearch", action_search_text, 256)
    if search_changed then
        action_search_text = new_search
        -- 重新过滤
        actions_filtered = M.filter_actions(action_search_text)
        -- 如果选中的 action 不在过滤结果中，清除选择
        if selected_browser_action then
            local still_in_list = false
            for _, action in ipairs(actions_filtered) do
                if action.command_id == selected_browser_action.command_id then
                    still_in_list = true
                    break
                end
            end
            if not still_in_list then
                selected_browser_action = nil
            end
        end
    elseif #actions_filtered == 0 then
        -- 初始化过滤列表
        actions_filtered = M.filter_actions(action_search_text)
    end
    
    -- 列表区域（可滚动）
    local avail_w, avail_h = reaper.ImGui_GetContentRegionAvail(ctx)
    if reaper.ImGui_BeginChild(ctx, "ActionList", 0, 0, 1, reaper.ImGui_WindowFlags_None()) then
        -- 使用 ListClipper 进行高性能渲染
        -- 使用 ValidatePtr 验证 ListClipper 是否有效，避免频繁创建
        if not reaper.ImGui_ValidatePtr(action_list_clipper, 'ImGui_ListClipper*') then
            action_list_clipper = reaper.ImGui_CreateListClipper(ctx)
        end
        
        if action_list_clipper then
            reaper.ImGui_ListClipper_Begin(action_list_clipper, #actions_filtered)
            while reaper.ImGui_ListClipper_Step(action_list_clipper) do
                local display_start, display_end = reaper.ImGui_ListClipper_GetDisplayRange(action_list_clipper)
                
                for i = display_start, display_end - 1 do
                    if i + 1 <= #actions_filtered then
                        local action = actions_filtered[i + 1]
                        local item_label = string.format("%d: %s", action.command_id, action.name or "")
                        
                        -- Handle Selection
                        local is_selected = (selected_browser_action and selected_browser_action.command_id == action.command_id)
                        if reaper.ImGui_Selectable(ctx, item_label, is_selected, reaper.ImGui_SelectableFlags_AllowDoubleClick(), 0, 0) then
                            selected_browser_action = action
                            
                            -- Support Double Click to Run
                            if reaper.ImGui_IsMouseDoubleClicked(ctx, 0) then
                                local execution = require("execution")
                                local temp_slot = { type = "action", data = { command_id = action.command_id } }
                                execution.trigger_slot(temp_slot)
                            end
                        end
                        
                        -- 然后在 Selectable 之后设置为拖放源
                        if reaper.ImGui_BeginDragDropSource(ctx, reaper.ImGui_DragDropFlags_None()) then
                            local payload_data = string.format("%d|%s", action.command_id, action.name or "")
                            reaper.ImGui_SetDragDropPayload(ctx, "DND_ACTION", payload_data)
                            reaper.ImGui_Text(ctx, item_label)
                            reaper.ImGui_EndDragDropSource(ctx)
                        end
                    end
                end
            end
            reaper.ImGui_ListClipper_End(action_list_clipper)
        end
        
        reaper.ImGui_EndChild(ctx)
    end
end

-- 绘制 FX 浏览器（分类版本，固定头部）
-- @param ctx ImGui context
-- @param sector table: 当前扇区
-- @param state table: 状态对象
function M.draw_fx_browser(ctx, sector, state)
    -- 定义过滤器按钮
    local filters = {"All", "VST", "VST3", "JS", "AU", "CLAP", "LV2", "Chain", "Template"}
    
    -- 绘制过滤器按钮（水平排列，在 Child 外面）
    for _, filter in ipairs(filters) do
        local is_selected = (current_fx_filter == filter)
        if is_selected then
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x3F3F46FF)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x4F4F56FF)
        end
        
        if reaper.ImGui_Button(ctx, filter, 0, 0) then
            current_fx_filter = filter
        end
        
        if is_selected then
            reaper.ImGui_PopStyleColor(ctx, 2)
        end
        
        reaper.ImGui_SameLine(ctx, 0, 4)
    end
    
    -- 搜索框（紧跟在过滤器按钮后，同一行）
    local avail_w = reaper.ImGui_GetContentRegionAvail(ctx)
    local search_w = math.max(150, avail_w - 8)  -- 至少 150 像素宽
    reaper.ImGui_SetNextItemWidth(ctx, search_w)
    local search_changed, new_search = reaper.ImGui_InputText(ctx, "##FXSearch", fx_search_text, 256)
    if search_changed then
        fx_search_text = new_search
    end
    
    -- 准备显示列表（根据过滤器）
    local display_list = {}
    
    if current_fx_filter == "Template" then
        display_list = utils_fx.get_track_templates()
    elseif current_fx_filter == "Chain" then
        display_list = utils_fx.get_fx_chains()
    else
        -- 标准 FX，按类型过滤
        local all_fx = utils_fx.get_all_fx()
        for _, fx in ipairs(all_fx) do
            if current_fx_filter == "All" or fx.type == current_fx_filter then
                table.insert(display_list, fx)
            end
        end
    end
    
    -- 应用搜索过滤
    if fx_search_text and fx_search_text ~= "" then
        local filtered = {}
        local lower_search = string.lower(fx_search_text)
        for _, item in ipairs(display_list) do
            local name = item.name or ""
            if string.find(string.lower(name), lower_search, 1, true) then
                table.insert(filtered, item)
            end
        end
        display_list = filtered
    end
    
    -- 列表区域（可滚动）
    if reaper.ImGui_BeginChild(ctx, "FXList", 0, 0, 1, reaper.ImGui_WindowFlags_None()) then
        -- 使用 ListClipper 进行高性能渲染
        if not reaper.ImGui_ValidatePtr(fx_list_clipper, 'ImGui_ListClipper*') then
            fx_list_clipper = reaper.ImGui_CreateListClipper(ctx)
        end
        
        if fx_list_clipper then
            reaper.ImGui_ListClipper_Begin(fx_list_clipper, #display_list)
            while reaper.ImGui_ListClipper_Step(fx_list_clipper) do
                local display_start, display_end = reaper.ImGui_ListClipper_GetDisplayRange(fx_list_clipper)
                
                for i = display_start, display_end - 1 do
                    if i + 1 <= #display_list then
                        local item = display_list[i + 1]
                        local item_label = item.name or "未命名"
                        
                        -- 添加类型标签（如果有）
                        if item.type and item.type ~= "Other" then
                            item_label = string.format("[%s] %s", item.type, item_label)
                        end
                        
                        -- 渲染 Selectable
                        if reaper.ImGui_Selectable(ctx, item_label, false, reaper.ImGui_SelectableFlags_None(), 0, 0) then
                            -- 点击选择（可选功能）
                        end
                        
                        -- 设置为拖放源
                        if reaper.ImGui_BeginDragDropSource(ctx, reaper.ImGui_DragDropFlags_None()) then
                            -- 根据类型设置不同的 payload
                            local payload_type = "fx"
                            local payload_id = item.original_name or item.name
                            
                            if current_fx_filter == "Chain" or item.type == "Chain" then
                                payload_type = "chain"
                                payload_id = item.path or item.name
                            elseif current_fx_filter == "Template" or item.type == "TrackTemplate" then
                                payload_type = "template"
                                payload_id = item.path or item.name
                            end
                            
                            -- Payload 格式: "type|id"
                            local payload_data = string.format("%s|%s", payload_type, payload_id)
                            reaper.ImGui_SetDragDropPayload(ctx, "DND_FX", payload_data)
                            reaper.ImGui_Text(ctx, item_label)
                            reaper.ImGui_EndDragDropSource(ctx)
                        end
                    end
                end
            end
            reaper.ImGui_ListClipper_End(fx_list_clipper)
        end
        
        -- 如果列表为空，显示提示
        if #display_list == 0 then
            reaper.ImGui_TextDisabled(ctx, string.format("未找到匹配的 %s", current_fx_filter))
        end
        
        reaper.ImGui_EndChild(ctx)
    end
end

-- 获取 Actions 缓存（供其他模块使用）
function M.get_actions_cache()
    if not actions_cache then
        M.load_actions()
    end
    return actions_cache
end

-- [PERF] 根据 command_id 获取 Action 名称（O(1) 查找）
function M.get_action_name_by_id(command_id)
    if not command_id then
        return "Unknown Action"
    end
    -- 如果 map 为空，确保先加载 actions
    if next(actions_by_id) == nil then
        M.load_actions()
    end
    return actions_by_id[command_id] or "Unknown Action"
end

return M
