# frozen_string_literal: true

require "test_helper"

module Tsrs
  class DiagnosticTest < Minitest::Spec
    def response
      {
        "fileName" => "/app/src/index.ts",
        "pos" => 6,
        "end" => 11,
        "startPosition" => { "line" => 0, "character" => 6 },
        "endPosition" => { "line" => 0, "character" => 11 },
        "code" => 2322,
        "category" => 1,
        "text" => "Type 'string' is not assignable to type 'number'.",
        "messageChain" => [
          { "pos" => -1, "end" => -1, "code" => 2326, "category" => 3, "text" => "Types of property 'a' are incompatible." }
        ],
      }
    end

    test "reads tsc's diagnostic response" do
      diagnostic = Diagnostic.from_hash(response)

      assert_equal 2322, diagnostic.code
      assert_equal :error, diagnostic.category
      assert_equal "/app/src/index.ts", diagnostic.file
      assert_equal [1, 7, 1, 12], [diagnostic.line, diagnostic.column, diagnostic.end_line, diagnostic.end_column]
      assert_equal [6, 11], [diagnostic.start, diagnostic.finish]
      assert_equal true, diagnostic.error?
      assert_equal true, diagnostic.frozen?
    end

    test "prints like tsc" do
      assert_equal "/app/src/index.ts:1:7 - error TS2322: Type 'string' is not assignable to type 'number'.\n  Types of property 'a' are incompatible.",
                   Diagnostic.from_hash(response).to_s
    end

    test "a diagnostic with no file has no location" do
      diagnostic = Diagnostic.from_hash({ "pos" => -1, "end" => -1, "code" => 5023, "category" => 1, "text" => "Unknown compiler option 'x'." })

      assert_nil diagnostic.file
      assert_nil diagnostic.start
      assert_equal "", diagnostic.location
      assert_equal "error TS5023: Unknown compiler option 'x'.", diagnostic.to_s
    end

    test "reads the chain and the related information" do
      diagnostic = Diagnostic.from_hash(response.merge("relatedInformation" => [response.merge("category" => 3, "text" => "Declared here.")]))

      assert_equal [2326], diagnostic.message_chain.map(&:code)
      assert_equal ["Declared here."], diagnostic.related_information.map(&:message)
    end
  end
end
