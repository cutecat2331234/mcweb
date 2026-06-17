# frozen_string_literal: true

module Community
  class SavedSearchDigestJob < ApplicationJob
    queue_as :mailers

    def perform
      Community::SendSavedSearchDigests.call
    end
  end
end
