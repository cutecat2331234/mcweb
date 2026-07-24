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

      test "root index describes the API and the authenticated key" do
        get "/api/v1", headers: auth_headers
        assert_response :success
        body = JSON.parse(response.body)
        assert_equal "v1", body["version"]
        assert_equal "test key", body["authenticated_as"]["key"]
        assert_includes body["resources"], "conversations"
        assert_includes body["events"], "forum.post.created"
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

      test "write key with acting user can create a topic" do
        writer = create_user(username: "apiwriter")
        _rec, wtoken = Administration::ApiKey.generate!(name: "writer", scopes: %w[read write], user: writer)

        assert_difference -> { Community::Topic.count }, 1 do
          post "/api/v1/topics", params: {
            section_id: "api-sec", title: "API created topic", body: "Body created via API"
          }, headers: auth_headers(wtoken)
        end
        assert_response :created
        assert JSON.parse(response.body)["data"]["id"].present?
      end

      test "write key with acting user can create a reply" do
        replier = create_user(username: "apireplier")
        _rec, wtoken = Administration::ApiKey.generate!(name: "replier", scopes: %w[read write], user: replier)

        assert_difference -> { Community::Post.count }, 1 do
          post "/api/v1/posts", params: {
            topic_id: @topic.public_id, body: "A reply created via API"
          }, headers: auth_headers(wtoken)
        end
        assert_response :created
        assert_equal "A reply created via API", JSON.parse(response.body)["data"]["body"]
      end

      test "read-only key cannot create a topic" do
        post "/api/v1/topics", params: { section_id: "api-sec", title: "X", body: "Body here" },
             headers: auth_headers
        assert_response :forbidden
        assert_equal "insufficient_scope", JSON.parse(response.body)["error"]
      end

      test "write key without an acting user cannot create a topic" do
        _rec, wtoken = Administration::ApiKey.generate!(name: "userless-writer", scopes: %w[read write])
        post "/api/v1/topics", params: { section_id: "api-sec", title: "X", body: "Body here" },
             headers: auth_headers(wtoken)
        assert_response :forbidden
        assert_equal "write_requires_user", JSON.parse(response.body)["error"]
      end

      test "bookmark toggle, watch level, and bookmarks list" do
        member = create_user(username: "apibookmarker")
        _rec, wtoken = Administration::ApiKey.generate!(name: "bk", scopes: %w[read write], user: member)

        post "/api/v1/topics/#{@topic.public_id}/bookmark", headers: auth_headers(wtoken)
        assert_response :success
        assert_equal true, JSON.parse(response.body)["data"]["bookmarked"]

        post "/api/v1/topics/#{@topic.public_id}/subscription", params: { level: "watching" }, headers: auth_headers(wtoken)
        assert_response :success
        assert_equal "watching", JSON.parse(response.body)["data"]["notification_level"]

        get "/api/v1/bookmarks", headers: auth_headers(wtoken)
        assert_response :success
        topic_ids = JSON.parse(response.body)["data"].map { |b| b["topic"]["id"] }
        assert_includes topic_ids, @topic.public_id
      end

      test "bookmarks hide topics after the bound user loses section visibility" do
        member = create_user(username: "apiprivatebookmarker")
        grant_permission(member, "forum.private.view")
        private_section = Community::Section.create!(
          category: @category,
          slug: "api-private-bookmarks",
          name: "Private bookmarks",
          position: 2,
          permissions: { "view" => [ "forum.private.view" ] }
        )
        private_topic = Community::Topic.create!(
          public_id: "topic_#{SecureRandom.alphanumeric(16)}",
          section: private_section,
          user: @author,
          title: "Private bookmark",
          status: "published",
          last_posted_at: Time.current,
          last_post_user: @author,
          replies_count: 0
        )
        Community::Bookmark.create!(user: member, topic: private_topic)
        _record, token = Administration::ApiKey.generate!(name: "private-bookmarks", scopes: %w[read], user: member)

        get "/api/v1/bookmarks", headers: auth_headers(token)
        assert_includes JSON.parse(response.body)["data"].map { |b| b["topic"]["id"] }, private_topic.public_id

        member.roles.clear
        get "/api/v1/bookmarks", headers: auth_headers(token)
        assert_not_includes JSON.parse(response.body)["data"].map { |b| b["topic"]["id"] }, private_topic.public_id
      end

      test "bookmarks require a bound user" do
        get "/api/v1/bookmarks", headers: auth_headers
        assert_response :forbidden
      end

      test "topic author can mark solved and unsolve via API" do
        replier = create_user(username: "apisolvereplier")
        reply = Community::Post.create!(topic: @topic, user: replier, floor_number: 2, body: "The answer", status: "published")
        _rec, wtoken = Administration::ApiKey.generate!(name: "sv", scopes: %w[read write], user: @author)

        post "/api/v1/topics/#{@topic.public_id}/solve", params: { post_id: reply.id }, headers: auth_headers(wtoken)
        assert_response :success
        assert_equal reply.id, @topic.reload.solved_post_id

        post "/api/v1/topics/#{@topic.public_id}/unsolve", headers: auth_headers(wtoken)
        assert_response :success
        assert_nil @topic.reload.solved_post_id
      end

      test "subscribe to a tag" do
        Community::Tag.create!(name: "Announcements")
        member = create_user(username: "apitagfollower")
        _rec, wtoken = Administration::ApiKey.generate!(name: "tg", scopes: %w[read write], user: member)

        post "/api/v1/tags/announcements/subscription", params: { level: "watching" }, headers: auth_headers(wtoken)
        assert_response :success
        assert_equal "watching", JSON.parse(response.body)["data"]["notification_level"]
        tag = Community::Tag.find_by(slug: "announcements")
        assert Community::Subscription.exists?(user: member, subscribable: tag)
      end

      test "react to a post and read reaction counts" do
        reactor = create_user(username: "apireactor")
        _rec, wtoken = Administration::ApiKey.generate!(name: "rx", scopes: %w[read write], user: reactor)

        post "/api/v1/posts/#{@post.id}/react", params: { emoji: "👍" }, headers: auth_headers(wtoken)
        assert_response :success
        assert_equal true, JSON.parse(response.body)["data"]["added"]

        get "/api/v1/posts/#{@post.id}/reactions", headers: auth_headers
        assert_response :success
        counts = JSON.parse(response.body)["data"]["counts"]
        assert_equal 1, counts["👍"]
      end

      test "follow toggles following a user" do
        follower = create_user(username: "apifollower")
        target = create_user(username: "apifollowed")
        _rec, wtoken = Administration::ApiKey.generate!(name: "fl", scopes: %w[read write], user: follower)

        post "/api/v1/users/#{target.public_id}/follow", headers: auth_headers(wtoken)
        assert_response :success
        assert_equal true, JSON.parse(response.body)["data"]["following"]
        assert Community::UserFollow.exists?(follower: follower, followed: target)

        post "/api/v1/users/#{target.public_id}/follow", headers: auth_headers(wtoken)
        assert_equal false, JSON.parse(response.body)["data"]["following"]
      end

      test "profile posts list and create" do
        wall_owner = create_user(username: "apiwallowner")
        author = create_user(username: "apiwallauthor")
        grant_permission(author, "forum.topics.lock") # staff bypass for profile-wall trust gate
        _rec, wtoken = Administration::ApiKey.generate!(name: "pp", scopes: %w[read write], user: author)

        assert_difference -> { Community::ProfilePost.count }, 1 do
          post "/api/v1/users/#{wall_owner.public_id}/profile-posts", params: { body: "Nice profile!" }, headers: auth_headers(wtoken)
        end
        assert_response :created

        get "/api/v1/users/#{wall_owner.public_id}/profile-posts", headers: auth_headers
        assert_response :success
        bodies = JSON.parse(response.body)["data"].map { |p| p["body"] }
        assert_includes bodies, "Nice profile!"
      end

      test "GET /users lists members and supports q search" do
        create_user(username: "zzz_uniquemember")
        get "/api/v1/users", params: { q: "zzz_uniquemember" }, headers: auth_headers
        assert_response :success
        body = JSON.parse(response.body)
        usernames = body["data"].map { |u| u["username"] }
        assert_includes usernames, "zzz_uniquemember"
        assert body["data"].none? { |u| u.key?("email") }, "must not leak email in member listing"
      end

      test "GET /me returns the bound user with email" do
        me = create_user(username: "apime")
        _rec, mtoken = Administration::ApiKey.generate!(name: "me-key", scopes: %w[read], user: me)
        get "/api/v1/me", headers: auth_headers(mtoken)
        assert_response :success
        body = JSON.parse(response.body)["data"]
        assert_equal "apime", body["username"]
        assert_equal me.email, body["email"]
      end

      test "GET /me without a bound user is forbidden" do
        get "/api/v1/me", headers: auth_headers
        assert_response :forbidden
        assert_equal "no_bound_user", JSON.parse(response.body)["error"]
      end

      test "GET /tags lists non-staff canonical tags" do
        Community::Tag.create!(name: "Guides")
        Community::Tag.create!(name: "Secret").update!(staff_only: true)
        get "/api/v1/tags", headers: auth_headers
        assert_response :success
        names = JSON.parse(response.body)["data"].map { |t| t["name"] }
        assert_includes names, "Guides"
        assert_not_includes names, "Secret"
      end

      test "topic search filters by title" do
        Community::Topic.create!(
          public_id: "topic_#{SecureRandom.alphanumeric(16)}", section: @section, user: @author,
          title: "Completely unrelated subject", status: "published",
          last_posted_at: Time.current, last_post_user: @author, replies_count: 0
        )
        get "/api/v1/topics", params: { q: "Public" }, headers: auth_headers
        assert_response :success
        titles = JSON.parse(response.body)["data"].map { |t| t["title"] }
        assert_includes titles, "Public API topic"
        assert_not_includes titles, "Completely unrelated subject"
      end

      test "notifications API lists, filters unread, and marks read" do
        owner = create_user(username: "apinotify")
        _rec, ntoken = Administration::ApiKey.generate!(name: "notif-key", scopes: %w[read write], user: owner)
        n1 = Notification.notify!(user: owner, notification_type: "forum.reaction", title: "Reacted")
        Notification.notify!(user: owner, notification_type: "forum.mention", title: "Mentioned")

        get "/api/v1/notifications", headers: auth_headers(ntoken)
        assert_response :success
        body = JSON.parse(response.body)
        assert_equal 2, body["data"].size
        assert_equal 2, body["meta"]["unread_count"]

        post "/api/v1/notifications/#{n1.id}/read", headers: auth_headers(ntoken)
        assert_response :success
        assert n1.reload.read?

        get "/api/v1/notifications", params: { unread: "true" }, headers: auth_headers(ntoken)
        assert_equal 1, JSON.parse(response.body)["data"].size

        post "/api/v1/notifications/read_all", headers: auth_headers(ntoken)
        assert_response :success
        assert_equal 0, owner.notifications.unread.count
      end

      test "notifications API requires a bound user" do
        get "/api/v1/notifications", headers: auth_headers
        assert_response :forbidden
        assert_equal "no_bound_user", JSON.parse(response.body)["error"]
      end

      test "cannot read another user's notification" do
        owner = create_user(username: "apinotifyowner")
        other = create_user(username: "apinotifyother")
        _rec, ntoken = Administration::ApiKey.generate!(name: "notif-key2", scopes: %w[read write], user: other)
        n = Notification.notify!(user: owner, notification_type: "forum.reaction", title: "Reacted")

        post "/api/v1/notifications/#{n.id}/read", headers: auth_headers(ntoken)
        assert_response :not_found
      end

      test "read-only key cannot mutate notification read state" do
        owner = create_user(username: "apinotifyreadonly")
        _record, token = Administration::ApiKey.generate!(name: "notif-read-only", scopes: %w[read], user: owner)
        notification = Notification.notify!(user: owner, notification_type: "forum.reaction", title: "Reacted")

        post "/api/v1/notifications/#{notification.id}/read", headers: auth_headers(token)
        assert_response :forbidden
        assert_not notification.reload.read?

        post "/api/v1/notifications/read_all", headers: auth_headers(token)
        assert_response :forbidden
        assert_equal 1, owner.notifications.unread.count
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
