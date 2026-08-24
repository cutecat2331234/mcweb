# frozen_string_literal: true

# Prevents browser/history and shared caches from retaining responses whose
# profile activity fields vary by viewer permission or the subject's opt-in.
module ViewerScopedNoStoreResponse
  extend ActiveSupport::Concern

  included do
    after_action :set_viewer_scoped_no_store_response, if: :viewer_scoped_no_store_response?
  end

  private

  def mark_viewer_scoped_no_store_response!
    @viewer_scoped_no_store_response = true
  end

  def viewer_scoped_no_store_response?
    logged_in? || @viewer_scoped_no_store_response == true
  end

  def set_viewer_scoped_no_store_response
    response.set_header("Cache-Control", "private, no-store")
  end
end
