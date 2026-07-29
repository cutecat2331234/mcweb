# frozen_string_literal: true

require_relative "error"

module Mcweb
  module Plugins
    class FulfillmentProviderError < Error
      attr_reader :code

      def initialize(code:, message:)
        @code = code.to_s.freeze
        super(message)
      end
    end
  end
end
