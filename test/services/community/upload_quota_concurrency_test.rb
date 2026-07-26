# frozen_string_literal: true

require "test_helper"

module Community
  class UploadQuotaConcurrencyTest < ActiveSupport::TestCase
    self.use_transactional_tests = false

    setup do
      @user = create_user
      SiteSetting.set("forum.upload_quota.account.count", "1")
    end

    teardown do
      Community::Upload.where(user_id: @user&.id).delete_all
      User.where(id: @user&.id).delete_all
      SiteSetting.unset("forum.upload_quota.account.count")
    end

    test "serializes concurrent reservations so only one consumes the last slot" do
      ready = Queue.new
      gate = Queue.new
      results = Queue.new
      threads = 2.times.map do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            ready << true
            gate.pop
            results << Community::UploadQuota.call(
              user: User.find(@user.id),
              kind: :inline_image,
              byte_size: 1
            )
          end
        end
      end
      2.times { ready.pop }
      2.times { gate << true }
      threads.each(&:join)
      outcomes = 2.times.map { results.pop }

      assert_equal 1, outcomes.count(&:success?)
      assert_equal 1, outcomes.count(&:failure?)
      assert_equal 1, Community::Upload.where(user_id: @user.id).count
    end
  end
end
