# frozen_string_literal: true

require "test_helper"

module Community
  class UploadQuotaTest < ActiveSupport::TestCase
    setup do
      @user = create_user
    end

    test "enforces retained account bytes and emits a rejection event" do
      SiteSetting.set("forum.upload_quota.account.bytes", "3")
      events = []
      subscriber = ActiveSupport::Notifications.subscribe(
        "community.upload.quota_rejected"
      ) do |event|
        events << event.payload
      end

      first = Community::UploadQuota.call(
        user: @user,
        kind: :inline_image,
        byte_size: 2
      )
      second = Community::UploadQuota.call(
        user: @user,
        kind: :post_attachment,
        byte_size: 2
      )

      assert_predicate first, :success?
      assert_predicate second, :failure?
      assert_equal "upload_quota_exceeded", second.code
      assert_equal "account", second.value[:scope]
      assert_equal "bytes", second.value[:metric]
      assert_equal 1, events.size
      assert_equal @user.id, events.first[:user_id]
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
    end

    test "enforces identity group retained count" do
      group = Community::UserGroup.create!(name: "Quota group", priority: 10)
      Community::GroupMembership.create!(user: @user, user_group: group)
      SiteSetting.set("forum.upload_quota.group.#{group.id}.count", "1")

      first = Community::UploadQuota.call(
        user: @user,
        kind: :inline_image,
        byte_size: 1
      )
      second = Community::UploadQuota.call(
        user: @user,
        kind: :inline_image,
        byte_size: 1
      )

      assert_predicate first, :success?
      assert_predicate second, :failure?
      assert_equal "group", second.value[:scope]
      assert_equal group.id, second.value[:scope_id]
      assert_equal "count", second.value[:metric]
    end

    test "enforces site retained count across accounts" do
      other = create_user
      retained_count = Community::Upload.counted_toward_quota.count
      SiteSetting.set("forum.upload_quota.site.count", (retained_count + 1).to_s)

      first = Community::UploadQuota.call(
        user: @user,
        kind: :inline_image,
        byte_size: 1
      )
      second = Community::UploadQuota.call(
        user: other,
        kind: :post_attachment,
        byte_size: 1
      )

      assert_predicate first, :success?
      assert_predicate second, :failure?
      assert_equal "site", second.value[:scope]
      assert_equal "count", second.value[:metric]
      assert_equal retained_count + 1, second.value[:used]
    end

    test "accepted upload frequency remains accounted after storage is cleaned" do
      SiteSetting.set("forum.upload_quota.account.hourly_count", "1")
      first = Community::UploadQuota.call(
        user: @user,
        kind: :inline_image,
        byte_size: 1
      )
      first.value.update!(status: "cleaned", cleaned_at: Time.current, expires_at: nil)

      second = Community::UploadQuota.call(
        user: @user,
        kind: :inline_image,
        byte_size: 1
      )

      assert_predicate second, :failure?
      assert_equal "hourly_count", second.value[:metric]
    end
  end

  class UploadLifecycleTest < ActiveSupport::TestCase
    setup do
      @user = create_user(forum_trust_level_override: 1)
      suffix = SecureRandom.hex(5)
      category = Community::Category.create!(
        name: "Upload lifecycle #{suffix}",
        slug: "upload-lifecycle-category-#{suffix}"
      )
      section = Community::Section.create!(
        category: category,
        name: "Upload lifecycle",
        slug: "upload-lifecycle-section-#{suffix}",
        position: 0
      )
      @topic = Community::Topic.create!(
        public_id: "topic_#{SecureRandom.alphanumeric(16)}",
        section: section,
        user: @user,
        title: "Upload lifecycle",
        status: "published",
        last_posted_at: Time.current,
        last_post_user: @user,
        replies_count: 0
      )
      @post = Community::Post.create!(
        topic: @topic,
        user: @user,
        floor_number: 1,
        body: "Opening post",
        status: "published"
      )
    end

    test "binds an inline upload token to saved content" do
      upload, blob = stored_upload(kind: :inline_image)
      body = "![image](/rails/active_storage/blobs/redirect/signed/file.png?upload=#{upload.public_id})"

      result = Community::BindInlineUploads.call(
        user: @user,
        post: @post,
        body: body
      )

      assert_predicate result, :success?
      assert_equal 1, result.value[:linked]
      assert_equal "linked", upload.reload.status
      assert_equal @post.id, upload.forum_post_id
      assert_nil upload.expires_at
      assert ActiveStorage::Blob.exists?(blob.id)
    end

    test "cleans an expired inline blob exactly once and emits lifecycle telemetry" do
      upload, blob = stored_upload(kind: :inline_image)
      upload.update!(expires_at: 1.minute.ago)
      events = []
      subscriber = ActiveSupport::Notifications.subscribe(
        "community.upload.cleaned"
      ) do |event|
        events << event.payload
      end

      first = Community::CleanupUpload.call(upload: upload)
      second = Community::CleanupUpload.call(upload: upload.reload)

      assert_predicate first, :success?
      assert_predicate second, :success?
      assert_equal "already_cleaned", second.value[:skipped]
      assert_equal "cleaned", upload.reload.status
      assert_equal 1, upload.cleanup_attempts
      assert_not ActiveStorage::Blob.exists?(blob.id)
      assert_equal [ upload.id ], events.map { |payload| payload[:upload_id] }
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
    end

    test "does not clean a linked inline upload" do
      upload, blob = stored_upload(kind: :inline_image)
      upload.update!(
        status: "linked",
        post: @post,
        expires_at: 1.minute.ago
      )

      result = Community::CleanupUpload.call(upload: upload)

      assert_predicate result, :success?
      assert_equal "not_due", result.value[:skipped]
      assert ActiveStorage::Blob.exists?(blob.id)
    end

    test "cleans an expired unlinked attachment and its blob" do
      upload, blob = stored_upload(kind: :post_attachment)
      attachment = Community::PostAttachment.create!(
        user: @user,
        filename: "notes.txt",
        content_type: "text/plain",
        byte_size: blob.byte_size
      )
      attachment.file.attach(blob)
      upload.update!(post_attachment: attachment, expires_at: 1.minute.ago)

      result = Community::CleanupUpload.call(upload: upload)

      assert_predicate result, :success?
      assert_not Community::PostAttachment.exists?(attachment.id)
      assert_not ActiveStorage::Blob.exists?(blob.id)
      assert_equal "cleaned", upload.reload.status
    end

    test "cleanup preserves a blob still attached to another record" do
      upload, blob = stored_upload(kind: :post_attachment)
      expiring = Community::PostAttachment.create!(
        user: @user,
        filename: "expiring.txt",
        content_type: "text/plain",
        byte_size: blob.byte_size
      )
      retained = Community::PostAttachment.create!(
        user: @user,
        filename: "retained.txt",
        content_type: "text/plain",
        byte_size: blob.byte_size
      )
      expiring.file.attach(blob)
      retained.file.attach(blob)
      upload.update!(post_attachment: expiring, expires_at: 1.minute.ago)

      result = Community::CleanupUpload.call(upload: upload)

      assert_predicate result, :success?
      refute Community::PostAttachment.exists?(expiring.id)
      assert Community::PostAttachment.exists?(retained.id)
      assert retained.reload.file.attached?
      assert ActiveStorage::Blob.exists?(blob.id)
      assert_equal "cleaned", upload.reload.status
    ensure
      retained&.file&.purge if retained&.persisted? && retained.file.attached?
      retained&.destroy! if retained&.persisted?
    end

    test "records a purge failure and safely retries from the cleanup outbox" do
      upload, blob = stored_upload(kind: :inline_image)
      upload.update!(expires_at: 1.minute.ago)
      original = ActiveStorage::Blob.instance_method(:delete)
      failed_once = false
      target_id = blob.id
      ActiveStorage::Blob.define_method(:delete) do
        if id == target_id && !failed_once
          failed_once = true
          raise IOError, "simulated storage outage"
        end

        original.bind_call(self)
      end

      first = Community::CleanupUpload.call(upload: upload)
      second = Community::CleanupUpload.call(upload: upload.reload)

      assert_predicate first, :failure?
      assert_predicate second, :success?
      assert_equal "cleaned", upload.reload.status
      assert_equal 2, upload.cleanup_attempts
      assert_not ActiveStorage::Blob.exists?(blob.id)
    ensure
      ActiveStorage::Blob.define_method(:delete, original) if original
    end

    test "adopts and cleans a legacy orphaned post attachment" do
      blob = create_blob("legacy")
      attachment = Community::PostAttachment.create!(
        user: @user,
        filename: "legacy.txt",
        content_type: "text/plain",
        byte_size: blob.byte_size,
        created_at: 2.days.ago,
        updated_at: 2.days.ago
      )
      attachment.file.attach(blob)

      Maintenance::CleanupForumUploadsJob.new.perform(
        now: Time.current,
        limit: 20
      )

      assert_not Community::PostAttachment.exists?(attachment.id)
      assert_not ActiveStorage::Blob.exists?(blob.id)
      assert Community::Upload.where(status: "cleaned", kind: "post_attachment").exists?
    end

    test "cleans an old unattached temporary blob but preserves a managed pending blob" do
      managed_upload, managed_blob = stored_upload(kind: :inline_image)
      managed_blob.update_columns(created_at: 8.days.ago)
      unmanaged_blob = create_blob("temporary")
      unmanaged_blob.update_columns(created_at: 8.days.ago)

      Maintenance::CleanupForumUploadsJob.new.perform(
        now: Time.current,
        limit: 20
      )

      assert ActiveStorage::Blob.exists?(managed_blob.id)
      assert ActiveStorage::Blob.exists?(managed_upload.reload.active_storage_blob_id)
      assert_not ActiveStorage::Blob.exists?(unmanaged_blob.id)
    end

    test "coordinator raises a retryable error when an item cleanup fails" do
      upload, blob = stored_upload(kind: :inline_image)
      upload.update!(expires_at: 1.minute.ago)
      original = ActiveStorage::Blob.instance_method(:purge)
      target_id = blob.id
      ActiveStorage::Blob.define_method(:purge) do
        raise IOError, "simulated storage outage" if id == target_id

        original.bind_call(self)
      end

      assert_raises(Maintenance::CleanupForumUploadsJob::RetryableCleanupError) do
        Maintenance::CleanupForumUploadsJob.new.perform(upload_id: upload.id)
      end
      assert_equal "cleanup_failed", upload.reload.status
    ensure
      ActiveStorage::Blob.define_method(:purge, original) if original
    end

    private

    def stored_upload(kind:)
      result = Community::StoreUpload.call(
        user: @user,
        kind: kind,
        payload: "safe upload bytes",
        filename: kind == :inline_image ? "image.png" : "notes.txt",
        content_type: kind == :inline_image ? "image/png" : "text/plain"
      )
      assert_predicate result, :success?
      [ result.value.fetch(:upload), result.value.fetch(:blob) ]
    end

    def create_blob(contents)
      ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new(contents),
        filename: "orphan.txt",
        content_type: "text/plain",
        identify: false
      )
    end
  end
end
