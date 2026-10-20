use serde::Serialize;
use tsrs_execute::tsc::ExitStatus;

#[derive(Serialize)]
pub struct Status {
  code: i32,
  name: &'static str,
}

impl From<ExitStatus> for Status {
  fn from(status: ExitStatus) -> Self {
    let name = match status {
      ExitStatus::Success => "success",
      ExitStatus::DiagnosticsPresent_OutputsSkipped => "diagnostics_present_outputs_skipped",
      ExitStatus::DiagnosticsPresent_OutputsGenerated => "diagnostics_present_outputs_generated",
      ExitStatus::InvalidProject_OutputsSkipped => "invalid_project_outputs_skipped",
      ExitStatus::ProjectReferenceCycle_OutputsSkipped => "project_reference_cycle_outputs_skipped",
      ExitStatus::NotImplemented => "not_implemented",
    };

    Status {
      code: status as i32,
      name,
    }
  }
}
