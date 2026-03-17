#include "hailo/hailort.hpp"
#include <fine.hpp>
#include <map>
#include <memory>
#include <string>
#include <vector>

struct VDeviceResource {
  std::shared_ptr<hailort::VDevice> vdevice;
};

struct NetworkGroupResource {
  std::shared_ptr<hailort::ConfiguredNetworkGroup> network_group;
  std::shared_ptr<hailort::VDevice> vdevice;
};

struct InferPipelineResource {
  std::shared_ptr<hailort::InferVStreams> pipeline;
  std::shared_ptr<hailort::ConfiguredNetworkGroup> network_group;
};

FINE_RESOURCE(VDeviceResource);
FINE_RESOURCE(NetworkGroupResource);
FINE_RESOURCE(InferPipelineResource);

fine::Term fine_error_string(ErlNifEnv *env, const std::string &message) {
  std::tuple<fine::Atom, std::string> tagged_result(fine::Atom("error"),
                                                    message);
  return fine::encode(env, tagged_result);
}

template <typename T> fine::Term fine_ok(ErlNifEnv *env, T value) {
  std::tuple<fine::Atom, T> tagged_result(fine::Atom("ok"), value);
  return fine::encode(env, tagged_result);
}

fine::Atom format_type_to_atom(hailo_format_type_t type) {
  switch (type) {
  case HAILO_FORMAT_TYPE_AUTO:
    return fine::Atom("auto");
  case HAILO_FORMAT_TYPE_UINT8:
    return fine::Atom("uint8");
  case HAILO_FORMAT_TYPE_UINT16:
    return fine::Atom("uint16");
  case HAILO_FORMAT_TYPE_FLOAT32:
    return fine::Atom("float32");
  default:
    return fine::Atom("unknown_type");
  }
}

fine::Atom format_order_to_atom(hailo_format_order_t order) {
  switch (order) {
  case HAILO_FORMAT_ORDER_AUTO:
    return fine::Atom("auto");
  case HAILO_FORMAT_ORDER_NHWC:
    return fine::Atom("nhwc");
  case HAILO_FORMAT_ORDER_NHCW:
    return fine::Atom("nhcw");
  case HAILO_FORMAT_ORDER_NCHW:
    return fine::Atom("nchw");
  case HAILO_FORMAT_ORDER_FCR:
    return fine::Atom("fcr");
  case HAILO_FORMAT_ORDER_HAILO_NMS:
    return fine::Atom("hailo_nms");
  case HAILO_FORMAT_ORDER_HAILO_NMS_WITH_BYTE_MASK:
    return fine::Atom("hailo_nms_with_byte_mask");
  case HAILO_FORMAT_ORDER_HAILO_NMS_BY_CLASS:
    return fine::Atom("hailo_nms_by_class");
  default:
    return fine::Atom("unknown_order");
  }
}

fine::Atom format_flags_to_atom(hailo_format_flags_t flags) {
  if (flags == HAILO_FORMAT_FLAGS_NONE)
    return fine::Atom("none");
  if (flags == HAILO_FORMAT_FLAGS_TRANSPOSED)
    return fine::Atom("transposed");
  return fine::Atom("unknown_flags");
}

fine::Term create_vdevice(ErlNifEnv *env) {
  auto vdevice_expected = hailort::VDevice::create();
  if (!vdevice_expected) {
    return fine_error_string(env,
                             "Failed to create virtual device: " +
                                 std::to_string(vdevice_expected.status()));
  }
  auto vdevice = std::move(vdevice_expected.value());

  auto resource = fine::make_resource<VDeviceResource>();
  resource->vdevice = std::move(vdevice);
  return fine_ok(env, resource);
}

