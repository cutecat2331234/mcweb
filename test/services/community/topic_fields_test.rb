# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

class Community::TopicFieldsTest < ActiveSupport::TestCase
  setup do
    category = Community::Category.create!(
      name: "Topic fields",
      slug: "topic-fields-#{SecureRandom.hex(4)}"
    )
    @section = Community::Section.create!(
      category: category,
      name: "Field section",
      slug: "field-section-#{SecureRandom.hex(4)}",
      position: 0
    )
    @other_section = Community::Section.create!(
      category: category,
      name: "Other section",
      slug: "other-field-section-#{SecureRandom.hex(4)}",
      position: 1
    )
    @user = create_user
    @topic = create_topic_record(user: @user, section: @section)
  end

  test "required fields roll back topic creation atomically" do
    definition = create_definition(key: "required_code", required: true)
    creator = create_user

    assert_no_difference -> { Community::Topic.count } do
      result = Community::CreateTopic.call(
        user: creator,
        section: @section,
        title: "Missing required field",
        body: "A valid opening post",
        ip_address: "127.0.0.1"
      )
      assert result.failure?
      assert result.errors.key?("custom_fields.required_code")
    end

    result = Community::CreateTopic.call(
      user: create_user,
      section: @section,
      title: "Has required field",
      body: "A valid opening post",
      custom_fields: { required_code: "ABC-123" },
      ip_address: "127.0.0.1"
    )
    assert result.success?, result.errors.inspect
    assert_equal "ABC-123", result.value.topic_field_values.find_by(definition: definition).value
  end

  test "sync validates all supported value types without partial writes" do
    text = create_definition(key: "summary")
    number = create_definition(key: "score", field_type: "number")
    url = create_definition(key: "homepage", field_type: "url")
    select = create_definition(key: "edition", field_type: "select", choices: "Java\nBedrock")
    checkbox = create_definition(key: "agreed", field_type: "checkbox")
    Community::TopicFieldValue.create!(topic: @topic, definition: text, value: "before")
    @topic.topic_field_values.load

    invalid = Community::SyncTopicFieldValues.call(
      topic: @topic,
      user: @user,
      values: {
        summary: "after",
        score: "not-a-number",
        homepage: "javascript:alert(1)",
        edition: "Other",
        agreed: "maybe"
      }
    )
    assert invalid.failure?
    assert_equal "before", @topic.topic_field_values.find_by(definition: text).reload.value
    assert_nil @topic.topic_field_values.find_by(definition: number)

    valid = Community::SyncTopicFieldValues.call(
      topic: @topic,
      user: @user,
      values: {
        summary: "after",
        score: "-12.5",
        homepage: "https://example.com/profile",
        edition: "Java",
        agreed: true
      }
    )
    assert valid.success?, valid.errors.inspect
    assert_equal(
      {
        "summary" => "after",
        "score" => "-12.5",
        "homepage" => "https://example.com/profile",
        "edition" => "Java",
        "agreed" => "1"
      },
      @topic.topic_field_values.includes(:definition).to_h { |value| [ value.definition.key, value.value ] }
    )
  end

  test "section and group applicability control forms while moves retain hidden values" do
    group = Community::UserGroup.create!(name: "Field editors", priority: 10)
    Community::GroupMembership.create!(user: @user, user_group: group)
    definition = create_definition(
      key: "private_code",
      section_ids: [ @section.id ],
      editable_group_ids: [ group.id ]
    )

    assert_equal [ "private_code" ],
      Community::SerializeTopicFields.for_form(section: @section, user: @user).pluck(:key)
    assert_empty Community::SerializeTopicFields.for_form(section: @section, user: create_user)
    assert_empty Community::SerializeTopicFields.for_form(section: @other_section, user: @user)

    Community::TopicFieldValue.create!(topic: @topic, definition: definition, value: "kept")
    assert_equal [ "private_code" ], Community::SerializeTopicFields.for_display(topic: @topic).pluck(:key)
    @topic.update!(section: @other_section)
    assert_empty Community::SerializeTopicFields.for_display(topic: @topic)
    assert_equal "kept", @topic.topic_field_values.find_by(definition: definition).value
  end

  test "drafts may omit required fields but publishing revalidates them" do
    definition = create_definition(key: "publish_code", required: true)
    author = create_user
    save_result = Community::SaveTopicDraft.call(
      user: author,
      section: @section,
      title: "Incomplete draft",
      body: "Draft body",
      custom_fields: {}
    )
    assert save_result.success?, save_result.errors.inspect

    draft = save_result.value
    publish_result = Community::PublishTopicDraft.call(user: author, topic: draft)
    assert publish_result.failure?
    assert_equal "draft", draft.reload.status

    update_result = Community::SaveTopicDraft.call(
      user: author,
      section: @section,
      topic: draft,
      title: draft.title,
      body: "Draft body",
      custom_fields: { publish_code: "ready" }
    )
    assert update_result.success?, update_result.errors.inspect
    assert_equal "ready", draft.topic_field_values.find_by(definition: definition).value

    publish_result = Community::PublishTopicDraft.call(user: author, topic: draft.reload)
    assert publish_result.success?, publish_result.errors.inspect
    assert_not_equal "draft", draft.reload.status
  end

  test "scheduling validates required fields" do
    create_definition(key: "schedule_code", required: true)

    assert_no_difference -> { Community::Topic.count } do
      result = Community::ScheduleTopic.call(
        user: @user,
        section: @section,
        title: "Scheduled without field",
        body: "Scheduled body",
        scheduled_at: 1.hour.from_now,
        ip_address: "127.0.0.1"
      )
      assert result.failure?
    end

    result = Community::ScheduleTopic.call(
      user: @user,
      section: @section,
      title: "Scheduled with field",
      body: "Scheduled body",
      scheduled_at: 1.hour.from_now,
      custom_fields: { schedule_code: "ready" },
      ip_address: "127.0.0.1"
    )
    assert result.success?, result.errors.inspect
  end

  test "copy topic copies all raw field values" do
    definition = create_definition(key: "copy_code", section_ids: [ @section.id ])
    Community::TopicFieldValue.create!(topic: @topic, definition: definition, value: "source-value")
    Community::Post.create!(
      topic: @topic,
      user: @user,
      floor_number: 1,
      body: "Opening post",
      status: "published"
    )
    moderator = create_user
    grant_permission(moderator, "forum.topics.move")

    result = Community::CopyTopic.call(
      user: moderator,
      topic: @topic,
      section: @other_section
    )
    assert result.success?, result.errors.inspect
    assert_equal "source-value", result.value.topic_field_values.find_by(definition: definition).value
    assert_empty Community::SerializeTopicFields.for_display(topic: result.value)
  end

  test "field update event is deferred until the transaction commit hook" do
    create_definition(key: "event_code")
    pending_callback = nil
    received = nil
    subscriber = Mcweb::Events.subscribe("forum.topic.fields.updated") { |payload| received = payload }
    original_after_commit = ActiveRecord.method(:after_all_transactions_commit)
    ActiveRecord.define_singleton_method(:after_all_transactions_commit) do |&callback|
      pending_callback = callback
    end

    begin
      result = Community::SyncTopicFieldValues.call(
        topic: @topic,
        user: @user,
        values: { event_code: "changed" }
      )
      assert result.success?, result.errors.inspect
      assert_nil received
    ensure
      ActiveRecord.define_singleton_method(:after_all_transactions_commit, original_after_commit)
    end

    assert pending_callback
    pending_callback.call
    assert_equal @topic, received[:topic]
    assert_equal [ "event_code" ], received[:field_keys]
  ensure
    ActiveRecord.define_singleton_method(:after_all_transactions_commit, original_after_commit) if original_after_commit
    Mcweb::Events.unsubscribe(subscriber) if subscriber
  end

  test "definition keys are immutable and plugin owners use vendor/name ids" do
    definition = create_definition(key: "stable_key", owner_plugin_id: "Vendor.Name/Plugin_Name")
    assert_equal "vendor.name/plugin_name", definition.owner_plugin_id
    assert_not definition.update(key: "changed_key")
    assert_includes definition.errors[:key],
      I18n.t("mcweb.validation_errors.cannot_be_changed_after_creation")

    definition.owner_plugin_id = "invalid owner"
    assert_not definition.valid?

    %w[1vendor/plugin vendor/plugin- vendor-/plugin vendor//plugin].each do |invalid_id|
      definition.owner_plugin_id = invalid_id
      assert_not definition.valid?, "#{invalid_id.inspect} must not be accepted as a plugin id"
    end
  end

  test "select definitions require at least one choice" do
    definition = Community::TopicFieldDefinition.new(
      key: "empty_select",
      label: "Empty select",
      field_type: "select",
      display_location: "before_message",
      choices: "\n",
      active: true,
      editable_by_user: true
    )

    assert_not definition.valid?
    assert_includes definition.errors[:choices],
      I18n.t("mcweb.validation_errors.must_contain_at_least_one_option")
  end

  private

  def create_definition(key:, **attrs)
    Community::TopicFieldDefinition.create!({
      key: key,
      label: key.humanize,
      field_type: "text",
      display_location: "before_message",
      active: true,
      editable_by_user: true
    }.merge(attrs))
  end

  def create_topic_record(user:, section:)
    Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: section,
      user: user,
      title: "Topic #{SecureRandom.hex(4)}",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: user,
      replies_count: 0
    )
  end
