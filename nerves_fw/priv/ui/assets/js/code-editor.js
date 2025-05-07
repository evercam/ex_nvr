import "phoenix_html"
import { Socket } from "phoenix"
import { elixir } from "codemirror-lang-elixir"
import { LiveSocket } from "phoenix_live_view"
import { basicSetup} from "codemirror"
import { EditorView } from "@codemirror/view"
import { oneDark } from "@codemirror/theme-one-dark"
let CustomHooks = {}

console.log("XXXXXXXX")
CustomHooks.CodeEditor = {
  mounted() {
    this.editor = new EditorView({
      doc: "",
      extensions: [
          basicSetup, elixir(),
          oneDark,
          EditorView.lineWrapping,
          EditorView.updateListener.of(update => {
              this.editor.scrollDOM.style.height = "100%";
              this.editor.scrollDOM.style.width = "100%";
          })
      ],
      parent: this.el.querySelector(".editor-container")
    })

    this.el.querySelector("button.run").addEventListener("click", () => {
      const code = this.editor.state.doc.toString()
      this.pushEvent("run_code", { code })
    })

    this.handleEvent("evaluation_result", ({ result }) => {
      const output = this.el.querySelector("pre.result")
      output.textContent = result
    })
  }
}

console.log("window.Hooks: ", window.Hooks)
console.log("window.liveSocket: ", window.liveSocket)
if (window.liveSocket && window.Hooks) {
    window.Hooks = { ...window.Hooks, ...CustomHooks }
    let csrfToken = document
        .querySelector("meta[name='csrf-token']")
        .getAttribute("content")
    liveSocket.disconnect()
    liveSocket = new LiveSocket("/live", Socket, {
        params: { _csrf_token: csrfToken },
        hooks: Hooks,
    })
    liveSocket.connect()
}
