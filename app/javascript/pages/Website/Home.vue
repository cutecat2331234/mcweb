<script setup lang="ts">
import { Link } from '@inertiajs/vue3'
import WebsiteLayout from '@/layouts/WebsiteLayout.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: WebsiteLayout })

export interface FeaturedArticle {
  id: string
  title: string
  slug: string
  excerpt: string | null
  published_at: string | null
}

defineProps<{
  featuredArticles: FeaturedArticle[]
}>()

const features = [
  {
    title: '社区论坛',
    description: '分区讨论、话题追踪、搜索与举报，构建活跃玩家社区。',
  },
  {
    title: '数字商城',
    description: '商品上架、购物车、支付与 Minecraft 自动发货一体化。',
  },
  {
    title: '账号与安全',
    description: '注册登录、2FA、会话管理与权限角色，保障运营安全。',
  },
]
</script>

<template>
  <section class="relative overflow-hidden px-4 py-28 text-center">
    <div class="website-float mx-auto mb-8 flex h-16 w-16 items-center justify-center rounded-2xl border border-sky-400/30 bg-sky-400/10 text-2xl">
      ⛏
    </div>
    <h1 class="website-hero-title text-5xl font-bold tracking-tight md:text-6xl">
      为你的 Minecraft 服务器打造官网
    </h1>
    <p class="mx-auto mt-6 max-w-2xl text-lg text-slate-300">
      Mcweb 将营销官网、玩家社区与数字商城整合在同一套 Rails 应用中 —— 对外是品牌官网，对内是高效运营后台。
    </p>
    <div class="mt-10 flex flex-wrap items-center justify-center gap-4">
      <Link :href="routes.forum" class="website-btn website-btn-primary">进入论坛</Link>
      <Link :href="routes.store" class="website-btn website-btn-ghost">浏览商城</Link>
    </div>
  </section>

  <section class="mx-auto max-w-5xl px-4 py-20">
    <h2 class="mb-10 text-center text-3xl font-semibold">一站式服主工具箱</h2>
    <div class="grid gap-6 md:grid-cols-3">
      <article v-for="feature in features" :key="feature.title" class="website-card text-left">
        <h3 class="mb-2 text-lg font-semibold">{{ feature.title }}</h3>
        <p class="text-sm text-slate-300">{{ feature.description }}</p>
      </article>
    </div>
  </section>

  <section v-if="featuredArticles.length" class="mx-auto max-w-5xl px-4 pb-24">
    <h2 class="mb-8 text-2xl font-semibold">最新动态</h2>
    <div class="grid gap-4 md:grid-cols-2">
      <article
        v-for="article in featuredArticles"
        :key="article.id"
        class="website-card text-left"
      >
        <h3 class="font-semibold">{{ article.title }}</h3>
        <p v-if="article.excerpt" class="mt-2 text-sm text-slate-300">{{ article.excerpt }}</p>
      </article>
    </div>
  </section>
</template>
