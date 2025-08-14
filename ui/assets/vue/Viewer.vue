<template>
    <ECol v-resize-observer="handleResize" class="dashboard-viewer e-h-full e-p-0 overflow-hidden">
      <ERow ref="topMenu" justify="between" align-content="start" class="top-bar dark:bg-gray-900">
        <ECol class="e-p-0" cols="5">
          <ERow>
            <select
              :value="device"
              id="device_form_id"
              name="devices"
              class="text-sm dark:bg-gray-800 dark:placeholder-gray-400 dark:text-white dark:hover:bg-gray-600 e-border-transparent"
              @input="$emit('switch_device', {device: $event.target.value})"
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
              class="text-sm dark:bg-gray-800 dark:placeholder-gray-400 dark:text-white dark:hover:bg-gray-600 e-border-transparent"
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
        </ECol>
        <ETooltip v-if="liveViewEnabled" position="bottom" text="Go live">
          <button
            class="
                dark:bg-gray-800 dark:border-gray-600 e-h-full
                text-white dark:text-white px-4 flex items-center dark:hover:bg-gray-600"
            @click="$emit('load-recording', { timestamp: null })"
          >
            <span class="">Live</span>
            <div v-if="!startDate" class="ml-2">
              <EPulsatingDot :size="12" color="#c5393d" />
            </div>
          </button>
        </ETooltip>
        <ECol class="e-p-0" cols="5" align-self="stretch">
          <ERow class="right-buttons e-h-full" align-content="stretch" justify="end">
            <ETooltip v-if="liveViewEnabled" position="bottom" text="Download current snapshot">
              <button
                class="
                  dark:bg-gray-800 dark:border-gray-600 e-h-full
                  text-white dark:text-white px-4 flex items-center dark:hover:bg-gray-600"
                @click="downloadSnapshot"
              >
                <EIcon icon="camera" size="xl" class="e-mt-1" />
              </button>
            </ETooltip>
            <ETooltip position="bottom" text="Download footage">
              <button
                class="
                  dark:bg-gray-800 dark:border-gray-600 e-h-full
                  text-white dark:text-white px-4 flex items-center dark:hover:bg-gray-600"
                @click="$emit('show-download-modal')"
              >
                <EIcon icon="download" size="xl" class="e-mt-1" />
              </button>
            </ETooltip>
          </ERow>
        </ECol>
      </ERow>
      <ELayout ref="mainLayout" :height="height">
        <template #main>
          <EVideoPlayer
            v-if="liveViewEnabled"
            ref="videoPlayer"
            :sources="[
            {
              src: url,
            },
            ]"
            is-hls
            is-zoomable
            :pause-on-click="false"
            :video-options="videoOptions"
            :hls-options="{
              manifestLoadingTimeOut: 60000
            }"
          />
          <div
            v-else
            class="relative text-lg rounded-tr rounded-tl text-center bg-gray-200 dark:text-gray-200 w-full h-full dark:bg-gray-400 flex justify-center items-center d-flex"
          >
            Device is not recording, live view is not available
          </div>
        </template>

        <template #bottom-right>
          <ECol class="mb-2 mr-2">
            <button
                class="
                  dark:bg-gray-800 dark:border-gray-600
                  text-white dark:text-white px-3 e-py-1.5 flex items-center dark:hover:bg-gray-600"
                @click="toggleFullscreen"
              >
                <EIcon :icon="isFullScreen ? 'minimize' : 'maximize'" size="xl" class="e-mt-1" />
            </button>
          </ECol>
        </template>
      </ELayout>
      <Timeline 
        ref="timeline" 
        :segments="segments" 
        @run-clicked="$emit('load-recording', $event)" 
      />
    </ECol>
</template>

<script>
import { defineComponent, isProxy, toRaw } from 'vue'
import Timeline from './Timeline.vue'
import { makeFullScreen, exitFullScreen } from '@evercam/ui/vue3'

export default defineComponent({
  props: {
    url: {
      type: String,
      default: "",
    },
    poster: {
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
      type: Object,
      default: ()  => ({})
    },
    liveViewEnabled: {
      type: Boolean,
      default: false
    },
    startDate: {
      type: String,
      default: null
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
        controls: false,
        poster: this.poster
      }
    }
  },
  watch: {
    url(value) {
      const component = this.$refs.videoPlayer
      component?.initHls(value)

      const playerElement = component?.$refs?.player
      if (playerElement) {
        playerElement._hls = isProxy(component.player) ? toRaw(component.player) : component.player
        console.log("[Player]: HLS.js initialized", playerElement._hls)
      }
    }
  },
  data() {
    return {
      height: 0,
      navElement: null,
      isFullScreen: false
    }
  },
  methods: {
    handleResize() {
      this.height = `${
        document.body.clientHeight - 
        this.$refs.topMenu?.$el.clientHeight - 
        this.getNavHeight() -
        this.$refs.timeline?.$el?.clientHeight ?? 0
      }px`
    },
    getNavHeight() {
      if (!this.navElement) {
        this.navElement = document.getElementById("main-nav")
      }

      return this.navElement.clientHeight
    },
    downloadSnapshot(event) {
      const player = this.$refs.videoPlayer?.$refs.player
      var canvas = document.createElement("canvas")

      if (!player) {
        return
      }

      canvas.width = player.videoWidth
      canvas.height = player.videoHeight
      canvas.getContext('2d').drawImage(player, 0, 0, canvas.width, canvas.height)
      
      const dataUri = canvas.toDataURL('image/png')

      const timestampOfRequest = new Date().toString().split('GMT')[0].trim();

      const link = document.createElement("a")
      link.style.display = "none"
      link.download = `${this.device.name}_${timestampOfRequest}_${this.stream}.png`
      link.href = dataUri

      document.body.appendChild(link)
      link.click()

      document.body.removeChild(link)
      canvas.getContext('2d').clearRect(0, 0, canvas.width, canvas.height)
    },
    async toggleFullscreen() {
      this.isFullScreen = !this.isFullScreen
      if (this.isFullScreen) {
        await makeFullScreen(this.$refs.mainLayout.$el)
        setTimeout(() => this.height = `${window.screen.height}px`, 200)
      } else {
        exitFullScreen()
      }
    }
  }
})
</script>

<style lang="scss">
.dashboard-viewer {
  .top-bar {
    min-height: 2.5em;
  }

  .tooltip {
    z-index: 100;
  }

  .right-buttons .tooltip {
    transform: translate(-80%, 0) !important;
  }
}
</style>
