# frozen_string_literal: true

module Administration
  class CheckEmailBan < ApplicationService
    def initialize(email:)
      @email = email.to_s.strip
    end

    def call
      return ServiceResult.success if Mcweb::DeveloperMode.allow?(:skip_anti_spam)
      return ServiceResult.success if @email.blank?
      return ServiceResult.success unless Administration::EmailBan.match?(@email)

      ServiceResult.failure(
        error: "email_banned_registration",
        code: "email_banned_registration"
      )
    end
  end
end
