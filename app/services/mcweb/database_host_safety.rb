# frozen_string_literal: true

require "ipaddr"

module Mcweb
  module DatabaseHostSafety
    LOCAL_HOSTS = %w[localhost 127.0.0.1 ::1].freeze

    module_function

    def allowed?(host)
      normalized = normalize_host(host)
      return false if normalized.blank?
      return false if normalized.include?("/") || normalized.include?("://")
      return true if local_host?(normalized)
      return false if UrlSafety::BLOCKED_HOSTS.include?(normalized)
      return false if normalized.end_with?(".local", ".internal", ".localhost")

      addresses = Addrinfo.getaddrinfo(normalized, nil, nil, :STREAM).map { |info| IPAddr.new(info.ip_address) }
      return false if addresses.empty?

      addresses.all? { |address| allowed_address?(address, normalized) }
    rescue SocketError
      false
    end

    def normalize_host(host)
      host.to_s.strip.downcase.delete_prefix("[").delete_suffix("]")
    end

    def local_host?(host)
      LOCAL_HOSTS.include?(host)
    end

    def allowed_address?(address, host)
      return false if metadata_address?(address)
      return false if address.loopback? && !local_host?(host)
      return false if address.link_local?
      return false if Rails.env.production? && address.private? && !allow_private_database_hosts?

      true
    end

    def allow_private_database_hosts?
      ActiveModel::Type::Boolean.new.cast(ENV["SETUP_ALLOW_PRIVATE_DB_HOST"])
    end
    private_class_method :allow_private_database_hosts?

    def metadata_address?(address)
      address.to_s.start_with?("169.254.") || address.to_s == "0.0.0.0"
    end
  end
end
