---
title: Yoke知识积累与落盘实现分析
author: 写作应用
digest: 拆解Yoke如何用.yoke文件系统做记忆：会话LMML、工作流、规则技能与Ragex知识图及落盘细节。
slug: yoke-knowledge
date: 2026-09-29
cover: content/assets/yoke-knowledge/cover.jpg

tags: [Yoke, Agent, Elixir, 知识管理]
need_open_comment: 0
only_fans_can_comment: 0

# 脚本回写，勿手填
# draft_media_id:
# thumb_media_id:
---

分析对象为 `https://yoke.yokerhood.com` 及其源码 `https://github.com/Oeditus/yoke`。结论一句话：Yoke 没有向量库，它的 knowledge 就是文件系统——`.yoke/` + `LMML` + `Ragex/dllb`，全部明文、可 diff、可进 git。

## 总览：五层记忆

Yoke 把短期会话记忆、中期项目规范、长期团队资产、流程记忆、代码语义图分开存，运行时再拼进 prompt：

```text
.yoke/sessions/<uuid>.lmml
.yoke/rules.json
.yoke/practices/<lang>.lmml + ~/.yoke/practices/<lang>.lmml
.yoke/skills/<name>/SKILL.md
.yoke/workflows/definitions/*.json + runs/<run-id>/...
project/workflow/{thoughts,backlog,active,completed,rejected}/*.md
project/lessons.md + project/scrap.md
.yoke/config.json + ~/.yoke/config.json
```

核心哲学是迭代闭环：`Observe -> Codify(rules/practices) -> Automate(workflow/plugin) -> Snapshot(把 .yoke/ commit)`，全队共享同一套 agent 标准。

## 短期记忆：Brain 不丢

`Yoke.Brain.Session` 是常驻 `GenServer`，`Hands(Executor)` 跑在隔离 `Task/Session` 进程。工具挂了只死子进程，`OTP Supervisor` 兜住，会话不丢。

落盘在 `lib/yoke/brain/session_store.ex`、`session_lmml.ex`、`session.ex`：

* 写触发：每次用户消息后的 `auto_checkpoint(pre-turn)`、每 turn 结束、`checkpoint/undo`、`handle_info({ref,result})` 都会 `save_session(state, cwd)`，内存 `snapshots` 只留 20 个。
* 无图写 `.yoke/sessions/<id>.lmml`，有 `images` 打包 `Lmml.Bundle.new_zip -> <id>.lmmlz` 并删旧 `.lmml`。失败走 `fallback_save -> <id>.json(pretty)` + `<id>.lmml_error.log` 记录 timestamp、model、消息数、快照数。
* 另有双 transcript：`<id>/transcript_full.jsonl` 全量，`transcript_compact.jsonl` 超过 500B 按字段递归截断为 `...[truncated]`，形如 `{timestamp,type,payload}`，写失败 `rescue -> :ok` 永不崩主流程。
* 读优先 `.lmmlz > .lmml > .json`，`list_sessions/list_session_metadata` 供 `/resume`、`/session list` 按 `updated_at` 排序，标题取首条 user 消息截 60 字。

## LMML 格式：人可读，机无损

`LMML` 是 Markdown 超集，见 `session_lmml.ex`：

```text
# Yoke Conversation: <id>
@@@manifest.json
{session_id,model,permission_mode,step_count,tokens,updated_at,snapshots}
@@@
## USER
可读正文
@@@message.0.json
原始消息JSON
@@@
```

`narrative` 只是视图，`decode` 只信 `embed`。`@@@` 会被转义为 `\u0040\u0040\u0040` 再写 embed，`JSON.decode` 自动还原，避免嵌套 `.lmml` 内容截断整个文件。`Bundle.new_text` 解析失败还有正则 `@@@name...@@@` 兜底解码。

## 长期显式知识：practices、rules、skills

三者都注入 `system prompt`，优先级 `project .yoke/ > ~/.yoke/ > 内置` 合并。

### practices：语言惯用法

`lib/yoke/practices.ex`，路径 `local .yoke/practices/<lang>.lmml` + `global ~/.yoke/practices/<lang>.lmml`。

* 解析 `Lmml.new_text -> narrative+manifest`，失败用正则提 `@@@manifest.json(.*?)@@@`，`items` 取 `-/*/1.` 列表行。
* `load` 合并 `uniq(global ++ local)`，`save(target=:both|:global|:local)` 经 `render_narrative` 双写。
* `/practices teach <lang>` 取范例仓 `lib/src/app` 下至多 12 文件各 60 行，调 `deepseek-chat` 提炼 5-10 条，无 key 用 `@default_practices`。新语言首次进目录自动问范例路径，回车即基线。
* `build_preamble` 按 `detect_languages(mix.exs/Cargo.toml/go.mod 等)` 拼 `### Good Practices for X`。

### rules：作用域前言

`lib/yoke/rules.ex`，文件 `.yoke/rules.json`，形如 `[{id,scope,text,enabled}]`。

