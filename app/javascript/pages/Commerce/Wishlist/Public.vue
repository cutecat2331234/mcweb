<script setup lang="ts">
import { Link } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

defineProps<{
  owner: string
  products: Array<{
    id: string
    name: string
    price_label: string
    url: string
    saved_variant_name?: string | null
  }>
}>()
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '商城', href: routes.store },
    { label: '分享心愿单', current: true },
  ]" />

  <PageHeader :title="`${owner} 的心愿单`" subtitle="公开分享列表" />

  <div v-if="products.length" class="divide-y rounded-lg border">
    <div v-for="product in products" :key="product.id" class="flex items-center justify-between p-4">
      <div>
        <Link :href="product.url" class="font-medium hover:underline">{{ product.name }}</Link>
        <p class="text-sm text-muted-foreground">{{ product.price_label }}</p>
        <p v-if="product.saved_variant_name" class="text-xs text-muted-foreground">规格：{{ product.saved_variant_name }}</p>
      </div>
      <Button as-child variant="outline" size="sm">
        <Link :href="product.url">查看</Link>
      </Button>
    </div>
  </div>
  <p v-else class="rounded-lg border border-dashed p-8 text-center text-sm text-muted-foreground">
    心愿单是空的。
  </p>
</template>
