# frozen_string_literal: true

require "test_helper"

module Operations
  class ExclusiveExecutionTest < ActiveSupport::TestCase
    self.use_transactional_tests = false

    test "returns the block result when the lock is acquired" do
      result = ExclusiveExecution.try_with(name: "maintenance.example") { :completed }

      assert_predicate result, :acquired?
      refute_predicate result, :contended?
      assert_equal :completed, result.value
    end

    test "does not run a second block while another connection holds the same lock" do
      acquired = Queue.new
      release = Queue.new
      first_result = Queue.new

      holder = Thread.new do
        first_result << ExclusiveExecution.try_with(name: "maintenance.shared") do
          acquired << true
          release.pop
          :first
        end
      end

      acquired.pop
      second_block_ran = false
      second = ExclusiveExecution.try_with(name: "maintenance.shared") do
        second_block_ran = true
      end

      assert_predicate second, :contended?
      refute second_block_ran

      release << true
      holder.join
      assert_predicate first_result.pop, :acquired?
    ensure
      release << true if holder&.alive?
      holder&.join
    end

    test "releases the lock when the block raises" do
      assert_raises(RuntimeError) do
        ExclusiveExecution.try_with(name: "maintenance.failure") { raise "failed" }
      end

      result = ExclusiveExecution.try_with(name: "maintenance.failure") { :recovered }

      assert_predicate result, :acquired?
      assert_equal :recovered, result.value
    end

    test "different names do not contend" do
      outer = ExclusiveExecution.try_with(name: "maintenance.first") do
        ExclusiveExecution.try_with(name: "maintenance.second") { :second }
      end

      assert_predicate outer, :acquired?
      assert_predicate outer.value, :acquired?
      assert_equal :second, outer.value.value
    end

    test "rejects dynamic or malformed lock names" do
      invalid_names = [ nil, "", "UPPERCASE", "contains spaces", "x" * 129 ]

      invalid_names.each do |name|
        error = assert_raises(ArgumentError) do
          ExclusiveExecution.try_with(name:) { flunk "invalid lock executed" }
        end
        assert_equal "exclusive execution name is invalid", error.message
      end
    end
  end
end
