use std::collections::BTreeMap;
use std::fmt;

use prompt_smith_core::{Dialect, MAX_VARIABLES, inspect_template};
use serde::de::{Error as _, MapAccess, Visitor};
use serde::{Deserialize, Deserializer};

pub const MAX_VALUES_JSON_BYTES: usize = 1024 * 1024;

const TOO_MANY_VALUES: &str = "values object exceeds the 200 entry limit";
const DUPLICATE_VALUES: &str = "values object contains duplicate keys";

struct StrictValues(BTreeMap<String, String>);

impl<'de> Deserialize<'de> for StrictValues {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        deserializer.deserialize_map(StrictValuesVisitor)
    }
}

struct StrictValuesVisitor;

impl<'de> Visitor<'de> for StrictValuesVisitor {
    type Value = StrictValues;

    fn expecting(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("a JSON object with unique string values")
    }

    fn visit_map<M>(self, mut map: M) -> Result<Self::Value, M::Error>
    where
        M: MapAccess<'de>,
    {
        let mut values = BTreeMap::new();
        let mut entries = 0usize;
        while let Some(name) = map.next_key::<String>()? {
            entries += 1;
            if entries > MAX_VARIABLES {
                return Err(M::Error::custom(TOO_MANY_VALUES));
            }
            if values.contains_key(&name) {
                return Err(M::Error::custom(DUPLICATE_VALUES));
            }
            values.insert(name, map.next_value::<String>()?);
        }
        Ok(StrictValues(values))
    }
}

pub fn inspect_json(template: &str, dialect: &str, values_json: &str) -> Result<String, String> {
    if values_json.len() > MAX_VALUES_JSON_BYTES {
        return Err("values JSON exceeds the 1 MiB input limit".to_string());
    }
    let dialect = match dialect {
        "simple_double_brace" => Dialect::SimpleDoubleBrace,
        "langchain_f_string" => Dialect::LangchainFString,
        _ => return Err("unsupported template dialect".to_string()),
    };
    let StrictValues(values) = serde_json::from_str(values_json).map_err(|error| {
        let message = error.to_string();
        if message.starts_with(TOO_MANY_VALUES) {
            TOO_MANY_VALUES.to_string()
        } else if message.starts_with(DUPLICATE_VALUES) {
            DUPLICATE_VALUES.to_string()
        } else {
            "values must be a JSON object of strings".to_string()
        }
    })?;
    serde_json::to_string(&inspect_template(template, dialect, &values))
        .map_err(|_| "cannot serialize template report".to_string())
}

#[cfg(target_arch = "wasm32")]
mod wasm {
    use wasm_bindgen::prelude::*;

    #[wasm_bindgen]
    pub fn inspect(template: &str, dialect: &str, values_json: &str) -> Result<String, JsValue> {
        super::inspect_json(template, dialect, values_json)
            .map_err(|message| JsValue::from(&message))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn serializes_the_shared_core_report() {
        let output = inspect_json("Hello {name}", "langchain_f_string", r#"{"name":"Ada"}"#)
            .expect("inspect template");
        let report: serde_json::Value = serde_json::from_str(&output).expect("report JSON");

        assert_eq!(report["variables"], serde_json::json!(["name"]));
        assert_eq!(report["rendered"], "Hello Ada");
    }

    #[test]
    fn rejects_unknown_dialects_and_non_string_values() {
        assert_eq!(
            inspect_json("Hello", "jinja2", "{}").expect_err("unsupported dialect"),
            "unsupported template dialect"
        );
        assert_eq!(
            inspect_json("Hello {name}", "langchain_f_string", r#"{"name":42}"#)
                .expect_err("invalid values"),
            "values must be a JSON object of strings"
        );
    }

    #[test]
    fn rejects_oversized_or_excessive_value_inputs() {
        let oversized = format!(r#"{{"name":"{}"}}"#, "x".repeat(MAX_VALUES_JSON_BYTES));
        assert_eq!(
            inspect_json("Hello {name}", "langchain_f_string", &oversized)
                .expect_err("oversized values JSON"),
            "values JSON exceeds the 1 MiB input limit"
        );

        let excessive = serde_json::to_string(
            &(0..=prompt_smith_core::MAX_VARIABLES)
                .map(|index| (format!("v{index}"), String::new()))
                .collect::<BTreeMap<_, _>>(),
        )
        .expect("serialize values");
        assert_eq!(
            inspect_json("Hello", "simple_double_brace", &excessive).expect_err("too many values"),
            "values object exceeds the 200 entry limit"
        );

        assert_eq!(
            inspect_json(
                "Hello",
                "simple_double_brace",
                r#"{"same":"first","same":"second"}"#
            )
            .expect_err("duplicate values"),
            "values object contains duplicate keys"
        );
    }

    #[test]
    fn does_not_echo_values_in_error_reports() {
        let secret = "never-print-this";
        let output = inspect_json(
            "{{required}}",
            "simple_double_brace",
            &format!(r#"{{"unused":"{secret}"}}"#),
        )
        .expect("inspect template");

        assert!(!output.contains(secret));
    }
}
