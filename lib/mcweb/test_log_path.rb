# frozen_string_literal: true

require "pathname"

module Mcweb
  module TestLogPath
    module_function

    def resolve(root:, environment: ENV)
      override = environment["MCWEB_TEST_LOG_PATH"].to_s.strip
      unless override.empty?
        path = Pathname.new(override)
        return path.absolute? ? path : Pathname.new(root).join(path)
      end

      worker = environment["TEST_ENV_NUMBER"].to_s.strip
      worker = worker.gsub(/[^A-Za-z0-9_-]/, "_")
      Pathname.new(root).join("log", "test#{worker}.log")
    end
  end
end
