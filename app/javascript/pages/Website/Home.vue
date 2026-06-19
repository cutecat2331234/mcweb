<script setup lang="ts">
import { computed } from 'vue'
import { Link } from '@inertiajs/vue3'
import WebsiteLayout from '@/layouts/WebsiteLayout.vue'
import { routes } from '@/lib/routes'
import { useFeatureFlags } from '@/lib/useFeatureFlags'

defineOptions({ layout: WebsiteLayout })

export interface FeaturedArticle {
  id: string
  title: string
  slug: string
  excerpt: string | null
  published_at: string | null
}

export interface FeaturedProduct {
  id: string
  name: string
  price_label: string
  image_url: string | null
  url: string
  average_rating?: number | null
}

defineProps<{
  featuredArticles: FeaturedArticle[]
  featuredProducts: FeaturedProduct[]
}>()

const { features } = useFeatureFlags()

const allFeatures = [
  {
    id: 'forum',
    icon: '💬',
    title: '社区论坛',
    description: '分区讨论、话题追踪、私信与举报审核，让玩家在社区里自然留存。',
  },
  {
    id: 'store',
    icon: '🛒',
    title: '数字商城',
    description: '商品上架、购物车、支付回调与 Minecraft 自动发货，变现与运营一体化。',
  },
  {
    id: 'identity',
    icon: '🔐',
    title: '账号与安全',
    description: '注册登录、邮箱验证、2FA 与细粒度权限，为服主团队提供可靠后台。',
  },
] as const

const visibleFeatures = computed(() =>
  allFeatures.filter((feature) => {
    if (feature.id === 'forum') return features.value.forum
    if (feature.id === 'store') return features.value.store
    return true
  }),
)

const featureGridClass = computed(() => {
  const count = visibleFeatures.value.length
  if (count <= 1) return 'grid gap-6 md:grid-cols-1 max-w-xl mx-auto'
  if (count === 2) return 'grid gap-6 md:grid-cols-2'
  return 'grid gap-6 md:grid-cols-3'
})

const appEntryHref = computed(() => {
  if (features.value.forum) return routes.forum
  if (features.value.store) return routes.store
  return routes.signIn
})

const stats = [
  { value: '3 合 1', label: '官网 · 论坛 · 商城' },
  { value: '/app', label: '独立用户应用模块' },
  { value: 'Rails 8', label: '现代全栈架构' },
]
</script>

