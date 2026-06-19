<script setup lang="ts">
import { computed } from 'vue'
import { router, usePage } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import { Globe } from '@lucide/vue'
import {
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuRoot,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from 'reka-ui'
import Button from '@/components/ui/Button.vue'
import { cn } from '@/lib/utils'
import { normalizeAppLocale, type AppLocale } from '@/lib/i18n'
import { routes } from '@/lib/routes'

const page = usePage()
const { t } = useI18n()

const currentLocale = computed(() => normalizeAppLocale(page.props.locale))
const availableLocales = computed(() => {
  const raw = page.props.available_locales
  if (!Array.isArray(raw)) return [ 'zh-CN', 'en' ] as AppLocale[]
  return raw.map((locale) => normalizeAppLocale(locale))
})

function localeLabel(locale: AppLocale) {
  return t(`locale.${locale}`)
}

function switchLocale(locale: AppLocale) {
  if (locale === currentLocale.value) return
  router.patch(routes.locale, { locale }, { preserveScroll: true })
}
</script>

<template>
  <DropdownMenuRoot>
    <DropdownMenuTrigger as-child>
      <Button variant="ghost" size="icon" type="button" :aria-label="t('locale.label')">
        <Globe class="h-4 w-4" />
      </Button>
    </DropdownMenuTrigger>
    <DropdownMenuContent
      :class="cn(
        'z-50 min-w-[10rem] overflow-hidden rounded-md border bg-popover p-1 text-popover-foreground shadow-md',
      )"
      :side-offset="8"
      align="end"
    >
      <DropdownMenuLabel class="px-2 py-1.5 text-xs text-muted-foreground">
        {{ t('locale.label') }}
      </DropdownMenuLabel>
      <DropdownMenuSeparator class="my-1 h-px bg-border" />
      <DropdownMenuItem
        v-for="locale in availableLocales"
        :key="locale"
        class="relative flex cursor-pointer select-none items-center rounded-sm px-2 py-1.5 text-sm outline-none hover:bg-accent hover:text-accent-foreground"
        :class="locale === currentLocale ? 'font-medium text-foreground' : ''"
        @select="switchLocale(locale)"
      >
        <span class="flex-1">{{ localeLabel(locale) }}</span>
        <span v-if="locale === currentLocale" class="text-xs text-muted-foreground">✓</span>
      </DropdownMenuItem>
    </DropdownMenuContent>
  </DropdownMenuRoot>
</template>
