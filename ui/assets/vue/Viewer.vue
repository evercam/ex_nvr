<template>
    <div ref="container" class="e-h-full">
      <ERow ref="topMenu" justify="between" align="stretch" class="top-bar dark:bg-gray-900">
        <ERow>
          <select
            :value="device"
            name="devices"
            class="border border-gray-300 bg-white shadow-sm focus:border-zinc-400 text-sm
              dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:hover:bg-gray-600"
            @input="$emit('switch_device', {stream: $event.target.value})"
          >
            <option
              v-for="device in devices"
              :key="device.id"
              :value="device.id"
            >
              {{ device.name }}
            </option>
          </select>
          <select
            :value="stream"
            name="streams"
            class="border border-gray-300 bg-white shadow-sm focus:border-zinc-400 text-sm
              dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:hover:bg-gray-600"
            @input="$emit('switch_stream', {stream: $event.target.value})"
            >
            <option
              v-for="stream in streams"
              :key="stream.value"
              :value="stream.value"
            >
              {{ stream.name }}
            </option>
          </select>

        </ERow>
        <ERow align-content="stretch">
          <button
            id="download-footage-btn"
            class="
              dark:bg-gray-700 dark:border-gray-600
              text-white dark:text-white px-4 flex items-center dark:hover:bg-gray-600"
          >
            <span title="Download footage" class="mr-2">
              <svg
                xmlns="http://www.w3.org/2000/svg"
                class="w-5 h-5"
                fill="none"
                viewBox="0 0 24 24"
                stroke="currentColor"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="1.5"
                  d="M3 16.5v2.25A2.25 2.25 0 005.25 21h13.5A2.25 2.25 0 0021 18.75V16.5M16.5 12L12 16.5m0 0L7.5 12m4.5 4.5V3"
                />
              </svg>
            </span>
            Download
          </button>
        </ERow>
      </ERow>
      <ELayout v-if="url !== ''" :height="height">
        <template #main>
          <EVideoPlayer
            ref="videoPlayer"
            :sources="[
            {
              src: url,
            },
            ]"
            is-hls
            is-zoomable
            :video-options="videoOptions"
            :hls-options="{
              manifestLoadingTimeOut: 60_000
            }"
          />
        </template>

        <template #bottom-left>
          <div class="e-mb-4 e-ml-4">
            <slot name="bottom-left" />
          </div>
        </template>

        <template #footer>
          <Timeline :segments="segments" />
        </template>
      </ELayout>
    </div>
</template>

<script>
import { defineComponent } from 'vue'
import Timeline from './Timeline.vue'
import { ERow } from '@evercam/ui'

export default defineComponent({
  props: {
    url: {
      type: String,
      default: "",
    },
    segments: {
      type: Array,
      default: () => {[]}
    },
    devices: {
      type: Array,
      default: () => {[]}
    },
    streams: {
      type: Array,
      default: () => {[]}
    },
    stream: {
      type: String,
      default: ""
    },
    device: {
      type: String,
      default: ""
    }
  },
  components: {
    Timeline
  },
  computed: {
    videoOptions() {
      return {
        autoplay: true,
        muted: true,
        controls: false
      }
    }
  },
  watch: {
    url(value) {
      this.$refs.videoPlayer.initHls(value)
    }
  },
  data() {
    return {
      height: window.clientHeight
    }
  },
  mounted() {
    window.addEventListener("resize", this.handleResize);
    this.handleResize()
  },
  beforeUnmount() {
    window.removeEventListener("resize", this.handleResize);
  },
  methods: {
    handleResize() {
      this.height = `${this.$refs.container.clientHeight - this.$refs.topMenu.$el.clientHeight}px`
    }
  }
})
</script>

<style lang="scss">
.top-bar {
  min-height: 2.5em;
}

.zoomable_viewer {
  position: relative;
  width: 100%;
  height: 100%;
  overflow: hidden;

  .e-zoomable__content {
    display: flex;
    align-items: stretch;
    position: relative;
  }

  &__img {
    display: block;
    min-width: 100%;
    min-height: 100%;
    object-fit: contain;
    object-position: center;
    position: relative;
    z-index: 3;
  }

  &__overlay {
    position: absolute;
    z-index: 4;
  }
}
</style>