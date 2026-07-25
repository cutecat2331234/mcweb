<script setup lang="ts">
import { computed } from 'vue'
import { Link, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

const props = defineProps<{
  title: string
  gift_card: {
    code: string
    balance_cents: number
    currency: string
    expires_at: string | null
    note: string
    active: boolean
    recipient_email?: string
  }
  submitUrl: string
  method?: 'post' | 'patch'
  backUrl: string
}>()

const form = useForm({ gift_card: { ...props.gift_card } })

const expiresAt = computed<string | undefined>({
  get: () => form.gift_card.expires_at || undefined,
  set: (value) => {
    form.gift_card.expires_at = value || null
  },
})

function fieldError(field: string) {
  return form.errors[field] || form.errors[`gift_card.${field}`]
}

function normalizeEmptyNumbers(record: object, fields: string[]) {
  const values = record as Record<string, unknown>
  fields.forEach((field) => {
    if (values[field] === undefined) values[field] = null
  })
}

function submit(event?: { errors?: unknown }) {
  if (event?.errors) return
  normalizeEmptyNumbers(form.gift_card, ['balance_cents'])
  if (props.method === 'patch') {
    form.patch(props.submitUrl)
  } else {
    form.post(props.submitUrl)
  }
}
</script>

<template>
  <section class="admin-store-gift-card-form">
    <a-page-header :title="title" :show-back="false" class="mb-4 !px-0" />

    <a-card class="max-w-3xl" :bordered="true">
      <a-form :model="form.gift_card" layout="vertical" @submit="submit">
        <a-form-item
          field="code"
          :label="t('admin.forms.giftCard.code')"
          :validate-status="fieldError('code') ? 'error' : undefined"
          :help="fieldError('code') || (method !== 'patch' ? t('admin.forms.giftCard.codeHint') : undefined)"
        >
          <a-input
            v-model="form.gift_card.code"
            :placeholder="t('admin.forms.giftCard.codePlaceholder')"
            :disabled="method === 'patch'"
            allow-clear
          />
        </a-form-item>

        <a-grid :cols="{ xs: 1, sm: 2 }" :col-gap="16" :row-gap="4">
          <a-grid-item>
            <a-form-item
              field="balance_cents"
              :label="t('admin.forms.giftCard.balanceCents')"
              :rules="[{ required: true, message: t('admin.forms.giftCard.balanceCents') }]"
              :validate-status="fieldError('balance_cents') ? 'error' : undefined"
              :help="fieldError('balance_cents')"
            >
              <a-input-number v-model="form.gift_card.balance_cents" :min="1" class="w-full" />
            </a-form-item>
          </a-grid-item>

          <a-grid-item>
            <a-form-item
              field="currency"
              :label="t('admin.forms.giftCard.currency')"
              :rules="[{ required: true, message: t('admin.forms.giftCard.currency') }]"
              :validate-status="fieldError('currency') ? 'error' : undefined"
              :help="fieldError('currency')"
            >
              <a-input v-model="form.gift_card.currency" allow-clear />
            </a-form-item>
          </a-grid-item>
        </a-grid>

        <a-form-item
          field="expires_at"
          :label="t('admin.forms.giftCard.expiresAt')"
          :validate-status="fieldError('expires_at') ? 'error' : undefined"
          :help="fieldError('expires_at')"
        >
          <a-date-picker
            v-model="expiresAt"
            class="w-full"
            show-time
            format="YYYY-MM-DD HH:mm"
            value-format="YYYY-MM-DDTHH:mm"
            allow-clear
          />
        </a-form-item>

        <a-form-item
          field="note"
          :label="t('admin.forms.giftCard.note')"
          :validate-status="fieldError('note') ? 'error' : undefined"
          :help="fieldError('note')"
        >
          <a-input
            v-model="form.gift_card.note"
            :placeholder="t('admin.forms.giftCard.notePlaceholder')"
            allow-clear
          />
        </a-form-item>

        <a-form-item
          v-if="method !== 'patch'"
          field="recipient_email"
          :label="t('admin.forms.giftCard.recipientEmail')"
          :validate-status="fieldError('recipient_email') ? 'error' : undefined"
          :help="fieldError('recipient_email')"
        >
          <a-input
            v-model="form.gift_card.recipient_email"
            :placeholder="t('admin.forms.giftCard.recipientPlaceholder')"
            allow-clear
          />
        </a-form-item>

        <a-form-item
          field="active"
          :label="t('admin.common.enable')"
          :validate-status="fieldError('active') ? 'error' : undefined"
          :help="fieldError('active')"
        >
          <a-switch v-model="form.gift_card.active" />
        </a-form-item>

        <a-space wrap>
          <a-button type="primary" html-type="submit" :loading="form.processing">
            {{ method === 'patch' ? t('admin.ui.save') : t('admin.ui.create') }}
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
