# frozen_string_literal: true

module Identity
  module DataExporting
    class CommunityUploadsContributor
      FIELDS = %w[
        public_id kind status scan_status content_type byte_size created_at linked_at cleaned_at
        manual_review_status manual_reviewed_at manual_review_revoked_at
      ].freeze

      def self.call(context:)
        Contribution.new(
          documents: {
            "uploads.json" => RecordSerializer.stream_records(
              Community::Upload.where(user: context.user).order(:id),
              FIELDS
            )
          }
        )
      end
    end
  end
end
