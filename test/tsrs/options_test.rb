# frozen_string_literal: true

require "test_helper"

module Tsrs
  class OptionsTest < Minitest::Spec
    test "camel cases snake case names, as tsc spells them" do
      assert_equal ["--esModuleInterop", "--noUncheckedIndexedAccess"], Options.arguments(es_module_interop: true, no_unchecked_indexed_access: true)
    end

    test "passes string names through as they are" do
      assert_equal ["--esModuleInterop"], Options.arguments("esModuleInterop" => true)
      assert_equal ["--strict"], Options.arguments("--strict" => true)
    end

    test "true is the bare flag and false says so" do
      assert_equal ["--strict", "--noEmit", "false"], Options.arguments(strict: true, no_emit: false)
    end

    test "nil leaves the option out" do
      assert_equal [], Options.arguments(target: nil)
    end

    test "values become strings" do
      assert_equal ["--target", "es2020", "--maxNodeModuleJsDepth", "2"], Options.arguments(target: :es2020, max_node_module_js_depth: 2)
    end

    test "lists are comma separated, as tsc takes them" do
      assert_equal ["--lib", "es2022,dom"], Options.arguments(lib: ["es2022", "dom"])
    end

    test "a hash cannot be said on tsc's command line" do
      assert_raises(OptionError) { Options.arguments(paths: { "@/*" => ["src/*"] }) }
    end

    test "refuses the options that only make sense in a terminal" do
      [:build, :watch, :init, :show_config, :help, :all, :version].each do |name|
        assert_raises(OptionError) { Options.arguments(name => true) }
      end
    end
  end
end
