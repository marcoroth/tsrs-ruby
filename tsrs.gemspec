# frozen_string_literal: true

require_relative "lib/tsrs/version"

Gem::Specification.new do |spec|
  spec.name = "tsrs"
  spec.version = Tsrs::VERSION
  spec.authors = ["Marco Roth"]
  spec.email = ["marco.roth@intergga.ch"]

  spec.summary = "A drop-in replacement for the TypeScript 7 compiler and language server, written in Rust."
  spec.description = "Ruby bindings for tsrs, a drop-in replacement for the TypeScript 7 compiler and language server, written in Rust."
  spec.homepage = "https://github.com/marcoroth/tsrs-ruby"
  spec.licenses = ["MIT", "Apache-2.0"]
  spec.required_ruby_version = ">= 3.2.0"
  spec.require_paths = ["lib"]

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/marcoroth/tsrs-ruby"
  spec.metadata["changelog_uri"] = "https://github.com/marcoroth/tsrs-ruby/releases"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir[
    "tsrs.gemspec",
    "LICENSE.txt",
    "licenses/*.txt",
    "licenses/README.md",
    "README.md",
    "lib/**/*.rb",
    "sig/**/*.rbs",
    "ext/tsrs/extconf.rb",
    "ext/tsrs/tsrs.c",
    "ext/tsrs/include/**/*.h",
    "rust/Cargo.toml",
    "rust/Cargo.lock",
    "rust/build.rs",
    "rust/cbindgen.toml",
    "rust/rustfmt.toml",
    "rust/rust-toolchain.toml",
    "rust/.cargo/config.toml",
    "rust/src/**/*.rs"
  ]

  spec.extensions = ["ext/tsrs/extconf.rb"]
end
