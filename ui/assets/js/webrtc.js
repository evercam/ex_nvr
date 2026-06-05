import { Socket } from "phoenix"

window.onload = function (_event) {
    const player = document.getElementById("webRtcPlayer")
    const canvas = document.getElementById("hevcCanvas")
    const logsComponent = document.getElementById("webRtcLogs")
    const deviceId = player.dataset.device
    const stream = player.dataset.stream
    const pc = new RTCPeerConnection({ iceServers: [{ urls: 'stun:stun.l.google.com:19302' }] });

    const socket = new Socket("/socket", {params: {token: window.token}})
    const channel = socket.channel(`device:${deviceId}`, {stream: stream})

    function log(message) {
        if (!logsComponent) {
            return
        }

        logsComponent.innerHTML += "\n\n" + message
        logsComponent.scrollTop = logsComponent.scrollHeight
    }

    channel.join()
        .receive("ok", resp => {
            const codec = resp && resp.codec
            log("Joined channel successfully (codec=" + codec + ")")

            if (is_hevc(codec) && !browser_supports_hevc()) {
                log("HEVC not supported by browser, falling back to libav wasm decoder")
                channel.leave()
                pc.close()
                socket.disconnect()
                fallback_to_libav()
            }
        })
        .receive("error", reason => {
            log("Unable to join channel: " + format_join_error(reason))
            alert("could not join channel: " + format_join_error(reason))
            channel.leave()
        })

    // ICE candidates can arrive before we've finished applying the remote
    // description; adding them too early throws. Buffer until the remote
    // description is set, then flush.
    let remoteDescriptionSet = false
    const pendingCandidates = []

    channel.on("offer", async ({ data }) => {
        log("Received offer: " + data)

        try {
            await pc.setRemoteDescription(JSON.parse(data))
            remoteDescriptionSet = true

            for (const candidate of pendingCandidates.splice(0)) {
                await pc.addIceCandidate(candidate)
            }

            const answer = await pc.createAnswer()
            await pc.setLocalDescription(answer)
            channel.push("answer", JSON.stringify(answer))
        } catch (err) {
            log("Failed to handle offer: " + err)
        }
    })

    channel.on("ice_candidate", async ({ data }) => {
        log("received new ice candidate: " + data)
        const candidate = JSON.parse(data)

        if (!remoteDescriptionSet) {
            pendingCandidates.push(candidate)
            return
        }

        try {
            await pc.addIceCandidate(candidate)
        } catch (err) {
            log("Failed to add ice candidate: " + err)
        }
    })

    pc.onicecandidate = (event) => {
        log("new local ice candidate: " + JSON.stringify(event.candidate))
        if (event.candidate) {
            channel.push("ice_candidate", JSON.stringify(event.candidate))
        }
    }

    pc.ontrack = (track) => {
        log("received new track: " + JSON.stringify(track))
        player.srcObject = track.streams[0]
    }

    pc.onconnectionstatechange = (event) => {
        log("connection state: " + pc.connectionState)

        if (pc.connectionState == "failed" || pc.connectionState == "disconnected") {
            alert("connection lost, refresh browser to retry")
            channel.leave()
            pc.close()
            socket.disconnect()
        }
    }

    socket.connect()

    async function fallback_to_libav() {
        if (canvas) {
            canvas.style.display = "block"
        }
        if (player) {
            player.style.display = "none"
            player.srcObject = null
        }

        try {
            const { startLibavPlayer } = await import("./libav-player.js")
            startLibavPlayer({
                deviceId,
                stream,
                canvas,
                logEl: logsComponent,
                token: window.token,
            })
        } catch (err) {
            log("Failed to load libav player: " + err)
        }
    }
}

function is_hevc(codec) {
    if (!codec) return false
    const c = String(codec).toLowerCase()
    return c === "h265" || c === "hevc"
}

function browser_supports_hevc() {
    if (typeof RTCRtpReceiver === "undefined" || !RTCRtpReceiver.getCapabilities) {
        return false
    }
    const caps = RTCRtpReceiver.getCapabilities("video")
    if (!caps || !caps.codecs) return false
    return caps.codecs.some(c => /h265|hevc/i.test(c.mimeType || ""))
}

function format_join_error(error) {
    switch (error) {
        case "unsupported_codec":
            return "Unsupported Codec"
        case "offline":
            return "Camera Offline"
        case "stream_unavailable":
            return "Unavailable Stream"
        default:
            return "Unknown Error"
    }
}
