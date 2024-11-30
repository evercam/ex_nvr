defmodule ExNVR.BundlexProject do
  @moduledoc false

  use Bundlex.Project

  def project() do
    [
      natives: natives()
    ]
  end

  defp natives() do
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
