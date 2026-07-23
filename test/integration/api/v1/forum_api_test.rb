# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class ForumApiTest < ActionDispatch::IntegrationTest
      setup do
        @key_record, @token = Administration::ApiKey.generate!(name: "test key", scopes: %w[read])

        @category = Community::Category.find_or_create_by!(slug: "api-cat") { |c| c.name = "API Cat" }
        @section = Community::Section.find_or_create_by!(category: @category, slug: "api-sec") do |s|
          s.name = "API Section"
          s.position = 0
        end
        @author = create_user(username: "apiauthor")
        @topic = Community::Topic.create!(
          public_id: "topic_#{SecureRandom.alphanumeric(16)}",
          section: @section,
          user: @author,
          title: "Public API topic",
          status: "published",
          last_posted_at: Time.current,
          last_post_user: @author,
          replies_count: 0
        )
        @post = Community::Post.create!(topic: @topic, user: @author, floor_number: 1, body: "Hello API", status: "published")
      end

      def auth_headers(token = @token)
        { "Authorization" => "Bearer #{token}" }
      end

      test "rejects request without an API key" do
        get "/api/v1/categories"
        assert_response :unauthorized
        assert_equal "invalid_api_key", JSON.parse(response.body)["error"]
      end

      test "rejects request with an invalid API key" do
        get "/api/v1/categories", headers: auth_headers("mcw_totally-bogus")
        assert_response :unauthorized
      end

      test "rejects a revoked key" do
        @key_record.revoke!
        get "/api/v1/categories", headers: auth_headers
        assert_response :unauthorized
      end

      test "lists categories with visible sections" do
        get "/api/v1/categories", headers: auth_headers
        assert_response :success
        body = JSON.parse(response.body)
        cat = body["data"].find { |c| c["id"] == "api-cat" }
        assert cat, "expected api-cat in response"
        assert(cat["sections"].any? { |s| s["id"] == "api-sec" })
      end

      test "lists topics in a section" do
        get "/api/v1/topics", params: { section_id: "api-sec" }, headers: auth_headers
        assert_response :success
        body = JSON.parse(response.body)
        assert(body["data"].any? { |t| t["id"] == @topic.public_id })
        assert body["meta"]["count"] >= 1
      end

      test "shows a topic with its posts" do
        get "/api/v1/topics/#{@topic.public_id}", headers: auth_headers
        assert_response :success
        body = JSON.parse(response.body)
        assert_equal @topic.public_id, body["data"]["id"]
        assert(body["data"]["posts"].any? { |p| p["body"] == "Hello API" })
      end

      test "shows a public user profile without leaking email" do
        get "/api/v1/users/#{@author.public_id}", headers: auth_headers
        assert_response :success
        body = JSON.parse(response.body)
        assert_equal @author.username, body["data"]["username"]
        assert_not body["data"].key?("email"), "must not expose email"
      end

      test "does not leak topics from a login-required (restricted) section" do
        restricted = Community::Section.create!(
          category: @category, slug: "api-restricted", name: "Restricted", position: 1, login_required: true
        )
        hidden_topic = Community::Topic.create!(
          public_id: "topic_#{SecureRandom.alphanumeric(16)}",
          section: restricted, user: @author, title: "Secret",
          status: "published", last_posted_at: Time.current, last_post_user: @author, replies_count: 0
        )

        # not listed in categories
        get "/api/v1/categories", headers: auth_headers
        body = JSON.parse(response.body)
        section_ids = body["data"].flat_map { |c| c["sections"].map { |s| s["id"] } }
        assert_not_includes section_ids, "api-restricted"

        # topics of restricted section are not returned
        get "/api/v1/topics", params: { section_id: "api-restricted" }, headers: auth_headers
        assert_response :not_found

        # direct topic show is blocked
        get "/api/v1/topics/#{hidden_topic.public_id}", headers: auth_headers
        assert_response :not_found
      end

      test "read key cannot use a write-only endpoint guard" do
        # simulate a key without read scope
        key = Administration::ApiKey.create!(
          public_id: "apik_#{SecureRandom.alphanumeric(16)}",
          name: "noscope", token_digest: Administration::ApiKey.digest("mcw_noscope-#{SecureRandom.hex(8)}"),
          token_prefix: "mcw_none", scopes: ""
        )
        # craft a token whose digest matches
        plain = "mcw_scopetest-#{SecureRandom.hex(8)}"
        key.update!(token_digest: Administration::ApiKey.digest(plain), scopes: "")

        get "/api/v1/categories", headers: auth_headers(plain)
        assert_response :forbidden
        assert_equal "insufficient_scope", JSON.parse(response.body)["error"]
      end
    end
  end
end
