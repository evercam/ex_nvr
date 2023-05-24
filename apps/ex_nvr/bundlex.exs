defmodule ExNVR.BundlexProject do
  use Bundlex.Project

  def project() do
    [
      natives: natives(Bundlex.platform())
    ]
  end

  def natives(_platform) do
    [
      mp4_depayloader: [
        interface: :nif,
        sources: ["mp4_depayloader.c"],
        pkg_configs: ["libavformat", "libavcodec"],
        preprocessor: Unifex
      ]
    ]
  end
end
