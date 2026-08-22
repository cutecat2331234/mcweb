# frozen_string_literal: true

module Identity
  module DataExporting
    class Contribution
      PATH_PATTERN = /\A(?!\/)(?!.*(?:\A|\/)\.\.(?:\/|\z))[a-zA-Z0-9][a-zA-Z0-9._\/-]*\.json\z/
      RESERVED_PATHS = %w[manifest.json].freeze

      attr_reader :documents, :file_counts

      def initialize(documents:)
        source = documents.to_h
        raise ArgumentError, "data_export_contribution_files_required" if source.empty?

        @documents = source.each_with_object({}) do |(path, payload), result|
          normalized_path = path.to_s
          unless normalized_path.match?(PATH_PATTERN) && RESERVED_PATHS.exclude?(normalized_path)
            raise ArgumentError, "data_export_contribution_path_invalid"
          end
          raise ArgumentError, "data_export_contribution_path_duplicate" if result.key?(normalized_path)

          JSON.generate(payload)
          result[normalized_path.freeze] = payload
        end.freeze
        @file_counts = @documents.transform_values { |payload| payload_record_count(payload) }.freeze
      end

      def record_count
        file_counts.values.sum
      end

      def manifest
        {
          "status" => "completed",
          "record_count" => record_count,
          "files" => file_counts.map do |path, count|
            { "path" => path, "record_count" => count }
          end
        }
      end

      private

      def payload_record_count(payload)
        payload.is_a?(Array) ? payload.length : 1
      end
    end
  end
end
