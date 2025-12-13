# 版本控制指南

本指南说明如何对 Lee Scripts 项目进行版本管理和 Git 操作。

## 📚 目录

- [快速开始](#快速开始)
- [日常工作流](#日常工作流)
- [Git 基本命令](#git-基本命令)
- [Cursor AI 版本控制指南](#cursor-ai-版本控制指南)
- [常见问题](#常见问题)

---

## 🚀 快速开始

### 首次设置（已完成）

项目已经初始化并推送到 GitHub：
- **仓库地址**: https://github.com/leeakun373/Lee_Reaper_Scripts
- **本地路径**: `C:\Users\DELL\AppData\Roaming\REAPER\Scripts\Lee_Scripts`
- **远程分支**: `origin/master` 和 `origin/main`

### 检查当前状态

```bash
cd Lee_Scripts
git status          # 查看工作区状态
git log --oneline   # 查看提交历史
```

---

## 📝 日常工作流

### 1. 开发新功能或修改脚本

```bash
# 1. 确保在最新代码基础上工作
cd Lee_Scripts
git pull origin master

# 2. 创建新分支（可选，推荐用于大功能）
git checkout -b feature/新功能名称

# 3. 进行开发和修改...

# 4. 查看修改内容
git status
git diff

# 5. 添加修改的文件
git add .                    # 添加所有修改
# 或
git add 具体文件路径.lua     # 添加特定文件

# 6. 提交修改
git commit -m "描述你的修改内容"

# 7. 推送到远程仓库
git push origin master
# 或如果使用了分支
git push origin feature/新功能名称
```

### 2. 提交信息规范

使用清晰、简洁的提交信息：

**格式：**
```
类型: 简短描述

详细说明（可选）
```

**类型示例：**
- `feat:` - 新功能
- `fix:` - 修复bug
- `docs:` - 文档更新
- `refactor:` - 代码重构
- `style:` - 代码格式调整
- `test:` - 测试相关

**示例：**
```bash
git commit -m "feat: 添加新的 Marker 工作站功能"
git commit -m "fix: 修复 Items 分割脚本的边界问题"
git commit -m "docs: 更新 README 添加新脚本说明"
```

### 3. 同步远程仓库

```bash
# 拉取最新代码
git pull origin master

# 如果有冲突，解决后：
git add .
git commit -m "merge: 解决冲突"
git push origin master
```

---

## 🔧 Git 基本命令

### 查看状态和差异

```bash
git status                    # 查看工作区状态
git diff                      # 查看未暂存的修改
git diff --staged             # 查看已暂存的修改
git log --oneline             # 查看提交历史（简洁）
git log                       # 查看详细提交历史
```

### 撤销操作

```bash
# 撤销工作区的修改（未暂存）
git checkout -- 文件名

# 撤销已暂存但未提交的修改
git reset HEAD 文件名

# 修改最后一次提交（如果还没推送）
git commit --amend -m "新的提交信息"
```

### 分支操作

```bash
# 创建新分支
git checkout -b 分支名

# 切换分支
git checkout 分支名

# 查看所有分支
git branch -a

# 合并分支
git checkout master
git merge 分支名

# 删除分支
git branch -d 分支名
```

---

## 🤖 Cursor AI 版本控制指南

### 如何让 Cursor 帮助你进行版本控制

#### 1. 在 Cursor 中请求版本控制

你可以直接向 Cursor 请求：

```
"帮我提交这些修改并推送到 GitHub"
"查看当前的 Git 状态"
"创建一个新的提交，包含所有修改"
"帮我解决 Git 冲突"
```

#### 2. Cursor 会自动执行的操作

当你在 Cursor 中修改文件后，Cursor 可以：
- ✅ 检查 Git 状态
- ✅ 添加修改的文件
- ✅ 创建提交
- ✅ 推送到远程仓库

#### 3. 使用 .cursorrules 文件

项目根目录的 `.cursorrules` 文件已经配置了版本控制规则，Cursor 会自动遵循这些规则。

---

## ❓ 常见问题

### Q1: 如何查看我修改了哪些文件？

```bash
git status
```

### Q2: 如何查看具体的修改内容？

```bash
git diff                    # 查看所有未暂存的修改
git diff 文件名.lua         # 查看特定文件的修改
```

### Q3: 我不小心提交了错误的文件，怎么办？

```bash
# 如果还没推送
git reset --soft HEAD~1     # 撤销提交但保留修改
# 然后重新添加正确的文件并提交

# 如果已经推送了
git revert HEAD             # 创建一个新提交来撤销
```

### Q4: 如何回退到之前的版本？

```bash
# 查看提交历史
git log --oneline

# 回退到指定提交（保留修改）
git reset --soft 提交hash

# 回退到指定提交（丢弃修改）
git reset --hard 提交hash
```

### Q5: 推送时提示需要身份验证？

GitHub 现在要求使用 Personal Access Token (PAT) 而不是密码：

1. 访问 https://github.com/settings/tokens
2. 生成新的 token（选择 `repo` 权限）
3. 使用 token 作为密码进行推送

或者配置 SSH 密钥（推荐）：
```bash
# 生成 SSH 密钥
ssh-keygen -t ed25519 -C "your_email@example.com"

# 将公钥添加到 GitHub
# 然后修改远程地址为 SSH
git remote set-url origin git@github.com:leeakun373/Lee_Reaper_Scripts.git
```

### Q6: 如何忽略某些文件？

编辑 `.gitignore` 文件，添加要忽略的文件或目录：

```
# 示例
*.bak
临时文件/
.DS_Store
```

---

## 📋 最佳实践

1. **频繁提交**: 完成一个小功能就提交一次
2. **清晰的提交信息**: 让别人（和未来的你）能理解每次提交做了什么
3. **先拉取再推送**: 推送前先 `git pull` 确保同步
4. **使用分支**: 大功能开发使用独立分支
5. **定期备份**: 重要修改及时推送到远程仓库

---

## 🔗 相关资源

- [Git 官方文档](https://git-scm.com/doc)
- [GitHub 帮助文档](https://docs.github.com/)
- [项目 README](../README.md)
- [维护文档](MAINTENANCE.md)

---

**最后更新**: 2024-11-18


