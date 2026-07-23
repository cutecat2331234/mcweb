import { ref } from 'vue'
import { router } from '@inertiajs/vue3'

/**
 * Shared bulk topic moderation for the forum list pages. Owns the selected-id
 * state and issues the PATCH used by every list, clearing the selection on
 * success.
 *
 * @param urlGetter returns the bulk-moderate endpoint (usually
 *   `() => props.bulkModerateUrl`); a nullish value makes `bulkModerate` a no-op.
 */
export function useBulkModerate(urlGetter: () => string | null | undefined) {
  const selectedIds = ref<string[]>([])

  function bulkModerate(action: string) {
    const url = urlGetter()
    if (!url || selectedIds.value.length === 0) return
    router.patch(url, {
      topic_ids: selectedIds.value,
      action_type: action,
      return_to: window.location.pathname + window.location.search,
    }, {
      onSuccess: () => { selectedIds.value = [] },
    })
  }

  return { selectedIds, bulkModerate }
}
