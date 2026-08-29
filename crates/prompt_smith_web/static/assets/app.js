import init, { inspect } from "../pkg/prompt_smith_web.js";

const messages = {
  en: {
    skip: "Skip to workspace",
    productLabel: "Template preflight",
    repository: "Repository",
    dialectLegend: "Template dialect",
    simpleDialect: "Simple {{variable}}",
    langchainDialect: "LangChain f-string subset",
    example: "Use example",
    reset: "Reset",
    source: "Source",
    templateHeading: "Prompt template",
    templateLabel: "Prompt template",
    inputs: "Inputs",
    variablesHeading: "Variables",
    result: "Result",
    resultHeading: "Preflight report",
    renderedLabel: "Rendered prompt",
    copy: "Copy output",
    download: "Download .txt",
    templatePlaceholder: "Enter a template...",
    noVariables: "No variables detected",
    valueFor: (name) => `Value for ${name}`,
    remove: "Remove",
    removeValue: (name) => `Remove value for ${name}`,
    variablePlaceholder: "Enter a value",
    ready: (count) => `Ready to use · ${count} variable${count === 1 ? "" : "s"}`,
    attention: (count) => `Needs attention · ${count} finding${count === 1 ? "" : "s"}`,
    byte: (offset) => `byte ${offset}`,
    copied: "Rendered prompt copied",
    copyFailed: "Clipboard access failed",
    downloaded: "Rendered prompt downloaded",
    resetDone: "Workspace reset",
    loadingFailed: "WASM initialization failed",
    inputLimit: "Input limits exceeded. Remove unused values or reduce the input size.",
  },
  zh: {
    skip: "跳到工作区",
    productLabel: "模板预检",
    repository: "代码仓库",
    dialectLegend: "模板方言",
    simpleDialect: "简单 {{变量}}",
    langchainDialect: "LangChain f-string 子集",
    example: "使用示例",
    reset: "重置",
    source: "模板",
    templateHeading: "提示词模板",
    templateLabel: "提示词模板",
    inputs: "输入",
    variablesHeading: "变量",
    result: "结果",
    resultHeading: "预检报告",
    renderedLabel: "渲染结果",
    copy: "复制结果",
    download: "下载 .txt",
    templatePlaceholder: "输入模板...",
    noVariables: "未检测到变量",
    valueFor: (name) => `${name} 的值`,
    remove: "移除",
    removeValue: (name) => `移除 ${name} 的值`,
    variablePlaceholder: "输入变量值",
    ready: (count) => `可以使用 · ${count} 个变量`,
    attention: (count) => `需要处理 · ${count} 项`,
    byte: (offset) => `字节 ${offset}`,
    copied: "已复制渲染结果",
    copyFailed: "无法访问剪贴板",
    downloaded: "已下载渲染结果",
    resetDone: "工作区已重置",
    loadingFailed: "WASM 初始化失败",
    inputLimit: "输入超过容量上限。请移除未使用值或缩小输入。",
  },
};

const findingMessages = {
  zh: {
    empty_template: "模板为空或只包含空白字符。",
    template_too_large: "模板超过 256 KiB 输入上限。",
    too_many_variables: "模板超过 200 个唯一变量的上限。",
    unmatched_opening_brace: "起始花括号没有匹配的结束花括号。",
    unmatched_closing_brace: "结束花括号没有匹配的起始花括号。",
    empty_variable_name: "占位符没有变量名。",
    invalid_variable_name: "变量名不在当前方言支持的范围内。",
    unsupported_format_feature: "当前版本不支持格式说明符、转换或嵌套字段。",
    likely_literal_braces: "该字段像 JSON 或代码字面量，请按当前方言转义花括号。",
    missing_variable_value: "模板变量尚未提供值。",
    unused_variable_value: "已提供的值没有被当前模板引用。",
    value_too_large: "变量值超过 256 KiB 输入上限。",
    rendered_output_too_large: "渲染结果超过 1 MiB 输出上限。",
  },
};

