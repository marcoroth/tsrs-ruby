# frozen_string_literal: true

module Tsrs
  module Backend
    module Unavailable
      #: (String, String) -> String
      def transpile(_source, _options_json)
        unavailable(__method__)
      end

      #: (String, String) -> String
      def transpile_declaration(_source, _options_json)
        unavailable(__method__)
      end

      #: (String) -> String
      def check(_options_json)
        unavailable(__method__)
      end

      #: (String) -> untyped
      def session_new(_cwd)
        unavailable(__method__)
      end

      #: (untyped, String) -> String
      def session_check(_handle, _options_json)
        unavailable(__method__)
      end

      #: (untyped) -> nil
      def session_close(_handle)
        unavailable(__method__)
      end

      #: () -> String
      def panic_for_test
        unavailable(__method__)
      end

      #: () -> String
      def version
        unavailable(__method__)
      end

      #: () -> String
      def tsrs_version
        unavailable(__method__)
      end

      #: () -> String
      def typescript_version
        unavailable(__method__)
      end

      private

      #: (Symbol?) -> bot
      def unavailable(name)
        raise NotImplementedError, "Tsrs::Backend.#{name} is defined by the native extension, which did not load"
      end
    end

    extend Unavailable
  end
end
