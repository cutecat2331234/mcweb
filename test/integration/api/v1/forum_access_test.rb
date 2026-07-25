# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class ForumAccessTest < ActionDispatch::IntegrationTest
      setup do
        suffix = SecureRandom.hex(4)
        @category = Community::Category.create!(
          name: "API private category #{suffix}",
          slug: "api-private-category-#{suffix}"
        )
        @section = Community::Section.create!(
          category: @category,
          name: "API permission-only #{suffix}",
          slug: "api-permission-only-#{suffix}",
          position: 0,
          permissions: { "view" => [ "forum.api_private.view" ] }
        )
        @public_section = Community::Section.create!(
          category: @category,
          name: "API public #{suffix}",
          slug: "api-public-#{suffix}",
          position: 1
        )
        @author = create_user
        @topic = Community::Topic.create!(
          public_id: "topic_#{SecureRandom.alphanumeric(16)}",
          section: @section,
          user: @author,
          title: "API permission-only topic #{suffix}",
          status: "published",
          last_posted_at: Time.current,
          last_post_user: @author,
          replies_count: 0
        )
        Community::Post.create!(
          topic: @topic,
          user: @author,
          floor_number: 1,
          body: "API permission-only body #{suffix}",
          status: "published"
        )

        @denied_user = create_user
        _denied_key, @denied_token = Administration::ApiKey.generate!(
          name: "denied-#{suffix}",
          scopes: %w[read],
          user: @denied_user
        )

        @allowed_user = create_user
        grant_permission(@allowed_user, "forum.api_private.view")
        _allowed_key, @allowed_token = Administration::ApiKey.generate!(
          name: "allowed-#{suffix}",
          scopes: %w[read],
          user: @allowed_user
        )
      end

      test "bound user without permission cannot list or directly read restricted content" do
        get "/api/v1/categories", headers: auth_headers(@denied_token)
        assert_response :success
        section_ids = JSON.parse(response.body)["data"].flat_map do |category|
          category["sections"].map { |section| section["id"] }
        end
        assert_not_includes section_ids, @section.slug

        get "/api/v1/topics", params: { section_id: @section.slug }, headers: auth_headers(@denied_token)
        assert_response :not_found

        get "/api/v1/topics/#{@topic.public_id}", headers: auth_headers(@denied_token)
        assert_response :not_found
      end

      test "bound user with permission can list and directly read restricted content" do
        get "/api/v1/categories", headers: auth_headers(@allowed_token)
        assert_response :success
        section_ids = JSON.parse(response.body)["data"].flat_map do |category|
          category["sections"].map { |section| section["id"] }
        end
        assert_includes section_ids, @section.slug

        get "/api/v1/topics", params: { section_id: @section.slug }, headers: auth_headers(@allowed_token)
        assert_response :success
        assert_includes JSON.parse(response.body)["data"].map { |topic| topic["id"] }, @topic.public_id

        get "/api/v1/topics/#{@topic.public_id}", headers: auth_headers(@allowed_token)
        assert_response :success
        assert_equal @topic.public_id, JSON.parse(response.body).dig("data", "id")
      end

      test "public API excludes whispers moderation states and non-listed counts" do
        topic, regular = create_topic_with_post(section: @public_section)
        whisper = create_post(
          topic: topic,
          floor: 2,
          status: "published",
          post_type: "whisper",
          body: "API whisper secret"
        )
        pending = create_post(
          topic: topic,
          floor: 3,
          status: "pending_approval",
          body: "API pending secret"
        )
        hidden = create_post(
          topic: topic,
          floor: 4,
          status: "hidden",
          body: "API hidden secret"
        )
        unlisted, = create_topic_with_post(section: @public_section, unlisted: true)
        archived, archived_post = create_topic_with_post(
          section: @public_section,
          archived_at: Time.current
        )

        get "/api/v1/topics/#{topic.public_id}", headers: auth_headers(@denied_token)
        assert_response :success
        posts = JSON.parse(response.body).dig("data", "posts")
        assert_equal [ regular.id ], posts.map { |post| post["id"] }

        [ whisper, pending, hidden ].each do |post|
          get "/api/v1/posts/#{post.id}", headers: auth_headers(@denied_token)
          assert_response :not_found
        end

        Community::SectionModerator.create!(section: @public_section, user: @allowed_user)
        get "/api/v1/posts/#{whisper.id}", headers: auth_headers(@allowed_token)
        assert_response :not_found

        get "/api/v1/users/#{@author.public_id}", headers: auth_headers(@denied_token)
        assert_response :success
        assert_equal 1, JSON.parse(response.body).dig("data", "forum_posts_count")

        get "/api/v1/users", params: { q: @author.username, sort: "posts" }, headers: auth_headers(@denied_token)
        assert_response :success
        api_author = JSON.parse(response.body)["data"].find { |user| user["id"] == @author.public_id }
        assert_equal 1, api_author["forum_posts_count"]

        get "/api/v1/topics", headers: auth_headers(@denied_token)
        listed_ids = JSON.parse(response.body)["data"].map { |item| item["id"] }
        assert_includes listed_ids, topic.public_id
        assert_not_includes listed_ids, unlisted.public_id
        assert_not_includes listed_ids, archived.public_id

        get "/api/v1/categories", headers: auth_headers(@denied_token)
        public_section = JSON.parse(response.body)["data"]
          .flat_map { |category| category["sections"] }
          .find { |section| section["id"] == @public_section.slug }
        assert_equal 1, public_section["topics_count"]

        get "/api/v1/topics/#{unlisted.public_id}", headers: auth_headers(@denied_token)
        assert_response :success

        get "/api/v1/topics/#{archived.public_id}", headers: auth_headers(@denied_token)
        assert_response :not_found

        get "/api/v1/posts/#{archived_post.id}", headers: auth_headers(@denied_token)
        assert_response :not_found

        _owner_key, owner_token = Administration::ApiKey.generate!(
          name: "owner-#{SecureRandom.hex(4)}",
          scopes: %w[read],
          user: @author
        )
        get "/api/v1/topics/#{archived.public_id}", headers: auth_headers(owner_token)
        assert_response :success

        get "/api/v1/posts/#{archived_post.id}", headers: auth_headers(owner_token)
        assert_response :success
      end

      test "API bookmarks omit a moderator whisper bookmark" do
        topic, = create_topic_with_post(section: @public_section)
        whisper = create_post(
          topic: topic,
          floor: 2,
          status: "published",
          post_type: "whisper",
          body: "API bookmarked whisper"
        )
        Community::SectionModerator.create!(section: @public_section, user: @allowed_user)
        Community::Bookmark.create!(user: @allowed_user, topic: topic, post: whisper)

        get "/api/v1/bookmarks", headers: auth_headers(@allowed_token)

        assert_response :success
        assert_empty JSON.parse(response.body)["data"]
      end

      private

      def create_topic_with_post(section:, unlisted: false, archived_at: nil)
        topic = Community::Topic.create!(
          public_id: "topic_#{SecureRandom.alphanumeric(16)}",
          section: section,
          user: @author,
          title: "API policy topic #{SecureRandom.hex(4)}",
          status: "published",
          unlisted: unlisted,
          archived_at: archived_at,
          last_posted_at: Time.current,
          last_post_user: @author,
          replies_count: 0
        )
        post = create_post(
          topic: topic,
          floor: 1,
          status: "published",
          body: "API public body #{SecureRandom.hex(4)}"
        )
        [ topic, post ]
      end

      def create_post(topic:, floor:, status:, body:, post_type: "regular")
        Community::Post.create!(
          topic: topic,
          user: @author,
          floor_number: floor,
          status: status,
          post_type: post_type,
          body: body
        )
      end

      def auth_headers(token)
        { "Authorization" => "Bearer #{token}" }
      end
    end
  end
end
