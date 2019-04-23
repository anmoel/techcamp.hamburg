#!/bin/bash

export k8s_contexts="$(kubectl config get-contexts -o name)"

for k8s_context in $k8s_contexts
do
  echo "Cluster: $k8s_context"
  kubectl delete namespace istio-system --context="$k8s_context"
done
