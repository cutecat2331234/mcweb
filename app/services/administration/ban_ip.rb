# frozen_string_literal: true

module Administration
  class BanIp < ApplicationService
    def initialize(ip_address:, actor:, reason: nil, expires_at: nil)
      @ip_address = ip_address.to_s.strip
      @actor = actor
      @reason = reason
      @expires_at = expires_at
    end

    def call
      return ServiceResult.failure(error: "IP address is required.") if @ip_address.blank?

      ban = Administration::IpBan.find_or_initialize_by(ip_address: @ip_address)
      ban.assign_attributes(reason: @reason, banned_by: @actor, expires_at: @expires_at)
      ban.save!
      ServiceResult.success(ban)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
