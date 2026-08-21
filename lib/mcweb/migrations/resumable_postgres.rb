# frozen_string_literal: true

module Mcweb
  module Migrations
    module ResumablePostgres
      private

      def ensure_check_constraint(table, expression, name:)
        unless constraint_definition(table, name)
          add_check_constraint table,
            expression,
            name: name,
            validate: false
        end
        validate_check_constraint table, name: name unless constraint_validated?(table, name)
      end

      def ensure_foreign_key(table, to_table, column:)
        foreign_key = connection.foreign_keys(table).find do |candidate|
          candidate.to_table == to_table.to_s && candidate.options[:column].to_s == column.to_s
        end
        unless foreign_key
          add_foreign_key table,
            to_table,
            column: column,
            validate: false
          foreign_key = connection.foreign_keys(table).find do |candidate|
            candidate.to_table == to_table.to_s && candidate.options[:column].to_s == column.to_s
          end
        end
        return unless foreign_key
        return if constraint_validated?(table, foreign_key.name)

        validate_foreign_key table, to_table, column: column
      end

      def ensure_concurrent_index(table, columns, name:, **options)
        if postgres_index_present?(name)
          return if postgres_index_valid?(name)

          remove_index table, name: name, algorithm: :concurrently, if_exists: true
        end

        add_index table,
          columns,
          name: name,
          algorithm: :concurrently,
          if_not_exists: true,
          **options
      end

      def remove_concurrent_index(table, name:)
        remove_index table, name: name, algorithm: :concurrently, if_exists: true
      end

      def constraint_validated?(table, name)
        connection.select_value(<<~SQL.squish) == true
          SELECT constraint_state.convalidated
          FROM pg_constraint constraint_state
          WHERE constraint_state.conrelid = #{connection.quote(table.to_s)}::regclass
            AND constraint_state.conname = #{connection.quote(name.to_s)}
          LIMIT 1
        SQL
      end

      def constraint_definition(table, name)
        connection.select_value(<<~SQL.squish)
          SELECT pg_get_constraintdef(constraint_state.oid, true)
          FROM pg_constraint constraint_state
          WHERE constraint_state.conrelid = #{connection.quote(table.to_s)}::regclass
            AND constraint_state.conname = #{connection.quote(name.to_s)}
          LIMIT 1
        SQL
      end

      def postgres_index_valid?(name)
        connection.select_value(<<~SQL.squish) == true
          SELECT index_state.indisvalid AND index_state.indisready
          FROM pg_index index_state
          WHERE index_state.indexrelid = to_regclass(#{connection.quote(name.to_s)})
        SQL
      end

      def postgres_index_present?(name)
        connection.select_value(<<~SQL.squish).present?
          SELECT to_regclass(#{connection.quote(name.to_s)})::oid
        SQL
      end
    end
  end
end
