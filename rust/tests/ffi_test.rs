use std::ffi::{CStr, CString};

use tsrs_ffi::{tsrs_check, tsrs_panic_for_test, tsrs_result_free, tsrs_transpile, tsrs_transpile_declaration};

fn text(pointer: *mut std::os::raw::c_char) -> Option<String> {
  (!pointer.is_null()).then(|| unsafe { CStr::from_ptr(pointer) }.to_string_lossy().into_owned())
}

fn transpile(source: &str, options: &str, declaration: bool) -> (Option<String>, Option<String>) {
  let source = CString::new(source).unwrap();
  let options = CString::new(options).unwrap();

  let result = unsafe {
    if declaration {
      tsrs_transpile_declaration(source.as_ptr(), options.as_ptr())
    } else {
      tsrs_transpile(source.as_ptr(), options.as_ptr())
    }
  };

  let outcome = (text(result.value), text(result.error));

  unsafe { tsrs_result_free(result) };

  outcome
}

#[test]
fn transpiles_typescript() {
  let (value, error) = transpile(
    "export const a: number = 1;",
    r#"{"args":["--target","es2020"]}"#,
    false,
  );

  assert_eq!(error, None);

  let payload: serde_json::Value = serde_json::from_str(&value.unwrap()).unwrap();

  assert_eq!(payload["code"], "export const a = 1;\n");
  assert_eq!(payload["map"], serde_json::Value::Null);
  assert_eq!(payload["diagnostics"], serde_json::json!([]));
}

#[test]
fn emits_declarations() {
  let (value, _) = transpile("export function f(a: number): string { return `${a}`; }", "{}", true);

  let payload: serde_json::Value = serde_json::from_str(&value.unwrap()).unwrap();

  assert_eq!(payload["code"], "export declare function f(a: number): string;\n");
}

#[test]
fn refuses_unknown_options() {
  let (value, error) = transpile("let a = 1", r#"{"args":["--nonsense"]}"#, false);

  assert_eq!(value, None);
  assert_eq!(error.as_deref(), Some("Unknown compiler option '--nonsense'."));
}

#[test]
fn refuses_unknown_request_fields() {
  let (_, error) = transpile("let a = 1", r#"{"nonsense":true}"#, false);

  assert!(error.is_some());
}

#[test]
fn checks_a_project() {
  let fixture = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../test/fixtures/broken");
  let request = serde_json::json!({ "cwd": fixture, "args": ["--noEmit"] }).to_string();
  let request = CString::new(request).unwrap();

  let result = unsafe { tsrs_check(request.as_ptr()) };
  let value = text(result.value).unwrap();

  unsafe { tsrs_result_free(result) };

  let payload: serde_json::Value = serde_json::from_str(&value).unwrap();
  let codes: Vec<i64> = payload["diagnostics"]
    .as_array()
    .unwrap()
    .iter()
    .map(|d| d["code"].as_i64().unwrap())
    .collect();

  assert_eq!(codes, vec![2322, 2554]);
  assert_eq!(
    payload["status"],
    serde_json::json!({ "code": 2, "name": "diagnostics_present_outputs_generated" })
  );
}

#[test]
fn catches_panics() {
  let result = tsrs_panic_for_test();
  let error = text(result.error);

  unsafe { tsrs_result_free(result) };

  assert_eq!(error.as_deref(), Some("a deliberate panic"));
}

#[test]
fn checks_a_project_in_a_session_again_and_again() {
  use tsrs_ffi::{tsrs_session_check, tsrs_session_close, tsrs_session_free, tsrs_session_new};

  let fixture = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../test/fixtures/broken");
  let cwd = CString::new(fixture.to_string_lossy().into_owned()).unwrap();
  let request = CString::new(r#"{"project":"tsconfig.json"}"#).unwrap();

  let session = unsafe { tsrs_session_new(cwd.as_ptr()) };

  assert!(!session.is_null());

  for _ in 0..3 {
    let result = unsafe { tsrs_session_check(session, request.as_ptr()) };
    let value = text(result.value).unwrap();

    unsafe { tsrs_result_free(result) };

    let payload: serde_json::Value = serde_json::from_str(&value).unwrap();
    let codes: Vec<i64> = payload["diagnostics"]
      .as_array()
      .unwrap()
      .iter()
      .map(|d| d["code"].as_i64().unwrap())
      .collect();

    assert_eq!(codes, vec![2322, 2554]);
  }

  unsafe { tsrs_session_close(session) };

  let result = unsafe { tsrs_session_check(session, request.as_ptr()) };
  let error = text(result.error);

  unsafe { tsrs_result_free(result) };
  unsafe { tsrs_session_free(session) };

  assert!(error.unwrap().contains("session is closed"));
}
