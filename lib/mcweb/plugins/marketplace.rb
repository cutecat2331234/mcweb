# frozen_string_literal: true

require_relative "marketplace/manager"

module Mcweb
  module Plugins
    module Marketplace
      class << self
        def manager(**options)
          Manager.new(**options)
        end
      end
    end
  end
end
