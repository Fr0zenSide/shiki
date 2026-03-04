import { defineStore } from "pinia";
import { ref } from "vue";

export type ToastType = "success" | "error" | "info" | "warning";

export interface Toast {
  id: string;
  message: string;
  type: ToastType;
  timeout: ReturnType<typeof setTimeout>;
}

export const useToast = defineStore("toast", () => {
  const toasts = ref<Toast[]>([]);

  function show(message: string, type: ToastType = "info", durationMs = 3000) {
    const id = crypto.randomUUID();

    // Auto-dismiss oldest if we hit 3
    if (toasts.value.length >= 3) {
      dismiss(toasts.value[0].id);
    }

    const timeout = setTimeout(() => dismiss(id), durationMs);
    toasts.value.push({ id, message, type, timeout });
  }

  function dismiss(id: string) {
    const idx = toasts.value.findIndex((t) => t.id === id);
    if (idx !== -1) {
      clearTimeout(toasts.value[idx].timeout);
      toasts.value.splice(idx, 1);
    }
  }

  return { toasts, show, dismiss };
});
