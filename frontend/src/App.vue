<script setup lang="ts">
import { useAgencyStore } from "@/composables/useAgencyStore";

const store = useAgencyStore();
store.init();
</script>

<template>
  <RouterView />
</template>
