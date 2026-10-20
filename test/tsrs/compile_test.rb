# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

module Tsrs
  class CompileTest < Minitest::Spec
    def project_copy
      Dir.mktmpdir do |dir|
        FileUtils.cp_r(File.join(File.expand_path("../fixtures/project", __dir__), "."), dir)

        yield dir
      end
    end

    test "writes the outputs, as tsc does" do
      project_copy do |dir|
        result = Tsrs.compile(cwd: dir)

        assert_equal true, result.success?
        assert_includes File.read(File.join(dir, "dist", "greet.js")), "export function greet(name)"
        assert_equal true, File.exist?(File.join(dir, "dist", "index.js"))
      end
    end

    test "writes declaration files when asked for them" do
      project_copy do |dir|
        Tsrs.compile(cwd: dir, declaration: true)

        assert_equal "export declare function greet(name: string): string;\n", File.read(File.join(dir, "dist", "greet.d.ts"))
      end
    end

    test "tsc takes command-line arguments as they are" do
      project_copy do |dir|
        result = Tsrs.tsc("--listFilesOnly", cwd: dir)

        assert_equal true, result.success?
        assert_includes result.output, File.join(dir, "src", "greet.ts")
      end
    end
  end
end
