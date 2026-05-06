-- @description Delete regions within time selection (删除时间选区内的所有Region)
-- @author Gemini
-- @version 1.0

function Main()
    -- 1. 获取当前的时间选区
    local start_time, end_time = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)

    -- 如果没有时间选区（或者选区长度为0），则退出
    if start_time == end_time then
        reaper.MB("请先在时间线上拉出一个时间选区（Time Selection）。", "提示", 0)
        return
    end

    reaper.Undo_BeginBlock()
    
    -- 2. 获取项目中标记和区域的总数
    local retval, num_markers, num_regions = reaper.CountProjectMarkers(0)
    local total = num_markers + num_regions

    -- 3. 从后往前遍历（重要：防止索引错乱）
    for i = total - 1, 0, -1 do
        local retval, isrgn, pos, rgnend, name, markrgnindexnumber = reaper.EnumProjectMarkers(i)
        
        -- 如果这是一个 Region
        if isrgn then
            -- 判断逻辑：只要 Region 的起点或终点在选区内，或者 Region 完全包围了选区
            -- 你也可以根据需要调整判断条件，目前是“只要有重叠就删除”
            if (pos >= start_time and pos <= end_time) or 
               (rgnend >= start_time and rgnend <= end_time) or
               (pos <= start_time and rgnend >= end_time) then
                
                -- 执行删除
                reaper.DeleteProjectMarker(0, markrgnindexnumber, true)
            end
        end
    end

    reaper.Undo_EndBlock("Delete regions in time selection", -1)
    reaper.UpdateArrange()
end

Main()
