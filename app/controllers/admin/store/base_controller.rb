# frozen_string_literal: true

module Admin
  module Store
    class BaseController < Admin::BaseController
      before_action -> { require_admin_module!("store") }
    end
  end
end
