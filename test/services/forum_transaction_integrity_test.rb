# frozen_string_literal: true

require "test_helper"

# Regression tests for transactional integrity fixes:
# - EditTopic must not commit a partial title/prefix change when tag/poll sync fails.
# - SyncUserFieldValues must not persist earlier fields when a later field is invalid.
class ForumEditTopicTransactionTest < ActiveSupport::TestCase
  setup do
    category = Community::Category.find_or_create_by!(slug: "txn-int-cat") { |c| c.name = "Txn" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "txn-int-sec") do |s|
      s.name = "Txn Section"
      s.position = 0
    end
    @user = create_user(username: "txnauthor")
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: @section,
      user: @user,
      title: "Original title",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @user,
      replies_count: 0
    )
    Community::Post.create!(topic: @topic, user: @user, floor_number: 1, body: "OP body", status: "published")
  end

  test "title change is rolled back when tag sync fails" do
    tag = Community::Tag.create!(name: "RestrictedTag")
    tag.update!(staff_only: true)

    result = Community::EditTopic.call(
      user: @user,
      topic: @topic,
      title: "Changed title",
      tag_names: [ "RestrictedTag" ]
    )

    assert result.failure?, "edit should fail on restricted tag"
    assert_equal "Original title", @topic.reload.title,
                 "title must roll back to original when tag sync fails inside the transaction"
  end

  test "title change succeeds when no sub-step fails" do
    result = Community::EditTopic.call(user: @user, topic: @topic, title: "Fresh title")
    assert result.success?
    assert_equal "Fresh title", @topic.reload.title
  end
end

class ForumSyncUserFieldValuesTransactionTest < ActiveSupport::TestCase
  setup do
    @user = create_user(username: "fieldsuser")
    @valid_field = Community::UserFieldDefinition.create!(
      key: "txn_bio_a",
      label: "Bio A",
      field_type: "text",
      visibility: "public",
      active: true,
      show_on_profile: true,
      editable_by_user: true,
      required: false,
      sort_order: 0
    )
    @url_field = Community::UserFieldDefinition.create!(
      key: "txn_site_b",
      label: "Site B",
      field_type: "url",
      visibility: "public",
      active: true,
      show_on_profile: true,
      editable_by_user: true,
      required: false,
      sort_order: 1
    )
  end

  test "no field is persisted when a later field is invalid" do
    result = Community::SyncUserFieldValues.call(
      user: @user,
      values: { "txn_bio_a" => "hello world", "txn_site_b" => "not-a-valid-url" },
      context: :profile
    )

    assert result.failure?, "sync should fail on invalid url field"
    assert_equal 0, Community::UserFieldValue.where(user: @user).count,
                 "earlier valid field must not be persisted when a later field is invalid"
  end

  test "all fields persist when every value is valid" do
    result = Community::SyncUserFieldValues.call(
      user: @user,
      values: { "txn_bio_a" => "hello world", "txn_site_b" => "https://example.com" },
      context: :profile
    )

    assert result.success?
    assert_equal 2, Community::UserFieldValue.where(user: @user).count
  end
end
