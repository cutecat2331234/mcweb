# frozen_string_literal: true

module Maintenance
  class ReconcileAccountClosureContentJob < ApplicationJob
    queue_as :maintenance

    def perform(limit: Identity::AccountClosure::ReconcileAuthoredContentDeletion::DEFAULT_LIMIT)
      Identity::AccountClosure::ReconcileAuthoredContentDeletion.call(limit:)
    end
  end
end
