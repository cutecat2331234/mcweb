# frozen_string_literal: true

require "test_helper"

class PerformanceBudgetTest < ActionDispatch::IntegrationTest
  test "warm anonymous website home stays inside the SQL budget" do
    get root_path
    assert_response :success

    statements = capture_business_sql do
      get root_path
    end

    assert_response :success
    assert_operator statements.length, :<=, 15,
      "warm home exceeded 15 SQL statements:\n#{statements.join("\n")}"
  end

  private

  def capture_business_sql
    statements = []
    subscriber = lambda do |_name, _started, _finished, _id, payload|
      next if payload[:cached]
      next if %w[SCHEMA TRANSACTION].include?(payload[:name].to_s.upcase)

      sql = payload[:sql].to_s.squish
      next if sql.match?(/\A(?:BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)/i)

      statements << sql
    end
    ActiveSupport::Notifications.subscribed(
      subscriber,
      "sql.active_record"
    ) { yield }
    statements
  end
end
