# frozen_string_literal: true

require "test_helper"

class WebsiteContentRecoveryTest < ActiveSupport::TestCase
  setup do
    @actor = create_user
    grant_permission(@actor, "website.content.purge")
    @theme = Website::Theme.create!(
      name: "Recovery theme #{SecureRandom.hex(3)}",
      key: "recovery-theme-#{SecureRandom.hex(4)}"
    )
  end

  test "page update records the complete pre-change snapshot and rolls failed mutations back" do
    page = build_page(status: "published", title: "Before")
    page.blocks.create!(
      block_type: "hero", position: 0, visible: true,
      settings: { "headline" => "Before headline" },
      translations: { "zh-CN" => { "headline" => "旧标题" } }
    )

    update_key = request_id("page-update")
    result = Website::ContentUpdate.call(
      content: page,
      attributes: { title: "After", seo: { "title" => "After SEO" } },
      actor: @actor,
      expected_lock_version: page.lock_version,
      request_id: update_key
    )

    assert result.success?
    revision = page.revisions.ordered.first
    assert_equal "update", revision.event_type
    assert_equal "Before", revision.snapshot.fetch("title")
    assert_equal "Before headline", revision.snapshot.fetch("blocks").first.dig("settings", "headline")
    assert_equal "旧标题", revision.snapshot.fetch("blocks").first.dig("translations", "zh-CN", "headline")

    reused = Website::ContentUpdate.call(
      content: page.reload,
      attributes: { title: "Different payload" },
      actor: @actor,
      expected_lock_version: page.lock_version,
      request_id: update_key
    )
    assert_equal "website_content_idempotency_key_reused", reused.code

    count = page.revisions.count
    failed = Website::ContentUpdate.call(
      content: page.reload,
      attributes: { title: "" },
      actor: @actor,
      expected_lock_version: page.lock_version,
      request_id: request_id("page-invalid")
    )
    assert failed.failure?
    assert_equal count, page.revisions.count
    assert_equal "After", page.reload.title
  end

  test "article history retains pre-change body across publish schedule archive and revision restore" do
    article = build_article(title: "Article before", body: "Body before")
    update = Website::ContentUpdate.call(
      content: article,
      attributes: { body: "Body after" },
      actor: @actor,
      expected_lock_version: article.lock_version,
      request_id: request_id("article-update")
    )
    assert update.success?
    source_revision = article.revisions.ordered.first
    assert_equal "Body before", source_revision.snapshot.fetch("body")

    publish = Website::ArticlePublisher.call(
      article: article.reload,
      actor: @actor,
      expected_lock_version: article.lock_version,
      request_id: request_id("article-publish")
    )
    assert publish.success?

    archive = Website::ArchiveContent.call(
      content: article.reload,
      actor: @actor,
      expected_lock_version: article.lock_version,
      request_id: request_id("article-archive")
    )
    assert archive.success?

    restore_key = request_id("article-revision-restore")
    restored = Website::RestoreRevision.call(
      content: article.reload,
      revision: source_revision,
      actor: @actor,
      reason: "Restore the previous article body",
      confirmation: article.title,
      expected_lock_version: article.lock_version,
      idempotency_key: restore_key
    )
    assert restored.success?
    assert_equal "draft", article.reload.status
    assert_equal "Body before", article.body
    assert_equal %w[revision_restore archive publish update],
      article.revisions.ordered.limit(4).pluck(:event_type)

    mismatched_source = Website::RestoreRevision.call(
      content: article.reload,
      revision: article.revisions.where(event_type: "publish").first,
      actor: @actor,
      reason: "Restore the previous article body",
      confirmation: article.title,
      expected_lock_version: article.lock_version,
      idempotency_key: restore_key
    )
    assert_equal "website_content_idempotency_key_reused", mismatched_source.code
  end

  test "discard and restore retries converge and active slug conflicts fail without partial mutation" do
    page = build_page(title: "Recover me")
    discard_key = request_id("discard")
    initial_version = page.lock_version
    first = discard(page, key: discard_key, expected_version: initial_version)
    second = discard(page, key: discard_key, expected_version: initial_version)
    assert first.success?
    assert second.success?
    assert second.value.fetch(:replayed)
    reused = discard(
      page,
      key: discard_key,
      expected_version: initial_version,
      reason: "A different discard operation"
    )
    assert_equal "website_content_idempotency_key_reused", reused.code
    assert_nil Website::Page.find_by(id: page.id)
    assert Website::Page.discarded_content.exists?(id: page.id)

    conflicting = build_page(title: "Conflict", slug: page.slug)
    restore = restore(page, key: request_id("restore-conflict"))
    assert restore.failure?
    assert_equal "website_content_restore_blocked", restore.code
    assert Website::Page.discarded_content.exists?(id: page.id)
    conflicting.update!(slug: "released-#{SecureRandom.hex(4)}")

    restore_key = request_id("restore")
    restored = restore(page, key: restore_key)
    replayed = restore(page, key: restore_key, expected_version: page.reload.lock_version - 1)
    assert restored.success?
    assert replayed.success?
    assert replayed.value.fetch(:replayed)
    assert_equal "draft", page.reload.status
    assert_nil page.discarded_at
  end

  test "published home page discard requires another published home page" do
    home = build_page(status: "published", page_type: "home", title: "Current home")
    blocked = discard(home, key: request_id("home-blocked"), expected_version: home.lock_version)
    assert_equal "website_home_replacement_required", blocked.code
    assert home.reload.active_content?

    replacement = build_page(
      status: "published", page_type: "home", title: "Replacement home",
      slug: "replacement-home-#{SecureRandom.hex(3)}"
    )
    allowed = Website::DiscardContent.call(
      content: home,
      actor: @actor,
      reason: "Replace the public home page",
      confirmation: home.title,
      expected_lock_version: home.lock_version,
      idempotency_key: request_id("home-allowed"),
      replacement_page_public_id: replacement.public_id
    )
    assert allowed.success?
    assert Website::Page.cms_home.exists?(id: replacement.id)
    refute Website::Page.cms_home.exists?(id: home.id)
  end

  test "discarded content stays out of public scopes navigation sitemap and scheduled publishing" do
    page = build_page(status: "published", title: "Hidden page")
    article = build_article(status: "scheduled", title: "Hidden article")
    article.update!(scheduled_at: 1.minute.ago)
    nav = Website::NavItem.create!(
      label: "Hidden page", page: page, location: "header", position: 0, visible: true
    )

    assert discard(page, key: request_id("hide-page"), expected_version: page.lock_version).success?
    assert discard(article, key: request_id("hide-article"), expected_version: article.lock_version).success?
    assert_nil nav.reload.href
    assert_empty Website::NavItem.frontend_items("header").select { |item| item[:label] == "Hidden page" }

    Website::PublishScheduledContentJob.perform_now
    assert Website::Article.discarded_content.find(article.id).discarded?
    Website::GenerateSitemapJob.perform_now
    sitemap = Rails.root.join("public", "sitemap.xml").read
    refute_includes sitemap, page.slug
    refute_includes sitemap, article.slug
  end

  test "final purge enforces retention and references then keeps immutable evidence and tombstone" do
    page = build_page(title: "Purge target")
    page.blocks.create!(block_type: "rich_text", position: 0, settings: { "html" => "Mutable" })
    nav = Website::NavItem.create!(
      label: "Purge target", page: page, location: "footer", position: 0, visible: true
    )
    discarded_at = 40.days.ago
    assert Website::DiscardContent.call(
      content: page,
      actor: @actor,
      reason: "Retire obsolete content",
      confirmation: page.title,
      expected_lock_version: page.lock_version,
      idempotency_key: request_id("purge-discard"),
      at: discarded_at
    ).success?

    blocked = Website::FinalPurge.call(
      content: page,
      actor: nil,
      reason: "retention_expired",
      confirmation: Website::FinalPurge.confirmation_for(page),
      expected_lock_version: page.reload.lock_version,
      idempotency_key: request_id("purge-blocked"),
      background: true
    )
    assert_equal "website_content_purge_blocked", blocked.code

    nav.destroy!
    purge_key = request_id("purge-success")
    purged = Website::FinalPurge.call(
      content: page,
      actor: nil,
      reason: "retention_expired",
      confirmation: Website::FinalPurge.confirmation_for(page),
      expected_lock_version: page.reload.lock_version,
      idempotency_key: purge_key,
      background: true
    )
    replayed = Website::FinalPurge.call(
      content: page,
      actor: nil,
      reason: "retention_expired",
      confirmation: Website::FinalPurge.confirmation_for(page),
      expected_lock_version: page.lock_version - 1,
      idempotency_key: purge_key,
      background: true
    )
    assert purged.success?
    assert replayed.success?
    mismatched_replay = Website::FinalPurge.call(
      content: page,
      actor: nil,
      reason: "different_retention_reason",
      confirmation: Website::FinalPurge.confirmation_for(page),
      expected_lock_version: page.lock_version - 1,
      idempotency_key: purge_key,
      background: true
    )
    assert_equal "website_content_idempotency_key_reused", mismatched_replay.code
    tombstone = Website::Page.with_lifecycle.find(page.id)
    assert tombstone.purged?
    assert_empty tombstone.blocks
    assert_equal tombstone.public_id, tombstone.title
    assert tombstone.revisions.where(event_type: "purge").exists?
    assert_not tombstone.update(title: "Changed")
    assert_not tombstone.destroy
  end

  test "final purge authorization requires current credentials and binds the preview to state and reason" do
    page = build_page(title: "Protected purge")
    assert Website::DiscardContent.call(
      content: page,
      actor: @actor,
      reason: "Retire protected content",
      confirmation: page.title,
      expected_lock_version: page.lock_version,
      idempotency_key: request_id("protected-discard"),
      at: 40.days.ago
    ).success?
    reason = "Retention review approved final purge"
    key = request_id("protected-purge")

    denied = Website::PurgeAuthorization.call(
      actor: @actor,
      content: page,
      reason: reason,
      request_id: key,
      password: "incorrect"
    )
    assert denied.failure?
    assert_equal "password_incorrect", denied.code

    issued = Website::PurgeAuthorization.call(
      actor: @actor,
      content: page,
      reason: reason,
      request_id: key,
      password: "password123"
    )
    assert issued.success?
    verified = Website::PurgeAuthorization.call(
      actor: @actor,
      content: page,
      reason: reason,
      request_id: key,
      authorization_token: issued.value.fetch(:authorization_token)
    )
    assert verified.success?
    assert_equal "password", verified.value.fetch(:authorization_method)

    rebound = Website::PurgeAuthorization.call(
      actor: @actor,
      content: page,
      reason: "A different reason",
      request_id: key,
      authorization_token: issued.value.fetch(:authorization_token)
    )
    assert_equal "website_content_purge_authorization_invalid", rebound.code

    purged = Website::FinalPurge.call(
      content: page,
      actor: @actor,
      reason: reason,
      confirmation: issued.value.fetch(:confirmation),
      expected_lock_version: page.reload.lock_version,
      idempotency_key: key,
      authorization_token: issued.value.fetch(:authorization_token)
    )
    assert purged.success?
    replayed = Website::FinalPurge.call(
      content: page,
      actor: @actor,
      reason: reason,
      confirmation: issued.value.fetch(:confirmation),
      expected_lock_version: page.lock_version,
      idempotency_key: key,
      authorization_token: issued.value.fetch(:authorization_token)
    )
    assert replayed.success?
    assert replayed.value.fetch(:replayed)
    assert Website::Page.with_lifecycle.find(page.id).purged?
  end

  test "block mutations snapshot ordered blocks and reject stale ordering" do
    page = build_page(title: "Blocks")
    first = page.blocks.create!(block_type: "hero", position: 0, settings: { "headline" => "One" })
    second = page.blocks.create!(block_type: "rich_text", position: 1, settings: { "html" => "Two" })
    page.reload

    reorder_key = request_id("block-reorder")
    result = Website::BlockMutation.call(
      page: page,
      actor: @actor,
      action: :reorder,
      block_ids: [ second.id, first.id ],
      expected_lock_version: page.lock_version,
      request_id: reorder_key
    )
    assert result.success?
    assert_equal [ first.id, second.id ],
      page.revisions.ordered.first.snapshot.fetch("blocks").map { |block| block.fetch("id") }
    assert_equal [ second.id, first.id ], page.blocks.reload.unscope(:order).order(:position).pluck(:id)

    mismatched_replay = Website::BlockMutation.call(
      page: page.reload,
      actor: @actor,
      action: :reorder,
      block_ids: [ first.id, second.id ],
      expected_lock_version: page.lock_version,
      request_id: reorder_key
    )
    assert_equal "website_content_idempotency_key_reused", mismatched_replay.code

    stale = Website::BlockMutation.call(
      page: page.reload,
      actor: @actor,
      action: :reorder,
      block_ids: [ second.id ],
      expected_lock_version: page.lock_version,
      request_id: request_id("block-stale")
    )
    assert_equal "website_block_reorder_conflict", stale.code
  end

  private

  def build_page(status: "draft", title: "Page", slug: nil, page_type: "custom")
    Website::Page.create!(
      title: title,
      slug: slug || "recovery-page-#{SecureRandom.hex(4)}",
      page_type: page_type,
      status: status,
      published_at: status == "published" ? Time.current : nil,
      theme: @theme,
      author: @actor
    )
  end

  def build_article(status: "draft", title: "Article", body: "Body")
    Website::Article.create!(
      title: title,
      slug: "recovery-article-#{SecureRandom.hex(4)}",
      article_type: "news",
      status: status,
      published_at: status == "published" ? Time.current : nil,
      body: body,
      author: @actor
    )
  end

  def discard(content, key:, expected_version:, reason: "Content is no longer current")
    Website::DiscardContent.call(
      content: content,
      actor: @actor,
      reason: reason,
      confirmation: content.title,
      expected_lock_version: expected_version,
      idempotency_key: key
    )
  end

  def restore(content, key:, expected_version: nil)
    current = content.class.with_lifecycle.find(content.id)
    Website::RestoreContent.call(
      content: current,
      actor: @actor,
      reason: "Restore the discarded content",
      confirmation: current.title,
      expected_lock_version: expected_version || current.lock_version,
      idempotency_key: key
    )
  end

  def request_id(prefix)
    "website-#{prefix}-#{SecureRandom.uuid}"
  end
end
