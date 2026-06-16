import { computed } from 'vue'
import { usePage } from '@inertiajs/vue3'

export interface ActiveTemplate {
  key: string
  name?: string
  version?: string
  scope?: string
  tokens: Record<string, string>
  cssUrls: string[]
  logoUrl?: string | null
  faviconUrl?: string | null
  slots: Record<string, string | null | undefined>
}

export function useActiveTemplate() {
  const page = usePage()
  const activeTemplate = computed(() => page.props.activeTemplate as ActiveTemplate | undefined)
  const tokenStyle = computed(() => activeTemplate.value?.tokens || {})
  const websiteHeaderSlot = computed(() => activeTemplate.value?.slots?.website_header || null)
  const websiteFooterSlot = computed(() => activeTemplate.value?.slots?.website_footer || null)
  const portalHeaderExtraSlot = computed(() => activeTemplate.value?.slots?.portal_header_extra || null)

  return {
    activeTemplate,
    tokenStyle,
    websiteHeaderSlot,
    websiteFooterSlot,
    portalHeaderExtraSlot,
  }
}
