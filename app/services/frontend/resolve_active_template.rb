# frozen_string_literal: true

module Frontend
  class ResolveActiveTemplate < ApplicationService
    def initialize(scope:, preview_key: nil)
      @scope = scope.to_s
      @preview_key = preview_key
    end

    def call
      key = @preview_key.presence || Frontend::Template.active_key_for(@scope)
      template = if key.present?
        Frontend::Template.installed.find_by(key: key)
      end
      template = builtin_template if template.nil? || !template.supports_scope?(@scope)

      ServiceResult.success(template)
    end

    private

    def builtin_template
      template = Frontend::Template.installed.find_by(key: Frontend::EnsureDefaultTemplate::BUILTIN_KEY)
      return unless template&.supports_scope?(@scope)

      template
    end
  end
end
