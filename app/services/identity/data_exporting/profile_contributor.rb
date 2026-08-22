# frozen_string_literal: true

module Identity
  module DataExporting
    class ProfileContributor
      FIELDS = %w[
        public_id email username display_name bio locale time_zone created_at updated_at
        email_verified email_verified_at status account_type deleted_at
      ].freeze

      def self.call(context:)
        Contribution.new(
          documents: {
            "profile.json" => RecordSerializer.record(context.user, FIELDS)
          }
        )
      end
    end
  end
end
