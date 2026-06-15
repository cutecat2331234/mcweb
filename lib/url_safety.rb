# frozen_string_literal: true

require "ipaddr"
require "uri"

module UrlSafety
  BLOCKED_HOSTS = %w[localhost metadata.google.internal].freeze

  module_function

  def public_http_url?(url)
    uri = URI.parse(url.to_s.strip)
    return false unless uri.is_a?(URI::HTTP) && uri.host.present?

    host = uri.host.downcase
    return false if BLOCKED_HOSTS.include?(host)
    return false if host.end_with?(".local", ".internal", ".localhost")

    resolved_addresses(host).all? { |address| public_ip?(address) }
  rescue URI::InvalidURIError, SocketError
    false
  end

  def resolved_addresses(host)
    Addrinfo.getaddrinfo(host, nil, nil, :STREAM).map { |info| IPAddr.new(info.ip_address) }
  end
  private_class_method :resolved_addresses

  def public_ip?(address)
    !address.loopback? && !address.private? && !address.link_local?
  end
  private_class_method :public_ip?
end
