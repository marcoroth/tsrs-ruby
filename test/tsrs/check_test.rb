# frozen_string_literal: true

require "test_helper"

module Tsrs
  class CheckTest < Minitest::Spec
    def fixture(*path)
      File.expand_path(File.join("../fixtures", *path), __dir__)
    end

    test "a project with no errors succeeds" do
      result = Tsrs.check(cwd: fixture("project"))

      assert_instance_of CheckResult, result
      assert_equal 0, result.status
      assert_equal :success, result.exit_status
      assert_equal true, result.success?
      assert_equal [], result.diagnostics
    end

    test "reports type errors with where they are" do
      result = Tsrs.check(cwd: fixture("broken"))

      assert_equal false, result.success?
      assert_equal [2322, 2554], result.errors.map(&:code)

      first = result.errors.first

      assert_equal fixture("broken", "src", "index.ts"), first.file
      assert_equal [1, 7], [first.line, first.column]
      assert_equal "Type 'string' is not assignable to type 'number'.", first.message
    end

    test "finds the project from a tsconfig path" do
      result = Tsrs.check(project: fixture("broken", "tsconfig.json"))

      assert_equal [2322, 2554], result.errors.map(&:code)
    end

    test "checks a list of files, following their imports" do
      result = Tsrs.check(fixture("files", "wrong.ts"), strict: true)

      assert_equal [2322], result.errors.map(&:code)
      assert_equal fixture("files", "wrong.ts"), result.errors.first.file
    end

    test "checks files relative to cwd" do
      result = Tsrs.check("math.ts", cwd: fixture("files"))

      assert_equal true, result.success?
    end

    test "takes compiler options on top of the project's" do
      assert_equal true, Tsrs.check(fixture("files", "math.ts"), target: "es2022", no_unused_locals: true).success?
    end

    test "does not write anything" do
      Tsrs.check(cwd: fixture("project"))

      assert_equal false, File.exist?(fixture("project", "dist"))
    end

    test "validate! raises the type errors" do
      error = assert_raises(Tsrs::TypeError) { Tsrs.check(cwd: fixture("broken")).validate! }

      assert_equal [2322, 2554], error.diagnostics.map(&:code)
      assert_includes error.message, "index.ts:1:7 - error TS2322: Type 'string' is not assignable to type 'number'."
    end

    test "validate! returns the result when there is nothing wrong" do
      result = Tsrs.check(cwd: fixture("project"))

      assert_same result, result.validate!
    end

    test "an unknown compiler option is a diagnostic, as it is for tsc" do
      result = Tsrs.check(cwd: fixture("project"), nonsense: true)

      assert_equal [5023], result.errors.map(&:code)
    end

    test "a missing project is a diagnostic" do
      result = Tsrs.check(project: fixture("nowhere", "tsconfig.json"))

      assert_equal false, result.success?
      assert_equal [5058], result.errors.map(&:code)
    end

    test "refuses build mode" do
      assert_raises(OptionError) { Tsrs.tsc("--build", cwd: fixture("project")) }
      assert_raises(OptionError) { Tsrs.check(cwd: fixture("project"), build: true) }
    end

    test "refuses watch mode" do
      assert_raises(OptionError) { Tsrs.check(cwd: fixture("project"), watch: true) }
    end

    test "can run again and again in one process" do
      3.times { assert_equal [2322, 2554], Tsrs.check(cwd: fixture("broken")).errors.map(&:code) }
    end
  end
end
