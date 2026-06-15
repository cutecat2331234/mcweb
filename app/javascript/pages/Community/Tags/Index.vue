<script setup lang="ts">
import { Link } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Badge from '@/components/ui/Badge.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

interface TagItem {
  name: string
  slug: string
  topics_count: number
  url: string
  color_hex?: string | null
}

defineProps<{
  tagGroups?: Array<{
    name: string
    slug: string
    color_hex?: string | null
    tags: TagItem[]
  }>
  ungroupedTags?: TagItem[]
  tags?: TagItem[]
}>()

function tagSize(count: number) {
  if (count >= 20) return 'text-lg'
  if (count >= 10) return 'text-base'
  if (count >= 5) return 'text-sm'
  return 'text-xs'
}

function tagStyle(tag: TagItem) {
  return tag.color_hex ? { borderColor: tag.color_hex, color: tag.color_hex } : undefined
}
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '论坛', href: routes.forum },
    { label: '标签', current: true },
  ]" />

  <PageHeader title="标签云" subtitle="按标签组与使用频率浏览" />

  <div v-if="tagGroups?.length" class="mb-8 space-y-6">
    <section v-for="group in tagGroups" :key="group.slug">
      <div class="mb-2 flex items-center gap-2">
        <span v-if="group.color_hex" class="h-3 w-3 rounded-full" :style="{ backgroundColor: group.color_hex }" />
        <h2 class="text-sm font-semibold">{{ group.name }}</h2>
      </div>
      <div class="flex flex-wrap gap-3">
        <Link
          v-for="tag in group.tags"
          :key="tag.slug"
          :href="tag.url"
          class="inline-flex items-center gap-1 rounded-full border px-3 py-1 hover:bg-muted"
          :class="tagSize(tag.topics_count)"
          :style="tagStyle(tag)"
        >
          #{{ tag.name }}
          <Badge variant="secondary" class="text-[10px]">{{ tag.topics_count }}</Badge>
        </Link>
      </div>
    </section>
  </div>

  <section v-if="ungroupedTags?.length">
    <h2 v-if="tagGroups?.length" class="mb-2 text-sm font-semibold">其他标签</h2>
    <div class="flex flex-wrap gap-3">
      <Link
        v-for="tag in ungroupedTags"
        :key="tag.slug"
        :href="tag.url"
        class="inline-flex items-center gap-1 rounded-full border px-3 py-1 hover:bg-muted"
        :class="tagSize(tag.topics_count)"
        :style="tagStyle(tag)"
      >
        #{{ tag.name }}
        <Badge variant="secondary" class="text-[10px]">{{ tag.topics_count }}</Badge>
      </Link>
    </div>
  </section>

  <div v-else-if="tags?.length" class="flex flex-wrap gap-3">
    <Link
      v-for="tag in tags"
      :key="tag.slug"
      :href="tag.url"
      class="inline-flex items-center gap-1 rounded-full border px-3 py-1 hover:bg-muted"
      :class="tagSize(tag.topics_count)"
      :style="tagStyle(tag)"
    >
      #{{ tag.name }}
      <Badge variant="secondary" class="text-[10px]">{{ tag.topics_count }}</Badge>
    </Link>
  </div>

  <p v-else-if="!tagGroups?.length && !ungroupedTags?.length" class="rounded-lg border border-dashed p-8 text-center text-sm text-muted-foreground">
    暂无标签。
  </p>
</template>
