<template>
    <ECol
        v-resize-observer="handleResize"
        class="dashboard-viewer e-h-full e-p-0 overflow-hidden"
    >
        <ERow
            ref="topMenu"
            justify="between"
            align-content="start"
            class="top-bar dark:bg-gray-900"
        >
            <ECol class="e-p-0" cols="5">
                <ERow>
                    <select
                        :value="device.id"
                        id="device_form_id"
                        name="devices"
                        class="text-sm dark:bg-gray-800 dark:placeholder-gray-400 dark:text-white dark:hover:bg-gray-600 e-border-transparent"
                        @input="
                            $emit('switch_device', {
                                device: $event.target.value,
                            })
                        "
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
                        @input="
                            $emit('switch_stream', {
                                stream: $event.target.value,
                            })
                        "
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
                    class="dark:bg-gray-800 dark:border-gray-600 e-h-full text-white dark:text-white px-4 flex items-center dark:hover:bg-gray-600"
                    @click="$emit('load-recording', { timestamp: null })"
                >
                    <span class="">Live</span>
                    <div v-if="!startDate" class="ml-2">
                        <EPulsatingDot :size="12" color="#c5393d" />
                    </div>
                </button>
            </ETooltip>
            <ECol class="e-p-0" cols="5" align-self="stretch">
                <ERow
                    class="right-buttons e-h-full"
                    align-content="stretch"
                    justify="end"
                >
                    <ETooltip
                        v-if="liveViewEnabled"
                        position="bottom"
                        text="Download current snapshot"
                    >
                        <button
                            class="dark:bg-gray-800 dark:border-gray-600 e-h-full text-white dark:text-white px-4 flex items-center dark:hover:bg-gray-600"
                            @click="downloadSnapshot"
                        >
                            <EIcon icon="camera" size="xl" class="e-mt-1" />
                        </button>
                    </ETooltip>
                    <ETooltip
                        v-if="liveViewEnabled && hailoAvailable"
                        position="bottom"
                        :text="
                            overlayMode === 'detections'
                                ? 'Disable detection overlay'
                                : 'Enable detection overlay'
                        "
                    >
                        <button
                            class="dark:bg-gray-800 dark:border-gray-600 e-h-full text-white dark:text-white px-4 flex items-center dark:hover:bg-gray-600"
                            :class="overlayMode === 'detections' ? 'bg-emerald-600 hover:bg-emerald-500' : ''"
                            @click="
                                $emit('set-overlay-mode', {
                                    mode: overlayMode === 'detections' ? 'off' : 'detections',
                                })
                            "
                        >
                            <i class="fa-solid fa-brain e-mt-1"></i>
                        </button>
                    </ETooltip>
                    <ETooltip
                        v-if="liveViewEnabled && hailoAvailable"
                        position="bottom"
                        :text="
                            overlayMode === 'tracking'
                                ? 'Disable tracking overlay'
                                : 'Enable tracking overlay'
                        "
                    >
                        <button
                            class="dark:bg-gray-800 dark:border-gray-600 e-h-full text-white dark:text-white px-4 flex items-center dark:hover:bg-gray-600"
                            :class="overlayMode === 'tracking' ? 'bg-emerald-600 hover:bg-emerald-500' : ''"
                            @click="
                                $emit('set-overlay-mode', {
                                    mode: overlayMode === 'tracking' ? 'off' : 'tracking',
                                })
                            "
                        >
                            <i class="fa-solid fa-location-crosshairs e-mt-1"></i>
                        </button>
                    </ETooltip>
                    <ETooltip position="bottom" text="Download footage">
                        <button
                            class="dark:bg-gray-800 dark:border-gray-600 e-h-full text-white dark:text-white px-4 flex items-center dark:hover:bg-gray-600"
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
                <div
                    v-if="isStreamShown"
                    class="absolute z-10 top-5 left-5 max-w-sm bg-slate-800/70 rounded-2xl shadow-xl p-2"
                >
                    <div
                        class="grid grid-cols-1 sm:grid-cols-2 gap-x-1 gap-y-1"
                    >
                        <div class="flex flex-col p-1">
                            <span class="text-sm text-gray-400 font-medium mb-0"
                                >Resolution</span
                            >
                            <span
                                id="resolution"
                                class="text-base text-gray-100 font-semibold"
                                >{{ stats.resolution }}</span
                            >
                        </div>

                        <div class="flex flex-col p-1">
                            <span class="text-sm text-gray-400 font-medium mb-0"
                                >Bitrate</span
                            >
                            <span
                                id="bitrate"
                                class="text-base text-gray-100 font-semibold"
                                >{{ bitrate }}</span
                            >
                        </div>

                        <div class="flex flex-col p-1">
                            <span class="text-sm text-gray-400 font-medium mb-0"
                                >Bandwidth</span
                            >
                            <span
                                id="bandwidth"
                                class="text-base text-gray-100 font-semibold"
                                >{{ stats.bandwidth }}</span
                            >
                        </div>

                        <div class="flex flex-col p-1">
                            <span class="text-sm text-gray-400 font-medium mb-0"
                                >Available Levels</span
                            >
                            <span
                                id="frameRate"
                                class="text-base text-gray-100 font-semibold"
                                >{{ stats.availableLevels }}</span
                            >
                        </div>

                        <div class="flex flex-col p-1">
                            <span class="text-sm text-gray-400 font-medium mb-0"
                                >Total Video Frames</span
                            >
                            <span
                                id="totalVideoFrames"
                                class="text-base text-gray-100 font-semibold"
                                >{{ stats.totalVideoFrames }}</span
                            >
                        </div>

                        <div class="flex flex-col p-1">
                            <span class="text-sm text-gray-400 font-medium mb-0"
                                >Corrupted Frames</span
                            >
                            <span
                                id="decodedFrames"
                                class="text-base text-gray-100 font-semibold"
                                >{{ stats.corruptedFrames }}</span
                            >
                        </div>

                        <div class="flex flex-col p-1">
                            <span class="text-sm text-gray-400 font-medium mb-0"
                                >Dropped Frames</span
                            >
                            <span
                                id="droppedFrames"
                                class="text-base text-gray-100 font-semibold"
                                >{{ stats.droppedFrames }}</span
                            >
                        </div>

                        <div class="flex flex-col p-1">
                            <span class="text-sm text-gray-400 font-medium mb-0"
                                >Codec</span
                            >
                            <span
                                id="codec"
                                class="text-base text-gray-100 font-semibold"
                                >{{ stats.codec }}</span
                            >
                        </div>
                    </div>
                </div>

                <div
                    v-if="liveViewEnabled"
                    ref="videoStage"
                    class="relative w-full h-full"
                >
                    <EVideoPlayer
                        id="main"
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
                            liveSyncDurationCount: 3,
                            liveMaxLatencyDurationCount: 6,
                            manifestLoadingTimeOut: 60000,
                        }"
                    />
                    <div
                        v-if="showDetectionOverlay"
                        class="pointer-events-none absolute inset-0 z-20"
                    >
                        <div
                            v-for="(det, idx) in tracking.detections || []"
                            :key="`det-${idx}-${det.class_id}`"
                            class="absolute border-2 border-cyan-400 bg-cyan-500/10"
                            :style="detectionStyle(det)"
                        >
                            <div
                                class="absolute -top-6 left-0 text-xs font-semibold px-2 py-0.5 bg-black/80 text-cyan-300 whitespace-nowrap"
                            >
                                {{ det.class_name || "unknown" }}
                                {{ formatScore(det.score) }}
                            </div>
                        </div>
                    </div>
                    <div
                        v-if="showTrackingOverlay"
                        class="pointer-events-none absolute inset-0 z-20"
                    >
                        <div
                            v-for="track in tracking.tracks"
                            :key="track.id"
                            class="absolute border-2 border-lime-400 bg-lime-500/10"
                            :style="trackStyle(track)"
                        >
                            <div
                                class="absolute -top-6 left-0 text-xs font-semibold px-2 py-0.5 bg-black/80 text-lime-300 whitespace-nowrap"
                            >
                                #{{ track.id }}
                                {{ track.class_name || "unknown" }}
                            </div>
                        </div>
                    </div>
                </div>

                <div
                    v-else
                    class="relative text-lg rounded-tr rounded-tl text-center bg-gray-200 dark:text-gray-200 w-full h-full dark:bg-gray-400 flex justify-center items-center d-flex"
                >
                    {{ liveViewDisabledReason || "Device is not recording, live view is not available" }}
                </div>
            </template>

            <template #bottom-right>
                <ECol>
                    <div class="mb-2">
                        <button
                            class="dark:bg-gray-800 dark:border-gray-600 text-white dark:text-white px-3.5 e-py-2.5 flex items-center dark:hover:bg-gray-600"
                            @click="openStatsTab"
                        >
                            <i class="fa-solid fa-sliders"></i>
                        </button>
                    </div>

                    <button
                        class="dark:bg-gray-800 dark:border-gray-600 text-white dark:text-white px-3 e-py-1.5 flex items-center dark:hover:bg-gray-600"
                        @click="toggleFullscreen"
                    >
                        <EIcon
                            :icon="isFullScreen ? 'minimize' : 'maximize'"
                            size="xl"
                            class="e-mt-1"
                        />
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
import { defineComponent, isProxy, toRaw } from "vue";
import Timeline from "./Timeline.vue";
import { makeFullScreen, exitFullScreen } from "@evercam/ui/vue3";
import Hls from "hls.js";

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
            default: () => {
                [];
            },
        },
        devices: {
            type: Array,
            default: () => {
                [];
            },
        },
        streams: {
            type: Array,
            default: () => {
                [];
            },
        },
        stream: {
            type: String,
            default: "",
        },
        device: {
            type: Object,
            default: () => ({}),
        },
        liveViewEnabled: {
            type: Boolean,
            default: false,
        },
        liveViewDisabledReason: {
            type: String,
            default: null,
        },
        startDate: {
            type: String,
            default: null,
        },
        overlayMode: {
            type: String,
            default: "off",
        },
        hailoAvailable: {
            type: Boolean,
            default: false,
        },
    },
    components: {
        Timeline,
    },
    computed: {
        videoOptions() {
            return {
                autoplay: true,
                muted: true,
                controls: false,
                poster: this.poster,
            };
        },
        showDetectionOverlay() {
            return (
                this.overlayMode === "detections" &&
                Array.isArray(this.tracking.detections) &&
                this.tracking.detections.length > 0
            );
        },
        showTrackingOverlay() {
            return (
                this.overlayMode === "tracking" &&
                Array.isArray(this.tracking.tracks) &&
                this.tracking.tracks.length > 0
            );
        },
    },
    watch: {
        url(value) {
            this.startStreaming(value);
        },
        overlayMode(value) {
            if (value === "off") {
                this.tracking = {
                    frame_width: 1,
                    frame_height: 1,
                    detections: [],
                    tracks: [],
                };
            }
        },
        stream() {
            this.tracking = {
                frame_width: 1,
                frame_height: 1,
                detections: [],
                tracks: [],
            };
        },
    },

    mounted() {
        this.startStreaming(this.url);
        window.addEventListener("phx:tracking-data", this.onTrackingData);
        window.addEventListener("phx:tracking-clear", this.onTrackingClear);
    },
    beforeUnmount() {
        window.removeEventListener("phx:tracking-data", this.onTrackingData);
        window.removeEventListener("phx:tracking-clear", this.onTrackingClear);
    },
    data() {
        return {
            height: 0,
            navElement: null,
            isFullScreen: false,
            isStreamShown: false,
            interval: null,
            stats: {
                availableLevels: 0,
                resolution: "",
                bandwidth: "",
                totalVideoFrames: 0,
                corruptedFrames: 0,
                droppedFrames: 0,
                codec: "",
                bitrate: "",
            },
            tracking: {
                frame_width: 1,
                frame_height: 1,
                detections: [],
                tracks: [],
            },
        };
    },
    methods: {
        onTrackingData(event) {
            const payload = event?.detail;
            if (!payload || payload.device_id !== this.device.id) {
                return;
            }

            if (payload.stream && payload.stream !== this.stream) {
                return;
            }

            this.tracking = payload;
        },
        onTrackingClear(event) {
            const payload = event?.detail;
            if (payload && payload.device_id !== this.device.id) {
                return;
            }

            this.tracking = {
                frame_width: 1,
                frame_height: 1,
                detections: [],
                tracks: [],
            };
        },
        formatScore(score) {
            if (typeof score !== "number") {
                return "";
            }

            return `${(score * 100).toFixed(0)}%`;
        },
        detectionStyle(det) {
            const videoRect = this.getVideoRect();
            const frameWidth = this.tracking.frame_width || 1;
            const frameHeight = this.tracking.frame_height || 1;

            const x = det.xmin || 0;
            const y = det.ymin || 0;
            const w = Math.max(0, (det.xmax || 0) - x);
            const h = Math.max(0, (det.ymax || 0) - y);

            const left = videoRect.left + (x / frameWidth) * videoRect.width;
            const top = videoRect.top + (y / frameHeight) * videoRect.height;
            const width = (w / frameWidth) * videoRect.width;
            const height = (h / frameHeight) * videoRect.height;

            return {
                left: `${left}px`,
                top: `${top}px`,
                width: `${width}px`,
                height: `${height}px`,
            };
        },
        trackStyle(track) {
            const videoRect = this.getVideoRect();
            const frameWidth = this.tracking.frame_width || 1;
            const frameHeight = this.tracking.frame_height || 1;

            const left = videoRect.left + (track.x / frameWidth) * videoRect.width;
            const top = videoRect.top + (track.y / frameHeight) * videoRect.height;
            const width = (track.width / frameWidth) * videoRect.width;
            const height = (track.height / frameHeight) * videoRect.height;

            return {
                left: `${left}px`,
                top: `${top}px`,
                width: `${width}px`,
                height: `${height}px`,
            };
        },
        getVideoRect() {
            const stage = this.$refs.videoStage;
            const player =
                this.$refs.videoPlayer?.$refs?.player ||
                stage?.querySelector("video");

            if (!stage) {
                return { left: 0, top: 0, width: 0, height: 0 };
            }

            const stageWidth = stage.clientWidth || 0;
            const stageHeight = stage.clientHeight || 0;

            if (!player || !player.videoWidth || !player.videoHeight) {
                return { left: 0, top: 0, width: stageWidth, height: stageHeight };
            }

            const videoAspect = player.videoWidth / player.videoHeight;
            const stageAspect = stageWidth > 0 && stageHeight > 0 ? stageWidth / stageHeight : 1;

            let width = stageWidth;
            let height = stageHeight;
            let left = 0;
            let top = 0;

            if (stageAspect > videoAspect) {
                height = stageHeight;
                width = height * videoAspect;
                left = (stageWidth - width) / 2;
            } else {
                width = stageWidth;
                height = width / videoAspect;
                top = (stageHeight - height) / 2;
            }

            return { left, top, width, height };
        },
        handleResize() {
            const GAP_PX = 8;
            this.height = `${
                document.body.clientHeight -
                    this.$refs.topMenu?.$el.clientHeight -
                    this.getNavHeight() -
                    (this.$refs.timeline?.$el?.clientHeight ?? 0) -
                    GAP_PX
            }px`;
        },
        getNavHeight() {
            if (!this.navElement) {
                this.navElement = document.getElementById("main-nav");
            }

            return this.navElement.clientHeight;
        },
        downloadSnapshot(event) {
            const player =
                this.$refs.videoPlayer?.$refs.player ||
                this.$refs.videoStage?.querySelector("video");
            var canvas = document.createElement("canvas");

            if (!player) {
                return;
            }

            canvas.width = player.videoWidth;
            canvas.height = player.videoHeight;
            canvas
                .getContext("2d")
                .drawImage(player, 0, 0, canvas.width, canvas.height);

            const dataUri = canvas.toDataURL("image/jpeg", 0.7);

            const timestampOfRequest = new Date()
                .toString()
                .split("GMT")[0]
                .trim();

            const link = document.createElement("a");
            link.style.display = "none";
            link.download = `${this.device.name}_${timestampOfRequest}_${this.stream}.png`;
            link.href = dataUri;

            document.body.appendChild(link);
            link.click();

            document.body.removeChild(link);
            canvas
                .getContext("2d")
                .clearRect(0, 0, canvas.width, canvas.height);
        },
        async toggleFullscreen() {
            this.isFullScreen = !this.isFullScreen;
            if (this.isFullScreen) {
                await makeFullScreen(this.$refs.mainLayout.$el);
                setTimeout(
                    () => (this.height = `${window.screen.height}px`),
                    200,
                );
            } else {
                exitFullScreen();
            }
        },
        openStatsTab() {
            this.isStreamShown = !this.isStreamShown;
        },
        startStreaming(streamUrl) {
            const component = this.$refs.videoPlayer;
            component?.initHls(streamUrl);
            const playerElement = component?.$refs?.player;

            if (playerElement) {
                playerElement._hls = isProxy(component.player)
                    ? toRaw(component.player)
                    : component.player;
                const hls = playerElement._hls;

                hls.on(Hls.Events.FRAG_LOADED, (event, data) => {
                    this.stats.bytes = data.stats.total;
                    this.stats.bytes += data.stats.total;
                });

                hls.on(Hls.Events.LEVEL_LOADED, (event, data) => {
                    const level = hls.levels[data.level];
                    this.stats.bandwidth = convertBitrate(
                        hls.bandwidthEstimate,
                    );
                    this.stats.resolution = `${level.width}x${level.height}`;
                    this.stats.codec = level.videoCodec || level.codecs;
                    this.bitrate = convertBitrate(level.bitrate);
                    this.stats.availableLevels = hls.levels.length;
                    this.stats.resolution = `${hls.levels[data.level].width}x${hls.levels[data.level].height}`;
                });

                setInterval(() => {
                    const quality = playerElement.getVideoPlaybackQuality?.();
                    if (quality) {
                        this.stats.droppedFrames = quality.droppedVideoFrames;
                        this.stats.totalVideoFrames = quality.totalVideoFrames;
                        this.stats.corruptedVideoFrames =
                            quality.corruptedVideoFrames;
                    }
                }, 2000);
            }
        },
    },
});

function convertBitrate(bitRate) {
    const mbpsFactor = 1000 * 1000;
    const bitRateMbps = bitRate / mbpsFactor;

    return bitRateMbps < 1
        ? `${(bitRateMbps * 1000).toFixed(2)} Kbps`
        : `${bitRateMbps.toFixed(2)} Mbps`;
}
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
