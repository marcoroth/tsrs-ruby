use std::env;
use std::fs;
use std::path::PathBuf;

fn main() {
  let crate_dir = env::var("CARGO_MANIFEST_DIR").unwrap();
  let header_path = PathBuf::from(&crate_dir).join("../ext/tsrs/include/tsrs.h");

  if let Ok(bindings) = cbindgen::generate(&crate_dir) {
    if let Some(parent) = header_path.parent() {
      let _ = std::fs::create_dir_all(parent);
    }

    bindings.write_to_file(&header_path);
  }

  let lock_path = PathBuf::from(&crate_dir).join("Cargo.lock");

  println!("cargo:rerun-if-changed={}", lock_path.display());

  println!(
    "cargo:rerun-if-changed={}",
    PathBuf::from(&crate_dir).join("src").display()
  );

  println!(
    "cargo:rerun-if-changed={}",
    PathBuf::from(&crate_dir).join("cbindgen.toml").display()
  );

  let version_rb_path = PathBuf::from(&crate_dir).join("../lib/tsrs/version.rb");

  println!("cargo:rerun-if-changed={}", version_rb_path.display());

  println!(
    "cargo:rustc-env=TSRS_VERSION={}",
    locked_version(&lock_path, "tsrs_api")
  );

  println!("cargo:rustc-env=GEM_VERSION={}", gem_version(&version_rb_path));
}

fn gem_version(version_rb_path: &PathBuf) -> String {
  let Ok(source) = fs::read_to_string(version_rb_path) else {
    return "unknown".to_string();
  };

  for line in source.lines() {
    let Some(rest) = line.trim().strip_prefix("VERSION = ") else {
      continue;
    };

    return rest.trim().trim_matches('"').to_string();
  }

  "unknown".to_string()
}

fn locked_version(lock_path: &PathBuf, package: &str) -> String {
  let Ok(lock) = fs::read_to_string(lock_path) else {
    return "unknown".to_string();
  };

  let mut lines = lock.lines();

  while let Some(line) = lines.next() {
    if line.trim() != format!("name = \"{package}\"") {
      continue;
    }

    if let Some(version) = lines.next().and_then(|next| next.trim().strip_prefix("version = ")) {
      return version.trim_matches('"').to_string();
    }
  }

  "unknown".to_string()
}
