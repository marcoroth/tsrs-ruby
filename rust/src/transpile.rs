use serde::Serialize;
use serde_json::value::RawValue;

use crate::options::{self, TranspileRequest};
use crate::result::{TsrsErrorCode, TsrsResult};

#[derive(Serialize)]
struct TranspilePayload {
  code: String,
  map: Option<String>,
  diagnostics: Box<RawValue>,
}

pub fn transpile(source: String, request_json: String, declaration: bool) -> TsrsResult {
  let request: TranspileRequest = match serde_json::from_str(&request_json) {
    Ok(request) => request,
    Err(error) => return TsrsResult::error(TsrsErrorCode::Option, error.to_string()),
  };

  // Option parsing allocates in the thread's arena unless a region is entered.
  let region = tsrs_core::arena::Region::new(64 << 10);
  let outcome = {
    let _scope = region.enter();

    run(&source, &request, declaration)
  };
  drop(region);

  outcome
}

fn run(source: &str, request: &TranspileRequest, declaration: bool) -> TsrsResult {
  let compiler_options = match options::compiler_options(&request.args) {
    Ok(compiler_options) => compiler_options,
    Err(message) => return TsrsResult::error(TsrsErrorCode::Option, message),
  };

  let output = match tsrs_api::transpile::transpile(
    source,
    Some(&compiler_options),
    &request.file_name,
    request.report_diagnostics,
    declaration,
  ) {
    Ok(output) => output,
    Err(error) => return TsrsResult::error(TsrsErrorCode::Transpile, error.to_string()),
  };

  let diagnostics = tsrs_core::json::Value::Array(output.diagnostics);

  let diagnostics = match tsrs_core::json::marshal(&diagnostics).map(RawValue::from_string) {
    Ok(Ok(diagnostics)) => diagnostics,
    _ => return TsrsResult::error(TsrsErrorCode::Internal, "the diagnostics could not be serialized"),
  };

  let payload = TranspilePayload {
    code: output.output_text,
    map: (!output.source_map_text.is_empty()).then_some(output.source_map_text),
    diagnostics,
  };

  match serde_json::to_string(&payload) {
    Ok(json) => TsrsResult::value(json),
    Err(error) => TsrsResult::error(TsrsErrorCode::Internal, error.to_string()),
  }
}
