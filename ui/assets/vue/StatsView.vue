<template>
  <EVideoPlayer
    ref="statsPlayer"
    :sources="[
      {
        src: url
      }
    ]"
    is-hls
    is-zoomable
    :pause-on-click="false"
    :video-options="videoOptions"
    :hls-options="{
      manifestLoadingTimeOut: 60000
    }"
  />
</template>

<script>
import { defineComponent } from 'vue'

export default defineComponent({
  props: {
    url: {
      type: String,
      defualt: "",
    }
  },
  computed: {
    videoOptions(){
      return {
        autoPlayer: true,
        muted: true,
        controls: false
      }
    }
  },
  watch: {
    url(value){
      this.$refs.statsPlayer?.initHls(value)
    }
  },
  data(){
    return{
      height: 0,
      navElement: null,
      isFullScreen: false
    }
  }
})
</script>
