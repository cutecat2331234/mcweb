# frozen_string_literal: true

module Identity
  module DataExporting
    class Contribution
      PATH_PATTERN = /\A(?!\/)(?!.*(?:\A|\/)\.\.(?:\/|\z))[a-zA-Z0-9][a-zA-Z0-9._\/-]*\.(?:json|jsonl)\z/
      RESERVED_PATHS = %w[manifest.json].freeze
      MAX_JSON_DEPTH = 100
      JSON_VALIDATION_CHUNK_BYTES = 64.kilobytes

      class InvalidPayload < StandardError
        attr_reader :reason

        def initialize(reason:)
          @reason = reason
          super("data export contribution payload invalid")
        end
      end

      class << self
        def validate_payload!(payload)
          validate_value!(payload, depth: 0, ancestors: {})
          payload
        end

        private

        def validate_value!(value, depth:, ancestors:)
          case value
          when StreamingDocument, StreamingObjectDocument
            nil
          when Hash
            validate_container!(value, depth:, ancestors:) do |next_depth|
              value.each do |key, member|
                validate_string!(stringify_key!(key))
                validate_value!(member, depth: next_depth, ancestors:)
              end
            end
          when Array
            validate_container!(value, depth:, ancestors:) do |next_depth|
              value.each { |member| validate_value!(member, depth: next_depth, ancestors:) }
            end
          when String
            validate_string!(value)
          else
            generate_json!(value)
          end
        end

        def validate_container!(container, depth:, ancestors:)
          invalid_payload!(:maximum_depth) if depth >= MAX_JSON_DEPTH

          identity = container.object_id
          invalid_payload!(:circular_reference) if ancestors.key?(identity)

          ancestors[identity] = true
          begin
            yield depth + 1
          ensure
            ancestors.delete(identity)
          end
        end

        def validate_string!(value)
          buffer = +""
          value.each_char do |character|
            buffer << character
            next if buffer.bytesize < JSON_VALIDATION_CHUNK_BYTES

            generate_json!(buffer)
            buffer.clear
          end
          generate_json!(buffer) unless buffer.empty?
        rescue InvalidPayload
          raise
        rescue StandardError => error
          invalid_payload!(:invalid_encoding, cause: error)
        end

        def stringify_key!(key)
          key.to_s
        rescue StandardError => error
          invalid_payload!(:invalid_key, cause: error)
        end

        def generate_json!(value)
          JSON.generate(value)
        rescue StandardError => error
          invalid_payload!(:invalid_json_value, cause: error)
        end

        def invalid_payload!(reason, cause: nil)
          error = InvalidPayload.new(reason:)
          raise error, cause: cause if cause

          raise error
        end
      end

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

          if payload.is_a?(StreamingDocument)
            expected_suffix = payload.jsonl? ? ".jsonl" : ".json"
            raise ArgumentError, "data_export_stream_path_invalid" unless normalized_path.end_with?(expected_suffix)
          elsif payload.is_a?(StreamingObjectDocument)
            raise ArgumentError, "data_export_stream_path_invalid" unless normalized_path.end_with?(".json")
          elsif normalized_path.end_with?(".jsonl")
            raise ArgumentError, "data_export_stream_document_required"
          end
          self.class.validate_payload!(payload)
          result[normalized_path.freeze] = payload
        end.freeze
        @file_counts = @documents.transform_values { |payload| payload_record_count(payload) }.freeze
      end

      def record_count(counts = file_counts)
        counts.values.sum
      end

      def manifest(file_counts: self.file_counts)
        {
          "status" => "completed",
          "record_count" => record_count(file_counts),
          "files" => file_counts.map do |path, count|
            { "path" => path, "record_count" => count }
          end
        }
      end

      private

      def payload_record_count(payload)
        return payload.declared_count if payload.is_a?(StreamingDocument) || payload.is_a?(StreamingObjectDocument)

        payload.is_a?(Array) ? payload.length : 1
      end
    end
  end
end
