--[[
  Marker Function: Align Items to Markers by Name
  Description: 自动对齐同名文件到Project Marker
  - 根据媒体项的文件名（不含路径和扩展名）匹配标记名称
  - 将匹配的媒体项移动到对应标记的位置
  - 静默执行，如果没有选中项则静默退出
]]

local proj = 0

-- 提取文件名（不含路径和扩展名）
local function extractBaseName(filename)
    if not filename or filename == "" then
        return nil
    end
    
    -- 提取文件名（不含路径）
    local base_name = string.match(filename, "([^\\/]-)%.?[^%.\\/]*$")
    
    -- 移除扩展名
    base_name = string.match(base_name, "(.+)%..+$") or base_name
    
    return base_name
end

-- 收集所有标记信息
local function getAllMarkers()
    local markers = {}
    local retval, marker_count, region_count = reaper.CountProjectMarkers(proj)
    
    for i = 0, marker_count + region_count - 1 do
        local retval, isrgn, pos, rgnend, name, markrgnindex = reaper.EnumProjectMarkers(i)
        if retval and not isrgn then -- 只处理标记，不处理区域
            markers[name] = pos
        end
    end
    
    return markers
end

-- Execute function
local function execute()
    -- 收集所有标记信息
    local markers = getAllMarkers()
    
    if not markers or next(markers) == nil then
        return false, "Error: No project markers found"
    end
    
    -- 获取所有选中的媒体项
    local selected_item_count = reaper.CountSelectedMediaItems(proj)
    
    if selected_item_count == 0 then
        return false, "Error: No items selected"
    end
    
    local processed_count = 0
    local matched_count = 0
    local unmatched_count = 0
    
    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)
    
    -- 遍历所有选中的媒体项
    for i = 0, selected_item_count - 1 do
        local item = reaper.GetSelectedMediaItem(proj, i)
        if item then
            -- 获取媒体项的take
            local take = reaper.GetActiveTake(item)
            if take then
                -- 获取源文件名称
                local source = reaper.GetMediaItemTake_Source(take)
                if source then
                    local filename = reaper.GetMediaSourceFileName(source, "")
                    
                    -- 提取文件名（不含路径和扩展名）
                    local base_name = extractBaseName(filename)
                    
                    if base_name then
                        -- 检查是否有对应的标记
                        if markers[base_name] then
                            local marker_pos = markers[base_name]
                            local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                            
                            -- 计算偏移量
                            local offset = marker_pos - item_pos
                            
                            if math.abs(offset) > 0.001 then -- 避免浮点数精度问题
                                -- 移动媒体项到标记位置
                                reaper.SetMediaItemInfo_Value(item, "D_POSITION", marker_pos)
                                processed_count = processed_count + 1
                                matched_count = matched_count + 1
                            else
                                matched_count = matched_count + 1
                            end
                        else
                            unmatched_count = unmatched_count + 1
                        end
                    else
                        unmatched_count = unmatched_count + 1
                    end
                else
                    unmatched_count = unmatched_count + 1
                end
            else
                unmatched_count = unmatched_count + 1
            end
        end
    end
    
    reaper.UpdateArrange()
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock("自动对齐同名文件到标记", -1)
    
    -- 生成状态消息
    local message = string.format("Aligned %d item(s)", processed_count)
    if matched_count > processed_count then
        message = message .. string.format(", %d already aligned", matched_count - processed_count)
    end
    if unmatched_count > 0 then
        message = message .. string.format(", %d unmatched", unmatched_count)
    end
    
    return true, message
end

-- Return module
return {
    name = "Align to Markers",
    description = "Align selected items to markers by matching filename",
    execute = execute,
    buttonColor = {0xFF9800FF, 0xFFB74DFF, 0xF57C00FF}  -- Orange
}

