# frozen_string_literal: true

class WebhookSignature
  def self.header_for(secret, body)
    return nil if secret.blank?

    "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, body)}"
  end
end
