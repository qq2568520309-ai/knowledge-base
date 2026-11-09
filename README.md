# 我的知识库

基于 [Material for MkDocs](https://squidfunk.github.io/mkdocs-material/) 的个人知识库模板：
Markdown 写内容，GitHub Actions 自动构建，GitHub Pages 免费托管。

## 本地运行

Windows 用户直接双击 **`启动预览.bat`**（首次会自动建环境装依赖），浏览器打开
`http://127.0.0.1:8000/knowledge-base/` 即可。

手动方式：

```bash
python -m venv .venv
# Windows
.\.venv\Scripts\Activate.ps1
# macOS / Linux
source .venv/bin/activate

pip install -r requirements.txt
mkdocs serve          # http://127.0.0.1:8000
```

构建静态文件到 `site/`：

```bash
mkdocs build --strict
```

## 目录说明

```
.
├── mkdocs.yml                  # 站点配置：导航 / 主题 / 插件 / Markdown 扩展
├── requirements.txt            # Python 依赖
├── docs/
│   ├── index.md                # 首页
│   ├── guide/                  # 使用指南分区
│   ├── cpp/                    # C++ 知识集（基础 → 进阶 → 面试）
│   ├── blog/
│   │   ├── index.md            # 博客列表页（由 blog 插件填充）
│   │   └── posts/              # 博客文章，文件名即 URL
│   ├── tags.md                 # 标签索引页
│   ├── javascripts/mathjax.js  # 数学公式支持
│   └── stylesheets/extra.css   # 自定义样式
└── .github/workflows/deploy.yml  # 推送到 main 后自动部署
```

## 发布

1. GitHub 新建**公开**仓库，推上去
2. **Settings → Pages → Source** 选 **GitHub Actions**
3. 之后每次 `git push` 到 `main` 都会自动重建站点

详细步骤见 `docs/guide/deploy.md`。

## 上线前要改的地方

| 位置 | 改什么 |
| --- | --- |
| `mkdocs.yml` → `site_name` | 站点名 |
| `mkdocs.yml` → `site_url` | `https://<用户名>.github.io/<仓库名>/`，结尾斜杠 |
| `mkdocs.yml` → `repo_url` / `repo_name` | 你的仓库地址 |
| `mkdocs.yml` → `site_author` / `copyright` / `extra.social` | 署名与社交链接 |

## 许可

内容归你自己；模板部分可随意取用。
