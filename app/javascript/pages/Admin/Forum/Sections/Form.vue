<script setup lang="ts">
import { Link, useForm } from '@inertiajs/vue3'
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import Textarea from '@/components/ui/Textarea.vue'
import Select from '@/components/ui/Select.vue'
import Checkbox from '@/components/ui/Checkbox.vue'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

const props = defineProps<{
  title: string
  section: {
    id?: number
    name: string
    slug: string
    description: string
    position: number
    forum_category_id: number | null
    parent_id: number | null
    prefixes: string
    create_topic_roles: string
    reply_roles: string
    required_tag_ids: number[]
    required_tag_group_ids: number[]
    allowed_tag_ids: number[]
    default_tag_ids: number[]
    prefix_required: boolean
    min_trust_level_create: number
    min_trust_level_reply: number
    read_only: boolean
    login_required: boolean
    color_hex: string
    icon: string
    banner_text: string
    link_url: string
    link_label: string
    default_notification_level: string
    seo_title: string
    seo_description: string
    topic_template?: string
    moderator_usernames?: string
  }
  tags: Array<{ id: number; name: string }>
  tagGroups?: Array<{ id: number; name: string }>
  categories: Array<{ id: number; name: string }>
  parentSections: Array<{ id: number; name: string }>
  submitUrl: string
  method: 'post' | 'patch'
  backUrl: string
}>()

const form = useForm({
  section: {
    ...props.section,
    required_tag_ids: [ ...props.section.required_tag_ids ],
    required_tag_group_ids: [ ...(props.section.required_tag_group_ids || []) ],
    allowed_tag_ids: [ ...props.section.allowed_tag_ids ],
    default_tag_ids: [ ...props.section.default_tag_ids ],
  },
})

const categoryOptions = computed(() => [
  { value: '', label: t('admin.common.noCategory') },
  ...props.categories.map((cat) => ({ value: String(cat.id), label: cat.name })),
])

const parentSectionOptions = computed(() => [
  { value: '', label: t('admin.forms.section.noParent') },
  ...props.parentSections.map((sec) => ({ value: String(sec.id), label: sec.name })),
])

const notificationLevelOptions = computed(() => [
  { value: 'watching', label: t('admin.forms.section.notifyWatching') },
  { value: 'tracking', label: t('admin.forms.section.notifyTracking') },
  { value: 'normal', label: t('admin.forms.section.notifyNormal') },
])

function updateForumCategoryId(value: string) {
  form.section.forum_category_id = value ? Number(value) : null
}

function updateParentId(value: string) {
  form.section.parent_id = value ? Number(value) : null
}

function toggleRequiredTag(tagId: number, checked: boolean) {
  const ids = form.section.required_tag_ids
  if (checked) {
    if (!ids.includes(tagId)) ids.push(tagId)
  } else {
    const index = ids.indexOf(tagId)
    if (index >= 0) ids.splice(index, 1)
  }
}

function toggleAllowedTag(tagId: number, checked: boolean) {
  const ids = form.section.allowed_tag_ids
  if (checked) {
    if (!ids.includes(tagId)) ids.push(tagId)
  } else {
    const index = ids.indexOf(tagId)
    if (index >= 0) ids.splice(index, 1)
  }
}

function toggleDefaultTag(tagId: number, checked: boolean) {
  const ids = form.section.default_tag_ids
  if (checked) {
    if (!ids.includes(tagId)) ids.push(tagId)
  } else {
    const index = ids.indexOf(tagId)
    if (index >= 0) ids.splice(index, 1)
  }
}

function toggleRequiredTagGroup(groupId: number, checked: boolean) {
  const ids = form.section.required_tag_group_ids
  if (checked) {
    if (!ids.includes(groupId)) ids.push(groupId)
  } else {
    const index = ids.indexOf(groupId)
    if (index >= 0) ids.splice(index, 1)
  }
}

function submit() {
  if (props.method === 'patch') {
    form.patch(props.submitUrl)
  } else {
    form.post(props.submitUrl)
  }
}
</script>

