#include "fine.hpp"
#include "../include/BYTETracker.h"
#include "../include/Object.h"
#include <vector>
#include <tuple>

using namespace byte_track;
using namespace std;

typedef tuple<double, double, double, double, int64_t> Track;

fine::ResourcePtr<BYTETracker> create_tracker(ErlNifEnv* env) {
    return fine::make_resource<BYTETracker>();
}

vector<Track> update(ErlNifEnv* env, vector<tuple<double, double, double, double, int64_t, double>> objects, fine::ResourcePtr<BYTETracker> tracker) {
    vector<Object> objects_vec;
    for (const auto& obj : objects) {
        float x1, y1, x2, y2, score;
        int cls;
        tie(x1, y1, x2, y2, cls, score) = obj;
        objects_vec.emplace_back(Rect<float>(x1, y1, x2, y2), cls, score);
    }

    auto results = tracker->update(objects_vec);
    vector<Track> tracks;
    for (const auto& track : results) {
        auto rect = track->getRect();
        tracks.emplace_back(
            Track{rect.x(), rect.y(), rect.width(), rect.height(), static_cast<int64_t>(track->getTrackId())}
        );
    }

    return tracks;
}

FINE_RESOURCE(BYTETracker);

FINE_NIF(create_tracker, 0);
FINE_NIF(update, 2);

FINE_INIT("Elixir.ExNVR.AV.ByteTrack.NIF");
