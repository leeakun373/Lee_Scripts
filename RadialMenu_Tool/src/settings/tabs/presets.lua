-- @description RadialMenu Tool - 预设管理模块
-- @author Lee
-- @about
--   预设管理：预设切换、保存、删除和新建（UI 参考 1.1.5 的紧凑风格）
--
-- 目标：
-- - UI 尽量贴近 1.1.5 旧版（Combo + 小按钮），不要大幅改变页面结构
-- - 功能保持最新：Blank/Duplicate 新建、重命名、删除（Default 保护）
-- - 弹窗稳定：AlwaysAutoResize + 固定输入宽度 + Appearing 居中（防飞走/无限变宽）

local M = {}

local config_manager = require("config_manager")
local im_utils = require("im_utils")
local i18n = require("utils.i18n")

-- ============================================================================
-- Local UI state
-- ============================================================================

-- New preset modal
local show_new_preset_modal = false
local new_preset_name_buf = ""
local new_preset_mode = "blank" -- "blank" | "duplicate"
local new_preset_error = nil
local new_preset_focus_next = false

-- Rename preset modal
local show_rename_modal = false
local rename_new_name_buf = ""
local rename_error = nil
local rename_focus_next = false

-- ============================================================================
-- Helpers
-- ============================================================================

local function trim(s)
  s = tostring(s or "")
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function center_modal_on_appearing(ctx)
  local vp = reaper.ImGui_GetMainViewport(ctx)
  if vp and reaper.ImGui_Viewport_GetCenter then
    local cx, cy = reaper.ImGui_Viewport_GetCenter(vp)
    reaper.ImGui_SetNextWindowPos(ctx, cx, cy, reaper.ImGui_Cond_Appearing(), 0.5, 0.5)
  end
  reaper.ImGui_SetNextWindowSize(ctx, 0, 0, reaper.ImGui_Cond_Appearing())
end

local function preset_exists(name)
  for _, n in ipairs(config_manager.get_preset_list()) do
    if n == name then return true end
  end
  return false
end

-- ============================================================================
-- Main draw
-- ============================================================================

