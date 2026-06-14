# frozen_string_literal: true

module Administration
  class UnbanIp < ApplicationService
    def initialize(ip_address:)
      @ip_address = ip_address.to_s.strip
    end

    def call
      ban = Administration::IpBan.find_by(ip_address: @ip_address)
      return ServiceResult.failure(error: "IP ban not found.") unless ban

      ban.destroy!
      ServiceResult.success
    end
  end
end
