defmodule ExNVR.AV.Hailo.OutputParser do
  @moduledoc """
  Behaviour for parsing Hailo network output.

  Models will encode data differently, so a different parser is needed for each model.

  For example, the Hailo YoloV8 model with embedded NMS-pruning outputs a run-length
  encoded binary with `N, ymin, xmin, ymax, xmax, score` for each class, where `N` can be 0.
  """
  @callback parse(binary(), opts :: keyword()) :: {:ok, term()} | {:error, term()}
end
