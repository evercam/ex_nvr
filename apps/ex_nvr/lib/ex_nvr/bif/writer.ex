defmodule ExNVR.BIF.Writer do
  @moduledoc """
  Bundle images as BIF (Base Index Frames) files.
  """

  alias ExNVR.BIF.Index

  @type t :: %__MODULE__{
          device: IO.device(),
          index: Index.t(),
          path: Path.t()
        }

  @typep unix_timestamp :: integer()

  @enforce_keys [:device, :index, :path]
  defstruct @enforce_keys

  @magic_number <<0x894249460D0A1A0A::64>>
  @version <<0::32>>
  @reserverd <<0::44*8>>

  @doc """
  Create a new BIF writer
  """
  @spec new(Path.t()) :: t()
  def new(out_path) do
    with {:ok, io_device} <- File.open(out_path <> ".tmp", [:binary, :read, :write]) do
      %__MODULE__{
        device: io_device,
        index: Index.new(),
        path: out_path
      }
    end
  end

  @spec write(t(), binary(), unix_timestamp()) :: t() | {:error, term()}
  def write(%__MODULE__{} = writer, image, timestamp) do
    index = Index.add_entry(writer.index, timestamp, byte_size(image))

    with :ok <- IO.binwrite(writer.device, image) do
      %__MODULE__{writer | index: index}
    end
  end

  @spec write!(t(), binary(), unix_timestamp()) :: t()
  def write!(%__MODULE__{} = writer, image, timestamp) do
    case write(writer, image, timestamp) do
      {:error, error} -> raise("could not write image to BIF file: #{inspect(error)}")
      writer -> writer
    end
  end

  @spec finalize(t()) :: :ok | {:error, term()}
  def finalize(%__MODULE__{device: io_device} = writer) do
    with {:ok, io} <- File.open(writer.path, [:binary, :write]),
         :ok <- IO.binwrite(io, build_header(writer.index)),
         {:ok, 0} <- :file.position(io_device, :bof),
         {:ok, _bytes_copied} <- :file.copy(io_device, io),
         :ok <- File.close(io),
         :ok <- File.close(io_device) do
      File.rm(writer.path <> ".tmp")
    end
  end

  @spec finalize!(t()) :: :ok
  def finalize!(%__MODULE__{} = writer) do
    case finalize(writer) do
      :ok -> :ok
      {:error, error} -> raise("could not finalize BIF: #{inspect(error)}")
    end
  end

  defp build_header(index) do
    <<@magic_number, @version, Index.count(index)::32-integer-little, 0::32, @reserverd::binary,
      Index.serialize(index)::binary>>
  end
end
