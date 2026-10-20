use std::ffi::CString;
use std::os::raw::c_char;

#[repr(C)]
pub enum TsrsErrorCode {
  None = 0,
  Option,
  Encoding,
  Transpile,
  Check,
  Internal,
  Panic,
}

#[repr(C)]
pub struct TsrsResult {
  pub value: *mut c_char,
  pub value_len: usize,
  pub error: *mut c_char,
  pub code: TsrsErrorCode,
}

// SAFETY: the pointers are owned CStrings that nothing else refers to.
unsafe impl Send for TsrsResult {}

impl TsrsResult {
  pub fn value(payload: String) -> Self {
    let len = payload.len();

    match CString::new(payload) {
      Ok(value) => Self {
        value: value.into_raw(),
        value_len: len,
        error: std::ptr::null_mut(),
        code: TsrsErrorCode::None,
      },
      Err(_) => Self::error(TsrsErrorCode::Encoding, "the payload contained a null byte"),
    }
  }

  pub fn error(code: TsrsErrorCode, message: impl Into<String>) -> Self {
    let message = CString::new(message.into())
      .unwrap_or_else(|_| CString::new("an error with no printable message").expect("no interior nul"));

    Self {
      value: std::ptr::null_mut(),
      value_len: 0,
      error: message.into_raw(),
      code,
    }
  }
}
