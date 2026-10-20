# frozen_string_literal: true

require "test_helper"

module Tsrs
  class TranspileTest < Minitest::Spec
    test "strips the types" do
      assert_equal "\"use strict\";\nconst count = 1;\n", Tsrs.transpile("const count: number = 1;").code
    end

    test "returns a frozen transpile result" do
      result = Tsrs.transpile("const count: number = 1;")

      assert_instance_of TranspileResult, result
      assert_equal true, result.frozen?
      assert_equal result.code, result.to_s
    end

    test "takes tsc's compiler options" do
      code = Tsrs.transpile("export const answer = async () => 42;", target: "es2015", module: "commonjs").code

      assert_includes code, "exports.answer"
      assert_includes code, "__awaiter"
    end

    test "compiles enums and namespaces, which have runtime semantics" do
      code = Tsrs.transpile("enum Color { Red, Green }").code

      assert_includes code, "Color[Color[\"Red\"] = 0] = \"Red\""
    end

    test "compiles jsx when the file name says it is tsx" do
      code = Tsrs.transpile("export const a = <div className=\"x\" />;", file_name: "app.tsx", jsx: "react-jsx").code

      assert_includes code, "react/jsx-runtime"
    end

    test "has no source map unless asked for one" do
      assert_nil Tsrs.transpile("let a = 1").map
    end

    test "returns a source map when asked for one" do
      result = Tsrs.transpile("let a: number = 1", file_name: "a.ts", source_map: true)

      assert_equal "a.js", JSON.parse(result.map.to_s).fetch("file")
      assert_includes result.code, "//# sourceMappingURL=a.js.map"
    end

    test "does not type check" do
      result = Tsrs.transpile("const count: number = \"three\";")

      assert_equal [], result.diagnostics
    end

    test "raises a syntax error for a source that does not parse" do
      error = assert_raises(Tsrs::SyntaxError) { Tsrs.transpile("let = ;", file_name: "broken.ts") }

      assert_equal [1109], error.diagnostics.map(&:code)
      assert_equal "/broken.ts:1:7 - error TS1109: Expression expected.", error.message
    end

    test "skips the syntax check when diagnostics are not wanted" do
      result = Tsrs.transpile("let = ;", report_diagnostics: false)

      assert_equal [], result.diagnostics
    end

    test "raises an option error for an option tsc does not know" do
      error = assert_raises(OptionError) { Tsrs.transpile("let a = 1", nonsense: true) }

      assert_equal "Unknown compiler option '--nonsense'.", error.message
    end

    test "raises an option error for a value tsc does not take" do
      assert_raises(OptionError) { Tsrs.transpile("let a = 1", target: "es1999") }
    end

    test "keeps unicode intact" do
      assert_includes Tsrs.transpile("const greeting: string = \"grüezi 👋\";").code, "grüezi 👋"
    end

    test "returns utf-8 strings" do
      assert_equal Encoding::UTF_8, Tsrs.transpile("let a = 1").code.encoding
    end
  end
end
