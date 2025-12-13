-- @description Lee Radial Menu Tool
-- @version 1.0.0
-- @author Lee
-- @about
--   轮盘菜单工具的状态重置脚本
--   用于清除脚本的"僵尸状态"，解决因崩溃或中断导致的脚本无法打开问题
--   如果主脚本无法启动，运行此脚本可以强制重置状态
-- @provides
--   [main] .
--   [main] Lee_RadialMenu_Setup.lua
--   src/**
--   utils/**
--   doc/**
--   config.example.json
--   Lee_RadialMenu_reset_state.lua

-- 临时重置脚本：清除 RadialMenu Tool 的"僵尸状态"
-- 如果脚本无法打开，运行此脚本可以强制重置状态

reaper.SetExtState("RadialMenu_Tool", "Running", "0", false)
reaper.ShowMessageBox("状态已重置！\n\n现在可以尝试运行 RadialMenu Tool 了。", "状态重置", 0)

