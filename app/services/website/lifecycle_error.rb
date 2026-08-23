# frozen_string_literal: true

module Website
  class LifecycleError < StandardError
    attr_reader :code, :details

    def initialize(code, details = {})
      @code = code.to_s
      @details = details
      super(@code)
    end
  end
end
