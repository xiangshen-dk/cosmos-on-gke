#!/bin/bash

# Script to check node status and ephemeral storage

echo "=== Node Status ==="
kubectl get nodes -o wide

echo -e "\n=== GPU Nodes ==="
kubectl get nodes -l cloud.google.com/gke-accelerator

echo -e "\n=== Node Resources ==="
kubectl describe nodes | grep -A 10 "Allocatable:" | grep -E "(ephemeral-storage|nvidia.com/gpu)"

echo -e "\n=== Ephemeral Storage Usage ==="
kubectl get nodes -o json | jq -r '.items[] | "\(.metadata.name): \(.status.allocatable."ephemeral-storage")"'

echo -e "\n=== Pod Status ==="
kubectl get pods -n cosmos -o wide

echo -e "\n=== Pod Events ==="
kubectl describe pod -n cosmos | grep -A 20 "Events:"
