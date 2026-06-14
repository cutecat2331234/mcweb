<script setup lang="ts">
import { Link, router } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

defineProps<{
  tags: Array<{
    name: string
    slug: string
    description?: string | null
    url: string
    subscription_url: string
  }>
  tagTopicsUrl: string
}>()

function unsubscribe(url: string) {
  router.post(url)
}
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '论坛', href: routes.forum },
    { label: '关注标签', current: true },
  ]" />

  <div class="mb-4 flex items-center justify-between gap-3">
    <PageHeader title="关注的标签" subtitle="有新主题使用这些标签时会通知你" />
    <Button as-child variant="outline" size="sm">
      <Link :href="tagTopicsUrl">标签主题流</Link>
    </Button>
  </div>

  <div v-if="tags.length" class="space-y-3">
    <div v-for="tag in tags" :key="tag.slug" class="flex items-start justify-between gap-3 rounded-lg border p-4">
      <div>
        <Link :href="tag.url" class="font-medium hover:underline">#{{ tag.name }}</Link>
        <p v-if="tag.description" class="mt-1 text-sm text-muted-foreground">{{ tag.description }}</p>
      </div>
      <Button type="button" variant="outline" size="sm" @click="unsubscribe(tag.subscription_url)">取消关注</Button>
    </div>
  </div>
  <p v-else class="rounded-lg border border-dashed p-8 text-center text-sm text-muted-foreground">
    尚未关注任何标签。在标签页点击「关注此标签」即可订阅。
  </p>
</template>
