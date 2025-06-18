# Running the NVIDIA DRA Driver on Red Hat OpenShift

This document details how to install and run the NVIDIA DRA driver on Openshift 4.18

## Prerequisites

1. OpenShift 4.18
2. OpenShift CLI `oc`
3. NVIDIA GPU Operator
4. OpenShift DRA

## Installation Walkthrough

### Install OpenShift

Install OpenShift 4.18. You can use the Assisted Installer to install on bare metal, or obtain an IPI installer binary (`openshift-install`) from the [OpenShift clients page](https://mirror.openshift.com/pub/openshift-v4/clients/ocp/) page. Refer to the [OpenShift documentation](https://docs.redhat.com/en/documentation/openshift_container_platform/latest/html/installation_overview/ocp-installation-overview) for different installation methods.

### Install OpenShift CLI

Install the OpenShift CLI `oc`. See the official documentation [here](https://docs.redhat.com/en/documentation/openshift_container_platform/4.18/html/cli_tools/openshift-cli-oc#cli-about-cli_cli-developer-commands) and the official downloads [here](https://console.redhat.com/openshift/downloads)


### Install the NVIDIA GPU Operator

Install NVIDIA GPU Operator **_v25.3.1_** by following the official documentation [here](https://docs.nvidia.com/datacenter/cloud-native/openshift/24.9.2/steps-overview.html). **Make sure** to also install the Node Feature Discovery Operator as it is a required dependency of the GPU Operator.

Once installed, begin creating the default cluster policy as described [here](https://docs.nvidia.com/datacenter/cloud-native/openshift/latest/install-gpu-ocp.html#create-the-clusterpolicy-instance). The only change that needs to be done to the default policy is to disable the devicePlugin

```
  devicePlugin:
    config:
      ...
    enabled: false
    mps:
      ...
```

Create the policy with that one change and wait for the state to be `ready` (this can take from 15-30 minutes)

![cluster policy ready example](./docs/cluster-policy-ready.png)

### MIG

If MIG is going to be used on the node, enable it with the following commands

Set the strategy to mixed

```
STRATEGY=mixed && \
  oc patch clusterpolicy/gpu-cluster-policy --type='json' -p='[{"op": "replace", "path": "/spec/mig/strategy", "value": '$STRATEGY'}]'
```

Set the desired MIG profiles. The available default MIG profiles can be seen [here](https://gitlab.com/nvidia/kubernetes/gpu-operator/-/blob/v1.8.0/assets/state-mig-manager/0400_configmap.yaml). To create custom profiles, follow these [instructions](https://docs.nvidia.com/datacenter/cloud-native/openshift/latest/mig-ocp.html#creating-and-applying-a-custom-mig-configuration). This example will use the `all-balanced` MIG setup.

```
NODE_NAME=<node name> && MIG_CONFIGURATION=all-balanced && oc label node/$NODE_NAME nvidia.com/mig.config=$MIG_CONFIGURATION --overwrite
```

Check the status of the profile change by running

```
oc -n nvidia-gpu-operator logs ds/nvidia-mig-manager --all-containers -f --prefix
```

If successful, the logs will look something like this

```
[pod/nvidia-mig-manager-nq2fs/nvidia-mig-manager] node/<node name> labeled
[pod/nvidia-mig-manager-nq2fs/nvidia-mig-manager] Changing the 'nvidia.com/mig.config.state' node label to 'success'
[pod/nvidia-mig-manager-nq2fs/nvidia-mig-manager] node/<node name> labeled
[pod/nvidia-mig-manager-nq2fs/nvidia-mig-manager] time="2025-06-18T18:38:35Z" level=info msg="Successfully updated to MIG config: all-balanced"
[pod/nvidia-mig-manager-nq2fs/nvidia-mig-manager] time="2025-06-18T18:38:35Z" level=info msg="Waiting for change to 'nvidia.com/mig.config' label"
```

Finally, use the NVIDIA GPU Operator to confirm the creation of the profiles. First, identify the driver daemonset by running

```
oc get pods -n nvidia-gpu-operator
```

Then run `nvidia-smi` through the daemonset with

```
oc exec -ti <nvidia-driver-daemonset-xxxxx...> -n nvidia-gpu-operator -- nvidia-smi
```

If successful, you should see something like this
```
Wed Jun 18 19:22:47 2025       
+-----------------------------------------------------------------------------------------+
| NVIDIA-SMI 570.148.08             Driver Version: 570.148.08     CUDA Version: 12.8     |
|-----------------------------------------+------------------------+----------------------+
| GPU  Name                 Persistence-M | Bus-Id          Disp.A | Volatile Uncorr. ECC |
| Fan  Temp   Perf          Pwr:Usage/Cap |           Memory-Usage | GPU-Util  Compute M. |
|                                         |                        |               MIG M. |
|=========================================+========================+======================|
|   0  NVIDIA A100 80GB PCIe          On  |   00000000:B6:00.0 Off |                   On |
| N/A   54C    P0             90W /  300W |     249MiB /  81920MiB |     N/A      Default |
|                                         |                        |              Enabled |
+-----------------------------------------+------------------------+----------------------+

+-----------------------------------------------------------------------------------------+
| MIG devices:                                                                            |
+------------------+----------------------------------+-----------+-----------------------+
| GPU  GI  CI  MIG |                     Memory-Usage |        Vol|        Shared         |
|      ID  ID  Dev |                       BAR1-Usage | SM     Unc| CE ENC  DEC  OFA  JPG |
|                  |                                  |        ECC|                       |
|==================+==================================+===========+=======================|
|  0    1   0   0  |             107MiB / 40192MiB    | 42      0 |  3   0    2    0    0 |
|                  |                 0MiB / 65535MiB  |           |                       |
+------------------+----------------------------------+-----------+-----------------------+
|  0    5   0   1  |              71MiB / 19968MiB    | 28      0 |  2   0    1    0    0 |
|                  |                 0MiB / 32767MiB  |           |                       |
+------------------+----------------------------------+-----------+-----------------------+
|  0   13   0   2  |              36MiB /  9728MiB    | 14      0 |  1   0    0    0    0 |
|                  |                 0MiB / 16383MiB  |           |                       |
+------------------+----------------------------------+-----------+-----------------------+
|  0   14   0   3  |              36MiB /  9728MiB    | 14      0 |  1   0    0    0    0 |
|                  |                 0MiB / 16383MiB  |           |                       |
+------------------+----------------------------------+-----------+-----------------------+
                                                                                         
+-----------------------------------------------------------------------------------------+
| Processes:                                                                              |
|  GPU   GI   CI              PID   Type   Process name                        GPU Memory |
|        ID   ID                                                               Usage      |
|=========================================================================================|
|  No running processes found                                                             |
+-----------------------------------------------------------------------------------------+
```

### Enabling DRA on OpenShift

**NOTE** enabling DRA in OpenShift permanently prevents the cluster from being upgraded with minor updates and cannot be undone. Only proceed if this does not matter for your cluster.

DRA is an experimental feature and is not available by default in OpenShift. To use it, enable the `TechPreviewNoUpgrade` feature set as explained in [Enabling features using FeatureGates](https://docs.redhat.com/en/documentation/openshift_container_platform/4.18/html/nodes/working-with-clusters#nodes-cluster-enabling), either with the CLI or Web Console. The feature set includes the `DynamicResourceAllocation` feature gate.

Additionally, set the scheduler to have `HighNodeUtilization` in the CLI

```console
$ oc patch --type merge -p '{"spec":{"profile": "HighNodeUtilization"}}' scheduler cluster
```


### Install the DRA Driver

This DRA Driver is built off of NVIDIA's DRA Driver for Kubernetes 1.31 and uses the the v1alpha3 DRA API


ADD LINKS



Clone the repo and cd into it

```
GIT GLONE
```

Install the DRA driver

```
./demo/clusters/openshift/install-dra-driver.sh
```

And make sure the pods startup correctly

```
$ oc get pods -n nvidia
NAME                                                          READY   STATUS    RESTARTS   AGE
nvidia-dra-driver-k8s-dra-driver-controller-6c8958947-ls6px   1/1     Running   0          10s
nvidia-dra-driver-k8s-dra-driver-kubelet-plugin-pskgj         1/1     Running   0          10s
```

#### Building a Custom Image

If any custom changes need to be made to DRA Driver image, modify the necessary files and rebuild the image
```
./demo/clusters/openshift/build-dra-driver.sh
```

This image will then need to be added to some sort of registry so it can be referenced by `./versions.mk`, `./deployments/helm/k8s-dra-driver/Chart.yaml`, and `./deployments/helm/k8s-dra-driver/values.yaml`

## Demo

<!-- Finally, you can run the various examples contained in the `demo/specs/quickstart` folder

You can run them as follows:
```console
kubectl apply --filename=demo/specs/quickstart/gpu-test{1,2,3}.yaml
```

Get the pods' statuses. Depending on which GPUs are available, running the first three examples will produce output similar to the following...

**Note:** there is a [known issue with kind](https://kind.sigs.k8s.io/docs/user/known-issues/#pod-errors-due-to-too-many-open-files). You may see an error while trying to tail the log of a running pod in the kind cluster: `failed to create fsnotify watcher: too many open files.` The issue may be resolved by increasing the value for `fs.inotify.max_user_watches`.
```console
kubectl get pod -A -l app=pod
```
```
NAMESPACE           NAME                                       READY   STATUS    RESTARTS   AGE
gpu-test1           pod1                                       1/1     Running   0          34s
gpu-test1           pod2                                       1/1     Running   0          34s
gpu-test2           pod                                        2/2     Running   0          34s
gpu-test3           pod1                                       1/1     Running   0          34s
gpu-test3           pod2                                       1/1     Running   0          34s
```
```console
kubectl logs -n gpu-test1 -l app=pod
```
```
GPU 0: A100-SXM4-40GB (UUID: GPU-662077db-fa3f-0d8f-9502-21ab0ef058a2)
GPU 0: A100-SXM4-40GB (UUID: GPU-4cf8db2d-06c0-7d70-1a51-e59b25b2c16c)
```
```console
kubectl logs -n gpu-test2 pod --all-containers
```
```
GPU 0: A100-SXM4-40GB (UUID: GPU-79a2ba02-a537-ccbf-2965-8e9d90c0bd54)
GPU 0: A100-SXM4-40GB (UUID: GPU-79a2ba02-a537-ccbf-2965-8e9d90c0bd54)
```

```console
kubectl logs -n gpu-test3 -l app=pod
```
```
GPU 0: A100-SXM4-40GB (UUID: GPU-4404041a-04cf-1ccf-9e70-f139a9b1e23c)
GPU 0: A100-SXM4-40GB (UUID: GPU-4404041a-04cf-1ccf-9e70-f139a9b1e23c)
```

### Cleaning up the environment

Remove the cluster created in the preceding steps:
```console
./demo/clusters/kind/delete-cluster.sh
``` -->
