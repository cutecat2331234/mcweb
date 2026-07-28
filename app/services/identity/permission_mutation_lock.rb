# frozen_string_literal: true

module Identity
  class PermissionMutationLock
    LOCK_KEY = 0x4D43_5745_4249_4447

    LOCK_STATEMENTS = {
      exclusive: "SELECT pg_advisory_xact_lock(?)",
      shared: "SELECT pg_advisory_xact_lock_shared(?)"
    }.freeze

    class << self
      def acquire_exclusive!
        acquire!(:exclusive)
      end

      def acquire_shared!
        acquire!(:shared)
      end

      def with_exclusive(&)
        with_lock(:exclusive, &)
      end

      def with_shared(&)
        with_lock(:shared, &)
      end

      private

      def acquire!(mode)
        connection = ApplicationRecord.connection
        unless connection.transaction_open?
          raise ActiveRecord::ActiveRecordError,
                "identity permission mutation lock requires an open transaction"
        end

        statement = LOCK_STATEMENTS.fetch(mode)
        sql = ApplicationRecord.sanitize_sql_array([ statement, LOCK_KEY ])
        connection.execute(sql)
      end

      def with_lock(mode)
        ApplicationRecord.transaction do
          acquire!(mode)
          yield
        end
      end
    end
  end
end
