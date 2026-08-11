# frozen_string_literal: true

require "test_helper"

class OperationsDurableEnqueueJobsContractTest < ActiveSupport::TestCase
  test "manual task runs expose only safe durable enqueue result counts" do
    controller = Rails.root.join(
      "app/controllers/admin/system/jobs_controller.rb"
    ).read
    safe_serializer = controller[/def safe_manual_task_result.*?^      end$/m]

    assert_includes controller, "result: safe_manual_task_result(run)"
    assert_includes safe_serializer, "partial:"
    assert_includes safe_serializer, "processed_count:"
    assert_includes safe_serializer, "failed_count:"
    assert_includes safe_serializer, "error_codes_count:"
    refute_match(/arguments|source_id|source_kind|dedupe/i, safe_serializer)
  end

  test "jobs page renders the safe partial result summary with both locales" do
    page = Rails.root.join(
      "app/javascript/pages/Admin/System/Jobs/Index.vue"
    ).read
    english = Rails.root.join("app/javascript/locales/en.ts").read
    chinese = Rails.root.join("app/javascript/locales/zh-CN.ts").read

    %w[partial processed_count failed_count error_codes_count].each do |field|
      assert_includes page, "record.result.#{field}"
    end
    %w[result partial processedCount failedCount errorCodesCount].each do |key|
      assert_match(/#{Regexp.escape(key)}:/, english)
      assert_match(/#{Regexp.escape(key)}:/, chinese)
    end
  end
end
