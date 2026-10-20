use std::sync::Arc;

use serde::{Deserialize, Serialize};
use serde_json::value::RawValue;
use tsrs_api::{Handler, Response, Session, SessionOptions};
use tsrs_core::context::{with_checker_lifetime, CheckerLifetime, Context};
use tsrs_core::json::Value;
use tsrs_core::tspath;
use tsrs_vfs::{bundled, osvfs, FS};

use tsrs_execute::tsc::ExitStatus;

use crate::result::{TsrsErrorCode, TsrsResult};
use crate::status::Status;

pub struct TsrsSession {
  session: Arc<Session>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct CheckRequest {
  project: String,
}

#[derive(Serialize)]
struct CheckPayload {
  status: Status,
  diagnostics: Box<RawValue>,
}

pub fn new(cwd: &str) -> TsrsSession {
  let fs: Arc<dyn FS> = Arc::new(bundled::wrap_fs(osvfs::fs()));

  let session = Session::new(SessionOptions::new(
    tspath::normalize_path(cwd),
    bundled::default_lib_path(),
    fs,
    false,
  ));

  TsrsSession { session }
}

impl TsrsSession {
  pub fn session(&self) -> Arc<Session> {
    Arc::clone(&self.session)
  }

  pub fn retain(&self) -> TsrsSession {
    TsrsSession {
      session: self.session(),
    }
  }

  pub fn close(&self) {
    self.session.close();
  }
}

pub fn check(session: &Session, request_json: &str) -> TsrsResult {
  let request: CheckRequest = match serde_json::from_str(request_json) {
    Ok(request) => request,
    Err(error) => return TsrsResult::error(TsrsErrorCode::Option, error.to_string()),
  };

  let project = tspath::get_normalized_absolute_path(&request.project, session.current_directory());
  let params = object("openProjects", Value::Array(vec![Value::String(project.clone())]));

  let created = match call(session, "createSnapshot", &params) {
    Ok(created) => created,
    Err(message) => return TsrsResult::error(TsrsErrorCode::Check, message),
  };

  let Some(snapshot) = number(field(&created, "snapshot")) else {
    return TsrsResult::error(TsrsErrorCode::Internal, "createSnapshot returned no snapshot");
  };

  let outcome = diagnostics(session, snapshot, &created, &project);

  let _ = call(session, "release", &object("snapshot", Value::Number(snapshot as f64)));

  match outcome {
    Ok((status, diagnostics)) => {
      let payload = CheckPayload {
        status: status.into(),
        diagnostics,
      };

      match serde_json::to_string(&payload) {
        Ok(json) => TsrsResult::value(json),
        Err(error) => TsrsResult::error(TsrsErrorCode::Internal, error.to_string()),
      }
    }
    Err(result) => result,
  }
}

fn diagnostics(
  session: &Session,
  snapshot: u64,
  created: &Value,
  project: &str,
) -> Result<(ExitStatus, Box<RawValue>), TsrsResult> {
  let id = project_id(created, project)
    .ok_or_else(|| TsrsResult::error(TsrsErrorCode::Check, format!("no project was loaded from {project}")))?;

  let data = session
    .snapshot_data(snapshot)
    .map_err(|error| TsrsResult::error(TsrsErrorCode::Internal, error.to_string()))?;

  let program = data
    .get_program(&tsrs_project::ID(id))
    .map_err(|error| TsrsResult::error(TsrsErrorCode::Check, error.to_string()))?;

  // As tsc collects them before emitting (tsrs_execute/src/tsc/emit.rs).
  let ctx = with_checker_lifetime(&Context::background(), CheckerLifetime::Diagnostics);
  let all = tsrs_compiler::get_diagnostics_of_any_program(
    &ctx,
    program,
    None,
    false,
    &mut |ctx, file| program.get_bind_diagnostics(ctx, file),
    &mut |ctx, file| program.get_semantic_diagnostics(ctx, file),
  );
  let all = tsrs_compiler::sort_and_deduplicate_diagnostics(&all);

  // tsc's rule (tsrs_execute/src/tsc/emit.rs) for a run that did not skip emitting, as with --noEmit.
  let status = if all.is_empty() {
    ExitStatus::Success
  } else {
    ExitStatus::DiagnosticsPresent_OutputsGenerated
  };

  let responses = tsrs_api::diagnostics::diagnostic_responses(&all);

  drop(all);
  drop(data);

  tsrs_core::json::marshal(&responses)
    .ok()
    .and_then(|json| RawValue::from_string(json).ok())
    .map(|diagnostics| (status, diagnostics))
    .ok_or_else(|| TsrsResult::error(TsrsErrorCode::Internal, "the diagnostics could not be serialized"))
}

// A snapshot also holds the projects this one references.
fn project_id(created: &Value, project: &str) -> Option<String> {
  let Value::Array(projects) = field(created, "projects")? else {
    return None;
  };

  projects
    .iter()
    .find(|candidate| matches!(field(candidate, "configFileName"), Some(Value::String(name)) if name == project))
    .or_else(|| projects.first())
    .and_then(|candidate| match field(candidate, "id") {
      Some(Value::String(id)) => Some(id.clone()),
      _ => None,
    })
}

fn call(session: &Session, method: &str, params: &Value) -> Result<Value, String> {
  let params = tsrs_core::json::marshal(params)?;

  match session.handle_request(method, params.as_bytes()) {
    Ok(Response::Json(text)) => tsrs_core::json::unmarshal(&text),
    Ok(Response::Binary(_)) => Err(format!("{method} returned a binary response")),
    Err(error) => Err(error.to_string()),
  }
}

fn object(key: &str, value: Value) -> Value {
  let mut map = tsrs_core::collections::OrderedMap::default();

  map.insert(key.to_string(), value);

  Value::Object(map)
}

fn field<'a>(value: &'a Value, key: &str) -> Option<&'a Value> {
  match value {
    Value::Object(object) => object.get(key),
    _ => None,
  }
}

fn number(value: Option<&Value>) -> Option<u64> {
  match value? {
    Value::Number(number) if *number >= 0.0 => Some(*number as u64),
    Value::Integer(number) => u64::try_from(*number).ok(),
    _ => None,
  }
}
