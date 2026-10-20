# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

module Tsrs
  class SessionTest < Minitest::Spec
    def fixture(*path)
      File.expand_path(File.join("../fixtures", *path), __dir__)
    end

    def copy_of(name)
      Dir.mktmpdir do |dir|
        FileUtils.cp_r(File.join(fixture(name), "."), dir)

        yield dir
      end
    end

    def rss
      `ps -o rss= -p #{Process.pid}`.to_i / 1024
    end

    test "a project with no errors succeeds" do
      Session.open(cwd: fixture("project")) do |session|
        result = session.check

        assert_instance_of CheckResult, result
        assert_equal 0, result.status
        assert_equal [], result.diagnostics
      end
    end

    test "reports what Tsrs.check reports" do
      Session.open(cwd: fixture("broken")) do |session|
        result = session.check
        expected = Tsrs.check(cwd: fixture("broken"))

        assert_equal expected.status, result.status
        assert_equal expected.diagnostics.map(&:to_s), result.diagnostics.map(&:to_s)
      end
    end

    test "takes the tsconfig.json relative to cwd, or anywhere" do
      Session.open(cwd: fixture) do |session|
        assert_equal [2322, 2554], session.check("broken/tsconfig.json").errors.map(&:code)
        assert_equal true, session.check(fixture("project", "tsconfig.json")).success?
      end
    end

    test "validate! raises the type errors" do
      Session.open(cwd: fixture("broken")) do |session|
        error = assert_raises(Tsrs::TypeError) { session.check.validate! }

        assert_equal [2322, 2554], error.diagnostics.map(&:code)
      end
    end

    test "raises a check error when there is no project" do
      Session.open(cwd: fixture("broken")) do |session|
        error = assert_raises(CheckError) { session.check("nowhere/tsconfig.json") }

        assert_equal "no project was loaded from #{fixture("broken", "nowhere", "tsconfig.json")}", error.message
      end
    end

    test "sees what changed on disk since the last check" do
      copy_of("broken") do |dir|
        Session.open(cwd: dir) do |session|
          assert_equal [2322, 2554], session.check.errors.map(&:code)

          File.write(File.join(dir, "src", "index.ts"), "export const count: number = 3;\n")
          assert_equal [], session.check.errors.map(&:code)

          File.write(File.join(dir, "src", "other.ts"), "export const other: string = 1;\n")
          assert_equal [2322], session.check.errors.map(&:code)

          FileUtils.rm(File.join(dir, "src", "other.ts"))
          assert_equal [], session.check.errors.map(&:code)
        end
      end
    end

    test "sees a changed tsconfig.json" do
      copy_of("broken") do |dir|
        Session.open(cwd: dir) do |session|
          File.write(File.join(dir, "src", "index.ts"), "function unused() {}\nexport const count = 3;\n")
          assert_equal [], session.check.errors.map(&:code)

          File.write(File.join(dir, "tsconfig.json"), JSON.generate({ compilerOptions: { noUnusedLocals: true }, include: ["src"] }))
          assert_equal [6133], session.check.errors.map(&:code)
        end
      end
    end

    test "does not write anything" do
      Session.open(cwd: fixture("project"), &:check)

      assert_equal false, File.exist?(fixture("project", "dist"))
    end

    test "checks from several threads at once" do
      Session.open(cwd: fixture("broken")) do |session|
        threads = 4.times.map { Thread.new { session.check.errors.map(&:code) } }

        assert_equal [[2322, 2554]] * 4, threads.map(&:value)
      end
    end

    test "a closed session cannot check anymore" do
      session = Session.new(cwd: fixture("project"))
      session.close

      assert_equal true, session.closed?
      assert_raises(Error) { session.check }
    end

    test "closing twice is fine" do
      session = Session.new(cwd: fixture("project"))

      2.times { session.close }

      assert_equal true, session.closed?
    end

    test "open closes the session after the block, even when it raises" do
      opened = nil

      assert_raises(RuntimeError) do
        Session.open(cwd: fixture("project")) do |session|
          opened = session

          raise "boom"
        end
      end

      assert_equal true, opened.closed?
    end

    test "a session that is collected without being closed is freed" do
      5.times { Session.new(cwd: fixture("project")).check }

      GC.start

      assert_equal true, Session.new(cwd: fixture("project")).check.success?
    end

    test "checking again and again gives the memory back" do
      Session.open(cwd: fixture("broken")) do |session|
        20.times { session.check }

        before = rss

        40.times { session.check }

        # A Tsrs.check of this project keeps about 38 MiB, so 40 of them would keep 1.5 GiB.
        assert_operator rss - before, :<, 60
      end
    end
  end
end
