# frozen_string_literal: true

module Admin
  class BaseController < ApplicationController
    layout "admin"

    before_action -> { require_permission("admin.access") }
  end
end
