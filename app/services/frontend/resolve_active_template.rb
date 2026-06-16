# frozen_string_literal: true

module Frontend
  class ResolveActiveTemplate < ApplicationService
    def initialize(scope:, preview_key: nil)
      @scope = scope.to_s
      @preview_key = preview_key
    end

    def call
      key = @preview_key.presence || Frontend::Template.active_key_for(@scope)
      return ServiceResult.success(nil) if key.blank?

      template = Frontend::Template.installed.find_by(key: key)
      return ServiceResult.success(nil) unless template&.supports_scope?(@scope)

      ServiceResult.success(template)
    end
  end
end
