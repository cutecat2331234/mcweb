# frozen_string_literal: true

module Identity
  module DataExporting
    module RecordSerializer
      DEFAULT_STREAM_BATCH_SIZE = 50

      module_function

      def record(item, fields)
        item.attributes.slice(*fields)
      end

      def records(relation, fields)
        relation.map { |item| record(item, fields) }
      end

      def stream_records(relation, fields, batch_size: DEFAULT_STREAM_BATCH_SIZE)
        stream_relation(relation, batch_size:) { |item| record(item, fields) }
      end

      def stream_relation(relation, batch_size: DEFAULT_STREAM_BATCH_SIZE, &serializer)
        raise ArgumentError, "data_export_stream_serializer_required" unless serializer

        StreamingDocument.new(declared_count: relation.count, format: :json_array) do
          Enumerator.new do |records|
            relation.reorder(nil).find_in_batches(batch_size:, order: :asc) do |batch|
              batch.each { |item| records << serializer.call(item) }
            end
          end
        end
      end
    end
  end
end
