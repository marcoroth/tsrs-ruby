# frozen_string_literal: true

require "test_helper"

module Tsrs
  class DeclarationTest < Minitest::Spec
    test "emits the declaration file for a source" do
      source = "export function greet(name: string): string { return `Hello, ${name}`; }"

      assert_equal "export declare function greet(name: string): string;\n", Tsrs.transpile_declaration(source).code
    end

    test "keeps interfaces and types, which have no JavaScript" do
      code = Tsrs.transpile_declaration("export interface User { name: string }\nexport type Id = string | number;").code

      assert_includes code, "export interface User"
      assert_includes code, "export type Id = string | number;"
    end

    test "raises for what isolated declarations cannot infer" do
      error = assert_raises(Tsrs::SyntaxError) do
        Tsrs.transpile_declaration("export const items = [1, 2].map((n) => n * 2);")
      end

      assert_equal [9010], error.diagnostics.map(&:code)
    end
  end
end
