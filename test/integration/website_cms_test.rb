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
