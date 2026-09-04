# frozen_string_literal: true

module Identity
  module DataExporting
    class StreamingObjectDocument
      MEMBER_PATTERN = /\A[a-zA-Z0-9][a-zA-Z0-9_-]*\z/

      attr_reader :members

      def initialize(members:)
        source = members.to_h
        raise ArgumentError, "data_export_stream_members_required" if source.empty?

        @members = source.each_with_object({}) do |(key, document), result|
          normalized_key = key.to_s
          unless normalized_key.match?(MEMBER_PATTERN) && document.is_a?(StreamingDocument) && !document.jsonl?
            raise ArgumentError, "data_export_stream_member_invalid"
          end
          raise ArgumentError, "data_export_stream_member_duplicate" if result.key?(normalized_key)

          result[normalized_key.freeze] = document
        end.freeze
      end

      def declared_count
        members.values.sum(&:declared_count)
      end
    end
  end
end
