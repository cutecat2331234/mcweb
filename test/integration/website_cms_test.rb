# frozen_string_literal: true

require "test_helper"

class WebsiteCmsIntegrationTest < ActionDispatch::IntegrationTest
  setup do
    @theme = Website::Theme.find_or_create_by!(key: "cms-test") do |t|
      t.name = "CMS Test"
      t.active = true
    end
    @page = Website::Page.create!(
      public_id: "page_cms_#{SecureRandom.hex(4)}",
      title: "About CMS",
      slug: "about-cms-#{SecureRandom.hex(3)}",
      page_type: "custom",
      status: "published",
      published_at: Time.current,
      theme: @theme
    )
    Website::Block.create!(
      page: @page,
      block_type: "rich_text",
      position: 0,
      settings: { html: "<p>CMS content</p>" },
      visible: true
    )
    @article = Website::Article.create!(
      public_id: "art_cms_#{SecureRandom.hex(4)}",
      title: "CMS Article",
      slug: "cms-article-#{SecureRandom.hex(3)}",
      article_type: "news",
      status: "published",
      published_at: Time.current,
      summary: "Summary",
      body: "**Hello** world"
    )
  end

  test "public page renders by slug" do
    get "/#{@page.slug}"
    assert_response :success
    assert_includes response.body, "About CMS"
  end

  test "public blog article renders" do
    get "/blog/#{@article.slug}"
    assert_response :success
    assert_includes response.body, "CMS Article"
  end

  test "cms home page renders at root" do
    home = Website::Page.find_by(page_type: "home") || Website::Page.new
    home.assign_attributes(
      public_id: home.public_id.presence || "page_home_#{SecureRandom.hex(4)}",
      title: "CMS Home",
      slug: home.slug.presence || "home-cms-#{SecureRandom.hex(2)}",
      page_type: "home",
      status: "published",
      published_at: Time.current,
      theme: @theme
    )
    home.save!
    Website::Block.find_or_create_by!(page: home, block_type: "hero", position: 0) do |b|
      b.settings = { headline: "Welcome CMS" }
      b.visible = true
    end
    home.blocks.where.not(block_type: "hero").destroy_all
    home.blocks.find_by(block_type: "hero")&.update!(settings: { headline: "Welcome CMS" }, visible: true)

    get root_path
    assert_response :success
    assert_includes response.body, "Welcome CMS"
  end

  test "home slug redirects to root when cms home active" do
    home = Website::Page.find_by(slug: "home") || Website::Page.new
    home.assign_attributes(
      public_id: home.public_id.presence || "page_home2_#{SecureRandom.hex(4)}",
      title: "CMS Home",
      slug: "home",
      page_type: "home",
      status: "published",
      published_at: Time.current,
      theme: @theme
    )
    home.save!

    get "/home"
    assert_redirected_to root_path
  end
end

class WebsiteCmsBugfixTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create_user
    grant_permission(@admin, "admin.access")
    grant_admin_module(@admin, "website")
    %w[
      website.pages.read website.pages.edit website.pages.publish
      website.articles.read website.articles.edit website.articles.publish
    ].each { |key| grant_permission(@admin, key) }
    sign_in_as(@admin)
  end

  test "page update persists nested translation seo" do
    page = Website::Page.create!(
      public_id: "page_i18n_#{SecureRandom.hex(4)}",
      title: "I18n Page",
      slug: "i18n-page-#{SecureRandom.hex(3)}",
      page_type: "custom",
      status: "draft",
      author: @admin
    )

    patch admin_website_page_path(page), params: {
      page: {
        title: page.title,
        slug: page.slug,
        page_type: "custom",
        seo: { title: "", description: "", og_image: "" },
        translations: {
          "en" => { "title" => "English title", "seo" => { "title" => "EN SEO", "description" => "EN desc" } }
        }
      }
    }

    assert_redirected_to admin_website_page_path(page)
    translation = page.reload.translations.dig("en", "seo")
    assert_equal "EN SEO", translation["title"]
    assert_equal "EN desc", translation["description"]
  end

  test "schedule rejects blank publish_at" do
    page = Website::Page.create!(
      public_id: "page_sched_#{SecureRandom.hex(4)}",
      title: "Schedule Page",
      slug: "schedule-page-#{SecureRandom.hex(3)}",
      page_type: "custom",
      status: "draft",
      author: @admin
    )

    post schedule_admin_website_page_path(page), params: { publish_at: "" }
    assert_redirected_to admin_website_page_path(page)
    assert_equal "draft", page.reload.status
  end

  test "admin preview renders draft page" do
    page = Website::Page.create!(
      public_id: "page_prev_#{SecureRandom.hex(4)}",
      title: "Draft Preview",
      slug: "draft-preview-#{SecureRandom.hex(3)}",
      page_type: "custom",
      status: "draft",
      author: @admin
    )
    Website::Block.create!(page: page, block_type: "rich_text", position: 0, settings: { html: "<p>Draft only</p>" }, visible: true)

    get preview_admin_website_page_path(page)
    assert_response :success
    assert_includes response.body, "Draft only"
  end

  test "article slug is globally unique" do
    Website::Article.create!(
      public_id: "art_a_#{SecureRandom.hex(4)}",
      title: "News",
      slug: "shared-slug-#{SecureRandom.hex(3)}",
      article_type: "news",
      status: "draft"
    )

    article = Website::Article.new(
      public_id: "art_b_#{SecureRandom.hex(4)}",
      title: "Blog",
      slug: Website::Article.order(:id).last.slug,
      article_type: "blog",
      status: "draft"
    )

    assert_not article.valid?
    assert article.errors[:slug].present?
  end

  test "hero cta url is sanitized on output" do
    page = Website::Page.create!(
      public_id: "page_xss_#{SecureRandom.hex(4)}",
      title: "XSS",
      slug: "xss-page-#{SecureRandom.hex(3)}",
      page_type: "custom",
      status: "published",
      published_at: Time.current
    )
    Website::Block.create!(
      page: page,
      block_type: "hero",
      position: 0,
      settings: { headline: "Hi", cta_text: "Click", cta_url: "javascript:alert(1)" },
      visible: true
    )

    result = Website::SerializePageBlocks.call(page: page)
    assert_nil result.value.first[:settings]["cta_url"]
  end
end

class Website::ArticlePublisherTest < ActiveSupport::TestCase
  test "publishes article immediately" do
    article = Website::Article.create!(
      public_id: "art_pub_#{SecureRandom.hex(4)}",
      title: "Draft",
      slug: "draft-#{SecureRandom.hex(3)}",
      article_type: "news",
      status: "draft"
    )
    result = Website::ArticlePublisher.call(article: article, actor: create_user)
    assert result.success?
    assert_equal "published", article.reload.status
  end
end

class Website::GenerateSitemapJobTest < ActiveSupport::TestCase
  test "writes blog urls" do
    article = Website::Article.create!(
      public_id: "art_site_#{SecureRandom.hex(4)}",
      title: "Sitemap",
      slug: "sitemap-test",
      article_type: "news",
      status: "published",
      published_at: Time.current
    )
    Website::GenerateSitemapJob.perform_now
    xml = File.read(Rails.root.join("public/sitemap.xml"))
    assert_includes xml, "/blog/#{article.slug}"
    assert_includes xml, "/blog</loc>"
  end
end
