# frozen_string_literal: true

module Community
  class ToggleUserIgnore < ApplicationService
    def initialize(ignorer:, ignored_username:)
      @ignorer = ignorer
      @ignored_username = ignored_username.to_s.strip
    end

    def call
      ignored = User.find_by!(username: @ignored_username)
      return ServiceResult.failure(error: "不能忽略自己。") if @ignorer.id == ignored.id

      record = Community::UserIgnore.find_by(ignorer: @ignorer, ignored: ignored)
      if record
        record.destroy!
        ServiceResult.success(ignored: false)
      else
        Community::UserIgnore.create!(ignorer: @ignorer, ignored: ignored)
        ServiceResult.success(ignored: true)
      end
    rescue ActiveRecord::RecordNotFound
      ServiceResult.failure(error: "用户不存在。")
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
