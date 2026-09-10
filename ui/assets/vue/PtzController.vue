<template>
    <div
        class="ptz-controller absolute z-10 bottom-5 left-5 bg-slate-800/70 rounded-2xl shadow-xl p-3 select-none"
    >
        <div class="grid grid-cols-3 gap-1 w-32">
            <div />
            <button
                class="ptz-btn"
                @mousedown="move({ tilt: 1 })"
                @mouseup="stop"
                @mouseleave="stop"
                @touchstart.prevent="move({ tilt: 1 })"
                @touchend.prevent="stop"
            >
                <i class="fa-solid fa-chevron-up"></i>
            </button>
            <div />

            <button
                class="ptz-btn"
                @mousedown="move({ pan: -1 })"
                @mouseup="stop"
                @mouseleave="stop"
                @touchstart.prevent="move({ pan: -1 })"
                @touchend.prevent="stop"
            >
                <i class="fa-solid fa-chevron-left"></i>
            </button>
            <button class="ptz-btn" disabled>
                <i class="fa-solid fa-circle text-xs"></i>
            </button>
            <button
                class="ptz-btn"
                @mousedown="move({ pan: 1 })"
                @mouseup="stop"
                @mouseleave="stop"
                @touchstart.prevent="move({ pan: 1 })"
                @touchend.prevent="stop"
            >
                <i class="fa-solid fa-chevron-right"></i>
            </button>

            <div />
            <button
                class="ptz-btn"
                @mousedown="move({ tilt: -1 })"
                @mouseup="stop"
                @mouseleave="stop"
                @touchstart.prevent="move({ tilt: -1 })"
                @touchend.prevent="stop"
            >
                <i class="fa-solid fa-chevron-down"></i>
            </button>
            <div />
        </div>

        <div class="flex justify-center gap-1 mt-2">
            <button
                class="ptz-btn"
                @mousedown="move({ zoom: 1 })"
                @mouseup="stop"
                @mouseleave="stop"
                @touchstart.prevent="move({ zoom: 1 })"
                @touchend.prevent="stop"
            >
                <i class="fa-solid fa-plus"></i>
            </button>
            <button
                class="ptz-btn"
                @mousedown="move({ zoom: -1 })"
                @mouseup="stop"
                @mouseleave="stop"
                @touchstart.prevent="move({ zoom: -1 })"
                @touchend.prevent="stop"
            >
                <i class="fa-solid fa-minus"></i>
            </button>
        </div>
    </div>
</template>

<script>
import { defineComponent } from "vue";

export default defineComponent({
    emits: ["move", "stop"],
    methods: {
        move(direction) {
            this.$emit("move", direction);
        },
        stop() {
            this.$emit("stop");
        },
    },
});
</script>

<style lang="scss" scoped>
.ptz-controller {
    .ptz-btn {
        @apply bg-gray-100 dark:bg-gray-700 text-gray-700 dark:text-white w-9 h-9 flex items-center justify-center rounded hover:bg-gray-200 dark:hover:bg-gray-600 transition-colors;

        &:disabled {
            @apply opacity-40 cursor-default;
        }
    }
}
</style>
