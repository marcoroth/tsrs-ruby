use serde::Deserialize;
use serde::Serialize;
use serde_json::value::RawValue;
use tsrs_api::{Handler, Response};
use tsrs_core::json::{JsonMap, Value};

use crate::options::{self, TranspileRequest};
use crate::result::{TsrsErrorCode, TsrsResult};

#[derive(Serialize)]
struct TranspilePayload {
  code: String,
  map: Option<String>,
  diagnostics: Box<RawValue>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ApiTranspileResponse {
  output_text: String,
  source_map_text: Option<String>,
  diagnostics: Option<Box<RawValue>>,
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

  let mut options = JsonMap::default();
  options.insert(
    "compilerOptions".to_string(),
    tsrs_tsoptions::gojson::compiler_options_to_go_json(&compiler_options),
  );
  options.insert("fileName".to_string(), Value::String(request.file_name.clone()));
  options.insert("reportDiagnostics".to_string(), Value::Bool(request.report_diagnostics));

  let mut params = JsonMap::default();
  params.insert("input".to_string(), Value::String(source.to_string()));
  params.insert("options".to_string(), Value::Object(options));
  let params = match tsrs_core::json::marshal(&Value::Object(params)) {
    Ok(params) => params,
    Err(error) => return TsrsResult::error(TsrsErrorCode::Internal, error),
  };

  let session = crate::session::new("/").session();
  let method = if declaration {
    "transpileDeclaration"
  } else {
    "transpileModule"
  };
  let response = match session.handle_request(method, params.as_bytes()) {
    Ok(Response::Json(response)) => response,
    Ok(Response::Binary(_)) => {
      return TsrsResult::error(TsrsErrorCode::Internal, "transpilation returned a binary response");
    }
    Err(error) => return TsrsResult::error(TsrsErrorCode::Transpile, error.to_string()),
  };

  let output: ApiTranspileResponse = match serde_json::from_str(&response) {
    Ok(output) => output,
    Err(error) => return TsrsResult::error(TsrsErrorCode::Internal, error.to_string()),
  };

  let payload = TranspilePayload {
    code: output.output_text,
    map: output.source_map_text.filter(|map| !map.is_empty()),
    diagnostics: output
      .diagnostics
      .unwrap_or_else(|| RawValue::from_string("[]".to_string()).expect("a valid empty JSON array")),
  };

  match serde_json::to_string(&payload) {
    Ok(json) => TsrsResult::value(json),
    Err(error) => TsrsResult::error(TsrsErrorCode::Internal, error.to_string()),
  }
}
