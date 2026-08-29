mod template;

pub use template::{
    Dialect, Finding, FindingCode, MAX_RENDERED_BYTES, MAX_TEMPLATE_BYTES, MAX_VALUE_BYTES,
    MAX_VARIABLES, Severity, TemplateReport, inspect_template,
};