-- 绘制预设管理 UI（操作栏中的预设部分）
-- @param ctx ImGui context
-- @param config table: 当前编辑器内的 config（可能未保存）
-- @param state table: settings state（包含 current_preset_name, is_modified, save_feedback_time 等）
-- @param callbacks table: 回调函数（switch_preset, save_current_preset, delete_current_preset, save_config）
function M.draw(ctx, config, state, callbacks)
  -- 预设管理区域（保持旧版布局：一行）
  reaper.ImGui_SameLine(ctx, 0, 30)

  reaper.ImGui_Text(ctx, i18n.t("preset") .. ":")
  reaper.ImGui_SameLine(ctx, 0, 4)

  local preset_list = config_manager.get_preset_list()
  local current_name = state.current_preset_name or "Default"

  local combo_label = current_name
  if state.is_modified then
    combo_label = combo_label .. " *"
  end

  reaper.ImGui_SetNextItemWidth(ctx, 150)
  if reaper.ImGui_BeginCombo(ctx, "##PresetCombo", combo_label, reaper.ImGui_ComboFlags_None()) then
    for _, preset_name in ipairs(preset_list) do
      local is_selected = (preset_name == state.current_preset_name)
      if reaper.ImGui_Selectable(ctx, preset_name, is_selected, reaper.ImGui_SelectableFlags_None(), 0, 0) then
        if preset_name ~= state.current_preset_name then
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

  -- [+] 新建预设按钮（打开弹窗，弹窗内选择 Blank/Duplicate）
  -- 【修复】使用固定ID，避免切换语言时按钮失效
  if reaper.ImGui_Button(ctx, "+##PresetAdd", 0, 0) then
    new_preset_name_buf = ""
    new_preset_error = nil
    new_preset_mode = "blank"
    new_preset_focus_next = true
    show_new_preset_modal = true
    -- 【修复】OpenPopup应该在下一帧调用，所以只设置标志
  end
  im_utils.tooltip(ctx, i18n.t("create_new_preset"))

  reaper.ImGui_SameLine(ctx, 0, 4)

  -- [Save] 保存当前预设（沿用现有回调）
  local can_save = (state.current_preset_name ~= nil and state.current_preset_name ~= "")
  if not can_save then reaper.ImGui_BeginDisabled(ctx) end
  -- 【修复】使用固定ID，避免切换语言时按钮失效
  if reaper.ImGui_Button(ctx, i18n.t("save_preset") .. "##PresetSave", 0, 0) then
    if callbacks and callbacks.save_current_preset then
      callbacks.save_current_preset()
    end
  end
  if not can_save then reaper.ImGui_EndDisabled(ctx) end
  im_utils.tooltip(ctx, i18n.t("update_current_preset"))

  reaper.ImGui_SameLine(ctx, 0, 4)

  -- [Rename] 重命名当前预设（Default 禁用）
  local can_rename = (current_name ~= "Default" and current_name ~= "")
  if not can_rename then reaper.ImGui_BeginDisabled(ctx) end
  -- 【修复】使用固定ID，避免切换语言时按钮失效
  if reaper.ImGui_Button(ctx, i18n.t("rename") .. "##PresetRename", 0, 0) then
    -- 打开时默认填入当前预设名，便于直接删改/覆盖
    rename_new_name_buf = current_name
    rename_error = nil
    rename_focus_next = true
    show_rename_modal = true
    -- 【修复】OpenPopup应该在下一帧调用，所以只设置标志
  end
  if not can_rename then reaper.ImGui_EndDisabled(ctx) end
  im_utils.tooltip(ctx, can_rename and i18n.t("rename_current_preset") or i18n.t("default_cannot_rename_tooltip"))

  reaper.ImGui_SameLine(ctx, 0, 4)

  -- [Trash] 删除当前预设（沿用现有回调；Default 禁用）
  local can_delete = (state.current_preset_name ~= "Default" and state.current_preset_name ~= nil and state.current_preset_name ~= "")
  if not can_delete then reaper.ImGui_BeginDisabled(ctx) end
  -- 【修复】使用固定ID，避免切换语言时按钮失效
  if reaper.ImGui_Button(ctx, i18n.t("delete") .. "##PresetDelete", 0, 0) then
    if callbacks and callbacks.delete_current_preset then
      callbacks.delete_current_preset()
    end
  end
  if not can_delete then reaper.ImGui_EndDisabled(ctx) end
  im_utils.tooltip(ctx, can_delete and i18n.t("delete_current_preset") or i18n.t("default_cannot_delete_tooltip"))

  -- Modals
  M.draw_new_preset_modal(ctx, config, state, callbacks)
  M.draw_rename_modal(ctx, state, callbacks)

  -- 右侧状态文本（保持 1.1.5 旧逻辑）
  -- 注意：不再使用SameLine，避免与语言按钮冲突
  -- 状态文本现在在语言按钮之后显示（如果需要）
  -- 语言按钮在draw_action_bar中绘制，确保始终显示
end

-- ============================================================================
-- New preset modal (Blank/Duplicate)
-- ============================================================================

