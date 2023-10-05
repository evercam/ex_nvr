defmodule ExNVR.RecordingsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `ExNVR.Recordings` context.
  """

  alias ExNVR.Repo

  def valid_recording_attributes(attrs \\ %{}) do
    start_date = attrs[:start_date] || Faker.DateTime.backward(1)

    Enum.into(attrs, %{
      start_date: start_date,
      end_date: DateTime.add(start_date, :rand.uniform(10) * 60),
      path: "../../fixtures/big_buck.mp4" |> Path.expand(__DIR__)
    })
  end

  def valid_run_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      start_date: Faker.DateTime.backward(1),
      end_date: Faker.DateTime.forward(1),
      active: false
    })
  end

  def recording_fixture(device, attrs \\ %{}) do
    {:ok, recording, _run} =
      attrs
      |> Enum.into(%{device_id: device.id})
      |> valid_recording_attributes()
      |> then(&ExNVR.Recordings.create(attrs[:run] || run_fixture(device), &1))

    recording
  end

  def run_fixture(device, attrs \\ %{}) do
    {:ok, run} =
      attrs
      |> Enum.into(%{device_id: device.id})
      |> valid_run_attributes()
      |> then(&struct(ExNVR.Model.Run, &1))
      |> Repo.insert()

    run
  end
end
