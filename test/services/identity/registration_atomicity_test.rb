# frozen_string_literal: true

require "test_helper"

module Identity
  class RegistrationAtomicityTest < ActiveSupport::TestCase
    setup do
      clear_enqueued_jobs
      @default_group = Community::UserGroup.create!(
        name: "Atomic registration #{SecureRandom.hex(4)}",
        priority: 1_000_000,
        is_primary_default: true,
        permissions: [ "forum.basic" ]
      )
    end

    test "registration commits identity fields groups audit and a secret-safe durable delivery together" do
      result = register

      assert_predicate result, :success?
      user = result.value.fetch(:user).reload
      token = result.value.fetch(:verification_token)
      assert_equal @default_group, user.group_memberships.find_by!(is_primary: true).user_group
      audit = AuditLog.find_by!(action: "identity.register", resource_id: user.id)

      intent = Operations::DurableEnqueueIntent.find_by!(
        handler_key: EmailVerificationDelivery::HANDLER_KEY,
        source_id: user.id
      )
      assert_equal "mailers", intent.queue_name
      assert_equal Digest::SHA256.hexdigest(token), intent.arguments.fetch("token_digest")
      refute_includes intent.attributes.to_json, token
      refute_includes audit.attributes.to_json, token
      refute_includes audit.attributes.to_json, "password123"
      refute_equal token, user.email_verification_token_ciphertext
      assert_equal token, user.email_verification_token
    end

    test "required custom field failure rolls every registration record back" do
      Community::UserFieldDefinition.create!(
        key: "atomic_required_#{SecureRandom.hex(3)}",
        label: "Required field",
        field_type: "text",
        visibility: "public",
        active: true,
        show_on_registration: true,
        editable_by_user: true,
        required: true,
        sort_order: 0
      )

      assert_registration_rollback do
        result = register(user_fields: {})
        assert_predicate result, :failure?
      end
    end

    test "default group failure rolls the user and earlier custom values back" do
      field = Community::UserFieldDefinition.create!(
        key: "atomic_value_#{SecureRandom.hex(3)}",
        label: "Profile value",
        field_type: "text",
        visibility: "public",
        active: true,
        show_on_registration: true,
        editable_by_user: true,
        required: false,
        sort_order: 0
      )
      error = invalid_record(Community::GroupMembership)

      Community::GroupMembership.stub(:create!, ->(**) { raise error }) do
        assert_registration_rollback do
          result = register(user_fields: { field.key => "must roll back" })
          assert_predicate result, :failure?
        end
      end
      assert_empty Community::UserFieldValue.where(definition: field)
    end

    test "audit failure rolls the user and group membership back" do
      error = invalid_record(AuditLog)

      Administration::AuditLogger.stub(:call, ->(**) { raise error }) do
        assert_registration_rollback do
          result = register
          assert_predicate result, :failure?
        end
      end
    end

    test "durable intent recording failure returns a recoverable error without reserving identity" do
      failure = Operations::DurableEnqueue::InvalidRequest.new("injected")

      EmailVerificationDelivery.stub(:record!, ->(**) { raise failure }) do
        assert_registration_rollback do
          result = register
          assert_predicate result, :failure?
          assert_equal "registration_temporarily_unavailable", result.code
        end
      end
    end

    test "durable worker decrypts the token only at delivery time" do
      result = register
      intent = Operations::DurableEnqueueIntent.find_by!(
        handler_key: EmailVerificationDelivery::HANDLER_KEY,
        source_id: result.value.fetch(:user).id
      )

      assert_difference -> { ActionMailer::Base.deliveries.size }, 1 do
        Operations::DispatchDurableIntentJob.perform_now(intent.id, 1, "maintenance")
      end

      assert_equal "succeeded", Operations::DurableEnqueueLedger.state(intent).status
    end

    test "queue handoff failure leaves a recoverable durable intent" do
      callbacks = []
      result = nil
      ActiveRecord.stub(:after_all_transactions_commit, ->(&callback) { callbacks << callback }) do
        result = register
      end
      intent = Operations::DurableEnqueueIntent.find_by!(
        handler_key: EmailVerificationDelivery::HANDLER_KEY,
        source_id: result.value.fetch(:user).id
      )
      assert_equal 1, callbacks.size

      Operations::DispatchDurableIntentJob.stub(:set, ->(**) { raise IOError, "queue unavailable" }) do
        dispatch = callbacks.sole.call
        assert_predicate dispatch, :failure?
      end

      assert_equal "enqueue_failed", intent.events.order(:sequence).last.event_type
      refute_predicate Operations::DurableEnqueueLedger.state(intent), :terminal?
      assert User.exists?(result.value.fetch(:user).id)
    end

    private

    def register(user_fields: {})
      suffix = SecureRandom.hex(5)
      Identity::RegisterUser.call(
        email: "atomic-#{suffix}@example.com",
        username: "atomic#{suffix}",
        password: "password123",
        user_fields:,
        ip_address: "127.0.0.1"
      )
    end

    def assert_registration_rollback
      assert_no_difference -> { User.count } do
        assert_no_difference -> { Community::GroupMembership.count } do
          assert_no_difference -> { AuditLog.where(action: "identity.register").count } do
            assert_no_difference -> {
              Operations::DurableEnqueueIntent.where(
                handler_key: EmailVerificationDelivery::HANDLER_KEY
              ).count
            } do
              yield
            end
          end
        end
      end
    end

    def invalid_record(model_class)
      record = model_class.new
      record.errors.add(:base, "injected failure")
      ActiveRecord::RecordInvalid.new(record)
    end
  end
end
