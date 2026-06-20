# frozen_string_literal: true

module Admin
  module Website
    class BaseController < Admin::BaseController
      before_action -> { require_admin_module!("website") }
    end
  end
end
