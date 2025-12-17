-- @description RadialMenu Tool - 预设管理模块
-- @author Lee
-- @about
--   预设管理：预设切换、保存、删除和新建

local M = {}

-- ============================================================================
-- 模块依赖
-- ============================================================================

local config_manager = require("config_manager")
local im_utils = require("im_utils")

-- ============================================================================
-- 模块状态变量
-- ============================================================================

local show_new_preset_modal = false  -- 是否显示新建预设弹窗
local new_preset_name_buf = ""  -- 新建预设名称输入缓冲区

-- ============================================================================
-- 绘制函数
-- ============================================================================

-- 绘制预设管理 UI（操作栏中的预设部分）
-- @param ctx ImGui context
-- @param config table: 配置对象
-- @param state table: 状态对象（包含 current_preset_name, is_modified, save_feedback_time 等）
-- @param callbacks table: 回调函数（switch_preset, save_current_preset, delete_current_preset, save_config）
function M.draw(ctx, config, state, callbacks)
    -- 预设管理区域
    reaper.ImGui_SameLine(ctx, 0, 30)  -- 增加间距，移除分隔线
    
    -- 预设标签
    reaper.ImGui_Text(ctx, "预设:")
    reaper.ImGui_SameLine(ctx, 0, 4)
    
    -- 下拉菜单：选择预设（固定宽度）
    local preset_list = config_manager.get_preset_list()
    local current_preset_display = state.current_preset_name or "Default"
    if state.is_modified then
        current_preset_display = current_preset_display .. " *"
    end
    
    -- 固定下拉菜单宽度为 150px
    reaper.ImGui_SetNextItemWidth(ctx, 150)
    if reaper.ImGui_BeginCombo(ctx, "##PresetCombo", current_preset_display, reaper.ImGui_ComboFlags_None()) then
        for _, preset_name in ipairs(preset_list) do
            local is_selected = (preset_name == state.current_preset_name)
            if reaper.ImGui_Selectable(ctx, preset_name, is_selected, reaper.ImGui_SelectableFlags_None(), 0, 0) then
                if preset_name ~= state.current_preset_name then
                    -- 切换预设
                    if callbacks and callbacks.switch_preset then
                        callbacks.switch_preset(preset_name)
                    end
                end
            end
            if is_selected then
                reaper.ImGui_SetItemDefaultFocus(ctx)
            end
        end
        reaper.ImGui_EndCombo(ctx)
    end
    
    reaper.ImGui_SameLine(ctx, 0, 4)
    
    -- [+] 新建预设按钮
    if reaper.ImGui_Button(ctx, "+", 0, 0) then
        new_preset_name_buf = ""
        show_new_preset_modal = true
        reaper.ImGui_OpenPopup(ctx, "新建预设")
    end
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_BeginTooltip(ctx)
        reaper.ImGui_Text(ctx, "创建新预设")
        reaper.ImGui_EndTooltip(ctx)
    end
    
    reaper.ImGui_SameLine(ctx, 0, 4)
    
    -- [Save] 保存当前预设按钮
    local can_save_preset = (state.current_preset_name ~= nil and state.current_preset_name ~= "")
    if not can_save_preset then
        reaper.ImGui_BeginDisabled(ctx)
    end
    if reaper.ImGui_Button(ctx, "保存预设", 0, 0) then
        if callbacks and callbacks.save_current_preset then
            callbacks.save_current_preset()
        end
    end
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_BeginTooltip(ctx)
        reaper.ImGui_Text(ctx, "更新当前预设")
        reaper.ImGui_EndTooltip(ctx)
    end
    if not can_save_preset then
        reaper.ImGui_EndDisabled(ctx)
    end
    
    reaper.ImGui_SameLine(ctx, 0, 4)
    
    -- [Trash] 删除预设按钮（Default 预设时禁用）
    local can_delete = (state.current_preset_name ~= "Default" and state.current_preset_name ~= nil and state.current_preset_name ~= "")
    if not can_delete then
        reaper.ImGui_BeginDisabled(ctx)
    end
    if reaper.ImGui_Button(ctx, "删除", 0, 0) then
        if callbacks and callbacks.delete_current_preset then
            callbacks.delete_current_preset()
        end
    end
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_BeginTooltip(ctx)
        reaper.ImGui_Text(ctx, "删除预设")
        reaper.ImGui_EndTooltip(ctx)
    end
    if not can_delete then
        reaper.ImGui_EndDisabled(ctx)
    end
    
    -- 新建预设弹窗
    M.draw_new_preset_modal(ctx, config, state, callbacks)
    
    -- 状态文本（绝对定位，不影响按钮布局）
    local current_time = os.time()
    local status_text = ""
    local status_color = 0
    
    if state.save_feedback_time and (current_time - state.save_feedback_time < 2) then
        status_text = "✔ 配置已保存"
        status_color = 0x4CAF50FF  -- Green
    elseif state.is_modified then
        status_text = "* 有未保存的更改"
        status_color = 0xFFC800FF  -- Yellow
    end
    
    if status_text ~= "" then
        local text_w, text_h = reaper.ImGui_CalcTextSize(ctx, status_text)
        local win_w, win_h = reaper.ImGui_GetWindowSize(ctx)
        -- Align to right with 20px padding
        reaper.ImGui_SameLine(ctx)  -- Keep on same line technically to share height
        reaper.ImGui_SetCursorPosX(ctx, win_w - text_w - 20)
        reaper.ImGui_TextColored(ctx, status_color, status_text)
    end
