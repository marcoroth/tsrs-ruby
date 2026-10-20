use std::io::Write;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use serde::Serialize;
use serde_json::value::RawValue;
use tsrs_ast::Diagnostic;
use tsrs_core::{tspath, P};
use tsrs_execute::tsc::{ReadWriteCloser, System};
use tsrs_vfs::{bundled, osvfs, FS};

use crate::options::CheckRequest;
use crate::result::{TsrsErrorCode, TsrsResult};
use crate::status::Status;

#[derive(Serialize)]
struct CheckPayload {
  status: Status,
  output: String,
  diagnostics: Box<RawValue>,
}

struct RubySys {
  output: Mutex<String>,
  sink: Box<dyn Fn(P<Diagnostic>) + Send + Sync>,
  fs: Arc<dyn FS>,
  default_library_path: String,
  cwd: String,
  start: Instant,
}

impl System for RubySys {
  fn fs(&self) -> Arc<dyn FS> {
    Arc::clone(&self.fs)
  }

  fn default_library_path(&self) -> &str {
    &self.default_library_path
  }

  fn get_current_directory(&self) -> &str {
    &self.cwd
  }

  fn write(&self, text: &str) {
    if let Ok(mut output) = self.output.lock() {
      output.push_str(text);
    }
  }

  fn flush(&self) {}

  fn write_output_is_tty(&self) -> bool {
    false
  }

  fn get_environment_variable(&self, name: &str) -> Option<String> {
    std::env::var(name).ok()
  }

  fn spawn(
    &self,
    command: &[String],
    dir: &str,
    stderr: Option<Box<dyn Write + Send>>,
  ) -> Result<ReadWriteCloser, String> {
    tsrs_contentmapper::spawn_process(command, dir, stderr)
  }

  fn now(&self) -> Instant {
    Instant::now()
  }

  fn since_start(&self) -> Duration {
    self.start.elapsed()
  }

  fn diagnostic_sink(&self) -> Option<&(dyn Fn(P<Diagnostic>) + Sync)> {
    Some(&*self.sink as &(dyn Fn(P<Diagnostic>) + Sync))
  }
}

pub fn check(request_json: String) -> TsrsResult {
  let request: CheckRequest = match serde_json::from_str(&request_json) {
    Ok(request) => request,
    Err(error) => return TsrsResult::error(TsrsErrorCode::Option, error.to_string()),
  };

  if request.args.iter().any(|arg| is_build_flag(arg)) {
    return TsrsResult::error(TsrsErrorCode::Option, "build mode (--build) is not supported");
  }

  // The parsed command line keeps referring to the system, so it is leaked, as tsrs's CLI does.
  let collected: Arc<Mutex<Vec<P<Diagnostic>>>> = Arc::new(Mutex::new(Vec::new()));
  let sink_target = Arc::clone(&collected);

  let sys: &'static RubySys = Box::leak(Box::new(RubySys {
    output: Mutex::new(String::new()),
    sink: Box::new(move |diagnostic| {
      if let Ok(mut list) = sink_target.lock() {
        list.push(diagnostic);
      }
    }),
    fs: Arc::new(bundled::wrap_fs(osvfs::fs())),
    default_library_path: bundled::default_lib_path(),
    cwd: tspath::normalize_path(&request.cwd),
    start: Instant::now(),
  }));

  let result = tsrs_execute::execute::command_line(sys, request.args);

  let diagnostics = std::mem::take(&mut *collected.lock().unwrap_or_else(|poisoned| poisoned.into_inner()));
  let output = std::mem::take(&mut *sys.output.lock().unwrap_or_else(|poisoned| poisoned.into_inner()));

  let diagnostics = tsrs_api::diagnostics::diagnostic_responses(&diagnostics);

  let diagnostics = match tsrs_core::json::marshal(&diagnostics).map(RawValue::from_string) {
    Ok(Ok(diagnostics)) => diagnostics,
    _ => return TsrsResult::error(TsrsErrorCode::Internal, "the diagnostics could not be serialized"),
  };

  let payload = CheckPayload {
    status: result.status.into(),
    output,
    diagnostics,
  };

  match serde_json::to_string(&payload) {
    Ok(json) => TsrsResult::value(json),
    Err(error) => TsrsResult::error(TsrsErrorCode::Internal, error.to_string()),
  }
}

fn is_build_flag(arg: &str) -> bool {
  matches!(arg.to_lowercase().as_str(), "-b" | "--b" | "-build" | "--build")
}
