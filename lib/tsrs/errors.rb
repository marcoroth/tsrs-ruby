# frozen_string_literal: true

module Tsrs
  class Error < StandardError; end
  class OptionError < Error; end
  class EncodingError < Error; end
  class TranspileError < Error; end
  class InternalError < Error; end
  class PanicError < InternalError; end
  class CheckError < Error; end

  class DiagnosticError < Error
    attr_reader :diagnostics #: Array[Tsrs::Diagnostic]

    #: (Array[Tsrs::Diagnostic]) -> void
    def initialize(diagnostics)
      @diagnostics = diagnostics

      super(diagnostics.join("\n"))
    end
  end

  class SyntaxError < DiagnosticError; end
  class TypeError < DiagnosticError; end
end
