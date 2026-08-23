# frozen_string_literal: true

require "test_helper"
require "timeout"

module Community
  class RelationshipStateTest < ActiveSupport::TestCase
    setup do
      @actor = create_user
      @target = create_user
    end

    test "repeated block requests preserve their explicit final state" do
      first = set_block(true)
      retry_result = set_block(true)

      assert_predicate first, :success?
      assert first.value[:changed]
      assert_predicate retry_result, :success?
      assert_not retry_result.value[:changed]
      assert retry_result.value[:blocked]
      assert_equal 1, UserBlock.where(blocker: @actor, blocked: @target).count

      removed = set_block(false)
      repeated_remove = set_block(false)

      assert removed.value[:changed]
      assert_not repeated_remove.value[:changed]
      assert_not repeated_remove.value[:blocked]
      assert_not UserBlock.exists?(blocker: @actor, blocked: @target)
    end

    test "repeated ignore requests preserve their explicit final state" do
      first = set_ignore(true)
      retry_result = set_ignore(true)

      assert first.value[:changed]
      assert_not retry_result.value[:changed]
      assert retry_result.value[:ignored]
      assert_equal 1, UserIgnore.where(ignorer: @actor, ignored: @target).count

      set_ignore(false)
      repeated_remove = set_ignore(false)

      assert_not repeated_remove.value[:changed]
      assert_not repeated_remove.value[:ignored]
    end

    test "repeated follow requests notify once and preserve their explicit final state" do
      notification_scope = @target.notifications.where(notification_type: "forum.new_follower")

      assert_difference -> { notification_scope.count }, 1 do
        assert_predicate set_follow(true), :success?
        retry_result = set_follow(true)
        assert_predicate retry_result, :success?
        assert_not retry_result.value[:changed]
        assert retry_result.value[:following]
      end
      assert_equal 1, UserFollow.where(follower: @actor, followed: @target).count

      set_follow(false)
      repeated_remove = set_follow(false)

      assert_not repeated_remove.value[:changed]
      assert_not repeated_remove.value[:following]
    end

    test "follow creation rolls back when its notification cannot be recorded" do
      notification_scope = @target.notifications.where(notification_type: "forum.new_follower")
      failed_enqueue = Notification.new
      failed_enqueue.errors.add(:base, :invalid)

      Operations::DurableEnqueue.stub(:record!, ->(**) { raise ActiveRecord::RecordInvalid.new(failed_enqueue) }) do
        result = set_follow(true)

        assert_predicate result, :failure?
      end
      assert_not UserFollow.exists?(follower: @actor, followed: @target)
      assert_equal 0, notification_scope.count
    end

    test "missing desired state fails closed instead of toggling" do
      results = [
        SetUserBlock.call(blocker: @actor, blocked_username: @target.username),
        SetUserIgnore.call(ignorer: @actor, ignored_username: @target.username),
        SetUserFollow.call(follower: @actor, followed_username: @target.username)
      ]

      results.each do |result|
        assert_predicate result, :failure?
        assert_equal I18n.t("mcweb.services.errors.relationship_state_required"), result.error
      end
      assert_not UserBlock.exists?(blocker: @actor, blocked: @target)
      assert_not UserIgnore.exists?(ignorer: @actor, ignored: @target)
      assert_not UserFollow.exists?(follower: @actor, followed: @target)
    end

    test "a transient unique race is retried instead of escaping as an exception" do
      relation = UserBlock.where(blocker: @actor, blocked: @target)
      calls = 0
      original_create = relation.method(:create_or_find_by!)

      relation.stub(:create_or_find_by!, lambda {
        calls += 1
        raise ActiveRecord::RecordNotUnique if calls == 1

        original_create.call
      }) do
        result = SetUserRelationship.call(
          relation: relation,
          desired_state: true,
          participants: [ @actor, @target ]
        )

        assert_predicate result, :success?
        assert result.value[:active]
        assert_equal 2, calls
      end
    end

    test "an exhausted unique race returns a conflict instead of raising" do
      relation = UserBlock.where(blocker: @actor, blocked: @target)

      relation.stub(:create_or_find_by!, -> { raise ActiveRecord::RecordNotUnique }) do
        result = SetUserRelationship.call(
          relation: relation,
          desired_state: true,
          participants: [ @actor, @target ]
        )

        assert_predicate result, :failure?
        assert_equal "conflict", result.code
        assert_equal I18n.t("mcweb.services.errors.relationship_update_conflict"), result.error
      end
    end

    test "relationship pairs are protected by database unique indexes" do
      expected_indexes = {
        UserBlock => %w[blocker_id blocked_id],
        UserIgnore => %w[ignorer_id ignored_id],
        UserFollow => %w[follower_id followed_id]
      }

      expected_indexes.each do |model, columns|
        index = model.connection.indexes(model.table_name).find { |candidate| candidate.columns == columns }

        assert index, "missing composite index for #{model.name}"
        assert index.unique, "#{model.name} relationship index must be unique"
      end
    end

    private

    def set_block(desired_state)
      SetUserBlock.call(blocker: @actor, blocked_username: @target.username, desired_state: desired_state)
    end

    def set_ignore(desired_state)
      SetUserIgnore.call(ignorer: @actor, ignored_username: @target.username, desired_state: desired_state)
    end

    def set_follow(desired_state)
      SetUserFollow.call(follower: @actor, followed_username: @target.username, desired_state: desired_state)
    end
  end

  class RelationshipStateConcurrencyTest < ActiveSupport::TestCase
    self.use_transactional_tests = false
    parallelize(workers: 1)

    setup do
      suffix = SecureRandom.hex(6)
      @actor = create_user(username: "relationship_race_actor_#{suffix}")
      @target = create_user(username: "relationship_race_target_#{suffix}")
    end

    teardown do
      user_ids = [ @actor&.id, @target&.id ].compact
      UserBlock.where(blocker_id: user_ids).or(UserBlock.where(blocked_id: user_ids)).delete_all
      UserIgnore.where(ignorer_id: user_ids).or(UserIgnore.where(ignored_id: user_ids)).delete_all
      UserFollow.where(follower_id: user_ids).or(UserFollow.where(followed_id: user_ids)).delete_all
      Notification.where(user_id: user_ids).delete_all
      Session.where(user_id: user_ids).delete_all
      UserRole.where(user_id: user_ids).delete_all
      User.where(id: user_ids).delete_all
    end

    test "concurrent retries establish one relationship without errors or duplicate notifications" do
      notification_calls = 0
      notification_lock = Mutex.new
      notify = ->(**) { notification_lock.synchronize { notification_calls += 1 } }

      NotificationPreference.stub(:enabled?, true) do
        Community::InAppNotification.stub(:notify, notify) do
          configurations.each do |configuration|
            results = race(3) { configuration[:call].call(true) }

            results.each { |result| assert_instance_of ServiceResult, result }
            results.each { |result| assert_predicate result, :success? }
            assert_equal 1, results.count { |result| result.value[:changed] }
            assert results.all? { |result| result.value[configuration[:state_key]] }
            assert_equal 1, configuration[:relation].call.count
          end
        end
      end

      assert_equal 1, notification_calls
    end

    test "concurrent repeated removals converge on an absent relationship" do
      NotificationPreference.stub(:enabled?, false) do
        configurations.each do |configuration|
          assert_predicate configuration[:call].call(true), :success?
          results = race(3) { configuration[:call].call(false) }

          results.each { |result| assert_instance_of ServiceResult, result }
          results.each { |result| assert_predicate result, :success? }
          assert_equal 1, results.count { |result| result.value[:changed] }
          assert results.all? { |result| result.value[configuration[:state_key]] == false }
          assert_equal 0, configuration[:relation].call.count
        end
      end
    end

    test "participant locks normalize order and serialize relationship writes" do
      lock_acquired = Queue.new
      release_lock = Queue.new
      writer_started = Queue.new
      writer_outcome = Queue.new

      holder = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          Identity::UserMutationLock.with_users(users: [ @target, @actor, @target ]) do |locked_users|
            lock_acquired << locked_users.keys
            release_lock.pop
          end
        end
      rescue StandardError => error
        lock_acquired << error
      end

      locked_ids = Timeout.timeout(5) { lock_acquired.pop }
      raise locked_ids if locked_ids.is_a?(Exception)
      assert_equal [ @actor.id, @target.id ].sort, locked_ids

      writer = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          writer_started << true
          writer_outcome << SetUserBlock.call(
            blocker: User.find(@actor.id),
            blocked_username: @target.username,
            desired_state: true
          )
        end
      rescue StandardError => error
        writer_outcome << error
      end

      Timeout.timeout(5) { writer_started.pop }
      assert_raises(Timeout::Error) do
        Timeout.timeout(0.2) { writer_outcome.pop }
      end

      release_lock << true
      result = Timeout.timeout(5) { writer_outcome.pop }
      raise result if result.is_a?(Exception)

      assert_predicate result, :success?
      assert result.value[:blocked]
      assert UserBlock.exists?(blocker: @actor, blocked: @target)
    ensure
      release_lock&.push(true)
      holder&.join(1)
      writer&.join(1)
      holder&.kill if holder&.alive?
      writer&.kill if writer&.alive?
    end

    private

    def configurations
      [
        {
          call: ->(state) { SetUserBlock.call(blocker: User.find(@actor.id), blocked_username: @target.username, desired_state: state) },
          state_key: :blocked,
          relation: -> { UserBlock.where(blocker_id: @actor.id, blocked_id: @target.id) }
        },
        {
          call: ->(state) { SetUserIgnore.call(ignorer: User.find(@actor.id), ignored_username: @target.username, desired_state: state) },
          state_key: :ignored,
          relation: -> { UserIgnore.where(ignorer_id: @actor.id, ignored_id: @target.id) }
        },
        {
          call: ->(state) { SetUserFollow.call(follower: User.find(@actor.id), followed_username: @target.username, desired_state: state) },
          state_key: :following,
          relation: -> { UserFollow.where(follower_id: @actor.id, followed_id: @target.id) }
        }
      ]
    end

    def race(count, &operation)
      ready = Queue.new
      gate = Queue.new
      results = Queue.new
      threads = []
      count.times do
        threads << Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            ready << true
            gate.pop
            results << operation.call
          rescue StandardError => error
            results << error
          end
        end
      end

      Timeout.timeout(10) do
        count.times { ready.pop }
        count.times { gate << true }
        responses = count.times.map { results.pop }
        threads.each(&:join)
        responses
      end
    ensure
      count.times { gate&.push(true) }
      threads&.each { |thread| thread.join(1) }
      threads&.each { |thread| thread.kill if thread.alive? }
      threads&.each { |thread| thread.join(1) }
    end
  end
end
