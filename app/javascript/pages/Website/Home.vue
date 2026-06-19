<script setup lang="ts">
import { computed } from 'vue'
import { Link } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import WebsiteLayout from '@/layouts/WebsiteLayout.vue'
import { routes } from '@/lib/routes'
import { useFeatureFlags } from '@/lib/useFeatureFlags'

defineOptions({ layout: WebsiteLayout })

const { t } = useI18n()

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

const allFeatures = computed(() => [
  {
    id: 'forum' as const,
    icon: '💬',
    title: t('website.home.forumTitle'),
    description: t('website.home.forumDesc'),
  },
  {
    id: 'store' as const,
    icon: '🛒',
    title: t('website.home.storeTitle'),
    description: t('website.home.storeDesc'),
  },
  {
    id: 'identity' as const,
    icon: '🔐',
    title: t('website.home.identityTitle'),
    description: t('website.home.identityDesc'),
  },
])

const visibleFeatures = computed(() =>
  allFeatures.value.filter((feature) => {
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

const stats = computed(() => [
  { value: t('website.home.stat1Value'), label: t('website.home.stat1Label') },
  { value: t('website.home.stat2Value'), label: t('website.home.stat2Label') },
  { value: t('website.home.stat3Value'), label: t('website.home.stat3Label') },
])
</script>

<template>
  <section class="website-hero relative overflow-hidden px-4 pb-12 pt-28 text-center md:pt-36">
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
      {{ t('website.home.badge') }}
    </div>

    <div class="website-float mx-auto mb-10 flex h-24 w-24 items-center justify-center rounded-2xl border border-green-500/30 bg-green-500/10 text-5xl shadow-2xl shadow-green-500/20">
      ⛏
    </div>

    <h1 class="website-hero-title mx-auto max-w-4xl text-5xl font-black tracking-tight leading-none md:text-7xl lg:text-8xl">
      {{ t('website.home.heroLine1') }}<br>
      <span class="shimmer-text">{{ t('website.home.heroLine2') }}</span><br>
      {{ t('website.home.heroLine3') }}
    </h1>
    <p class="mx-auto mt-8 max-w-2xl text-lg leading-relaxed text-slate-300 md:text-xl">
      {{ t('website.home.heroDesc') }}
    </p>

    <div class="mt-12 flex flex-wrap items-center justify-center gap-4">
      <Link :href="appEntryHref" class="website-btn website-btn-primary text-base">
        {{ t('website.home.enterApp') }}
      </Link>
      <Link :href="routes.page('about')" class="website-btn website-btn-ghost text-base">
        {{ t('website.home.learnMore') }}
      </Link>
    </div>

    <div class="mx-auto mt-16 max-w-3xl">
      <div class="grid grid-cols-3 gap-px overflow-hidden rounded-2xl border border-green-500/20 bg-green-500/10">
        <div v-for="stat in stats" :key="stat.label" class="website-stat bg-[#030a03]/80 py-6">
          <div class="website-stat-value">{{ stat.value }}</div>
          <div class="website-stat-label">{{ stat.label }}</div>
        </div>
      </div>
    </div>
  </section>

  <section class="mx-auto max-w-6xl px-4 py-24">
    <div class="mb-16 text-center">
      <p class="mb-3 text-xs font-bold uppercase tracking-[0.3em] text-green-400">{{ t('website.home.featuresLabel') }}</p>
      <h2 class="website-section-title">{{ t('website.home.featuresTitle') }}</h2>
      <p class="website-section-subtitle mt-4">
        {{ t('website.home.featuresSubtitle') }}
      </p>
    </div>
    <div :class="featureGridClass">
      <article
        v-for="feature in visibleFeatures"
        :key="feature.title"
        class="website-card group relative overflow-hidden text-left"
      >
        <div class="absolute -right-8 -top-8 h-32 w-32 rounded-full bg-green-500/5 blur-2xl transition-all group-hover:bg-green-500/10" />
        <div class="website-card-icon relative z-10">{{ feature.icon }}</div>
        <h3 class="relative z-10 mb-2 text-lg font-bold text-white">{{ feature.title }}</h3>
        <p class="relative z-10 text-sm leading-relaxed text-slate-400">{{ feature.description }}</p>
      </article>
    </div>
  </section>

  <section v-if="features.store && featuredProducts.length" class="mx-auto max-w-6xl px-4 pb-16">
    <div class="mb-10 flex items-end justify-between gap-4">
      <div>
        <p class="mb-1 text-xs font-bold uppercase tracking-[0.3em] text-green-400">{{ t('website.home.storeSection') }}</p>
        <h2 class="website-section-title text-left text-2xl font-bold">{{ t('website.home.featuredProducts') }}</h2>
      </div>
      <Link :href="routes.store" class="text-sm text-green-400 transition-colors hover:text-green-300">
        {{ t('website.home.allProducts') }}
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

  <section v-if="features.website_blog && featuredArticles.length" class="mx-auto max-w-6xl px-4 pb-20">
    <div class="mb-10">
      <p class="mb-1 text-xs font-bold uppercase tracking-[0.3em] text-green-400">{{ t('website.home.announcements') }}</p>
      <h2 class="website-section-title text-left text-2xl font-bold">{{ t('website.home.latestNews') }}</h2>
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

  <section class="mx-auto max-w-5xl px-4 pb-28">
    <div class="website-cta-band scan-effect relative">
      <div class="pointer-events-none absolute inset-0 overflow-hidden rounded-[inherit]">
        <div class="absolute -left-20 -top-20 h-64 w-64 rounded-full bg-green-500/8 blur-3xl" />
        <div class="absolute -bottom-20 -right-20 h-48 w-48 rounded-full bg-purple-500/8 blur-3xl" />
      </div>
      <div class="relative">
        <p class="mb-3 text-xs font-bold uppercase tracking-[0.3em] text-green-400">{{ t('website.home.ctaLabel') }}</p>
        <h2 class="text-3xl font-black tracking-tight md:text-4xl">{{ t('website.home.ctaTitle') }}</h2>
        <p class="mx-auto mt-4 max-w-xl text-slate-300">
          {{ t('website.home.ctaDesc') }}
        </p>
        <div class="mt-10 flex flex-wrap justify-center gap-4">
          <Link :href="routes.register" class="website-btn website-btn-primary text-base">{{ t('website.home.registerFree') }}</Link>
          <Link v-if="features.website_blog" :href="routes.blog" class="website-btn website-btn-ghost text-base">{{ t('website.home.viewAnnouncements') }}</Link>
        </div>
      </div>
    </div>
  </section>
</template>
