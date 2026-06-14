<script setup lang="ts">
import { Link } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Badge from '@/components/ui/Badge.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

defineProps<{
  tags: Array<{
    name: string
    slug: string
    topics_count: number
    url: string
  }>
}>()

function tagSize(count: number) {
  if (count >= 20) return 'text-lg'
  if (count >= 10) return 'text-base'
  if (count >= 5) return 'text-sm'
  return 'text-xs'
}
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '论坛', href: routes.forum },
    { label: '标签', current: true },
  ]" />

  <PageHeader title="标签云" subtitle="按使用频率浏览标签" />

  <div v-if="tags.length" class="flex flex-wrap gap-3">
    <Link
      v-for="tag in tags"
      :key="tag.slug"
      :href="tag.url"
      class="inline-flex items-center gap-1 rounded-full border px-3 py-1 hover:bg-muted"
      :class="tagSize(tag.topics_count)"
    >
      #{{ tag.name }}
      <Badge variant="secondary" class="text-[10px]">{{ tag.topics_count }}</Badge>
    </Link>
  </div>
  <p v-else class="rounded-lg border border-dashed p-8 text-center text-sm text-muted-foreground">
    暂无标签。
  </p>
</template>
