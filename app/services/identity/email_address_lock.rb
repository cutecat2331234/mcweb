# frozen_string_literal: true

module Identity
  class EmailAddressLock
    class << self
      def acquire!(*addresses)
        connection = ApplicationRecord.connection
        unless connection.transaction_open?
          raise ActiveRecord::ActiveRecordError,
                "identity email address lock requires an open transaction"
        end

        normalized(addresses).each do |email|
          key = Digest::SHA256.digest(email).unpack1("q>")
          sql = ApplicationRecord.sanitize_sql_array(
            [ "SELECT pg_advisory_xact_lock(?)", key ]
          )
          connection.execute(sql)
        end
      end

      private

      def normalized(addresses)
        addresses.flatten.filter_map do |address|
          value = address.to_s.strip.downcase
          value.presence
        end.uniq.sort
      end
    end
  end
end