const templateInput = document.querySelector("#template-input");
const templateSize = document.querySelector("#template-size");
const variableCount = document.querySelector("#variable-count");
const variablesList = document.querySelector("#variables-list");
const findingsList = document.querySelector("#findings-list");
const renderedOutput = document.querySelector("#rendered-output");
const preflightStatus = document.querySelector("#preflight-status");
const preflightStatusText = document.querySelector("#preflight-status-text");
const copyButton = document.querySelector("#copy-button");
const downloadButton = document.querySelector("#download-button");
const localeToggle = document.querySelector("#locale-toggle");
const toast = document.querySelector("#toast");
const applicationStatus = document.querySelector("#application-status");

const state = {
  locale: "en",
  dialect: "simple_double_brace",
  values: new Map(),
  variableNames: null,
  report: null,
  bridgeError: false,
};

function text() {
  return messages[state.locale];
}

function valuesObject() {
  return Object.fromEntries(state.values.entries());
}

function inspectCurrentTemplate() {
  updateTemplateSize();
  try {
    state.report = JSON.parse(
      inspect(templateInput.value, state.dialect, JSON.stringify(valuesObject())),
    );
    state.bridgeError = false;
  } catch {
    state.bridgeError = true;
  }
  renderVariableFields();
  renderReport();
}

function updateTemplateSize() {
  templateSize.textContent = `${new TextEncoder().encode(templateInput.value).length} B`;
}

function renderVariableFields() {
  const activeNames = state.report?.variables ?? [];
  const activeSet = new Set(activeNames);
  const nextNames = [
    ...activeNames,
    ...[...state.values.keys()].filter((name) => !activeSet.has(name)),
  ];
  const nextSignatures = nextNames.map((name) => `${activeSet.has(name) ? "active" : "unused"}:${name}`);
  const namesChanged = state.variableNames === null
    || nextSignatures.length !== state.variableNames.length
    || nextSignatures.some((signature, index) => signature !== state.variableNames[index]);
  state.variableNames = nextSignatures;
  variableCount.textContent = String(activeNames.length);

  if (!namesChanged && variablesList.childElementCount > 0) {
    return;
  }

  variablesList.replaceChildren();
  if (nextNames.length === 0) {
    const empty = document.createElement("p");
    empty.className = "empty-state";
    empty.textContent = text().noVariables;
    variablesList.append(empty);
    return;
  }

  nextNames.forEach((name, index) => {
    const wrapper = document.createElement("div");
    wrapper.className = "variable-field";

    const heading = document.createElement("div");
    heading.className = "variable-field-heading";
    const label = document.createElement("label");
    const inputId = `variable-${index}`;
    label.htmlFor = inputId;
    label.setAttribute("data-variable-label", name);
    label.textContent = text().valueFor(name);

    const code = document.createElement("code");
    code.textContent = name;
    label.replaceChildren(document.createTextNode(`${text().valueFor(name)} · `), code);
    heading.append(label);

    if (!activeSet.has(name)) {
      const removeButton = document.createElement("button");
      removeButton.className = "button button-quiet remove-value-button";
      removeButton.type = "button";
      removeButton.textContent = text().remove;
      removeButton.setAttribute("aria-label", text().removeValue(name));
      removeButton.addEventListener("click", () => {
        state.values.delete(name);
        state.variableNames = null;
        inspectCurrentTemplate();
      });
      heading.append(removeButton);
    }

    const input = document.createElement("textarea");
    input.id = inputId;
    input.dataset.variable = name;
    input.value = state.values.get(name) ?? "";
    input.placeholder = text().variablePlaceholder;
    input.autocomplete = "off";
    input.spellcheck = false;
    input.addEventListener("input", () => {
      state.values.set(name, input.value);
      inspectCurrentTemplate();
    });

    wrapper.append(heading, input);
    variablesList.append(wrapper);
  });
}

