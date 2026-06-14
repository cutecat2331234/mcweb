<script setup lang="ts">
import { Link, router } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

defineProps<{
  topicMutes: Array<{
    id: number
    title: string
    topic_url: string
    section_name: string
    muted_at: string
    unmute_url: string
  }>
  sectionMutes: Array<{
    id: number
    name: string
    section_url: string
    muted_at: string
    unmute_url: string
  }>
}>()

function unmute(url: string) {
  router.post(url, {}, { preserveScroll: true })
}
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '论坛', href: routes.forum },
    { label: '静音列表', current: true },
  ]" />

  <PageHeader title="静音列表" subtitle="管理你已静音的主题与分区通知" />

  <section v-if="topicMutes.length" class="mb-8">
    <h2 class="mb-3 text-sm font-semibold">静音主题</h2>
    <div class="divide-y rounded-lg border">
      <div v-for="item in topicMutes" :key="item.id" class="flex items-center justify-between gap-4 p-4">
        <div>
          <Link :href="item.topic_url" class="font-medium hover:underline">{{ item.title }}</Link>
          <p class="text-xs text-muted-foreground">{{ item.section_name }} · 静音于 {{ item.muted_at }}</p>
        </div>
        <Button type="button" variant="outline" size="sm" @click="unmute(item.unmute_url)">取消静音</Button>
      </div>
    </div>
  </section>

  <section v-if="sectionMutes.length">
    <h2 class="mb-3 text-sm font-semibold">静音分区</h2>
    <div class="divide-y rounded-lg border">
      <div v-for="item in sectionMutes" :key="item.id" class="flex items-center justify-between gap-4 p-4">
        <div>
          <Link :href="item.section_url" class="font-medium hover:underline">{{ item.name }}</Link>
          <p class="text-xs text-muted-foreground">静音于 {{ item.muted_at }}</p>
        </div>
        <Button type="button" variant="outline" size="sm" @click="unmute(item.unmute_url)">取消静音</Button>
      </div>
    </div>
  </section>

  <p v-if="!topicMutes.length && !sectionMutes.length" class="text-sm text-muted-foreground">暂无静音项。</p>
</template>
