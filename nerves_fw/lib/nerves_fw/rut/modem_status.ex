defmodule ExNVR.Nerves.RUT.ModemStatus do
  @moduledoc false

  @derive Jason.Encoder
  defstruct [
    :id,
    :imei,
    :model,
    :name,
    :state,
    :txbytes,
    :rxbytes,
    :provider,
    :signal,
    :temperature,
    :connection_type
  ]

  @spec from_response(map()) :: %__MODULE__{}
  def from_response(data) do
    %__MODULE__{
      id: data["id"],
      imei: data["imei"],
      model: data["model"],
      name: data["name"],
      state: data["state"],
      txbytes: data["txbytes"],
      rxbytes: data["rxbytes"],
      provider: data["provider"],
      signal: data["signal"],
      temperature: data["temperature"],
      connection_type: data["conntype"]
    }
  end
end
