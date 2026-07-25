<script setup lang="ts">
import { Link, useForm } from '@inertiajs/vue3'
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'

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

function submit() {
  if (props.method === 'patch') {
    form.patch(props.submitUrl)
  } else {
    form.post(props.submitUrl)
  }
}
</script>

<template>
  <a-page-header :title="title" :show-back="false" class="mb-4 !px-0" />

  <a-card class="max-w-5xl" :bordered="true">
    <form class="space-y-5" @submit.prevent="submit">
      <a-row :gutter="[16, 0]">
        <a-col :xs="24" :md="12">
          <label class="admin-forum-field">
            <span>{{ t('admin.common.name') }}</span>
            <a-input v-model="form.section.name" :input-attrs="{ required: true }" allow-clear />
          </label>
        </a-col>
        <a-col :xs="24" :md="12">
          <label class="admin-forum-field">
            <span>{{ t('admin.common.slugFull') }}</span>
            <a-input v-model="form.section.slug" :input-attrs="{ required: true }" allow-clear />
          </label>
        </a-col>
      </a-row>

      <label class="admin-forum-field">
        <span>{{ t('admin.common.description') }}</span>
        <a-textarea v-model="form.section.description" :auto-size="{ minRows: 3, maxRows: 7 }" />
      </label>

      <a-row :gutter="[16, 0]">
        <a-col :xs="24" :sm="8">
          <label class="admin-forum-field">
            <span>{{ t('admin.common.position') }}</span>
            <a-input-number v-model="form.section.position" :min="0" class="w-full" />
          </label>
        </a-col>
        <a-col :xs="24" :sm="8">
          <label class="admin-forum-field">
            <span>{{ t('admin.forms.section.category') }}</span>
            <a-select
              :model-value="form.section.forum_category_id == null ? '' : String(form.section.forum_category_id)"
              :options="categoryOptions"
              @change="updateForumCategoryId"
            />
          </label>
        </a-col>
        <a-col :xs="24" :sm="8">
          <label class="admin-forum-field">
            <span>{{ t('admin.forms.section.parent') }}</span>
            <a-select
              :model-value="form.section.parent_id == null ? '' : String(form.section.parent_id)"
              :options="parentSectionOptions"
              @change="updateParentId"
            />
          </label>
        </a-col>
      </a-row>

      <a-card size="small" :bordered="true">
        <template #title>{{ t('admin.forms.section.createRoles') }} / {{ t('admin.forms.section.replyRoles') }}</template>
        <a-row :gutter="[16, 0]">
          <a-col :xs="24" :md="12">
            <label class="admin-forum-field">
              <span>{{ t('admin.forms.section.createRoles') }}</span>
              <a-input v-model="form.section.create_topic_roles" placeholder="forum.topics.lock" allow-clear />
            </label>
          </a-col>
          <a-col :xs="24" :md="12">
            <label class="admin-forum-field">
              <span>{{ t('admin.forms.section.replyRoles') }}</span>
              <a-input v-model="form.section.reply_roles" placeholder="forum.topics.lock" allow-clear />
            </label>
          </a-col>
        </a-row>
        <a-space wrap :size="[20, 8]">
          <a-checkbox v-model="form.section.read_only">{{ t('admin.forms.section.readOnly') }}</a-checkbox>
          <a-checkbox v-model="form.section.login_required">{{ t('admin.forms.section.loginRequired') }}</a-checkbox>
        </a-space>
      </a-card>

      <label class="admin-forum-field">
        <span>{{ t('admin.forms.section.prefixes') }}</span>
        <a-textarea
          v-model="form.section.prefixes"
          :auto-size="{ minRows: 3, maxRows: 7 }"
          :placeholder="t('admin.forms.section.prefixColorHint')"
        />
      </label>
      <a-checkbox v-model="form.section.prefix_required">
        {{ t('admin.forms.section.prefixRequired') }}
      </a-checkbox>

      <a-card size="small" :bordered="true">
        <a-row :gutter="[16, 0]">
          <a-col :xs="24" :md="12">
            <label class="admin-forum-field">
              <span>{{ t('admin.forms.section.colorHexHint') }}</span>
              <a-input v-model="form.section.color_hex" placeholder="#3b82f6" allow-clear />
            </label>
          </a-col>
          <a-col :xs="24" :md="12">
            <label class="admin-forum-field">
              <span>{{ t('admin.forms.section.icon') }}</span>
              <a-input v-model="form.section.icon" placeholder="💬" allow-clear />
            </label>
          </a-col>
          <a-col :xs="24" :md="12">
            <label class="admin-forum-field">
              <span>{{ t('admin.forms.section.banner') }}</span>
              <a-textarea
                v-model="form.section.banner_text"
                :auto-size="{ minRows: 2, maxRows: 5 }"
                :placeholder="t('admin.forms.section.bannerPlaceholder')"
              />
            </label>
          </a-col>
          <a-col :xs="24" :md="12">
            <label class="admin-forum-field">
              <span>{{ t('admin.forms.section.linkUrl') }}</span>
              <a-input v-model="form.section.link_url" placeholder="https://example.com/rules" allow-clear />
            </label>
          </a-col>
          <a-col :xs="24" :md="12">
            <label class="admin-forum-field">
              <span>{{ t('admin.forms.section.linkLabel') }}</span>
              <a-input
                v-model="form.section.link_label"
                :placeholder="t('admin.forms.section.linkLabelPlaceholder')"
                allow-clear
              />
            </label>
          </a-col>
          <a-col :xs="24" :md="12">
            <label class="admin-forum-field">
              <span>{{ t('admin.forms.section.seoTitle') }}</span>
              <a-input v-model="form.section.seo_title" allow-clear />
            </label>
          </a-col>
        </a-row>
        <label class="admin-forum-field">
          <span>{{ t('admin.forms.section.seoDescription') }}</span>
          <a-textarea v-model="form.section.seo_description" :auto-size="{ minRows: 2, maxRows: 5 }" />
        </label>
      </a-card>

      <a-row :gutter="[16, 0]">
        <a-col :xs="24" :sm="8">
          <label class="admin-forum-field">
            <span>{{ t('admin.forms.section.minTrustCreate') }}</span>
            <a-input-number v-model="form.section.min_trust_level_create" :min="0" :max="4" class="w-full" />
          </label>
        </a-col>
        <a-col :xs="24" :sm="8">
          <label class="admin-forum-field">
            <span>{{ t('admin.forms.section.minTrustReply') }}</span>
            <a-input-number v-model="form.section.min_trust_level_reply" :min="0" :max="4" class="w-full" />
          </label>
        </a-col>
        <a-col :xs="24" :sm="8">
          <label class="admin-forum-field">
            <span>{{ t('admin.forms.section.defaultNotification') }}</span>
            <a-select v-model="form.section.default_notification_level" :options="notificationLevelOptions" />
          </label>
        </a-col>
      </a-row>

      <label class="admin-forum-field">
        <span>{{ t('admin.forms.section.topicTemplate') }}</span>
        <a-textarea
          v-model="form.section.topic_template"
          :auto-size="{ minRows: 5, maxRows: 12 }"
          :placeholder="t('admin.forms.section.topicTemplatePlaceholder')"
        />
      </label>
      <label class="admin-forum-field">
        <span>{{ t('admin.forms.section.moderators') }}</span>
        <a-textarea
          v-model="form.section.moderator_usernames"
          :auto-size="{ minRows: 3, maxRows: 8 }"
          :placeholder="t('admin.forms.section.moderatorsPlaceholder')"
        />
        <small>{{ t('admin.forms.section.moderatorsHint') }}</small>
      </label>

      <a-row v-if="tags.length || tagGroups?.length" :gutter="[16, 16]">
        <a-col v-if="tags.length" :xs="24" :lg="12">
          <a-card :title="t('admin.forms.section.requiredTags')" size="small" :bordered="true" class="h-full">
            <a-checkbox-group v-model="form.section.required_tag_ids" class="admin-forum-choice-grid">
              <a-checkbox v-for="tag in tags" :key="tag.id" :value="tag.id">{{ tag.name }}</a-checkbox>
            </a-checkbox-group>
            <p class="mt-2 text-xs text-[var(--color-text-3)]">{{ t('admin.forms.section.requiredTagsHint') }}</p>
          </a-card>
        </a-col>
        <a-col v-if="tagGroups?.length" :xs="24" :lg="12">
          <a-card :title="t('admin.forms.section.requiredTagGroups')" size="small" :bordered="true" class="h-full">
            <a-checkbox-group v-model="form.section.required_tag_group_ids" class="admin-forum-choice-grid">
              <a-checkbox v-for="group in tagGroups" :key="group.id" :value="group.id">{{ group.name }}</a-checkbox>
            </a-checkbox-group>
          </a-card>
        </a-col>
        <a-col v-if="tags.length" :xs="24" :lg="12">
          <a-card :title="t('admin.forms.section.allowedTags')" size="small" :bordered="true" class="h-full">
            <a-checkbox-group v-model="form.section.allowed_tag_ids" class="admin-forum-choice-grid">
              <a-checkbox v-for="tag in tags" :key="tag.id" :value="tag.id">{{ tag.name }}</a-checkbox>
            </a-checkbox-group>
            <p class="mt-2 text-xs text-[var(--color-text-3)]">{{ t('admin.forms.section.allowedTagsHint') }}</p>
          </a-card>
        </a-col>
        <a-col v-if="tags.length" :xs="24" :lg="12">
          <a-card :title="t('admin.forms.section.defaultTags')" size="small" :bordered="true" class="h-full">
            <a-checkbox-group v-model="form.section.default_tag_ids" class="admin-forum-choice-grid">
              <a-checkbox v-for="tag in tags" :key="tag.id" :value="tag.id">{{ tag.name }}</a-checkbox>
            </a-checkbox-group>
            <p class="mt-2 text-xs text-[var(--color-text-3)]">{{ t('admin.forms.section.defaultTagsHint') }}</p>
          </a-card>
        </a-col>
      </a-row>

      <a-space wrap>
        <a-button html-type="submit" type="primary" :loading="form.processing">
          {{ t('admin.ui.save') }}
        </a-button>
        <Link :href="backUrl" class="arco-btn arco-btn-outline arco-btn-size-medium no-underline">
          {{ t('admin.ui.cancel') }}
        </Link>
      </a-space>
    </form>
  </a-card>
</template>

<style scoped>
.admin-forum-field {
  display: grid;
  gap: 6px;
  margin-bottom: 16px;
  color: var(--color-text-2);
  font-size: 14px;
}

.admin-forum-field small {
  color: var(--color-text-3);
}

.admin-forum-choice-grid {
  display: grid;
  max-height: 12rem;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 8px 12px;
  overflow-y: auto;
}

@media (max-width: 639px) {
  .admin-forum-choice-grid {
    grid-template-columns: minmax(0, 1fr);
  }
}
</style>
