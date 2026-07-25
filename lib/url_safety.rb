# frozen_string_literal: true

require "ipaddr"
require "net/http"
require "uri"

module UrlSafety
  BLOCKED_HOSTS = %w[localhost metadata.google.internal 169.254.169.254].freeze
  CGNAT_NETWORK = IPAddr.new("100.64.0.0/10")
  UNSPECIFIED_HOSTS = %w[0.0.0.0 ::].freeze
  RESERVED_V4_NETWORKS = [
    IPAddr.new("0.0.0.0/8"),
    IPAddr.new("192.0.0.0/24"),
    IPAddr.new("192.0.2.0/24"),
    IPAddr.new("198.51.100.0/24"),
    IPAddr.new("203.0.113.0/24"),
    IPAddr.new("224.0.0.0/4"),
    IPAddr.new("240.0.0.0/4")
  ].freeze
  RESERVED_V6_NETWORKS = [
    IPAddr.new("::/96"),
    IPAddr.new("64:ff9b::/96"),
    IPAddr.new("64:ff9b:1::/48"),
    IPAddr.new("100::/64"),
    IPAddr.new("2001::/32"),
    IPAddr.new("2001:2::/48"),
    IPAddr.new("2001:10::/28"),
    IPAddr.new("2001:20::/28"),
    IPAddr.new("2001:db8::/32"),
    IPAddr.new("2002::/16"),
    IPAddr.new("ff00::/8")
  ].freeze

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

    public_http_url?(location)
  end

  def public_http_url?(url)
    uri = URI.parse(url.to_s.strip)
    return false unless uri.is_a?(URI::HTTP) && uri.host.present?
    return false unless uri.userinfo.blank?

    host = normalized_host(uri)
    return false if blocked_host?(host)

    addresses = resolved_addresses(host)
    return false if addresses.empty?

    addresses.all? { |address| public_ip?(address) }
  rescue URI::InvalidURIError, SocketError
    false
  end

  def safe_http_get(uri, open_timeout: 5, read_timeout: 5, headers: {})
    return nil unless uri.is_a?(URI::HTTP) && uri.host.present? && uri.userinfo.blank?

    host = normalized_host(uri)
    return nil if blocked_host?(host)

    addresses = resolved_addresses(host)
    return nil if addresses.empty?
    return nil unless addresses.all? { |address| public_ip?(address) }

    http = build_pinned_http(uri, addresses, open_timeout:, read_timeout:)

    request = Net::HTTP::Get.new(uri)
    headers.each { |key, value| request[key] = value }

    http.request(request)
  rescue StandardError
    nil
  end

  def safe_http_post(uri, body:, open_timeout: 5, read_timeout: 10, headers: {})
    return nil unless uri.is_a?(URI::HTTP) && uri.host.present? && uri.userinfo.blank?

    host = normalized_host(uri)
    return nil if blocked_host?(host)

    addresses = resolved_addresses(host)
    return nil if addresses.empty?
    return nil unless addresses.all? { |address| public_ip?(address) }

    http = build_pinned_http(uri, addresses, open_timeout:, read_timeout:)

    request = Net::HTTP::Post.new(uri)
    headers.each { |key, value| request[key] = value }
    request.body = body

    http.request(request)
  rescue StandardError
    nil
  end

  def resolved_addresses(host)
    Addrinfo.getaddrinfo(host, nil, nil, :STREAM).map { |info| IPAddr.new(info.ip_address) }
  end
  private_class_method :resolved_addresses

  def normalized_host(uri)
    uri.host.to_s.downcase.delete_prefix("[").delete_suffix("]").delete_suffix(".")
  end
  private_class_method :normalized_host

  def blocked_host?(host)
    host.blank? ||
      BLOCKED_HOSTS.include?(host) ||
      host.end_with?(".local", ".internal", ".localhost") ||
      UNSPECIFIED_HOSTS.include?(host) ||
      host == "::1"
  end
  private_class_method :blocked_host?

  def build_pinned_http(uri, addresses, open_timeout:, read_timeout:)
    http = Net::HTTP.new(uri.host, uri.port)
    http.ipaddr = addresses.first.to_s
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = open_timeout
    http.read_timeout = read_timeout
    http
  end
  private_class_method :build_pinned_http

  def public_ip?(address)
    return public_ip?(address.native) if address.ipv6? && address.ipv4_mapped?
    return false if address.loopback? || address.private? || address.link_local?
    return false if CGNAT_NETWORK.include?(address)
    # Unspecified (0.0.0.0 / ::) routes to local services on many stacks; reserved/
    # future ranges are not routable. Centralized here so every caller (incl. resolved
    # addresses in safe_http_get/post) is covered, not just the literal-host check.
    return false if UNSPECIFIED_HOSTS.include?(address.to_s)
    return false if address.ipv4? && RESERVED_V4_NETWORKS.any? { |net| net.include?(address) }
    return false if address.ipv6? && RESERVED_V6_NETWORKS.any? { |net| net.include?(address) }

    true
  end
  private_class_method :public_ip?
end
