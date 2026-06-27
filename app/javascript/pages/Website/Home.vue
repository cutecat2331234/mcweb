<script setup lang="ts">
import { computed, onMounted, onBeforeUnmount, ref, nextTick } from 'vue'
import { Link } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import { gsap } from 'gsap'
import { ScrollTrigger } from 'gsap/ScrollTrigger'
import WebsiteLayout from '@/layouts/WebsiteLayout.vue'
import { routes } from '@/lib/routes'
import { useFeatureFlags } from '@/lib/useFeatureFlags'

gsap.registerPlugin(ScrollTrigger)

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
    glyph: '#',
    icon: '💬',
    title: t('website.home.forumTitle'),
    description: t('website.home.forumDesc'),
  },
  {
    id: 'store' as const,
    glyph: '$',
    icon: '🛒',
    title: t('website.home.storeTitle'),
    description: t('website.home.storeDesc'),
  },
  {
    id: 'identity' as const,
    glyph: '★',
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

const appEntryHref = computed(() => {
  if (features.value.forum) return routes.forum
  if (features.value.store) return routes.store
  return routes.signIn
})

// Stats: some values are pure numbers (count-up), others are tokens like "/app" or "Rails 8" (reveal as-is).
const stats = computed(() => [
  { value: t('website.home.stat1Value'), label: t('website.home.stat1Label') },
  { value: t('website.home.stat2Value'), label: t('website.home.stat2Label') },
  { value: t('website.home.stat3Value'), label: t('website.home.stat3Label') },
])

// Split hero headline into character "blocks" for staggered reveal.
function splitBlocks(text: string): string[] {
  return Array.from(text)
}
const heroLine1Blocks = computed(() => splitBlocks(t('website.home.heroLine1')))
const heroLine2Blocks = computed(() => splitBlocks(t('website.home.heroLine2')))
const heroLine3Blocks = computed(() => splitBlocks(t('website.home.heroLine3')))

// Floating isometric voxel cubes for the hero parallax field.
const heroCubes = [
  { x: 8, y: 22, s: 64, depth: 1.0, hue: 'a', rot: -14 },
  { x: 84, y: 18, s: 44, depth: 0.6, hue: 'b', rot: 12 },
  { x: 20, y: 70, s: 38, depth: 0.85, hue: 'a', rot: 24 },
  { x: 72, y: 64, s: 56, depth: 1.2, hue: 'c', rot: -8 },
  { x: 90, y: 78, s: 30, depth: 0.5, hue: 'a', rot: 18 },
  { x: 50, y: 12, s: 26, depth: 0.4, hue: 'b', rot: -22 },
  { x: 14, y: 44, s: 34, depth: 0.7, hue: 'c', rot: 10 },
  { x: 63, y: 86, s: 40, depth: 0.95, hue: 'a', rot: -16 },
]

const root = ref<HTMLElement | null>(null)
let ctx: gsap.Context | null = null
let mouseHandler: ((e: MouseEvent) => void) | null = null
const cleanups: Array<() => void> = []
const reduceMotion =
  typeof window !== 'undefined' &&
  window.matchMedia?.('(prefers-reduced-motion: reduce)').matches

onMounted(async () => {
  await nextTick()
  const el = root.value
  if (!el) return

  if (reduceMotion) {
    // Respect reduced-motion: ensure everything is visible, run no animation.
    gsap.set(el.querySelectorAll('[data-anim]'), { clearProps: 'all', opacity: 1, y: 0, scale: 1 })
    gsap.set(el.querySelectorAll('.hero-block'), { opacity: 1, y: 0, rotateX: 0 })
    return
  }

  ctx = gsap.context(() => {
    // --- Hero headline: blocks fall & assemble ---
    gsap.from('.hero-block', {
      yPercent: -120,
      opacity: 0,
      rotateX: -90,
      duration: 0.7,
      ease: 'back.out(1.7)',
      stagger: { each: 0.035, from: 'start' },
      delay: 0.15,
    })

    // --- Hero supporting elements ---
    gsap
      .timeline({ delay: 0.5 })
      .from('.hero-badge', { y: 16, opacity: 0, duration: 0.6, ease: 'power3.out' }, 0)
      .from('.hero-emblem', { scale: 0.4, opacity: 0, rotate: -45, duration: 0.8, ease: 'back.out(2)' }, 0)
      .from('.hero-desc', { y: 20, opacity: 0, duration: 0.7, ease: 'power3.out' }, 0.2)
      .from('.hero-cta > *', { y: 20, opacity: 0, duration: 0.6, ease: 'power3.out', stagger: 0.12 }, 0.35)

    // --- Floating voxel cubes: slow idle float + entrance ---
    gsap.utils.toArray<HTMLElement>('.hero-cube').forEach((cube, i) => {
      gsap.from(cube, { opacity: 0, scale: 0.3, duration: 1, ease: 'power2.out', delay: 0.3 + i * 0.05 })
      gsap.to(cube, {
        y: `+=${14 + (i % 3) * 8}`,
        x: `+=${(i % 2 ? 1 : -1) * (6 + (i % 3) * 4)}`,
        rotate: `+=${(i % 2 ? 1 : -1) * 8}`,
        duration: 4 + (i % 4),
        ease: 'sine.inOut',
        repeat: -1,
        yoyo: true,
      })
    })

    // --- Pixel dust particles drift ---
    gsap.utils.toArray<HTMLElement>('.dust').forEach((p, i) => {
      gsap.to(p, {
        y: '-=40',
        x: `+=${(i % 2 ? 1 : -1) * 18}`,
        opacity: 0,
        duration: 5 + (i % 5),
        ease: 'none',
        repeat: -1,
        delay: i * 0.4,
        repeatRefresh: true,
      })
    })

    // --- Mouse parallax on cubes + emblem ---
    const layers = gsap.utils.toArray<HTMLElement>('[data-parallax]')
    const qx = layers.map((l) => gsap.quickTo(l, 'xPercent', { duration: 0.8, ease: 'power3' }))
    const qy = layers.map((l) => gsap.quickTo(l, 'yPercent', { duration: 0.8, ease: 'power3' }))
    mouseHandler = (e: MouseEvent) => {
      const cx = (e.clientX / window.innerWidth - 0.5) * 2
      const cy = (e.clientY / window.innerHeight - 0.5) * 2
      layers.forEach((l, i) => {
        const depth = parseFloat(l.dataset.depth || '1')
        qx[i](cx * depth * 6)
        qy[i](cy * depth * 6)
      })
    }
    window.addEventListener('mousemove', mouseHandler, { passive: true })

    // --- Scrollytelling background: mine → surface → twilight ---
    // Driven by scrubbing CSS custom properties on the atmosphere layer.
    const atmo = el.querySelector('.atmosphere') as HTMLElement | null
    if (atmo) {
      gsap.to(atmo, {
        '--atmo': 1,
        ease: 'none',
        scrollTrigger: { trigger: el, start: 'top top', end: 'bottom bottom', scrub: 0.6 },
      })
    }

    // --- Grid floor perspective drift on scroll ---
    gsap.to('.grid-floor', {
      backgroundPositionY: '+=240px',
      ease: 'none',
      scrollTrigger: { trigger: el, start: 'top top', end: 'bottom bottom', scrub: true },
    })

    // --- Section reveals (staggered, asymmetric) ---
    gsap.utils.toArray<HTMLElement>('[data-reveal]').forEach((node) => {
      const children = node.querySelectorAll<HTMLElement>('[data-reveal-item]')
      const targets = children.length ? children : [node]
      gsap.from(targets, {
        y: 48,
        opacity: 0,
        duration: 0.8,
        ease: 'power3.out',
        stagger: 0.12,
        scrollTrigger: { trigger: node, start: 'top 82%' },
      })
    })

    // --- Parallax drift for section eyebrows / accents ---
    gsap.utils.toArray<HTMLElement>('[data-drift]').forEach((node) => {
      const amt = parseFloat(node.dataset.drift || '40')
      gsap.fromTo(
        node,
        { y: amt },
        {
          y: -amt,
          ease: 'none',
          scrollTrigger: { trigger: node, start: 'top bottom', end: 'bottom top', scrub: true },
        },
      )
    })

    // --- Count-up stats (only pure-number values) ---
    gsap.utils.toArray<HTMLElement>('.stat-num').forEach((node) => {
      const raw = node.dataset.value || ''
      const match = raw.match(/^(\d+)/)
      if (!match) return
      const target = parseInt(match[1], 10)
      const suffix = raw.slice(match[1].length)
      const obj = { n: 0 }
      gsap.to(obj, {
        n: target,
        duration: 1.6,
        ease: 'power2.out',
        scrollTrigger: { trigger: node, start: 'top 88%' },
        onUpdate: () => {
          node.textContent = Math.round(obj.n) + suffix
        },
      })
    })

    // --- Feature cards: 3D tilt on pointer move ---
    gsap.utils.toArray<HTMLElement>('.tilt-card').forEach((card) => {
      const onMove = (e: PointerEvent) => {
        const r = card.getBoundingClientRect()
        const px = (e.clientX - r.left) / r.width - 0.5
        const py = (e.clientY - r.top) / r.height - 0.5
        gsap.to(card, {
          rotateY: px * 10,
          rotateX: -py * 10,
          duration: 0.4,
          ease: 'power2.out',
          transformPerspective: 800,
        })
      }
      const onLeave = () => gsap.to(card, { rotateX: 0, rotateY: 0, duration: 0.6, ease: 'power3.out' })
      card.addEventListener('pointermove', onMove)
      card.addEventListener('pointerleave', onLeave)
      cleanups.push(() => {
        card.removeEventListener('pointermove', onMove)
        card.removeEventListener('pointerleave', onLeave)
      })
    })

    ScrollTrigger.refresh()
  }, el)
})

onBeforeUnmount(() => {
  if (mouseHandler) window.removeEventListener('mousemove', mouseHandler)
  mouseHandler = null
  cleanups.forEach((fn) => fn())
  cleanups.length = 0
  ScrollTrigger.getAll().forEach((t) => t.kill())
  ctx?.revert()
  ctx = null
})
</script>

<template>
  <div ref="root" class="voxel-home">
    <!-- Scroll-driven atmosphere: mine → surface → twilight -->
    <div class="atmosphere" aria-hidden="true" />
    <div class="grid-floor" aria-hidden="true" />

    <!-- ============ HERO ============ -->
    <section class="hero relative px-4 pb-24 pt-28 md:pt-36">
      <!-- Floating voxel cube field -->
      <div class="cube-field pointer-events-none absolute inset-0 overflow-hidden" aria-hidden="true">
        <span
          v-for="(c, i) in heroCubes"
          :key="`cube-${i}`"
          class="hero-cube"
          :class="`cube-${c.hue}`"
          data-parallax
          :data-depth="c.depth"
          :style="{
            left: `${c.x}%`,
            top: `${c.y}%`,
            '--cs': `${c.s}px`,
            '--cr': `${c.rot}deg`,
          }"
        />
        <!-- Pixel dust -->
        <span
          v-for="i in 24"
          :key="`dust-${i}`"
          class="dust"
          :style="{
            left: `${(i * 37) % 100}%`,
            top: `${(i * 53) % 100}%`,
            '--ds': `${2 + (i % 3)}px`,
          }"
        />
      </div>

      <div class="relative mx-auto max-w-5xl text-center">
        <div class="hero-badge mx-auto mb-8 inline-flex items-center gap-2">
          <span class="relative flex h-2 w-2">
            <span class="absolute inline-flex h-full w-full animate-ping rounded-full bg-green-400 opacity-75" />
            <span class="relative inline-flex h-2 w-2 rounded-full bg-green-500" />
          </span>
          {{ t('website.home.badge') }}
        </div>

        <div
          class="hero-emblem mx-auto mb-10 flex h-24 w-24 items-center justify-center text-5xl"
          data-parallax
          data-depth="1.6"
        >
          <span class="emblem-cube">⛏</span>
        </div>

        <h1 class="hero-title mx-auto max-w-4xl">
          <span class="hero-line line-a">
            <span v-for="(ch, i) in heroLine1Blocks" :key="`l1-${i}`" class="hero-block">{{ ch === ' ' ? ' ' : ch }}</span>
          </span>
          <span class="hero-line line-b">
            <span v-for="(ch, i) in heroLine2Blocks" :key="`l2-${i}`" class="hero-block accent">{{ ch === ' ' ? ' ' : ch }}</span>
          </span>
          <span class="hero-line line-c">
            <span v-for="(ch, i) in heroLine3Blocks" :key="`l3-${i}`" class="hero-block">{{ ch === ' ' ? ' ' : ch }}</span>
          </span>
        </h1>

        <p class="hero-desc mx-auto mt-8 max-w-2xl text-lg leading-relaxed text-emerald-100/70 md:text-xl">
          {{ t('website.home.heroDesc') }}
        </p>

        <div class="hero-cta mt-12 flex flex-wrap items-center justify-center gap-4">
          <Link :href="appEntryHref" class="website-btn website-btn-primary text-base">
            {{ t('website.home.enterApp') }}
          </Link>
          <Link :href="routes.page('about')" class="website-btn website-btn-ghost text-base">
            {{ t('website.home.learnMore') }}
          </Link>
        </div>
      </div>
    </section>

    <!-- ============ STATS ============ -->
    <section class="relative mx-auto max-w-5xl px-4 pb-24" data-reveal>
      <div class="stat-rail grid grid-cols-1 gap-4 sm:grid-cols-3">
        <div v-for="stat in stats" :key="stat.label" class="stat-cell" data-reveal-item>
          <div class="stat-num" :data-value="stat.value">{{ stat.value }}</div>
          <div class="stat-label">{{ stat.label }}</div>
        </div>
      </div>
    </section>

    <!-- ============ FEATURES (asymmetric) ============ -->
    <section class="relative mx-auto max-w-6xl px-4 py-28">
      <div class="mb-20 max-w-2xl" data-reveal>
        <p class="section-eyebrow" data-reveal-item data-drift="30">{{ t('website.home.featuresLabel') }}</p>
        <h2 class="section-title mt-4" data-reveal-item>{{ t('website.home.featuresTitle') }}</h2>
        <p class="mt-5 text-lg text-emerald-100/60" data-reveal-item>
          {{ t('website.home.featuresSubtitle') }}
        </p>
      </div>

      <div class="feature-stack" data-reveal>
        <article
          v-for="(feature, idx) in visibleFeatures"
          :key="feature.title"
          class="feature-card tilt-card"
          :class="idx % 2 === 1 ? 'feature-card--offset' : ''"
          data-reveal-item
        >
          <div class="feature-glow" aria-hidden="true" />
          <div class="feature-index" aria-hidden="true">{{ String(idx + 1).padStart(2, '0') }}</div>
          <div class="feature-glyph" aria-hidden="true">{{ feature.glyph }}</div>
          <div class="feature-body">
            <span class="feature-emoji">{{ feature.icon }}</span>
            <h3 class="feature-title">{{ feature.title }}</h3>
            <p class="feature-desc">{{ feature.description }}</p>
          </div>
        </article>
      </div>
    </section>

    <!-- ============ FEATURED PRODUCTS ============ -->
    <section v-if="features.store && featuredProducts.length" class="relative mx-auto max-w-6xl px-4 pb-24">
      <div class="mb-12 flex items-end justify-between gap-4" data-reveal>
        <div>
          <p class="section-eyebrow" data-reveal-item>{{ t('website.home.storeSection') }}</p>
          <h2 class="section-title section-title--sm mt-3" data-reveal-item>{{ t('website.home.featuredProducts') }}</h2>
        </div>
        <Link :href="routes.store" class="link-arrow shrink-0" data-reveal-item>
          {{ t('website.home.allProducts') }}
        </Link>
      </div>
      <div class="grid gap-5 sm:grid-cols-2 lg:grid-cols-3" data-reveal>
        <Link
          v-for="product in featuredProducts"
          :key="product.id"
          :href="product.url"
          class="product-card tilt-card no-underline"
          data-reveal-item
        >
          <div v-if="product.image_url" class="product-media">
            <img :src="product.image_url" :alt="product.name" loading="lazy">
          </div>
          <div v-else class="product-media product-media--empty">🎁</div>
          <h3 class="product-name">{{ product.name }}</h3>
          <div class="mt-2 flex items-center justify-between">
            <p class="product-price">{{ product.price_label }}</p>
            <p v-if="product.average_rating" class="product-rating">★ {{ product.average_rating }}</p>
          </div>
        </Link>
      </div>
    </section>

    <!-- ============ LATEST NEWS ============ -->
    <section v-if="features.website_blog && featuredArticles.length" class="relative mx-auto max-w-6xl px-4 pb-24">
      <div class="mb-12" data-reveal>
        <p class="section-eyebrow" data-reveal-item>{{ t('website.home.announcements') }}</p>
        <h2 class="section-title section-title--sm mt-3" data-reveal-item>{{ t('website.home.latestNews') }}</h2>
      </div>
      <div class="grid gap-5 md:grid-cols-2" data-reveal>
        <Link
          v-for="article in featuredArticles"
          :key="article.id"
          :href="routes.blogArticle(article.slug)"
          class="news-card no-underline"
          data-reveal-item
        >
          <div class="news-marker" aria-hidden="true">📢</div>
          <div>
            <h3 class="news-title">{{ article.title }}</h3>
            <p v-if="article.excerpt" class="news-excerpt">{{ article.excerpt }}</p>
            <p v-if="article.published_at" class="news-date">{{ article.published_at }}</p>
          </div>
        </Link>
      </div>
    </section>

    <!-- ============ CTA ============ -->
    <section class="relative mx-auto max-w-5xl px-4 pb-32" data-reveal>
      <div class="cta-band scan-effect" data-reveal-item>
        <div class="cta-aura" aria-hidden="true" />
        <div class="relative">
          <p class="section-eyebrow justify-center text-center">{{ t('website.home.ctaLabel') }}</p>
          <h2 class="cta-title">{{ t('website.home.ctaTitle') }}</h2>
          <p class="mx-auto mt-5 max-w-xl text-emerald-100/70">
            {{ t('website.home.ctaDesc') }}
          </p>
          <div class="mt-10 flex flex-wrap justify-center gap-4">
            <Link :href="routes.register" class="website-btn website-btn-primary text-base">{{ t('website.home.registerFree') }}</Link>
            <Link v-if="features.website_blog" :href="routes.blog" class="website-btn website-btn-ghost text-base">{{ t('website.home.viewAnnouncements') }}</Link>
          </div>
        </div>
      </div>
    </section>
  </div>
</template>
