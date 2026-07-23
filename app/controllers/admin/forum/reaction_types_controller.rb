# frozen_string_literal: true

module Admin
  module Forum
    # XenForo-style reaction manager: custom name / emoji / weighted score / order /
    # enable toggle. When at least one active reaction type exists it becomes the
    # single source of truth for the allowed reactions and their scores.
    class ReactionTypesController < BaseController
      before_action -> { require_permission("forum.sections.manage") }
      before_action :set_reaction_type, only: %i[edit update destroy]

      def index
        reaction_types = ::Community::ReactionType.ordered

        render inertia: "Admin/Generic/Index", props: {
          title: forum_t("reaction_types.title"),
          subtitle: forum_t("reaction_types.description"),
          columns: [
            admin_column(:emoji, forum_t("reaction_types.col_emoji"), link: true),
            admin_column(:name, forum_t("reaction_types.col_name")),
            admin_column(:score, forum_t("reaction_types.col_score")),
            admin_column(:position, forum_t("reaction_types.col_position")),
            admin_column(:active, forum_t("reaction_types.col_active"))
          ],
          rows: reaction_types.map do |reaction_type|
            admin_row(
              emoji: reaction_type.emoji,
              name: reaction_type.name,
              score: reaction_type.score,
              position: reaction_type.position,
              active: forum_yes_no(reaction_type.active),
              url: edit_admin_forum_reaction_type_path(reaction_type)
            )
          end,
          actions: [ { label: forum_t("reaction_types.action_new"), href: new_admin_forum_reaction_type_path } ]
        }
      end

      def new
        render inertia: "Admin/Forum/ReactionTypes/Form", props: form_props(::Community::ReactionType.new)
      end

      def create
        reaction_type = ::Community::ReactionType.new(reaction_type_params)
        if reaction_type.save
          redirect_to admin_forum_reaction_types_path, notice: t("mcweb.flash.reaction_type_created")
        else
          render inertia: "Admin/Forum/ReactionTypes/Form", props: form_props(reaction_type), status: :unprocessable_entity
        end
      end

      def edit
        render inertia: "Admin/Forum/ReactionTypes/Form", props: form_props(@reaction_type, editing: true)
      end

      def update
        if @reaction_type.update(reaction_type_params)
          redirect_to admin_forum_reaction_types_path, notice: t("mcweb.flash.reaction_type_updated")
        else
          render inertia: "Admin/Forum/ReactionTypes/Form", props: form_props(@reaction_type, editing: true), status: :unprocessable_entity
        end
      end

      def destroy
        @reaction_type.destroy!
        redirect_to admin_forum_reaction_types_path, notice: t("mcweb.flash.reaction_type_deleted")
      end

      private

      def set_reaction_type
        @reaction_type = ::Community::ReactionType.find(params[:id])
      end

      def reaction_type_params
        params.require(:reaction_type).permit(:emoji, :name, :score, :position, :active)
      end

      def form_props(reaction_type, editing: false)
        {
          title: editing ? forum_t("reaction_types.form_edit") : forum_t("reaction_types.form_new"),
          reactionType: {
            emoji: reaction_type.emoji || "",
            name: reaction_type.name || "",
            score: reaction_type.score.nil? ? 1 : reaction_type.score,
            position: reaction_type.position || 0,
            active: reaction_type.active.nil? ? true : reaction_type.active
          },
          submitUrl: editing ? admin_forum_reaction_type_path(reaction_type) : admin_forum_reaction_types_path,
          method: editing ? "patch" : "post",
          backUrl: admin_forum_reaction_types_path,
          deleteUrl: editing ? admin_forum_reaction_type_path(reaction_type) : nil
        }
      end
    end
  end
end
