# frozen_string_literal: true

require "test_helper"
require "timeout"

module Administration
  class AbuseRateLimitTest < ActiveSupport::TestCase
    test "rate limiter returns an exact retry interval without exposing its key" do
      key = "login:private-account:203.0.113.7"

      travel_to Time.zone.parse("2026-07-26 12:00:00") do
        assert Administration::RateLimiter.call(key: key, limit: 1, window: 1.minute).success?

        travel 7.seconds
        result = Administration::RateLimiter.call(key: key, limit: 1, window: 1.minute)

        assert result.failure?
        assert result.rate_limited?
        assert_equal "rate_limited", result.code
        assert_equal 53, result.retry_after
        assert_nil result.value
        refute_includes result.error.to_s, key
        refute_includes result.errors.inspect, key

        counter = RateLimitCounter.find_by!(key: key)
        assert_equal 1, counter.blocked_count
        assert_equal Time.current, counter.last_blocked_at
      end
    end

    test "configured account limit allows then rejects the same account across IPs" do
      configure(:login, account_limit: 1, ip_limit: 100)

      assert abuse_limit(:login, account: "first@example.com", ip: "203.0.113.1").success?
      assert abuse_limit(:login, account: "second@example.com", ip: "203.0.113.1").success?

      blocked = abuse_limit(:login, account: "first@example.com", ip: "203.0.113.2")
      assert blocked.rate_limited?
      assert_operator blocked.retry_after, :>, 0
    end

    test "configured IP limit isolates different IPs and aggregates accounts on one IP" do
      configure(:registration, account_limit: 100, ip_limit: 1)

      assert abuse_limit(:registration, account: "first@example.com", ip: "198.51.100.1").success?
      assert abuse_limit(:registration, account: "second@example.com", ip: "198.51.100.2").success?

      blocked = abuse_limit(:registration, account: "third@example.com", ip: "198.51.100.1")
      assert blocked.rate_limited?
      assert_operator blocked.retry_after, :>, 0
    end

    test "zero disables one dimension without disabling the other" do
      configure(:preview, account_limit: 0, ip_limit: 1)

      assert abuse_limit(:preview, account: "1", ip: "192.0.2.10").success?
      assert abuse_limit(:preview, account: "1", ip: "192.0.2.11").success?
      assert abuse_limit(:preview, account: "2", ip: "192.0.2.10").rate_limited?
    end

    test "write-heavy forum policies independently protect account and IP dimensions" do
      %i[upload topic reply reaction].each do |action|
        configure(action, account_limit: 1, ip_limit: 100)

        assert abuse_limit(action, account: "member-#{action}", ip: "192.0.2.20").success?
        blocked = abuse_limit(action, account: "member-#{action}", ip: "192.0.2.21")

        assert blocked.rate_limited?, "#{action} should enforce its account dimension"
        assert_operator blocked.retry_after, :>, 0
      end
    end

    test "expired windows reset request and blocked observability counters" do
      key = "abuse:test:account:private"

      travel_to Time.zone.parse("2026-07-26 12:00:00") do
        assert Administration::RateLimiter.call(key: key, limit: 1, window: 1.minute).success?
        assert Administration::RateLimiter.call(key: key, limit: 1, window: 1.minute).rate_limited?

        travel 61.seconds
        assert Administration::RateLimiter.call(key: key, limit: 1, window: 1.minute).success?

        counter = RateLimitCounter.find_by!(key: key)
        assert_equal 1, counter.count
        assert_equal 0, counter.blocked_count
        assert_nil counter.last_blocked_at
      end
    end

    test "policy catalog is the single source for runtime effective values" do
      SiteSetting.set("security.rate_limits.search.account_limit", "17")
      SiteSetting.set("security.rate_limits.search.account_window_seconds", "91")

      row = Administration::AbuseRateLimit.policy_rows.find do |policy|
        policy[:action] == :search && policy[:dimension] == :account
      end

      assert_equal 17, row[:limit]
      assert_equal 91, row[:window_seconds]

      17.times do
        assert abuse_limit(:search, account: "catalog-user", ip: nil).success?
      end
      assert abuse_limit(:search, account: "catalog-user", ip: nil).rate_limited?
    end

    private

    def configure(action, account_limit:, ip_limit:)
      SiteSetting.set("security.rate_limits.#{action}.account_limit", account_limit.to_s)
      SiteSetting.set("security.rate_limits.#{action}.ip_limit", ip_limit.to_s)
    end

    def abuse_limit(action, account:, ip:)
      Administration::AbuseRateLimit.call(action: action, account: account, ip_address: ip)
    end
  end
