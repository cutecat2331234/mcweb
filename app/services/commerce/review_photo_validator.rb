# frozen_string_literal: true

module Commerce
  module ReviewPhotoValidator
    ALLOWED_TYPES = %w[image/jpeg image/png image/gif image/webp].freeze
    MAX_BYTES = 2.megabytes
    MAX_PHOTOS = 3

    module_function

    def files(value)
      Array(value).compact.reject { |photo| photo == "" }
    end

    def validate(files, retained_count: 0)
      return :review_photos_too_many if retained_count + files.length > MAX_PHOTOS
      return :review_photo_type_invalid unless files.all? do |photo|
        photo.respond_to?(:content_type) && photo.respond_to?(:size)
      end
      return :review_photo_type_invalid if files.any? { |photo| !ALLOWED_TYPES.include?(photo.content_type) }
      return :review_photo_too_large if files.any? { |photo| photo.size > MAX_BYTES }

      nil
    end
  end
end
