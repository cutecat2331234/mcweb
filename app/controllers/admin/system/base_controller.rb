# frozen_string_literal: true

module Admin
  module System
    class BaseController < Admin::BaseController
      before_action -> { require_admin_module!("system") }
    end
  end
end
