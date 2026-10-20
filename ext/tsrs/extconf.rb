# frozen_string_literal: true

require "mkmf"
require "fileutils"

ext_dir = __dir__
root_dir = File.expand_path("../..", ext_dir)

rust_dir = File.join(root_dir, "rust")

unless File.exist?(File.join(rust_dir, "Cargo.toml"))
  abort <<~MESSAGE

    ERROR: Rust sources not found at #{rust_dir}.

  MESSAGE
end

unless system("cargo --version > /dev/null 2>&1")
  abort <<~MESSAGE

    ERROR: Rust toolchain not found.

    tsrs requires the Rust toolchain to compile from source.

    Install Rust: https://rustup.rs

  MESSAGE
end

RUST_TARGETS = {
  "aarch64-linux-gnu" => "aarch64-unknown-linux-gnu",
  "aarch64-linux-musl" => "aarch64-unknown-linux-musl",
  "arm64-darwin" => "aarch64-apple-darwin",
  "x86_64-darwin" => "x86_64-apple-darwin",
  "x86_64-linux-gnu" => "x86_64-unknown-linux-gnu",
  "x86_64-linux-musl" => "x86_64-unknown-linux-musl",
}.freeze

cross_compiling = ENV.key?("RUBY_CC_VERSION")
target_platform = ENV.fetch("CARGO_BUILD_TARGET", nil)

if cross_compiling && target_platform.nil?
  rcd_platform = ENV.fetch("RCD_PLATFORM", "")
  target_platform = RUST_TARGETS[rcd_platform]

  if target_platform.nil?
    ruby_platform = RbConfig::CONFIG["arch"]
    target_platform = RUST_TARGETS.values.find { |target| ruby_platform.include?(target.split("-").first) }
  end
end

header_path = File.join(ext_dir, "include", "tsrs.h")

FileUtils.mkdir_p(File.dirname(header_path))

target_dir = File.join(rust_dir, "target")

if target_platform
  puts "tsrs: Cross-compiling Rust for target: #{target_platform}"

  system("cd #{rust_dir} && rustup target add #{target_platform}") || warn("tsrs: Failed to add Rust target #{target_platform}")

  cargo_args = "--release --locked --target #{target_platform}"
  lib_dir = File.join(target_dir, target_platform, "release")
else
  puts "tsrs: Compiling Rust library for native platform..."

  cargo_args = "--release --locked"
  lib_dir = File.join(target_dir, "release")
end

unless system("cd #{rust_dir} && cargo build #{cargo_args}")
  abort "ERROR: Failed to compile tsrs from Rust source."
end

unless File.exist?(header_path)
  abort "ERROR: cbindgen did not generate #{header_path}. Try `cargo clean` in #{rust_dir} and reinstall."
end

static_lib = File.join(lib_dir, "libtsrs_ffi.a")
developing = File.exist?(File.join(root_dir, ".git"))

if File.exist?(static_lib) && !developing
  vendored = File.join(ext_dir, "libtsrs_ffi.a")

  FileUtils.cp(static_lib, vendored)
  FileUtils.rm_rf(target_dir)

  puts "tsrs: Static library vendored at #{vendored}, Rust build directory removed"

  $LDFLAGS << " #{vendored}"
elsif File.exist?(static_lib)
  puts "tsrs: Static library found at #{static_lib}"

  $LDFLAGS << " #{static_lib}"
else
  host_os = target_platform || RbConfig::CONFIG["host_os"]

  lib_name = case host_os
             when /darwin/
               "libtsrs_ffi.dylib"
             when /mingw|mswin|windows/
               "tsrs_ffi.dll"
             else
               "libtsrs_ffi.so"
             end

  lib_path = File.join(lib_dir, lib_name)

  abort "ERROR: Shared library not found at #{lib_path}" unless File.exist?(lib_path)

  puts "tsrs: Shared library found at #{lib_path} (dynamic)"

  $LDFLAGS << " -L#{lib_dir} -ltsrs_ffi"
  $LDFLAGS << " -Wl,-rpath,#{lib_dir}" if RbConfig::CONFIG["host_os"].match?(/darwin|linux/)
end

$CFLAGS << " -I#{ext_dir}"

create_makefile("tsrs/tsrs")
