-- @description Toolbox - Temp Action Bar (临时动作触发面板)
-- @version 1.2
-- @author Lee
-- @about
--   基于 Toolbox 框架的临时 Action Bar。
--   - 支持自由添加/删除槽位。
--   - 自动持久化保存配置好的 Action。
--   - 支持从剪贴板粘贴 ID 并自动获取 Action 名称（强化版解析）。
--   - 交互：左键执行（或分配），右键呼出编辑菜单。

local r = reaper

local function script_dir()
  local src = debug.getinfo(1, "S").source
  return src:match("^@(.+[\\/])")
end

local root = script_dir()
package.path = root .. "framework/?.lua;" .. package.path

local bootstrap = require("bootstrap")
local ImGui = bootstrap.ensure_imgui("0.9")
if not ImGui then
  return
end

local App = require("app").App
local W = require("widgets")
local Theme = require("ui_theme")
local AppState = require("app_state")

local app = App.new(ImGui, {
  title = "临时 Action Bar",
  ext_section = "Toolbox_TempActionBar",
})

local function ensure_state()
  if not app.state.slots then
    app.state.slots = {
      { name = "", cmd_id = "" },
      { name = "", cmd_id = "" },
      { name = "", cmd_id = "" },
      { name = "", cmd_id = "" }
    }
  end
end

local destroyed = false
r.atexit(function()
  if not destroyed then
    destroyed = true
    pcall(function()
      Theme.destroy(app)
      app:destroy()
    end)
  end
end)

