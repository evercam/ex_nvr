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
      def init! do
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

  @type t :: %__MODULE__{mod: module(), state: any()}
  defstruct [:mod, :state]

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

  @spec new!(atom()) :: t()
  def new!(:h264), do: %__MODULE__{mod: H264, state: H264.init!()}
  def new!(:h265), do: %__MODULE__{mod: H265, state: H265.init!()}

  @spec decode(t(), Buffer.t()) :: {:ok, [Buffer.t()]} | error()
  def decode(%__MODULE__{mod: mod, state: state}, buffer), do: mod.decode(state, buffer)

  @spec decode!(t(), Buffer.t()) :: [Buffer.t()]
  def decode!(%__MODULE__{mod: mod, state: state}, buffer), do: mod.decode!(state, buffer)

  @spec flush!(t()) :: [Buffer.t()]
  def flush!(%__MODULE__{mod: mod, state: state}), do: mod.flush!(state)
end
