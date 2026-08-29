# Prompt Smith 产品规格

[English](PRODUCT_SPEC.md) | [简体中文](PRODUCT_SPEC.zh-CN.md)

## 目标

Prompt Smith 是浏览器本地的提示词模板变量契约预检与渲染工具。它帮助 Agent
开发者在运行时框架把 JSON、代码花括号或缺失值误判为变量之前，发现坏占位符、
缺失值、未使用值和字面花括号问题。

这个问题有重复公开证据：

- LangChain [#32702](https://github.com/langchain-ai/langchain/issues/32702)
  记录 JSON、代码占位符和空花括号导致 prompt 执行失败。
- Langfuse [#14721](https://github.com/langfuse/langfuse/issues/14721)
  记录空花括号与仅含空格的花括号绕过转义启发式后破坏 LangChain 模板。
- ScrapeGraphAI [#926](https://github.com/ScrapeGraphAI/Scrapegraph-ai/issues/926)
  和 [#931](https://github.com/ScrapeGraphAI/Scrapegraph-ai/issues/931) 显示同类
  missing-variable 故障已经影响示例工作流用户。
- LangChain [#30049](https://github.com/langchain-ai/langchain/issues/30049)
  显示模板组合后部分预填变量重新变成缺失变量。

LangChain 当前 `f-string` 实现使用 Python 的关键字专用 `StrictFormatter`，并在
格式化前验证变量。Prompt Smith 只对齐下述明确子集，不声明完整 LangChain 兼容。

## 替代方案与定位

- Promptfoo 已提供完整 prompt eval、provider、Nunjucks、测试矩阵和 CI；Prompt
  Smith 不复制该平台。
- LangChain 在 Python 应用内部验证模板；Prompt Smith 提供无需安装的浏览器预检。
- 通用 Mustache/Jinja 编辑器支持更丰富语言；Prompt Smith 不执行这些语言，也不
  接受不受信任的模板代码。

独立价值是一个小型、本地、诊断稳定且面向修复的 Agent prompt 契约检查器。

## 支持的方言

### 简单双花括号

- 占位符使用 `{{variable_name}}`。
- 忽略占位符内部两侧的 ASCII 空格。
- 名称必须匹配 `[A-Za-z_][A-Za-z0-9_]*`。
- 单花括号是普通文本。
- 这是 Tinkora 的变量替换子集，不是完整 Mustache 或 Nunjucks。

### LangChain f-string 子集

- 占位符使用 `{variable_name}`。
- `{{` 与 `}}` 渲染为字面花括号。
- 名称必须匹配 `[A-Za-z_][A-Za-z0-9_]*`。
- 本版本拒绝空字段、位置字段、属性/索引访问、conversion、format specifier 和
  嵌套 replacement field。
- 含引号、空格、JSON 标点或其他非名称内容的字段会收到字面花括号诊断和转义建议。

## 核心工作流

1. 选择方言并输入模板。
2. Prompt Smith 解析模板，按首次出现顺序列出唯一变量。
3. 在自动生成的字段中填写值。
4. 报告缺失值、未使用值、坏字段和花括号错误，且不在诊断中回显变量值。
5. 没有错误时，预览、复制或下载渲染后的 prompt。

## 稳定诊断边界

- `empty_template`
- `template_too_large`
- `too_many_variables`
- `unmatched_opening_brace`
- `unmatched_closing_brace`
- `empty_variable_name`
- `invalid_variable_name`
- `unsupported_format_feature`
- `likely_literal_braces`
- `missing_variable_value`
- `unused_variable_value`
- `value_too_large`
- `rendered_output_too_large`

诊断包含 severity、字节偏移、可选变量名和通用消息。诊断或 telemetry 都不能包含
变量值。

## 隐私与资源限制

- 通过 Rust/WASM 在浏览器内存中本地处理。
- 同源资产加载完成后，应用不发起运行时网络请求。
- 不调用 LLM、不执行模板代码、不展开环境变量、不持久化变量值，也不提供云同步。
- 渲染只执行一次非递归替换；插入值不会再次作为模板语法解析。

所有字节上限均包含边界值，并按 UTF-8 字节数计算。

| 边界 | 上限 | 失败语义 |
|---|---:|---|
| 模板 | 256 KiB | 返回 `template_too_large` 错误，不返回变量或渲染输出 |
| 模板中发现的唯一变量 | 200 | 返回 `too_many_variables` 错误，只公开前 200 个变量，且不渲染 |
| 每个已提供值，包括未使用值 | 256 KiB | 返回 `value_too_large` 错误，只包含变量名而不包含值，且不渲染 |
| WASM 边界的 values JSON | 1 MiB 且对象最多 200 项 | 生成 core 报告前拒绝；values 必须是字符串值组成的 JSON 对象 |
| 渲染输出 | 1 MiB | 返回 `rendered_output_too_large` 错误，且省略渲染输出 |

只有解析和变量值校验均未产生错误时，才检查渲染输出上限。包括
`unused_variable_value` 在内的 warning 不阻止渲染。

## 明确不做

- Token 数量或模型成本估算。
- Prompt eval、模型比较、red team 或 API 执行。
- 完整 Python formatting、Mustache、Nunjucks、Jinja、Handlebars 或 Liquid。
- 模板嵌套、循环、条件、filter、函数或任意代码。
- 在没有可执行实现和端到端集成测试前，不提供 MCP 或其他 Agent transport。

## 技术与命令

- Rust 1.85、edition 2024、提交 `Cargo.lock`。
- Rust core 与 `wasm-bindgen` 浏览器 bridge 共用契约。
- 静态 HTML/CSS/JavaScript 应用；无运行时框架或 CDN 依赖。

```bash
cargo fmt --all -- --check
cargo test --workspace --locked
cargo clippy --workspace --all-targets --locked -- -D warnings
cargo check -p prompt_smith_web --target wasm32-unknown-unknown --locked
npm --prefix crates/prompt_smith_web ci --ignore-scripts
npm --prefix crates/prompt_smith_web run build:wasm
npm --prefix crates/prompt_smith_web run test:wasm-smoke
ruby scripts/test_check_docs.rb
ruby scripts/check_docs.rb
```

## 项目结构

```text
crates/prompt_smith_core/  parser、诊断、渲染和原生测试
crates/prompt_smith_web/   WASM bridge 与浏览器应用
docs/                      双语产品规格
scripts/                   文档、浏览器和 Release 契约检查
.github/workflows/         CI、Pages、CodeQL 与 Release workflow
```

## 测试策略

- 原生结果测试覆盖两种方言、Unicode 字节偏移、坏花括号、重复变量、资源上限、
  缺失/未使用值和单次渲染。
- WASM 测试验证稳定 JSON 报告、bridge 输入限制、方言校验和变量值脱敏。
- 浏览器测试覆盖输入、方言切换、自动字段、诊断、复制/下载、键盘、console、
  accessibility，以及 375、768、1024、1440 像素的水平溢出。
- CI 检查 Rust 1.85、格式、Clippy、依赖策略、审计、Action 固定 SHA、文档链接和
  Release 契约。

## 成功标准

- 公开页面无需服务器即可完成编辑、检查、渲染全流程。
- 公开声明与支持子集一致，不暗示完整框架兼容。
- 英文 README/UI 为默认入口，并提供完整中文 README/规格链接。
- Package 元数据与 Release notes 保持对应 `v0.1.0-alpha.2`；只有 CI、Pages、
  checksum、SBOM、provenance 和 SBOM attestation 从 Release 资产独立验证后，
  才将该 Alpha 记录为已发布。
