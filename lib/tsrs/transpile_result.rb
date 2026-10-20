# frozen_string_literal: true

require "json"

module Tsrs
  # A transpile ignores imports, so its diagnostics never include type errors.
  #
  class TranspileResult
    include Diagnosed

    attr_reader :code #: String
    attr_reader :map #: String?
    attr_reader :diagnostics #: Array[Tsrs::Diagnostic]

    #: (String) -> Tsrs::TranspileResult
    def self.from_json(payload)
      data = JSON.parse(payload)

      new(
        code: data.fetch("code"),
        map: data["map"],
        diagnostics: data.fetch("diagnostics").map { |diagnostic| Diagnostic.from_hash(diagnostic) }
      )
    end

    #: (code: String, ?map: String?, ?diagnostics: Array[Tsrs::Diagnostic]) -> void
    def initialize(code:, map: nil, diagnostics: [])
      @code = code.freeze
      @map = map&.freeze
      @diagnostics = diagnostics.freeze

      freeze
    end

    #: (?strict: bool) -> self
    def validate!(strict: false)
      failing = strict ? diagnostics : errors

      raise SyntaxError, failing unless failing.empty?

      self
    end

    #: () -> String
    def to_s
      code
    end

    #: () -> String
    def inspect
      "#<#{self.class.name} code=#{code.bytesize}B map=#{map ? "yes" : "no"} diagnostics=#{diagnostics.length}>"
    end
  end
end
