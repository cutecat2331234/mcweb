# frozen_string_literal: true

module Administration
  class CheckIpBan < ApplicationService
    def initialize(ip_address:)
      @ip_address = ip_address.to_s.strip
    end

    def call
      return ServiceResult.success if Mcweb::DeveloperMode.allow?(:skip_anti_spam)
      return ServiceResult.success if @ip_address.blank?

      ban = Administration::IpBan.active.find_by(ip_address: @ip_address)
      return ServiceResult.success unless ban

      ServiceResult.failure(error: :your_ip_address_is_banned_from_posting)
    end
  end
end
