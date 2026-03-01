<script setup lang="ts">
import { useAgencyStore } from "@/composables/useAgencyStore";
import ToastContainer from "@/components/ToastContainer.vue";

const store = useAgencyStore();
store.init();
</script>

<template>
  <RouterView />
  <ToastContainer />
</template>
