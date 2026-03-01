import { onUnmounted, ref } from "vue";
import { useRouter } from "vue-router";

export interface Shortcut {
  keys: string;
  label: string;
  group: "Navigation" | "Chat" | "Search" | "General";
  handler: () => void;
}

// ── Escape priority stack (global singleton) ─────────────────────────
const escapeStack = ref<Array<{ id: string; handler: () => void }>>([]);

export function pushEscapeHandler(id: string, handler: () => void) {
  // Remove existing entry with same id to avoid duplicates
  escapeStack.value = escapeStack.value.filter((e) => e.id !== id);
  escapeStack.value.push({ id, handler });
}

export function popEscapeHandler(id: string) {
  escapeStack.value = escapeStack.value.filter((e) => e.id !== id);
}

// ── Shortcut registry (global singleton) ─────────────────────────────
const shortcuts = ref<Shortcut[]>([]);

export function getShortcuts(): Shortcut[] {
  return shortcuts.value;
}

export function registerShortcut(shortcut: Shortcut) {
  // Avoid duplicates
  if (!shortcuts.value.find((s) => s.keys === shortcut.keys)) {
    shortcuts.value.push(shortcut);
  }
}

export function unregisterShortcut(keys: string) {
  shortcuts.value = shortcuts.value.filter((s) => s.keys !== keys);
}

// ── Key matching ─────────────────────────────────────────────────────
function matchesShortcut(e: KeyboardEvent, keys: string): boolean {
  const parts = keys.toLowerCase().split("+");
  const needCmd = parts.includes("cmd") || parts.includes("meta");
  const needShift = parts.includes("shift");
  const needAlt = parts.includes("alt");
  const needCtrl = parts.includes("ctrl");
  const key = parts.filter((p) => !["cmd", "meta", "shift", "alt", "ctrl"].includes(p))[0];

  if (needCmd !== (e.metaKey || e.ctrlKey)) return false;
  if (needShift !== e.shiftKey) return false;
  if (needAlt !== e.altKey) return false;
  if (needCtrl && !needCmd !== e.ctrlKey) return false;
  return e.key.toLowerCase() === key || e.code.toLowerCase() === key;
}

// ── State for FZF panel and Help modal ───────────────────────────────
export const fzfOpen = ref(false);
export const helpOpen = ref(false);

// ── Main composable ──────────────────────────────────────────────────
export function useKeyboardShortcuts() {
  const router = useRouter();

  // Page navigation routes
  const pageRoutes = [
    { key: "1", path: "/" },
    { key: "2", path: "/agents" },
    { key: "3", path: "/chat" },
    { key: "4", path: "/memory" },
    { key: "5", path: "/prs" },
  ];

  // Register navigation shortcuts
  for (const { key, path } of pageRoutes) {
    registerShortcut({
      keys: `Cmd+Shift+${key}`,
      label: `Go to ${path === "/" ? "Dashboard" : path.slice(1)}`,
      group: "Navigation",
      handler: () => router.push(path),
    });
  }

  // Cmd+K → Chat
  registerShortcut({
    keys: "Cmd+k",
    label: "Open Chat",
    group: "Navigation",
    handler: () => router.push("/chat"),
  });

  // Cmd+P → FZF panel
  registerShortcut({
    keys: "Cmd+p",
    label: "Command palette",
    group: "Search",
    handler: () => {
      fzfOpen.value = !fzfOpen.value;
    },
  });

  // Cmd+/ → Help
  registerShortcut({
    keys: "Cmd+/",
    label: "Keyboard shortcuts",
    group: "General",
    handler: () => {
      helpOpen.value = !helpOpen.value;
    },
  });

  // Global keydown listener
  function handleKeydown(e: KeyboardEvent) {
    // Skip if typing in an input/textarea (unless it's a global shortcut)
    const target = e.target as HTMLElement;
    const isInput = target.tagName === "INPUT" || target.tagName === "TEXTAREA" || target.isContentEditable;

    // Escape always works — uses priority stack
    if (e.key === "Escape") {
      if (escapeStack.value.length > 0) {
        e.preventDefault();
        const top = escapeStack.value[escapeStack.value.length - 1];
        top.handler();
        return;
      }
      return;
    }

    // For shortcuts requiring Cmd/Ctrl, they work even in inputs
    const hasModifier = e.metaKey || e.ctrlKey;
    if (isInput && !hasModifier) return;

    // Match against registered shortcuts
    for (const shortcut of shortcuts.value) {
      if (matchesShortcut(e, shortcut.keys)) {
        e.preventDefault();
        shortcut.handler();
        return;
      }
    }
  }

  window.addEventListener("keydown", handleKeydown);

  onUnmounted(() => {
    window.removeEventListener("keydown", handleKeydown);
  });

  return {
    shortcuts,
    escapeStack,
    fzfOpen,
    helpOpen,
  };
}
