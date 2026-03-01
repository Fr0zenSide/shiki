<script setup lang="ts">
import { ref, onMounted, watch } from "vue";
import { Line } from "vue-chartjs";
import {
  Chart as ChartJS,
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  Title,
  Tooltip,
  Legend,
  Filler,
} from "chart.js";
import { useApi } from "@/composables/useApi";
import type { ActivityBucket } from "@/types";

ChartJS.register(CategoryScale, LinearScale, PointElement, LineElement, Title, Tooltip, Legend, Filler);

const api = useApi();
const timeRange = ref<"24h" | "7d" | "30d">("24h");
const rawData = ref<ActivityBucket[]>([]);
const loading = ref(false);

async function fetchActivity() {
  loading.value = true;
  try {
    rawData.value = await api.getActivity();
  } catch {
    rawData.value = [];
  } finally {
    loading.value = false;
  }
}

onMounted(fetchActivity);
watch(timeRange, fetchActivity);

// ── Chart config ─────────────────────────────────────────────────────

const seriesConfig: Record<string, { label: string; borderColor: string; bgColor: string }> = {
  agent_event: { label: "Agent Events", borderColor: "#c9956b", bgColor: "rgba(201,149,107,0.1)" },
  chat: { label: "Chat Messages", borderColor: "#7a9e7e", bgColor: "rgba(122,158,126,0.1)" },
  commit: { label: "Git Commits", borderColor: "#5E8E7A", bgColor: "rgba(94,142,122,0.1)" },
  api_call: { label: "API Calls", borderColor: "#d4a843", bgColor: "rgba(212,168,67,0.1)" },
};

function buildChartData() {
  // Group by bucket time
  const buckets = [...new Set(rawData.value.map((d) => d.bucket))].sort();
  const labels = buckets.map((b) => {
    const d = new Date(b);
    return d.toLocaleTimeString(undefined, { hour: "2-digit", minute: "2-digit" });
  });

  // Build datasets per event_type
  const eventTypes = [...new Set(rawData.value.map((d) => d.event_type))];
  const datasets = eventTypes.map((type) => {
    const conf = seriesConfig[type] ?? {
      label: type,
      borderColor: "#6b7280",
      bgColor: "rgba(107,114,128,0.1)",
    };
    const data = buckets.map((bucket) => {
      const entry = rawData.value.find((d) => d.bucket === bucket && d.event_type === type);
      return entry?.count ?? 0;
    });
    return {
      label: conf.label,
      data,
      borderColor: conf.borderColor,
      backgroundColor: conf.bgColor,
      borderWidth: 2,
      pointRadius: 3,
      pointHoverRadius: 5,
      tension: 0.3,
      fill: true,
    };
  });

  return { labels, datasets };
}

const chartOptions = {
  responsive: true,
  maintainAspectRatio: false,
  interaction: {
    mode: "index" as const,
    intersect: false,
  },
  plugins: {
    legend: {
      position: "bottom" as const,
      labels: {
        color: "#8a8478",
        boxWidth: 12,
        padding: 16,
        font: { size: 11 },
      },
    },
    tooltip: {
      backgroundColor: "#2a2820",
      borderColor: "#3d3a33",
      borderWidth: 1,
      titleColor: "#e8e5dd",
      bodyColor: "#b0aa9e",
      padding: 10,
      cornerRadius: 8,
    },
  },
  scales: {
    x: {
      grid: { color: "rgba(61,58,51,0.4)" },
      ticks: { color: "#6b6560", font: { size: 10 } },
    },
    y: {
      grid: { color: "rgba(61,58,51,0.4)" },
      ticks: { color: "#6b6560", font: { size: 10 } },
      beginAtZero: true,
    },
  },
};
</script>

<template>
  <section class="bg-surface-900 border border-surface-800 rounded-xl">
    <div class="px-5 py-4 border-b border-surface-800 flex items-center justify-between">
      <h2 class="text-sm font-semibold text-surface-200">Activity</h2>
      <div class="flex items-center gap-1">
        <button
          v-for="range in ['24h', '7d', '30d'] as const"
          :key="range"
          class="px-2.5 py-1 rounded-lg text-xs font-medium transition-colors"
          :class="timeRange === range
            ? 'bg-teal-400/15 text-teal-400'
            : 'text-surface-500 hover:text-surface-300 hover:bg-surface-800'"
          @click="timeRange = range"
        >
          {{ range }}
        </button>
      </div>
    </div>
    <div class="p-4" style="height: 200px">
      <div v-if="loading" class="flex items-center justify-center h-full">
        <svg class="w-5 h-5 animate-spin text-surface-600" fill="none" viewBox="0 0 24 24">
          <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" />
          <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
        </svg>
      </div>
      <div v-else-if="rawData.length === 0" class="flex items-center justify-center h-full text-sm text-surface-600">
        No activity data yet
      </div>
      <Line v-else :data="buildChartData()" :options="chartOptions" />
    </div>
  </section>
</template>
