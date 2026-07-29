# frozen_string_literal: true

module Administration
  class UnbanIp < ApplicationService
    def initialize(ip_address:)
      @ip_address = ip_address.to_s.strip
    end

    def call
      ban = Administration::IpBan.find_by(ip_address: @ip_address)
      return ServiceResult.failure(error: :ip_ban_not_found) unless ban

      ban.destroy!
      ServiceResult.success
    end
  end
end
