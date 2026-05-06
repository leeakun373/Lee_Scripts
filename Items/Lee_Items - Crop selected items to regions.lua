-- @description Crop selected items to regions (根据Region裁切并保留选中Item)
-- @author Gemini
-- @version 1.0

function Main()
    -- 开始 Undo 块，方便一键撤销
    reaper.Undo_BeginBlock()
    -- 暂停 UI 刷新以提高执行速度
    reaper.PreventUIRefresh(1)

    -- 1. 获取项目中所有的 Regions
    local regions = {}
    local retval, num_markers, num_regions = reaper.CountProjectMarkers(0)
    for i = 0, num_markers + num_regions - 1 do
        local retval, isrgn, pos, rgnend, name, markrgnindexnumber = reaper.EnumProjectMarkers(i)
        if isrgn then
            table.insert(regions, {start_pos = pos, end_pos = rgnend})
        end
    end

    if #regions == 0 then
        reaper.MB("当前项目中没有找到 Region。", "提示", 0)
        return
    end

    -- 2. 存储当前选中的 Items（存入数组以防止切割时指针混乱）
    local sel_items = {}
    local num_sel_items = reaper.CountSelectedMediaItems(0)
    
    if num_sel_items == 0 then
        reaper.MB("请先选中至少一个 Item。", "提示", 0)
        return
    end

    for i = 0, num_sel_items - 1 do
        table.insert(sel_items, reaper.GetSelectedMediaItem(0, i))
    end

    -- 3. 遍历并处理每个选中的 Item
    for _, item in ipairs(sel_items) do
        local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        local item_end = item_start + item_len

        -- 寻找当前 item 范围内所有的切点（Region 的起点和终点）
        local split_points = {}
        for _, rgn in ipairs(regions) do
            if rgn.start_pos > item_start and rgn.start_pos < item_end then
                split_points[rgn.start_pos] = true
            end
            if rgn.end_pos > item_start and rgn.end_pos < item_end then
                split_points[rgn.end_pos] = true
            end
        end

        -- 将切点转换为数组，并按时间降序（从右向左）排列
        local sp_arr = {}
        for sp, _ in pairs(split_points) do table.insert(sp_arr, sp) end
        table.sort(sp_arr, function(a, b) return a > b end)

        -- 从右向左切割 Item
        local fragments = {item} 
        for _, sp in ipairs(sp_arr) do
            -- fragments[1] 永远是最左边的原始片段，从它身上切下右半边
            local new_item = reaper.SplitMediaItem(fragments[1], sp)
            if new_item then
                table.insert(fragments, 2, new_item) -- 将新切出的片段插入到数组中
            end
        end

        -- 4. 检查所有切开后的碎片，删除中心点不在任何 Region 内的碎片
        for _, frag in ipairs(fragments) do
            local f_pos = reaper.GetMediaItemInfo_Value(frag, "D_POSITION")
            local f_len = reaper.GetMediaItemInfo_Value(frag, "D_LENGTH")
            local f_center = f_pos + (f_len / 2) -- 使用中心点判断最准确，避免精度误差

            local keep = false
            for _, rgn in ipairs(regions) do
                if f_center >= rgn.start_pos and f_center <= rgn.end_pos then
                    keep = true
                    break
                end
            end

            -- 如果不在保留名单里，直接删除
            if not keep then
                local track = reaper.GetMediaItem_Track(frag)
                reaper.DeleteTrackMediaItem(track, frag)
            end
        end
    end

    -- 恢复 UI 刷新并更新界面
    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
    -- 结束 Undo 块
    reaper.Undo_EndBlock("Crop items to regions", -1)
end

Main()
