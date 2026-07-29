# frozen_string_literal: true

module Minecraft
  class ValidateExecCommand < ApplicationService
    def initialize(command:, actor: nil)
      @command = command.to_s.strip
      @actor = actor
    end

    def call
      return ServiceResult.failure(error: :command_is_required) if @command.blank?

      prefixes = allowed_prefixes
      if prefixes.empty?
        return ServiceResult.failure(error: :exec_command_prefixes_are_not_configured) unless unrestricted_exec_allowed?

        return ServiceResult.success(true)
      end

      allowed = prefixes.any? { |prefix| @command.start_with?(prefix) }
      return ServiceResult.success(true) if allowed

      ServiceResult.failure(
        error: I18n.t(
          "mcweb.user_copy.command_prefix_not_allowed",
          prefixes: prefixes.join(", ")
        )
      )
    end

    private

    def allowed_prefixes
      raw = SiteSetting.get("minecraft.exec_command.allowed_prefixes", "").to_s
      return [] if raw.blank?

      raw.split(/[,\n]/).map(&:strip).reject(&:blank?)
    end

    def unrestricted_exec_allowed?
      return false if Rails.env.production?

      ActiveModel::Type::Boolean.new.cast(ENV["MCWEB_ALLOW_UNRESTRICTED_EXEC_COMMAND"])
    end
  end
end
