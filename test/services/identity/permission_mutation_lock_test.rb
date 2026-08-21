# frozen_string_literal: true

require "test_helper"
require "timeout"

module Identity
  class PermissionMutationLockTest < ActiveSupport::TestCase
    self.use_transactional_tests = false

    setup do
      @owner = create_user(account_type: "owner")
      @member = create_user
      @permission = Permission.find_or_create_by!(key: "forum.topics.lock") do |permission|
        permission.name = "Lock topics"
        permission.category = "forum"
      end
      @role = Role.create!(
        key: "legacy_barrier_#{SecureRandom.hex(5)}",
        name: "Legacy barrier role"
      )
      RolePermission.create!(role: @role, permission: @permission)
      UserRole.create!(user: @member, role: @role)
    end

    teardown do
      AuditLog.where(resource_type: "Role", resource_id: @role&.id).delete_all
      UserRole.where(role_id: @role&.id).delete_all
      RolePermission.where(role_id: @role&.id).delete_all
      Role.where(id: @role&.id).delete_all
      User.where(id: [ @owner&.id, @member&.id ].compact).destroy_all
    end

    test "legacy permission revocation blocks shared readers until commit" do
      assert_equal 0x4D43_5745_4249_4447, PermissionMutationLock::LOCK_KEY
      assert @member.permission?(@permission.key)

      mutation_paused = Queue.new
      release_mutation = Queue.new
      mutation_result = Queue.new
      reader_started = Queue.new
      reader_prewarmed = Queue.new
      reader_pid = Queue.new
      reader_result = Queue.new
      original_audit_call = Administration::AuditLogger.method(:call)

      audit_interceptor = lambda do |**arguments|
        if arguments[:action] == "identity.role.updated" &&
            arguments[:resource]&.id == @role.id
          mutation_paused << true
          release_mutation.pop
        end
        original_audit_call.call(**arguments)
      end

      Administration::AuditLogger.stub(:call, audit_interceptor) do
        writer = start_revocation(mutation_result)
        mutation_paused.pop

        reader = start_shared_reader(
          started: reader_started,
          prewarmed: reader_prewarmed,
          backend_pid: reader_pid,
          result: reader_result
        )
        assert reader_prewarmed.pop,
               "reader connection should cache the permission before revocation commits"
        reader_started.pop
        wait_until_advisory_lock_wait(reader_pid.pop)

        assert_predicate reader, :alive?,
                         "shared reader should remain blocked by the uncommitted revocation"

        release_mutation << true
        assert writer.join(5), "permission mutation thread did not finish"
        assert reader.join(5), "shared reader thread did not finish"
      ensure
        release_mutation << true if writer&.alive?
        writer&.join(5)
        reader&.join(5)
      end

      result = mutation_result.pop
      assert result.success?, result.error
      assert_equal false, reader_result.pop
      assert_not @member.reload.permission?(@permission.key)
    end

    test "direct acquisition requires an open transaction" do
      error = assert_raises(ActiveRecord::ActiveRecordError) do
        PermissionMutationLock.acquire_exclusive!
      end

      assert_equal(
        "identity permission mutation lock requires an open transaction",
        error.message
      )
    end

    test "owner demotion orders against cached high-risk readers" do
      target = create_user(account_type: "owner")
      reader_ready = Queue.new
      start_reader = Queue.new
      reader_pid = Queue.new
      reader_result = Queue.new
      writer_paused = Queue.new
      release_writer = Queue.new
      writer_result = Queue.new

      reader = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          connection.cache do
            stale_actor = User.find(target.id)
            assert stale_actor.permission?("identity.owner.demotion_probe")
            reader_pid << connection.select_value("SELECT pg_backend_pid()").to_i
            reader_ready << true
            start_reader.pop
            reader_result << AuthorizedMutation.with(
              actor: stale_actor,
              any_of: [ "identity.owner.demotion_probe" ]
            ) { ServiceResult.success(executed: true) }
          end
        end
      end
      reader_ready.pop

      writer = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          User.transaction do
            User.find(target.id).update!(account_type: "member")
            writer_paused << true
            release_writer.pop
          end
          writer_result << true
        end
      end
      writer_paused.pop

      start_reader << true
      wait_until_advisory_lock_wait(reader_pid.pop)
      assert_predicate reader, :alive?,
                       "shared reader should wait for the owner demotion to commit"

      release_writer << true
      assert writer.join(5), "owner demotion thread did not finish"
      assert reader.join(5), "high-risk reader thread did not finish"
      assert writer_result.pop
      assert_predicate reader_result.pop, :failure?
    ensure
      start_reader << true if reader&.alive?
      release_writer << true if writer&.alive?
      writer&.join(5)
      reader&.join(5)
      User.where(id: target&.id).destroy_all
    end

    private

    def start_revocation(result)
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          result << ApplyRoleMutation.call(
            actor: User.find(@owner.id),
            operation: :update,
            role: @role.id,
            attributes: {},
            permission_ids: [],
            permissions_submitted: true
          )
        end
      end
    end

    def start_shared_reader(started:, prewarmed:, backend_pid:, result:)
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          connection.cache do
            prewarmed << User.find(@member.id).permission?(@permission.key)
            ApplicationRecord.transaction do
              backend_pid << connection.select_value("SELECT pg_backend_pid()").to_i
              started << true
              PermissionMutationLock.acquire_shared!
              actor = User.uncached { User.find(@member.id) }
              result << actor.permission?(@permission.key)
            end
          end
        end
      end
    end

    def wait_until_advisory_lock_wait(backend_pid)
      Timeout.timeout(5) do
        loop do
          wait_event = ApplicationRecord.connection.select_one(
            ApplicationRecord.sanitize_sql_array(
              [
                <<~SQL.squish,
                  SELECT wait_event_type, wait_event
                  FROM pg_stat_activity
                  WHERE pid = ?
                SQL
                backend_pid
              ]
            )
          )
          break if wait_event == { "wait_event_type" => "Lock", "wait_event" => "advisory" }

          sleep 0.01
        end
      end
    end
  end
end
