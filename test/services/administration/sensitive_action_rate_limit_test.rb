# frozen_string_literal: true

require "test_helper"

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
    ready = Queue.new
    gate = Queue.new
    results = Queue.new
    threads = 10.times.map do |index|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          gate.pop
          results << Administration::SensitiveActionRateLimit.call(
            scope: @scope,
            user: User.find(@user.id),
            ip_address: @ip,
            context: "restore-plan-#{index}",
            action: :reserve
          )
        end
      end
    end

    10.times { ready.pop }
    10.times { gate << true }
    responses = 10.times.map { results.pop }
    threads.each(&:join)

    assert_equal 5, responses.count(&:success?)
    assert_equal 5, responses.count { |result| result.code == :rate_limited }
    assert_equal 5, Administration::SensitiveActionRateLimitReservation
      .where(user_id: @user.id, scope: @scope, status: "pending").count
  end
end
