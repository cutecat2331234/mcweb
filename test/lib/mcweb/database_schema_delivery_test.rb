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

    test "fresh database schema includes the authorization mutation barrier" do
      schema = Rails.root.join("db/schema.rb").read

      %w[
        identity_auth_acquire_exclusive_lock
        identity_auth_bump_user_access
        identity_auth_bump_user_roles
        identity_auth_bump_role_permissions
        identity_auth_bump_group_memberships
        identity_auth_bump_group_permissions
      ].each do |function|
        assert_includes schema, "CREATE OR REPLACE FUNCTION public.#{function}()"
      end

      %w[
        identity_auth_users_lock_delete
        identity_auth_users_lock_update
        identity_auth_users_bump_update
        identity_auth_user_roles_lock
        identity_auth_user_roles_bump_insert
        identity_auth_user_roles_bump_update
        identity_auth_user_roles_bump_delete
        identity_auth_role_permissions_lock
        identity_auth_role_permissions_bump_insert
        identity_auth_role_permissions_bump_update
        identity_auth_role_permissions_bump_delete
        identity_auth_group_memberships_lock
        identity_auth_group_memberships_bump_insert
        identity_auth_group_memberships_bump_update
        identity_auth_group_memberships_bump_delete
        identity_auth_group_permissions_lock_update
        identity_auth_group_permissions_bump_update
      ].each do |trigger|
        assert_includes schema, "CREATE TRIGGER #{trigger}"
      end
    end

    test "fresh database schema includes reporter case lifecycle guards" do
      schema = Rails.root.join("db/schema.rb").read

      %w[
        forum_report_supplements
        forum_report_outcome_deliveries
        forum_report_decision_batches
      ].each do |table|
        assert_includes schema, %(create_table "#{table}")
      end

      %w[
        forum_reports_guard_state_transition
        forum_report_supplements_reject_change
        forum_report_supplements_validate_insert
        forum_report_outcome_deliveries_guard_change
        forum_report_outcome_deliveries_validate_insert
        forum_report_decision_batches_reject_change
      ].each do |function|
        assert_includes schema, "CREATE OR REPLACE FUNCTION public.#{function}()"
      end

      %w[
        forum_reports_state_transition_guard
        forum_report_supplements_immutable
        forum_report_supplements_insert_contract
        forum_report_outcome_deliveries_immutable
        forum_report_outcome_deliveries_insert_contract
        forum_report_decision_batches_immutable
      ].each do |trigger|
        assert_includes schema, "CREATE TRIGGER #{trigger}"
      end
    end
  end
end
