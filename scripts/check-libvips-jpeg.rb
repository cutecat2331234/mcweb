# frozen_string_literal: true

require "vips"

source = Vips::Image.black(1, 1).new_from_image([ 24, 96, 180 ])
jpeg = source.jpegsave_buffer(Q: 85, interlace: false, strip: true)
decoded = Vips::Image.jpegload_buffer(
  jpeg,
  access: :sequential,
  fail_on: :warning,
  unlimited: false
)
decoded.write_to_memory

unless decoded.width == 1 && decoded.height == 1 && decoded.bands == 3
  abort "libvips JPEG smoke test returned an unexpected image"
end

puts "libvips JPEG decode/re-encode OK"
