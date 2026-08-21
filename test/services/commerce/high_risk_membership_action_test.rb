# frozen_string_literal: true

require "test_helper"

module Commerce
  class HighRiskMembershipActionTest < ActiveSupport::TestCase
    setup do
      @actor = create_user(account_type: "staff")
      @target = create_user
      @membership_type = Commerce::MembershipType.create!(
        slug: "risk-vip-#{SecureRandom.hex(4)}",
        name: "Risk VIP",
        duration_mode: "fixed_days",
        duration_days: 30,
        game_permission_enabled: false,
        active: true
      )
      @request_id = SecureRandom.uuid
      @reason = "Approved support request MC-2201"
      grant_permission(@actor, "store.entitlements.grant")
    end

    test "grant writes membership immutable operation and redacted audit in one transaction" do
      authorization = authorize_grant

      result = nil
      assert_difference -> { Commerce::UserMembership.count }, 1 do
        assert_difference -> { Commerce::HighRiskOperation.count }, 1 do
          assert_difference -> { AuditLog.by_action("commerce.membership_grant").count }, 1 do
            result = execute_grant(authorization)
          end
        end
      end

      assert_predicate result, :success?, result.error
      refute result.value[:idempotent]
      membership = result.value[:membership]
      assert membership.active?
      assert_equal "admin_grant", membership.source

      operation = result.value[:operation]
      assert_equal @request_id, operation.request_id
      assert_equal @actor, operation.actor
      assert_equal @target, operation.target_user
      assert_equal @reason, operation.reason
      assert_equal membership.id, operation.metadata["membership_id"]
      assert_equal 64, operation.authorization_digest.length
      refute operation.update(reason: "tampered")

      audit = AuditLog.by_action("commerce.membership_grant").order(:id).last
      assert_equal @request_id, audit.metadata["request_id"]
      assert_equal @reason, audit.reason
      assert_equal operation.id, audit.metadata["high_risk_operation_id"]
      refute audit.metadata.key?("authorization_token")
      refute audit.metadata.key?("confirmation")
    end

    test "identical replay returns original result and changed payload reusing request id is rejected" do
      authorization = authorize_grant
      first = execute_grant(authorization)
      assert_predicate first, :success?, first.error

      replay = nil
      assert_no_difference -> { Commerce::UserMembership.count } do
        assert_no_difference -> { Commerce::HighRiskOperation.count } do
          replay = execute_grant(authorization)
        end
      end
      assert_predicate replay, :success?, replay.error
      assert replay.value[:idempotent]
      assert_equal first.value[:membership].id, replay.value[:membership].id

      conflict = Commerce::HighRiskMembershipAction.call(
        actor: @actor,
        action: "membership.grant",
        user: @target,
        membership_type: @membership_type,
        grant_game_permissions: false,
        request_id: @request_id,
        reason: "A different reason",
        authorization_token: authorization[:authorization_token],
        confirmation: authorization[:confirmation]
      )
      assert_predicate conflict, :failure?
      assert_equal I18n.t("mcweb.services.errors.high_risk_request_id_reused"), conflict.error
      assert_equal 1, Commerce::UserMembership.where(user: @target).count
    end

    test "expired challenge and changed target state fail without creating partial assets" do
      expired_authorization = authorize_grant
      travel Commerce::HighRiskActionAuthorization::EXPIRES_IN + 1.second do
        assert_no_difference -> { Commerce::UserMembership.count } do
          expired = execute_grant(expired_authorization)
          assert_predicate expired, :failure?
          assert_equal I18n.t("mcweb.services.errors.high_risk_authorization_invalid"),
            expired.error
        end
      end

      @request_id = SecureRandom.uuid
      stale_authorization = authorize_grant
      Commerce::UserMembership.create!(
        user: @target,
        membership_type: @membership_type,
        status: "active",
        source: "admin_grant",
        starts_at: 5.days.from_now,
        expires_at: 35.days.from_now
      )

      assert_no_difference -> { Commerce::UserMembership.count } do
        stale = execute_grant(stale_authorization)
        assert_predicate stale, :failure?
        assert_equal I18n.t("mcweb.services.errors.high_risk_authorization_invalid"),
          stale.error
      end
      assert_not Commerce::HighRiskOperation.exists?(request_id: @request_id)
    end

    test "grant call denies a stale actor after permission revocation" do
      authorization = authorize_grant
      permission = Permission.find_by!(key: "store.entitlements.grant")
      role = @actor.roles.joins(:permissions).find_by!(permissions: { id: permission.id })
      assert @actor.permission?(permission.key)
      role.revoke_permission!(permission)

      assert_no_difference -> { Commerce::UserMembership.count } do
        result = execute_grant(authorization)
        assert_predicate result, :failure?
        assert_equal I18n.t("mcweb.services.errors.high_risk_unauthorized"), result.error
      end
      assert_not Commerce::HighRiskOperation.exists?(request_id: @request_id)
    end

    test "grant and revoke use independent permissions and revoke is idempotent" do
      membership = execute_grant(authorize_grant).value[:membership]
      revoke_request_id = SecureRandom.uuid

      denied = Commerce::HighRiskMembershipAction.authorize(
        actor: @actor,
        action: "membership.revoke",
        membership: membership,
        request_id: revoke_request_id,
        reason: @reason
      )
      assert_predicate denied, :failure?
      assert_equal I18n.t("mcweb.services.errors.high_risk_unauthorized"), denied.error

      grant_permission(@actor, "store.entitlements.revoke")
      authorization = Commerce::HighRiskMembershipAction.authorize(
        actor: @actor,
        action: "membership.revoke",
        membership: membership,
        revoke_game_permissions: false,
        request_id: revoke_request_id,
        reason: @reason
      )
      assert_predicate authorization, :success?, authorization.error

      attributes = {
        actor: @actor,
        action: "membership.revoke",
        membership: membership,
        revoke_game_permissions: false,
        request_id: revoke_request_id,
        reason: @reason,
        authorization_token: authorization.value[:authorization_token],
        confirmation: authorization.value[:confirmation]
      }
      first = Commerce::HighRiskMembershipAction.call(**attributes)
      replay = Commerce::HighRiskMembershipAction.call(**attributes)

      assert_predicate first, :success?, first.error
      assert_predicate replay, :success?, replay.error
      assert replay.value[:idempotent]
      assert membership.reload.revoked?
      assert_equal 1,
        Commerce::HighRiskOperation.where(action: "membership.revoke", request_id: revoke_request_id).count
    end

    test "audit failure rolls back membership and operation together" do
      authorization = authorize_grant
      original = Administration::AuditLogger.method(:call)
      Administration::AuditLogger.define_singleton_method(:call) do |**|
        raise ActiveRecord::RecordInvalid.new(AuditLog.new)
      end

      assert_no_difference -> { Commerce::UserMembership.count } do
        assert_no_difference -> { Commerce::HighRiskOperation.count } do
          result = execute_grant(authorization)
          assert_predicate result, :failure?
        end
      end
    ensure
      Administration::AuditLogger.define_singleton_method(:call, original)
    end

    test "membership command failure rolls back the grant operation and audit" do
      @membership_type.update!(
        game_permission_enabled: true,
        grant_commands: [ "lp user {player} parent add vip" ]
      )
      authorization = Commerce::HighRiskMembershipAction.authorize(
        actor: @actor,
        action: "membership.grant",
        user: @target,
        membership_type: @membership_type,
        grant_game_permissions: true,
        request_id: @request_id,
        reason: @reason
      )
      assert_predicate authorization, :success?, authorization.error

      assert_no_difference -> { Commerce::UserMembership.count } do
        assert_no_difference -> { Commerce::HighRiskOperation.count } do
          assert_no_difference -> { AuditLog.by_action("commerce.membership_grant").count } do
            result = Commerce::HighRiskMembershipAction.call(
              actor: @actor,
              action: "membership.grant",
              user: @target,
              membership_type: @membership_type,
              grant_game_permissions: true,
              request_id: @request_id,
              reason: @reason,
              authorization_token: authorization.value[:authorization_token],
              confirmation: authorization.value[:confirmation]
            )
            assert_predicate result, :failure?
            assert_equal I18n.t("mcweb.services.errors.player_not_linked"), result.error
          end
        end
      end
    end

    private

    def authorize_grant
      result = Commerce::HighRiskMembershipAction.authorize(
        actor: @actor,
        action: "membership.grant",
        user: @target,
        membership_type: @membership_type,
        grant_game_permissions: false,
        request_id: @request_id,
        reason: @reason
      )
      assert_predicate result, :success?, result.error
      result.value
    end

    def execute_grant(authorization)
      Commerce::HighRiskMembershipAction.call(
        actor: @actor,
        action: "membership.grant",
        user: @target,
        membership_type: @membership_type,
        grant_game_permissions: false,
        request_id: @request_id,
        reason: @reason,
        authorization_token: authorization[:authorization_token],
        confirmation: authorization[:confirmation]
      )
    end
  end

  class HighRiskMembershipActionConcurrencyTest < ActiveSupport::TestCase
    self.use_transactional_tests = false

    setup do
      @actor = create_user(account_type: "staff")
      @target = create_user
      @membership_type = Commerce::MembershipType.create!(
        slug: "risk-concurrent-#{SecureRandom.hex(5)}",
        name: "Concurrent Risk Membership",
        duration_mode: "fixed_days",
        duration_days: 30,
        game_permission_enabled: false,
        active: true
      )
      grant_permission(@actor, "store.entitlements.grant")
      @request_id = SecureRandom.uuid
      @reason = "Concurrent membership grant verification"
      authorization = Commerce::HighRiskMembershipAction.authorize(
        actor: @actor,
        action: "membership.grant",
        user: @target,
        membership_type: @membership_type,
        grant_game_permissions: false,
        request_id: @request_id,
        reason: @reason
      )
      assert_predicate authorization, :success?, authorization.error
      @authorization = authorization.value
    end

    teardown do
      AuditLog.where("metadata ->> 'request_id' = ?", @request_id).delete_all
      Commerce::HighRiskOperation.where(request_id: @request_id).delete_all
      Commerce::UserMembership.where(
        user_id: @target.id,
        store_membership_type_id: @membership_type.id
      ).delete_all
      Commerce::MembershipType.where(id: @membership_type.id).delete_all
      User.where(id: [ @actor.id, @target.id ]).destroy_all
    end

    test "concurrent identical grants create one membership and one immutable operation" do
      ready = Queue.new
      gate = Queue.new
      results = Queue.new

      threads = 2.times.map do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            ready << true
            gate.pop
            results << Commerce::HighRiskMembershipAction.call(
              actor: User.find(@actor.id),
              action: "membership.grant",
              user: User.find(@target.id),
              membership_type: Commerce::MembershipType.find(@membership_type.id),
              grant_game_permissions: false,
              request_id: @request_id,
              reason: @reason,
              authorization_token: @authorization[:authorization_token],
              confirmation: @authorization[:confirmation]
            )
          end
        end
      end

      2.times { ready.pop }
      2.times { gate << true }
      responses = 2.times.map { results.pop }
      threads.each(&:join)

      assert responses.all?(&:success?), responses.map(&:error).inspect
      assert_equal 1, responses.count { |result| result.value[:idempotent] }
      assert_equal 1, responses.count { |result| !result.value[:idempotent] }
      assert_equal 1, Commerce::UserMembership.where(
        user_id: @target.id,
        store_membership_type_id: @membership_type.id
      ).count
      assert_equal 1, Commerce::HighRiskOperation.where(request_id: @request_id).count
    end
  end
end
