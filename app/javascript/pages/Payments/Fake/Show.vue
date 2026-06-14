<script setup lang="ts">
import { Link, useForm } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Card from '@/components/ui/Card.vue'
import CardContent from '@/components/ui/CardContent.vue'

defineOptions({ layout: PortalLayout })

const props = defineProps<{
  paymentId: string
  amountLabel: string
  order: { id: string; order_number: string; url: string }
  payUrl: string
}>()

const form = useForm({})
</script>

<template>
  <PageHeader title="模拟支付" subtitle="开发环境测试支付" />

  <Card class="max-w-md">
    <CardContent class="space-y-4 pt-6">
      <div class="flex justify-between text-sm">
        <span class="text-muted-foreground">订单号</span>
        <span>{{ order.order_number }}</span>
      </div>
      <div class="flex justify-between text-sm">
        <span class="text-muted-foreground">支付金额</span>
        <span class="font-medium">{{ amountLabel }}</span>
      </div>
      <p class="text-xs text-muted-foreground">
        这是 Fake 支付提供商的测试页面。点击下方按钮将立即完成支付并触发发货流程。
      </p>
      <div class="flex gap-3">
        <Button type="button" :disabled="form.processing" @click="form.post(payUrl)">确认支付</Button>
        <Button as-child variant="outline">
          <Link :href="order.url">返回订单</Link>
        </Button>
      </div>
    </CardContent>
  </Card>
</template>
