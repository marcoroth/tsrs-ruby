# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"

begin
  require "rake/extensiontask"
  require "rb_sys"

  PLATFORMS = [
    "aarch64-linux-gnu",
    "aarch64-linux-musl",
    "arm-linux-gnu",
    "arm-linux-musl",
    "arm64-darwin",
    "x86_64-darwin",
    "x86_64-linux-gnu",
    "x86_64-linux-musl"
  ].freeze

  RB_SYS_PLATFORM_MAP = {
    "aarch64-linux-gnu" => "aarch64-linux",
    "aarch64-linux-musl" => "aarch64-linux-musl",
    "arm-linux-gnu" => "arm-linux",
    "arm-linux-musl" => "arm-linux-musl",
    "arm64-darwin" => "arm64-darwin",
    "x86_64-darwin" => "x86_64-darwin",
    "x86_64-linux-gnu" => "x86_64-linux",
    "x86_64-linux-musl" => "x86_64-linux-musl",
  }.freeze

  RUST_TARGETS = {
    "aarch64-linux-gnu" => "aarch64-unknown-linux-gnu",
    "aarch64-linux-musl" => "aarch64-unknown-linux-musl",
    "arm-linux-gnu" => "armv7-unknown-linux-gnueabihf",
    "arm-linux-musl" => "armv7-unknown-linux-musleabihf",
    "arm64-darwin" => "aarch64-apple-darwin",
    "x86_64-darwin" => "x86_64-apple-darwin",
    "x86_64-linux-gnu" => "x86_64-unknown-linux-gnu",
    "x86_64-linux-musl" => "x86_64-unknown-linux-musl",
    "x86-linux-gnu" => "i686-unknown-linux-gnu",
    "x86-linux-musl" => "i686-unknown-linux-musl",
  }.freeze

  Rake::ExtensionTask.new do |ext|
    ext.name = "tsrs"
    ext.source_pattern = "*.{c,h}"
    ext.ext_dir = "ext/tsrs"
    ext.lib_dir = "lib/tsrs"
    ext.gem_spec = Gem::Specification.load("tsrs.gemspec")
    ext.cross_compile = true
    ext.cross_platform = PLATFORMS
  end

  desc "Build the Rust library for the native platform"
  task :cargo do
    Dir.chdir("rust") { sh "cargo build --release --locked" }

    FileUtils.rm_f(Dir.glob("tmp/*/tsrs/*/tsrs.{bundle,so}"))
  end

  Rake::Task["compile"].prerequisites.unshift("cargo")

  namespace "gem" do
    task "prepare" do
      require "rake_compiler_dock"

      sh "bundle config set cache_all true"

      gemspec_path = File.expand_path("./tsrs.gemspec", __dir__)
      spec = eval(File.read(gemspec_path), binding, gemspec_path) # rubocop:disable Security/Eval

      RakeCompilerDock.set_ruby_cc_version(spec.required_ruby_version.as_list)
    rescue LoadError
      abort "rake_compiler_dock is required for this task"
    end

    PLATFORMS.each do |platform|
      desc "Build all native binary gems in parallel"
      multitask "native" => platform

      desc "Build the native gem for #{platform}"
      task platform => "prepare" do
        rb_sys_platform = RB_SYS_PLATFORM_MAP.fetch(platform)
        rust_target = RUST_TARGETS.fetch(platform)

        linker_env = case rust_target
                     when /aarch64.*linux.*gnu/
                       "CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=aarch64-linux-gnu-gcc"
                     when /aarch64.*linux.*musl/
                       "CARGO_TARGET_AARCH64_UNKNOWN_LINUX_MUSL_LINKER=aarch64-linux-musl-gcc"
                     when /armv7.*gnueabihf/
                       "CARGO_TARGET_ARMV7_UNKNOWN_LINUX_GNUEABIHF_LINKER=arm-linux-gnueabihf-gcc"
                     when /armv7.*musleabihf/
                       "CARGO_TARGET_ARMV7_UNKNOWN_LINUX_MUSLEABIHF_LINKER=arm-linux-musleabihf-gcc"
                     else
                       ""
                     end

        RakeCompilerDock.sh(
          "(cd rust && rustup target add #{rust_target}) 2>/dev/null; " \
          "export #{linker_env}; " \
          "cd rust && cargo build --release --locked --target #{rust_target} && cd .. && " \
          "export RCD_PLATFORM=#{platform} && " \
          "bundle --local && rake native:#{platform} gem RUBY_CC_VERSION='#{ENV.fetch("RUBY_CC_VERSION", nil)}'",
          platform: platform,
          image: "rbsys/#{rb_sys_platform}:#{RbSys::VERSION}"
        )
      end
    end
  end
rescue LoadError => e
  warn "WARNING: Failed to load extension tasks: #{e.message}"

  desc "Compile task not available (rake-compiler not installed)"
  task :compile do
    abort "rake-compiler is required: #{e.message}\n\nRun: bundle install"
  end
end

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
end

begin
  require "rubocop/rake_task"

  RuboCop::RakeTask.new
rescue LoadError => e
  desc "RuboCop task not available (rubocop not installed)"
  task :rubocop do
    abort "rubocop is required: #{e.message}\n\nRun: bundle install"
  end
end

desc "Generate RBS signatures from the inline annotations"
task :rbs do
  sh "bundle exec rbs-inline --opt-out --output=sig/ lib/"
end

desc "Type check with Steep"
task :steep do
  sh "bundle exec steep check"
end

task test: :compile
task default: [:test, :rubocop, :steep]
