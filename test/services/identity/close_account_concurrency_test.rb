# frozen_string_literal: true

require "test_helper"

module Identity
  class CloseAccountConcurrencyTest < ActiveSupport::TestCase
    self.use_transactional_tests = false

    setup do
      @previous_owner_ids = User.where(
        account_type: :owner,
        status: :active
      ).pluck(:id)
      User.where(id: @previous_owner_ids).update_all(account_type: :admin)
      @owners = 2.times.map { create_user(account_type: :owner) }
    end

    teardown do
      owner_ids = Array(@owners).map(&:id)
      AuditLog.where(actor_id: owner_ids).or(
        AuditLog.where(resource_type: "User", resource_id: owner_ids)
      ).delete_all
      Session.where(user_id: owner_ids).delete_all
      User.where(id: owner_ids).delete_all
      User.where(id: @previous_owner_ids).update_all(account_type: :owner)
    end

    test "concurrent owner closures preserve one active owner" do
      ready = Queue.new
      gate = Queue.new
      results = Queue.new
      threads = @owners.map do |owner|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            ready << true
            gate.pop
            results << CloseAccount.call(
              user: User.find(owner.id),
              password: "password123",
              confirmation: "DELETE"
            )
          end
        end
      end

      2.times { ready.pop }
      2.times { gate << true }
      responses = 2.times.map { results.pop }
      threads.each(&:join)

      assert_equal 1, responses.count(&:success?)
      last_owner_failures = responses.count do |result|
        result.failure? && result.code == "last_owner_account_cannot_close"
      end
      assert_equal 1, last_owner_failures
      assert_equal 1, User.where(
        id: @owners.map(&:id),
        account_type: :owner,
        status: :active
      ).count
    end
  end
end
