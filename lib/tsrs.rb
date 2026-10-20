# frozen_string_literal: true

require "json"

require_relative "tsrs/version"
require_relative "tsrs/errors"
require_relative "tsrs/backend"
require_relative "tsrs/options"
require_relative "tsrs/diagnostic"
require_relative "tsrs/diagnosed"
require_relative "tsrs/transpile_result"
require_relative "tsrs/check_result"
require_relative "tsrs/session"

begin
  major, minor, = RUBY_VERSION.split(".")
  require_relative "tsrs/#{major}.#{minor}/tsrs"
rescue LoadError
  require_relative "tsrs/tsrs"
end

module Tsrs
  #: (String, ?file_name: String?, ?report_diagnostics: bool, ?strict: bool, **untyped) -> Tsrs::TranspileResult
  def self.transpile(source, file_name: nil, report_diagnostics: true, strict: false, **compiler_options)
    payload = Backend.transpile(source, transpile_request(file_name, report_diagnostics, compiler_options))

    TranspileResult.from_json(payload).validate!(strict: strict)
  end

  #: (String, ?file_name: String?, ?report_diagnostics: bool, ?strict: bool, **untyped) -> Tsrs::TranspileResult
  def self.transpile_declaration(source, file_name: nil, report_diagnostics: true, strict: false, **compiler_options)
    payload = Backend.transpile_declaration(source, transpile_request(file_name, report_diagnostics, compiler_options))

    TranspileResult.from_json(payload).validate!(strict: strict)
  end

  #: (*String, ?project: String?, ?cwd: String, **untyped) -> Tsrs::CheckResult
  def self.check(*files, project: nil, cwd: Dir.pwd, **compiler_options)
    compile(*files, project: project, cwd: cwd, no_emit: true, **compiler_options)
  end

  #: (*String, ?project: String?, ?cwd: String, **untyped) -> Tsrs::CheckResult
  def self.compile(*files, project: nil, cwd: Dir.pwd, **compiler_options)
    compiler_options = { ignore_config: true }.merge(compiler_options) if project.nil? && !files.empty?

    arguments = Options.arguments(compiler_options)

    arguments.push("--project", project.to_s) if project

    tsc(*arguments, *files.map(&:to_s), cwd: cwd)
  end

  #: (*String, ?cwd: String) -> Tsrs::CheckResult
  def self.tsc(*arguments, cwd: Dir.pwd)
    request = JSON.generate({ cwd: File.expand_path(cwd.to_s), args: arguments.map(&:to_s) })

    CheckResult.from_json(Backend.check(request))
  end

  #: () -> String
  def self.tsrs_version
    Backend.tsrs_version
  end

  #: () -> String
  def self.typescript_version
    Backend.typescript_version
  end

  #: (String?, bool, Hash[Symbol, untyped]) -> String
  def self.transpile_request(file_name, report_diagnostics, compiler_options)
    JSON.generate({
      fileName: file_name.to_s,
      args: Options.arguments(compiler_options),
      reportDiagnostics: report_diagnostics ? true : false,
    })
  end

  private_class_method :transpile_request
end
