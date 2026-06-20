# frozen_string_literal: true

require "test_helper"

class Community::CouponOneboxTest < ActiveSupport::TestCase
  setup do
    @coupon = Commerce::Coupon.create!(
      code: "R33SAVE",
      discount_type: "percentage",
      discount_value: 15,
      active: true,
      min_amount_cents: 0
    )
  end

  test "fetch coupon onebox" do
    result = Community::FetchCouponOnebox.call(url: "/app/store/coupons/#{@coupon.code}")
    assert result.success?
    assert_nil result.value
  end

  test "format post body keeps coupon links as plain links" do
    result = Community::FormatPostBody.call(body: "/app/store/coupons/#{@coupon.code}")
    assert result.success?
    refute_includes result.value, "coupon-onebox"
    assert_includes result.value, @coupon.code
  end
end

class Community::SimilarTopicsTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r33-sim") { |c| c.name = "R33 Sim" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r33-sim-sec") do |s|
      s.name = "Sim Sec"
      s.position = 0
    end
    @topic = Community::CreateTopic.call(user: @user, section: @section, title: "Main", body: "OP").value
    @other = Community::Topic.create!(
      section: @section,
      user: @user,
      title: "Same section",
      status: :published,
      last_posted_at: Time.current,
      last_post_user: @user,
      replies_count: 0
    )
    Community::Post.create!(topic: @other, user: @user, floor_number: 1, body: "OP2", status: "published")
  end

  test "similar topics includes same section fallback" do
    similar = @topic.similar_topics(limit: 5)
    assert_includes similar.map(&:id), @other.id
  end
end

class Commerce::NotifyNewProductQuestionTest < ActiveSupport::TestCase
  setup do
    @asker = create_user(username: "asker_r33")
    @staff = create_user(username: "staff_r33")
    grant_permission(@staff, "store.questions.answer")
    @product = Commerce::Product.create!(
      public_id: "prod_#{SecureRandom.alphanumeric(16)}",
      name: "Notify Product",
      slug: "notify-r33-#{SecureRandom.hex(4)}",
      price_cents: 100,
      currency: "CNY",
      status: "active",
      product_type: "digital"
    )
    @question = Commerce::CreateProductQuestion.call(user: @asker, product: @product, body: "Need help?").value
  end

  test "notifies staff on new question" do
    assert Notification.exists?(user: @staff, notification_type: "commerce.new_product_question")
  end
end

class Community::WikiEditsGuestTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r33-wiki") { |c| c.name = "R33 Wiki" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r33-wiki-sec") do |s|
      s.name = "Wiki Sec"
      s.position = 0
    end
    @topic = Community::CreateTopic.call(user: @user, section: section, title: "Wiki topic", body: "OP").value
    @topic.update!(wiki: true)
    @post = @topic.posts.first
    Community::EditPost.call(user: @user, post: @post, body: "Updated wiki content here")
  end

  test "guest can view wiki edit history" do
    get edits_forum_post_path(@post)
    assert_response :success
  end
end

class Community::NotifyFollowedIgnoreTest < ActiveSupport::TestCase
  setup do
    @author = create_user(username: "author_r33f")
    @follower = create_user(username: "follower_r33f")
    Community::UserFollow.create!(follower: @follower, followed: @author)
    Community::ToggleUserIgnore.call(ignorer: @follower, ignored_username: @author.username)
    category = Community::Category.find_or_create_by!(slug: "r33-follow") { |c| c.name = "R33 Follow" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r33-follow-sec") do |s|
      s.name = "Follow Sec"
      s.position = 0
    end
    NotificationPreference.set!(@follower, channel: "in_app", notification_type: "forum.followed_topic", enabled: true)
  end

  test "ignored author new topic does not notify follower" do
    assert_no_difference -> { Notification.where(user: @follower, notification_type: "forum.followed_topic").count } do
      topic = Community::CreateTopic.call(user: @author, section: section, title: "New from author", body: "OP").value
      Community::NotifyFollowedUserTopic.call(topic: topic)
    end
  end

  private

  def section
    Community::Section.find_by!(slug: "r33-follow-sec")
  end
end
