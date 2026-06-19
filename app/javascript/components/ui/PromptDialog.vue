<script setup lang="ts">
import { nextTick, ref, watch } from 'vue'
import { promptState, resolvePrompt } from '@/lib/usePrompt'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'

const inputRef = ref<HTMLInputElement | null>(null)

watch(
  () => promptState.open,
  async (open) => {
    if (!open) return
    await nextTick()
    inputRef.value?.focus()
    inputRef.value?.select()
  },
)

function cancel() {
  resolvePrompt(null)
}

function accept() {
  resolvePrompt(promptState.value)
}
</script>

<template>
  <Teleport to="body">
    <Transition
      enter-active-class="transition duration-150 ease-out"
      enter-from-class="opacity-0"
      leave-active-class="transition duration-100 ease-in"
      leave-to-class="opacity-0"
    >
      <div
        v-if="promptState.open"
        class="fixed inset-0 z-[100] flex items-center justify-center bg-black/50 p-4"
        @click.self="cancel"
      >
        <form
          role="dialog"
          aria-modal="true"
          class="w-full max-w-md rounded-lg border bg-card p-6 shadow-lg"
          @submit.prevent="accept"
        >
          <h2 class="text-lg font-semibold">{{ promptState.options.title }}</h2>
          <p v-if="promptState.options.message" class="mt-2 text-sm text-muted-foreground">
            {{ promptState.options.message }}
          </p>
          <div class="mt-4">
            <Input
              ref="inputRef"
              v-model="promptState.value"
              :placeholder="promptState.options.placeholder"
            />
          </div>
          <div class="mt-6 flex flex-wrap justify-end gap-2">
            <Button type="button" variant="outline" @click="cancel">
              {{ promptState.options.cancelLabel || '取消' }}
            </Button>
            <Button type="submit">
              {{ promptState.options.confirmLabel || '确定' }}
            </Button>
          </div>
        </form>
      </div>
    </Transition>
  </Teleport>
</template>
