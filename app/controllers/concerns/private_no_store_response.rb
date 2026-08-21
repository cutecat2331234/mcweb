# frozen_string_literal: true

module PrivateNoStoreResponse
  extend ActiveSupport::Concern

  included do
    after_action :set_private_no_store_response
  end

  private

  def set_private_no_store_response
    response.set_header("Cache-Control", "private, no-store")
  end
end
