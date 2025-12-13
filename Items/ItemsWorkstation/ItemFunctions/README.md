# Item Functions Directory

This directory contains modular item functions that can be loaded by Item Workstation.

## Available Functions

### 01_JumpToPreviousItem.lua
**Jump to Previous** - 跳转到选中轨道上的上一个媒体项
- 将编辑光标移动到上一个媒体项的起始位置
- 查找光标之前最接近的item
- 自动滚动视图以显示目标位置

### 02_JumpToNextItem.lua
**Jump to Next** - 跳转到选中轨道上的下一个媒体项
- 将编辑光标移动到下一个媒体项的起始位置
- 如果光标在item内，会跳过当前item，跳转到下一个
- 自动滚动视图以显示目标位置

### 03_MoveCursorToItemStart.lua
**Move Cursor to Item Start** - 移动光标到选中item的头部
- 将编辑光标移动到第一个选中item的开始位置
- 自动滚动视图以显示目标位置

### 04_MoveCursorToItemEnd.lua
**Move Cursor to Item End** - 移动光标到选中item的尾部
- 将编辑光标移动到第一个选中item的结束位置
- 自动滚动视图以显示目标位置

### 05_SelectUnmutedItems.lua
**Select Unmuted Items** - 选中所有未mute的item
- 取消当前所有item的选择
- 遍历项目中所有item
- 选中所有未mute的item
- 显示选中数量

### 06_TrimItemsToReferenceLength.lua
**Trim Items to Reference Length** - 统一选中item的长度
- 以最先开始的那个选中item的长度为参考
- 如果item比参考长度长，裁剪尾部（缩短）
- 如果item比参考长度短，拉长尾部（延长）
- 不移动起点，只调整尾部
- 支持多轨道，以时间最早的item为参考
- 适用于从长录音切出多个item后统一长度的场景

### 07_AddFadeInOut.lua
**Add Fade In Out** - 给选中的items添加fade in和fade out
- 可以自定义fade in和fade out的时长（通过输入对话框）
- 默认值：0.2秒fade in，0.2秒fade out
- 如果item长度小于fade in + fade out的总长度，则按比例分配（各占50%）
- 智能处理：确保fade长度不超过item长度

### 08_SelectAllItemsOnTrack.lua
**Select All Items on Track** - 选择轨道上的所有媒体项
- 获取当前轨道（优先选中的轨道，否则最后触摸的轨道）
- 取消所有item的选择
- 选中该轨道上的所有item

## How to Add New Functions

1. Create a new `.lua` file in this directory
2. The file must return a table with the following structure:

```lua
return {
    name = "Button Name",           -- Required: Display name for the button
    description = "Description",    -- Optional: Function description
    execute = function()            -- Required: Function to execute
        -- Your code here
        -- Return: success (boolean), message (string)
        return true, "Success message"
    end,
    buttonColor = nil               -- Optional: Custom button color
                                    -- nil = default color
                                    -- {color1, color2, color3} = custom colors
                                    --   color1 = normal color
                                    --   color2 = hover color  
                                    --   color3 = active color
                                    -- Colors are in 0xRRGGBBAA format
}
```

## Example Function

```lua
--[[
  Item Function: My Custom Function
]]

local function execute()
    -- Your item operation code here
    reaper.Undo_BeginBlock()
    -- ... do something ...
    reaper.Undo_EndBlock("My operation", -1)
    
    return true, "Operation completed successfully"
end

return {
    name = "My Function",
    description = "Does something with items",
    execute = execute,
    buttonColor = nil  -- Use default color
}
```

## Color Examples

```lua
-- Orange button
buttonColor = {0xFF9800FF, 0xFFB74DFF, 0xF57C00FF}

-- Red button
buttonColor = {0xFF0000FF, 0xFF3333FF, 0xCC0000FF}

-- Green button
buttonColor = {0x4CAF50FF, 0x66BB6AFF, 0x43A047FF}

-- Blue button
buttonColor = {0x2196F3FF, 0x42A5F5FF, 0x1976D2FF}

-- Purple button
buttonColor = {0x9C27B0FF, 0xBA68C8FF, 0x7B1FA2FF}
```

## Notes

- Functions are automatically loaded when Item Workstation starts
- Click "Reload Functions" button to reload without restarting
- Each function should handle its own undo blocks
- Functions should return (success, message) tuple