local function draw()
  local ctx = app.ctx
  ensure_state()

  W.separator_text(ctx, ImGui, "Action 触发面板")
  ImGui.TextDisabled(ctx, "左键：执行动作 / 右键：编辑与管理槽位")
  ImGui.Spacing(ctx)

  local open_edit_popup = false
  local remove_idx = nil

  -- 遍历绘制所有槽位
  for i, slot in ipairs(app.state.slots) do
    ImGui.PushID(ctx, i)
    
    local btn_w = ImGui.GetContentRegionAvail(ctx)
    local btn_h = 32

    if slot.cmd_id == nil or slot.cmd_id == "" then
      ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x44444444)
      if ImGui.Button(ctx, "+ 点击分配 Action", btn_w, btn_h) then
        app.edit_idx = i
        app.edit_name = ""
        app.edit_cmd = ""
        open_edit_popup = true
      end
      ImGui.PopStyleColor(ctx)
    else
      local display_name = (slot.name and slot.name ~= "") and slot.name or slot.cmd_id
      if ImGui.Button(ctx, display_name, btn_w, btn_h) then
        local cmd_num = r.NamedCommandLookup(slot.cmd_id)
        if cmd_num > 0 then
          r.Main_OnCommand(cmd_num, 0)
        else
          app.log = app.log or {}
          table.insert(app.log, "无法识别 Command ID: " .. tostring(slot.cmd_id))
        end
      end
    end

    if ImGui.BeginPopupContextItem(ctx) then
      if ImGui.MenuItem(ctx, "编辑槽位 (Edit)...") then
        app.edit_idx = i
        app.edit_name = slot.name or ""
        app.edit_cmd = slot.cmd_id or ""
        open_edit_popup = true
      end
      
      if ImGui.MenuItem(ctx, "清空动作 (Clear)") then
        slot.name = ""
        slot.cmd_id = ""
        AppState.save(app)
      end
      
      ImGui.Separator(ctx)
      
      if ImGui.MenuItem(ctx, "删除此槽位 (Remove Slot)") then
        remove_idx = i
      end
      ImGui.EndPopup(ctx)
    end
    
    ImGui.PopID(ctx)
    ImGui.Spacing(ctx)
  end

  if remove_idx then
    table.remove(app.state.slots, remove_idx)
    AppState.save(app)
  end

  ImGui.Spacing(ctx)
  ImGui.Separator(ctx)
  
  if ImGui.Button(ctx, "+ 添加新槽位", -1, 24) then
    table.insert(app.state.slots, { name = "", cmd_id = "" })
    AppState.save(app)
  end

  ImGui.Spacing(ctx)
  if ImGui.Button(ctx, "关闭面板 (Close)", -1, 30) then
    app.open = false
  end

  -- =========================================
  -- 编辑弹窗逻辑
  -- =========================================
  if open_edit_popup then
    ImGui.OpenPopup(ctx, "EditActionPopup")
  end

  local win_x, win_y = ImGui.GetWindowPos(ctx)
  local win_w, win_h = ImGui.GetWindowSize(ctx)
  ImGui.SetNextWindowPos(ctx, win_x + win_w * 0.5, win_y + win_h * 0.5, ImGui.Cond_Appearing, 0.5, 0.5)
  
  local rv, is_open = ImGui.BeginPopupModal(ctx, "EditActionPopup", true, ImGui.WindowFlags_AlwaysAutoResize)
  if rv then
    W.separator_text(ctx, ImGui, "配置动作")
    ImGui.TextDisabled(ctx, "提示: 在 Action List 中右键你要的动作\n选择 'Copy selected action command ID'，然后点击粘贴。")
    ImGui.Spacing(ctx)

    local _
    _, app.edit_name = ImGui.InputText(ctx, "显示名称 (别名)", app.edit_name)
    _, app.edit_cmd = ImGui.InputText(ctx, "Command ID", app.edit_cmd)

    ImGui.Spacing(ctx)
    if ImGui.Button(ctx, "从剪贴板粘贴 ID 并自动获取名称", -1, 30) then
      local clip = ImGui.GetClipboardText(ctx)
      if clip and clip ~= "" then
        -- 彻底清理剪贴板中可能带有的换行符、空格和不可见控制字符
        clip = clip:gsub("[%s%c]", "")
        app.edit_cmd = clip
        
        local cmd_num = r.NamedCommandLookup(clip)
        if cmd_num > 0 then
          local found_name = ""
          
          -- 1. 优先尝试原生 API，遍历常用 Section (0=Main, 32060=MIDI Editor, 32063=Media Explorer)
          local sections = {0, 32060, 32063}
          for _, sec_id in ipairs(sections) do
            local sec = r.SectionFromUniqueID(sec_id)
            if sec then
              local ok, action_name = r.kbd_getTextFromCmd(cmd_num, sec)
              if ok and action_name and action_name ~= "" then
                found_name = action_name
                break
              end
            end
          end
          
          -- 2. 如果原生 API 没抓到，且安装了 SWS 扩展，用 SWS 兜底获取
          if found_name == "" and r.CF_GetCommandText then
             local action_name = r.CF_GetCommandText(0, cmd_num)
             if action_name and action_name ~= "" then 
               found_name = action_name 
             end
          end

          -- 3. 给获取到的名字进行净化
          if found_name ~= "" then
            -- 去除名字开头的 "Script: " 或 "Custom: " 等前缀，让按钮文字更清晰
            found_name = found_name:gsub("^Script:%s*", ""):gsub("^Custom:%s*", "")
            app.edit_name = found_name
          else
            app.edit_name = "未找到名称 (请手动输入)"
          end
        else
          app.edit_name = "无效的 Command ID"
        end
      end
    end

    ImGui.Spacing(ctx)
    ImGui.Separator(ctx)
    ImGui.Spacing(ctx)

    local btn_w2 = (ImGui.GetContentRegionAvail(ctx) - 8) / 2
    if ImGui.Button(ctx, "保存 (Save)", btn_w2, 30) then
      if app.edit_idx and app.state.slots[app.edit_idx] then
        app.state.slots[app.edit_idx].name = app.edit_name
        app.state.slots[app.edit_idx].cmd_id = app.edit_cmd
        AppState.save(app)
      end
      ImGui.CloseCurrentPopup(ctx)
    end
    
    ImGui.SameLine(ctx)
    
    if ImGui.Button(ctx, "取消 (Cancel)", btn_w2, 30) then
      ImGui.CloseCurrentPopup(ctx)
    end

    ImGui.EndPopup(ctx)
  end
end

local function loop()
  Theme.begin(app)

  local visible, open
  if app.open == false then
    visible, open = false, false
  else
    visible, open = app:begin_window()
    if visible then
      draw()
    end
    app:end_window()
    if app.open == false then
      open = false
    end
  end

  Theme.end_(app)
  
  if open then
    AppState.tick(app, app.state.low_cpu and 2.0 or 0.75)
    r.defer(loop)
  else
    if not destroyed then
      destroyed = true
      Theme.destroy(app)
      app:destroy()
    end
  end
end

r.defer(loop)
