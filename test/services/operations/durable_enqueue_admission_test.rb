# frozen_string_literal: true

require "test_helper"

module Operations
  class DurableEnqueueAdmissionTest < ActiveSupport::TestCase
    test "normalizes persistence failures to one stable fail-closed error without logging details" do
      messages = []
      logger = Object.new
      logger.define_singleton_method(:error) { |message| messages << message }

      Operations::DurableEnqueue.stub(
        :record!,
        ->(**) { raise ActiveRecord::StatementInvalid, "postgres://secret@example.test" }
      ) do
        Rails.stub(:logger, logger) do
          error = assert_raises(Operations::DurableEnqueueAdmission::Unavailable) do
            Operations::DurableEnqueueAdmission.record!(
              handler: "identity.data_export_generation",
              source_id: 1,
              dedupe_key: "identity-data-export:1:1"
            )
          end

          assert_equal "background_processing_unavailable", error.message
        end
      end

      assert_equal 1, messages.length
      assert_includes messages.sole, "identity.data_export_generation"
      assert_includes messages.sole, "ActiveRecord::StatementInvalid"
      refute_includes messages.sole, "secret"
      refute_includes messages.sole, "postgres://"
    end

    test "fail-closed admission code has stable English and Chinese copy" do
      translations = [ :en, :"zh-CN" ].map do |locale|
        I18n.with_locale(locale) do
          ServiceErrorTranslator.translate(
            Operations::DurableEnqueueAdmission::ERROR_CODE
          )
        end
      end

      assert translations.all?(&:present?)
      refute_includes translations, Operations::DurableEnqueueAdmission::ERROR_CODE
      refute_equal translations.first, translations.last
    end
  end
end
