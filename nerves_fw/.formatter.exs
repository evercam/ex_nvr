# Used by "mix format"
[
  import_deps: [:ecto],
  inputs: [
    "{mix,.formatter}.exs",
    "{config,lib,test}/**/*.{heex,ex,exs}",
    "rootfs_overlay/etc/iex.exs"
  ],
  plugins: [Phoenix.LiveView.HTMLFormatter]
]
