# frozen_string_literal: true

module Minecraft
  class ConnectorAuthenticator < ApplicationService
    def initialize(server:, payload:, signature:, timestamp: nil, max_skew: 5.minutes)
      @server = server
      @payload = payload
      @signature = signature.to_s
      @timestamp = timestamp
      @max_skew = max_skew
    end

    def call
      return ServiceResult.failure(error: "Server connector is not configured.") if @server.connector_secret.blank?
      return ServiceResult.failure(error: "Request timestamp is too old or invalid.") unless timestamp_valid?

      secret = @server.connector_secret
      expected = OpenSSL::HMAC.hexdigest("SHA256", secret, signed_payload)

      if ActiveSupport::SecurityUtils.secure_compare(expected, @signature)
        ServiceResult.success(server: @server)
      else
        ServiceResult.failure(error: "Invalid connector signature.")
      end
    end

    private

    def signed_payload
      return @payload if @timestamp.blank?

      "#{@timestamp}.#{@payload}"
    end

    def timestamp_valid?
      return true if @timestamp.blank?

      ts = Time.zone.at(@timestamp.to_i)
      (Time.current - ts).abs <= @max_skew
    rescue ArgumentError, TypeError
      false
    end
  end
end
