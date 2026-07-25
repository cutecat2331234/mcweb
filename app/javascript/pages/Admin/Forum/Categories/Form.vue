<script setup lang="ts">
import { Link, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

const props = defineProps<{
  title: string
  category: { id?: number; name: string; slug: string; position: number; color_hex?: string; icon?: string; description?: string; seo_title?: string; seo_description?: string }
  submitUrl: string
  method: 'post' | 'patch'
  backUrl: string
}>()

const form = useForm({ category: { ...props.category } })

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
  <a-card class="max-w-3xl" :bordered="true">
    <form class="grid gap-4" @submit.prevent="submit">
      <a-row :gutter="[16, 0]">
        <a-col :xs="24" :sm="12">
          <label class="admin-forum-field">
            <span>{{ t('admin.common.name') }}</span>
            <a-input v-model="form.category.name" :input-attrs="{ required: true }" allow-clear />
          </label>
        </a-col>
        <a-col :xs="24" :sm="12">
          <label class="admin-forum-field">
            <span>{{ t('admin.common.slugFull') }}</span>
            <a-input v-model="form.category.slug" :input-attrs="{ required: true }" allow-clear />
          </label>
        </a-col>
        <a-col :xs="24" :sm="8">
          <label class="admin-forum-field">
            <span>{{ t('admin.common.position') }}</span>
            <a-input-number v-model="form.category.position" :min="0" class="w-full" />
          </label>
        </a-col>
        <a-col :xs="24" :sm="8">
          <label class="admin-forum-field">
            <span>{{ t('admin.forms.forumCategory.colorHex') }}</span>
            <a-input v-model="form.category.color_hex" placeholder="#2563eb" allow-clear />
          </label>
        </a-col>
        <a-col :xs="24" :sm="8">
          <label class="admin-forum-field">
            <span>{{ t('admin.forms.forumCategory.iconEmoji') }}</span>
            <a-input v-model="form.category.icon" placeholder="💬" allow-clear />
          </label>
        </a-col>
      </a-row>
      <label class="admin-forum-field">
        <span>{{ t('admin.common.description') }}</span>
        <a-textarea
          v-model="form.category.description"
          :auto-size="{ minRows: 3, maxRows: 7 }"
          :placeholder="t('admin.forms.forumCategory.descriptionPlaceholder')"
        />
      </label>
      <label class="admin-forum-field">
        <span>{{ t('admin.forms.category.seoTitle') }}</span>
        <a-input v-model="form.category.seo_title" allow-clear />
      </label>
      <label class="admin-forum-field">
        <span>{{ t('admin.forms.category.seoDescription') }}</span>
        <a-textarea v-model="form.category.seo_description" :auto-size="{ minRows: 2, maxRows: 5 }" />
      </label>
      <a-space wrap>
        <a-button html-type="submit" type="primary" :loading="form.processing">{{ t('admin.ui.save') }}</a-button>
        <Link :href="backUrl" class="arco-btn arco-btn-outline arco-btn-size-medium no-underline">{{ t('admin.ui.cancel') }}</Link>
      </a-space>
    </form>
  </a-card>
</template>

<style scoped>
.admin-forum-field { display: grid; gap: 6px; color: var(--color-text-2); font-size: 14px; }
</style>
