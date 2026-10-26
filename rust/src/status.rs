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
      ExitStatus::DiagnosticsPresentOutputsSkipped => "diagnostics_present_outputs_skipped",
      ExitStatus::DiagnosticsPresentOutputsGenerated => "diagnostics_present_outputs_generated",
      ExitStatus::InvalidProjectOutputsSkipped => "invalid_project_outputs_skipped",
      ExitStatus::ProjectReferenceCycleOutputsSkipped => "project_reference_cycle_outputs_skipped",
      ExitStatus::NotImplemented => "not_implemented",
    };

    Status {
      code: status as i32,
      name,
    }
  }
}
