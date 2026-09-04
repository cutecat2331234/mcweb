# frozen_string_literal: true

require "test_helper"

module Identity
  class PersonalDataExportCoverageTest < ActiveSupport::TestCase
    test "core catalog registers community and commerce activity contributors" do
      keys = DataExportCatalog.entries.map(&:key)

      assert_includes keys, "community.activity"
      assert_includes keys, "commerce.activity"
    end

    test "activity contributors are deterministic for an empty account" do
      user = create_user
      context = DataExporting::Context.new(user:, generated_at: Time.current)

      community_first = DataExporting::CommunityActivityContributor.call(context:)
      community_second = DataExporting::CommunityActivityContributor.call(context:)
      commerce_first = DataExporting::CommerceActivityContributor.call(context:)
      commerce_second = DataExporting::CommerceActivityContributor.call(context:)

      assert_equal materialize_export(community_first.documents),
                   materialize_export(community_second.documents)
      assert_equal materialize_export(commerce_first.documents),
                   materialize_export(commerce_second.documents)
      assert_equal 0, community_first.record_count
      assert_equal 0, commerce_first.record_count
    end

    test "community relationships include only choices initiated by the exporting member" do
      user = create_user
      followed = create_user
      incoming_blocker = create_user
      Community::UserFollow.create!(follower: user, followed:)
      Community::UserBlock.create!(blocker: incoming_blocker, blocked: user)

      contribution = DataExporting::CommunityActivityContributor.call(
        context: DataExporting::Context.new(user:, generated_at: Time.current)
      )

      documents = materialize_export(contribution.documents)
      follows = documents.fetch("forum/relationships/follows.json")
      blocks = documents.fetch("forum/relationships/blocks.json")
      assert_equal followed.public_id, follows.sole.fetch("target_public_id")
      assert_empty blocks
      refute_includes JSON.generate(documents), incoming_blocker.username
    end

    test "commerce allowlists exclude provider payloads and internal dispute signals" do
      exported_fields = [
        *DataExporting::CommerceActivityContributor::PAYMENT_FIELDS,
        *DataExporting::CommerceActivityContributor::PAYMENT_ATTEMPT_FIELDS,
        *DataExporting::CommerceActivityContributor::REFUND_FIELDS,
        *DataExporting::CommerceActivityContributor::DISPUTE_FIELDS,
        *DataExporting::CommerceActivityContributor::DISPUTE_EVENT_FIELDS
      ]

      %w[
        metadata request_data response_data provider_metadata provider_error_code restoration_error
        risk_level legal_hold note request_id payload_digest idempotency_key assigned_to_id actor_id
      ].each { |field| refute_includes exported_fields, field }
    end

    test "commerce account export includes the complete store credit ledger without authorization secrets" do
      user = create_user
      transaction = Commerce::StoreCreditTransaction.create!(
        user: user,
        amount_cents: 250,
        balance_before_cents: 100,
        balance_after_cents: 350,
        note: "customer-visible correction"
      )

      contribution = DataExporting::CommerceAccountContributor.call(
        context: DataExporting::Context.new(user:, generated_at: Time.current)
      )
      rows = contribution.documents.fetch("commerce/store-credit-transactions.json").each_record.to_a

      assert_equal transaction.id, rows.sole.fetch("id")
      assert_equal 100, rows.sole.fetch("balance_before_cents")
      assert_equal 350, rows.sole.fetch("balance_after_cents")
      assert_equal "credit", rows.sole.fetch("source")
      %w[store_order_id request_id request_fingerprint authorization_digest actor_id].each do |field|
        refute_includes rows.sole.keys, field
      end
    end

    test "community points omit internal deduplication tokens" do
      refute_includes DataExporting::CommunityActivityContributor::POINT_TRANSACTION_FIELDS,
                      "dedupe_token"
    end

    private

    def materialize_export(value)
      case value
      when DataExporting::StreamingDocument
        value.each_record.map { |record| materialize_export(record) }
      when DataExporting::StreamingObjectDocument
        value.members.transform_values { |member| materialize_export(member) }
      when Hash
        value.transform_values { |member| materialize_export(member) }
      when Array
        value.map { |member| materialize_export(member) }
      else
        value
      end
    end
  end
end
