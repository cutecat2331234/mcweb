# frozen_string_literal: true

module Admin
  class BaseController < ApplicationController
    inertia_config layout: "inertia_admin"

    before_action -> { require_permission("admin.access") }
  end
end
