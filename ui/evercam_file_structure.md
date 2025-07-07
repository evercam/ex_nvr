lib/ex_nvr.ex
├── lib/ex_nvr/accounts.ex
├── lib/ex_nvr/devices.ex
└── lib/ex_nvr/utils/utils.ex (export)
lib/ex_nvr/accounts.ex
├── lib/ex_nvr/accounts/user.ex (export)
├── lib/ex_nvr/accounts/user_notifier.ex
├── lib/ex_nvr/accounts/user_token.ex (export)
└── lib/ex_nvr/repo.ex
lib/ex_nvr/accounts/user.ex
└── lib/ex_nvr/repo.ex
lib/ex_nvr/accounts/user_notifier.ex
└── lib/ex_nvr/mailer.ex
lib/ex_nvr/accounts/user_token.ex
└── lib/ex_nvr/accounts/user.ex
lib/ex_nvr/authorization.ex
└── lib/ex_nvr/accounts/user.ex (export)
lib/ex_nvr/bif/generator_server.ex
├── lib/ex_nvr/bif/writer.ex
└── lib/ex_nvr/model/device.ex
lib/ex_nvr/bif/index.ex
lib/ex_nvr/bif/writer.ex
└── lib/ex_nvr/bif/index.ex
lib/ex_nvr/decoder.ex
├── lib/ex_nvr/decoder/h264.ex
└── lib/ex_nvr/decoder/h265.ex
lib/ex_nvr/decoder/h264.ex
└── lib/ex_nvr/decoder.ex (compile)
lib/ex_nvr/decoder/h265.ex
└── lib/ex_nvr/decoder.ex (compile)
lib/ex_nvr/devices.ex
├── lib/ex_nvr/devices/cameras/http_client/axis.ex
├── lib/ex_nvr/devices/cameras/http_client/hik.ex
├── lib/ex_nvr/devices/cameras/http_client/milesight.ex
├── lib/ex_nvr/devices/onvif.ex
├── lib/ex_nvr/devices/supervisor.ex
├── lib/ex_nvr/http.ex
├── lib/ex_nvr/model/device.ex (export)
├── lib/ex_nvr/model/recording.ex
├── lib/ex_nvr/model/run.ex
├── lib/ex_nvr/pipelines/main.ex
├── lib/ex_nvr/repo.ex
└── lib/ex_nvr/utils/utils.ex
lib/ex_nvr/devices/cameras/device_info.ex
lib/ex_nvr/devices/cameras/http_client.ex
lib/ex_nvr/devices/cameras/http_client/axis.ex
├── lib/ex_nvr/devices/cameras/device_info.ex (export)
├── lib/ex_nvr/devices/cameras/http_client.ex (compile)
├── lib/ex_nvr/devices/cameras/stream_profile.ex (export)
└── lib/ex_nvr/http.ex
lib/ex_nvr/devices/cameras/http_client/hik.ex
├── lib/ex_nvr/devices/cameras/device_info.ex
├── lib/ex_nvr/devices/cameras/http_client.ex (compile)
├── lib/ex_nvr/devices/cameras/stream_profile.ex
└── lib/ex_nvr/http.ex
lib/ex_nvr/devices/cameras/http_client/milesight.ex
├── lib/ex_nvr/devices/cameras/device_info.ex (export)
├── lib/ex_nvr/devices/cameras/http_client.ex (compile)
├── lib/ex_nvr/devices/cameras/stream_profile.ex (export)
└── lib/ex_nvr/http.ex
lib/ex_nvr/devices/cameras/stream_profile.ex
lib/ex_nvr/devices/lpr_event_puller.ex
├── lib/ex_nvr/devices.ex
└── lib/ex_nvr/events.ex
lib/ex_nvr/devices/onvif.ex
└── lib/ex_nvr/model/device.ex (export)
lib/ex_nvr/devices/snapshot_uploader.ex
├── lib/ex_nvr/devices.ex
├── lib/ex_nvr/model/device.ex
├── lib/ex_nvr/remote_storages.ex
├── lib/ex_nvr/remote_storages/remote_storage.ex (export)
└── lib/ex_nvr/remote_storages/store.ex
lib/ex_nvr/devices/supervisor.ex
├── lib/ex_nvr/bif/generator_server.ex
├── lib/ex_nvr/devices/lpr_event_puller.ex
├── lib/ex_nvr/devices/snapshot_uploader.ex
├── lib/ex_nvr/disk_monitor.ex
├── lib/ex_nvr/model/device.ex
├── lib/ex_nvr/pipelines/main.ex
├── lib/ex_nvr/unix_socket_server.ex
└── lib/ex_nvr/utils/utils.ex
lib/ex_nvr/disk.ex
lib/ex_nvr/disk_monitor.ex
└── lib/ex_nvr/recordings.ex
lib/ex_nvr/elements/cvs_bufferer.ex
├── lib/ex_nvr/decoder.ex
├── lib/ex_nvr/utils/media_utils.ex
└── lib/ex_nvr/utils/utils.ex (compile)
lib/ex_nvr/elements/funnel_tee.ex
└── lib/ex_nvr/pipeline/event/stream_closed.ex (export)
lib/ex_nvr/elements/realtimer.ex
lib/ex_nvr/elements/recording.ex
├── lib/ex_nvr/pipeline/track.ex
└── lib/ex_nvr/recordings/concatenater.ex
lib/ex_nvr/elements/video_stream_stat_reporter.ex
├── lib/ex_nvr/pipeline/event/stream_closed.ex (export)
├── lib/ex_nvr/pipeline/track/stat.ex (export)
└── lib/ex_nvr/utils/utils.ex (compile)
lib/ex_nvr/events.ex
├── lib/ex_nvr/events/event.ex (export)
├── lib/ex_nvr/events/lpr.ex
├── lib/ex_nvr/flop.ex
├── lib/ex_nvr/model/device.ex
└── lib/ex_nvr/repo.ex
lib/ex_nvr/events/event.ex
└── lib/ex_nvr/model/device.ex
lib/ex_nvr/events/lpr.ex
└── lib/ex_nvr/model/device.ex
lib/ex_nvr/flop.ex
└── lib/ex_nvr/repo.ex
lib/ex_nvr/hardware/serial_port_checker.ex
└── lib/ex_nvr/hardware/victron.ex
lib/ex_nvr/hardware/victron.ex
└── lib/ex_nvr/system_status.ex
lib/ex_nvr/hls/processor.ex
lib/ex_nvr/http.ex
lib/ex_nvr/image/scaler.ex
lib/ex_nvr/mailer.ex
lib/ex_nvr/model/device.ex
├── lib/ex_nvr/model/device/snapshot_config.ex
├── lib/ex_nvr/model/device/storage_config.ex
└── lib/ex_nvr/model/schedule.ex
lib/ex_nvr/model/device/snapshot_config.ex
└── lib/ex_nvr/model/schedule.ex
lib/ex_nvr/model/device/storage_config.ex
└── lib/ex_nvr/model/schedule.ex
lib/ex_nvr/model/recording.ex
├── lib/ex_nvr/model/device.ex
└── lib/ex_nvr/model/run.ex
lib/ex_nvr/model/run.ex
└── lib/ex_nvr/model/device.ex
lib/ex_nvr/model/schedule.ex
lib/ex_nvr/pipeline/event/stream_closed.ex
lib/ex_nvr/pipeline/output/hls.ex
├── lib/ex_nvr/pipeline/output/hls/timestamp_adjuster.ex
└── lib/ex_nvr/utils/utils.ex
lib/ex_nvr/pipeline/output/hls/timestamp_adjuster.ex
lib/ex_nvr/pipeline/output/socket.ex
└── lib/ex_nvr/pipeline/output/socket/sink.ex
lib/ex_nvr/pipeline/output/socket/sink.ex
lib/ex_nvr/pipeline/output/storage.ex
├── lib/ex_nvr/model/device.ex
├── lib/ex_nvr/model/run.ex (export)
├── lib/ex_nvr/pipeline/event/stream_closed.ex (export)
├── lib/ex_nvr/pipeline/output/storage/segment.ex
├── lib/ex_nvr/recordings.ex
├── lib/ex_nvr/utils/media_utils.ex (export)
└── lib/ex_nvr/utils/utils.ex (compile)
lib/ex_nvr/pipeline/output/storage/segment.ex
└── lib/ex_nvr/pipeline/output/storage/segment_metadata.ex (compile)
lib/ex_nvr/pipeline/output/storage/segment_metadata.ex
lib/ex_nvr/pipeline/output/thumbnailer.ex
├── lib/ex_nvr/decoder.ex
├── lib/ex_nvr/image/scaler.ex
└── lib/ex_nvr/utils/utils.ex (compile)
lib/ex_nvr/pipeline/output/web_rtc.ex
├── lib/ex_nvr/pipeline/event/stream_closed.ex (export)
├── lib/ex_nvr/rtp/h264_payloader.ex
└── lib/ex_nvr/rtp/h265_payloader.ex
lib/ex_nvr/pipeline/source/file.ex
├── lib/ex_nvr/model/device.ex
└── lib/ex_nvr/pipeline/track.ex
lib/ex_nvr/pipeline/source/rtsp.ex
├── lib/ex_nvr/model/device.ex
├── lib/ex_nvr/pipeline/track.ex
└── lib/ex_nvr/utils/utils.ex
lib/ex_nvr/pipeline/storage_monitor.ex
├── lib/ex_nvr/model/device.ex
├── lib/ex_nvr/model/schedule.ex
└── lib/ex_nvr/utils/utils.ex
lib/ex_nvr/pipeline/track.ex
lib/ex_nvr/pipeline/track/stat.ex
lib/ex_nvr/pipelines/hls_playback.ex
├── lib/ex_nvr/elements/realtimer.ex
├── lib/ex_nvr/elements/recording.ex (export)
└── lib/ex_nvr/pipeline/output/hls.ex (export)
lib/ex_nvr/pipelines/main.ex
├── lib/ex_nvr/devices.ex
├── lib/ex_nvr/elements/cvs_bufferer.ex
├── lib/ex_nvr/elements/funnel_tee.ex
├── lib/ex_nvr/elements/video_stream_stat_reporter.ex (export)
├── lib/ex_nvr/model/device.ex
├── lib/ex_nvr/pipeline/output/hls.ex (export)
├── lib/ex_nvr/pipeline/output/socket.ex (export)
├── lib/ex_nvr/pipeline/output/storage.ex (export)
├── lib/ex_nvr/pipeline/output/thumbnailer.ex (export)
├── lib/ex_nvr/pipeline/output/web_rtc.ex (export)
├── lib/ex_nvr/pipeline/source/file.ex (export)
├── lib/ex_nvr/pipeline/source/rtsp.ex (export)
├── lib/ex_nvr/pipeline/storage_monitor.ex
├── lib/ex_nvr/pipelines/main/state.ex (export)
├── lib/ex_nvr/recordings.ex
└── lib/ex_nvr/utils/utils.ex
lib/ex_nvr/pipelines/main/state.ex
lib/ex_nvr/pipelines/onvif_replay.ex
├── lib/ex_nvr/elements/funnel_tee.ex
└── lib/ex_nvr/pipeline/output/storage.ex (export)
lib/ex_nvr/recordings.ex
├── lib/ex_nvr/decoder.ex
├── lib/ex_nvr/flop.ex
├── lib/ex_nvr/model/device.ex (export)
├── lib/ex_nvr/model/recording.ex
├── lib/ex_nvr/model/run.ex (export)
├── lib/ex_nvr/recordings/video_assembler.ex
├── lib/ex_nvr/repo.ex
├── lib/ex_nvr/utils/media_utils.ex
└── lib/ex_nvr/utils/utils.ex
lib/ex_nvr/recordings/concatenater.ex
└── lib/ex_nvr/recordings.ex
lib/ex_nvr/recordings/video_assembler.ex
└── lib/ex_nvr/recordings/concatenater.ex
lib/ex_nvr/release.ex
lib/ex_nvr/remote_connection.ex
└── lib/ex_nvr/system_status.ex
lib/ex_nvr/remote_storages.ex
├── lib/ex_nvr/remote_storages/remote_storage.ex (export)
└── lib/ex_nvr/repo.ex
lib/ex_nvr/remote_storages/remote_storage.ex
lib/ex_nvr/remote_storages/store.ex
├── lib/ex_nvr/remote_storages/store/http.ex
└── lib/ex_nvr/remote_storages/store/s3.ex
lib/ex_nvr/remote_storages/store/http.ex
├── lib/ex_nvr/recordings.ex
└── lib/ex_nvr/remote_storages/store.ex
lib/ex_nvr/remote_storages/store/s3.ex
├── lib/ex_nvr/model/device.ex
├── lib/ex_nvr/recordings.ex
└── lib/ex_nvr/remote_storages/store.ex
lib/ex_nvr/repo.ex
lib/ex_nvr/rtp/h264_payloader.ex
lib/ex_nvr/rtp/h265_payloader.ex
lib/ex_nvr/system_status.ex
├── lib/ex_nvr/devices.ex
└── lib/ex_nvr/disk.ex
lib/ex_nvr/token_pruner.ex
└── lib/ex_nvr/accounts.ex
lib/ex_nvr/unix_socket_server.ex
└── lib/ex_nvr/utils/utils.ex
lib/ex_nvr/utils/media_utils.ex
└── lib/ex_nvr/decoder.ex
lib/ex_nvr/utils/utils.ex
lib/ex_nvr_web.ex
lib/ex_nvr_web/application.ex
├── lib/ex_nvr.ex
├── lib/ex_nvr/hardware/serial_port_checker.ex
├── lib/ex_nvr/remote_connection.ex
├── lib/ex_nvr/repo.ex
├── lib/ex_nvr/system_status.ex
├── lib/ex_nvr/token_pruner.ex
├── lib/ex_nvr_web/endpoint.ex
├── lib/ex_nvr_web/hls_streaming_monitor.ex
├── lib/ex_nvr_web/prom_ex.ex
└── lib/ex_nvr_web/telemetry.ex
lib/ex_nvr_web/channels/device_room_channel.ex
├── lib/ex_nvr/devices.ex
├── lib/ex_nvr/pipelines/main.ex
└── lib/ex_nvr_web.ex (compile)
lib/ex_nvr_web/channels/user_socket.ex
└── lib/ex_nvr_web/channels/device_room_channel.ex
lib/ex_nvr_web/components/core_components.ex
├── lib/ex_nvr_web/components/icon.ex
├── lib/ex_nvr_web/components/sidebar.ex
├── lib/ex_nvr_web/components/tabs.ex
└── lib/ex_nvr_web/gettext.ex
lib/ex_nvr_web/components/flop_config.ex
lib/ex_nvr_web/components/icon.ex
lib/ex_nvr_web/components/layouts.ex
├── lib/ex_nvr_web.ex (compile)
├── lib/ex_nvr_web/components/core_components.ex (export)
├── lib/ex_nvr_web/endpoint.ex
├── lib/ex_nvr_web/gettext.ex (export)
└── lib/ex_nvr_web/router.ex
lib/ex_nvr_web/components/sidebar.ex
├── lib/ex_nvr_web.ex (compile)
├── lib/ex_nvr_web/components/core_components.ex (export)
├── lib/ex_nvr_web/endpoint.ex
├── lib/ex_nvr_web/gettext.ex (export)
└── lib/ex_nvr_web/router.ex
lib/ex_nvr_web/components/tabs.ex
lib/ex_nvr_web/components/timeline.ex
lib/ex_nvr_web/controllers/api/device_controller.ex
├── lib/ex_nvr/authorization.ex (export)
├── lib/ex_nvr/devices.ex
├── lib/ex_nvr_web.ex (compile)
├── lib/ex_nvr_web/components/layouts.ex
├── lib/ex_nvr_web/controllers/api/fallback_controller.ex
├── lib/ex_nvr_web/endpoint.ex
├── lib/ex_nvr_web/gettext.ex (export)
├── lib/ex_nvr_web/plugs/device.ex
└── lib/ex_nvr_web/router.ex
lib/ex_nvr_web/controllers/api/device_json.ex
lib/ex_nvr_web/controllers/api/device_streaming_controller.ex
├── lib/ex_nvr/devices.ex
├── lib/ex_nvr/hls/processor.ex
├── lib/ex_nvr/model/device.ex
├── lib/ex_nvr/pipelines/hls_playback.ex
├── lib/ex_nvr/pipelines/main.ex
├── lib/ex_nvr/recordings.ex
├── lib/ex_nvr/utils/utils.ex
├── lib/ex_nvr_web.ex (compile)
├── lib/ex_nvr_web/components/layouts.ex
├── lib/ex_nvr_web/controllers/api/fallback_controller.ex
├── lib/ex_nvr_web/endpoint.ex
├── lib/ex_nvr_web/gettext.ex (export)
├── lib/ex_nvr_web/hls_streaming_monitor.ex
└── lib/ex_nvr_web/router.ex
lib/ex_nvr_web/controllers/api/event_controller.ex
├── lib/ex_nvr/events.ex
├── lib/ex_nvr/model/device.ex
├── lib/ex_nvr_web.ex (compile)
├── lib/ex_nvr_web/components/layouts.ex
├── lib/ex_nvr_web/controllers/api/fallback_controller.ex
├── lib/ex_nvr_web/endpoint.ex
├── lib/ex_nvr_web/gettext.ex (export)
├── lib/ex_nvr_web/lpr/parser/milesight.ex
└── lib/ex_nvr_web/router.ex
lib/ex_nvr_web/controllers/api/fallback_controller.ex
├── lib/ex_nvr_web.ex (compile)
├── lib/ex_nvr_web/components/layouts.ex
├── lib/ex_nvr_web/endpoint.ex
├── lib/ex_nvr_web/gettext.ex (export)
└── lib/ex_nvr_web/router.ex
lib/ex_nvr_web/controllers/api/onvif_controller.ex
├── lib/ex_nvr/authorization.ex (export)
├── lib/ex_nvr/devices/onvif.ex
├── lib/ex_nvr_web.ex (compile)
├── lib/ex_nvr_web/components/layouts.ex
├── lib/ex_nvr_web/controllers/api/fallback_controller.ex
├── lib/ex_nvr_web/endpoint.ex
├── lib/ex_nvr_web/gettext.ex (export)
└── lib/ex_nvr_web/router.ex
lib/ex_nvr_web/controllers/api/recording_controller.ex
├── lib/ex_nvr/recordings.ex
├── lib/ex_nvr_web.ex (compile)
├── lib/ex_nvr_web/components/layouts.ex
├── lib/ex_nvr_web/controllers/api/fallback_controller.ex
├── lib/ex_nvr_web/controllers/helpers.ex (export)
├── lib/ex_nvr_web/endpoint.ex
├── lib/ex_nvr_web/gettext.ex (export)
└── lib/ex_nvr_web/router.ex
lib/ex_nvr_web/controllers/api/remote_storage_controlller.ex
├── lib/ex_nvr/authorization.ex (export)
├── lib/ex_nvr/remote_storages.ex
├── lib/ex_nvr/remote_storages/remote_storage.ex (export)
├── lib/ex_nvr_web.ex (compile)
├── lib/ex_nvr_web/components/layouts.ex
├── lib/ex_nvr_web/controllers/api/fallback_controller.ex
├── lib/ex_nvr_web/controllers/helpers.ex (export)
├── lib/ex_nvr_web/endpoint.ex
├── lib/ex_nvr_web/gettext.ex (export)
└── lib/ex_nvr_web/router.ex
lib/ex_nvr_web/controllers/api/remote_storage_json.ex
lib/ex_nvr_web/controllers/api/system_status_controller.ex
├── lib/ex_nvr/authorization.ex (export)
├── lib/ex_nvr/system_status.ex
├── lib/ex_nvr_web.ex (compile)
├── lib/ex_nvr_web/components/layouts.ex
├── lib/ex_nvr_web/controllers/api/fallback_controller.ex
├── lib/ex_nvr_web/endpoint.ex
├── lib/ex_nvr_web/gettext.ex (export)
└── lib/ex_nvr_web/router.ex
lib/ex_nvr_web/controllers/api/user_controller.ex
├── lib/ex_nvr/accounts.ex
├── lib/ex_nvr/accounts/user.ex (export)
├── lib/ex_nvr/authorization.ex (export)
├── lib/ex_nvr_web.ex (compile)
├── lib/ex_nvr_web/components/layouts.ex
├── lib/ex_nvr_web/controllers/api/fallback_controller.ex
├── lib/ex_nvr_web/controllers/helpers.ex (export)
├── lib/ex_nvr_web/endpoint.ex
├── lib/ex_nvr_web/gettext.ex (export)
└── lib/ex_nvr_web/router.ex
lib/ex_nvr_web/controllers/api/user_json.ex
lib/ex_nvr_web/controllers/api/user_session_controller.ex
├── lib/ex_nvr/accounts.ex
├── lib/ex_nvr/accounts/user.ex (export)
├── lib/ex_nvr_web.ex (compile)
├── lib/ex_nvr_web/components/layouts.ex
├── lib/ex_nvr_web/controllers/api/fallback_controller.ex
├── lib/ex_nvr_web/endpoint.ex
├── lib/ex_nvr_web/gettext.ex (export)
└── lib/ex_nvr_web/router.ex
lib/ex_nvr_web/controllers/error_html.ex
├── lib/ex_nvr_web.ex (compile)
├── lib/ex_nvr_web/components/core_components.ex (export)
├── lib/ex_nvr_web/endpoint.ex
├── lib/ex_nvr_web/gettext.ex (export)
└── lib/ex_nvr_web/router.ex
lib/ex_nvr_web/controllers/error_json.ex
lib/ex_nvr_web/controllers/helpers.ex
└── lib/ex_nvr_web/controllers/error_json.ex
lib/ex_nvr_web/controllers/page_controller.ex
├── lib/ex_nvr_web.ex (compile)
├── lib/ex_nvr_web/components/layouts.ex
├── lib/ex_nvr_web/endpoint.ex
├── lib/ex_nvr_web/gettext.ex (export)
├── lib/ex_nvr_web/plugs/device.ex
└── lib/ex_nvr_web/router.ex
lib/ex_nvr_web/controllers/page_html.ex
├── lib/ex_nvr_web.ex (compile)
├── lib/ex_nvr_web/components/core_components.ex (export)
├── lib/ex_nvr_web/endpoint.ex
├── lib/ex_nvr_web/gettext.ex (export)
└── lib/ex_nvr_web/router.ex
lib/ex_nvr_web/controllers/user_session_controller.ex
├── lib/ex_nvr/accounts.ex
├── lib/ex_nvr_web.ex (compile)
├── lib/ex_nvr_web/components/layouts.ex
├── lib/ex_nvr_web/endpoint.ex
├── lib/ex_nvr_web/gettext.ex (export)
├── lib/ex_nvr_web/router.ex
└── lib/ex_nvr_web/user_auth.ex
lib/ex_nvr_web/endpoint.ex
├── lib/ex_nvr_web.ex (compile)
├── lib/ex_nvr_web/channels/user_socket.ex
├── lib/ex_nvr_web/plugs/cache_body_reader.ex (compile)
├── lib/ex_nvr_web/prom_ex.ex (compile)
└── lib/ex_nvr_web/router.ex
lib/ex_nvr_web/gettext.ex
lib/ex_nvr_web/hls_streaming_monitor.ex
lib/ex_nvr_web/live/dashboard_live.ex
├── lib/ex_nvr/devices.ex
├── lib/ex_nvr/model/device.ex
├── lib/ex_nvr/recordings.ex
├── lib/ex_nvr/utils/utils.ex
├── lib/ex_nvr_web.ex (compile)
├── lib/ex_nvr_web/components/core_components.ex (export)
├── lib/ex_nvr_web/components/layouts.ex
├── lib/ex_nvr_web/endpoint.ex
├── lib/ex_nvr_web/gettext.ex (export)
└── lib/ex_nvr_web/router.ex
lib/ex_nvr_web/live/device_list_live.ex
├── lib/ex_nvr/authorization.ex (export)
├── lib/ex_nvr/devices.ex
├── lib/ex_nvr/model/device.ex (export)
├── lib/ex_nvr_web.ex (compile)
├── lib/ex_nvr_web/components/core_components.ex (export)
├── lib/ex_nvr_web/components/layouts.ex
├── lib/ex_nvr_web/endpoint.ex
├── lib/ex_nvr_web/gettext.ex (export)
└── lib/ex_nvr_web/router.ex
lib/ex_nvr_web/live/device_live.ex
├── lib/ex_nvr/devices.ex
├── lib/ex_nvr/model/device.ex (export)
├── lib/ex_nvr/remote_storages.ex
├── lib/ex_nvr_web.ex (compile)
├── lib/ex_nvr_web/components/core_components.ex (export)
├── lib/ex_nvr_web/components/layouts.ex
├── lib/ex_nvr_web/endpoint.ex
├── lib/ex_nvr_web/gettext.ex (export)
└── lib/ex_nvr_web/router.ex
lib/ex_nvr_web/live/generic_events/events_list.ex
├── lib/ex_nvr/events.ex
├── lib/ex_nvr_web.ex (compile)
├── lib/ex_nvr_web/components/core_components.ex (export)
├── lib/ex_nvr_web/components/flop_config.ex
├── lib/ex_nvr_web/endpoint.ex
├── lib/ex_nvr_web/gettext.ex (export)
└── lib/ex_nvr_web/router.ex
lib/ex_nvr_web/live/generic_events/webhook_config.ex
├── lib/ex_nvr/accounts.ex
├── lib/ex_nvr_web.ex (compile)
├── lib/ex_nvr_web/components/core_components.ex (export)
├── lib/ex_nvr_web/endpoint.ex
├── lib/ex_nvr_web/gettext.ex (export)
└── lib/ex_nvr_web/router.ex
lib/ex_nvr_web/live/generic_events_live.ex
├── lib/ex_nvr/devices.ex
├── lib/ex_nvr_web.ex (compile)
├── lib/ex_nvr_web/components/core_components.ex (export)
├── lib/ex_nvr_web/components/layouts.ex
├── lib/ex_nvr_web/endpoint.ex
├── lib/ex_nvr_web/gettext.ex (export)
├── lib/ex_nvr_web/live/generic_events/events_list.ex
├── lib/ex_nvr_web/live/generic_events/webhook_config.ex
└── lib/ex_nvr_web/router.ex
lib/ex_nvr_web/live/lpr_events_list_live.ex
├── lib/ex_nvr/devices.ex
├── lib/ex_nvr/events.ex
├── lib/ex_nvr_web.ex (compile)
├── lib/ex_nvr_web/components/core_components.ex (export)
├── lib/ex_nvr_web/components/flop_config.ex
├── lib/ex_nvr_web/components/layouts.ex
├── lib/ex_nvr_web/endpoint.ex
├── lib/ex_nvr_web/gettext.ex (export)
└── lib/ex_nvr_web/router.ex
lib/ex_nvr_web/live/onvif/stream_profile.ex
├── lib/ex_nvr_web.ex (compile)
├── lib/ex_nvr_web/components/core_components.ex (export)
├── lib/ex_nvr_web/endpoint.ex
├── lib/ex_nvr_web/gettext.ex (export)
└── lib/ex_nvr_web/router.ex
lib/ex_nvr_web/live/onvif_discovery_live.ex
├── lib/ex_nvr/devices.ex
├── lib/ex_nvr/devices/onvif.ex
├── lib/ex_nvr_web.ex (compile)
├── lib/ex_nvr_web/components/core_components.ex (export)
├── lib/ex_nvr_web/components/layouts.ex
├── lib/ex_nvr_web/endpoint.ex
├── lib/ex_nvr_web/gettext.ex (export)
├── lib/ex_nvr_web/live/onvif/stream_profile.ex
└── lib/ex_nvr_web/router.ex
lib/ex_nvr_web/live/recordings_list_live.ex
├── lib/ex_nvr/devices.ex
├── lib/ex_nvr/recordings.ex
├── lib/ex_nvr_web.ex (compile)
├── lib/ex_nvr_web/components/core_components.ex (export)
├── lib/ex_nvr_web/components/flop_config.ex
├── lib/ex_nvr_web/components/layouts.ex
├── lib/ex_nvr_web/endpoint.ex
├── lib/ex_nvr_web/gettext.ex (export)
├── lib/ex_nvr_web/router.ex
└── lib/ex_nvr_web/view_utils.ex (export)
lib/ex_nvr_web/live/remote_storage_list_live.ex
├── lib/ex_nvr/remote_storages.ex
├── lib/ex_nvr_web.ex (compile)
├── lib/ex_nvr_web/components/core_components.ex (export)
├── lib/ex_nvr_web/components/layouts.ex
├── lib/ex_nvr_web/endpoint.ex
├── lib/ex_nvr_web/gettext.ex (export)
└── lib/ex_nvr_web/router.ex
lib/ex_nvr_web/live/remote_storage_live.ex
├── lib/ex_nvr/remote_storages.ex
├── lib/ex_nvr/remote_storages/remote_storage.ex (export)
├── lib/ex_nvr_web.ex (compile)
├── lib/ex_nvr_web/components/core_components.ex (export)
├── lib/ex_nvr_web/components/layouts.ex
├── lib/ex_nvr_web/endpoint.ex
├── lib/ex_nvr_web/gettext.ex (export)
└── lib/ex_nvr_web/router.ex
lib/ex_nvr_web/live/user_confirmation_instructions_live.ex
├── lib/ex_nvr/accounts.ex
├── lib/ex_nvr_web.ex (compile)
├── lib/ex_nvr_web/components/core_components.ex (export)
├── lib/ex_nvr_web/components/layouts.ex
├── lib/ex_nvr_web/endpoint.ex
├── lib/ex_nvr_web/gettext.ex (export)
└── lib/ex_nvr_web/router.ex
lib/ex_nvr_web/live/user_confirmation_live.ex
├── lib/ex_nvr/accounts.ex
├── lib/ex_nvr_web.ex (compile)
├── lib/ex_nvr_web/components/core_components.ex (export)
├── lib/ex_nvr_web/components/layouts.ex
├── lib/ex_nvr_web/endpoint.ex
├── lib/ex_nvr_web/gettext.ex (export)
└── lib/ex_nvr_web/router.ex
lib/ex_nvr_web/live/user_forgot_password_live.ex
├── lib/ex_nvr/accounts.ex
├── lib/ex_nvr_web.ex (compile)
├── lib/ex_nvr_web/components/core_components.ex (export)
├── lib/ex_nvr_web/components/layouts.ex
├── lib/ex_nvr_web/endpoint.ex
├── lib/ex_nvr_web/gettext.ex (export)
└── lib/ex_nvr_web/router.ex
lib/ex_nvr_web/live/user_list_live.ex
├── lib/ex_nvr/accounts.ex
├── lib/ex_nvr_web.ex (compile)
├── lib/ex_nvr_web/components/core_components.ex (export)
├── lib/ex_nvr_web/components/layouts.ex
├── lib/ex_nvr_web/endpoint.ex
├── lib/ex_nvr_web/gettext.ex (export)
└── lib/ex_nvr_web/router.ex
lib/ex_nvr_web/live/user_live.ex
├── lib/ex_nvr/accounts.ex
├── lib/ex_nvr/accounts/user.ex (export)
├── lib/ex_nvr_web.ex (compile)
├── lib/ex_nvr_web/components/core_components.ex (export)
├── lib/ex_nvr_web/components/layouts.ex
├── lib/ex_nvr_web/endpoint.ex
├── lib/ex_nvr_web/gettext.ex (export)
└── lib/ex_nvr_web/router.ex
lib/ex_nvr_web/live/user_login_live.ex
├── lib/ex_nvr_web.ex (compile)
├── lib/ex_nvr_web/components/core_components.ex (export)
├── lib/ex_nvr_web/components/layouts.ex
├── lib/ex_nvr_web/endpoint.ex
├── lib/ex_nvr_web/gettext.ex (export)
└── lib/ex_nvr_web/router.ex
lib/ex_nvr_web/live/user_registration_live.ex
├── lib/ex_nvr/accounts.ex
├── lib/ex_nvr/accounts/user.ex (export)
├── lib/ex_nvr_web.ex (compile)
├── lib/ex_nvr_web/components/core_components.ex (export)
├── lib/ex_nvr_web/components/layouts.ex
├── lib/ex_nvr_web/endpoint.ex
├── lib/ex_nvr_web/gettext.ex (export)
└── lib/ex_nvr_web/router.ex
lib/ex_nvr_web/live/user_reset_password_live.ex
├── lib/ex_nvr/accounts.ex
├── lib/ex_nvr_web.ex (compile)
├── lib/ex_nvr_web/components/core_components.ex (export)
├── lib/ex_nvr_web/components/layouts.ex
├── lib/ex_nvr_web/endpoint.ex
├── lib/ex_nvr_web/gettext.ex (export)
└── lib/ex_nvr_web/router.ex
lib/ex_nvr_web/live/user_settings_live.ex
├── lib/ex_nvr/accounts.ex
├── lib/ex_nvr_web.ex (compile)
├── lib/ex_nvr_web/components/core_components.ex (export)
├── lib/ex_nvr_web/components/layouts.ex
├── lib/ex_nvr_web/endpoint.ex
├── lib/ex_nvr_web/gettext.ex (export)
└── lib/ex_nvr_web/router.ex
lib/ex_nvr_web/lpr/parser.ex
lib/ex_nvr_web/lpr/parser/milesight.ex
└── lib/ex_nvr_web/lpr/parser.ex
lib/ex_nvr_web/navigation.ex
├── lib/ex_nvr_web.ex (compile)
├── lib/ex_nvr_web/components/core_components.ex (export)
├── lib/ex_nvr_web/components/layouts.ex
├── lib/ex_nvr_web/endpoint.ex
├── lib/ex_nvr_web/gettext.ex (export)
└── lib/ex_nvr_web/router.ex
lib/ex_nvr_web/plugs/cache_body_reader.ex
lib/ex_nvr_web/plugs/device.ex
├── lib/ex_nvr/devices.ex
├── lib/ex_nvr/model/device.ex (export)
└── lib/ex_nvr_web/controllers/helpers.ex (export)
lib/ex_nvr_web/prom_ex.ex
├── lib/ex_nvr_web/prom_ex/device.ex
├── lib/ex_nvr_web/prom_ex/device_stream.ex
├── lib/ex_nvr_web/prom_ex/recording.ex
└── lib/ex_nvr_web/prom_ex/system_status.ex
lib/ex_nvr_web/prom_ex/device.ex
├── lib/ex_nvr/devices.ex
└── lib/ex_nvr/model/device.ex
lib/ex_nvr_web/prom_ex/device_stream.ex
lib/ex_nvr_web/prom_ex/recording.ex
lib/ex_nvr_web/prom_ex/system_status.ex
└── lib/ex_nvr/system_status.ex
lib/ex_nvr_web/router.ex
├── lib/ex_nvr_web.ex (compile)
├── lib/ex_nvr_web/components/layouts.ex
├── lib/ex_nvr_web/controllers/api/device_controller.ex
├── lib/ex_nvr_web/controllers/api/device_streaming_controller.ex
├── lib/ex_nvr_web/controllers/api/event_controller.ex
├── lib/ex_nvr_web/controllers/api/onvif_controller.ex
├── lib/ex_nvr_web/controllers/api/recording_controller.ex
├── lib/ex_nvr_web/controllers/api/remote_storage_controlller.ex
├── lib/ex_nvr_web/controllers/api/system_status_controller.ex
├── lib/ex_nvr_web/controllers/api/user_controller.ex
├── lib/ex_nvr_web/controllers/api/user_session_controller.ex
├── lib/ex_nvr_web/controllers/page_controller.ex
├── lib/ex_nvr_web/controllers/user_session_controller.ex
├── lib/ex_nvr_web/navigation.ex
├── lib/ex_nvr_web/plugs/device.ex
├── lib/ex_nvr_web/telemetry.ex
└── lib/ex_nvr_web/user_auth.ex (export)
lib/ex_nvr_web/telemetry.ex
lib/ex_nvr_web/user_auth.ex
├── lib/ex_nvr/accounts.ex
├── lib/ex_nvr_web.ex (compile)
├── lib/ex_nvr_web/controllers/helpers.ex (export)
├── lib/ex_nvr_web/endpoint.ex
└── lib/ex_nvr_web/router.ex
lib/ex_nvr_web/view_utils.ex