end

-- 绘制新建预设弹窗
-- @param ctx ImGui context
-- @param config table: 配置对象
-- @param state table: 状态对象
-- @param callbacks table: 回调函数
function M.draw_new_preset_modal(ctx, config, state, callbacks)
    -- 设置弹窗默认大小为 320x160，足以容纳输入框和按钮
    reaper.ImGui_SetNextWindowSize(ctx, 320, 160, reaper.ImGui_Cond_Appearing())
    
    -- 显示弹窗
    if reaper.ImGui_BeginPopupModal(ctx, "新建预设", nil, reaper.ImGui_WindowFlags_None()) then
        reaper.ImGui_Text(ctx, "请输入预设名称:")
        reaper.ImGui_Spacing(ctx)
        
        -- 输入框
        reaper.ImGui_SetNextItemWidth(ctx, -1)
        local input_changed, new_text = reaper.ImGui_InputText(ctx, "##NewPresetName", new_preset_name_buf, 256)
        if input_changed then
            new_preset_name_buf = new_text
        end
        
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Spacing(ctx)  -- 增加额外的间距，确保按钮不贴边
        
        -- 按钮区域（居中，底部留有 padding）
        local button_width = 80
        local avail_w = reaper.ImGui_GetContentRegionAvail(ctx)
        local button_x = (avail_w - button_width * 2 - 8) / 2
        
        reaper.ImGui_SetCursorPosX(ctx, button_x)
        
        -- 确认按钮
        if reaper.ImGui_Button(ctx, "确认", button_width, 0) then
            local preset_name = new_preset_name_buf:match("^%s*(.-)%s*$")  -- 去除首尾空格
            
            if preset_name == "" then
                reaper.ShowMessageBox("预设名称不能为空", "错误", 0)
            else
                -- 检查名称是否已存在
                local preset_list = config_manager.get_preset_list()
                local name_exists = false
                for _, existing_name in ipairs(preset_list) do
                    if existing_name == preset_name then
                        name_exists = true
                        break
                    end
                end
                
                if name_exists then
                    reaper.ShowMessageBox("预设名称已存在，请使用其他名称", "错误", 0)
                else
                    -- 保存当前配置为新预设
                    local success, err = config_manager.save_preset(preset_name, config)
                    if success then
                        -- 切换到新预设
                        if callbacks and callbacks.switch_preset then
                            callbacks.switch_preset(preset_name)
                        end
                        -- 关闭弹窗
                        show_new_preset_modal = false
                        new_preset_name_buf = ""
                        reaper.ImGui_CloseCurrentPopup(ctx)
                    else
                        reaper.ShowMessageBox("保存预设失败: " .. (err or "未知错误"), "错误", 0)
                    end
                end
            end
        end
        
        reaper.ImGui_SameLine(ctx, 0, 8)
        
        -- 取消按钮
        if reaper.ImGui_Button(ctx, "取消", button_width, 0) then
            show_new_preset_modal = false
            new_preset_name_buf = ""
            reaper.ImGui_CloseCurrentPopup(ctx)
        end
        
        -- 如果按 ESC 键，关闭弹窗
        if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape()) then
            show_new_preset_modal = false
            new_preset_name_buf = ""
            reaper.ImGui_CloseCurrentPopup(ctx)
        end
        
        reaper.ImGui_EndPopup(ctx)
    end
    
    -- 如果 show_new_preset_modal 为 true，打开弹窗
    if show_new_preset_modal then
        reaper.ImGui_OpenPopup(ctx, "新建预设")
    end
end

return M

