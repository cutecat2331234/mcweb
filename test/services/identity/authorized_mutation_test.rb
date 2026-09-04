# frozen_string_literal: true

require "test_helper"
require "timeout"

module Identity
  class AuthorizedMutationTest < ActiveSupport::TestCase
    self.use_transactional_tests = false

    setup do
      @actor = create_user(display_name: "Before")
      @permission = Permission.find_or_create_by!(key: "forum.users.warn") do |permission|
        permission.name = "Warn users"
        permission.category = "forum"
      end
      @role = Role.create!(
        key: "authorized_mutation_#{SecureRandom.hex(5)}",
        name: "Authorized mutation test"
      )
      @role.grant_permission!(@permission)
      UserRole.create!(user: @actor, role: @role)
      @actor.reload
    end

    teardown do
      UserRole.where(user_id: @actor&.id).delete_all
      RolePermission.where(role_id: @role&.id).delete_all
      Role.where(id: @role&.id).delete_all
      User.where(id: @actor&.id).destroy_all
    end

    test "a stale actor is denied when permission was revoked before the lease" do
      assert @actor.permission?(@permission.key)
      @role.revoke_permission!(@permission)

      yielded = false
      result = AuthorizedMutation.with(
        actor: @actor,
        all_of: @permission.key
      ) do
        yielded = true
        ServiceResult.success
      end

      assert result.failure?
      assert_equal "forbidden", result.code
      assert_not yielded
    end

    test "a permission revocation waits for an authorized mutation to commit" do
      mutation_paused = Queue.new
      release_mutation = Queue.new
      mutation_result = Queue.new
      writer_started = Queue.new
      writer_pid = Queue.new
      writer_result = Queue.new

      mutation = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          mutation_result << AuthorizedMutation.with(
            actor: @actor,
            all_of: @permission.key
          ) do |fresh_actor|
            mutation_paused << true
            release_mutation.pop
            fresh_actor.update!(display_name: "Committed first")
            ServiceResult.success
          end
        end
      end
      mutation_paused.pop

      writer = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          writer_pid << connection.select_value("SELECT pg_backend_pid()").to_i
          writer_started << true
          writer_result << @role.revoke_permission!(@permission)
        end
      end
      writer_started.pop
      wait_until_advisory_lock_wait(writer_pid.pop)

      assert_predicate writer, :alive?,
                       "permission revocation should wait for the authorized write"

      release_mutation << true
      assert mutation.join(5), "authorized mutation thread did not finish"
      assert writer.join(5), "permission revocation thread did not finish"

      assert mutation_result.pop.success?
      writer_result.pop
      assert_equal "Committed first", @actor.reload.display_name
      assert_not @actor.permission?(@permission.key)
    ensure
      release_mutation << true if mutation&.alive?
      mutation&.join(5)
      writer&.join(5)
    end

    test "an ineligible actor never enters the mutation block" do
      @actor.update!(status: :banned, banned_at: Time.current)

      result = AuthorizedMutation.with(actor: @actor) do
        flunk "ineligible actor must not be yielded"
      end

      assert result.failure?
      assert_equal "forbidden", result.code
    end

    private

    def wait_until_advisory_lock_wait(backend_pid)
      lock_key = PermissionMutationLock::LOCK_KEY
      lock_class_id = (lock_key >> 32) & 0xffff_ffff
      lock_object_id = lock_key & 0xffff_ffff
      waiting_lock_sql = ApplicationRecord.sanitize_sql_array(
        [
          <<~SQL.squish,
            SELECT 1
            FROM pg_locks
            WHERE locktype = 'advisory'
              AND database = (
                SELECT oid FROM pg_database WHERE datname = current_database()
              )
              AND classid = ?::oid
              AND objid = ?::oid
              AND objsubid = 1
              AND mode = 'ExclusiveLock'
              AND granted = FALSE
              AND pid = ?
            LIMIT 1
          SQL
          lock_class_id,
          lock_object_id,
          backend_pid
        ]
      )

      Timeout.timeout(5) do
        loop do
          waiting_lock = ApplicationRecord.uncached do
            ApplicationRecord.connection.select_value(waiting_lock_sql)
          end
          break if waiting_lock

          sleep 0.01
        end
      end
    end
  end
end
