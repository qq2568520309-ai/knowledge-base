# 使用指南

这一部分讲清楚三件事：本地怎么跑、内容怎么写、怎么发到公网。

| 章节 | 你会得到什么 |
| --- | --- |
| [三步上手](quickstart.md) | 本机预览环境，改一行字就能看到效果 |
| [常用语法速查](syntax.md) | 提示块、标签页、代码、图表、公式的写法 |
| [配置说明](config.md) | `mkdocs.yml` 常用项的解释 |
| [发布到 GitHub Pages](deploy.md) | 从建仓库到拿到网址的完整流程 |

!!! note "目录结构"
    ```
    knowledge-base/
    ├── mkdocs.yml          # 站点配置（导航、主题、插件）
    ├── requirements.txt    # Python 依赖
    ├── docs/               # 你写的所有 Markdown 都在这里
    │   ├── index.md        # 首页
    │   ├── guide/          # 一个分区 = 一个文件夹
    │   ├── blog/posts/     # 博客文章
    │   └── assets/         # 图片等静态资源
    └── .github/workflows/deploy.yml   # 自动部署
    ```
