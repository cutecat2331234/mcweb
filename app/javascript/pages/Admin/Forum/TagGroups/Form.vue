<script setup lang="ts">
import { ref } from 'vue'
import { Link, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

const props = defineProps<{
  title: string
  tagGroup: {
    id?: number
    name: string
    slug: string
    description: string
    one_per_topic: boolean
    color_hex?: string
    tag_ids: number[]
  }
  tags: Array<{ id: number; name: string }>
  submitUrl: string
  method: 'post' | 'patch'
  backUrl: string
}>()

const selectedTagIds = ref<number[]>([...props.tagGroup.tag_ids])

const form = useForm({
  tag_group: {
    name: props.tagGroup.name,
    slug: props.tagGroup.slug,
    description: props.tagGroup.description,
    one_per_topic: props.tagGroup.one_per_topic,
    color_hex: props.tagGroup.color_hex || '',
    tag_ids: selectedTagIds.value,
  },
})

function submit() {
  form.tag_group.tag_ids = [...selectedTagIds.value]
  if (props.method === 'patch') {
    form.patch(props.submitUrl)
  } else {
    form.post(props.submitUrl)
  }
}
</script>

<template>
  <a-page-header :title="title" :show-back="false" class="mb-4 !px-0" />
  <a-card class="max-w-2xl" :bordered="true">
    <form class="grid gap-4" @submit.prevent="submit">
      <a-row :gutter="[16, 0]">
        <a-col :xs="24" :sm="12">
          <label class="admin-forum-field">
            <span>{{ t('admin.common.name') }}</span>
            <a-input v-model="form.tag_group.name" :input-attrs="{ required: true }" allow-clear />
          </label>
        </a-col>
        <a-col :xs="24" :sm="12">
          <label class="admin-forum-field">
            <span>{{ t('admin.forms.tag.slug') }}</span>
            <a-input v-model="form.tag_group.slug" allow-clear />
          </label>
        </a-col>
      </a-row>
      <label class="admin-forum-field">
        <span>{{ t('admin.common.description') }}</span>
        <a-textarea v-model="form.tag_group.description" :auto-size="{ minRows: 3, maxRows: 7 }" />
      </label>
      <label class="admin-forum-field">
        <span>{{ t('admin.forms.tagGroup.groupColor') }}</span>
        <a-input v-model="form.tag_group.color_hex" placeholder="#6366f1" allow-clear />
      </label>
      <a-checkbox v-model="form.tag_group.one_per_topic">
        {{ t('admin.forms.tagGroup.onePerTopic') }}
      </a-checkbox>
      <a-card :title="t('admin.forms.tagGroup.tagsInGroup')" size="small" :bordered="true">
        <a-checkbox-group v-model="selectedTagIds" class="admin-forum-choice-grid">
          <a-checkbox v-for="tag in tags" :key="tag.id" :value="tag.id">{{ tag.name }}</a-checkbox>
        </a-checkbox-group>
      </a-card>
      <a-space wrap>
        <a-button html-type="submit" type="primary" :loading="form.processing">{{ t('admin.ui.save') }}</a-button>
        <Link :href="backUrl" class="arco-btn arco-btn-outline arco-btn-size-medium no-underline">{{ t('admin.ui.back') }}</Link>
      </a-space>
    </form>
  </a-card>
</template>

<style scoped>
.admin-forum-field { display: grid; gap: 6px; color: var(--color-text-2); font-size: 14px; }
.admin-forum-choice-grid { display: grid; max-height: 12rem; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 8px 12px; overflow-y: auto; }
@media (max-width: 639px) { .admin-forum-choice-grid { grid-template-columns: minmax(0, 1fr); } }
</style>
