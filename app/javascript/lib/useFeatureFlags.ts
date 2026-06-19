import { computed } from 'vue'
import { usePage } from '@inertiajs/vue3'
import { resolveFeatureFlags, type FeatureFlagsMap } from '@/lib/featureFlags'

export function useFeatureFlags() {
  const page = usePage()

  const features = computed<FeatureFlagsMap>(() =>
    resolveFeatureFlags(page.props.features as Partial<FeatureFlagsMap> | undefined),
  )

  const portalSections = computed(() => {
    const sections: Array<'forum' | 'store'> = []
    if (features.value.forum) sections.push('forum')
    if (features.value.store) sections.push('store')
    return sections
  })

  const showPortalSectionTabs = computed(() => portalSections.value.length > 0)

  const portalSectionGridClass = computed(() =>
    portalSections.value.length === 1 ? 'grid-cols-1' : 'grid-cols-2',
  )

  return {
    features,
    portalSections,
    showPortalSectionTabs,
    portalSectionGridClass,
  }
}
