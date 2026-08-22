# frozen_string_literal: true

module Identity
  module DataExporting
    module RecordSerializer
      module_function

      def record(item, fields)
        item.attributes.slice(*fields)
      end

      def records(relation, fields)
        relation.map { |item| record(item, fields) }
      end
    end
  end
end
