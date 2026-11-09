# 配置说明

`mkdocs.yml` 是整站的大脑。下面按「你最可能改的」顺序解释这个仓库里的配置。

!!! tip "改完必须重启吗？"
    `mkdocs serve` 只对 `docs/` 里的内容热更新。改 `mkdocs.yml` 会自动重载配置，
    但新增插件、新增静态资源目录时，稳妥起见按 `Ctrl+C` 重跑一次。

## 基本信息

```yaml
site_name: 我的知识库                 # 浏览器标签、左上角标题
site_description: 个人知识管理        # SEO 描述
site_author: 你的名字
site_url: https://<用户名>.github.io/<仓库名>/   # 必须与实际部署地址一致，否则 sitemap 和分享卡片会错
repo_url: https://github.com/<用户名>/<仓库名>
edit_uri: edit/main/docs/            # 每页右上角「编辑此页」
```

!!! warning "`site_url` 是新手最常见的坑"
    GitHub Pages 项目站的地址形如 `https://用户名.github.io/仓库名/`，**结尾必须有斜杠**。
    写成 `https://用户名.github.io` 会导致静态资源 404。

## 主题与外观

```yaml
theme:
  name: material
  language: zh                # 界面按钮全中文
  palette: [...]              # 配色 + 深浅色切换
  features: [...]             # 各种交互开关
```

常用 `features`：

| 配置 | 效果 |
| --- | --- |
| `navigation.tabs` | 顶部出现一级导航栏 |
| `navigation.sections` | 侧边栏按分区折叠分组 |
| `navigation.instant` | 站内跳转不整页刷新，像 SPA |
| `navigation.top` | 右下角「回到顶部」 |
| `toc.follow` | 右侧目录随滚动高亮 |
| `search.suggest` | 搜索框实时联想 |
| `content.code.copy` | 代码块一键复制 |

### 换配色

Material 内置配色名：`red` `pink` `purple` `deep purple` `indigo` `blue` `light blue` `cyan` `teal` `green` `light green` `lime` `yellow` `amber` `orange` `deep orange` `brown` `grey` `blue grey` `black` `white`。

### 自定义 CSS

`docs/stylesheets/extra.css` 会被自动注入，可以微调字号、宽度、横幅等：

```css
.md-grid { max-width: 68rem; }        /* 页面最大宽度 */
```

## 插件

```yaml
plugins:
  - search: { lang: zh }     # 中文搜索分词
  - blog:                    # 内置博客系统
  - tags:                    # 标签页
```

- **search**：站点超过 100 页后建议开启 `separator` 或换用 `mkdocs-material` 的离线搜索优化。
- **blog**：把文章放进 `docs/blog/posts/`，写好 front matter 的 `date`、`categories`，博客首页自动聚合。
- **tags**：页面顶部的 front matter 写 `tags: [Docker, 运维]`，标签页自动汇总。

更多官方插件：`git-revision-date-localized`（页脚显示最后更新时间）、`minify`（压缩 HTML）、`redirect`（旧链接跳转）。装上之后在 `requirements.txt` 里固定版本。

## Markdown 扩展

`markdown_extensions` 决定了你能用哪些语法糖。这个仓库已开启：

- `admonition` / `pymdownx.details` → 提示块 `!!!` `???`
- `pymdownx.superfences` → 嵌套代码块、Mermaid
- `pymdownx.tabbed` → 标签页 `===`
- `pymdownx.highlight` + `inlinehilite` → 代码高亮
- `pymdownx.arithmatex` → 数学公式（需要 `extra_javascript` 里的 MathJax）
- `pymdownx.emoji` → `:material-xxx:` 图标
- `attr_list` / `md_in_html` → 给元素加属性、在 HTML 块里写 Markdown
- `toc` → 标题锚点

## 导航

```yaml
nav:
  - 首页: index.md
  - 使用指南:
      - guide/index.md
      - 三步上手: guide/quickstart.md
```

- 每个子项的路径**相对于 `docs/` 目录**。
- 只写文件名（`guide/index.md`）而不写标题时，页面自己的 H1 会被当作导航文字。
- 想给某个分区加一个「概览页」，把该分区的 `index.md` 放进同一层级，并开启 `navigation.indexes`。

## 严格模式

```bash
mkdocs build --strict
```

任何警告（死链、缺页、未引用文件）都算失败。CI 里建议开着，能把「链接写错」这类问题挡在上线前。

## 本地配置不提交

个人偏好可以写进 `mkdocs.local.yml` 之类的副本，用 `mkdocs serve -f mkdocs.local.yml` 跑，并把它加进 `.gitignore`。
