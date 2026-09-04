# frozen_string_literal: true

module Identity
  class PurgeDataExportBlobJob < ApplicationJob
    queue_as :maintenance

    def perform(blob_id)
      blob = ActiveStorage::Blob.find_by(id: blob_id)
      return true unless blob

      Identity::DataExportBlobCleanup.purge_now(blob)
    end
  end
end
