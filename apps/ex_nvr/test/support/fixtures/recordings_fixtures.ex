defmodule ExNVR.RecordingsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `ExNVR.Recordings` context.
  """

  alias ExNVR.Repo
  alias ExNVR.Model.{Device, Recording, Run}

  @typep attr :: map() | keyword()

  @avc1_file "../../fixtures/mp4/big_buck_avc.mp4" |> Path.expand(__DIR__)
  @hvc1_file "../../fixtures/mp4/big_buck_hevc.mp4" |> Path.expand(__DIR__)

  @spec valid_recording_attributes(attr()) :: map()
  def valid_recording_attributes(attrs \\ %{}) do
    start_date = attrs[:start_date] || Faker.DateTime.backward(1)

    file_path =
      case Map.fetch(attrs, :encoding) do
        {:ok, :H265} -> @hvc1_file
        _other -> @avc1_file
      end

    Enum.into(attrs, %{
      start_date: start_date,
      end_date: DateTime.add(start_date, :rand.uniform(10) * 60),
      path: file_path
    })
  end

  @spec valid_run_attributes(attr()) :: map()
  def valid_run_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      start_date: Faker.DateTime.backward(1),
      end_date: Faker.DateTime.forward(1),
      active: false
    })
  end

  @spec recording_fixture(Device.t(), attr()) :: Recording.t()
  def recording_fixture(device, attrs \\ %{}) do
    {:ok, recording, _run} =
      attrs
      |> Enum.into(%{device_id: device.id})
      |> valid_recording_attributes()
      |> tap(
        &File.mkdir_p!(
          Path.dirname(ExNVR.Recordings.recording_path(device, attrs[:stream] || :high, &1))
        )
      )
      |> then(&ExNVR.Recordings.create(device, attrs[:run] || run_fixture(device), &1))

    recording
  end

  @spec run_fixture(Device.t(), attr()) :: Run.t()
  def run_fixture(device, attrs \\ %{}) do
    {:ok, run} =
      attrs
      |> Enum.into(%{device_id: device.id})
      |> valid_run_attributes()
      |> then(&Run.changeset(%Run{}, &1))
      |> Repo.insert()

    run
  end
end
