# 项目维护指南

本指南说明如何维护 Lee Scripts 项目，包括文档管理、代码整理和版本控制。

## 📚 目录

- [文档维护](#文档维护)
- [代码维护](#代码维护)
- [版本管理](#版本管理)
- [定期任务](#定期任务)

---

## 📝 文档维护

### 文档结构

```
Doc/
├── README.md                          # 文档索引（主入口）
├── VERSION_CONTROL_GUIDE.md          # 版本控制指南
├── MAINTENANCE.md                    # 维护指南（本文件）
│
├── UI框架相关/
│   ├── UI_FRAMEWORKS_RESOURCES.md    # UI框架资源
│   └── RTK_VS_REAIMGUI_COMPARISON.md # 框架对比
│
├── 脚本分析/
│   ├── SCRIPT_ANALYSIS.md            # 脚本功能分析
│   ├── nvkLearn.md                   # nvk Take Marker 学习文档
│   └── CONVERSATION_SUMMARY.md       # 对话摘要
│
├── 技术研究/
│   ├── LOKASENNA_RADIAL_MENU_ANALYSIS.md      # Lokasenna 分析
│   ├── MANTRIKA_RADIAL_MENU_ANALYSIS.md       # Mantrika 分析
│   ├── RADIAL_MENU_IMPLEMENTATION_OPTIONS.md  # 实现方案
│   ├── SLINT_FOR_REAPER_ANALYSIS.md          # Slint 分析
│   ├── REAPER_CPP_EXTENSION_DEVELOPMENT.md    # C++ 扩展开发
│   └── DEPLOYMENT_COMPARISON.md              # 部署对比
│
└── 配置文件/
    └── Scripts.code-workspace        # VS Code 工作区配置
```

### 文档分类

#### 1. 核心文档（必须保持更新）
- `README.md` - 项目主文档
- `Doc/README.md` - 文档索引
- `VERSION_CONTROL_GUIDE.md` - 版本控制指南
- `MAINTENANCE.md` - 维护指南

#### 2. 参考文档（按需更新）
- UI 框架相关文档
- 脚本分析文档
- 技术研究文档

#### 3. 归档文档（不再更新）
- 过时的分析文档
- 已完成的研究文档

### 文档更新规则

1. **添加新脚本时**:
   - 更新根目录 `README.md` 的脚本列表
   - 如有必要，更新相关分类说明

2. **修改脚本功能时**:
   - 更新 `README.md` 中的功能描述
   - 如有重大变更，在更新日志中记录

3. **添加新文档时**:
   - 在 `Doc/README.md` 中添加索引
   - 按分类组织文档

4. **文档清理**:
   - 定期检查文档是否过时
   - 将过时文档移至归档或删除

---

## 💻 代码维护

### 代码组织

#### 目录结构
```
Lee_Scripts/
├── Items/              # Items 操作脚本
│   └── ItemFunctions/  # Items 功能模块
├── Tracks/             # Tracks 操作脚本
├── Takes/              # Takes 操作脚本
├── Markers/            # Markers 操作脚本
│   └── MarkerFunctions/# Marker 功能模块
├── Main/               # 主要工作流脚本
├── test/               # 测试脚本
│   └── Archive/        # 归档脚本
└── Doc/                # 文档目录
```

### 命名规范

#### 脚本文件命名
- **格式**: `Lee_[分类] - [功能描述].lua`
- **示例**: 
  - `Lee_Items - Split at Time Selection.lua`
  - `Lee_Markers - Workstation.lua`

#### 功能模块命名
- **格式**: `[序号]_[功能名称].lua`
- **示例**: 
  - `01_JumpToPreviousItem.lua`
  - `02_JumpToNextItem.lua`

### 代码质量

#### 代码规范
- 使用 2 空格缩进
- 函数和变量使用驼峰命名
- 添加必要的注释
- 保持代码简洁清晰

#### 测试流程
1. 新脚本在 `test/` 目录开发
2. 测试通过后移至对应分类目录
3. 更新 `README.md` 添加说明
4. 提交并推送

### 代码清理

#### 定期任务
- 检查未使用的脚本
- 合并重复功能
- 优化性能
- 更新注释

#### 归档规则
- 不再使用的脚本移至 `test/Archive/`
- 保留历史版本用于参考
- 在 README 中标注归档状态

---

## 🔄 版本管理

### 提交规范

#### 提交类型
- `feat:` - 新功能
- `fix:` - 修复 bug
- `docs:` - 文档更新
- `refactor:` - 代码重构
- `style:` - 代码格式调整
- `test:` - 测试相关

#### 提交频率
- 完成一个小功能就提交
- 不要积累太多修改再提交
- 每次提交保持逻辑独立

### 分支策略

#### 主分支
- `master` - 稳定版本
- `main` - GitHub 默认分支（与 master 同步）

#### 功能分支
- `feature/功能名称` - 新功能开发
- `fix/问题描述` - Bug 修复

### 版本标签

#### 标签命名
- 格式: `v1.0.0`
- 语义化版本: `主版本.次版本.修订版本`

#### 何时打标签
- 重要功能完成
- 重大版本发布
- 稳定版本发布

---

## 📅 定期任务

### 每周任务
- [ ] 检查未提交的修改
- [ ] 更新 README 中的脚本列表
- [ ] 检查文档是否需要更新

### 每月任务
- [ ] 清理测试目录
- [ ] 归档过时脚本
- [ ] 更新文档索引
- [ ] 检查代码质量

### 每季度任务
- [ ] 全面代码审查
- [ ] 优化项目结构
- [ ] 更新依赖和工具
- [ ] 备份重要数据

---

## 🛠️ 工具和资源

### 开发工具
- **编辑器**: Cursor / VS Code
- **版本控制**: Git
- **文档**: Markdown
- **脚本语言**: Lua

### 参考资源
- [REAPER 脚本开发文档](https://www.reaper.fm/sdk/js/js.php)
- [ReaImGui 文档](https://github.com/cfillion/reaimgui)
- [Git 官方文档](https://git-scm.com/doc)

### 项目资源
- **GitHub 仓库**: https://github.com/leeakun373/Lee_Reaper_Scripts
- **文档目录**: `Doc/`
- **版本控制指南**: `Doc/VERSION_CONTROL_GUIDE.md`

---

## 📋 检查清单

### 添加新脚本时
- [ ] 脚本命名符合规范
- [ ] 放在正确的分类目录
- [ ] 代码格式正确
- [ ] 添加必要的注释
- [ ] 更新 README.md
- [ ] 测试功能正常
- [ ] 提交并推送

### 修改现有脚本时
- [ ] 保持命名规范
- [ ] 更新相关文档
- [ ] 测试修改后的功能
- [ ] 提交并推送

### 更新文档时
- [ ] 更新 Doc/README.md 索引
- [ ] 保持文档结构清晰
- [ ] 使用 Markdown 格式
- [ ] 提交时使用 `docs:` 类型

---

## 🔗 相关文档

- [版本控制指南](VERSION_CONTROL_GUIDE.md)
- [文档索引](README.md)
- [项目 README](../README.md)

---

**最后更新**: 2024-11-18
**维护者**: Lee


