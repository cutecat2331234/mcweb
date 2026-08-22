# frozen_string_literal: true

# Prevents browser/history caches from retaining responses that gain private
# fields when a signed-in viewer is the subject or has an explicit permission.
module ViewerScopedNoStoreResponse
  extend ActiveSupport::Concern

  included do
    after_action :set_viewer_scoped_no_store_response, if: :logged_in?
  end

  private

  def set_viewer_scoped_no_store_response
    response.set_header("Cache-Control", "private, no-store")
  end
end
