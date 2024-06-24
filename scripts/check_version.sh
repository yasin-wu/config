#!/bin/bash
# shellcheck disable=SC1083

docker_version=26.1.12
docker_compose_version=2.27.1

versionGTFunc() { test "$(echo "$@" | tr " " "\n" | sort -V | head -n 1)" != "$1"; }

if versionGTFunc "${docker_version}" "$(docker version -f {{.Server.Version}})"; then
   echo "docker version should greater than ${docker_version}, current version $(docker version -f {{.Server.Version}})"
   exit 1
fi

if versionGTFunc "${docker_compose_version}" "$(docker-compose version --short)"; then
   echo "docker-compose version should greater than ${docker_compose_version}, current version $(docker-compose version --short)"
   exit 1
fi

echo "check docker and docker-compose version pass"