function M.draw_new_preset_modal(ctx, config, state, callbacks)
  if show_new_preset_modal then
    -- 【修复】OpenPopup和BeginPopupModal的ID必须完全匹配（包括标题部分）
    reaper.ImGui_OpenPopup(ctx, i18n.t("new_preset") .. "##NewPresetModal")
    show_new_preset_modal = false  -- 【修复】重置标志，避免重复调用OpenPopup
  end

  center_modal_on_appearing(ctx)

  local flags = reaper.ImGui_WindowFlags_AlwaysAutoResize()
  if reaper.ImGui_BeginPopupModal(ctx, i18n.t("new_preset") .. "##NewPresetModal", nil, flags) then
    reaper.ImGui_Text(ctx, i18n.t("new_preset"))

    -- Mode
    local mode_label = (new_preset_mode == "duplicate") and i18n.t("duplicate_current") or i18n.t("create_blank_preset")
    reaper.ImGui_SetNextItemWidth(ctx, 250)
    if reaper.ImGui_BeginCombo(ctx, "##NewPresetMode", mode_label) then
      if reaper.ImGui_Selectable(ctx, i18n.t("create_blank_preset"), new_preset_mode == "blank") then
        new_preset_mode = "blank"
      end
      if reaper.ImGui_Selectable(ctx, i18n.t("duplicate_current"), new_preset_mode == "duplicate") then
        new_preset_mode = "duplicate"
      end
      reaper.ImGui_EndCombo(ctx)
    end

    reaper.ImGui_Text(ctx, i18n.t("name_label"))

    if new_preset_focus_next then
      reaper.ImGui_SetKeyboardFocusHere(ctx)
      new_preset_focus_next = false
    end

    -- Fixed width: avoid modal flying/infinite growth
    reaper.ImGui_SetNextItemWidth(ctx, 250)
    local changed, txt = reaper.ImGui_InputText(ctx, "##NewPresetName", new_preset_name_buf, 256)
    if changed then new_preset_name_buf = txt end

    if new_preset_error and new_preset_error ~= "" then
      reaper.ImGui_TextColored(ctx, 0xFF5252FF, new_preset_error)
    end

    -- Buttons: center-align like old UI
    local button_width = 80
    local button_spacing = 8
    local cursor_x = reaper.ImGui_GetCursorPosX(ctx)
    local avail_w = reaper.ImGui_GetContentRegionAvail(ctx)
    local total_w = button_width * 2 + button_spacing
    local offset = math.max(0, (avail_w - total_w) / 2)
    reaper.ImGui_SetCursorPosX(ctx, cursor_x + offset)

    -- 【修复】使用固定ID，避免切换语言时按钮失效
    if reaper.ImGui_Button(ctx, i18n.t("cancel") .. "##NewPresetCancel", button_width, 0) then
      show_new_preset_modal = false
      new_preset_name_buf = ""
      new_preset_error = nil
      reaper.ImGui_CloseCurrentPopup(ctx)
    end

    reaper.ImGui_SameLine(ctx, 0, 8)

    -- 【修复】使用固定ID，避免切换语言时按钮失效
    if reaper.ImGui_Button(ctx, i18n.t("confirm") .. "##NewPresetConfirm", button_width, 0) then
      local name = trim(new_preset_name_buf)

      if name == "" then
        new_preset_error = i18n.t("name_cannot_be_empty")
      elseif preset_exists(name) then
        new_preset_error = i18n.t("name_already_exists")
      else
        local data
        if new_preset_mode == "blank" then
          data = config_manager.create_blank_config()
        else
          -- 按需求：复制 config_manager.load()（已保存的 active_config）
          local src = config_manager.load()
          data = config_manager.duplicate_preset(src)
        end

        local ok, err = config_manager.save_preset(name, data)
        if ok then
          show_new_preset_modal = false
          new_preset_name_buf = ""
          new_preset_error = nil
          reaper.ImGui_CloseCurrentPopup(ctx)

          if callbacks and callbacks.switch_preset then
            callbacks.switch_preset(name)
          end
        else
          new_preset_error = err or i18n.t("save_failed")
        end
      end
    end

    if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape()) then
      show_new_preset_modal = false
      new_preset_name_buf = ""
      new_preset_error = nil
      reaper.ImGui_CloseCurrentPopup(ctx)
    end

    reaper.ImGui_EndPopup(ctx)
  end
end

-- ============================================================================
-- Rename modal
-- ============================================================================

