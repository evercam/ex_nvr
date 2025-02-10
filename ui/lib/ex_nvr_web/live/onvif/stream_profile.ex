defmodule ExNVRWeb.Onvif.StreamProfile do
  @moduledoc false

  use ExNVRWeb, :live_component

  require Logger

  alias Onvif.Media
  alias Onvif.Media.Ver20.Schemas.Profile.VideoEncoder

  def render(assigns) do
    ~H"""
    <div>
      <.simple_form
        :if={@edit_mode}
        for={@update_form}
        id={"update_profile_#{@id}"}
        phx-submit="update-profile"
        phx-target={@myself}
        class="w-full"
        actions_class="float-right"
      >
        <.input field={@update_form[:reference_token]} type="hidden" />
        <div class="w-full flex flex-wrap">
          <div class="w-full md:w-1/3 pr-5">
            <.input
              field={@update_form[:encoding]}
              id={"encoder_config_codec_#{@id}"}
              type="select"
              label="Encoding"
              options={codecs(@encoder_options)}
              phx-change="encoding-change"
              required
            />

            <.input
              field={@update_form[:profile]}
              id={"encoder_config_profile_#{@id}"}
              type="select"
              label="Profile"
              options={@view_encoder_options.profiles}
            />

            <.input
              field={@update_form[:gov_length]}
              id={"encoder_config_gov_#{@id}"}
              type="number"
              label="Gov Length"
              min={@view_encoder_options.gov_length_min}
              max={@view_encoder_options.gov_length_max}
            />
          </div>

          <div class="w-full md:w-1/3 pr-5">
            <.input
              field={@update_form[:quality]}
              id={"encoder_config_quality_#{@id}"}
              type="number"
              label="Image Quality"
              min={@view_encoder_options.quality_min}
              max={@view_encoder_options.quality_max}
            />

            <.input
              field={@update_form[:resolution]}
              id={"encoder_config_resolution_#{@id}"}
              type="select"
              label="Resolution"
              options={@view_encoder_options.resolutions}
            />
          </div>

          <div class="w-full md:w-1/3">
            <.inputs_for
              :let={rate_control}
              field={@update_form[:rate_control]}
              id={"encoder_config_resolution_#{@id}"}
            >
              <.input
                field={rate_control[:bitrate_limit]}
                id={"encoder_config_bit_rate_limit_#{@id}"}
                type="number"
                label="Max Bitrate"
                min={@view_encoder_options.bitrate_min}
                max={@view_encoder_options.bitrate_max}
              />

              <.input
                field={rate_control[:constant_bitrate]}
                id={"encoder_config_constant_bitrate_#{@id}"}
                type="select"
                label="Constant Bitrate"
                options={[{"True", true}, {"False", false}]}
              />

              <.input
                field={rate_control[:frame_rate_limit]}
                id={"encoder_config_frame_rate_#{@id}"}
                type="select"
                label="Frame Rate"
                options={@view_encoder_options.frame_rates}
              />
            </.inputs_for>
          </div>
        </div>

        <:actions>
          <.button phx-disable-with="Updating...">Update</.button>
          <.button
            type="button"
            phx-click="switch-profile-edit-mode"
            phx-value-edit="false"
            phx-target={@myself}
          >
            Cancel
          </.button>
        </:actions>
      </.simple_form>
      <div :if={not @edit_mode} class="text-sm md:text-l w-full flex flex-wrap justify-between">
        <div class="w-full flex justify-between">
          <h3 class="w-full font-bold text-xl">{@profile.name}</h3>
          <div class="flex">
            <button
              class="mr-3"
              phx-click="reorder-profiles"
              ,
              phx-value-token={@id}
              phx-value-direction="up"
            >
              <.icon name="hero-chevron-double-up-solid" class="w-4 h-4" />
            </button>
            <button
              class="mr-3"
              phx-click="reorder-profiles"
              ,
              phx-value-token={@id}
              phx-value-direction="down"
            >
              <.icon name="hero-chevron-double-down-solid" class="w-4 h-4" />
            </button>
            <button phx-click="switch-profile-edit-mode" phx-value-edit="true" phx-target={@myself}>
              <.icon name="hero-pencil-solid" class="w-4 h-4" />
            </button>
          </div>
        </div>
        <div class="md:w-2/5 p-5 dark:text-gray-400">
          <table class="w-full table-auto">
            <tr>
              <td class="font-bold">Codec</td>
              <td>{@profile.video_encoder_configuration.encoding}</td>
            </tr>
            <tr>
              <td class="font-bold">Profile</td>
              <td>{@profile.video_encoder_configuration.profile}</td>
            </tr>
            <tr>
              <td class="font-bold">Group of Pictures</td>
              <td>{@profile.video_encoder_configuration.gov_length}</td>
            </tr>
            <tr>
              <td class="font-bold">Image Quality</td>
              <td>{@profile.video_encoder_configuration.quality}</td>
            </tr>
          </table>
        </div>
        <div class="md:w-2/5 p-5 dark:text-gray-400">
          <table class="w-full table-auto">
            <tr>
              <td class="font-bold">Resolution</td>
              <td>
                {@profile.video_encoder_configuration.resolution.width} x {@profile.video_encoder_configuration.resolution.height}
              </td>
            </tr>
            <tr>
              <td class="font-bold">Constant Bitrate</td>
              <td>{@profile.video_encoder_configuration.rate_control.constant_bitrate}</td>
            </tr>
            <tr>
              <td class="font-bold">Frame rate</td>
              <td>{@profile.video_encoder_configuration.rate_control.frame_rate_limit} fps</td>
            </tr>
            <tr>
              <td class="font-bold">Max Bitrate</td>
              <td>{@profile.video_encoder_configuration.rate_control.bitrate_limit} kbps</td>
            </tr>
          </table>
        </div>
        <div class="w-full p-5 dark:text-gray-400">
          <table class="w-full table-auto">
            <tr>
              <td class="font-bold">Stream URI</td>
              <td class="break-all">{@stream_uri}</td>
            </tr>
            <tr>
              <td class="font-bold">Snapshot URI</td>
              <td class="break-all">{@snapshot_uri}</td>
            </tr>
          </table>
        </div>
      </div>
    </div>
    """
  end

  def mount(socket) do
    {:ok,
     assign(socket,
       edit_mode: false,
       update_form: nil,
       view_encoder_options: nil
     )}
  end

  def update(%{profile: profile, onvif_device: onvif_device, id: id}, socket) do
    old_profile = socket.assigns[:profile]

    if profile == old_profile do
      {:ok, socket}
    else
      socket =
        socket
        |> assign(profile: profile, id: id)
        |> assign(onvif_device: onvif_device)
        |> assign(
          update_form: to_form(profile.video_encoder_configuration |> VideoEncoder.changeset(%{}))
        )
        |> assign(snapshot_uri: snapshot_uri(profile, onvif_device))
        |> assign(stream_uri: stream_uri(profile, onvif_device))
        |> assign_new(:encoder_options, fn -> encoder_options(profile, onvif_device) end)

      send(self(), {:stream_uri, profile.reference_token, socket.assigns.stream_uri})
      send(self(), {:snapshot_uri, profile.reference_token, socket.assigns.snapshot_uri})

      {:ok,
       assign(socket,
         view_encoder_options:
           video_encoder_view_options(
             socket.assigns,
             profile.video_encoder_configuration.encoding
           )
       )}
    end
  end

  def handle_event("switch-profile-edit-mode", %{"edit" => edit}, socket) do
    {:noreply, assign(socket, edit_mode: String.to_existing_atom(edit))}
  end

  def handle_event("encoding-change", %{"video_encoder" => params}, socket) do
    encoding = String.to_existing_atom(params["encoding"])

    {:noreply,
     assign(socket, view_encoder_options: video_encoder_view_options(socket.assigns, encoding))}
  end

  def handle_event("update-profile", %{"video_encoder" => params}, socket) do
    profile = socket.assigns.profile

    params =
      Map.update!(params, "resolution", fn value ->
        [width, height] = String.split(value, "|", parts: 2)
        %{"width" => width, "height" => height}
      end)

    with {:ok, video_encoder} <- validate_encoder_params(profile, params),
         {:ok, _response} <-
           Media.Ver20.SetVideoEncoderConfiguration.request(
             socket.assigns.onvif_device,
             [video_encoder]
           ) do
      send(self(), {:profile_updated, profile.reference_token})
      {:noreply, assign(socket, edit_mode: false)}
    else
      {:error, reason} ->
        Logger.error(
          "Error occurred while updating video encoder configuration: #{inspect(reason)}"
        )

        {:noreply, put_flash(socket, :error, "could not update video encoder configuration")}
    end
  end

  defp snapshot_uri(profile, onvif_device) do
    {:ok, snapshot_uri} =
      Media.Ver10.GetSnapshotUri.request(onvif_device, [profile.reference_token])

    snapshot_uri
  end

  defp stream_uri(profile, onvif_device) do
    {:ok, stream_uri} = Media.Ver20.GetStreamUri.request(onvif_device, [profile.reference_token])
    stream_uri
  end

  defp encoder_options(profile, onvif_device) do
    case Media.Ver20.GetVideoEncoderConfigurationOptions.request(onvif_device, [
           nil,
           profile.reference_token
         ]) do
      {:ok, options} -> options
      _error -> []
    end
  end

  defp video_encoder_view_options(assigns, encoding) do
    config = Enum.find(assigns.encoder_options, &(&1.encoding == encoding))

    resolutions =
      Enum.map(
        config.resolutions_available,
        &{"#{&1.width} x #{&1.height}", "#{&1.width}|#{&1.height}"}
      )
      |> Enum.reverse()

    %{
      profiles: config.profiles_supported,
      gov_length_min: List.first(config.gov_length_range),
      gov_length_max: List.last(config.gov_length_range),
      quality_min: config.quality_range.min,
      quality_max: config.quality_range.max,
      resolutions: resolutions,
      bitrate_min: config.bitrate_range.min,
      bitrate_max: config.bitrate_range.max,
      frame_rates: config.frame_rates_supported
    }
  end

  defp validate_encoder_params(profile, params) do
    profile.video_encoder_configuration
    |> VideoEncoder.changeset(params)
    |> Ecto.Changeset.apply_action(:update)
  end

  defp codecs(encoder_options) do
    encoder_options
    |> Enum.map(&{to_string(&1.encoding) |> String.upcase(), &1.encoding})
    |> Enum.reverse()
  end
end

defimpl Phoenix.HTML.Safe, for: Onvif.Media.Ver20.Schemas.Profile.VideoEncoder.Resolution do
  def to_iodata(%{width: width, height: height}), do: "#{width}|#{height}"
end
