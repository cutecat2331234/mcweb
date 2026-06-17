# frozen_string_literal: true

module Frontend
  class DeleteTemplate < ApplicationService
    def initialize(template:, actor: nil)
      @template = template
      @actor = actor
    end

    def call
      Frontend::Template::SITE_SETTING_KEYS.each do |scope, setting_key|
        SiteSetting.set(setting_key, nil) if SiteSetting.get(setting_key) == @template.key
      end

      path = @template.installed_path
      FileUtils.rm_rf(path) if path.present? && Pathname(path).exist?

      key = @template.key
      @template.destroy!

      log_audit(key)
      ServiceResult.success(true)
    end

    private

    def log_audit(key)
      return unless @actor

      Administration::AuditLogger.call(
        actor: @actor,
        action: "frontend.template.deleted",
        metadata: { key: key }
      )
    end
  end
end