fine::Term configure_network_group(ErlNifEnv *env,
                                   fine::Term vdevice_resource_term,
                                   fine::Term hef_path_term) {
  fine::ResourcePtr<VDeviceResource> vdevice_res;
  try {
    vdevice_res = fine::decode<fine::ResourcePtr<VDeviceResource>>(
        env, vdevice_resource_term);
  } catch (const std::exception &e) {
    return fine_error_string(env, "Invalid VDevice resource");
  }

  std::string hef_path;
  try {
    hef_path = fine::decode<std::string>(env, hef_path_term);
  } catch (const std::exception &e) {
    return fine_error_string(env, "Invalid HEF file path");
  }

  auto hef = hailort::Hef::create(hef_path);
  if (!hef) {
    return fine_error_string(env, "Failed to load HEF file: " +
                                      std::to_string(hef.status()));
  }

  auto configure_params =
      vdevice_res->vdevice->create_configure_params(hef.value());
  if (!configure_params) {
    return fine_error_string(env,
                             "Failed to create configure params: " +
                                 std::to_string(configure_params.status()));
  }

  auto network_groups =
      vdevice_res->vdevice->configure(hef.value(), configure_params.value());
  if (!network_groups) {
    return fine_error_string(env, "Failed to configure network groups: " +
                                      std::to_string(network_groups.status()));
  }

  if (network_groups->size() != 1) {
    return fine_error_string(env, "Invalid number of network groups: " +
                                      std::to_string(network_groups->size()));
  }

  auto resource = fine::make_resource<NetworkGroupResource>();
  resource->network_group = std::move(network_groups->at(0));
  resource->vdevice = vdevice_res->vdevice;
  return fine_ok(env, resource);
}

fine::Term create_pipeline(ErlNifEnv *env, fine::Term network_group_term) {
  fine::ResourcePtr<NetworkGroupResource> ng_res;
  try {
    ng_res = fine::decode<fine::ResourcePtr<NetworkGroupResource>>(
        env, network_group_term);
  } catch (const std::exception &e) {
    return fine_error_string(env, "Invalid network group resource");
  }

  auto input_params = ng_res->network_group->make_input_vstream_params(
      {}, HAILO_FORMAT_TYPE_AUTO, HAILO_DEFAULT_VSTREAM_TIMEOUT_MS,
      HAILO_DEFAULT_VSTREAM_QUEUE_SIZE);
  if (!input_params) {
    return fine_error_string(env, "Failed to create input vstream params: " +
                                      std::to_string(input_params.status()));
  }

  auto output_params = ng_res->network_group->make_output_vstream_params(
      {}, HAILO_FORMAT_TYPE_AUTO, HAILO_DEFAULT_VSTREAM_TIMEOUT_MS,
      HAILO_DEFAULT_VSTREAM_QUEUE_SIZE);
  if (!output_params) {
    return fine_error_string(env, "Failed to create output vstream params: " +
                                      std::to_string(output_params.status()));
  }

  auto pipeline = hailort::InferVStreams::create(
      *ng_res->network_group, input_params.value(), output_params.value());
  if (!pipeline) {
    return fine_error_string(env, "Failed to create inference pipeline: " +
                                      std::to_string(pipeline.status()));
  }

  auto resource = fine::make_resource<InferPipelineResource>();
  resource->pipeline =
      std::make_shared<hailort::InferVStreams>(std::move(pipeline.value()));
  resource->network_group = ng_res->network_group;

  return fine_ok(env, resource);
}

