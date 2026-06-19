<script setup lang="ts">
import { Link, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import Checkbox from '@/components/ui/Checkbox.vue'

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
      <Label for="code">{{ t('admin.forms.giftCard.code') }}</Label>
      <Input id="code" v-model="form.gift_card.code" :placeholder="t('admin.forms.giftCard.codePlaceholder')" :disabled="method === 'patch'" />
      <p v-if="method !== 'patch'" class="text-xs text-muted-foreground">{{ t('admin.forms.giftCard.codeHint') }}</p>
    </div>
    <div class="grid grid-cols-2 gap-4">
      <div class="space-y-2">
        <Label for="balance_cents">{{ t('admin.forms.giftCard.balanceCents') }}</Label>
        <Input id="balance_cents" v-model.number="form.gift_card.balance_cents" type="number" min="1" required />
      </div>
      <div class="space-y-2">
        <Label for="currency">{{ t('admin.forms.giftCard.currency') }}</Label>
        <Input id="currency" v-model="form.gift_card.currency" required />
      </div>
    </div>
    <div class="space-y-2">
      <Label for="expires_at">{{ t('admin.forms.giftCard.expiresAt') }}</Label>
      <Input id="expires_at" v-model="form.gift_card.expires_at" type="datetime-local" />
    </div>
    <div class="space-y-2">
      <Label for="note">{{ t('admin.forms.giftCard.note') }}</Label>
      <Input id="note" v-model="form.gift_card.note" :placeholder="t('admin.forms.giftCard.notePlaceholder')" />
    </div>
    <div v-if="method !== 'patch'" class="space-y-2">
      <Label for="recipient_email">{{ t('admin.forms.giftCard.recipientEmail') }}</Label>
      <Input id="recipient_email" v-model="form.gift_card.recipient_email" type="email" :placeholder="t('admin.forms.giftCard.recipientPlaceholder')" />
    </div>
    <label class="flex items-center gap-2 text-sm">
      <Checkbox v-model="form.gift_card.active" />
      {{ t('admin.common.enable') }}
    </label>
    <div class="flex gap-2">
      <Button type="submit" :disabled="form.processing">{{ method === 'patch' ? t('admin.ui.save') : t('admin.ui.create') }}</Button>
      <Button as-child variant="outline">
        <Link :href="backUrl">{{ t('admin.ui.cancel') }}</Link>
      </Button>
    </div>
  </form>
</template>
