import { createRouter, createWebHistory } from "vue-router";

export const router = createRouter({
  history: createWebHistory(),
  routes: [
    {
      path: "/",
      component: () => import("@/layouts/DashboardLayout.vue"),
      children: [
        {
          path: "",
          name: "dashboard",
          component: () => import("@/pages/DashboardPage.vue"),
        },
        {
          path: "agents",
          name: "agents",
          component: () => import("@/pages/AgentsPage.vue"),
        },
        {
          path: "sessions/:id",
          name: "session",
          component: () => import("@/pages/SessionPage.vue"),
          props: true,
        },
        {
          path: "chat",
          name: "chat",
          component: () => import("@/pages/ChatPage.vue"),
        },
        {
          path: "memory",
          name: "memory",
          component: () => import("@/pages/MemoryPage.vue"),
        },
        {
          path: "prs",
          name: "prs",
          component: () => import("@/pages/PRsPage.vue"),
        },
      ],
    },
  ],
});
