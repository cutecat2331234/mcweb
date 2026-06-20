# frozen_string_literal: true

module Minecraft
  class PairNode < ApplicationService
    def initialize(token:, hostname: nil)
      @token = token.to_s.strip
      @hostname = hostname
    end

    def call
      return ServiceResult.failure(error: "Pairing token is required.") if @token.blank?

      node = find_node_by_token
      return ServiceResult.failure(error: "Invalid or expired pairing token.") unless node

      secret = node.generate_node_secret!
      metadata = node.metadata.except("pairing_token", "pairing_token_expires_at")
      node.update!(
        hostname: @hostname.presence || node.hostname,
        metadata: metadata,
        status: :online,
        last_heartbeat_at: Time.current
      )

      ServiceResult.success(
        node_id: node.public_id,
        node_secret: secret,
        rails_url: Rails.application.routes.default_url_options[:host].presence ||
          ENV.fetch("MCWEB_PUBLIC_URL", "http://localhost:3000")
      )
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def find_node_by_token
      Minecraft::Node.find_each do |node|
        stored = node.metadata["pairing_token"]
        next unless stored.present? && ActiveSupport::SecurityUtils.secure_compare(stored, @token)

        expires = node.metadata["pairing_token_expires_at"]
        next if expires.present? && Time.zone.parse(expires.to_s) < Time.current

        return node
      end
      nil
    end
  end
end
