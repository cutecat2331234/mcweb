# frozen_string_literal: true

module Minecraft
  class NodeAuthenticator < ApplicationService
    def initialize(node:, payload:, signature:, timestamp: nil, max_skew: 5.minutes)
      @node = node
      @payload = payload
      @signature = signature.to_s
      @timestamp = timestamp
      @max_skew = max_skew
    end

    def call
      return ServiceResult.failure(error: "Node secret is not configured.") if @node.node_secret.blank?
      return ServiceResult.failure(error: "Request timestamp is too old or invalid.") unless timestamp_valid?

      expected = OpenSSL::HMAC.hexdigest("SHA256", @node.node_secret, signed_payload)

      if ActiveSupport::SecurityUtils.secure_compare(expected, @signature)
        if Minecraft::HmacReplayGuard.replayed?(scope: "node:#{@node.id}", signature: @signature, expires_in: @max_skew)
          return ServiceResult.failure(error: "Replay detected.")
        end

        ServiceResult.success(node: @node)
      else
        ServiceResult.failure(error: "Invalid node signature.")
      end
    end

    private

    def signed_payload
      "#{@timestamp}.#{@payload}"
    end

    def timestamp_valid?
      return false if @timestamp.blank?

      ts = Time.zone.at(@timestamp.to_i)
      (Time.current - ts).abs <= @max_skew
    rescue ArgumentError, TypeError
      false
    end
  end
end
