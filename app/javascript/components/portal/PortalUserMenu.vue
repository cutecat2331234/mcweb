<script setup lang="ts">
import { Link } from '@inertiajs/vue3'
import {
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuRoot,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from 'reka-ui'
import { LogOut, User, Settings } from '@lucide/vue'
import { routes } from '@/lib/routes'
import Avatar from '@/components/ui/Avatar.vue'
import Button from '@/components/ui/Button.vue'
import { cn } from '@/lib/utils'

defineProps<{
  username: string
}>()
</script>

<template>
  <DropdownMenuRoot>
    <DropdownMenuTrigger as-child>
      <Button variant="ghost" class="h-9 gap-2 px-2">
        <Avatar :fallback="username" class="h-7 w-7 text-xs" />
        <span class="hidden max-w-[7rem] truncate text-sm font-medium sm:inline">{{ username }}</span>
      </Button>
    </DropdownMenuTrigger>
    <DropdownMenuContent
      :class="cn(
        'z-50 min-w-[12rem] overflow-hidden rounded-md border bg-popover p-1 text-popover-foreground shadow-md',
        'data-[state=open]:animate-in data-[state=closed]:animate-out',
      )"
      :side-offset="8"
      align="end"
    >
      <DropdownMenuLabel class="px-2 py-1.5 text-sm font-normal">
        <p class="font-medium leading-none">{{ username }}</p>
        <p class="mt-1 text-xs text-muted-foreground">用户中心</p>
      </DropdownMenuLabel>
      <DropdownMenuSeparator class="my-1 h-px bg-border" />
      <DropdownMenuItem as-child>
        <Link
          :href="routes.forumUser(username)"
          class="relative flex cursor-pointer select-none items-center gap-2 rounded-sm px-2 py-1.5 text-sm outline-none hover:bg-accent hover:text-accent-foreground"
        >
          <User class="h-4 w-4" />
          个人资料
        </Link>
      </DropdownMenuItem>
      <DropdownMenuItem as-child>
        <Link
          :href="routes.forumPreferences"
          class="relative flex cursor-pointer select-none items-center gap-2 rounded-sm px-2 py-1.5 text-sm outline-none hover:bg-accent hover:text-accent-foreground"
        >
          <Settings class="h-4 w-4" />
          论坛偏好
        </Link>
      </DropdownMenuItem>
      <DropdownMenuSeparator class="my-1 h-px bg-border" />
      <DropdownMenuItem as-child>
        <Link
          :href="routes.signOut"
          method="delete"
          as="button"
          class="relative flex w-full cursor-pointer select-none items-center gap-2 rounded-sm px-2 py-1.5 text-sm text-destructive outline-none hover:bg-destructive/10"
        >
          <LogOut class="h-4 w-4" />
          退出登录
        </Link>
      </DropdownMenuItem>
    </DropdownMenuContent>
  </DropdownMenuRoot>
</template>
