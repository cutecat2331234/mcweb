# frozen_string_literal: true

require "vips"

module Minecraft
  # Renders a Minecraft skin without a browser, WebGL, or an external render
  # service. The small software rasterizer keeps cached public images portable
  # while preserving the block geometry and second skin layers.
  class IsometricSkinBustRenderer
    CANVAS_SIZE = 256
    PROJECTION_SCALE = 10.0
    PROJECTION_ORIGIN = [ CANVAS_SIZE / 2.0, CANVAS_SIZE / 2.0 ].freeze
    CAMERA_TARGET = [ 0.0, 10.0, 0.0 ].freeze
    CAMERA_YAW = -28.0 * Math::PI / 180.0
    CAMERA_PITCH = 17.0 * Math::PI / 180.0
    DEPTH_EPSILON = 1e-6

    HEAD_FRONT = [ 8, 8, 8, 8 ].freeze
    HEAD_OVERLAY_FRONT = [ 40, 8, 8, 8 ].freeze
    TORSO_FRONT = [ 20, 20, 8, 12 ].freeze
    TORSO_OVERLAY_FRONT = [ 20, 36, 8, 12 ].freeze
    RIGHT_ARM_FRONT = [ 44, 20, 4, 12 ].freeze
    RIGHT_ARM_OVERLAY_FRONT = [ 44, 36, 4, 12 ].freeze
    LEFT_ARM_FRONT = [ 36, 52, 4, 12 ].freeze
    LEFT_ARM_OVERLAY_FRONT = [ 52, 52, 4, 12 ].freeze

    HEAD_TEXTURES = {
      top: [ 8, 0, 8, 8 ],
      bottom: [ 16, 0, 8, 8 ],
      right: [ 0, 8, 8, 8 ],
      front: HEAD_FRONT,
      left: [ 16, 8, 8, 8 ],
      back: [ 24, 8, 8, 8 ]
    }.freeze
    HEAD_OVERLAY_TEXTURES = {
      top: [ 40, 0, 8, 8 ],
      bottom: [ 48, 0, 8, 8 ],
      right: [ 32, 8, 8, 8 ],
      front: HEAD_OVERLAY_FRONT,
      left: [ 48, 8, 8, 8 ],
      back: [ 56, 8, 8, 8 ]
    }.freeze
    TORSO_TEXTURES = {
      top: [ 20, 16, 8, 4 ],
      bottom: [ 28, 16, 8, 4 ],
      right: [ 16, 20, 4, 12 ],
      front: TORSO_FRONT,
      left: [ 28, 20, 4, 12 ],
      back: [ 32, 20, 8, 12 ]
    }.freeze
    TORSO_OVERLAY_TEXTURES = {
      top: [ 20, 32, 8, 4 ],
      bottom: [ 28, 32, 8, 4 ],
      right: [ 16, 36, 4, 12 ],
      front: TORSO_OVERLAY_FRONT,
      left: [ 28, 36, 4, 12 ],
      back: [ 32, 36, 8, 12 ]
    }.freeze

    CLASSIC_RIGHT_ARM_TEXTURES = {
      top: [ 44, 16, 4, 4 ],
      bottom: [ 48, 16, 4, 4 ],
      right: [ 40, 20, 4, 12 ],
      front: RIGHT_ARM_FRONT,
      left: [ 48, 20, 4, 12 ],
      back: [ 52, 20, 4, 12 ]
    }.freeze
    CLASSIC_RIGHT_ARM_OVERLAY_TEXTURES = {
      top: [ 44, 32, 4, 4 ],
      bottom: [ 48, 32, 4, 4 ],
      right: [ 40, 36, 4, 12 ],
      front: RIGHT_ARM_OVERLAY_FRONT,
      left: [ 48, 36, 4, 12 ],
      back: [ 52, 36, 4, 12 ]
    }.freeze
    CLASSIC_LEFT_ARM_TEXTURES = {
      top: [ 36, 48, 4, 4 ],
      bottom: [ 40, 48, 4, 4 ],
      right: [ 32, 52, 4, 12 ],
      front: LEFT_ARM_FRONT,
      left: [ 40, 52, 4, 12 ],
      back: [ 44, 52, 4, 12 ]
    }.freeze
    CLASSIC_LEFT_ARM_OVERLAY_TEXTURES = {
      top: [ 52, 48, 4, 4 ],
      bottom: [ 56, 48, 4, 4 ],
      right: [ 48, 52, 4, 12 ],
      front: LEFT_ARM_OVERLAY_FRONT,
      left: [ 56, 52, 4, 12 ],
      back: [ 60, 52, 4, 12 ]
    }.freeze

    SLIM_RIGHT_ARM_TEXTURES = {
      top: [ 44, 16, 3, 4 ],
      bottom: [ 47, 16, 3, 4 ],
      right: [ 40, 20, 4, 12 ],
      front: [ 44, 20, 3, 12 ],
      left: [ 47, 20, 4, 12 ],
      back: [ 51, 20, 3, 12 ]
    }.freeze
    SLIM_RIGHT_ARM_OVERLAY_TEXTURES = {
      top: [ 44, 32, 3, 4 ],
      bottom: [ 47, 32, 3, 4 ],
      right: [ 40, 36, 4, 12 ],
      front: [ 44, 36, 3, 12 ],
      left: [ 47, 36, 4, 12 ],
      back: [ 51, 36, 3, 12 ]
    }.freeze
    SLIM_LEFT_ARM_TEXTURES = {
      top: [ 36, 48, 3, 4 ],
      bottom: [ 39, 48, 3, 4 ],
      right: [ 32, 52, 4, 12 ],
      front: [ 36, 52, 3, 12 ],
      left: [ 39, 52, 4, 12 ],
      back: [ 43, 52, 3, 12 ]
    }.freeze
    SLIM_LEFT_ARM_OVERLAY_TEXTURES = {
      top: [ 52, 48, 3, 4 ],
      bottom: [ 55, 48, 3, 4 ],
      right: [ 48, 52, 4, 12 ],
      front: [ 52, 52, 3, 12 ],
      left: [ 55, 52, 4, 12 ],
      back: [ 59, 52, 3, 12 ]
    }.freeze

    LEGACY_LEFT_ARM_TEXTURES = {
      top: { region: CLASSIC_RIGHT_ARM_TEXTURES.fetch(:top), flip_x: true },
      bottom: { region: CLASSIC_RIGHT_ARM_TEXTURES.fetch(:bottom), flip_x: true },
      right: { region: CLASSIC_RIGHT_ARM_TEXTURES.fetch(:left), flip_x: true },
      front: { region: CLASSIC_RIGHT_ARM_TEXTURES.fetch(:front), flip_x: true },
      left: { region: CLASSIC_RIGHT_ARM_TEXTURES.fetch(:right), flip_x: true },
      back: { region: CLASSIC_RIGHT_ARM_TEXTURES.fetch(:back), flip_x: true }
    }.freeze

    FACE_NORMALS = {
      front: [ 0.0, 0.0, 1.0 ],
      back: [ 0.0, 0.0, -1.0 ],
      right: [ -1.0, 0.0, 0.0 ],
      left: [ 1.0, 0.0, 0.0 ],
      top: [ 0.0, 1.0, 0.0 ],
      bottom: [ 0.0, -1.0, 0.0 ]
    }.freeze
    FACE_SHADES = {
      front: 1.0,
      back: 0.68,
      right: 0.78,
      left: 0.88,
      top: 1.08,
      bottom: 0.64
    }.freeze

    def self.call(image:, model: nil)
      new(image:, model:).render
    end

    def initialize(image:, model: nil)
      @image = normalize_image(image)
      @slim = model.to_s.casecmp?("slim") && modern_skin?
      @atlas_scale = @image.width / 64.0
      @source_width = @image.width
      @source_height = @image.height
      @source_pixels = @image.write_to_memory.unpack("C*")
      @pixels = Array.new(CANVAS_SIZE * CANVAS_SIZE * 4, 0)
      @depth = Array.new(CANVAS_SIZE * CANVAS_SIZE, -Float::INFINITY)
      @camera_forward, @camera_right, @camera_up = camera_vectors
    end

    def render
      render_base_geometry
      render_overlay_geometry

      Vips::Image
        .new_from_memory(@pixels.pack("C*"), CANVAS_SIZE, CANVAS_SIZE, 4, :uchar)
        .copy(interpretation: :srgb)
    end

    private

    def render_base_geometry
      render_cuboid(center: [ 0.0, 16.0, 0.0 ], size: [ 8.0, 8.0, 8.0 ], textures: HEAD_TEXTURES)
      render_cuboid(center: [ 0.0, 6.0, 0.0 ], size: [ 8.0, 12.0, 4.0 ], textures: TORSO_TEXTURES)

      arm_width = @slim ? 3.0 : 4.0
      arm_center = 4.0 + (arm_width / 2.0)
      render_cuboid(
        center: [ -arm_center, 6.0, 0.0 ],
        size: [ arm_width, 12.0, 4.0 ],
        textures: @slim ? SLIM_RIGHT_ARM_TEXTURES : CLASSIC_RIGHT_ARM_TEXTURES
      )
      render_cuboid(
        center: [ arm_center, 6.0, 0.0 ],
        size: [ arm_width, 12.0, 4.0 ],
        textures: left_arm_textures
      )
    end

    def render_overlay_geometry
      render_cuboid(
        center: [ 0.0, 16.0, 0.0 ],
        size: [ 8.0, 8.0, 8.0 ],
        textures: HEAD_OVERLAY_TEXTURES,
        inflate: 0.5
      )
      return unless modern_skin?

      render_cuboid(
        center: [ 0.0, 6.0, 0.0 ],
        size: [ 8.0, 12.0, 4.0 ],
        textures: TORSO_OVERLAY_TEXTURES,
        inflate: 0.25
      )

      arm_width = @slim ? 3.0 : 4.0
      arm_center = 4.0 + (arm_width / 2.0)
      render_cuboid(
        center: [ -arm_center, 6.0, 0.0 ],
        size: [ arm_width, 12.0, 4.0 ],
        textures: @slim ? SLIM_RIGHT_ARM_OVERLAY_TEXTURES : CLASSIC_RIGHT_ARM_OVERLAY_TEXTURES,
        inflate: 0.25
      )
      render_cuboid(
        center: [ arm_center, 6.0, 0.0 ],
        size: [ arm_width, 12.0, 4.0 ],
        textures: @slim ? SLIM_LEFT_ARM_OVERLAY_TEXTURES : CLASSIC_LEFT_ARM_OVERLAY_TEXTURES,
        inflate: 0.25
      )
    end

    def render_cuboid(center:, size:, textures:, inflate: 0.0)
      half_width = (size.fetch(0) / 2.0) + inflate
      half_height = (size.fetch(1) / 2.0) + inflate
      half_depth = (size.fetch(2) / 2.0) + inflate
      x0 = center.fetch(0) - half_width
      x1 = center.fetch(0) + half_width
      y0 = center.fetch(1) - half_height
      y1 = center.fetch(1) + half_height
      z0 = center.fetch(2) - half_depth
      z1 = center.fetch(2) + half_depth

      textures.each do |face, texture|
        next unless visible_face?(face)

        render_face(
          face_vertices(face, x0:, x1:, y0:, y1:, z0:, z1:),
          texture,
          FACE_SHADES.fetch(face)
        )
      end
    end

    def face_vertices(face, x0:, x1:, y0:, y1:, z0:, z1:)
      case face
      when :front
        [ [ x0, y1, z1 ], [ x1, y1, z1 ], [ x1, y0, z1 ], [ x0, y0, z1 ] ]
      when :back
        [ [ x1, y1, z0 ], [ x0, y1, z0 ], [ x0, y0, z0 ], [ x1, y0, z0 ] ]
      when :right
        [ [ x0, y1, z0 ], [ x0, y1, z1 ], [ x0, y0, z1 ], [ x0, y0, z0 ] ]
      when :left
        [ [ x1, y1, z1 ], [ x1, y1, z0 ], [ x1, y0, z0 ], [ x1, y0, z1 ] ]
      when :top
        [ [ x0, y1, z0 ], [ x1, y1, z0 ], [ x1, y1, z1 ], [ x0, y1, z1 ] ]
      when :bottom
        [ [ x0, y0, z1 ], [ x1, y0, z1 ], [ x1, y0, z0 ], [ x0, y0, z0 ] ]
      else
        raise ArgumentError, "unknown cuboid face: #{face.inspect}"
      end
    end

    def render_face(vertices, texture, shade)
      projected = vertices.map { |vertex| project(vertex) }
      render_triangle(projected.values_at(0, 1, 2), [ [ 0.0, 0.0 ], [ 1.0, 0.0 ], [ 1.0, 1.0 ] ], texture, shade)
      render_triangle(projected.values_at(0, 2, 3), [ [ 0.0, 0.0 ], [ 1.0, 1.0 ], [ 0.0, 1.0 ] ], texture, shade)
    end

    def render_triangle(vertices, texture_coordinates, texture, shade)
      min_x = [ vertices.map { |vertex| vertex.fetch(0) }.min.floor, 0 ].max
      max_x = [ vertices.map { |vertex| vertex.fetch(0) }.max.ceil, CANVAS_SIZE - 1 ].min
      min_y = [ vertices.map { |vertex| vertex.fetch(1) }.min.floor, 0 ].max
      max_y = [ vertices.map { |vertex| vertex.fetch(1) }.max.ceil, CANVAS_SIZE - 1 ].min
      denominator = edge(vertices.fetch(0), vertices.fetch(1), vertices.fetch(2).fetch(0), vertices.fetch(2).fetch(1))
      return if denominator.abs <= DEPTH_EPSILON

      (min_y..max_y).each do |y|
        (min_x..max_x).each do |x|
          sample_x = x + 0.5
          sample_y = y + 0.5
          weight_0 = edge(vertices.fetch(1), vertices.fetch(2), sample_x, sample_y) / denominator
          weight_1 = edge(vertices.fetch(2), vertices.fetch(0), sample_x, sample_y) / denominator
          weight_2 = 1.0 - weight_0 - weight_1
          next if weight_0 < -DEPTH_EPSILON || weight_1 < -DEPTH_EPSILON || weight_2 < -DEPTH_EPSILON

          pixel_index = (y * CANVAS_SIZE) + x
          depth = (weight_0 * vertices.fetch(0).fetch(2)) +
            (weight_1 * vertices.fetch(1).fetch(2)) +
            (weight_2 * vertices.fetch(2).fetch(2))
          next if depth <= @depth.fetch(pixel_index) + DEPTH_EPSILON

          texture_x = (weight_0 * texture_coordinates.fetch(0).fetch(0)) +
            (weight_1 * texture_coordinates.fetch(1).fetch(0)) +
            (weight_2 * texture_coordinates.fetch(2).fetch(0))
          texture_y = (weight_0 * texture_coordinates.fetch(0).fetch(1)) +
            (weight_1 * texture_coordinates.fetch(1).fetch(1)) +
            (weight_2 * texture_coordinates.fetch(2).fetch(1))
          rgba = texture_pixel(texture, texture_x, texture_y, shade)
          next if rgba.fetch(3).zero?

          composite_pixel(pixel_index, rgba)
          @depth[pixel_index] = depth
        end
      end
    end

    def texture_pixel(texture, texture_x, texture_y, shade)
      texture_options = texture.is_a?(Hash) ? texture : { region: texture }
      region = texture_options.fetch(:region)
      texture_x = 1.0 - texture_x if texture_options[:flip_x]
      texture_y = 1.0 - texture_y if texture_options[:flip_y]
      texture_x = texture_x.clamp(0.0, 1.0 - Float::EPSILON)
      texture_y = texture_y.clamp(0.0, 1.0 - Float::EPSILON)
      region_x, region_y, region_width, region_height = region
      source_x = ((region_x + (texture_x * region_width)) * @atlas_scale).floor
      source_y = ((region_y + (texture_y * region_height)) * @atlas_scale).floor
      source_x = source_x.clamp(0, @source_width - 1)
      source_y = source_y.clamp(0, @source_height - 1)
      offset = ((source_y * @source_width) + source_x) * 4

      [
        (@source_pixels.fetch(offset) * shade).round.clamp(0, 255),
        (@source_pixels.fetch(offset + 1) * shade).round.clamp(0, 255),
        (@source_pixels.fetch(offset + 2) * shade).round.clamp(0, 255),
        @source_pixels.fetch(offset + 3)
      ]
    end

    def composite_pixel(pixel_index, source)
      offset = pixel_index * 4
      source_alpha = source.fetch(3) / 255.0
      destination_alpha = @pixels.fetch(offset + 3) / 255.0
      result_alpha = source_alpha + (destination_alpha * (1.0 - source_alpha))
      return if result_alpha.zero?

      3.times do |band|
        source_component = source.fetch(band) * source_alpha
        destination_component = @pixels.fetch(offset + band) * destination_alpha * (1.0 - source_alpha)
        @pixels[offset + band] = ((source_component + destination_component) / result_alpha).round.clamp(0, 255)
      end
      @pixels[offset + 3] = (result_alpha * 255).round.clamp(0, 255)
    end

    def project(vertex)
      relative = 3.times.map { |axis| vertex.fetch(axis) - CAMERA_TARGET.fetch(axis) }
      [
        PROJECTION_ORIGIN.fetch(0) + (dot(relative, @camera_right) * PROJECTION_SCALE),
        PROJECTION_ORIGIN.fetch(1) - (dot(relative, @camera_up) * PROJECTION_SCALE),
        dot(relative, @camera_forward)
      ]
    end

    def visible_face?(face)
      dot(FACE_NORMALS.fetch(face), @camera_forward).positive?
    end

    def edge(first, second, x, y)
      ((second.fetch(0) - first.fetch(0)) * (y - first.fetch(1))) -
        ((second.fetch(1) - first.fetch(1)) * (x - first.fetch(0)))
    end

    def camera_vectors
      sin_yaw = Math.sin(CAMERA_YAW)
      cos_yaw = Math.cos(CAMERA_YAW)
      sin_pitch = Math.sin(CAMERA_PITCH)
      cos_pitch = Math.cos(CAMERA_PITCH)

      [
        [ sin_yaw * cos_pitch, sin_pitch, cos_yaw * cos_pitch ],
        [ cos_yaw, 0.0, -sin_yaw ],
        [ -sin_yaw * sin_pitch, cos_pitch, -cos_yaw * sin_pitch ]
      ]
    end

    def dot(first, second)
      first.zip(second).sum { |left, right| left * right }
    end

    def normalize_image(image)
      normalized = image.colourspace(:srgb)
      normalized = normalized.add_alpha unless normalized.has_alpha?
      normalized.cast(:uchar)
    end

    def left_arm_textures
      return LEGACY_LEFT_ARM_TEXTURES unless modern_skin?

      @slim ? SLIM_LEFT_ARM_TEXTURES : CLASSIC_LEFT_ARM_TEXTURES
    end

    def modern_skin?
      @image.height >= @image.width
    end
  end
end
