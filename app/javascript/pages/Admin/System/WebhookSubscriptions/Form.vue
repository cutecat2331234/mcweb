<script setup lang="ts">
import { computed } from 'vue'
import { Link, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import { confirm } from '@/lib/arcoConfirm'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

const props = defineProps<{
  title: string
  subscription: { name: string; url: string; event: string; secret: string; active: boolean }
  events: string[]
  submitUrl: string
  method?: 'post' | 'patch'
  backUrl: string
  deleteUrl?: string | null
}>()

const form = useForm({ webhook_subscription: { ...props.subscription } })
const eventOptions = computed(() =>
  props.events.map((event) => ({ value: event, label: event })),
)

function fieldError(field: string) {
  return form.errors[field] || form.errors[`webhook_subscription.${field}`]
}

function submit(event?: { errors?: unknown }) {
  if (event?.errors) return
  if (props.method === 'patch') form.patch(props.submitUrl)
  else form.post(props.submitUrl)
}

async function destroy() {
  const ok = await confirm({
    title: t('admin.webhookSubscriptions.deleteTitle'),
    message: t('admin.webhookSubscriptions.deleteConfirm'),
    confirmLabel: t('admin.ui.delete'),
    variant: 'destructive',
  })
  if (!props.deleteUrl || !ok) return
  form.delete(props.deleteUrl)
}
</script>

<template>
  <section class="admin-system-webhook-subscription-form">
    <a-page-header :title="title" :show-back="false" class="mb-4 !px-0" />

    <a-card class="max-w-2xl" :bordered="true">
      <a-form :model="form.webhook_subscription" layout="vertical" @submit="submit">
        <a-form-item
          field="name"
          :label="t('admin.webhookSubscriptions.name')"
          :rules="[{ required: true, message: t('admin.webhookSubscriptions.name') }]"
          :validate-status="fieldError('name') ? 'error' : undefined"
          :help="fieldError('name')"
        >
          <a-input
            v-model="form.webhook_subscription.name"
            :max-length="80"
            show-word-limit
            allow-clear
          />
        </a-form-item>

        <a-form-item
          field="url"
          :label="t('admin.webhookSubscriptions.url')"
          :rules="[{ required: true, message: t('admin.webhookSubscriptions.url') }]"
          :validate-status="fieldError('url') ? 'error' : undefined"
          :help="fieldError('url')"
        >
          <a-input
            v-model="form.webhook_subscription.url"
            placeholder="https://example.com/hook"
            allow-clear
          />
        </a-form-item>

        <a-form-item
          field="event"
          :label="t('admin.webhookSubscriptions.event')"
          :validate-status="fieldError('event') ? 'error' : undefined"
          :help="fieldError('event')"
        >
          <a-select
            v-model="form.webhook_subscription.event"
            :options="eventOptions"
            allow-search
          />
        </a-form-item>

        <a-form-item
          field="secret"
          :label="t('admin.webhookSubscriptions.secret')"
          :validate-status="fieldError('secret') ? 'error' : undefined"
          :help="fieldError('secret') || t('admin.webhookSubscriptions.secretHint')"
        >
          <a-input
            v-model="form.webhook_subscription.secret"
            :placeholder="t('admin.webhookSubscriptions.secretHint')"
            allow-clear
          />
        </a-form-item>

        <a-form-item
          field="active"
          :label="t('admin.webhookSubscriptions.activeLabel')"
          :validate-status="fieldError('active') ? 'error' : undefined"
          :help="fieldError('active')"
        >
          <a-space>
            <a-switch v-model="form.webhook_subscription.active" />
            <a-tag :color="form.webhook_subscription.active ? 'green' : 'gray'">
              {{
                form.webhook_subscription.active
                  ? t('admin.webhookSubscriptions.active')
                  : t('admin.webhookSubscriptions.disabled')
              }}
            </a-tag>
          </a-space>
        </a-form-item>

        <a-space wrap>
          <a-button
            type="primary"
            html-type="submit"
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
          <Link
            :href="backUrl"
            class="arco-btn arco-btn-outline arco-btn-size-medium no-underline"
          >
            {{ t('admin.ui.back') }}
          </Link>
        </a-space>
      </a-form>
    </a-card>
  </section>
</template>
