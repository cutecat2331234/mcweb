# frozen_string_literal: true

require "test_helper"

class CannedResponsePlaceholderTest < ActiveSupport::TestCase
  setup do
    SiteSetting.set("general.site_name", "MCWeb")
    @author = create_user
    category = Community::Category.create!(name: "C", slug: "c-#{SecureRandom.hex(3)}")
    section = Community::Section.create!(category: category, name: "S", slug: "s-#{SecureRandom.hex(3)}", position: 0)
    @topic = Community::Topic.create!(
      public_id: "t_#{SecureRandom.alphanumeric(10)}",
      section: section, user: @author, title: "Need help", status: "published",
      last_posted_at: Time.current, last_post_user: @author, replies_count: 0
    )
    staff = create_user
    @canned = Community::CannedResponse.create!(
      author: staff, title: "Greeting",
      body: %(Hi {username}, regarding "{topic}" — thanks from {site_name}.)
    )
  end

  test "substitutes username, topic, and site_name against the topic context" do
    rendered = @canned.render_for(topic: @topic)
    assert_equal %(Hi #{@author.username}, regarding "Need help" — thanks from MCWeb.), rendered
  end

  test "returns the raw body when no topic is given" do
    assert_equal @canned.body, @canned.render_for
  end
end
