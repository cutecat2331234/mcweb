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

const features = [
  {
    icon: '💬',
    title: '社区论坛',
    description: '分区讨论、话题追踪、私信与举报审核，让玩家在社区里自然留存。',
  },
  {
    icon: '🛒',
    title: '数字商城',
    description: '商品上架、购物车、支付回调与 Minecraft 自动发货，变现与运营一体化。',
  },
  {
    icon: '🔐',
    title: '账号与安全',
    description: '注册登录、邮箱验证、2FA 与细粒度权限，为服主团队提供可靠后台。',
  },
]

const stats = [
  { value: '3 合 1', label: '官网 · 论坛 · 商城' },
  { value: '/app', label: '独立用户应用模块' },
  { value: 'Rails 8', label: '现代全栈架构' },
]
</script>

<template>
  <section class="website-hero relative px-4 pb-8 pt-24 text-center md:pt-28">
    <div class="website-hero-badge mx-auto mb-6">
      <span class="inline-block h-2 w-2 rounded-full bg-sky-400" />
      开源 Minecraft 服主官网系统
    </div>
    <div class="website-float mx-auto mb-8 flex h-20 w-20 items-center justify-center rounded-2xl border border-sky-400/30 bg-sky-400/10 text-3xl shadow-lg shadow-sky-500/10">
      ⛏
    </div>
    <h1 class="website-hero-title mx-auto max-w-4xl text-5xl font-bold tracking-tight md:text-6xl lg:text-7xl">
      为你的服务器打造专业官网
    </h1>
    <p class="mx-auto mt-6 max-w-2xl text-lg leading-relaxed text-slate-300 md:text-xl">
      对外是品牌官网与内容页面，对内是论坛、商城与用户中心。
      玩家功能统一在 <span class="font-medium text-sky-300">/app</span> 模块，官网则使用简洁的 <span class="font-medium text-violet-300">/home</span>、<span class="font-medium text-violet-300">/about</span> 等路径。
    </p>
    <div class="mt-10 flex flex-wrap items-center justify-center gap-4">
      <Link :href="routes.forum" class="website-btn website-btn-primary">进入应用中心</Link>
      <Link :href="routes.page('about')" class="website-btn website-btn-ghost">了解我们</Link>
    </div>
  </section>

  <section class="mx-auto max-w-5xl px-4 py-8">
    <div class="grid gap-4 rounded-2xl border border-white/10 bg-white/[0.03] p-2 md:grid-cols-3">
      <div v-for="stat in stats" :key="stat.label" class="website-stat">
        <div class="website-stat-value">{{ stat.value }}</div>
        <div class="website-stat-label">{{ stat.label }}</div>
      </div>
    </div>
  </section>

  <section class="mx-auto max-w-5xl px-4 py-20">
    <div class="mb-12 text-center">
      <h2 class="website-section-title">一站式服主工具箱</h2>
      <p class="website-section-subtitle mt-3">
        从吸引新玩家到社区运营与付费转化，McWeb 把关键能力整合在同一套系统中。
      </p>
    </div>
    <div class="grid gap-6 md:grid-cols-3">
      <article v-for="feature in features" :key="feature.title" class="website-card text-left">
        <div class="website-card-icon">{{ feature.icon }}</div>
        <h3 class="mb-2 text-lg font-semibold">{{ feature.title }}</h3>
        <p class="text-sm leading-relaxed text-slate-300">{{ feature.description }}</p>
      </article>
    </div>
  </section>

  <section v-if="featuredProducts.length" class="mx-auto max-w-5xl px-4 pb-12">
    <div class="mb-8 flex items-end justify-between gap-4">
      <div>
        <h2 class="website-section-title text-left !text-2xl">精选商品</h2>
        <p class="mt-1 text-sm text-slate-400">在应用中心商城浏览完整目录</p>
      </div>
      <Link :href="routes.store" class="text-sm text-sky-300 hover:underline">浏览全部 →</Link>
    </div>
    <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
      <Link
        v-for="product in featuredProducts"
        :key="product.id"
        :href="product.url"
        class="website-card group text-left no-underline"
      >
        <div v-if="product.image_url" class="mb-4 overflow-hidden rounded-xl">
          <img :src="product.image_url" :alt="product.name" class="h-40 w-full object-cover transition-transform duration-300 group-hover:scale-105" />
        </div>
        <div v-else class="mb-4 flex h-40 items-center justify-center rounded-xl bg-slate-800/50 text-3xl">🎁</div>
        <h3 class="font-semibold text-white">{{ product.name }}</h3>
        <p class="mt-1 text-sm text-slate-300">{{ product.price_label }}</p>
        <p v-if="product.average_rating" class="mt-2 text-xs text-amber-300">★ {{ product.average_rating }}</p>
      </Link>
    </div>
  </section>

  <section v-if="featuredArticles.length" class="mx-auto max-w-5xl px-4 pb-16">
    <div class="mb-8">
      <h2 class="website-section-title text-left !text-2xl">最新动态</h2>
      <p class="mt-1 text-sm text-slate-400">公告、更新与活动资讯</p>
    </div>
    <div class="grid gap-4 md:grid-cols-2">
      <Link
        v-for="article in featuredArticles"
        :key="article.id"
        :href="routes.blogArticle(article.slug)"
        class="website-card block text-left no-underline"
      >
        <h3 class="font-semibold text-white">{{ article.title }}</h3>
        <p v-if="article.excerpt" class="mt-2 line-clamp-2 text-sm text-slate-300">{{ article.excerpt }}</p>
        <p v-if="article.published_at" class="mt-3 text-xs text-slate-500">{{ article.published_at }}</p>
      </Link>
    </div>
  </section>

  <section class="mx-auto max-w-4xl px-4 pb-24">
    <div class="website-cta-band">
      <h2 class="text-2xl font-bold md:text-3xl">准备好上线你的服务器官网了吗？</h2>
      <p class="mx-auto mt-3 max-w-xl text-slate-300">
        立即进入应用中心，体验论坛与商城；或通过后台自定义 /home、/about 等官网页面。
      </p>
      <div class="mt-8 flex flex-wrap justify-center gap-4">
        <Link :href="routes.register" class="website-btn website-btn-primary">免费注册</Link>
        <Link :href="routes.blog" class="website-btn website-btn-ghost">查看公告</Link>
      </div>
    </div>
  </section>
</template>
