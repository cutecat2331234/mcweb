# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class ConversationsApiTest < ActionDispatch::IntegrationTest
      setup do
        @owner = create_user(username: "apiconvowner")
        @other = create_user(username: "apiconvother")
        enable_forum_pm!(@owner)

        @conversation = Community::Conversation.create!(creator: @other, last_message_at: Time.current)
        @conversation.participants.create!(user: @other)
        @conversation.participants.create!(user: @owner)
        @conversation.messages.create!(user: @other, body: "Hello there")

        _rec, @token = Administration::ApiKey.generate!(name: "conv", scopes: %w[read write], user: @owner)
      end

      def h(token = @token)
        { "Authorization" => "Bearer #{token}" }
      end

      test "lists the bound user's conversations" do
        get "/api/v1/conversations", headers: h
        assert_response :success
        body = JSON.parse(response.body)
        assert(body["data"].any? { |c| c["id"] == @conversation.id })
        assert_equal 1, body["data"].find { |c| c["id"] == @conversation.id }["unread_count"]
      end

      test "shows a conversation with messages and can mark read" do
        get "/api/v1/conversations/#{@conversation.id}", params: { mark_read: "true" }, headers: h
        assert_response :success
        body = JSON.parse(response.body)["data"]
        assert(body["messages"].any? { |m| m["body"] == "Hello there" })
        assert_equal 0, @conversation.unread_count_for(@owner)
      end

      test "can reply with a write key" do
        assert_difference -> { @conversation.messages.count }, 1 do
          post "/api/v1/conversations/#{@conversation.id}/reply", params: { body: "A reply via API" }, headers: h
        end
        assert_response :created
        assert_equal "A reply via API", JSON.parse(response.body)["data"]["body"]
      end

      test "read marks the conversation read" do
        post "/api/v1/conversations/#{@conversation.id}/read", headers: h
        assert_response :success
        assert_equal 0, @conversation.unread_count_for(@owner)
      end

      test "a non-participant cannot access the conversation" do
        stranger = create_user(username: "apiconvstranger")
        _rec, stoken = Administration::ApiKey.generate!(name: "stranger", scopes: %w[read write], user: stranger)
        get "/api/v1/conversations/#{@conversation.id}", headers: h(stoken)
        assert_response :not_found
      end

      test "guest key cannot access conversations" do
        _rec, gtoken = Administration::ApiKey.generate!(name: "guest", scopes: %w[read])
        get "/api/v1/conversations", headers: h(gtoken)
        assert_response :forbidden
        assert_equal "no_bound_user", JSON.parse(response.body)["error"]
      end
    end
  end
end
