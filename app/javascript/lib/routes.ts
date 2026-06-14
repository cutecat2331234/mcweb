export const routes = {
  home: '/',
  forum: '/forum/sections',
  forumSection: (slug: string) => `/forum/sections/${slug}`,
  forumTopic: (id: string) => `/forum/topics/${id}`,
  store: '/store/products',
  storeProduct: (id: string) => `/store/products/${id}`,
  signIn: '/identity/sign-in',
  register: '/identity/register',
  blog: '/website/blog',
} as const
