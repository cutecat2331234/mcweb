# frozen_string_literal: true

require "digest"
require "json"

module Mcweb
  module Plugins
    class ManifestCanonicalizer
      FIELD_ORDER = %i[
        id
        name
        version
        api_version
        description
        author
        homepage
        requires
        capabilities
        contributions
        entrypoint
        setup
      ].freeze

      def initialize(manifest)
        @manifest = manifest
      end

      def canonical_hash
        FIELD_ORDER.each_with_object({}) do |field, result|
          value = @manifest.public_send(field)
          next if field == :contributions && value.empty?

          result[field.to_s.freeze] = canonical_value(field, value)
        end.freeze
      end

      def canonical_json
        JSON.generate(canonical_hash).encode(Encoding::UTF_8).freeze
      end

      def sha256
        Digest::SHA256.hexdigest(canonical_json).freeze
      end

      private

      def canonical_value(field, value)
        case field
        when :requires
          value.sort.to_h do |plugin_id, requirement|
            [ canonical_string(plugin_id), canonical_string(requirement) ]
          end.freeze
        when :capabilities
          value.map { |capability| canonical_string(capability) }.sort.freeze
        when :contributions
          value.sort.to_h do |type, path|
            [ canonical_string(type), canonical_string(path) ]
          end.freeze
        else
          value.nil? ? nil : canonical_string(value)
        end
      end

      def canonical_string(value)
        value.to_s
             .encode(Encoding::UTF_8)
             .unicode_normalize(:nfc)
             .gsub(/\r\n?/, "\n")
             .freeze
      end
    end
  end
end
