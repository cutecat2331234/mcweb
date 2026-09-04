# frozen_string_literal: true

module Identity
  module DataExporting
    class StreamingDocument
      include Enumerable

      FORMATS = %i[json_array jsonl].freeze

      class IterationFailure < StandardError
        attr_reader :failure_class

        def initialize(failure_class)
          @failure_class = failure_class
          super("data export stream iteration failed")
        end
      end

      attr_reader :declared_count, :format

      def initialize(declared_count:, format: :jsonl, &enumerator_factory)
        count = Integer(declared_count, exception: false)
        raise ArgumentError, "data_export_stream_count_invalid" unless count && count >= 0
        raise ArgumentError, "data_export_stream_factory_required" unless enumerator_factory
        raise ArgumentError, "data_export_stream_format_invalid" unless format.to_sym.in?(FORMATS)

        @declared_count = count
        @format = format.to_sym
        @enumerator_factory = enumerator_factory
      end

      def jsonl?
        format == :jsonl
      end

      def each_record
        return enum_for(:each_record) unless block_given?

        records = begin
          @enumerator_factory.call
        rescue StandardError => error
          raise IterationFailure.new(error.class.name), cause: error
        end
        unless records.respond_to?(:each)
          raise IterationFailure.new("invalid_stream_enumerator")
        end

        iterator = records.to_enum
        loop do
          record = begin
            iterator.next
          rescue StopIteration
            break
          rescue StandardError => error
            raise IterationFailure.new(error.class.name), cause: error
          end
          # Consumer failures (ZIP I/O, disk exhaustion, size enforcement) must
          # remain outside the producer rescue so they retain their true class.
          yield record
        end
      end

      alias each each_record

      def size
        declared_count
      end
    end
  end
end
