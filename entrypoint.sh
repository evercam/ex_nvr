#!/bin/sh

bin/ex_nvr eval "ExNVR.Release.migrate"

exec "$@"