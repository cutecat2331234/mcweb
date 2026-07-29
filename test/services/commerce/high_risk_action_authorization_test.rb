# frozen_string_literal: true

require "test_helper"

module Commerce
  class HighRiskActionAuthorizationTest < ActiveSupport::TestCase
    setup do
      @actor = create_user(account_type: "staff")
      @target = create_user
      grant_permission(@actor, "store.entitlements.grant")
      @request_id = SecureRandom.uuid
      @targets = [
        { type: "user", id: @target.public_id },
        { type: "membership_type", id: 42 }
      ]
      @state = {
        user_updated_at: @target.updated_at,
        active_memberships: []
      }
      @attributes = { grant_game_permissions: false }
      @reason = "Support case MC-1208"
    end

    test "short lived challenge is bound to actor action targets state values request and reason" do
      result = issue
      assert_predicate result, :success?, result.error
      authorization = result.value

      assert HighRiskActionAuthorization.valid?(
        authorization[:authorization_token],
        **validation_attributes
      )

      other_actor = create_user(account_type: "staff")
      grant_permission(other_actor, "store.entitlements.grant")
      changes = [
        { actor: other_actor },
        { action: "entitlement.grant" },
        { targets: [ { type: "user", id: create_user.public_id } ] },
        { state: @state.merge(active_memberships: [ { id: 99 } ]) },
        { attributes: { grant_game_permissions: true } },
        { request_id: SecureRandom.uuid },
        { reason: "Different reason" }
      ]

      changes.each do |change|
        refute HighRiskActionAuthorization.valid?(
          authorization[:authorization_token],
          **validation_attributes.merge(change)
        )
      end

      travel HighRiskActionAuthorization::EXPIRES_IN + 1.second do
        refute HighRiskActionAuthorization.valid?(
          authorization[:authorization_token],
          **validation_attributes
        )
      end
    end

    test "typed challenge is deterministic for the exact action target set and request" do
      result = issue
      assert_predicate result, :success?, result.error
      confirmation = result.value[:confirmation]

      assert HighRiskActionAuthorization.confirmation_valid?(
        confirmation,
        action: "membership.grant",
        targets: @targets,
        request_id: @request_id
      )
      refute HighRiskActionAuthorization.confirmation_valid?(
        confirmation,
        action: "membership.grant",
        targets: @targets.reverse,
        request_id: @request_id
      )
      refute HighRiskActionAuthorization.confirmation_valid?(
        confirmation,
        action: "membership.grant",
        targets: @targets,
        request_id: SecureRandom.uuid
      )
    end

    test "dedicated permission request id target and reason are required" do
      unauthorized = create_user(account_type: "staff")
      denied = HighRiskActionAuthorization.issue(
        actor: unauthorized,
        action: "membership.grant",
        targets: @targets,
        state: @state,
        attributes: @attributes,
        request_id: @request_id,
        reason: @reason
      )
      assert_predicate denied, :failure?
      assert_equal I18n.t("mcweb.services.errors.high_risk_unauthorized"), denied.error

      {
        request_id: [ "not-a-uuid", "high_risk_request_id_invalid" ],
        reason: [ " ", "high_risk_reason_required" ],
        targets: [ [], "high_risk_targets_required" ]
      }.each do |attribute, (value, error_key)|
        invalid = HighRiskActionAuthorization.issue(
          actor: @actor,
          action: "membership.grant",
          targets: @targets,
          state: @state,
          attributes: @attributes,
          request_id: @request_id,
          reason: @reason,
          **{ attribute => value }
        )
        assert_predicate invalid, :failure?
        assert_equal I18n.t("mcweb.services.errors.#{error_key}"), invalid.error
      end
    end

    private

    def issue
      HighRiskActionAuthorization.issue(
        actor: @actor,
        action: "membership.grant",
        targets: @targets,
        state: @state,
        attributes: @attributes,
        request_id: @request_id,
        reason: @reason
      )
    end

    def validation_attributes
      {
        actor: @actor,
        action: "membership.grant",
        targets: @targets,
        state: @state,
        attributes: @attributes,
        request_id: @request_id,
        reason: @reason
      }
    end
  end
end
