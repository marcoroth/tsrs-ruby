# frozen_string_literal: true

require "json"

module Tsrs
  class CheckResult
    include Diagnosed

    attr_reader :status #: Integer
    attr_reader :exit_status #: Symbol
    attr_reader :diagnostics #: Array[Tsrs::Diagnostic]
    attr_reader :output #: String

    #: (String) -> Tsrs::CheckResult
    def self.from_json(payload)
      data = JSON.parse(payload)
      status = data.fetch("status")

      new(
        status: status.fetch("code"),
        exit_status: status.fetch("name").to_sym,
        output: data.fetch("output", ""),
        diagnostics: data.fetch("diagnostics").map { |diagnostic| Diagnostic.from_hash(diagnostic) }
      )
    end

    #: (status: Integer, exit_status: Symbol, ?output: String, ?diagnostics: Array[Tsrs::Diagnostic]) -> void
    def initialize(status:, exit_status:, output: "", diagnostics: [])
      @status = status
      @exit_status = exit_status
      @output = output.freeze
      @diagnostics = diagnostics.freeze

      freeze
    end

    #: () -> bool
    def success?
      status.zero?
    end

    #: (?strict: bool) -> self
    def validate!(strict: false)
      return self if success? && (!strict || diagnostics.empty?)

      raise TypeError, diagnostics unless diagnostics.empty?

      raise Error, (output.empty? ? "tsc exited with status #{status} (#{exit_status})" : output.strip)
    end

    #: () -> String
    def to_s
      diagnostics.join("\n")
    end

    #: () -> String
    def inspect
      "#<#{self.class.name} status=#{status} errors=#{errors.length} diagnostics=#{diagnostics.length}>"
    end
  end
end
