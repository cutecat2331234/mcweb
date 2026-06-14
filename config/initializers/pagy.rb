# frozen_string_literal: true

require "pagy/extras/overflow"
require "pagy/extras/array"

Pagy::DEFAULT[:limit] = 20
Pagy::DEFAULT[:overflow] = :last_page