end

class Administration::RateLimiterConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @key_prefix = "rate-limiter-race-#{SecureRandom.hex(6)}"
  end

  teardown do
    RateLimitCounter.where("key LIKE ?", "#{@key_prefix}%").delete_all
  end

  test "concurrent first hits converge on one fully counted key" do
    key = "#{@key_prefix}:concurrent"
    ready = Queue.new
    release = Queue.new
    outcomes = Queue.new
    mutex = Mutex.new
    first_reads = 0
    relation = RateLimitCounter.lock
    finder = lambda do |*args, **kwargs|
      attributes = kwargs.presence || args.first
      counter = RateLimitCounter.find_or_initialize_by(attributes)
      wait = mutex.synchronize do
        first_reads += 1
        first_reads <= 2 && counter.new_record?
      end
      if wait
        ready << true
        release.pop
      end
      counter
    end

    threads = relation.stub(:find_or_initialize_by, finder) do
      RateLimitCounter.stub(:lock, relation) do
        2.times.map do
          Thread.new do
            ActiveRecord::Base.connection_pool.with_connection do
              outcomes << Administration::RateLimiter.call(key: key, limit: 5, window: 1.minute)
            end
          rescue StandardError => error
            outcomes << error
          end
        end.tap do |started|
          Timeout.timeout(5) { 2.times { ready.pop } }
          2.times { release << true }
          started.each { |thread| Timeout.timeout(10) { thread.join } }
        end
      end
    end

    results = 2.times.map { Timeout.timeout(5) { outcomes.pop } }
    error = results.find { |result| result.is_a?(Exception) }
    raise error if error

    assert_equal 2, results.count(&:success?)
    assert_equal 1, RateLimitCounter.where(key: key).count
    assert_equal 2, RateLimitCounter.find_by!(key: key).count
  ensure
    2.times { release << true } if release
    threads&.each { |thread| thread.kill if thread.alive? }
  end

  test "a database uniqueness race rolls back its savepoint without poisoning an outer transaction" do
    key = "#{@key_prefix}:outer"
    marker_key = "#{@key_prefix}:marker"
    RateLimitCounter.create!(key: key, count: 0, window_start: Time.current)
    conflicting = RateLimitCounter.new(key: key)
    conflicting.define_singleton_method(:save!) do
      now = Time.current
      RateLimitCounter.insert_all!([ {
        key: key,
        count: count,
        blocked_count: blocked_count,
        window_start: window_start,
        expires_at: expires_at,
        created_at: now,
        updated_at: now
      } ])
    end
    relation = RateLimitCounter.lock
    original_find = relation.method(:find_or_initialize_by)
    calls = 0
    finder = lambda do |*args, **kwargs|
      calls += 1
      attributes = kwargs.presence || args.first
      calls == 1 ? conflicting : original_find.call(attributes)
    end

    relation.stub(:find_or_initialize_by, finder) do
      RateLimitCounter.stub(:lock, relation) do
        RateLimitCounter.transaction do
          result = Administration::RateLimiter.call(key: key, limit: 5, window: 1.minute)
          assert_predicate result, :success?
          RateLimitCounter.create!(key: marker_key, count: 0, window_start: Time.current)
        end
      end
    end

    assert_equal 1, RateLimitCounter.find_by!(key: key).count
    assert RateLimitCounter.exists?(key: marker_key)
  end

  test "a non-uniqueness validation failure is not retried or swallowed" do
    key = "#{@key_prefix}:invalid"
    invalid = RateLimitCounter.new(key: key, count: 0, window_start: Time.current)
    invalid.errors.add(:count, :greater_than_or_equal_to, count: 0)
    validation_error = ActiveRecord::RecordInvalid.new(invalid)
    invalid.define_singleton_method(:save!) { raise validation_error }
    relation = RateLimitCounter.lock
    calls = 0
    finder = lambda do |*_args, **_kwargs|
      calls += 1
      invalid
    end

    raised = relation.stub(:find_or_initialize_by, finder) do
      RateLimitCounter.stub(:lock, relation) do
        assert_raises(ActiveRecord::RecordInvalid) do
          Administration::RateLimiter.call(key: key, limit: 5, window: 1.minute)
        end
      end
    end

    assert_same validation_error, raised
    assert_equal 1, calls
  end
end