function M.draw_rename_modal(ctx, state, callbacks)
  if show_rename_modal then
    -- 【修复】OpenPopup和BeginPopupModal的ID必须完全匹配（包括标题部分）
    reaper.ImGui_OpenPopup(ctx, i18n.t("rename") .. " " .. i18n.t("preset") .. "##RenamePresetModal")
    show_rename_modal = false  -- 【修复】重置标志，避免重复调用OpenPopup
  end

  center_modal_on_appearing(ctx)

  local flags = reaper.ImGui_WindowFlags_AlwaysAutoResize()
    if reaper.ImGui_BeginPopupModal(ctx, i18n.t("rename") .. " " .. i18n.t("preset") .. "##RenamePresetModal", nil, flags) then
    local old_name = state.current_preset_name or "Default"
    reaper.ImGui_Text(ctx, i18n.t("rename_label_prefix") .. tostring(old_name))
    reaper.ImGui_Text(ctx, i18n.t("new_name") .. ":")

    if rename_focus_next then
      reaper.ImGui_SetKeyboardFocusHere(ctx)
      rename_focus_next = false
    end

    reaper.ImGui_SetNextItemWidth(ctx, 250)
    local it_flags = 0
    if reaper.ImGui_InputTextFlags_AutoSelectAll then
      it_flags = reaper.ImGui_InputTextFlags_AutoSelectAll()
    end
    local changed, txt = reaper.ImGui_InputText(ctx, "##RenamePresetName", rename_new_name_buf, it_flags)
    if changed then rename_new_name_buf = txt end

    if rename_error and rename_error ~= "" then
      reaper.ImGui_TextColored(ctx, 0xFF5252FF, rename_error)
    end

    -- Buttons: center-align like old UI
    local button_width = 80
    local button_spacing = 8
    local cursor_x = reaper.ImGui_GetCursorPosX(ctx)
    local avail_w = reaper.ImGui_GetContentRegionAvail(ctx)
    local total_w = button_width * 2 + button_spacing
    local offset = math.max(0, (avail_w - total_w) / 2)
    reaper.ImGui_SetCursorPosX(ctx, cursor_x + offset)

    -- 【修复】使用固定ID，避免切换语言时按钮失效
    if reaper.ImGui_Button(ctx, i18n.t("cancel") .. "##RenamePresetCancel", button_width, 0) then
      show_rename_modal = false
      rename_new_name_buf = ""
      rename_error = nil
      reaper.ImGui_CloseCurrentPopup(ctx)
    end

    reaper.ImGui_SameLine(ctx, 0, 8)

    -- 【修复】使用固定ID，避免切换语言时按钮失效
    if reaper.ImGui_Button(ctx, i18n.t("confirm") .. "##RenamePresetConfirm", button_width, 0) then
      local new_name = trim(rename_new_name_buf)

      if old_name == "Default" then
        rename_error = i18n.t("default_cannot_rename")
      elseif new_name == "" then
        rename_error = i18n.t("name_cannot_be_empty_short")
      elseif preset_exists(new_name) then
        rename_error = i18n.t("name_already_exists")
      else
        local ok, err = config_manager.rename_preset(old_name, new_name)
        if ok then
          -- UI 立即刷新：当前预设名变更
          state.current_preset_name = new_name
          show_rename_modal = false
          rename_new_name_buf = ""
          rename_error = nil
          reaper.ImGui_CloseCurrentPopup(ctx)
        else
          rename_error = err or i18n.t("rename_failed")
        end
      end
    end

    if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape()) then
      show_rename_modal = false
      rename_new_name_buf = ""
      rename_error = nil
      reaper.ImGui_CloseCurrentPopup(ctx)
    end

    reaper.ImGui_EndPopup(ctx)
  end
end

-- 关闭所有弹窗（用于语言切换时清理状态）
function M.close_all_modals()
  show_new_preset_modal = false
  show_rename_modal = false
end

return M
