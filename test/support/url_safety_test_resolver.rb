# frozen_string_literal: true

# CNB and other sandboxed runners may resolve example.com through an internal
# egress proxy. Tests use this IANA-reserved documentation domain as their
# public webhook fixture, so keep its DNS result deterministic without
# weakening UrlSafety or changing resolution for any production hostname.
module UrlSafetyTestResolver
  EXAMPLE_HOST = "example.com"
  EXAMPLE_ADDRESS = IPAddr.new("93.184.216.34")

  private

  def resolved_addresses(host)
    return [ EXAMPLE_ADDRESS ] if host == EXAMPLE_HOST

    super
  end
end

UrlSafety.singleton_class.prepend(UrlSafetyTestResolver)
