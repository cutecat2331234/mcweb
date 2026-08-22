# frozen_string_literal: true

module Identity
  module DataExporting
    class NotificationsContributor
      FIELDS = %w[id notification_type title body metadata read_at created_at].freeze

      def self.call(context:)
        Contribution.new(
          documents: {
            "notifications.json" => RecordSerializer.records(
              Notification.where(user: context.user).order(:id),
              FIELDS
            )
          }
        )
      end
    end
  end
end
