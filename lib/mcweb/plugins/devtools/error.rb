# frozen_string_literal: true

module Mcweb
  module Plugins
    module Devtools
      class Error < StandardError
        attr_reader :code, :details

        def initialize(code, message, details: {})
          @code = code.to_s.freeze
          @details = details.freeze
          super(message)
        end
      end
    end
  end
end
