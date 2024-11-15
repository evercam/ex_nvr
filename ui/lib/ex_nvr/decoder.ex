defmodule ExNVR.Decoder do
  @moduledoc """
  A Behaviour module for implementing video decoders.
  """

  alias ExNVR.Decoder.{H264, H265}
  alias Membrane.Buffer

  @type decoder :: any()
  @type error :: {:error, reason :: any()}

  @callback init() :: {:ok, decoder()} | error()

  @callback init!() :: decoder()

  @callback decode(decoder(), buffer :: Buffer.t()) :: {:ok, [Buffer.t()]} | error()

  @callback decode!(decoder(), buffer :: Buffer.t()) :: [Buffer.t()]

  @callback flush(decoder()) :: {:ok, [Buffer.t()]} | error()

  @callback flush!(decoder()) :: [Buffer.t()]

  @optional_callbacks init!: 0, decode!: 2, flush!: 1

  defmacro __using__(_opts) do
    quote location: :keep do
      @behaviour ExNVR.Decoder

      @doc false
      def init!() do
        case init() do
          {:ok, decoder} -> decoder
          {:error, reason} -> raise "failed to create a decoder: #{inspect(reason)}"
        end
      end

      @doc false
      def decode!(decoder, buffer) do
        case decode(decoder, buffer) do
          {:ok, buffers} -> buffers
          {:error, reason} -> raise "failed to decode a buffer: #{inspect(reason)}"
        end
      end

      @doc false
      def flush!(decoder) do
        case flush(decoder) do
          {:ok, buffers} -> buffers
          {:error, reason} -> raise "failed to decode a buffer: #{inspect(reason)}"
        end
      end
    end
  end

  @spec new(atom()) :: {:ok, {module(), decoder()}} | error()
  def new(:h264) do
    case H264.init() do
      {:ok, decoder} -> {:ok, {H264, decoder}}
      error -> error
    end
  end

  def new(:h265) do
    case H265.init() do
      {:ok, decoder} -> {:ok, {H265, decoder}}
      error -> error
    end
  end

  @spec new!(atom()) :: {module(), decoder()}
  def new!(:h264), do: {H264, H264.init!()}
  def new!(:h265), do: {H265, H265.init!()}
end
