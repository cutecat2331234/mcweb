# frozen_string_literal: true

module Admin
  module Forum
    class UserFieldsController < BaseController
      before_action -> { require_permission("forum.topics.lock") }
      before_action :set_definition, only: %i[edit update destroy]

      def index
        definitions = ::Community::UserFieldDefinition.ordered

        render inertia: "Admin/Generic/Index", props: {
          title: forum_t("user_fields.title"),
          columns: [
            admin_column(:key, t("mcweb.admin.minecraft.col_key"), link: true),
            admin_column(:label, t("mcweb.admin.minecraft.col_label")),
            admin_column(:field_type, t("mcweb.admin.minecraft.col_type")),
            admin_column(:visibility, t("mcweb.admin.minecraft.col_visibility")),
            admin_column(:registration, forum_t("user_fields.col_registration"))
          ],
          rows: definitions.map do |definition|
            admin_row(
              key: definition.key,
              label: definition.label,
              field_type: definition.field_type,
              visibility: definition.visibility,
              registration: definition.show_on_registration? ? t("mcweb.labels.yes") : forum_na,
              url: edit_admin_forum_user_field_path(definition)
            )
          end,
          actions: [ { label: forum_t("user_fields.new"), href: new_admin_forum_user_field_path } ]
        }
      end

      def new
        render inertia: "Admin/Forum/UserFields/Form", props: form_props(::Community::UserFieldDefinition.new(active: true, field_type: "text", visibility: "public"))
      end

      def edit
        render inertia: "Admin/Forum/UserFields/Form", props: form_props(@definition)
      end

      def create
        definition = ::Community::UserFieldDefinition.new(definition_params)
        if definition.save
          redirect_to admin_forum_user_fields_path, notice: t("mcweb.flash.field_created")
        else
          render inertia: "Admin/Forum/UserFields/Form", props: form_props(definition), status: :unprocessable_entity
        end
      end

      def update
        if @definition.update(definition_params)
          redirect_to admin_forum_user_fields_path, notice: t("mcweb.flash.field_updated")
        else
          render inertia: "Admin/Forum/UserFields/Form", props: form_props(@definition), status: :unprocessable_entity
        end
      end

      def destroy
        @definition.destroy!
        redirect_to admin_forum_user_fields_path, notice: t("mcweb.flash.field_deleted")
      end

      private

      def set_definition
        @definition = ::Community::UserFieldDefinition.find(params[:id])
      end

      def definition_params
        params.expect(user_field: %i[key label field_type description choices sort_order visibility required show_on_registration show_on_profile editable_by_user active])[:user_field]
      end

      def form_props(definition)
        {
          title: definition.persisted? ? forum_t("user_fields.edit") : forum_t("user_fields.new"),
          userField: {
            key: definition.key.to_s,
            label: definition.label.to_s,
            field_type: definition.field_type.to_s,
            description: definition.description.to_s,
            choices: definition.choices.to_s,
            sort_order: definition.sort_order || 0,
            visibility: definition.visibility.to_s,
            required: definition.required?,
            show_on_registration: definition.show_on_registration?,
            show_on_profile: definition.show_on_profile?,
            editable_by_user: definition.editable_by_user?,
            active: definition.active.nil? ? true : definition.active
          },
          submitUrl: definition.persisted? ? admin_forum_user_field_path(definition) : admin_forum_user_fields_path,
          method: definition.persisted? ? "patch" : "post",
          backUrl: admin_forum_user_fields_path
        }
      end
    end
  end
end
