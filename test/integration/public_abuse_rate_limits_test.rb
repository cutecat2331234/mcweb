# frozen_string_literal: true

require "test_helper"

class PublicAbuseRateLimitsTest < ActionDispatch::IntegrationTest
  test "login returns 429 and Retry-After after the configured account limit" do
    configure(:login, account_limit: 1, ip_limit: 100)
    params = { session: { email: "missing@example.com", password: "incorrect-password" } }

    post identity_session_path, params: params
    assert_response :unprocessable_entity

    post identity_session_path, params: params
    assert_response :too_many_requests
    assert_retry_after(max: 15.minutes)
  end

  test "registration returns 429 and Retry-After after the configured account limit" do
    configure(:registration, account_limit: 1, ip_limit: 100)
    params = {
      registration: {
        email: "limited-registration@example.com",
        username: "limited-registration",
        password: "short"
      }
    }

    post identity_registrations_path, params: params
    assert_response :unprocessable_entity

    post identity_registrations_path, params: params
    assert_response :too_many_requests
    assert_retry_after(max: 24.hours)
  end

  test "search suggestions return 429 and Retry-After for a limited IP" do
    configure(:search_suggest, account_limit: 0, ip_limit: 1)

    get forum_search_suggest_path, params: { q: "abuse" }, as: :json
    assert_response :success

    get forum_search_suggest_path, params: { q: "abuse" }, as: :json
    assert_response :too_many_requests
    assert_equal "rate_limited", JSON.parse(response.body)["error"]
    assert_retry_after(max: 1.minute)
  end

  test "preview returns 429 and Retry-After after one allowed request" do
    user = create_user
    sign_in_as(user)
    configure(:preview, account_limit: 1, ip_limit: 100)

    post forum_preview_path, params: { body: "Preview body" }
    assert_response :success

    post forum_preview_path, params: { body: "Preview body" }
    assert_response :too_many_requests
    assert_equal "rate_limited", JSON.parse(response.body)["error"]
    assert_retry_after(max: 1.minute)
  end

  test "attachment upload returns a unified 429 response with Retry-After" do
    user = create_user(forum_trust_level_override: 1)
    sign_in_as(user)
    configure(:upload, account_limit: 1, ip_limit: 100)

    post forum_attachments_path
    assert_response :unprocessable_entity

    post forum_attachments_path
    assert_response :too_many_requests
    assert_equal "rate_limited", JSON.parse(response.body)["error"]
    assert_retry_after(max: 1.hour)
  end

  test "private conversation creation is limited before another message is written" do
    sender = create_user
    recipient = create_user
    enable_forum_pm!(sender)
    sign_in_as(sender)
    configure(:private_message, account_limit: 1, ip_limit: 100)

    params = {
      conversation: {
        recipient: recipient.username,
        body: "First private message"
      }
    }

    post forum_conversations_path, params: params
    assert_response :redirect
    conversation = Community::Conversation.for_user(sender).order(:created_at).last
    assert_equal 1, conversation.messages.count

    assert_no_difference -> { conversation.messages.count } do
      post forum_conversations_path, params: params
    end
    assert_response :too_many_requests
    assert_retry_after(max: 1.minute)
  end

  test "public API rate limit uses the unified 429 service response" do
    SiteSetting.set("api.rate_limit_per_minute", "1")
    _record, token = Administration::ApiKey.generate!(name: "limited-api", scopes: %w[read])
    headers = { "Authorization" => "Bearer #{token}" }

    get "/api/v1", headers: headers
    assert_response :success

    get "/api/v1", headers: headers
    assert_response :too_many_requests
    assert_equal "rate_limited", JSON.parse(response.body)["error"]
    assert_retry_after(max: 1.minute)
  end

  private

  def configure(action, account_limit:, ip_limit:)
    SiteSetting.set("security.rate_limits.#{action}.account_limit", account_limit.to_s)
    SiteSetting.set("security.rate_limits.#{action}.ip_limit", ip_limit.to_s)
  end

  def assert_retry_after(max:)
    value = response.headers["Retry-After"].to_i
    assert_operator value, :>, 0
    assert_operator value, :<=, max.to_i
  end
end
