# frozen_string_literal: true

module Community
  class CreateUserWarning < ApplicationService
    def initialize(actor:, user:, reason:, points: 1)
      @actor = actor
      @user = user
      @reason = reason.to_s.strip
      @points = [ points.to_i, 1 ].max
    end

    def call
      return ServiceResult.failure(error: "无权发出警告。") unless @actor.permission?("forum.users.warn") || @actor.permission?("admin.access")
      return ServiceResult.failure(error: "不能警告自己。") if @actor.id == @user.id
      return ServiceResult.failure(error: "请填写警告原因。") if @reason.blank?

      warning = Community::UserWarning.create!(
        user: @user,
        issuer: @actor,
        reason: @reason,
        points: [ @points, 10 ].min
      )

      Community::NotifyUserWarning.call(warning: warning)
      ServiceResult.success(warning)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