<template>
  <PageHeader :title="title" />

  <form class="max-w-lg space-y-4" @submit.prevent="submit">
    <div class="space-y-2">
      <Label for="name">{{ t('admin.common.name') }}</Label>
      <Input id="name" v-model="form.section.name" required />
    </div>
    <div class="space-y-2">
      <Label for="slug">{{ t('admin.common.slugFull') }}</Label>
      <Input id="slug" v-model="form.section.slug" required />
    </div>
    <div class="space-y-2">
      <Label for="description">{{ t('admin.common.description') }}</Label>
      <Textarea id="description" v-model="form.section.description" rows="3" />
    </div>
    <div class="space-y-2">
      <Label for="position">{{ t('admin.common.position') }}</Label>
      <Input id="position" v-model.number="form.section.position" type="number" min="0" />
    </div>
    <div class="space-y-2">
      <Label for="category">{{ t('admin.forms.section.category') }}</Label>
      <Select
        id="category"
        :model-value="form.section.forum_category_id == null ? '' : String(form.section.forum_category_id)"
        :options="categoryOptions"
        block
        @update:model-value="updateForumCategoryId"
      />
    </div>
    <div class="space-y-2">
      <Label for="parent">{{ t('admin.forms.section.parent') }}</Label>
      <Select
        id="parent"
        :model-value="form.section.parent_id == null ? '' : String(form.section.parent_id)"
        :options="parentSectionOptions"
        block
        @update:model-value="updateParentId"
      />
    </div>
    <div class="space-y-2">
      <Label for="create_topic_roles">{{ t('admin.forms.section.createRoles') }}</Label>
      <Input id="create_topic_roles" v-model="form.section.create_topic_roles" placeholder="forum.topics.lock" />
    </div>
    <div class="space-y-2">
      <Label for="reply_roles">{{ t('admin.forms.section.replyRoles') }}</Label>
      <Input id="reply_roles" v-model="form.section.reply_roles" placeholder="forum.topics.lock" />
    </div>
    <div class="space-y-2">
      <Label for="prefixes">{{ t('admin.forms.section.prefixes') }}</Label>
      <Textarea id="prefixes" v-model="form.section.prefixes" rows="3" :placeholder="t('admin.forms.section.prefixColorHint')" />
      <label class="flex items-center gap-2 text-sm">
        <Checkbox v-model="form.section.prefix_required" />
        {{ t('admin.forms.section.prefixRequired') }}
      </label>
    </div>
    <label class="flex items-center gap-2 text-sm">
      <Checkbox v-model="form.section.read_only" />
      {{ t('admin.forms.section.readOnly') }}
    </label>
    <label class="flex items-center gap-2 text-sm">
      <Checkbox v-model="form.section.login_required" />
      {{ t('admin.forms.section.loginRequired') }}
    </label>
    <div class="grid grid-cols-2 gap-4">
      <div class="space-y-2">
        <Label for="color_hex">{{ t('admin.forms.section.colorHexHint') }}</Label>
        <Input id="color_hex" v-model="form.section.color_hex" placeholder="#3b82f6" />
      </div>
      <div class="space-y-2">
        <Label for="icon">{{ t('admin.forms.section.icon') }}</Label>
        <Input id="icon" v-model="form.section.icon" placeholder="💬" />
      </div>
      <div class="space-y-2">
        <Label for="banner_text">{{ t('admin.forms.section.banner') }}</Label>
        <Textarea id="banner_text" v-model="form.section.banner_text" rows="2" :placeholder="t('admin.forms.section.bannerPlaceholder')" />
      </div>
      <div class="space-y-2">
        <Label for="link_url">{{ t('admin.forms.section.linkUrl') }}</Label>
        <Input id="link_url" v-model="form.section.link_url" placeholder="https://example.com/rules" />
      </div>
      <div class="space-y-2">
        <Label for="link_label">{{ t('admin.forms.section.linkLabel') }}</Label>
        <Input id="link_label" v-model="form.section.link_label" :placeholder="t('admin.forms.section.linkLabelPlaceholder')" />
      </div>
      <div class="space-y-2">
        <Label for="seo_title">{{ t('admin.forms.section.seoTitle') }}</Label>
        <Input id="seo_title" v-model="form.section.seo_title" />
      </div>
      <div class="space-y-2">
        <Label for="seo_description">{{ t('admin.forms.section.seoDescription') }}</Label>
        <Textarea id="seo_description" v-model="form.section.seo_description" rows="2" />
      </div>
    </div>
    <div class="grid grid-cols-2 gap-4">
      <div class="space-y-2">
        <Label for="min_trust_level_create">{{ t('admin.forms.section.minTrustCreate') }}</Label>
        <Input id="min_trust_level_create" v-model.number="form.section.min_trust_level_create" type="number" min="0" max="4" />
      </div>
      <div class="space-y-2">
        <Label for="min_trust_level_reply">{{ t('admin.forms.section.minTrustReply') }}</Label>
        <Input id="min_trust_level_reply" v-model.number="form.section.min_trust_level_reply" type="number" min="0" max="4" />
      </div>
    </div>
    <div class="space-y-2">
      <Label for="default_notification_level">{{ t('admin.forms.section.defaultNotification') }}</Label>
      <Select id="default_notification_level" v-model="form.section.default_notification_level" :options="notificationLevelOptions" block />
    </div>
    <div class="space-y-2">
      <Label for="topic_template">{{ t('admin.forms.section.topicTemplate') }}</Label>
      <Textarea id="topic_template" v-model="form.section.topic_template" rows="5" :placeholder="t('admin.forms.section.topicTemplatePlaceholder')" />
    </div>
    <div class="space-y-2">
      <Label for="moderator_usernames">{{ t('admin.forms.section.moderators') }}</Label>
      <Textarea id="moderator_usernames" v-model="form.section.moderator_usernames" rows="3" :placeholder="t('admin.forms.section.moderatorsPlaceholder')" />
      <p class="text-xs text-muted-foreground">{{ t('admin.forms.section.moderatorsHint') }}</p>
    </div>
    <div v-if="tags.length" class="space-y-2">
      <Label>{{ t('admin.forms.section.requiredTags') }}</Label>
      <div class="max-h-40 space-y-2 overflow-y-auto rounded-md border p-3">
        <label v-for="tag in tags" :key="tag.id" class="flex items-center gap-2 text-sm">
          <Checkbox
            :model-value="form.section.required_tag_ids.includes(tag.id)"
            @update:model-value="(checked) => toggleRequiredTag(tag.id, checked)"
          />
          {{ tag.name }}
        </label>
      </div>
      <p class="text-xs text-muted-foreground">{{ t('admin.forms.section.requiredTagsHint') }}</p>
    </div>
    <div v-if="tagGroups?.length" class="space-y-2">
      <Label>{{ t('admin.forms.section.requiredTagGroups') }}</Label>
      <div class="max-h-40 space-y-2 overflow-y-auto rounded-md border p-3">
        <label v-for="group in tagGroups" :key="`group-${group.id}`" class="flex items-center gap-2 text-sm">
          <Checkbox
            :model-value="form.section.required_tag_group_ids.includes(group.id)"
            @update:model-value="(checked) => toggleRequiredTagGroup(group.id, checked)"
          />
          {{ group.name }}
        </label>
      </div>
    </div>
    <div v-if="tags.length" class="space-y-2">
      <Label>{{ t('admin.forms.section.allowedTags') }}</Label>
      <div class="max-h-40 space-y-2 overflow-y-auto rounded-md border p-3">
        <label v-for="tag in tags" :key="`allowed-${tag.id}`" class="flex items-center gap-2 text-sm">
          <Checkbox
            :model-value="form.section.allowed_tag_ids.includes(tag.id)"
            @update:model-value="(checked) => toggleAllowedTag(tag.id, checked)"
          />
          {{ tag.name }}
        </label>
      </div>
      <p class="text-xs text-muted-foreground">{{ t('admin.forms.section.allowedTagsHint') }}</p>
    </div>
    <div v-if="tags.length" class="space-y-2">
      <Label>{{ t('admin.forms.section.defaultTags') }}</Label>
      <div class="max-h-40 space-y-2 overflow-y-auto rounded-md border p-3">
        <label v-for="tag in tags" :key="`default-${tag.id}`" class="flex items-center gap-2 text-sm">
          <Checkbox
            :model-value="form.section.default_tag_ids.includes(tag.id)"
            @update:model-value="(checked) => toggleDefaultTag(tag.id, checked)"
          />
          {{ tag.name }}
        </label>
      </div>
      <p class="text-xs text-muted-foreground">{{ t('admin.forms.section.defaultTagsHint') }}</p>
    </div>
    <div class="flex gap-2">
      <Button type="submit" :disabled="form.processing">{{ t('admin.ui.save') }}</Button>
      <Button as-child variant="outline">
        <Link :href="backUrl">{{ t('admin.ui.cancel') }}</Link>
      </Button>
    </div>
  </form>
</template>
