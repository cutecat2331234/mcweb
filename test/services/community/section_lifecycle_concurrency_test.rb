# frozen_string_literal: true

require "test_helper"

module Community
  class SectionLifecycleConcurrencyTest < ActiveSupport::TestCase
    self.use_transactional_tests = false

    setup do
      suffix = SecureRandom.hex(6)
      @actor = create_user(username: "section_lock_admin_#{suffix}")
      grant_permission(@actor, "forum.sections.lifecycle")
      grant_permission(@actor, "forum.sections.delete")
      @author = create_user(username: "section_lock_author_#{suffix}")
      @extra_sections = []
      @category = Community::Category.create!(
        name: "Section locking #{suffix}",
        slug: "section-locking-#{suffix}"
      )
      @parent = Community::Section.create!(
        category: @category,
        name: "Lock parent",
        slug: "lock-parent-#{suffix}",
        position: 0
      )
      @child = Community::Section.create!(
        category: @category,
        parent: @parent,
        name: "Lock child",
        slug: "lock-child-#{suffix}",
        position: 1
      )
    end

    teardown do
      section_ids = [ @parent&.id, @child&.id, *@extra_sections.map(&:id) ].compact
      topic_ids = Community::Topic.with_discarded.where(forum_section_id: section_ids).pluck(:id)
      Community::Post.with_discarded.where(forum_topic_id: topic_ids).delete_all
      Community::ReadState.where(forum_topic_id: topic_ids).delete_all
      Community::Subscription.where(
        subscribable_type: "Community::Topic",
        subscribable_id: topic_ids
      ).delete_all
      Community::Topic.with_discarded.where(id: topic_ids).delete_all
      AuditLog.where(resource_type: "Community::Section", resource_id: section_ids).delete_all
      Community::Section.where(id: @child&.id).delete_all
      Community::Section.where(id: @extra_sections.map(&:id)).delete_all
      Community::Section.where(id: @parent&.id).delete_all
      Community::Category.where(id: @category&.id).delete_all
      user_ids = [ @actor&.id, @author&.id ].compact
      AuditLog.where(actor_id: user_ids).delete_all
      UserRole.where(user_id: user_ids).delete_all
      User.where(id: user_ids).delete_all
    end

    test "archiving a parent serializes with topic creation in its child" do
      archive_result, write_result = race_parent_archive do
        Community::CreateTopic.call(
          user: User.find(@author.id),
          section: Community::Section.find(@child.id),
          title: "Concurrent child topic",
          body: "This write must observe the committed parent archive.",
          ip_address: "127.0.0.1"
        )
      end

      assert_predicate archive_result, :success?
      assert_predicate write_result, :failure?
      assert_equal I18n.t("mcweb.services.errors.section_not_available"), write_result.error
      assert_not Community::Topic.where(
        forum_section_id: @child.id,
        title: "Concurrent child topic"
      ).exists?
    end

    test "archiving a parent serializes with replies in its child" do
      topic = Community::Topic.create!(
        public_id: "topic_#{SecureRandom.alphanumeric(16)}",
        section: @child,
        user: @author,
        title: "Existing child topic",
        status: "published",
        last_posted_at: Time.current,
        last_post_user: @author,
        replies_count: 0
      )
      Community::Post.create!(
        topic: topic,
        user: @author,
        floor_number: 1,
        body: "Opening post",
        status: "published"
      )

      archive_result, write_result = race_parent_archive do
        Community::CreatePost.call(
          user: User.find(@author.id),
          topic: Community::Topic.find(topic.id),
          body: "Concurrent reply must not be persisted.",
          ip_address: "127.0.0.1",
          skip_interval_check: true
        )
      end

      assert_predicate archive_result, :success?
      assert_predicate write_result, :failure?
      assert_equal I18n.t("mcweb.services.errors.topic_not_available"), write_result.error
      assert_equal 1, topic.posts.with_discarded.count
    end

    test "archiving a parent serializes with topic forks and scheduled topics" do
      source_topic = Community::Topic.create!(
        public_id: "topic_#{SecureRandom.alphanumeric(16)}",
        section: @child,
        user: @author,
        title: "Fork source",
        status: "published",
        last_posted_at: Time.current,
        last_post_user: @author,
        replies_count: 0
      )
      source_post = Community::Post.create!(
        topic: source_topic,
        user: @author,
        floor_number: 1,
        body: "Fork source post",
        status: "published"
      )

      archive_result, fork_result = race_parent_archive do
        Community::CreateTopicFromPost.call(
          user: User.find(@author.id),
          post: Community::Post.find(source_post.id),
          title: "Concurrent fork",
          section: Community::Section.find(@child.id)
        )
      end

      assert_predicate archive_result, :success?
      assert_predicate fork_result, :failure?
      assert_not Community::Topic.where(title: "Concurrent fork").exists?

      restore_parent
      archive_result, scheduled_result = race_parent_archive do
        Community::ScheduleTopic.call(
          user: User.find(@author.id),
          section: Community::Section.find(@child.id),
          title: "Concurrent scheduled topic",
          body: "Scheduled body",
          scheduled_at: 1.day.from_now
        )
      end

      assert_predicate archive_result, :success?
      assert_predicate scheduled_result, :failure?
      assert_not Community::Topic.where(title: "Concurrent scheduled topic").exists?
    end

    test "archiving serializes section subscriptions and leaves no hidden write" do
      archive_result, subscription_result = race_parent_archive do
        Community::ToggleSectionSubscription.call(
          user: User.find(@author.id),
          section: Community::Section.find(@child.id)
        )
      end

      assert_predicate archive_result, :success?
      assert_predicate subscription_result, :failure?
      assert_not Community::Subscription.exists?(
        user_id: @author.id,
        subscribable_type: "Community::Section",
        subscribable_id: @child.id
      )
    end

    test "topic migration retries after a discovered child is concurrently reparented" do
      grant_permission(@actor, "forum.topics.move")
      target = track_section(
        Community::Section.create!(
          category: @category,
          name: "Migration target",
          slug: "migration-target-#{SecureRandom.hex(5)}",
          position: 2
        )
      )
      root_topic = create_topic(section: @parent, title: "Root migration topic")
      child_topic = create_topic(section: @child, title: "Reparented child topic")
      archive_section(@parent)

      lock_entered = Queue.new
      release_lock = Queue.new
      migration_outcome = Queue.new
      original_lock = Community::SectionHierarchyLock.method(:lock!)
      blocked = false
      guard = Mutex.new
      blocking_lock = lambda do |*sections|
        ids = sections.flatten.compact.map(&:id)
        should_block = guard.synchronize do
          next false if blocked || !ids.include?(@parent.id) || !ids.include?(target.id) || !ids.include?(@child.id)

          blocked = true
          true
        end
        if should_block
          lock_entered << true
          release_lock.pop
        end
        original_lock.call(*sections)
      end

      Community::SectionHierarchyLock.stub(:lock!, blocking_lock) do
        migration_thread = Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            migration_outcome << Community::MigrateArchivedSectionTopics.call(
              source_section: Community::Section.find(@parent.id),
              target_section: Community::Section.find(target.id),
              actor: User.find(@actor.id),
              reason: "Concurrent branch migration"
            )
          rescue StandardError => e
            migration_outcome << e
          end
        end

        lock_entered.pop
        Community::Section.find(@child.id).update!(parent: nil)
        release_lock << true
        migration_thread.join
      end

      result = migration_outcome.pop
      raise result if result.is_a?(Exception)

      assert_predicate result, :success?
      assert_equal target.id, root_topic.reload.forum_section_id
      assert_equal @child.id, child_topic.reload.forum_section_id
      audit = AuditLog.find_by!(action: "admin.forum_section_topics_migrated", resource_id: @parent.id)
      assert_equal [ @parent.id ], audit.metadata.fetch("subtree_section_ids")
    end

    test "topic migration returns not available when its target disappears before locking" do
      grant_permission(@actor, "forum.topics.move")
      target = track_section(
        Community::Section.create!(
          category: @category,
          name: "Disappearing target",
          slug: "disappearing-target-#{SecureRandom.hex(5)}",
          position: 3
        )
      )
      topic = create_topic(section: @parent, title: "Unmoved source topic")
      archive_section(@parent)

      lock_entered = Queue.new
      release_lock = Queue.new
      migration_outcome = Queue.new
      original_lock = Community::SectionHierarchyLock.method(:lock!)
      blocked = false
      guard = Mutex.new
      blocking_lock = lambda do |*sections|
        ids = sections.flatten.compact.map(&:id)
        should_block = guard.synchronize do
          next false if blocked || !ids.include?(@parent.id) || !ids.include?(target.id)

          blocked = true
          true
        end
        if should_block
          lock_entered << true
          release_lock.pop
        end
        original_lock.call(*sections)
      end

      Community::SectionHierarchyLock.stub(:lock!, blocking_lock) do
        migration_thread = Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            migration_outcome << Community::MigrateArchivedSectionTopics.call(
              source_section: Community::Section.find(@parent.id),
              target_section: Community::Section.find(target.id),
              actor: User.find(@actor.id),
              reason: "Target disappeared"
            )
          rescue StandardError => e
            migration_outcome << e
          end
        end

        lock_entered.pop
        archive_section(target)
        destroy_result = lifecycle_operation(target.reload, "destroy", reason: "Remove empty target")
        assert_predicate destroy_result, :success?
        release_lock << true
        migration_thread.join
      end

      result = migration_outcome.pop
      raise result if result.is_a?(Exception)

      assert_predicate result, :failure?
      assert_equal I18n.t("mcweb.services.errors.section_not_available"), result.error
      assert_equal @parent.id, topic.reload.forum_section_id
    end

    test "a second concurrent permanent delete returns a lifecycle conflict" do
      archive_section(@child)
      audit_entered = Queue.new
      release_delete = Queue.new
      first_outcome = Queue.new
      second_outcome = Queue.new
      original_audit = Administration::AuditLogger.method(:call)
      blocked = false
      guard = Mutex.new
      blocking_audit = lambda do |**attributes|
        should_block = guard.synchronize do
          next false if blocked || attributes[:action] != "admin.forum_section_deleted"

          blocked = true
          true
        end
        if should_block
          audit_entered << true
          release_delete.pop
        end
        original_audit.call(**attributes)
      end

      Administration::AuditLogger.stub(:call, blocking_audit) do
        first_thread = Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            first_outcome << lifecycle_operation(
              Community::Section.find(@child.id),
              "destroy",
              reason: "First concurrent delete"
            )
          rescue StandardError => e
            first_outcome << e
          end
        end

        audit_entered.pop
        stale_section = Community::Section.find(@child.id)
        second_thread = Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            second_outcome << lifecycle_operation(
              stale_section,
              "destroy",
              reason: "Second concurrent delete"
            )
          rescue StandardError => e
            second_outcome << e
          end
        end

        release_delete << true
        first_thread.join
        second_thread.join
      end

      first_result = first_outcome.pop
      second_result = second_outcome.pop
      raise first_result if first_result.is_a?(Exception)
      raise second_result if second_result.is_a?(Exception)

      assert_predicate first_result, :success?
      assert_predicate second_result, :failure?
      assert_equal I18n.t("mcweb.services.community.section_lifecycle.conflict"), second_result.error
      assert_not Community::Section.exists?(@child.id)
    end

    private

    def track_section(section)
      @extra_sections << section
      section
    end

    def create_topic(section:, title:)
      Community::Topic.create!(
        public_id: "topic_#{SecureRandom.alphanumeric(16)}",
        section: section,
        user: @author,
        title: title,
        status: "published",
        last_posted_at: Time.current,
        last_post_user: @author,
        replies_count: 0
      )
    end

    def archive_section(section)
      result = lifecycle_operation(section.reload, "archive", reason: "Prepare lifecycle concurrency coverage")
      assert_predicate result, :success?
      result
    end

    def lifecycle_operation(section, operation, reason:)
      Community::ManageSectionLifecycle.call(
        section: section,
        actor: User.find(@actor.id),
        operation: operation,
        reason: reason,
        confirmation: Community::ManageSectionLifecycle.confirmation_for(
          section: section,
          operation: operation
        )
      )
    end

    def restore_parent
      result = Community::ManageSectionLifecycle.call(
        section: @parent.reload,
        actor: @actor,
        operation: "restore",
        reason: "Continue concurrency coverage",
        confirmation: "RESTORE #{@parent.slug}"
      )
      assert_predicate result, :success?
    end

    def race_parent_archive(&write)
      audit_entered = Queue.new
      release_archive = Queue.new
      archive_outcome = Queue.new
      write_outcome = Queue.new
      original_audit = Administration::AuditLogger.method(:call)

      blocking_audit = lambda do |**attributes|
        if attributes[:action] == "admin.forum_section_archived"
          audit_entered << true
          release_archive.pop
        end
        original_audit.call(**attributes)
      end

      Administration::AuditLogger.stub(:call, blocking_audit) do
        archive_thread = Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            archive_outcome << Community::ManageSectionLifecycle.call(
              section: Community::Section.find(@parent.id),
              actor: User.find(@actor.id),
              operation: "archive",
              reason: "Concurrent retirement",
              confirmation: "ARCHIVE #{@parent.slug}"
            )
          rescue StandardError => e
            archive_outcome << e
          end
        end

        audit_entered.pop
        write_thread = Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            write_outcome << write.call
          rescue StandardError => e
            write_outcome << e
          end
        end

        assert_nil write_thread.join(0.15), "the child write did not wait for the parent lifecycle lock"
        release_archive << true
        archive_thread.join
        write_thread.join
      end

      archive_result = archive_outcome.pop
      write_result = write_outcome.pop
      raise archive_result if archive_result.is_a?(Exception)
      raise write_result if write_result.is_a?(Exception)

      [ archive_result, write_result ]
    end
  end
end
