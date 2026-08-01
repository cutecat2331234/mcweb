<script setup lang="ts">
import { router, useForm } from '@inertiajs/vue3'
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import { confirm } from '@/lib/arcoConfirm'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

const props = defineProps<{
  title: string
  custom_bbcode: { tag: string; replacement: string; sample: string; active: boolean }
  submitUrl: string
  method?: 'post' | 'patch'
  backUrl: string
  deleteUrl?: string | null
}>()

const form = useForm({ custom_bbcode: { ...props.custom_bbcode } })

const previewTag = computed(() => {
  const tag = form.custom_bbcode.tag.trim() || 'tag'
  const content = form.custom_bbcode.sample.trim() || '{content}'
  return `[${tag}]${content}[/${tag}]`
})

const previewReplacement = computed(() => {
  const replacement = form.custom_bbcode.replacement.trim()
  if (!replacement) return ''
  return replacement.replaceAll('{content}', form.custom_bbcode.sample.trim() || '{content}')
})

function fieldError(field: string) {
  const errors = form.errors as Record<string, string | undefined>
  return errors[field] || errors[`custom_bbcode.${field}`]
}

function submit(event?: { errors?: unknown }) {
  if (event?.errors) return
  if (props.method === 'patch') {
    form.patch(props.submitUrl)
  } else {
    form.post(props.submitUrl)
  }
}

async function destroy() {
  const ok = await confirm({
    title: t('admin.customBbcodes.deleteTitle'),
    message: t('admin.customBbcodes.deleteConfirm'),
    confirmLabel: t('admin.ui.delete'),
    variant: 'destructive',
  })
  if (!props.deleteUrl || !ok) return
  form.delete(props.deleteUrl)
}

function goBack() {
  router.visit(props.backUrl)
}
</script>

<template>
  <a-space direction="vertical" :size="16" fill>
    <a-page-header :title="title" :show-back="false">
      <template #extra>
        <a-button shape="round" @click="goBack">{{ t('admin.ui.back') }}</a-button>
      </template>
    </a-page-header>

    <a-row :gutter="[16, 16]">
      <a-col :xs="24" :xl="16">
        <a-card :bordered="true">
          <a-form :model="form.custom_bbcode" layout="vertical" @submit="submit">
            <a-grid :cols="{ xs: 1, md: 2 }" :col-gap="16" :row-gap="4">
              <a-grid-item>
                <a-form-item
                  field="tag"
                  :label="t('admin.customBbcodes.tag')"
                  :help="fieldError('tag') || t('admin.customBbcodes.tagHint')"
                  :validate-status="fieldError('tag') ? 'error' : undefined"
                >
                  <a-input
                    v-model="form.custom_bbcode.tag"
                    :placeholder="t('admin.customBbcodes.tagPlaceholder')"
                    :input-attrs="{ required: true, maxlength: 20 }"
                    allow-clear
                  />
                </a-form-item>
              </a-grid-item>
              <a-grid-item>
                <a-form-item
                  field="sample"
                  :label="t('admin.customBbcodes.sample')"
                  :help="fieldError('sample')"
                  :validate-status="fieldError('sample') ? 'error' : undefined"
                >
                  <a-input v-model="form.custom_bbcode.sample" allow-clear />
                </a-form-item>
              </a-grid-item>
            </a-grid>

            <a-form-item
              field="replacement"
              :label="t('admin.customBbcodes.replacement')"
              :help="fieldError('replacement') || t('admin.customBbcodes.replacementHint')"
              :validate-status="fieldError('replacement') ? 'error' : undefined"
            >
              <a-textarea
                v-model="form.custom_bbcode.replacement"
                :auto-size="{ minRows: 6, maxRows: 14 }"
                :placeholder="'> 📌 {content}'"
                :textarea-attrs="{ required: true }"
                allow-clear
              />
            </a-form-item>

            <a-form-item
              field="active"
              :label="t('admin.customBbcodes.active')"
              :help="fieldError('active')"
              :validate-status="fieldError('active') ? 'error' : undefined"
            >
              <a-switch
                v-model="form.custom_bbcode.active"
                :checked-text="t('admin.ui.enabled')"
                :unchecked-text="t('admin.ui.disabled')"
              />
            </a-form-item>

            <a-divider />

            <a-space wrap>
              <a-button
                html-type="submit"
                type="primary"
                shape="round"
                :loading="form.processing"
              >
                {{ t('admin.ui.save') }}
              </a-button>
              <a-button
                v-if="deleteUrl"
                type="primary"
                status="danger"
                :disabled="form.processing"
                @click="destroy"
              >
                {{ t('admin.ui.delete') }}
              </a-button>
            </a-space>
          </a-form>
        </a-card>
      </a-col>

      <a-col :xs="24" :xl="8">
        <a-card :title="t('admin.customBbcodes.sample')" :bordered="false">
          <a-space direction="vertical" :size="12" fill>
            <a-descriptions :column="1" bordered size="small">
              <a-descriptions-item :label="t('admin.customBbcodes.tag')">
                <a-typography-text code copyable>{{ previewTag }}</a-typography-text>
              </a-descriptions-item>
              <a-descriptions-item :label="t('admin.customBbcodes.active')">
                <a-tag :color="form.custom_bbcode.active ? 'green' : 'gray'">
                  {{ form.custom_bbcode.active ? t('admin.ui.enabled') : t('admin.ui.disabled') }}
                </a-tag>
              </a-descriptions-item>
            </a-descriptions>

            <a-typography-paragraph v-if="previewReplacement" code copyable>
              {{ previewReplacement }}
            </a-typography-paragraph>
            <a-empty v-else :description="t('admin.customBbcodes.replacementHint')" />
          </a-space>
        </a-card>
      </a-col>
    </a-row>
  </a-space>
</template>
