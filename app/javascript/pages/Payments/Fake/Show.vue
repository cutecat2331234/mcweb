<script setup lang="ts">
import { Link, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import PortalLayout from '@/layouts/PortalLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Card from '@/components/ui/Card.vue'
import CardContent from '@/components/ui/CardContent.vue'

defineOptions({ layout: PortalLayout })

const { t } = useI18n()

const props = defineProps<{
  paymentId: string
  amountLabel: string
  order: { id: string; order_number: string; url: string }
  payUrl: string
}>()

const form = useForm({})
</script>

<template>
  <PageHeader :title="t('payments.fake.title')" :subtitle="t('payments.fake.subtitle')" />

  <Card class="max-w-md">
    <CardContent class="space-y-4 pt-6">
      <div class="flex justify-between text-sm">
        <span class="text-muted-foreground">{{ t('payments.fake.orderNumber') }}</span>
        <span>{{ order.order_number }}</span>
      </div>
      <div class="flex justify-between text-sm">
        <span class="text-muted-foreground">{{ t('payments.fake.amount') }}</span>
        <span class="font-medium">{{ amountLabel }}</span>
      </div>
      <p class="text-xs text-muted-foreground">
        {{ t('payments.fake.hint') }}
      </p>
      <div class="flex gap-3">
        <Button type="button" :disabled="form.processing" @click="form.post(payUrl)">{{ t('payments.fake.confirm') }}</Button>
        <Button as-child variant="outline">
          <Link :href="order.url">{{ t('payments.fake.backToOrder') }}</Link>
        </Button>
      </div>
    </CardContent>
  </Card>
</template>
