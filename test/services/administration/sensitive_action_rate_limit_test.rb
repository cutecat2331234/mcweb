# frozen_string_literal: true

require "test_helper"
require "timeout"

class Administration::SensitiveActionRateLimitTest < ActiveSupport::TestCase
  setup do
    @first_user = create_user
    @second_user = create_user
    @scope = "destructive_action"
    @ip = "203.0.113.30"
  end

  test "success settles only its reservation and preserves another user's shared IP failure" do
    failed = reserve(user: @first_user, context: "plan-one")
    assert_predicate failed, :success?
    assert_predicate settle(:failure, failed, user: @first_user), :success?

    succeeded = reserve(user: @second_user, context: "plan-two")
    assert_predicate succeeded, :success?
    assert_predicate settle(:success, succeeded, user: @second_user), :success?

    ip_key = Administration::SensitiveActionRateLimitReservation.find_by!(
      public_id: failed.value.fetch(:reservation_id)
    ).ip_counter_key
    assert_equal 1, RateLimitCounter.find_by!(key: ip_key).count
    assert_equal "failed", reservation(failed).status
    assert_equal "succeeded", reservation(succeeded).status
  end

  test "abandoned reservations stop counting after their TTL" do
    5.times do |index|
      assert_predicate Administration::SensitiveActionRateLimit.call(
        scope: @scope,
        user: @first_user,
        ip_address: @ip,
        context: "crashed-plan-#{index}",
        action: :reserve,
        reservation_ttl: 30.seconds
      ), :success?
    end
    assert_predicate reserve(user: @first_user, context: "blocked-plan"), :failure?

    travel 31.seconds do
      assert_predicate reserve(user: @first_user, context: "replacement-plan"), :success?
    end
  end

  private

  def reserve(user:, context:)
    Administration::SensitiveActionRateLimit.call(
      scope: @scope,
      user: user,
      ip_address: @ip,
      context: context,
      action: :reserve
    )
  end

  def settle(action, result, user:)
    Administration::SensitiveActionRateLimit.call(
      scope: @scope,
      user: user,
      action: action,
      reservation_id: result.value.fetch(:reservation_id)
    )
  end

  def reservation(result)
    Administration::SensitiveActionRateLimitReservation.find_by!(
      public_id: result.value.fetch(:reservation_id)
    )
  end
end

class Administration::SensitiveActionRateLimitConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @user = create_user
    @scope = "concurrent_world_restore_authorize_#{SecureRandom.hex(5)}"
    @ip = "203.0.113.31"
  end

  teardown do
    reservations = Administration::SensitiveActionRateLimitReservation.where(user_id: @user.id)
    keys = reservations.pluck(:user_counter_key, :ip_counter_key).flatten.uniq
    reservations.delete_all
    RateLimitCounter.where(key: keys).delete_all
    User.where(id: @user.id).destroy_all
  end

  test "concurrent attempts for different plans cannot exceed atomic user and IP capacity" do
    prewarmed = Administration::SensitiveActionRateLimit.call(
      scope: @scope,
      user: @user,
      ip_address: @ip,
      context: "prewarm-counters",
      action: :reserve,
      limit: 1
    )
    assert_predicate prewarmed, :success?
    assert_predicate Administration::SensitiveActionRateLimit.call(
      scope: @scope,
      user: @user,
      action: :success,
      reservation_id: prewarmed.value.fetch(:reservation_id)
    ), :success?

    holder_ready = Queue.new
    contender_ready = Queue.new
    release_holder = Queue.new
    outcomes = Queue.new
    holder = Class.new(Administration::SensitiveActionRateLimit) do
      define_method(:locked_counters) do |keys, window:, now:|
        counters = super(keys, window:, now:)
        holder_ready << ActiveRecord::Base.connection.select_value("SELECT pg_backend_pid()").to_i
        release_holder.pop
        counters
      end
      private :locked_counters
    end
    contender = Class.new(Administration::SensitiveActionRateLimit) do
      define_method(:locked_counters) do |keys, window:, now:|
        contender_ready << ActiveRecord::Base.connection.select_value("SELECT pg_backend_pid()").to_i
        super(keys, window:, now:)
      end
      private :locked_counters
    end
    threads = []
    threads << rate_limit_thread(:holder, holder, outcomes, context: "restore-plan-holder")
    holder_pid = Timeout.timeout(10) { holder_ready.pop }
    threads << rate_limit_thread(:contender, contender, outcomes, context: "restore-plan-contender")
    contender_pid = Timeout.timeout(10) { contender_ready.pop }

    wait_until_blocked_by(waiting_pid: contender_pid, blocking_pid: holder_pid)
    release_holder << true
    Timeout.timeout(10) { threads.each(&:join) }

    assert threads.none?(&:alive?), "all competing workers must finish"
    results = 2.times.map { outcomes.pop(true) }.to_h
    errors = results.select { |_role, result| result.is_a?(Exception) }
    assert_empty errors
    assert_predicate results.fetch(:holder), :success?
    assert_predicate results.fetch(:contender), :rate_limited?
    assert_operator results.fetch(:contender).retry_after, :>=, 1
    assert_equal({ "pending" => 1, "succeeded" => 1 },
      Administration::SensitiveActionRateLimitReservation
        .where(user_id: @user.id, scope: @scope)
        .group(:status)
        .count)
    counter_keys = Administration::SensitiveActionRateLimitReservation
      .find_by!(public_id: prewarmed.value.fetch(:reservation_id))
      .then { |reservation| [ reservation.user_counter_key, reservation.ip_counter_key ] }
    assert_equal [ [ 0, 1 ], [ 0, 1 ] ],
      RateLimitCounter.where(key: counter_keys).order(:key).pluck(:count, :blocked_count)
  ensure
    release_holder << true if release_holder
    threads&.each { |thread| thread.kill if thread.alive? }
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    threads&.each do |thread|
      remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
      thread.join([ remaining, 0 ].max)
    end
  end

  private

  def rate_limit_thread(role, service_class, outcomes, context:)
    Thread.new do
      result = ActiveRecord::Base.connection_pool.with_connection(prevent_permanent_checkout: true) do
        service_class.call(
          scope: @scope,
          user: User.find(@user.id),
          ip_address: @ip,
          context: context,
          action: :reserve,
          limit: 1
        )
      end
      outcomes << [ role, result ]
    rescue StandardError => error
      outcomes << [ role, error ]
    end
  end

  def wait_until_blocked_by(waiting_pid:, blocking_pid:)
    waiting_lock_sql = ApplicationRecord.sanitize_sql_array(
      [
        <<~SQL.squish,
          SELECT 1
          FROM pg_locks
          WHERE pid = ?
            AND granted = FALSE
            AND ? = ANY(pg_blocking_pids(?))
          LIMIT 1
        SQL
        waiting_pid,
        blocking_pid,
        waiting_pid
      ]
    )

    Timeout.timeout(10) do
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
