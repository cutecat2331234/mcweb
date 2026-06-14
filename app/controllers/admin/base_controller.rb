# frozen_string_literal: true

module Admin
  class BaseController < ApplicationController
    before_action -> { require_permission("admin.access") }
  end
end
