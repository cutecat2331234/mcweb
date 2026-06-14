# frozen_string_literal: true

module Admin
  module System
    class JobsController < BaseController
      before_action -> { require_permission("admin.system.jobs") }

      def index
        redirect_to "/admin/jobs/engine", allow_other_host: false
      end
    end
  end
end