缺文件播种默认四条：`all:引号精确引用`、`all:backtick为代码引用`、`all:Ragex优先于grep/sed`、`cr:80列换行`。`add_rule` 只认 `all|cr|review|commit|refactor|test:` 前缀，否则归 `all`；`add_scoped_rule` 给 workflow 任意 scope 用，自增 `max_id+1`。`build_preamble(ctx)` 拼 `all+ctx` 再加 practices 和 lessons。

### skills：模块化指令

`lib/yoke/skill/manager.ex`，三根 `roots=[project .yoke/skills, builtin .gemini/... , global ~/.yoke/skills]`。

* 每个技能即 `<name>/SKILL.md`，`YAML frontmatter(name/description)+body`，坏文件保留 `error` 字段不静默丢弃，同名高优先级赢并标 `shadowed_by`。
* 发现结果按 `{scope,dir,mtime}` 做 `ETS :yoke_skill_cache` 缓存，`/skills` 不反复扫盘。
* 执行时替换 `{{arg}}/{{arguments}}/$ARGUMENTS`，查找顺序精确、大小写不敏感、唯一前缀， miss 给 `did you mean`。`scaffold` 拒绝 `/../..` 和覆盖。

插件同理：实现 `Yoke.Plugin.Behaviour` 放 `.yoke/plugins/`，`/plugins reload` 热更不掉会话。

## 流程记忆：Workflow Engine

`lib/yoke/workflow/definition.ex + store.ex`。

定义三级 `workspace .yoke/workflows/definitions/ > global ~/.yoke/... > bundled(elixir)`，首次使用把内置 `elixir{branch,task_description,task_split,tests_and_docs,lint,commit}` 物化为工作区 JSON 并把 `default_rules` 去重种进 `rules.json<rules_scope>`。

运行全持久化，一个 run 一目录：

```text
runs/<workflow>-<ts>-<rand6>/
  workflow.json 冻结快照，后改定义不影响 resume
  state.json {run_id,workflow,status,step_index,branch,created,updated}
  transcript.jsonl 每 prompt、模型回包、确认、命令
  task_description.md / split_plan.json
  subtasks/<id>/{branch.txt,worktree.txt,session_id.txt,result.md}
  artifacts/lint_report.txt
```

并行靠 `git worktree + 独立 Session` 物理隔离，合并不上就停住留现场，手动解冲突再 `/workflow resume`。

## 战略记忆：Idea 生命周期

`lib/yoke/workflow_index.ex + sweep.ex + lessons.ex + scrap.ex`。

* 目录 `project/workflow/{thoughts,backlog,active,completed,rejected}/*.md`，无 `project/` 则 fallback `.yoke/workflow/`。`ensure_scaffold` 建目录并写 `.gitignore(_MAP.md/_DEPS.md)`。
* 文件 `---yaml(type/summary|/priority/depends_on)---body`，手写小 YAML 解析器支持 `k: v`、`[a,b]`、`|` 块、`-` 列表。
* `create_thought` 写 `YYYYMMDD_slug.md`，`promote=rm旧+encode_yaml写新`，`completed` 重打日期前缀。每次变更重生成 `thoughts/_MAP.md(Stage|Slug|Type|Priority|Summary)` 和 `_DEPS.md(Slug|Stage|Depends|RequiredBy逆算)`，`check_items` 查缺 `summary/priority` 和断链 `depends_on`。
* 收尾 `close_out_active=promote(completed)+Lessons.append_lesson`， lessons/scrap 都是 `mkdir_p + 空文件才加头 + - [date] entry` 追加，路径皆 `project/*.md ? .yoke/*.md`。
* `/sweep <tokens>` 同步扫四语料 `workflow/reference+docs/lessons/vault_root(ENV VAULT_ROOT|config.json)`，逐行大小写不敏感匹配，报 `file:line:content` 或 `!! NOT SEARCHED`，防重复造轮子。

## 代码知识图：Ragex + dllb

`/ragex` 挂载 MCP：`mcp_ragex_{grep,search_code,symbol_definition,symbol_references,metaast_search,structure,view,image_*}`，`SCIP 符号图 + AST` 存 Rust 写的 `dllb-server`，按项目持久索引，`/ragex stats/reindex/export` 维护。`rules` 默认即强制模型先用 Ragex 而非 `cat/grep`。

## 配置与杂项落盘

* `config.ex`：`Map.merge(default, global ~/.yoke/config.json, local .yoke/config.json)`，`tool_permissions` 单独合并；另读 `.yokerules/.yoke/rules.md/SYSTEM.md` 拼项目规则。
* `cli/line_editor.ex`：`~/.yoke/history` 逐行 Base64 追加，`Up/Down/Ctrl+R` 导航，剪贴板图存 `.yoke/sessions/assets/<ts>.<ext>` 并以 `@` 引用回 prompt。
* `session.ex:export` 写 `.yoke/exports/<id>.{json,md}`；`mcp/server_manager.ex` 从两级 `config.json` 读 `mcp_servers`。
