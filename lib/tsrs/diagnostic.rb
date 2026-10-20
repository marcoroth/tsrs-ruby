# frozen_string_literal: true

module Tsrs
  # Lines and columns are 1-based. `start` and `finish` are offsets in UTF-16 code units, as TypeScript counts.
  #
  class Diagnostic
    CATEGORIES = [:warning, :error, :suggestion, :message].freeze #: Array[Symbol]

    attr_reader :code #: Integer
    attr_reader :category #: Symbol
    attr_reader :message #: String
    attr_reader :file #: String?
    attr_reader :line #: Integer?
    attr_reader :column #: Integer?
    attr_reader :end_line #: Integer?
    attr_reader :end_column #: Integer?
    attr_reader :start #: Integer?
    attr_reader :finish #: Integer?
    attr_reader :source #: String?
    attr_reader :message_chain #: Array[Tsrs::Diagnostic]
    attr_reader :related_information #: Array[Tsrs::Diagnostic]

    #: (Hash[String, untyped]) -> Tsrs::Diagnostic
    def self.from_hash(hash)
      start_position = hash["startPosition"]
      end_position = hash["endPosition"]

      new(
        code: hash.fetch("code"),
        category: CATEGORIES.fetch(hash.fetch("category"), :message),
        message: hash.fetch("text"),
        file: hash["fileName"],
        line: start_position && (start_position.fetch("line") + 1),
        column: start_position && (start_position.fetch("character") + 1),
        end_line: end_position && (end_position.fetch("line") + 1),
        end_column: end_position && (end_position.fetch("character") + 1),
        start: offset(hash["pos"]),
        finish: offset(hash["end"]),
        source: hash["source"],
        message_chain: (hash["messageChain"] || []).map { |link| from_hash(link) },
        related_information: (hash["relatedInformation"] || []).map { |related| from_hash(related) }
      )
    end

    #: (untyped) -> Integer?
    def self.offset(value)
      value.is_a?(Integer) && value >= 0 ? value : nil
    end

    #: (code: Integer, category: Symbol, message: String, ?file: String?, ?line: Integer?, ?column: Integer?, ?end_line: Integer?, ?end_column: Integer?, ?start: Integer?, ?finish: Integer?, ?source: String?, ?message_chain: Array[Tsrs::Diagnostic], ?related_information: Array[Tsrs::Diagnostic]) -> void
    def initialize(code:, category:, message:, file: nil, line: nil, column: nil, end_line: nil, end_column: nil, start: nil, finish: nil, source: nil, message_chain: [], related_information: [])
      @code = code
      @category = category
      @message = message.freeze
      @file = file&.freeze
      @line = line
      @column = column
      @end_line = end_line
      @end_column = end_column
      @start = start
      @finish = finish
      @source = source&.freeze
      @message_chain = message_chain.freeze
      @related_information = related_information.freeze

      freeze
    end

    #: () -> bool
    def error?
      category == :error
    end

    #: () -> bool
    def warning?
      category == :warning
    end

    #: () -> String
    def location
      return "" unless file

      line ? "#{file}:#{line}:#{column}" : file.to_s
    end

    #: () -> String
    def full_message
      ([message] + chain_lines(message_chain, 1)).join("\n")
    end

    #: () -> String
    def to_s
      prefix = "#{category} TS#{code}: #{full_message}"

      file ? "#{location} - #{prefix}" : prefix
    end

    #: () -> String
    def inspect
      "#<#{self.class.name} #{category} TS#{code} #{"#{location} " unless location.empty?}#{message.inspect}>"
    end

    private

    #: (Array[Tsrs::Diagnostic], Integer) -> Array[String]
    def chain_lines(chain, depth)
      chain.flat_map do |link|
        ["#{"  " * depth}#{link.message}"] + chain_lines(link.message_chain, depth + 1)
      end
    end
  end
end
