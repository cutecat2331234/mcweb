# frozen_string_literal: true

require "ipaddr"
require "uri"

module UrlSafety
  BLOCKED_HOSTS = %w[localhost metadata.google.internal 169.254.169.254].freeze
  CGNAT_NETWORK = IPAddr.new("100.64.0.0/10")

  module_function

  def http_https_url?(url)
    uri = URI.parse(url.to_s.strip)
    uri.is_a?(URI::HTTP) && uri.host.present? && uri.userinfo.blank?
  rescue URI::InvalidURIError
    false
  end

  def safe_image_src?(url)
    location = url.to_s.strip
    return false if location.blank?
    return true if location.start_with?("/rails/active_storage/")

    http_https_url?(location)
  end

  def public_http_url?(url)
    uri = URI.parse(url.to_s.strip)
    return false unless uri.is_a?(URI::HTTP) && uri.host.present?
    return false unless uri.userinfo.blank?

    host = uri.host.downcase.delete_prefix("[").delete_suffix("]")
    return false if BLOCKED_HOSTS.include?(host)
    return false if host.end_with?(".local", ".internal", ".localhost")
    return false if host == "0.0.0.0" || host == "::" || host == "::1"

    addresses = resolved_addresses(host)
    return false if addresses.empty?

    addresses.all? { |address| public_ip?(address) }
  rescue URI::InvalidURIError, SocketError
    false
  end

  def resolved_addresses(host)
    Addrinfo.getaddrinfo(host, nil, nil, :STREAM).map { |info| IPAddr.new(info.ip_address) }
  end
  private_class_method :resolved_addresses

  def public_ip?(address)
    return false if address.loopback? || address.private? || address.link_local?
    return false if CGNAT_NETWORK.include?(address)

    true
  end
  private_class_method :public_ip?
end
