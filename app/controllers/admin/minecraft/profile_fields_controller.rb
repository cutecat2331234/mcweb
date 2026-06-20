# frozen_string_literal: true

module Admin
  module Minecraft
    class ProfileFieldsController < BaseController
      before_action -> { require_permission("minecraft.servers.manage") }
      before_action :set_definition, only: %i[edit update destroy]

      def index
        definitions = ::Minecraft::ProfileFieldDefinition.ordered

        render inertia: "Admin/Generic/Index", props: {
          title: t("mcweb.admin.minecraft.profile_fields"),
          columns: [
            admin_column(:key, t("mcweb.admin.minecraft.col_key"), link: true),
            admin_column(:label, t("mcweb.admin.minecraft.col_label")),
            admin_column(:field_type, t("mcweb.admin.minecraft.col_type")),
            admin_column(:visibility, t("mcweb.admin.minecraft.col_visibility")),
            admin_column(:source, t("mcweb.admin.minecraft.col_source"))
          ],
          rows: definitions.map do |definition|
            admin_row(
              key: definition.key,
              label: definition.label,
              field_type: definition.field_type,
              visibility: definition.visibility,
              source: definition.source,
              url: edit_admin_minecraft_profile_field_path(definition)
            )
          end,
          actions: [ { label: t("mcweb.admin.minecraft.new_field"), href: new_admin_minecraft_profile_field_path } ]
        }
      end

      def new
        render inertia: "Admin/Minecraft/ProfileFields/Form", props: form_props(::Minecraft::ProfileFieldDefinition.new(active: true, field_type: "text", visibility: "public"))
      end

      def edit
        render inertia: "Admin/Minecraft/ProfileFields/Form", props: form_props(@definition)
      end

      def create
        definition = ::Minecraft::ProfileFieldDefinition.new(definition_params)
        if definition.save
          redirect_to admin_minecraft_profile_fields_path, notice: t("mcweb.flash.field_created")
        else
          render inertia: "Admin/Minecraft/ProfileFields/Form", props: form_props(definition), status: :unprocessable_entity
        end
      end

      def update
        if @definition.update(definition_params)
          redirect_to admin_minecraft_profile_fields_path, notice: t("mcweb.flash.field_updated")
        else
          render inertia: "Admin/Minecraft/ProfileFields/Form", props: form_props(@definition), status: :unprocessable_entity
        end
      end

      def destroy
        @definition.destroy!
        redirect_to admin_minecraft_profile_fields_path, notice: t("mcweb.flash.field_deleted")
      end

      private

      def set_definition
        @definition = ::Minecraft::ProfileFieldDefinition.find(params[:id])
      end

      def definition_params
        params.expect(profile_field: %i[key label field_type icon sort_order visibility source group_name active])[:profile_field]
      end

      def form_props(definition)
        {
          title: definition.persisted? ? t("mcweb.admin.minecraft.edit_field") : t("mcweb.admin.minecraft.new_field"),
          profileField: {
            key: definition.key.to_s,
            label: definition.label.to_s,
            field_type: definition.field_type.to_s,
            icon: definition.icon.to_s,
            sort_order: definition.sort_order || 0,
            visibility: definition.visibility.to_s,
            source: definition.source.to_s,
            group_name: definition.group_name.to_s,
            active: definition.active.nil? ? true : definition.active
          },
          submitUrl: definition.persisted? ? admin_minecraft_profile_field_path(definition) : admin_minecraft_profile_fields_path,
          method: definition.persisted? ? "patch" : "post",
          backUrl: admin_minecraft_profile_fields_path
        }
      end
    end
  end
end
