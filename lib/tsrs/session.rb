# frozen_string_literal: true

require "json"

module Tsrs
  # Unlike Tsrs.check, a session gives a check's memory back. Compiler options come from the tsconfig.json only.
  #
  class Session
    attr_reader :cwd #: String

    #: [T] (?cwd: String) { (Tsrs::Session) -> T } -> T
    def self.open(cwd: Dir.pwd)
      session = new(cwd: cwd)

      begin
        yield session
      ensure
        session.close
      end
    end

    #: (?cwd: String) -> void
    def initialize(cwd: Dir.pwd)
      @cwd = File.expand_path(cwd.to_s)
      @handle = Backend.session_new(@cwd)
      @closed = false
    end

    #: (?String) -> Tsrs::CheckResult
    def check(project = "tsconfig.json")
      raise Error, "the session is closed" if closed?

      request = JSON.generate({ project: File.expand_path(project.to_s, cwd) })

      CheckResult.from_json(Backend.session_check(@handle, request))
    end

    #: () -> void
    def close
      return if closed?

      @closed = true

      Backend.session_close(@handle)
    end

    #: () -> bool
    def closed?
      @closed
    end

    #: () -> String
    def inspect
      "#<#{self.class.name} cwd=#{cwd.inspect}#{" closed" if closed?}>"
    end
  end
end
