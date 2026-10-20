# frozen_string_literal: true

require "test_helper"

module Tsrs
  class ThreadsTest < Minitest::Spec
    test "transpiles from many threads at once" do
      threads = 8.times.map do |index|
        Thread.new { 10.times.map { Tsrs.transpile("export const value: number = #{index};").code } }
      end

      threads.each_with_index do |thread, index|
        assert_equal ["export const value = #{index};\n"], thread.value.uniq
      end
    end

    test "checks from several threads at once" do
      broken = File.expand_path("../fixtures/broken", __dir__)
      threads = 3.times.map { Thread.new { Tsrs.check(cwd: broken).errors.map(&:code) } }

      assert_equal [[2322, 2554]] * 3, threads.map(&:value)
    end

    test "other Ruby threads keep running while tsrs works" do
      ticks = 0
      ticker = Thread.new { loop { ticks += 1 and sleep 0.001 } }

      Tsrs.check(cwd: File.expand_path("../fixtures/project", __dir__))

      ticker.kill

      assert_operator ticks, :>, 5
    end
  end
end
