# frozen_string_literal: true

module Admin
  module Minecraft
    class BaseController < Admin::BaseController
      before_action -> { require_admin_module!("minecraft") }
    end
  end
end
