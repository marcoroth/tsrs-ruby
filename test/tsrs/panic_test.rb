# frozen_string_literal: true

require "test_helper"
require "tempfile"

module Tsrs
  class PanicTest < Minitest::Spec
    def stderr_of
      Tempfile.create("stderr") do |file|
        saved = $stderr.dup

        begin
          $stderr.reopen(file)
          yield
          $stderr.flush
        ensure
          $stderr.reopen(saved)
          saved.close
        end

        File.read(file.path)
      end
    end

    test "turns a panic into an exception instead of taking the process down" do
      error = assert_raises(PanicError) { Backend.panic_for_test }

      assert_equal "a deliberate panic", error.message
    end

    test "a panic is an internal error, so rescuing either catches it" do
      assert_raises(InternalError) { Backend.panic_for_test }
      assert_raises(Error) { Backend.panic_for_test }
    end

    test "says nothing on the way out, so a green build stays quiet" do
      assert_equal("", stderr_of { assert_raises(PanicError) { Backend.panic_for_test } })
    end

    test "the process keeps working afterwards" do
      assert_raises(PanicError) { Backend.panic_for_test }

      assert_equal "export let a = 1;\n", Tsrs.transpile("export let a = 1").code
    end
  end
end
