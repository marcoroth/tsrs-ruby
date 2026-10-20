# frozen_string_literal: true

require "test_helper"

module Tsrs
  class ErrorsTest < Minitest::Spec
    test "every error is rescuable as one" do
      [OptionError, EncodingError, TranspileError, InternalError, PanicError, DiagnosticError, SyntaxError, TypeError].each do |klass|
        assert_equal true, klass <= Error
        assert_equal true, klass <= StandardError
      end
    end

    test "a panic is an internal error" do
      assert_equal true, PanicError <= InternalError
    end

    test "the syntax and type errors are not Ruby's" do
      assert_nil Tsrs::SyntaxError <= ::SyntaxError
      assert_nil Tsrs::TypeError <= ::TypeError
    end

    test "a diagnostic error carries its diagnostics" do
      diagnostic = Diagnostic.new(code: 1109, category: :error, message: "Expression expected.")
      error = SyntaxError.new([diagnostic])

      assert_equal [diagnostic], error.diagnostics
      assert_equal "error TS1109: Expression expected.", error.message
    end

    test "a source with a nul byte cannot cross into C" do
      assert_raises(ArgumentError) { Tsrs.transpile("let a = 1\0") }
    end

    test "the backend says which method the extension failed to define" do
      error = assert_raises(NotImplementedError) do
        Module.new { extend Backend::Unavailable }.check("{}")
      end

      assert_equal "Tsrs::Backend.check is defined by the native extension, which did not load", error.message
    end
  end
end
