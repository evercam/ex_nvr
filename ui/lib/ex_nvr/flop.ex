defmodule ExNVR.Flop do
  @moduledoc """
  Flop global configuration module for filtering and pagination.
  """
  use Flop, repo: ExNVR.Repo, default_limit: 100
end
