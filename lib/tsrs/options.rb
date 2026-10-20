# frozen_string_literal: true

module Tsrs
  module Options
    REFUSED = {
      "build" => "build mode is not supported",
      "watch" => "watch mode is not supported",
      "init" => "--init is not supported by tsrs",
      "showConfig" => "--showConfig is not supported by tsrs",
      "help" => "--help prints to the terminal, it is not an option for a call",
      "all" => "--all prints to the terminal, it is not an option for a call",
      "version" => "--version prints to the terminal, use Tsrs.typescript_version instead",
    }.freeze #: Hash[String, String]

    #: (Hash[Symbol | String, untyped]) -> Array[String]
    def self.arguments(options)
      options.each_with_object([]) do |(key, value), arguments|
        next if value.nil?

        name = option_name(key)

        refuse!(name)

        arguments.push(*flag(name, value))
      end
    end

    #: (Symbol | String) -> String
    def self.option_name(key)
      name = key.to_s.delete_prefix("--")

      return name unless key.is_a?(Symbol)

      name.gsub(/_([a-z0-9])/) { ::Regexp.last_match(1).to_s.upcase }
    end

    #: (String) -> void
    def self.refuse!(name)
      reason = REFUSED[name]

      raise OptionError, "#{name}: #{reason}" if reason
    end

    #: (String, untyped) -> Array[String]
    def self.flag(name, value)
      case value
      when true
        ["--#{name}"]
      when false
        ["--#{name}", "false"]
      when Array
        ["--#{name}", value.join(",")]
      when Hash
        raise OptionError, "#{name} takes a #{value.class}, which tsc's command line has no way to say"
      else
        ["--#{name}", value.to_s]
      end
    end

    private_class_method :refuse!, :flag
  end
end
