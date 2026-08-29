# Prompt Smith

[English](README.md)

> 状态：`v0.1.0-alpha.2` 发布候选。实现与发布元数据对应日期为 2026-08-29 的
> Alpha；只有 CI、Pages、Release 资产、checksum、SBOM 和 attestations 全部
> 验证后，公开发布才算完成。

Prompt Smith 是本地提示词模板预检工具。它在 prompt 进入 Agent 框架前发现缺失值、
未使用值、坏占位符和有歧义的字面花括号。

这个需求来自真实框架故障，包括
[LangChain #32702](https://github.com/langchain-ai/langchain/issues/32702) 和
[Langfuse #14721](https://github.com/langfuse/langfuse/issues/14721)。Prompt
Smith 不复制 Promptfoo、Langfuse 或模板注册平台；它无需账号、模型调用或服务器，
只完成一次严格检查和渲染。

## 支持语法

| 方言 | 变量 | 字面花括号 | 边界 |
|---|---|---|---|
| 简单双花括号 | `{{name}}` | 单花括号为普通文本 | Tinkora 变量替换语法 |
| LangChain f-string 子集 | `{name}` | `{{` 与 `}}` | 不支持位置、属性、索引、conversion、format 或嵌套字段 |

变量名匹配 `[A-Za-z_][A-Za-z0-9_]*`。渲染严格且不递归：每个被引用变量都必须
提供值，插入值不会再次作为模板语法解析。

## 浏览器工作流

页面通过 WebAssembly 运行 Rust core，并提供：

- 方言选择；
- 按首次出现顺序生成唯一变量字段；
- 带 severity 和字节偏移的稳定诊断；
- 严格本地渲染预览；
- 英文和中文界面；
- 复制和文本下载命令。

Pages 发布后，可在
[tinkora.github.io/prompt_smith](https://tinkora.github.io/prompt_smith/)
直接使用。

## 隐私与资源边界

- 模板和值只保存在浏览器内存。
- 同源资产加载完成后，应用不再发起运行时请求。
- 不调用 LLM、不执行模板代码、不读取环境变量、不持久化输入，也不提供云同步。
- 诊断不会包含变量值。

所有容量上限均包含边界值，并按 UTF-8 字节数计算。资源限制失败时不生成渲染预览。

| 边界 | 上限 | 失败契约 |
|---|---:|---|
| 模板 | 256 KiB | `template_too_large` 错误 |
| 模板中的唯一变量 | 200 | `too_many_variables` 错误 |
| 每个已提供值 | 256 KiB | `value_too_large` 错误，只包含变量名 |
| 传入 WASM 的 values JSON | 1 MiB 且对象最多 200 项 | 生成报告前返回 bridge 错误 |
| 渲染输出 | 1 MiB | `rendered_output_too_large` 错误，且不返回输出 |

Prompt Smith 不估算 token 或模型成本，不评价 prompt 质量，不提供 registry，也不
暴露 MCP tools。

## 本地开发

需要 Rust 1.85 或更新版本、`wasm32-unknown-unknown` target、
`wasm-pack 0.15` 和 Node.js 24。

```bash
cargo fmt --all -- --check
cargo test --workspace --locked
cargo clippy --workspace --all-targets --locked -- -D warnings
cargo check -p prompt_smith_web --target wasm32-unknown-unknown --locked

cd crates/prompt_smith_web
npm ci --ignore-scripts
npm run build:wasm
npm run test:wasm-smoke
```

手动查看已构建页面：

```bash
cd crates/prompt_smith_web/static
python3 -m http.server 8080 --bind 127.0.0.1
```

然后打开 `http://127.0.0.1:8080`。

## 文档

- [产品规格](docs/PRODUCT_SPEC.zh-CN.md)
- [贡献指南](CONTRIBUTING.md)
- [安全策略](SECURITY.md)
- [支持](SUPPORT.md)
- [变更记录](CHANGELOG.md)

## 支持 Tinkora

如果 Prompt Smith 节省了你的时间，可以通过
[Ko-fi](https://ko-fi.com/tinkora) 支持持续维护。赞助完全可选，不影响访问或
Issue 优先级。

## 许可证

MIT
