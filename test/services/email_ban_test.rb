# frozen_string_literal: true

require "test_helper"

class EmailBanTest < ActiveSupport::TestCase
  test "exact pattern matches only that email" do
    Administration::EmailBan.create!(pattern: "spammer@bad.com")
    assert Administration::EmailBan.match?("spammer@bad.com")
    assert Administration::EmailBan.match?("SPAMMER@BAD.COM")
    assert_not Administration::EmailBan.match?("someone@bad.com")
  end

  test "wildcard domain pattern matches the whole domain" do
    Administration::EmailBan.create!(pattern: "*@spam.com")
    assert Administration::EmailBan.match?("a@spam.com")
    assert Administration::EmailBan.match?("b@spam.com")
    assert_not Administration::EmailBan.match?("a@ham.com")
  end

  test "expired bans do not match" do
    Administration::EmailBan.create!(pattern: "*@old.com", expires_at: 1.day.ago)
    assert_not Administration::EmailBan.match?("x@old.com")
  end

  test "CheckEmailBan fails for a banned email and succeeds otherwise" do
    Administration::EmailBan.create!(pattern: "*@spam.com")
    assert Administration::CheckEmailBan.call(email: "x@spam.com").failure?
    assert Administration::CheckEmailBan.call(email: "x@good.com").success?
    assert Administration::CheckEmailBan.call(email: "").success?
  end

  test "RegisterUser rejects a banned email" do
    Administration::EmailBan.create!(pattern: "*@spam.com")
    result = Identity::RegisterUser.call(
      email: "newbie@spam.com",
      username: "newbie#{SecureRandom.hex(3)}",
      password: "password123"
    )
    assert result.failure?
    assert_not User.exists?(email: "newbie@spam.com")
  end

  test "RegisterUser allows a non-banned email" do
    Administration::EmailBan.create!(pattern: "*@spam.com")
    result = Identity::RegisterUser.call(
      email: "good#{SecureRandom.hex(3)}@example.com",
      username: "good#{SecureRandom.hex(3)}",
      password: "password123"
    )
    assert result.success?
  end
end
