use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::panic::{catch_unwind, AssertUnwindSafe};

mod check;
mod options;
mod result;
mod session;
mod status;
mod transpile;
mod worker;

use result::{TsrsErrorCode, TsrsResult};
use session::TsrsSession;

/// # Safety
///
/// `source` and `options_json` must be valid, nul-terminated UTF-8 strings.
#[no_mangle]
pub unsafe extern "C" fn tsrs_transpile(source: *const c_char, options_json: *const c_char) -> TsrsResult {
  transpile_with(source, options_json, false)
}

/// # Safety
///
/// `source` and `options_json` must be valid, nul-terminated UTF-8 strings.
#[no_mangle]
pub unsafe extern "C" fn tsrs_transpile_declaration(source: *const c_char, options_json: *const c_char) -> TsrsResult {
  transpile_with(source, options_json, true)
}

/// # Safety
///
/// `options_json` must be a valid, nul-terminated UTF-8 string.
#[no_mangle]
pub unsafe extern "C" fn tsrs_check(options_json: *const c_char) -> TsrsResult {
  let Some(options) = borrow(options_json) else {
    return TsrsResult::error(TsrsErrorCode::Encoding, "options were not valid UTF-8");
  };

  let options = options.to_string();

  guard(move || worker::run(move || check::check(options)))
}

/// # Safety
///
/// `cwd` must be a valid, nul-terminated UTF-8 string.
#[no_mangle]
pub unsafe extern "C" fn tsrs_session_new(cwd: *const c_char) -> *mut TsrsSession {
  let Some(cwd) = borrow(cwd) else {
    return std::ptr::null_mut();
  };

  let cwd = cwd.to_string();

  catch_unwind(AssertUnwindSafe(|| Box::into_raw(Box::new(session::new(&cwd))))).unwrap_or(std::ptr::null_mut())
}

/// Taken before a check that runs without the GVL, so that freeing the original meanwhile cannot free the session.
///
/// # Safety
///
/// `session` must be a live pointer from `tsrs_session_new` or `tsrs_session_retain`.
#[no_mangle]
pub unsafe extern "C" fn tsrs_session_retain(session: *const TsrsSession) -> *mut TsrsSession {
  match session.as_ref() {
    Some(session) => Box::into_raw(Box::new(session.retain())),
    None => std::ptr::null_mut(),
  }
}

/// # Safety
///
/// `session` must be a live pointer from `tsrs_session_new` or `tsrs_session_retain`, and `options_json` a valid,
/// nul-terminated UTF-8 string.
#[no_mangle]
pub unsafe extern "C" fn tsrs_session_check(session: *const TsrsSession, options_json: *const c_char) -> TsrsResult {
  let Some(session) = session.as_ref() else {
    return TsrsResult::error(TsrsErrorCode::Internal, "the session is gone");
  };

  let Some(options) = borrow(options_json) else {
    return TsrsResult::error(TsrsErrorCode::Encoding, "options were not valid UTF-8");
  };

  let options = options.to_string();
  let session = session.retain();

  guard(move || worker::run(move || session::check(&session, &options)))
}

/// The pointer stays valid until `tsrs_session_free`.
///
/// # Safety
///
/// `session` must be a live pointer from `tsrs_session_new` or `tsrs_session_retain`, or null.
#[no_mangle]
pub unsafe extern "C" fn tsrs_session_close(session: *const TsrsSession) {
  if let Some(session) = session.as_ref() {
    let _ = catch_unwind(AssertUnwindSafe(|| session.close()));
  }
}

/// # Safety
///
/// `session` must be a pointer from `tsrs_session_new` or `tsrs_session_retain` that is not used afterwards, or null.
#[no_mangle]
pub unsafe extern "C" fn tsrs_session_free(session: *mut TsrsSession) {
  if session.is_null() {
    return;
  }

  let _ = catch_unwind(AssertUnwindSafe(|| drop(Box::from_raw(session))));
}

#[no_mangle]
pub extern "C" fn tsrs_version() -> *mut c_char {
  into_c_string(env!("GEM_VERSION"))
}

#[no_mangle]
pub extern "C" fn tsrs_tsrs_version() -> *mut c_char {
  into_c_string(env!("TSRS_VERSION"))
}

#[no_mangle]
pub extern "C" fn tsrs_typescript_version() -> *mut c_char {
  into_c_string(tsrs_core::version())
}

/// # Safety
///
/// `value` must be a pointer this library returned, and must not be used afterwards.
#[no_mangle]
pub unsafe extern "C" fn tsrs_string_free(value: *mut c_char) {
  if value.is_null() {
    return;
  }

  drop(CString::from_raw(value));
}

/// # Safety
///
/// `result` must be one this library returned, and must not be used afterwards.
#[no_mangle]
pub unsafe extern "C" fn tsrs_result_free(result: TsrsResult) {
  if !result.value.is_null() {
    drop(CString::from_raw(result.value));
  }

  if !result.error.is_null() {
    drop(CString::from_raw(result.error));
  }
}

#[no_mangle]
pub extern "C" fn tsrs_panic_for_test() -> TsrsResult {
  let previous = std::panic::take_hook();

  std::panic::set_hook(Box::new(|_| {}));

  let caught = worker::run(|| -> TsrsResult { panic!("a deliberate panic") });

  std::panic::set_hook(previous);

  caught
}

unsafe fn transpile_with(source: *const c_char, options_json: *const c_char, declaration: bool) -> TsrsResult {
  let Some(source) = borrow(source) else {
    return TsrsResult::error(TsrsErrorCode::Encoding, "source was not valid UTF-8");
  };

  let Some(options) = borrow(options_json) else {
    return TsrsResult::error(TsrsErrorCode::Encoding, "options were not valid UTF-8");
  };

  let source = source.to_string();
  let options = options.to_string();

  guard(move || worker::run(move || transpile::transpile(source, options, declaration)))
}

fn guard(call: impl FnOnce() -> TsrsResult) -> TsrsResult {
  match catch_unwind(AssertUnwindSafe(call)) {
    Ok(result) => result,
    Err(payload) => TsrsResult::error(TsrsErrorCode::Panic, panic_message(&payload)),
  }
}

unsafe fn borrow<'a>(value: *const c_char) -> Option<&'a str> {
  if value.is_null() {
    return None;
  }

  CStr::from_ptr(value).to_str().ok()
}

pub(crate) fn panic_message(payload: &Box<dyn std::any::Any + Send>) -> String {
  payload
    .downcast_ref::<&str>()
    .map(|message| (*message).to_string())
    .or_else(|| payload.downcast_ref::<String>().cloned())
    .unwrap_or_else(|| "tsrs panicked".to_string())
}

fn into_c_string(value: &str) -> *mut c_char {
  CString::new(value)
    .unwrap_or_else(|_| CString::new("unknown").expect("a string with no interior nul"))
    .into_raw()
}