ERL_NIF_TERM
build_detailed_vstream_info_map(ErlNifEnv *env,
                                const hailo_vstream_info_t &vstream_info) {
  ERL_NIF_TERM map_term = enif_make_new_map(env);
  uint32_t calculated_frame_size = 0;

  enif_make_map_put(env, map_term, fine::encode(env, fine::Atom("name")),
                    fine::encode(env, std::string(vstream_info.name)),
                    &map_term);

  enif_make_map_put(
      env, map_term, fine::encode(env, fine::Atom("network_name")),
      fine::encode(env, std::string(vstream_info.network_name)), &map_term);

  ERL_NIF_TERM direction_atom_term =
      (vstream_info.direction == HAILO_D2H_STREAM)
          ? fine::encode(env, fine::Atom("d2h"))
          : fine::encode(env, fine::Atom("h2d"));
  enif_make_map_put(env, map_term, fine::encode(env, fine::Atom("direction")),
                    direction_atom_term, &map_term);

  ERL_NIF_TERM format_map_erl = enif_make_new_map(env);
  hailo_format_order_t actual_format_order = vstream_info.format.order;
  enif_make_map_put(
      env, format_map_erl, fine::encode(env, fine::Atom("type")),
      fine::encode(env, format_type_to_atom(vstream_info.format.type)),
      &format_map_erl);
  enif_make_map_put(
      env, format_map_erl, fine::encode(env, fine::Atom("order")),
      fine::encode(env, format_order_to_atom(actual_format_order)),
      &format_map_erl);
  enif_make_map_put(
      env, format_map_erl, fine::encode(env, fine::Atom("flags")),
      fine::encode(env, format_flags_to_atom(vstream_info.format.flags)),
      &format_map_erl);
  enif_make_map_put(env, map_term, fine::encode(env, fine::Atom("format")),
                    format_map_erl, &map_term);

  bool is_nms =
      (actual_format_order == HAILO_FORMAT_ORDER_HAILO_NMS ||
       actual_format_order == HAILO_FORMAT_ORDER_HAILO_NMS_WITH_BYTE_MASK ||
       actual_format_order == HAILO_FORMAT_ORDER_HAILO_NMS_BY_CLASS);

  if (is_nms) {
    ERL_NIF_TERM nms_shape_map_erl = enif_make_new_map(env);
    enif_make_map_put(
        env, nms_shape_map_erl,
        fine::encode(env, fine::Atom("number_of_classes")),
        fine::encode(env, static_cast<uint64_t>(
                              vstream_info.nms_shape.number_of_classes)),
        &nms_shape_map_erl);

    enif_make_map_put(
        env, nms_shape_map_erl,
        fine::encode(env, fine::Atom("max_bboxes_per_class_or_total")),
        fine::encode(env, static_cast<uint64_t>(vstream_info.nms_shape.max_bboxes_total)),
        &nms_shape_map_erl);

    enif_make_map_put(env, map_term, fine::encode(env, fine::Atom("nms_shape")),
                      nms_shape_map_erl, &map_term);
    enif_make_map_put(env, map_term, fine::encode(env, fine::Atom("shape")),
                      fine::encode(env, fine::Atom("nil")), &map_term);

    calculated_frame_size = 0;

  } else {
    ERL_NIF_TERM shape_map_erl = enif_make_new_map(env);
    enif_make_map_put(
        env, shape_map_erl, fine::encode(env, fine::Atom("height")),
        fine::encode(env, static_cast<uint64_t>(vstream_info.shape.height)),
        &shape_map_erl);
    enif_make_map_put(
        env, shape_map_erl, fine::encode(env, fine::Atom("width")),
        fine::encode(env, static_cast<uint64_t>(vstream_info.shape.width)),
        &shape_map_erl);
    enif_make_map_put(
        env, shape_map_erl, fine::encode(env, fine::Atom("features")),
        fine::encode(env, static_cast<uint64_t>(vstream_info.shape.features)),
        &shape_map_erl);
    enif_make_map_put(env, map_term, fine::encode(env, fine::Atom("shape")),
                      shape_map_erl, &map_term);
    enif_make_map_put(env, map_term, fine::encode(env, fine::Atom("nms_shape")),
                      fine::encode(env, fine::Atom("nil")), &map_term);

    calculated_frame_size = hailort::HailoRTCommon::get_frame_size(
        vstream_info.shape, vstream_info.format);
  }

  enif_make_map_put(
      env, map_term, fine::encode(env, fine::Atom("frame_size")),
      fine::encode(env, static_cast<uint64_t>(calculated_frame_size)),
      &map_term);

  ERL_NIF_TERM quant_info_map_erl = enif_make_new_map(env);
  enif_make_map_put(
      env, quant_info_map_erl, fine::encode(env, fine::Atom("qp_zp")),
      fine::encode(env, static_cast<double>(vstream_info.quant_info.qp_zp)),
      &quant_info_map_erl);
  enif_make_map_put(
      env, quant_info_map_erl, fine::encode(env, fine::Atom("qp_scale")),
      fine::encode(env, static_cast<double>(vstream_info.quant_info.qp_scale)),
      &quant_info_map_erl);
  if (vstream_info.quant_info.qp_zp != 0.0f ||
      vstream_info.quant_info.qp_scale != 0.0f) {
    enif_make_map_put(env, map_term,
                      fine::encode(env, fine::Atom("quant_info")),
                      quant_info_map_erl, &map_term);
  } else {
    enif_make_map_put(env, map_term,
                      fine::encode(env, fine::Atom("quant_info")),
                      fine::encode(env, fine::Atom("nil")), &map_term);
  }

  return map_term;
}

