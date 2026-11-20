defmodule ExNVR.Nerves.ErrorReportingTest do
  @moduledoc false
  use ExUnit.Case, async: false

  import Mimic

  alias ExNVR.Nerves.ErrorReporting
  alias ExNVR.Nerves.ErrorReporting.{NervesHubReporter, SentryEnricher}

  setup :verify_on_exit!

  setup_all do
    Mimic.copy(NervesHubLink)
    :ok
  end

  setup do
    :persistent_term.put(ErrorReporting, %{
      serial: "nvr-0042",
      firmware_uuid: "6f0c1a8e-6b6e-5c1f-9a4f-1f3c2e7d9b10",
      firmware_version: "0.30.0",
      kit_id: "kit-123"
    })

    Application.put_env(
      :ex_nvr_fw,
      :nerves_hub_devices_url,
      "https://manage.nervescloud.com/org/Evercam/ex_nvr_fw/devices"
    )

    on_exit(fn ->
      :persistent_term.erase(ErrorReporting)
      Application.delete_env(:ex_nvr_fw, :nerves_hub_devices_url)
    end)
  end

  describe "NervesHubReporter.report/3" do
    test "sends the group and stringified details, with the report ID" do
      error = %RuntimeError{message: "Failed to set router schedule"}

      expect(NervesHubLink, :report_error, fn ^error, [], opts ->
        assert opts[:group] == "rut:set_scheduler"

        assert opts[:context] == %{
                 "reason" => ":timeout",
                 "router" => "rut241",
                 "report_id" => "9f86d081884c7d65"
               }

        :ok
      end)

      NervesHubReporter.report(error, [],
        group: "rut:set_scheduler",
        extra: %{reason: :timeout, router: "rut241", missing: nil},
        report_id: "9f86d081884c7d65"
      )
    end

    test "leaves out details that are missing" do
      expect(NervesHubLink, :report_error, fn _error, [], opts ->
        assert opts[:context] == %{}
        :ok
      end)

      NervesHubReporter.report(%RuntimeError{message: "boom"}, [],
        group: nil,
        extra: %{},
        report_id: nil
      )
    end
  end

  describe "SentryEnricher.before_send/1" do
    test "sets the release from the running firmware and tags the device" do
      event = %Sentry.Event{
        event_id: "abc123",
        timestamp: "2026-11-18T10:00:00Z",
        release: "ex_nvr@0.29.0",
        tags: %{"existing" => "kept"},
        extra: %{"reason" => "timeout"}
      }

      event = SentryEnricher.before_send(event)

      assert event.release == "ex_nvr@0.30.0"

      assert event.tags == %{
               "existing" => "kept",
               "nerves_hub.device" => "nvr-0042",
               "firmware_uuid" => "6f0c1a8e-6b6e-5c1f-9a4f-1f3c2e7d9b10",
               "kit_id" => "kit-123"
             }

      assert event.extra == %{
               "reason" => "timeout",
               "nerves_hub_errors" =>
                 "https://manage.nervescloud.com/org/Evercam/ex_nvr_fw/devices/nvr-0042/errors"
             }
    end

    test "keeps the configured release and skips the link when they are unknown" do
      :persistent_term.put(ErrorReporting, %{
        serial: "nvr-0042",
        firmware_uuid: nil,
        firmware_version: nil,
        kit_id: nil
      })

      Application.delete_env(:ex_nvr_fw, :nerves_hub_devices_url)

      event =
        SentryEnricher.before_send(%Sentry.Event{
          event_id: "abc123",
          timestamp: "2026-11-18T10:00:00Z",
          release: "ex_nvr@0.29.0"
        })

      assert event.release == "ex_nvr@0.29.0"
      assert event.tags == %{"nerves_hub.device" => "nvr-0042"}
      assert event.extra == %{}
    end
  end

  test "nerves_hub_context/0 sends the kit ID when there is one" do
    assert ErrorReporting.nerves_hub_context() == %{"kit_id" => "kit-123"}

    :persistent_term.put(ErrorReporting, %{
      serial: "nvr-0042",
      firmware_uuid: nil,
      firmware_version: nil,
      kit_id: nil
    })

    assert ErrorReporting.nerves_hub_context() == %{}
  end
end
