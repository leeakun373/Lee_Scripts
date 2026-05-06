--[[
  Item Function: Trim Items to Reference Length
  Description: 统一选中item的长度
  - 以最先开始的那个选中item的长度为参考
  - 如果item比参考长度长，裁剪尾部（缩短）
  - 如果item比参考长度短，拉长尾部（延长）
  - 不移动起点，只调整尾部
  - 可以多轨，但逻辑以时间最早的item做参考
]]

local proj = 0

-- Execute function
local function execute()
    -- 1. Start undo block
    reaper.Undo_BeginBlock()
    
    -- 2. 获取所有选中item，若数量 < 2 则提示并退出
    local item_count = reaper.CountSelectedMediaItems(proj)
    if item_count < 2 then
        reaper.Undo_EndBlock("Trim Items to Reference Length", -1)
        return false, "Please select at least 2 items"
    end
    
    -- 3. 在选中item中找到position最小的那个 → reference item
    local ref_item = nil
    local ref_pos = math.huge
    
    for i = 0, item_count - 1 do
        local item = reaper.GetSelectedMediaItem(proj, i)
        if item then
            local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            if item_pos < ref_pos then
                ref_pos = item_pos
                ref_item = item
            end
        end
    end
    
    if not ref_item then
        reaper.Undo_EndBlock("Trim Items to Reference Length", -1)
        return false, "Failed to find reference item"
    end
    
    -- 4. 计算 ref_len = GetMediaItemInfo_Value(ref_item, "D_LENGTH")
    local ref_len = reaper.GetMediaItemInfo_Value(ref_item, "D_LENGTH")
    
    -- 5. 对每个选中item进行处理
    local modified_count = 0
    local trimmed_count = 0
    local extended_count = 0
    
    for i = 0, item_count - 1 do
        local item = reaper.GetSelectedMediaItem(proj, i)
        if item then
            -- 若 item == ref_item → 跳过
            if item == ref_item then
                -- 跳过参考item
            else
                local current_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                
                -- 如果长度不同，调整到参考长度
                if math.abs(current_len - ref_len) > 0.0001 then  -- 考虑浮点数精度
                    reaper.SetMediaItemInfo_Value(item, "D_LENGTH", ref_len)
                    modified_count = modified_count + 1
                    
                    if current_len > ref_len then
                        trimmed_count = trimmed_count + 1
                    else
                        extended_count = extended_count + 1
                    end
                end
            end
        end
    end
    
    -- 6. UpdateArrange()
    reaper.UpdateArrange()
    
    -- 7. End undo block
    reaper.Undo_EndBlock("Trim/Extend Items to Reference Length", -1)
    
    if modified_count > 0 then
        local actions = {}
        if trimmed_count > 0 then
            table.insert(actions, string.format("%d trimmed", trimmed_count))
        end
        if extended_count > 0 then
            table.insert(actions, string.format("%d extended", extended_count))
        end
        return true, string.format("Modified %d item(s): %s", modified_count, table.concat(actions, ", "))
    else
        return true, "All items already match reference length"
    end
end

-- Return module
return {
    name = "Trim Items to Reference Length",
    description = "Trim or extend selected items to match earliest item length",
    execute = execute,
    buttonColor = {0xFF5722FF, 0xFF8A65FF, 0xE64A19FF}  -- Deep Orange
}

