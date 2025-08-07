#include <erl_nif.h>

#ifdef NVR_DEBUG
#define NVR_LOG_DEBUG(X, ...)                                                  \
  fprintf(stderr, "[XAV DEBUG %s] %s:%d " X "\n", __TIME__, __FILE__,          \
          __LINE__, ##__VA_ARGS__)
#else
#define NVR_LOG_DEBUG(...)
#endif

ERL_NIF_TERM nif_ok(ErlNifEnv *env, ERL_NIF_TERM data_term);
ERL_NIF_TERM nif_error(ErlNifEnv *env, char *reason);
ERL_NIF_TERM nif_raise(ErlNifEnv *env, char *msg);

int nif_get_atom(ErlNifEnv *env, ERL_NIF_TERM term, char **value);
int nif_get_string(ErlNifEnv *env, ERL_NIF_TERM term, char **value);