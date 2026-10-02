# 网站维护约定

这是 Hugo 网站，主题为 Git 子模块 `themes/hugo-ht`，中文/英文源稿分别位于 `content/cn`、`content/en`。正式网站为 https://yalinliu.org/，GitHub 为 WertherLiu/mysite，当前生产工作流程使用 main。

- 用户主要负责创作；接到“预览”“同步书籍”“发布”的请求后，主动执行对应工具并验证结果，无需让用户手动运行命令。
- 查看 Git 状态，区分当前任务与已有改动。保持作者语气、文章日期和 slug；不要自动更改 draft 状态来发布未指定的文章。
- 用项目级 layouts 和 static/css/custom.css 做主题定制；public 是构建输出。
- PowerShell 7 工作流：`pwsh -File scripts/site.ps1 -Action Check`；`-Action Preview` 启动包含草稿的本地预览。需要时用工具打开浏览器并检查相关页面。
- 书籍使用 `scripts/sync-book.ps1 -Source <源项目绝对路径> -BookId <稳定英文标识>`。脚本在临时副本中生成 HTML，替换该书的网站输出并保留旧文件备份。源项目路径由用户提供，不假定云端存在本地路径。
- 本地书籍路径登记在被 Git 忽略的 `books.local.json`。已登记书籍可只传 `-BookId`；用户说“亲密关系”时使用 `intimate-relationships`，不重复询问已有源稿位置。
- 用户说“发布某项内容”即授权在检查通过后提交和推送该项内容，无需重复确认。仅请求预览时不推送。
- 发布可用 `scripts/site.ps1 -Action Publish -Paths <明确的文件或目录列表> -Message <提交说明>`。脚本要求先处理所有未选中的改动和远端差异；遇到这些情况，检查并给出具体原因，不扩大提交范围，不强制推送。推送失败时保留本地提交，核对状态后重试，不重复提交。
- 推送成功不等于上线成功。查询对应提交的 Cloudflare 检查（例如 `gh api repos/WertherLiu/mysite/commits/<SHA>/check-runs`），并检查正式网址的目标页面。验证不了部署时明确报告“已推送，部署尚未验证”。
- `.site-work` 为本地构建及备份目录，被 Git 忽略。不要提交或发布它。源书稿需要另行备份。