fine::Term get_input_vstream_infos_from_ng(ErlNifEnv *env,
                                           fine::Term network_group_term) {
  fine::ResourcePtr<NetworkGroupResource> ng_res;
  try {
    ng_res = fine::decode<fine::ResourcePtr<NetworkGroupResource>>(
        env, network_group_term);
  } catch (const std::exception &e) {
    return fine_error_string(
        env, "Invalid network group resource for getting input vstream infos");
  }

  auto vstream_infos_expected =
      ng_res->network_group->get_input_vstream_infos();
  if (!vstream_infos_expected) {
    return fine_error_string(
        env, "Failed to get input vstream infos from network group: " +
                 std::to_string(vstream_infos_expected.status()));
  }

  std::vector<ERL_NIF_TERM> map_terms_vector;
  for (const auto &info : vstream_infos_expected.value()) {
    map_terms_vector.push_back(build_detailed_vstream_info_map(env, info));
  }
  ERL_NIF_TERM list_of_maps_term = enif_make_list_from_array(
      env, map_terms_vector.data(), map_terms_vector.size());
  return fine_ok(env, fine::Term(list_of_maps_term));
}

fine::Term get_output_vstream_infos_from_ng(ErlNifEnv *env,
                                            fine::Term network_group_term) {
  fine::ResourcePtr<NetworkGroupResource> ng_res;
  try {
    ng_res = fine::decode<fine::ResourcePtr<NetworkGroupResource>>(
        env, network_group_term);
  } catch (const std::exception &e) {
    return fine_error_string(
        env, "Invalid network group resource for getting output vstream infos");
  }

  auto vstream_infos_expected =
      ng_res->network_group->get_output_vstream_infos();
  if (!vstream_infos_expected) {
    return fine_error_string(
        env, "Failed to get output vstream infos from network group: " +
                 std::to_string(vstream_infos_expected.status()));
  }

  std::vector<ERL_NIF_TERM> map_terms_vector;
  for (const auto &info : vstream_infos_expected.value()) {
    map_terms_vector.push_back(build_detailed_vstream_info_map(env, info));
  }
  ERL_NIF_TERM list_of_maps_term = enif_make_list_from_array(
      env, map_terms_vector.data(), map_terms_vector.size());
  return fine_ok(env, fine::Term(list_of_maps_term));
}

fine::Term get_input_vstream_infos_from_pipeline(ErlNifEnv *env,
                                                 fine::Term pipeline_term) {
  fine::ResourcePtr<InferPipelineResource> pipeline_res;
  try {
    pipeline_res = fine::decode<fine::ResourcePtr<InferPipelineResource>>(
        env, pipeline_term);
  } catch (const std::exception &e) {
    return fine_error_string(
        env, "Invalid pipeline resource for getting input vstream infos");
  }

  auto all_ng_input_infos_expected =
      pipeline_res->network_group->get_input_vstream_infos();
  if (!all_ng_input_infos_expected) {
    return fine_error_string(
        env,
        "Failed to get input vstream infos from network group for pipeline: " +
            std::to_string(all_ng_input_infos_expected.status()));
  }
  const auto &all_ng_input_infos = all_ng_input_infos_expected.value();

  auto active_pipeline_input_vstreams =
      pipeline_res->pipeline->get_input_vstreams();
  std::vector<ERL_NIF_TERM> map_terms_vector;

  for (const auto &active_vstream_ref : active_pipeline_input_vstreams) {
    std::string active_name = active_vstream_ref.get().name();
    for (const auto &info_t : all_ng_input_infos) {
      if (std::string(info_t.name) == active_name) {
        map_terms_vector.push_back(
            build_detailed_vstream_info_map(env, info_t));
        break;
      }
    }
  }
  ERL_NIF_TERM list_of_maps_term = enif_make_list_from_array(
      env, map_terms_vector.data(), map_terms_vector.size());

  return fine_ok(env, fine::Term(list_of_maps_term));
}

