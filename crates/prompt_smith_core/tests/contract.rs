use std::collections::BTreeMap;

use prompt_smith_core::{
    Dialect, FindingCode, MAX_RENDERED_BYTES, MAX_TEMPLATE_BYTES, MAX_VALUE_BYTES, MAX_VARIABLES,
    Severity, inspect_template,
};

fn values(entries: &[(&str, &str)]) -> BTreeMap<String, String> {
    entries
        .iter()
        .map(|(name, value)| ((*name).to_string(), (*value).to_string()))
        .collect()
}

#[test]
fn simple_double_brace_detects_unique_variables_and_renders_once() {
    let report = inspect_template(
        "Hello {{ name }}. {{name}} asked for {{task}}.",
        Dialect::SimpleDoubleBrace,
        &values(&[("name", "{{task}}"), ("task", "a review")]),
    );

    assert_eq!(report.variables, ["name", "task"]);
    assert!(report.findings.is_empty());
    assert_eq!(
        report.rendered.as_deref(),
        Some("Hello {{task}}. {{task}} asked for a review.")
    );
}

#[test]
fn langchain_subset_renders_named_fields_and_escaped_literal_braces() {
    let report = inspect_template(
        r#"Return {{"status": "ok"}} for {name}."#,
        Dialect::LangchainFString,
        &values(&[("name", "Ada")]),
    );

    assert_eq!(report.variables, ["name"]);
    assert!(report.findings.is_empty());
    assert_eq!(
        report.rendered.as_deref(),
        Some(r#"Return {"status": "ok"} for Ada."#)
    );
}

#[test]
fn langchain_subset_flags_likely_literal_json_without_echoing_values() {
    let secret = "never-print-this";
    let report = inspect_template(
        r#"Return {"status": "ok"} for {name}."#,
        Dialect::LangchainFString,
        &values(&[("name", secret)]),
    );

    assert!(report.rendered.is_none());
    assert!(report.findings.iter().any(|finding| {
        finding.code == FindingCode::LikelyLiteralBraces
            && finding.severity == Severity::Error
            && finding.offset == 7
    }));
    assert!(
        !serde_json::to_string(&report)
            .expect("serialize report")
            .contains(secret)
    );
}

#[test]
fn missing_and_unused_values_have_stable_diagnostics() {
    let report = inspect_template(
        "{{required}}",
        Dialect::SimpleDoubleBrace,
        &values(&[("unused", "private-value")]),
    );

    assert!(report.rendered.is_none());
    assert!(report.findings.iter().any(|finding| {
        finding.code == FindingCode::MissingVariableValue
            && finding.variable.as_deref() == Some("required")
    }));
    assert!(report.findings.iter().any(|finding| {
        finding.code == FindingCode::UnusedVariableValue
            && finding.severity == Severity::Warning
            && finding.variable.as_deref() == Some("unused")
    }));
    assert!(
        !serde_json::to_string(&report)
            .expect("serialize report")
            .contains("private-value")
    );
}

#[test]
fn malformed_and_unsupported_fields_are_reported() {
    let cases = [
        (
            "Hello {{name",
            Dialect::SimpleDoubleBrace,
            FindingCode::UnmatchedOpeningBrace,
        ),
        (
            "Hello {{not-valid}}",
            Dialect::SimpleDoubleBrace,
            FindingCode::InvalidVariableName,
        ),
        (
            "Hello {}",
            Dialect::LangchainFString,
            FindingCode::EmptyVariableName,
        ),
        (
            "Hello {user.name}",
            Dialect::LangchainFString,
            FindingCode::InvalidVariableName,
        ),
        (
            "Hello { name }",
            Dialect::LangchainFString,
            FindingCode::LikelyLiteralBraces,
        ),
        (
            "Hello {amount:.2f}",
            Dialect::LangchainFString,
            FindingCode::UnsupportedFormatFeature,
        ),
        (
            "Hello name}",
            Dialect::LangchainFString,
            FindingCode::UnmatchedClosingBrace,
        ),
    ];

    for (template, dialect, code) in cases {
        let report = inspect_template(template, dialect, &BTreeMap::new());
        assert!(
            report.findings.iter().any(|finding| finding.code == code),
            "expected {code:?} for {template:?}"
        );
        assert!(report.rendered.is_none());
    }
}

#[test]
fn offsets_are_utf8_byte_offsets() {
    let report = inspect_template(
        "你好 {\"json\": 1}",
        Dialect::LangchainFString,
        &BTreeMap::new(),
    );

    let finding = report
        .findings
        .iter()
        .find(|finding| finding.code == FindingCode::LikelyLiteralBraces)
        .expect("literal brace finding");
    assert_eq!(finding.offset, "你好 ".len());
}

#[test]
fn template_and_variable_limits_are_enforced() {
    let oversized = "a".repeat(MAX_TEMPLATE_BYTES + 1);
    let oversized_report =
        inspect_template(&oversized, Dialect::SimpleDoubleBrace, &BTreeMap::new());
    assert!(oversized_report.findings.iter().any(|finding| {
        finding.code == FindingCode::TemplateTooLarge && finding.severity == Severity::Error
    }));
    let oversized_whitespace = " ".repeat(MAX_TEMPLATE_BYTES + 1);
    let whitespace_report = inspect_template(
        &oversized_whitespace,
        Dialect::SimpleDoubleBrace,
        &BTreeMap::new(),
    );
    assert_eq!(whitespace_report.findings.len(), 1);
    assert_eq!(
        whitespace_report.findings[0].code,
        FindingCode::TemplateTooLarge
    );

    let too_many = (0..=MAX_VARIABLES)
        .map(|index| format!("{{{{v{index}}}}}"))
        .collect::<String>();
    let variable_report = inspect_template(&too_many, Dialect::SimpleDoubleBrace, &BTreeMap::new());
    assert!(variable_report.findings.iter().any(|finding| {
        finding.code == FindingCode::TooManyVariables && finding.severity == Severity::Error
    }));
    assert_eq!(variable_report.variables.len(), MAX_VARIABLES);

    let supplied_last_variable = inspect_template(
        &too_many,
        Dialect::SimpleDoubleBrace,
        &values(&[("v200", "present")]),
    );
    assert!(!supplied_last_variable.findings.iter().any(|finding| {
        finding.code == FindingCode::UnusedVariableValue
            && finding.variable.as_deref() == Some("v200")
    }));
}

#[test]
fn empty_string_is_a_supplied_value() {
    let report = inspect_template(
        "Before{{value}}after",
        Dialect::SimpleDoubleBrace,
        &values(&[("value", "")]),
    );

    assert!(report.findings.is_empty());
    assert_eq!(report.rendered.as_deref(), Some("Beforeafter"));
}

#[test]
fn value_and_rendered_output_limits_fail_without_echoing_values() {
    let oversized_value = "private".repeat((MAX_VALUE_BYTES / "private".len()) + 1);
    let value_report = inspect_template(
        "{{value}}",
        Dialect::SimpleDoubleBrace,
        &values(&[("value", &oversized_value)]),
    );
    assert!(value_report.rendered.is_none());
    assert!(value_report.findings.iter().any(|finding| {
        finding.code == FindingCode::ValueTooLarge && finding.variable.as_deref() == Some("value")
    }));
    assert!(
        !serde_json::to_string(&value_report)
            .expect("serialize report")
            .contains(&oversized_value)
    );

    let placeholder = "{{value}}";
    let repeated = placeholder.repeat(MAX_TEMPLATE_BYTES / placeholder.len());
    let expansion = "x".repeat((MAX_RENDERED_BYTES / (MAX_TEMPLATE_BYTES / placeholder.len())) + 2);
    let output_report = inspect_template(
        &repeated,
        Dialect::SimpleDoubleBrace,
        &values(&[("value", &expansion)]),
    );
    assert!(output_report.rendered.is_none());
    assert!(
        output_report
            .findings
            .iter()
            .any(|finding| finding.code == FindingCode::RenderedOutputTooLarge)
    );
}
