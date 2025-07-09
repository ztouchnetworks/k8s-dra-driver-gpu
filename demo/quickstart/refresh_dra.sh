# !/bin/bash

# If the MIG setup is changed (ex: all-balanced -> all-2g.20gb), the nvidia dra driver will not notice until restarted
oc get pod -n nvidia | grep "nvidia-dra-driver-k8s-dra-driver-kubelet-plugin" | awk '{print $1}' | xargs kubectl delete pod -n nvidia
oc get pod -n nvidia | grep "nvidia-dra-driver-k8s-dra-driver-controller" | awk '{print $1}' | xargs kubectl delete pod -n nvidia