end

class Community::TopicFieldsAdminTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create_user
    grant_permission(@admin, "admin.access")
    grant_permission(@admin, "forum.topics.lock")
    grant_admin_module(@admin, "forum")
    sign_in_as(@admin)
    category = Community::Category.create!(name: "Admin fields", slug: "admin-fields-#{SecureRandom.hex(4)}")
    @section = Community::Section.create!(
      category: category,
      name: "Admin field section",
      slug: "admin-field-section-#{SecureRandom.hex(4)}",
      position: 0
    )
  end

  test "admin can create update and delete a topic field" do
    assert_difference -> { Community::TopicFieldDefinition.count }, 1 do
      post admin_forum_topic_fields_path, params: {
        topic_field: {
          key: "admin_code",
          label: "Admin code",
          field_type: "text",
          display_location: "topic_status",
          section_ids: [ @section.id ],
          editable_group_ids: [],
          owner_plugin_id: "vendor/plugin",
          active: true,
          editable_by_user: true
        }
      }
    end
    assert_redirected_to admin_forum_topic_fields_path

    definition = Community::TopicFieldDefinition.find_by!(key: "admin_code")
    patch admin_forum_topic_field_path(definition), params: {
      topic_field: {
        key: "attempted_change",
        label: "Updated label",
        field_type: "textarea",
        display_location: "after_message",
        section_ids: [ @section.id ],
        editable_group_ids: [],
        active: true,
        editable_by_user: true
      }
    }
    assert_redirected_to admin_forum_topic_fields_path
    assert_equal "admin_code", definition.reload.key
    assert_equal "Updated label", definition.label

    assert_difference -> { Community::TopicFieldDefinition.count }, -1 do
      delete admin_forum_topic_field_path(definition)
    end
  end

  test "invalid admin field renders actionable validation errors" do
    assert_no_difference -> { Community::TopicFieldDefinition.count } do
      post admin_forum_topic_fields_path, params: {
        topic_field: {
          key: "broken_select",
          label: "Broken select",
          field_type: "select",
          choices: "",
          display_location: "before_message",
          section_ids: [],
          editable_group_ids: [],
          active: true,
          editable_by_user: true
        }
      }
    end

    assert_response :unprocessable_entity
    props = inertia.props.deep_symbolize_keys
    assert_equal "Broken select", props.dig(:topicField, :label)
    assert_includes props.dig(:formErrors, :choices),
      I18n.t("mcweb.validation_errors.must_contain_at_least_one_option")
  end
end
