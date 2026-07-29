# frozen_string_literal: true

require_relative "devtools/builder"
require_relative "devtools/command"
require_relative "devtools/compatibility"
require_relative "devtools/contract_tester"
require_relative "devtools/creator"
require_relative "devtools/health_checker"
require_relative "devtools/releaser"
require_relative "devtools/validator"

module Mcweb
  module Plugins
    module Devtools
      TOOL_VERSION = "1.0.0"
    end
  end
end
