# frozen_string_literal: true

module Mcweb
  class SidekiqWebFramePolicy
    CONTENT_SECURITY_POLICY = "content-security-policy"
    CONTENT_TYPE = "content-type"
    CONTENT_LENGTH = "content-length"
    DOCUMENT_MARKER =
      '<meta name="mcweb-embedded-console" content="sidekiq">'
    FRAME_ANCESTORS_DIRECTIVE = "frame-ancestors 'self'"
    X_FRAME_OPTIONS = "x-frame-options"

    def initialize(app)
      @app = app
    end

    def call(environment)
      status, headers, body = @app.call(environment)
      secured_headers = headers.to_h.each_with_object({}) do |(key, value), normalized|
        normalized[key.to_s.downcase] = value
      end
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

      secured_body = embed_success_marker(status, secured_headers, body)
      [ status, secured_headers, secured_body ]
    end

    private

    def embed_success_marker(status, headers, body)
      return body unless status.to_i.between?(200, 299)

      content_type = header_values(headers, CONTENT_TYPE).first.to_s
      return body unless content_type.match?(/\Atext\/html\b/i)

      chunks = []
      body.each { |chunk| chunks << chunk.to_s }
      body.close if body.respond_to?(:close)
      document = chunks.join
      return chunks if document.include?(DOCUMENT_MARKER)

      marked_document = document.sub(/<head(?:\s[^>]*)?>/i) do |head|
        "#{head}#{DOCUMENT_MARKER}"
      end
      return chunks if marked_document == document

      remove_header_values!(headers, CONTENT_LENGTH)
      headers[CONTENT_LENGTH] = marked_document.bytesize.to_s
      [ marked_document ]
    end

    def header_values(headers, header_name)
      headers.filter_map do |key, value|
        value if key.to_s.casecmp?(header_name)
      end
    end

    def remove_header_values!(headers, header_name)
      headers.keys.filter_map do |key|
        headers.delete(key) if key.to_s.casecmp?(header_name)
      end
    end
  end
end
