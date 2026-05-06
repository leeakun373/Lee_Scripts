# Marker Functions Directory

This directory contains modular marker functions that can be loaded by Marker Workstation.

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
  Marker Function: My Custom Function
]]

local function execute()
    -- Your marker operation code here
    reaper.Undo_BeginBlock()
    -- ... do something ...
    reaper.Undo_EndBlock("My operation", -1)
    
    return true, "Operation completed successfully"
end

return {
    name = "My Function",
    description = "Does something with markers",
    execute = execute,
    buttonColor = nil  -- Use default color
}
```

## Color Examples

```lua
-- Orange button
buttonColor = {0xFF8800FF, 0xFF9933FF, 0xFF6600FF}

-- Red button
buttonColor = {0xFF0000FF, 0xFF3333FF, 0xCC0000FF}

-- Green button
buttonColor = {0x4CAF50FF, 0x66BB6AFF, 0x43A047FF}
```

## Notes

- Functions are automatically loaded when Marker Workstation starts
- Click "Reload Functions" button to reload without restarting
- Each function should handle its own undo blocks
- Functions should return (success, message) tuple




