defmodule ExNVRWeb.LPR.Parser do
  @moduledoc """
  Behaviour describing parsing incoming LPR event
  """

  @type plate_image :: binary() | nil
  @type timezone :: binary()

  @callback parse(term(), timezone()) :: {map(), binary() | plate_image()}
end
