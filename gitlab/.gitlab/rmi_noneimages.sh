#!/bin/bash
set -e

none_images=$(sudo docker images | grep none | awk '{print $3}')

for value in ${none_images[*]};
  do
    sudo docker rmi "$value"
  done