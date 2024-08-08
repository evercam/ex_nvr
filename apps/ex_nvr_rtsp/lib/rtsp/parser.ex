defmodule ExNVR.RTSP.Parser do
  @moduledoc """
  Behaviour to depayload and parse rtp packets.
  """

  @type state :: any()
  @type buffer :: Membrane.Buffer.t()

  @doc """
  Initialize deapyloader
  """
  @callback init(Keyword.t()) :: state()

  @doc """
  Invoked when a new RTP packet is received
  """
  @callback handle_packet(ExRTP.Packet.t(), state()) ::
              {:ok, {[buffer()], state()}} | {:error, any()}

  @doc """
  Invoked when a discontinuity occurred.

  A discontinuity occurs when an RTP packet is lost or missing by
  examining the sequence numbers.
  """
  @callback handle_discontinuity(state()) :: state()
end
