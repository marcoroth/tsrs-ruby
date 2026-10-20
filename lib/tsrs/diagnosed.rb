# frozen_string_literal: true

module Tsrs
  # @rbs module-self _Diagnosed
  module Diagnosed
    #: () -> Array[Tsrs::Diagnostic]
    def errors
      diagnostics.select(&:error?)
    end

    #: () -> Array[Tsrs::Diagnostic]
    def warnings
      diagnostics.select(&:warning?)
    end

    #: () -> bool
    def errors?
      diagnostics.any?(&:error?)
    end
  end
end
