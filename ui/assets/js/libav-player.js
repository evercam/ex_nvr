import { Socket } from "phoenix"
import LibAV from "libav.js"

// The hevc-aac variant files must be in ui/priv/static/ so Phoenix serves them
// at the origin root (/). toImport bypasses libav.js's base calculation entirely,
// guaranteeing a root-relative request to Phoenix regardless of Vite's asset base.
const LIBAV_VARIANT = "hevc-aac"
const LIBAV_IMPORT  = `/libav-${LibAV.VER}-${LIBAV_VARIANT}.wasm.mjs`

window.onload = async function (_event) {
  const player   = document.getElementById("webRtcPlayer")
  const canvas   = document.getElementById("hevcCanvas")
  const logsEl   = document.getElementById("webRtcLogs")
  const deviceId = player.dataset.device
  const stream   = player.dataset.stream

  function log(msg) {
    if (logsEl) {
      logsEl.innerHTML += "\n\n" + msg
      logsEl.scrollTop  = logsEl.scrollHeight
    }
    console.log("[libav-player]", msg)
  }

  // ── 1. Load libav.js HEVC variant ─────────────────────────────────────────
  log("Loading libav.js hevc-aac…")
  let libav
  try {
    libav = await LibAV.LibAV({ toImport: LIBAV_IMPORT })
  } catch (err) {
    log(`Failed to load libav.js: ${err}`)
    return
  }
  log("libav.js ready")

  // ── 2. Persistent HEVC decoder ────────────────────────────────────────────
  // One AVCodecContext lives for the entire session — no per-GOP restart.
  let codec, codecCtx, pkt, frame
  try {
    ;[codec, codecCtx, pkt, frame] = await libav.ff_init_decoder("hevc")
  } catch (err) {
    log(`HEVC decoder init failed: ${err}`)
    return
  }
  log("HEVC decoder ready")

  // ── 3. Canvas + render queue ──────────────────────────────────────────────
  const ctx2d         = canvas.getContext("2d")
  const frameQueue    = []
  let streamStartPts  = null
  let displayStartTime = null

  // ── 4. Phoenix socket + channel ───────────────────────────────────────────
  const socket = new Socket("/socket", { params: { token: window.token } })
  socket.connect()

  const streamChannel = socket.channel(`stream:${deviceId}`, { stream })

  log(`Joining stream:${deviceId}`)
  streamChannel
    .join()
    .receive("ok",      ()       => log("Connected to HEVC stream"))
    .receive("error",   (reason) => log("Join failed: " + formatJoinError(reason)))
    .receive("timeout", ()       => log("Join timed out"))

  // Serialise decoding — only one ff_decode_multi call in flight at a time
  // so the shared AVCodecContext is never accessed concurrently.
  const decodeQueue = []
  let   decoding    = false

  streamChannel.on("frame", (payload) => {
    const nalData = payload instanceof Uint8Array ? payload : new Uint8Array(payload.buffer ?? payload)
    const ptsMs   = performance.now()

    decodeQueue.push({ nalData, ptsMs })
    if (!decoding) drainDecodeQueue()
  })

  async function drainDecodeQueue() {
    decoding = true
    while (decodeQueue.length > 0) {
      const item = decodeQueue.shift()
      await decodePacket(item.nalData, item.ptsMs)
    }
    decoding = false
  }

  async function decodePacket(nalData, ptsMs) {
    if (!nalData || nalData.length === 0) return

    let frames
    try {
      frames = await libav.ff_decode_multi(codecCtx, pkt, frame, [{
        data: nalData,
        pts:  ptsMs,
        dts:  ptsMs,
      }], false)
    } catch (err) {
      log(`Decode error: ${err}`)
      return
    }

    if (!frames || frames.length === 0) return

    for (const f of frames) {
      if (!f.width || !f.height || !f.data || !f.layout) continue

      const rgba   = yuvFrameToRgba(f)
      const bitmap = await createImageBitmap(new ImageData(rgba, f.width, f.height))

      frameQueue.push({ bitmap, pts: ptsMs, width: f.width, height: f.height })
    }
  }

  // ── 5. Render loop ────────────────────────────────────────────────────────
  requestAnimationFrame(renderLoop)

  function renderLoop() {
    const now = performance.now()

    while (frameQueue.length > 0) {
      const f = frameQueue[0]

      if (streamStartPts === null) {
        streamStartPts   = f.pts
        displayStartTime = now
        canvas.width     = f.width
        canvas.height    = f.height
      }

      const expectedTime = displayStartTime + (f.pts - streamStartPts)
      if (now < expectedTime) break

      ctx2d.drawImage(f.bitmap, 0, 0)
      f.bitmap.close()
      frameQueue.shift()
    }

    requestAnimationFrame(renderLoop)
  }

  // ── 6. Cleanup ────────────────────────────────────────────────────────────
  window.addEventListener("beforeunload", () => {
    libav.ff_free_decoder(codec, codecCtx, pkt, frame)
  })
}

// ── YUV → RGBA ───────────────────────────────────────────────────────────────
// ff_copyout_frame_video packs all planes into a single Uint8Array (data) and
// describes each plane via a layout array: [{ offset, stride }, ...].
// AV_PIX_FMT_YUV420P  = 0  → BT.601 limited range
// AV_PIX_FMT_YUVJ420P = 12 → BT.601 full range (most IP cameras)
function yuvFrameToRgba({ width, height, data, layout, format }) {
  const fullRange = format === 12
  const rgba      = new Uint8ClampedArray(width * height * 4)

  const yOffset  = layout[0].offset
  const yStride  = layout[0].stride
  const uOffset  = layout[1].offset
  const uvStride = layout[1].stride
  const vOffset  = layout[2].offset

  for (let row = 0; row < height; row++) {
    const uvRow = row >> 1
    for (let col = 0; col < width; col++) {
      const uvCol = col >> 1
      const Y = data[yOffset + row * yStride + col]
      const U = data[uOffset + uvRow * uvStride + uvCol] - 128
      const V = data[vOffset + uvRow * uvStride + uvCol] - 128

      let r, g, b
      if (fullRange) {
        r = Y             + 1.402    * V
        g = Y - 0.344136 * U - 0.714136 * V
        b = Y + 1.772    * U
      } else {
        const Yc = Y - 16
        r = 1.164 * Yc             + 1.596    * V
        g = 1.164 * Yc - 0.392    * U - 0.813    * V
        b = 1.164 * Yc + 2.017    * U
      }

      const p     = (row * width + col) * 4
      rgba[p]     = r < 0 ? 0 : r > 255 ? 255 : r
      rgba[p + 1] = g < 0 ? 0 : g > 255 ? 255 : g
      rgba[p + 2] = b < 0 ? 0 : b > 255 ? 255 : b
      rgba[p + 3] = 255
    }
  }

  return rgba
}

function formatJoinError(reason) {
  switch (reason) {
    case "unsupported_codec":   return "Unsupported Codec"
    case "offline":             return "Camera Offline"
    case "stream_unavailable":  return "Unavailable Stream"
    default:                    return "Unknown Error"
  }
}