function renderReport() {
  const report = state.report;
  if (state.bridgeError) {
    preflightStatus.classList.remove("ready");
    preflightStatusText.textContent = text().attention(1);
    findingsList.replaceChildren();

    const item = document.createElement("li");
    item.className = "finding error";
    const code = document.createElement("code");
    code.textContent = "INPUT_LIMIT";
    const message = document.createElement("p");
    message.className = "finding-message";
    message.textContent = text().inputLimit;
    item.append(code, message);
    findingsList.append(item);

    renderedOutput.value = "";
    copyButton.disabled = true;
    downloadButton.disabled = true;
    return;
  }
  const findings = report?.findings ?? [];
  const errors = findings.filter((finding) => finding.severity === "error");
  const ready = errors.length === 0 && report?.rendered !== null;

  preflightStatus.classList.toggle("ready", ready);
  preflightStatusText.textContent = ready
    ? text().ready(report.variables.length)
    : text().attention(findings.length);

  findingsList.replaceChildren();
  for (const finding of findings) {
    const item = document.createElement("li");
    item.className = `finding ${finding.severity}`;

    const code = document.createElement("code");
    code.textContent = finding.code.toUpperCase();
    const location = document.createElement("span");
    location.className = "finding-location";
    location.textContent = finding.variable
      ? `${finding.variable} · ${text().byte(finding.offset)}`
      : text().byte(finding.offset);
    const message = document.createElement("p");
    message.className = "finding-message";
    message.textContent = state.locale === "zh"
      ? findingMessages.zh[finding.code] ?? finding.message
      : finding.message;

    item.append(code, location, message);
    findingsList.append(item);
  }

  renderedOutput.value = report?.rendered ?? "";
  copyButton.disabled = !ready;
  downloadButton.disabled = !ready;
}

function applyLocale() {
  document.documentElement.lang = state.locale === "zh" ? "zh-CN" : "en";
  for (const element of document.querySelectorAll("[data-i18n]")) {
    element.textContent = text()[element.dataset.i18n];
  }
  templateInput.placeholder = text().templatePlaceholder;
  localeToggle.textContent = state.locale === "en" ? "中文" : "EN";
  localeToggle.setAttribute("aria-label", state.locale === "en" ? "切换到中文" : "Switch to English");
  applicationStatus.textContent = state.locale === "en" ? "Ready" : "就绪";
  renderedOutput.setAttribute("aria-label", text().renderedLabel);
  templateInput.setAttribute("aria-label", text().templateLabel);

  const preflightLabel = state.locale === "en" ? "Preflight result" : "预检结果";
  preflightStatus.setAttribute("aria-label", preflightLabel);
  renderVariableFields();
  renderReport();
}

let toastTimer;
function showToast(message) {
  toast.textContent = message;
  toast.classList.add("visible");
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => toast.classList.remove("visible"), 1800);
}

function useExample() {
  state.dialect = "simple_double_brace";
  document.querySelector('[name="dialect"][value="simple_double_brace"]').checked = true;
  templateInput.value = [
    "You are a {{role}}.",
    "Prepare a release checklist for {{audience}}.",
    "Return the result as {{format}}.",
  ].join("\n");
  state.values = new Map([
    ["role", "release engineer"],
    ["audience", "Agent maintainers"],
    ["format", "Markdown"],
  ]);
  state.variableNames = null;
  inspectCurrentTemplate();
}

function resetWorkspace() {
  templateInput.value = "";
  state.values.clear();
  state.variableNames = null;
  inspectCurrentTemplate();
  templateInput.focus();
  showToast(text().resetDone);
}

function downloadRenderedPrompt() {
  const blob = new Blob([renderedOutput.value], { type: "text/plain;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = "prompt.txt";
  link.click();
  URL.revokeObjectURL(url);
  showToast(text().downloaded);
}

templateInput.addEventListener("input", inspectCurrentTemplate);
for (const dialectInput of document.querySelectorAll('[name="dialect"]')) {
  dialectInput.addEventListener("change", () => {
    state.dialect = dialectInput.value;
    state.variableNames = null;
    inspectCurrentTemplate();
  });
}

document.querySelector("#example-button").addEventListener("click", useExample);
document.querySelector("#reset-button").addEventListener("click", resetWorkspace);
localeToggle.addEventListener("click", () => {
  state.locale = state.locale === "en" ? "zh" : "en";
  state.variableNames = null;
  applyLocale();
});
copyButton.addEventListener("click", async () => {
  try {
    await navigator.clipboard.writeText(renderedOutput.value);
    showToast(text().copied);
  } catch {
    showToast(text().copyFailed);
  }
});
downloadButton.addEventListener("click", downloadRenderedPrompt);

try {
  await init();
  inspectCurrentTemplate();
  applyLocale();
} catch (error) {
  applicationStatus.textContent = text().loadingFailed;
  applicationStatus.setAttribute("role", "alert");
  console.error(error);
}
