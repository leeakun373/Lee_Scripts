-- @description RadialMenu Tool - 主运行时（兼容壳）
-- @about
--   为了降低维护成本，主运行时已迁移到 `src/runtime/controller.lua`。
--   保留此文件仅用于兼容旧入口：`require('main_runtime').run()`。

return require("runtime.controller")
