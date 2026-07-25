# frozen_string_literal: true

class ApplicationMailbox < ActionMailbox::Base
  routing(/\Areply\+/i => :forum_replies)
end
