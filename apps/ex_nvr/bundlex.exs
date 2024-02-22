defmodule ExNVR.BundlexProject do
  @moduledoc false

  use Bundlex.Project

  def project() do
    [
      natives: natives(Bundlex.platform())
    ]
  end

  defp natives(_platform) do
    [
      video_assembler: [
        interface: :nif,
        sources: ["video_assembler.c"],
        os_deps: [
          ffmpeg: [
            {:precompiled, Membrane.PrecompiledDependencyProvider.get_dependency_url(:ffmpeg),
             ["libavformat"]},
            {:pkg_config, ["libavformat"]}
          ]
        ],
        preprocessor: Unifex
      ]
    ]
  end
end
