# frozen_string_literal: true

module Administration
  class CheckEmailBan < ApplicationService
    def initialize(email:)
      @email = email.to_s.strip
    end

    def call
      return ServiceResult.success if @email.blank?
      return ServiceResult.success unless Administration::EmailBan.match?(@email)

      ServiceResult.failure(error: "该邮箱已被封禁，无法注册。")
    end
  end
end