<template>
  <!-- Hero -->
  <section class="website-hero relative overflow-hidden px-4 pb-12 pt-28 text-center md:pt-36">
    <!-- 背景装饰：像素方块散点 -->
    <div class="pointer-events-none absolute inset-0 overflow-hidden">
      <div class="absolute top-20 left-[10%] h-3 w-3 rounded-sm bg-green-500/20 rotate-12" />
      <div class="absolute top-32 right-[15%] h-2 w-2 rounded-sm bg-purple-500/20 -rotate-12" />
      <div class="absolute top-48 left-[25%] h-4 w-4 rounded-sm bg-yellow-500/10 rotate-45" />
      <div class="absolute top-24 right-[30%] h-2 w-2 bg-green-400/15" />
      <div class="absolute bottom-20 left-[20%] h-3 w-3 rounded-sm bg-purple-400/15 rotate-6" />
      <div class="absolute bottom-32 right-[25%] h-2 w-2 bg-green-500/20" />
    </div>

    <div class="website-hero-badge mx-auto mb-8">
      <span class="relative flex h-2 w-2">
        <span class="absolute inline-flex h-full w-full animate-ping rounded-full bg-green-400 opacity-75" />
        <span class="relative inline-flex h-2 w-2 rounded-full bg-green-500" />
      </span>
      开源 Minecraft 服主管理系统
    </div>

    <!-- 超大 Minecraft 图标，像素风 -->
    <div class="website-float mx-auto mb-10 flex h-24 w-24 items-center justify-center rounded-2xl border border-green-500/30 bg-green-500/10 text-5xl shadow-2xl shadow-green-500/20">
      ⛏
    </div>

    <h1 class="website-hero-title mx-auto max-w-4xl text-5xl font-black tracking-tight leading-none md:text-7xl lg:text-8xl">
      为你的<br>
      <span class="shimmer-text">服务器</span><br>
      打造官网
    </h1>
    <p class="mx-auto mt-8 max-w-2xl text-lg leading-relaxed text-slate-300 md:text-xl">
      论坛 · 商城 · 账号系统，三合一。
      玩家统一入口 <code class="rounded-md bg-green-900/40 px-2 py-0.5 text-green-300 text-sm font-mono">/app</code>，官网管理员自由定制。
    </p>

    <div class="mt-12 flex flex-wrap items-center justify-center gap-4">
      <Link :href="appEntryHref" class="website-btn website-btn-primary text-base">
        进入应用中心 →
      </Link>
      <Link :href="routes.page('about')" class="website-btn website-btn-ghost text-base">
        了解更多
      </Link>
    </div>

    <!-- 数据统计条带 -->
    <div class="mx-auto mt-16 max-w-3xl">
      <div class="grid grid-cols-3 gap-px overflow-hidden rounded-2xl border border-green-500/20 bg-green-500/10">
        <div v-for="stat in stats" :key="stat.label" class="website-stat bg-[#030a03]/80 py-6">
          <div class="website-stat-value">{{ stat.value }}</div>
          <div class="website-stat-label">{{ stat.label }}</div>
        </div>
      </div>
    </div>
  </section>

  <!-- 功能特性 -->
  <section class="mx-auto max-w-6xl px-4 py-24">
    <div class="mb-16 text-center">
      <p class="mb-3 text-xs font-bold uppercase tracking-[0.3em] text-green-400">核心功能</p>
      <h2 class="website-section-title">一站式服主工具箱</h2>
      <p class="website-section-subtitle mt-4">
        从吸引新玩家到社区运营与付费转化，McWeb 把关键能力整合在同一套系统中。
      </p>
    </div>
    <div :class="featureGridClass">
      <article
        v-for="feature in visibleFeatures"
        :key="feature.title"
        class="website-card group relative overflow-hidden text-left"
      >
        <!-- 装饰光效 -->
        <div class="absolute -right-8 -top-8 h-32 w-32 rounded-full bg-green-500/5 blur-2xl transition-all group-hover:bg-green-500/10" />
        <div class="website-card-icon relative z-10">{{ feature.icon }}</div>
        <h3 class="relative z-10 mb-2 text-lg font-bold text-white">{{ feature.title }}</h3>
        <p class="relative z-10 text-sm leading-relaxed text-slate-400">{{ feature.description }}</p>
      </article>
    </div>
  </section>

  <!-- 精选商品 -->
  <section v-if="features.store && featuredProducts.length" class="mx-auto max-w-6xl px-4 pb-16">
    <div class="mb-10 flex items-end justify-between gap-4">
      <div>
        <p class="mb-1 text-xs font-bold uppercase tracking-[0.3em] text-green-400">商城</p>
        <h2 class="website-section-title text-left text-2xl font-bold">精选商品</h2>
      </div>
      <Link :href="routes.store" class="text-sm text-green-400 transition-colors hover:text-green-300">
        全部商品 →
      </Link>
    </div>
    <div class="grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
      <Link
        v-for="product in featuredProducts"
        :key="product.id"
        :href="product.url"
        class="website-card group block text-left no-underline"
      >
        <div v-if="product.image_url" class="mb-4 overflow-hidden rounded-xl">
          <img
            :src="product.image_url"
            :alt="product.name"
            class="h-44 w-full object-cover transition-transform duration-500 group-hover:scale-110"
          >
        </div>
        <div v-else class="mb-4 flex h-44 items-center justify-center rounded-xl border border-green-500/10 bg-green-900/20 text-4xl">🎁</div>
        <h3 class="font-bold text-white">{{ product.name }}</h3>
        <div class="mt-2 flex items-center justify-between">
          <p class="text-sm font-medium text-green-400">{{ product.price_label }}</p>
          <p v-if="product.average_rating" class="text-xs text-amber-400">★ {{ product.average_rating }}</p>
        </div>
      </Link>
    </div>
  </section>

  <!-- 最新动态 -->
  <section v-if="features.website_blog && featuredArticles.length" class="mx-auto max-w-6xl px-4 pb-20">
    <div class="mb-10">
      <p class="mb-1 text-xs font-bold uppercase tracking-[0.3em] text-green-400">公告</p>
      <h2 class="website-section-title text-left text-2xl font-bold">最新动态</h2>
    </div>
    <div class="grid gap-5 md:grid-cols-2">
      <Link
        v-for="article in featuredArticles"
        :key="article.id"
        :href="routes.blogArticle(article.slug)"
        class="website-card group block text-left no-underline"
      >
        <div class="flex items-start gap-4">
          <div class="mt-1 flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-green-500/15 text-sm text-green-400 transition-colors group-hover:bg-green-500/25">
            📢
          </div>
          <div>
            <h3 class="font-bold text-white transition-colors group-hover:text-green-100">{{ article.title }}</h3>
            <p v-if="article.excerpt" class="mt-2 line-clamp-2 text-sm text-slate-400">{{ article.excerpt }}</p>
            <p v-if="article.published_at" class="mt-3 font-mono text-xs text-slate-500">{{ article.published_at }}</p>
          </div>
        </div>
      </Link>
    </div>
  </section>

  <!-- CTA -->
  <section class="mx-auto max-w-5xl px-4 pb-28">
    <div class="website-cta-band scan-effect relative">
      <div class="pointer-events-none absolute inset-0 overflow-hidden rounded-[inherit]">
        <div class="absolute -left-20 -top-20 h-64 w-64 rounded-full bg-green-500/8 blur-3xl" />
        <div class="absolute -bottom-20 -right-20 h-48 w-48 rounded-full bg-purple-500/8 blur-3xl" />
      </div>
      <div class="relative">
        <p class="mb-3 text-xs font-bold uppercase tracking-[0.3em] text-green-400">开始使用</p>
        <h2 class="text-3xl font-black tracking-tight md:text-4xl">准备好上线你的服务器官网了吗？</h2>
        <p class="mx-auto mt-4 max-w-xl text-slate-300">
          立即进入应用中心，体验论坛与商城；或通过后台自定义官网页面。
        </p>
        <div class="mt-10 flex flex-wrap justify-center gap-4">
          <Link :href="routes.register" class="website-btn website-btn-primary text-base">免费注册</Link>
          <Link v-if="features.website_blog" :href="routes.blog" class="website-btn website-btn-ghost text-base">查看公告</Link>
        </div>
      </div>
    </div>
  </section>
</template>
