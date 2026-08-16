# frozen_string_literal: true

require "digest"

module Operations
  class ExclusiveExecution
    Result = Data.define(:status, :value) do
      def acquired?
        status == :acquired
      end

      def contended?
        status == :contended
      end
    end

    LOCK_NAMESPACE = "mcweb:operations:exclusive-execution:v1"
    MAX_NAME_LENGTH = 128
    NAME_PATTERN = /\A[a-z0-9][a-z0-9._:-]*\z/

    class << self
      def try_with(name:)
        normalized_name = normalize_name(name)
        raise ArgumentError, "exclusive execution requires a block" unless block_given?

        ApplicationRecord.connection_pool.with_connection do |connection|
          lock_key = lock_key_for(normalized_name)
          return Result.new(status: :contended, value: nil) unless try_lock(connection, lock_key)

          begin
            Result.new(status: :acquired, value: yield)
          ensure
            unlock(connection, lock_key)
          end
        end
      end

      private

      def normalize_name(name)
        normalized = name.to_s
        unless normalized.length.between?(1, MAX_NAME_LENGTH) && NAME_PATTERN.match?(normalized)
          raise ArgumentError, "exclusive execution name is invalid"
        end

        normalized
      end

      def lock_key_for(name)
        Digest::SHA256.digest("#{LOCK_NAMESPACE}:#{name}").unpack1("q>")
      end

      def try_lock(connection, lock_key)
        query_boolean(connection, "SELECT pg_try_advisory_lock(?)", lock_key)
      end

      def unlock(connection, lock_key)
        return true if query_boolean(connection, "SELECT pg_advisory_unlock(?)", lock_key)

        raise ActiveRecord::ActiveRecordError, "exclusive execution lock was not held"
      end

      def query_boolean(connection, statement, lock_key)
        sql = ApplicationRecord.sanitize_sql_array([ statement, lock_key ])
        ActiveModel::Type::Boolean.new.cast(connection.select_value(sql))
      end
    end
  end
end
