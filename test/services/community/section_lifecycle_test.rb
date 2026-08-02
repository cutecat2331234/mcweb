# frozen_string_literal: true

require "test_helper"

module Community
  class SectionLifecycleTest < ActiveSupport::TestCase
    setup do
      suffix = SecureRandom.hex(5)
      @actor = create_user(username: "life_admin_#{suffix}")
      grant_permission(@actor, "forum.sections.lifecycle")
      grant_permission(@actor, "forum.sections.delete")
      @author = create_user(username: "life_author_#{suffix}")
      @category = Community::Category.create!(
        name: "Lifecycle #{suffix}",
        slug: "lifecycle-#{suffix}"
      )
      @section = Community::Section.create!(
        category: @category,
        name: "Lifecycle section",
        slug: "lifecycle-section-#{suffix}",
        position: 0
      )
    end

    test "archive hides a section and its active descendants from all public access" do
      child = Community::Section.create!(
        category: @category,
        parent: @section,
        name: "Lifecycle child",
        slug: "lifecycle-child-#{SecureRandom.hex(4)}",
        position: 1
      )

      result = run_operation(@section, "archive", reason: "Retiring this branch")

      assert_predicate result, :success?
      assert_not Community::SectionAccess.view?(section: @section.reload, user: nil)
      assert_not Community::SectionAccess.view?(section: child.reload, user: @author)
      assert_not_includes Community::SectionAccess.visible_ids(user: @author), child.id

      create_result = Community::CreateTopic.call(
        user: @author,
        section: child,
        title: "Should not be created",
        body: "The archived parent must block this topic.",
        ip_address: "127.0.0.1"
      )
      assert_predicate create_result, :failure?
    end

    test "restore makes the section and descendants visible again" do
      child = Community::Section.create!(
        category: @category,
        parent: @section,
        name: "Restored child",
        slug: "restored-child-#{SecureRandom.hex(4)}",
        position: 1
      )
      run_operation(@section, "archive", reason: "Temporary retirement")

      result = run_operation(@section.reload, "restore", reason: "Community reopened")

      assert_predicate result, :success?
      assert_nil @section.reload.archived_at
      assert Community::SectionAccess.view?(section: @section, user: nil)
      assert Community::SectionAccess.view?(section: child.reload, user: nil)
      assert AuditLog.exists?(action: "admin.forum_section_restored", resource_id: @section.id)
    end

    test "archived sections reject subscription mute and read-state services" do
      run_operation(@section, "archive", reason: "Hide all section interactions")

      results = [
        Community::ToggleSectionSubscription.call(user: @author, section: @section.reload),
        Community::SetSubscriptionLevel.call(user: @author, subscribable: @section.reload, level: "watching"),
        Community::ToggleSectionMute.call(user: @author, section: @section.reload),
        Community::MarkSectionRead.call(user: @author, section: @section.reload)
      ]

      assert results.all?(&:failure?)
      assert_not Community::Subscription.exists?(user: @author, subscribable: @section)
      assert_not Community::SectionMute.exists?(user: @author, section: @section)
    end

    test "impact preview includes the complete subtree and its retained content" do
      child = Community::Section.create!(
        category: @category,
        parent: @section,
        name: "Impact child",
        slug: "impact-child-#{SecureRandom.hex(4)}",
        position: 1
      )
      topic = create_topic(section: child)
      Community::Post.create!(
        topic: topic,
        user: @author,
        floor_number: 1,
        body: "Retained post",
        status: "published"
      )
      Community::SectionModerator.create!(section: child, user: @actor)

      impact = Community::SectionLifecycleImpact.call(section: @section)

      assert_equal 2, impact.fetch(:sections)
      assert_equal 1, impact.fetch(:descendants)
      assert_equal 1, impact.fetch(:topics)
      assert_equal 1, impact.fetch(:posts)
      assert_equal 1, impact.fetch(:moderators)
    end

    test "permanent deletion requires archive exact confirmation and an empty section" do
      active_delete = run_operation(@section, "destroy", reason: "Unused section")
      assert_predicate active_delete, :failure?
      assert Community::Section.exists?(@section.id)

      run_operation(@section, "archive", reason: "Unused section")
      topic = create_topic(section: @section)

      blocked_delete = run_operation(@section.reload, "destroy", reason: "Unused section")

      assert_predicate blocked_delete, :failure?
      assert Community::Section.exists?(@section.id)
      assert Community::Topic.exists?(topic.id)
    end

    test "model restrictions never cascade-delete topics or child sections" do
      topic = create_topic(section: @section)

      assert_not @section.destroy
      assert Community::Section.exists?(@section.id)
      assert Community::Topic.exists?(topic.id)
    end

    test "section hierarchy rejects self descendant and cross-category parents" do
      child = Community::Section.create!(
        category: @category,
        parent: @section,
        name: "Hierarchy child",
        slug: "hierarchy-child-#{SecureRandom.hex(4)}",
        position: 1
      )

      @section.parent = @section
      assert_not @section.valid?
      assert_includes @section.errors.details.fetch(:parent), error: :invalid

      @section.reload.parent = child
      assert_not @section.valid?
      assert_includes @section.errors.details.fetch(:parent), error: :invalid

      other_category = Community::Category.create!(
        name: "Other hierarchy category",
        slug: "other-hierarchy-#{SecureRandom.hex(4)}"
      )
      cross_category = Community::Section.new(
        category: other_category,
        parent: @section.reload,
        name: "Cross category child",
        slug: "cross-category-#{SecureRandom.hex(4)}",
        position: 2
      )
      assert_not cross_category.valid?
      assert_includes cross_category.errors.details.fetch(:parent), error: :invalid

      @section.forum_category_id = other_category.id
      assert_not @section.valid?
      assert_includes @section.errors.details.fetch(:category), error: :invalid
    end

    test "empty archived section deletion keeps an immutable audit record" do
      section_id = @section.id
      run_operation(@section, "archive", reason: "Duplicate empty section")

      result = run_operation(@section.reload, "destroy", reason: "Duplicate empty section")

      assert_predicate result, :success?
      assert_not Community::Section.exists?(section_id)
      audit = AuditLog.find_by!(action: "admin.forum_section_deleted", resource_id: section_id)
      assert_equal @section.slug, audit.metadata.fetch("section_slug")
      assert_equal "Duplicate empty section", audit.reason
      assert_equal true, audit.after_state.fetch("deleted")
    end

    test "audit failure rolls back lifecycle changes and returns an explicit failure" do
      failure_result = ServiceResult.failure(error: "audit unavailable")

      result = Administration::AuditLogger.stub(:call, failure_result) do
        run_operation(@section, "archive", reason: "Must remain atomic")
      end

      assert_predicate result, :failure?
      assert_equal I18n.t("mcweb.services.community.section_lifecycle.audit_failed"), result.error
      assert_nil @section.reload.archived_at
    end

    test "wrong typed confirmation changes nothing" do
      result = Community::ManageSectionLifecycle.call(
        section: @section,
        actor: @actor,
        operation: "archive",
        reason: "No-op",
        confirmation: "ARCHIVE another-section"
      )

      assert_predicate result, :failure?
      assert_nil @section.reload.archived_at
      assert_not AuditLog.exists?(action: "admin.forum_section_archived", resource_id: @section.id)
    end

    test "service enforces operation-specific lifecycle permissions" do
      ordinary_user = create_user(username: "life_unprivileged_#{SecureRandom.hex(4)}")

      archive_result = Community::ManageSectionLifecycle.call(
        section: @section,
        actor: ordinary_user,
        operation: "archive",
        reason: "Unauthorized archive",
        confirmation: "ARCHIVE #{@section.slug}"
      )
      assert_predicate archive_result, :failure?
      assert_equal I18n.t("mcweb.services.community.section_lifecycle.permission_denied"), archive_result.error
      assert_nil @section.reload.archived_at

      @section.update_columns(archived_at: Time.current, archived_reason: "Prepared")
      delete_result = Community::ManageSectionLifecycle.call(
        section: @section.reload,
        actor: ordinary_user,
        operation: "destroy",
        reason: "Unauthorized delete",
        confirmation: "DELETE #{@section.slug}"
      )
      assert_predicate delete_result, :failure?
      assert Community::Section.exists?(@section.id)
    end

    test "topic moves reject self archived and inherited archived destinations" do
      grant_permission(@actor, "forum.topics.move")
      source = Community::Section.create!(
        category: @category,
        name: "Move source",
        slug: "move-source-#{SecureRandom.hex(4)}",
        position: 2
      )
      destination_parent = Community::Section.create!(
        category: @category,
        name: "Move destination parent",
        slug: "move-destination-parent-#{SecureRandom.hex(4)}",
        position: 3
      )
      destination_child = Community::Section.create!(
        category: @category,
        parent: destination_parent,
        name: "Move destination child",
        slug: "move-destination-child-#{SecureRandom.hex(4)}",
        position: 4
      )
      topic = create_topic(section: source)

      run_operation(destination_child, "archive", reason: "Directly retired")
      self_archived = Community::MoveTopic.call(
        user: @actor,
        topic: topic,
        section: destination_child.reload
      )
      assert_predicate self_archived, :failure?
      assert_equal I18n.t("mcweb.services.errors.destination_section_not_available"), self_archived.error

      run_operation(destination_child, "restore", reason: "Restore child state")
      run_operation(destination_parent, "archive", reason: "Retire destination branch")
      inherited_archived = Community::MoveTopic.call(
        user: @actor,
        topic: topic.reload,
        section: destination_child.reload
      )

      assert_predicate inherited_archived, :failure?
      assert_equal I18n.t("mcweb.services.errors.destination_section_not_available"), inherited_archived.error
      assert_equal source.id, topic.reload.forum_section_id
      assert_not_includes Community::SectionModeration.moderated_sections_for(@actor), destination_child
    end

    test "split and merge cannot move content into archived destinations" do
      grant_permission(@actor, "forum.topics.move")
      destination = Community::Section.create!(
        category: @category,
        name: "Archived structural destination",
        slug: "archived-structural-destination-#{SecureRandom.hex(4)}",
        position: 5
      )
      source_topic = create_topic(section: @section)
      opening_post = Community::Post.create!(
        topic: source_topic,
        user: @author,
        floor_number: 1,
        body: "Opening post",
        status: "published"
      )
      reply = Community::Post.create!(
        topic: source_topic,
        user: @author,
        floor_number: 2,
        body: "Reply to split",
        status: "published"
      )
      target_topic = create_topic(section: destination)
      Community::Post.create!(
        topic: target_topic,
        user: @author,
        floor_number: 1,
        body: "Archived target opening post",
        status: "published"
      )
      run_operation(destination, "archive", reason: "Reject structural moves")

      split_result = Community::SplitTopic.call(
        user: @actor,
        topic: source_topic,
        post: reply,
        section: destination.reload
      )
      assert_predicate split_result, :failure?
      assert_equal I18n.t("mcweb.services.errors.destination_section_not_available"), split_result.error
      assert_equal source_topic.id, reply.reload.forum_topic_id

      merge_result = Community::MergeTopics.call(
        user: @actor,
        source: source_topic.reload,
        target_public_id: target_topic.public_id
      )
      assert_predicate merge_result, :failure?
      assert_equal I18n.t("mcweb.services.errors.destination_section_not_available"), merge_result.error
      assert_equal "published", source_topic.reload.status
      assert_equal source_topic.id, opening_post.reload.forum_topic_id
      assert_equal source_topic.id, reply.reload.forum_topic_id
    end

    test "archived subtree topics migrate through the audited admin service" do
      grant_permission(@actor, "forum.topics.move")
      child = Community::Section.create!(
        category: @category,
        parent: @section,
        name: "Migration child",
        slug: "migration-child-#{SecureRandom.hex(4)}",
        position: 1
      )
      target = Community::Section.create!(
        category: @category,
        name: "Migration target",
        slug: "migration-target-#{SecureRandom.hex(4)}",
        position: 2
      )
      root_topic = create_topic(section: @section)
      child_topic = create_topic(section: child)
      run_operation(@section, "archive", reason: "Move retained content")

      result = Community::MigrateArchivedSectionTopics.call(
        source_section: @section.reload,
        target_section: target,
        actor: @actor,
        reason: "Consolidating the retired branch",
        request_id: "section-migration-request"
      )

      assert_predicate result, :success?
      assert_equal [ target.id ], [ root_topic.reload.forum_section_id, child_topic.reload.forum_section_id ].uniq
      audit = AuditLog.find_by!(
        action: "admin.forum_section_topics_migrated",
        resource_id: @section.id
      )
      assert_equal "section-migration-request", audit.request_id
      assert_equal 2, audit.metadata.fetch("topic_count")
      assert_equal target.id, audit.metadata.fetch("target_section_id")
    end

    private

    def run_operation(section, operation, reason:)
      Community::ManageSectionLifecycle.call(
        section: section,
        actor: @actor,
        operation: operation,
        reason: reason,
        confirmation: Community::ManageSectionLifecycle.confirmation_for(
          section: section,
          operation: operation
        )
      )
    end

    def create_topic(section:)
      Community::Topic.create!(
        public_id: "topic_#{SecureRandom.alphanumeric(16)}",
        section: section,
        user: @author,
        title: "Lifecycle retained topic",
        status: "published",
        last_posted_at: Time.current,
        last_post_user: @author,
        replies_count: 0
      )
    end
  end
end
