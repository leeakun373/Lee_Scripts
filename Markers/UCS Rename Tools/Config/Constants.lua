--[[
  Configuration constants for UCS Rename Tools
]]

local Constants = {}

-- Version info
Constants.VERSION = "10.2"
Constants.VERSION_DATE = "2025-12-04"
Constants.VERSION_DESC = "Enhanced UX: Alias system, Smart init, Editable combos"

-- File paths
Constants.CSV_DB_FILE    = "ucs_data.csv"
Constants.CSV_ALIAS_FILE = "ucs_alias.csv"
Constants.SEPARATOR      = "_"
Constants.DEFAULT_UCS_MODE = false 

-- Safe dominant keywords (materials with minimal ambiguity)
-- Only these material keywords receive bonus points when matching categories
Constants.SAFE_DOMINANT_KEYWORDS = {
    ["water"] = true, ["liquid"] = true, ["ice"] = true,
    ["glass"] = true, ["ceramic"] = true, ["electricity"] = true,
    ["mud"] = true, ["dirt"] = true, ["stone"] = true, ["rock"] = true
}

-- Smart matching weights
Constants.WEIGHTS = {
    CATEGORY_EXACT = 20,       -- Base score for exact category match
    CATEGORY_PART  = 5,        -- Partial category match
    SUBCATEGORY    = 60,       -- Subcategory remains the main force
    SYNONYM        = 40,
    DESCRIPTION    = 5,
    PERFECT_BONUS  = 30,
    SAFE_DOMINANT_BONUS = 50   -- Bonus for safe dominant keywords (20 base + 50 bonus = 70, exceeds subcategory 60)
}
Constants.MATCH_THRESHOLD = 15

-- Words that downgrade match scores
Constants.DOWNGRADE_WORDS = {
    ["small"] = true, ["medium"] = true, ["large"] = true, ["big"] = true, ["tiny"] = true,
    ["fast"] = true, ["slow"] = true, ["heavy"] = true, ["light"] = true,
    ["long"] = true, ["short"] = true, ["high"] = true, ["low"] = true,
    ["soft"] = true, ["hard"] = true, ["wet"] = true, ["dry"] = true,
    ["general"] = true, ["misc"] = true, ["miscellaneous"] = true,
    ["indoor"] = true, ["outdoor"] = true, ["exterior"] = true, ["interior"] = true
}

-- Color constants (for GUI display)
Constants.COLORS = {
    TEXT_NORMAL   = 0xEEEEEEFF,
    TEXT_DIM      = 0x888888FF,
    TEXT_MODIFIED = 0x4DB6ACFF, 
    TEXT_AUTO     = 0xFFCA28FF, 
    ID_MARKER     = 0x90A4AEFF,
    ID_REGION     = 0x7986CBFF,
    
    BTN_COPY      = 0x42A5F5AA, 
    BTN_PASTE     = 0xFFA726AA, 
    BTN_REFRESH   = 0x666666AA,
    BTN_APPLY     = 0x2E7D32FF,
    BTN_AUTO      = 0xFFB300AA,
    BTN_ALIAS     = 0x9C27B0AA,  -- Purple for Alias button
    
    BTN_MODE_ON   = 0x7E57C2AA, 
    BTN_MODE_OFF  = 0x555555AA, 
    
    BG_ROW_ALT    = 0xFFFFFF0D,
}

-- Optional field configurations
Constants.UCS_OPTIONAL_FIELDS = {
    {
        key = "vendor_category",
        display = "Vendor Category",
        position_after = "fx_name",
        validation = function(value)
            if not value or value == "" then return true end
            return not value:match("[_ ]")  -- 不能包含_和空格
        end
    },
    {
        key = "creator_id",
        display = "CreatorID",
        position_after = "fx_name",
        validation = function(value)
            if not value or value == "" then return true end
            return not value:match("[_ ]")
        end
    },
    {
        key = "source_id",
        display = "SourceID",
        position_after = "creator_id",
        validation = function(value)
            if not value or value == "" then return true end
            return not value:match("[_ ]")
        end
    },
    {
        key = "user_data",
        display = "User Data",
        position_after = "source_id",
        validation = nil  -- 无限制
    }
}

-- Initialize application state
function Constants.createAppState()
    return {
        merged_list = {},
        status_msg = "Initializing...",
        filter_markers = true,
        filter_regions = true,
        use_ucs_mode = Constants.DEFAULT_UCS_MODE,
        display_language = "zh",  -- 显示语言：zh=中文, en=英文
        -- 字段显示状态（默认全部隐藏）
        field_visibility = {
            vendor_category = false,
            creator_id = false,
            source_id = false,
            user_data = false
        }
    }
end

-- Initialize UCS database structure
function Constants.createUCSDB()
    return {
        flat_list = {},
        id_lookup = {},
        tree_data = {},        -- 中文树结构
        tree_data_en = {},     -- 英文树结构
        categories_zh = {},
        categories_en = {},
        en_to_zh = {},         -- 英文到中文映射
        zh_to_en = {},         -- 中文到英文映射
        alias_list = {}        -- 别名列表（用于短语匹配）
    }
end

return Constants

