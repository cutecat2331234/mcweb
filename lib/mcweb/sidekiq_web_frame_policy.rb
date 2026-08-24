# frozen_string_literal: true

module Mcweb
  class SidekiqWebFramePolicy
    CONTENT_SECURITY_POLICY = "Content-Security-Policy"
    FRAME_ANCESTORS_DIRECTIVE = "frame-ancestors 'self'"
    X_FRAME_OPTIONS = "X-Frame-Options"

    def initialize(app)
      @app = app
    end

    def call(environment)
      status, headers, body = @app.call(environment)
      secured_headers = headers.to_h.dup
      policy_values = remove_header_values!(
        secured_headers,
        CONTENT_SECURITY_POLICY
      )
      policy = policy_values.join("; ")
      directives = policy.split(";").map(&:strip).reject(&:empty?)
      directives.reject! do |directive|
        directive.split(/\s+/, 2).first.casecmp?("frame-ancestors")
      end
      directives << FRAME_ANCESTORS_DIRECTIVE

      remove_header_values!(secured_headers, X_FRAME_OPTIONS)
      secured_headers[CONTENT_SECURITY_POLICY] = directives.join("; ")
      secured_headers[X_FRAME_OPTIONS] = "SAMEORIGIN"

      [ status, secured_headers, body ]
    end

    private

    def remove_header_values!(headers, header_name)
      headers.keys.filter_map do |key|
        headers.delete(key) if key.to_s.casecmp?(header_name)
      end
    end
  end
end
