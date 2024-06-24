#!/bin/bash

traversalFunc() {
  for file in "${1}"/*; do
    if [ -d "${file}" ]; then
      traversalFunc "${file}"
    else
      echo "${file}"
    fi
  done
}

traversalFunc "kubernetes"


