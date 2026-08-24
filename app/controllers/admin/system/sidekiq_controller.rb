# frozen_string_literal: true

module Admin
  module System
    class SidekiqController < BaseController
      before_action -> { require_permission("system.jobs.read") }

      def index
        render inertia: "Admin/System/Sidekiq/Index"
      end
    end
  end
end
