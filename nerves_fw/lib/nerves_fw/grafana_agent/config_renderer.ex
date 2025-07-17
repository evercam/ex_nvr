defmodule ExNVR.Nerves.GrafanaAgent.ConfigRenderer do
  @moduledoc """
  This module is used to render the YAML configuration file for
  GrafanaAgent.
  """

  @doc """
  Generate and write the GrafanaAgent config file.
  """
  @spec generate_config_file(opts :: map(), config_dir :: String.t()) :: String.t()
  def generate_config_file(opts, config_dir) do
    template_config = File.read!(template_file(opts))
    rendered_config = EEx.eval_string(template_config, assigns: opts)
    config_file_path = Path.join(config_dir, "agent.yml")
    File.write(config_file_path, rendered_config)
  end

  @spec generate_log_config(Keyword.t(), Path.t()) :: String.t()
  def generate_log_config(opts, config_file) do
    config = File.read!(config_file)

    if not String.contains?(config, "logs:") do
      template_config =
        template_file(opts)
        |> File.stream!(:line)
        |> Stream.drop_while(&(not String.starts_with?(&1, "logs:")))
        |> Stream.take_while(&(String.starts_with?(&1, "logs:") or String.match?(&1, ~r/^\s+/)))
        |> Enum.join()

      rendered_config = EEx.eval_string(template_config, assigns: opts)

      File.write!(config_file, config <> "\n\n" <> rendered_config)
    end
  end

  defp template_file(%{template_file: file}), do: file

  defp template_file(_) do
    :ex_nvr_fw
    |> :code.priv_dir()
    |> List.to_string()
    |> Path.join("/grafana_agent/config.yml.eex")
  end
end
