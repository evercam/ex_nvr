defmodule ExNVR.RecordingsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `ExNVR.Recordings` context.
  """

  alias ExNVR.Repo

  def valid_run_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      start_date: Faker.DateTime.backward(1),
      end_date: Faker.DateTime.forward(1),
      active: false
    })
  end

  def run_fixture(attrs \\ %{}) do
    {:ok, run} =
      attrs
      |> valid_run_attributes()
      |> then(&struct(ExNVR.Model.Run, &1))
      |> Repo.insert()

    run
  end
end
