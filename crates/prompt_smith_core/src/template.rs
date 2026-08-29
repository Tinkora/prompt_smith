use std::collections::{BTreeMap, BTreeSet};

use serde::{Deserialize, Serialize};

pub const MAX_TEMPLATE_BYTES: usize = 256 * 1024;
pub const MAX_VALUE_BYTES: usize = 256 * 1024;
pub const MAX_RENDERED_BYTES: usize = 1024 * 1024;
pub const MAX_VARIABLES: usize = 200;

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Dialect {
    SimpleDoubleBrace,
    LangchainFString,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Severity {
    Error,
    Warning,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum FindingCode {
    EmptyTemplate,
    TemplateTooLarge,
    TooManyVariables,
    UnmatchedOpeningBrace,
    UnmatchedClosingBrace,
    EmptyVariableName,
    InvalidVariableName,
    UnsupportedFormatFeature,
    LikelyLiteralBraces,
    MissingVariableValue,
    UnusedVariableValue,
    ValueTooLarge,
    RenderedOutputTooLarge,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct Finding {
    pub code: FindingCode,
    pub severity: Severity,
    pub offset: usize,
    pub variable: Option<String>,
    pub message: String,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct TemplateReport {
    pub dialect: Dialect,
    pub variables: Vec<String>,
    pub findings: Vec<Finding>,
    pub rendered: Option<String>,
}

impl TemplateReport {
    pub fn has_errors(&self) -> bool {
        self.findings
            .iter()
            .any(|finding| finding.severity == Severity::Error)
    }
}

#[derive(Clone, Debug)]
enum Segment {
    Literal(String),
    Variable(String),
}

#[derive(Clone, Debug)]
struct VariableOccurrence {
    name: String,
    offset: usize,
}

#[derive(Clone, Debug, Default)]
struct ParseResult {
    segments: Vec<Segment>,
    variables: Vec<VariableOccurrence>,
    findings: Vec<Finding>,
}

pub fn inspect_template(
    template: &str,
    dialect: Dialect,
    values: &BTreeMap<String, String>,
) -> TemplateReport {
    if template.len() > MAX_TEMPLATE_BYTES {
        return TemplateReport {
            dialect,
            variables: Vec::new(),
            findings: vec![finding(
                FindingCode::TemplateTooLarge,
                Severity::Error,
                MAX_TEMPLATE_BYTES,
                None,
                "template exceeds the 256 KiB input limit",
            )],
            rendered: None,
        };
    }
    if template.trim().is_empty() {
        return TemplateReport {
            dialect,
            variables: Vec::new(),
            findings: vec![finding(
                FindingCode::EmptyTemplate,
                Severity::Error,
                0,
                None,
                "template is empty or contains only whitespace",
            )],
            rendered: None,
        };
    }

    let mut parsed = match dialect {
        Dialect::SimpleDoubleBrace => parse_simple(template),
        Dialect::LangchainFString => parse_langchain(template),
    };

    let referenced_names: BTreeSet<String> = parsed
        .variables
        .iter()
        .map(|variable| variable.name.clone())
        .collect();
    if parsed.variables.len() > MAX_VARIABLES {
        parsed.findings.push(finding(
            FindingCode::TooManyVariables,
            Severity::Error,
            parsed.variables[MAX_VARIABLES].offset,
            None,
            "template exceeds the 200 unique variable limit",
        ));
        parsed.variables.truncate(MAX_VARIABLES);
    }

    for variable in &parsed.variables {
        if !values.contains_key(&variable.name) {
            parsed.findings.push(finding(
                FindingCode::MissingVariableValue,
                Severity::Error,
                variable.offset,
                Some(variable.name.clone()),
                "template variable has no supplied value",
            ));
        }
    }
    for name in values.keys() {
        if !referenced_names.contains(name) {
            parsed.findings.push(finding(
                FindingCode::UnusedVariableValue,
                Severity::Warning,
                0,
                Some(name.clone()),
                "supplied value is not referenced by the template",
            ));
        }
    }
    for (name, value) in values {
        if value.len() > MAX_VALUE_BYTES {
            parsed.findings.push(finding(
                FindingCode::ValueTooLarge,
                Severity::Error,
                0,
                Some(name.clone()),
                "supplied value exceeds the 256 KiB input limit",
            ));
        }
    }

    let has_errors = parsed
        .findings
        .iter()
        .any(|finding| finding.severity == Severity::Error);
    let rendered = if has_errors {
        None
    } else {
        match render_segments(&parsed.segments, values) {
            Some(rendered) => Some(rendered),
            None => {
                parsed.findings.push(finding(
                    FindingCode::RenderedOutputTooLarge,
                    Severity::Error,
                    0,
                    None,
                    "rendered output exceeds the 1 MiB limit",
                ));
                None
            }
        }
    };

    TemplateReport {
        dialect,
        variables: parsed
            .variables
            .into_iter()
            .map(|variable| variable.name)
            .collect(),
        findings: parsed.findings,
        rendered,
    }
}

fn parse_simple(template: &str) -> ParseResult {
    let bytes = template.as_bytes();
    let mut parsed = ParseResult::default();
    let mut seen = BTreeSet::new();
    let mut literal_start = 0;
    let mut index = 0;

    while index < bytes.len() {
        if pair_at(bytes, index, b'{') {
            push_literal_range(&mut parsed.segments, template, literal_start, index);
            let Some(close) = find_pair(bytes, index + 2, b'}') else {
                parsed.findings.push(finding(
                    FindingCode::UnmatchedOpeningBrace,
                    Severity::Error,
                    index,
                    None,
                    "opening double brace has no matching closing double brace",
                ));
                push_literal_range(&mut parsed.segments, template, index, bytes.len());
                return parsed;
            };
            let raw_name = &template[index + 2..close];
            let name = raw_name.trim_matches(|character: char| character.is_ascii_whitespace());
            let name_offset = index + 2 + (raw_name.len() - raw_name.trim_start().len());
            if name.is_empty() {
                parsed.findings.push(finding(
                    FindingCode::EmptyVariableName,
                    Severity::Error,
                    index,
                    None,
                    "placeholder has no variable name",
                ));
            } else if !valid_variable_name(name) {
                parsed.findings.push(finding(
                    FindingCode::InvalidVariableName,
                    Severity::Error,
                    name_offset,
                    None,
                    "variable name must match [A-Za-z_][A-Za-z0-9_]*",
                ));
            } else {
                parsed.segments.push(Segment::Variable(name.to_string()));
                record_variable(&mut parsed.variables, &mut seen, name, name_offset);
            }
            index = close + 2;
            literal_start = index;
        } else if pair_at(bytes, index, b'}') {
            push_literal_range(&mut parsed.segments, template, literal_start, index);
            parsed.findings.push(finding(
                FindingCode::UnmatchedClosingBrace,
                Severity::Error,
                index,
                None,
                "closing double brace has no matching opening double brace",
            ));
            push_literal_range(&mut parsed.segments, template, index, bytes.len());
            return parsed;
        } else {
            index += next_char_len(template, index);
        }
    }
    push_literal_range(&mut parsed.segments, template, literal_start, bytes.len());
    parsed
}

fn parse_langchain(template: &str) -> ParseResult {
    let bytes = template.as_bytes();
    let mut parsed = ParseResult::default();
    let mut seen = BTreeSet::new();
    let mut literal = String::new();
    let mut index = 0;

    while index < bytes.len() {
        if pair_at(bytes, index, b'{') {
            literal.push('{');
            index += 2;
            continue;
        }
        if pair_at(bytes, index, b'}') {
            literal.push('}');
            index += 2;
            continue;
        }
        if bytes[index] == b'{' {
            push_literal_string(&mut parsed.segments, &mut literal);
            let Some(close) = find_balanced_field_end(bytes, index) else {
                parsed.findings.push(finding(
                    FindingCode::UnmatchedOpeningBrace,
                    Severity::Error,
                    index,
                    None,
                    "opening brace has no matching closing brace",
                ));
                literal.push_str(&template[index..]);
                break;
            };
            let raw_name = &template[index + 1..close];
            let name = raw_name;
            let name_offset = index + 1;
            match classify_langchain_field(name) {
                FieldClassification::Variable => {
                    parsed.segments.push(Segment::Variable(name.to_string()));
                    record_variable(&mut parsed.variables, &mut seen, name, name_offset);
                }
                FieldClassification::Empty => parsed.findings.push(finding(
                    FindingCode::EmptyVariableName,
                    Severity::Error,
                    index,
                    None,
                    "replacement field has no variable name; escape literal braces as {{ and }}",
                )),
                FieldClassification::Invalid => parsed.findings.push(finding(
                    FindingCode::InvalidVariableName,
                    Severity::Error,
                    name_offset,
                    None,
                    "variable name is outside the supported LangChain subset",
                )),
                FieldClassification::Unsupported => parsed.findings.push(finding(
                    FindingCode::UnsupportedFormatFeature,
                    Severity::Error,
                    name_offset,
                    None,
                    "format specifiers, conversions, and nested fields are outside this release",
                )),
                FieldClassification::LikelyLiteral => parsed.findings.push(finding(
                    FindingCode::LikelyLiteralBraces,
                    Severity::Error,
                    index,
                    None,
                    "field looks like literal JSON or code; escape braces as {{ and }}",
                )),
            }
            index = close + 1;
            continue;
        }
        if bytes[index] == b'}' {
            push_literal_string(&mut parsed.segments, &mut literal);
            parsed.findings.push(finding(
                FindingCode::UnmatchedClosingBrace,
                Severity::Error,
                index,
                None,
                "closing brace has no matching opening brace",
            ));
            literal.push_str(&template[index..]);
            break;
        }

        let character = template[index..]
            .chars()
            .next()
            .expect("valid UTF-8 boundary");
        literal.push(character);
        index += character.len_utf8();
    }
    push_literal_string(&mut parsed.segments, &mut literal);
    parsed
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum FieldClassification {
    Variable,
    Empty,
    Invalid,
    Unsupported,
    LikelyLiteral,
}

fn classify_langchain_field(name: &str) -> FieldClassification {
    if name.is_empty() {
        return FieldClassification::Empty;
    }
    if valid_variable_name(name) {
        return FieldClassification::Variable;
    }
    if let Some((prefix, _)) = name.split_once([':', '!']) {
        if valid_variable_name(prefix) {
            return FieldClassification::Unsupported;
        }
    }
    if name.chars().all(|character| character.is_ascii_digit()) || name.contains(['.', '[', ']']) {
        return FieldClassification::Invalid;
    }
    if name.contains(['{', '}']) {
        let prefix = name.split([':', '!']).next().unwrap_or(name);
        if valid_variable_name(prefix) {
            return FieldClassification::Unsupported;
        }
    }
    FieldClassification::LikelyLiteral
}

fn render_segments(segments: &[Segment], values: &BTreeMap<String, String>) -> Option<String> {
    let mut rendered_bytes = 0usize;
    for segment in segments {
        let segment_bytes = match segment {
            Segment::Literal(value) => value.len(),
            Segment::Variable(name) => values.get(name)?.len(),
        };
        rendered_bytes = rendered_bytes.checked_add(segment_bytes)?;
        if rendered_bytes > MAX_RENDERED_BYTES {
            return None;
        }
    }

    let mut rendered = String::with_capacity(rendered_bytes);
    for segment in segments {
        match segment {
            Segment::Literal(value) => rendered.push_str(value),
            Segment::Variable(name) => rendered.push_str(values.get(name)?),
        }
    }
    Some(rendered)
}

fn record_variable(
    variables: &mut Vec<VariableOccurrence>,
    seen: &mut BTreeSet<String>,
    name: &str,
    offset: usize,
) {
    if seen.insert(name.to_string()) {
        variables.push(VariableOccurrence {
            name: name.to_string(),
            offset,
        });
    }
}

fn valid_variable_name(name: &str) -> bool {
    let mut characters = name.chars();
    matches!(characters.next(), Some(first) if first.is_ascii_alphabetic() || first == '_')
        && characters.all(|character| character.is_ascii_alphanumeric() || character == '_')
}

fn pair_at(bytes: &[u8], index: usize, byte: u8) -> bool {
    bytes.get(index) == Some(&byte) && bytes.get(index + 1) == Some(&byte)
}

fn find_pair(bytes: &[u8], start: usize, byte: u8) -> Option<usize> {
    (start..bytes.len().saturating_sub(1)).find(|index| pair_at(bytes, *index, byte))
}

fn find_balanced_field_end(bytes: &[u8], opening: usize) -> Option<usize> {
    let mut depth = 1usize;
    for (index, byte) in bytes.iter().enumerate().skip(opening + 1) {
        match byte {
            b'{' => depth += 1,
            b'}' => {
                depth -= 1;
                if depth == 0 {
                    return Some(index);
                }
            }
            _ => {}
        }
    }
    None
}

fn next_char_len(value: &str, index: usize) -> usize {
    value[index..]
        .chars()
        .next()
        .map(char::len_utf8)
        .unwrap_or(1)
}

fn push_literal_range(segments: &mut Vec<Segment>, source: &str, start: usize, end: usize) {
    if start < end {
        segments.push(Segment::Literal(source[start..end].to_string()));
    }
}

fn push_literal_string(segments: &mut Vec<Segment>, literal: &mut String) {
    if !literal.is_empty() {
        segments.push(Segment::Literal(std::mem::take(literal)));
    }
}

fn finding(
    code: FindingCode,
    severity: Severity,
    offset: usize,
    variable: Option<String>,
    message: &str,
) -> Finding {
    Finding {
        code,
        severity,
        offset,
        variable,
        message: message.to_string(),
    }
}
