use serde::Deserialize;
use tsrs_core::CompilerOptions;
use tsrs_tsoptions::ParseConfigHost;
use tsrs_vfs::FS;

#[derive(Deserialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct TranspileRequest {
  #[serde(default)]
  pub file_name: String,
  #[serde(default)]
  pub args: Vec<String>,
  #[serde(default = "yes")]
  pub report_diagnostics: bool,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct CheckRequest {
  pub cwd: String,
  #[serde(default)]
  pub args: Vec<String>,
}

fn yes() -> bool {
  true
}

struct OptionsHost;

impl ParseConfigHost for OptionsHost {
  fn fs(&self) -> &dyn FS {
    tsrs_vfs::osvfs::fs()
  }

  fn get_current_directory(&self) -> &str {
    "/"
  }
}

static OPTIONS_HOST: OptionsHost = OptionsHost;

pub fn compiler_options(args: &[String]) -> Result<CompilerOptions, String> {
  let parsed = tsrs_tsoptions::parse_command_line(args, &OPTIONS_HOST);

  if let Some(error) = parsed.errors.first() {
    return Err(error.localize());
  }

  if let Some(file) = parsed.file_names().first() {
    return Err(format!("{file:?} is a file name, not a compiler option"));
  }

  Ok(
    parsed
      .compiler_options()
      .map(|options| (*options).clone())
      .unwrap_or_default(),
  )
}
