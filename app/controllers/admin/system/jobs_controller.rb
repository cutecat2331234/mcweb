# frozen_string_literal: true

module Admin
  module System
    class JobsController < BaseController
      before_action -> { require_permission("system.jobs.read") }

      def index
        redirect_to "/jobs", allow_other_host: false
      end
    end
  end
end
