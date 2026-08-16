# frozen_string_literal: true

require "test_helper"

module Mcweb
  class DatabaseSchemaDeliveryTest < ActiveSupport::TestCase
    test "fresh database schema includes durable enqueue ledgers and their guards" do
      schema = Rails.root.join("db/schema.rb").read

      %w[
        operations_durable_enqueue_intents
        operations_durable_enqueue_attempts
        operations_durable_enqueue_events
      ].each do |table|
        assert_includes schema, %(create_table "#{table}")
      end

      %w[
        operations_durable_intents_immutable
        operations_durable_attempts_immutable
        operations_durable_attempts_validate
        operations_durable_events_immutable
        operations_durable_events_validate
      ].each do |trigger|
        assert_includes schema, "CREATE TRIGGER #{trigger}"
      end
    end
  end
end