fine::Term get_output_vstream_infos_from_pipeline(ErlNifEnv *env,
                                                  fine::Term pipeline_term) {
  fine::ResourcePtr<InferPipelineResource> pipeline_res;
  try {
    pipeline_res = fine::decode<fine::ResourcePtr<InferPipelineResource>>(
        env, pipeline_term);
  } catch (const std::exception &e) {
    return fine_error_string(
        env, "Invalid pipeline resource for getting output vstream infos");
  }

  auto all_ng_output_infos_expected =
      pipeline_res->network_group->get_output_vstream_infos();
  if (!all_ng_output_infos_expected) {
    return fine_error_string(
        env,
        "Failed to get output vstream infos from network group for pipeline: " +
            std::to_string(all_ng_output_infos_expected.status()));
  }
  const auto &all_ng_output_infos = all_ng_output_infos_expected.value();

  auto active_pipeline_output_vstreams =
      pipeline_res->pipeline->get_output_vstreams();
  std::vector<ERL_NIF_TERM> map_terms_vector;

  for (const auto &active_vstream_ref : active_pipeline_output_vstreams) {
    std::string active_name = active_vstream_ref.get().name();
    for (const auto &info_t : all_ng_output_infos) {
      if (std::string(info_t.name) == active_name) {
        map_terms_vector.push_back(
            build_detailed_vstream_info_map(env, info_t));
        break;
      }
    }
  }
  ERL_NIF_TERM list_of_maps_term = enif_make_list_from_array(
      env, map_terms_vector.data(), map_terms_vector.size());
  return fine_ok(env, fine::Term(list_of_maps_term));
}

fine::Term infer(ErlNifEnv *env, fine::Term pipeline_term,
                 fine::Term input_data_term) {
  fine::ResourcePtr<InferPipelineResource> pipeline_res;
  try {
    pipeline_res = fine::decode<fine::ResourcePtr<InferPipelineResource>>(
        env, pipeline_term);
  } catch (const std::exception &e) {
    return fine_error_string(env, "Invalid pipeline resource");
  }

  std::map<std::string, std::string> input_map;
  try {
    input_map =
        fine::decode<std::map<std::string, std::string>>(env, input_data_term);
  } catch (const std::exception &e) {
    return fine_error_string(env, "Input data must be a map");
  }

  auto input_vstreams = pipeline_res->pipeline->get_input_vstreams();
  auto output_vstreams = pipeline_res->pipeline->get_output_vstreams();

  std::map<std::string, hailort::MemoryView> input_data_mem_views;
  const size_t frames_count = 1;

  for (const auto &input_vstream : input_vstreams) {
    std::string name = input_vstream.get().name();
    auto it = input_map.find(name);
    if (it == input_map.end()) {
      return fine_error_string(env, "Missing input data for vstream: " + name);
    }
    std::string &binary = it->second;
    size_t expected_size = input_vstream.get().get_frame_size() * frames_count;
    if (binary.size() != expected_size) {
      return fine_error_string(
          env, "Invalid input data size for vstream " + name +
                   ". Expected: " + std::to_string(expected_size) +
                   ", Got: " + std::to_string(binary.size()));
    }
    input_data_mem_views.emplace(
        name, hailort::MemoryView(
                  const_cast<void *>(static_cast<const void *>(binary.data())),
                  binary.size()));
  }

  std::map<std::string, std::vector<uint8_t>> output_data;
  std::map<std::string, hailort::MemoryView> output_data_mem_views;
  for (const auto &output_vstream : output_vstreams) {
    std::string name = output_vstream.get().name();
    size_t frame_size = output_vstream.get().get_frame_size();
    output_data.emplace(name, std::vector<uint8_t>(frame_size * frames_count));
    auto &output_buffer = output_data[name];
    output_data_mem_views.emplace(
        name, hailort::MemoryView(output_buffer.data(), output_buffer.size()));
  }

  hailo_status status = pipeline_res->pipeline->infer(
      input_data_mem_views, output_data_mem_views, frames_count);
  if (status != HAILO_SUCCESS) {
    return fine_error_string(env, "Inference failed with status: " +
                                      std::to_string(status));
  }

  std::map<std::string, std::string> output_map;
  for (const auto &output_vstream : output_vstreams) {
    std::string name = output_vstream.get().name();
    const auto &output_buffer = output_data[name];
    output_map[name] =
        std::string(reinterpret_cast<const char *>(output_buffer.data()),
                    output_buffer.size());
  }

  return fine_ok(env, output_map);
}

FINE_NIF(create_pipeline, 1);
FINE_NIF(get_output_vstream_infos_from_pipeline, 1);
FINE_NIF(infer, 2);
FINE_NIF(create_vdevice, 0);
FINE_NIF(configure_network_group, 2);
FINE_NIF(get_input_vstream_infos_from_ng, 1);
FINE_NIF(get_output_vstream_infos_from_ng, 1);
FINE_NIF(get_input_vstream_infos_from_pipeline, 1);

FINE_INIT("Elixir.ExNVR.AV.Hailo.NIF");
