<script setup lang="ts">
import { Link } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Card from '@/components/ui/Card.vue'
import CardContent from '@/components/ui/CardContent.vue'
import { adminRoutes } from '@/lib/adminRoutes'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

defineProps<{
  fulfillment: {
    id: number
    delivery_id: string
    status: string
    order_number: string
    product_name: string
    attempts_count: number
    last_error: string | null
  }
}>()
</script>

<template>
  <PageHeader :title="t('admin.fulfillments.title', { id: fulfillment.delivery_id })" />

  <Card class="mb-6 max-w-2xl">
    <CardContent class="space-y-3 pt-6 text-sm">
      <div class="flex justify-between"><span class="text-muted-foreground">{{ t('admin.common.status') }}</span><span>{{ fulfillment.status }}</span></div>
      <div class="flex justify-between"><span class="text-muted-foreground">{{ t('admin.common.order') }}</span><span>{{ fulfillment.order_number }}</span></div>
      <div class="flex justify-between"><span class="text-muted-foreground">{{ t('admin.common.product') }}</span><span>{{ fulfillment.product_name }}</span></div>
      <div class="flex justify-between"><span class="text-muted-foreground">{{ t('admin.fulfillments.attempts') }}</span><span>{{ fulfillment.attempts_count }}</span></div>
      <div v-if="fulfillment.last_error" class="text-destructive">{{ fulfillment.last_error }}</div>
    </CardContent>
  </Card>

  <div class="flex gap-3">
    <template v-if="fulfillment.status === 'pending' || fulfillment.status === 'failed'">
      <Button as-child>
        <Link
          :href="adminRoutes.storeFulfillment(fulfillment.id)"
          method="patch"
          as="button"
          :data="{ retry: '1' }"
        >
          {{ t('admin.fulfillments.retry') }}
        </Link>
      </Button>
    </template>
    <Button as-child variant="outline">
      <Link :href="adminRoutes.storeFulfillments">{{ t('admin.ui.back') }}</Link>
    </Button>
  </div>
</template>
