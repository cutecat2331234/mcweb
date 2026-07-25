<script setup lang="ts">
import { Link, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

const props = defineProps<{
  title: string
  category: {
    id?: number
    name: string
    slug: string
    position: number
    description?: string
    icon?: string
    color_hex?: string
    seo_title?: string
    seo_description?: string
  }
  submitUrl: string
  method: 'post' | 'patch'
  backUrl: string
}>()

const form = useForm({
  category: { ...props.category },
})

function fieldError(field: string) {
  return form.errors[field] || form.errors[`category.${field}`]
}

function normalizeEmptyNumbers(record: object, fields: string[]) {
  const values = record as Record<string, unknown>
  fields.forEach((field) => {
    if (values[field] === undefined) values[field] = null
  })
}

function submit(event?: { errors?: unknown }) {
  if (event?.errors) return
  normalizeEmptyNumbers(form.category, ['position'])
  if (props.method === 'patch') {
    form.patch(props.submitUrl)
  } else {
    form.post(props.submitUrl)
  }
}
</script>

<template>
  <section class="admin-store-category-form">
    <a-page-header :title="title" :show-back="false" class="mb-4 !px-0" />

    <a-card class="max-w-3xl" :bordered="true">
      <a-form :model="form.category" layout="vertical" @submit="submit">
        <a-grid :cols="{ xs: 1, sm: 2 }" :col-gap="16" :row-gap="4">
          <a-grid-item>
            <a-form-item
              field="name"
              :label="t('admin.common.name')"
              :rules="[{ required: true, message: t('admin.common.name') }]"
              :validate-status="fieldError('name') ? 'error' : undefined"
              :help="fieldError('name')"
            >
              <a-input v-model="form.category.name" allow-clear />
            </a-form-item>
          </a-grid-item>

          <a-grid-item>
            <a-form-item
              field="slug"
              :label="t('admin.forms.category.slug')"
              :rules="[{ required: true, message: t('admin.forms.category.slug') }]"
              :validate-status="fieldError('slug') ? 'error' : undefined"
              :help="fieldError('slug')"
            >
              <a-input v-model="form.category.slug" allow-clear />
            </a-form-item>
          </a-grid-item>
        </a-grid>

        <a-form-item
          field="position"
          :label="t('admin.common.position')"
          :validate-status="fieldError('position') ? 'error' : undefined"
          :help="fieldError('position')"
        >
          <a-input-number v-model="form.category.position" :min="0" class="w-full" />
        </a-form-item>

        <a-form-item
          field="description"
          :label="t('admin.forms.category.descriptionPublic')"
          :validate-status="fieldError('description') ? 'error' : undefined"
          :help="fieldError('description')"
        >
          <a-input v-model="form.category.description" allow-clear />
        </a-form-item>

        <a-grid :cols="{ xs: 1, sm: 2 }" :col-gap="16" :row-gap="4">
          <a-grid-item>
            <a-form-item
              field="icon"
              :label="t('admin.forms.category.icon')"
              :validate-status="fieldError('icon') ? 'error' : undefined"
              :help="fieldError('icon')"
            >
              <a-input v-model="form.category.icon" placeholder="🛍️" allow-clear />
            </a-form-item>
          </a-grid-item>

          <a-grid-item>
            <a-form-item
              field="color_hex"
              :label="t('admin.common.colorHex')"
              :validate-status="fieldError('color_hex') ? 'error' : undefined"
              :help="fieldError('color_hex')"
            >
              <a-input v-model="form.category.color_hex" placeholder="#3b82f6" allow-clear />
            </a-form-item>
          </a-grid-item>
        </a-grid>

        <a-form-item
          field="seo_title"
          :label="t('admin.forms.category.seoTitle')"
          :validate-status="fieldError('seo_title') ? 'error' : undefined"
          :help="fieldError('seo_title')"
        >
          <a-input v-model="form.category.seo_title" allow-clear />
        </a-form-item>

        <a-form-item
          field="seo_description"
          :label="t('admin.forms.category.seoDescription')"
          :validate-status="fieldError('seo_description') ? 'error' : undefined"
          :help="fieldError('seo_description')"
        >
          <a-textarea
            v-model="form.category.seo_description"
            :auto-size="{ minRows: 2, maxRows: 5 }"
            allow-clear
          />
        </a-form-item>

        <a-space wrap>
          <a-button type="primary" html-type="submit" :loading="form.processing">
            {{ t('admin.ui.save') }}
          </a-button>
          <Link
            :href="backUrl"
            class="arco-btn arco-btn-outline arco-btn-size-medium no-underline"
          >
            {{ t('admin.ui.cancel') }}
          </Link>
        </a-space>
      </a-form>
    </a-card>
  </section>
</template>
