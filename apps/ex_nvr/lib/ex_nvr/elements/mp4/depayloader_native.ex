defmodule ExNVR.Elements.MP4.Depayloader.Native do
  @moduledoc false

  use Unifex.Loader

  @spec open_file!(binary()) :: reference()
  def open_file!(filename) do
    case open_file(filename) do
      {:ok, depayloader_ref, time_base_num, time_base_den} ->
        {depayloader_ref, {time_base_den, time_base_num}}

      {:error, reason} ->
        raise "Failed to open file #{filename}: #{inspect(reason)}"
    end
  end
end
