# Trident Force Detach Test for iSCSI Backend

This repository contains sample YAML files for a PersistentVolumeClaim (PVC) and a deployment that can be used to test the force detach feature of NetApp Trident during non-graceful Kubernetes node failures.

### Overview

Starting with Kubernetes v1.28, non-graceful node shutdown (NGNS) is enabled by default. This feature allows storage orchestrators like Trident to forcefully detach volumes from nodes that are not responding. This is particularly useful in scenarios where a node becomes unresponsive due to a crash, hardware failure, or network partitioning.

The force detach feature ensures that storage volumes can be quickly and safely detached from failed nodes and attached to other nodes, minimizing downtime and potential data corruption.

* Force detach is available for all of Trident drivers including ontap-san, ontap-san-economy, onatp-nas, and onatp-nas-economy. (Trident 25.02.0 and above)

### Testing Environment
All samples have been tested with the following environment:

* Trident with Kubernetes Advanced v6.0 (Trident 24.02.0 & Kubernetes 1.29.4) <https://labondemand.netapp.com/node/878>

Please note that while these samples have been tested in a specific environment, they may need to be adjusted for use in other setups.

### Test Steps for Force Detach Feature in Trident iSCSI Backend

The following steps outline how to test the force detach feature of the Trident with iSCSI backend. This feature ensures that a Persistent Volume Claim (PVC) can be detached from a failed node and reattached to a healthy node, allowing the pod that uses the PVC to be rescheduled.

#### 1. Enable Force Detach on Trident (Optional - If Force Detach is disabled)
Update Force Detach on Trident Orchestrator Custom Resource (torc) - This will restart Trident pods.

```
# kubectl get torc -n trident -o yaml | grep enableForceDetach
    enableForceDetach: false
      enableForceDetach: "false"

# kubectl patch torc trident -n trident --type=merge -p '{"spec":{"enableForceDetach":true}}'

# kubectl get torc -n trident -o yaml | grep enableForceDetach
    enableForceDetach: true
      enableForceDetach: "true"

# kubectl get pod -n trident
NAME                                  READY   STATUS    RESTARTS        AGE
trident-controller-6b7cdddf44-jvcs6   6/6     Running   0               18s
trident-node-linux-c55dz              1/2     Running   0               17s
trident-node-linux-hctpr              2/2     Running   0               3m28s
trident-node-linux-jdx5z              2/2     Running   0               3m49s
```

#### 2. Create the PVC
Create a Persistent Volume Claim (PVC) that will be used by the pod. 

```
# pvc-iscsi.yaml
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: pvc-iscsi
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 2Gi
  storageClassName: storage-class-iscsi
```

Apply the PVC definition to the Kubernetes cluster:

```
# kubectl apply -f pvc-iscsi.yaml
persistentvolumeclaim/pvc-iscsi created
# kubectl get pvc -o wide
NAME        STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS          VOLUMEATTRIBUTESCLASS   AGE   VOLUMEMODE
pvc-iscsi   Bound    pvc-2a11e307-1582-4650-bde6-bb9c12e55661   2Gi        RWO            storage-class-iscsi   <unset>                 32s   Filesystem
```

#### 3. Create the deployment
Create a deployment that uses the PVC created in the previous step. 

```
# test-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-deployment
  labels:
    app: test
spec:
  replicas: 1
  selector:
    matchLabels:
      app: test
  template:
    metadata:
      labels:
        app: test
    spec:
      volumes:
        - name: iscsi-vol
          persistentVolumeClaim:
            claimName: pvc-iscsi
      containers:
      - name: alpine
        image: alpine:3.19.1
        command:
          - /bin/sh
          - "-c"
          - "sleep 7d"
        volumeMounts:
          - mountPath: "/data"
            name: iscsi-vol
      tolerations:
      - effect: NoExecute
        key: node.kubernetes.io/not-ready
        operator: Exists
        tolerationSeconds: 30
      - effect: NoExecute
        key: node.kubernetes.io/unreachable
        operator: Exists
        tolerationSeconds: 30
      nodeSelector:
        kubernetes.io/os: linux
```

Apply the deployment to the Kubernetes cluster:

```
# kubectl apply -f test-deployment.yaml
deployment.apps/test-deployment created
# ./verify_status.sh
kubectl get deployment.apps/test-deployment -o wide
NAME              READY   UP-TO-DATE   AVAILABLE   AGE   CONTAINERS   IMAGES          SELECTOR
test-deployment   1/1     1            1           15m   alpine       alpine:3.19.1   app=test
kubectl get replicaset.apps/test-deployment-57fb685899 -o wide
NAME                         DESIRED   CURRENT   READY   AGE   CONTAINERS   IMAGES          SELECTOR
test-deployment-57fb685899   1         1         1       15m   alpine       alpine:3.19.1   app=test,pod-template-hash=57fb685899
kubectl get pod/test-deployment-57fb685899-66wmp -o wide
NAME                               READY   STATUS    RESTARTS   AGE   IP             NODE    NOMINATED NODE   READINESS GATES
test-deployment-57fb685899-66wmp   1/1     Running   0          15m   192.168.26.9   rhel1   <none>           <none>
kubectl get persistentvolumeclaim/pvc-iscsi -o wide
NAME        STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS          VOLUMEATTRIBUTESCLASS   AGE   VOLUMEMODE
pvc-iscsi   Bound    pvc-2a11e307-1582-4650-bde6-bb9c12e55661   2Gi        RWO            storage-class-iscsi   <unset>                 98m   Filesystem
kubectl get volumeattachment.storage.k8s.io/csi-da2b3538ecb54d57ccab422841bedb9516d5707ebe7656adc3b483d9901ef0a2 -o wide
NAME                                                                   ATTACHER                PV                                         NODE    ATTACHED   AGE
csi-da2b3538ecb54d57ccab422841bedb9516d5707ebe7656adc3b483d9901ef0a2   csi.trident.netapp.io   pvc-2a11e307-1582-4650-bde6-bb9c12e55661   rhel1   true       15m
```

Identify the node running the pod from the deployment.

```
# kubectl get pod -o wide
NAME                               READY   STATUS    RESTARTS   AGE   IP             NODE    NOMINATED NODE   READINESS GATES
test-deployment-57fb685899-66wmp   1/1     Running   0          16m   192.168.26.9   rhel1   <none>           <none>

# kubectl get node -o wide
NAME    STATUS   ROLES           AGE    VERSION   INTERNAL-IP    EXTERNAL-IP   OS-IMAGE                              KERNEL-VERSION                 CONTAINER-RUNTIME
rhel1   Ready    <none>          332d   v1.29.4   192.168.0.61   <none>        Red Hat Enterprise Linux 9.3 (Plow)   5.14.0-362.24.1.el9_3.x86_64   cri-o://1.30.0
rhel2   Ready    <none>          332d   v1.29.4   192.168.0.62   <none>        Red Hat Enterprise Linux 9.3 (Plow)   5.14.0-362.24.1.el9_3.x86_64   cri-o://1.30.0
rhel3   Ready    control-plane   332d   v1.29.4   192.168.0.63   <none>        Red Hat Enterprise Linux 9.3 (Plow)   5.14.0-362.24.1.el9_3.x86_64   cri-o://1.30.0
```

Verify iSCSI PVC attachment to the node.

```
[root@rhel1 ~]# multipath -ll
3600a0980774f6a34712b572d41767174 dm-3 NETAPP,LUN C-Mode
size=2.0G features='3 queue_if_no_path pg_init_retries 50' hwhandler='1 alua' wp=rw
`-+- policy='service-time 0' prio=50 status=active
  |- 34:0:0:0 sdb 8:16 active ready running
  `- 33:0:0:0 sdc 8:32 active ready running
[root@rhel1 ~]# lsscsi
[0:0:0:0]    disk    VMware   Virtual disk     2.0   /dev/sda
[3:0:0:0]    cd/dvd  NECVMWar VMware SATA CD00 1.00  /dev/sr0
[33:0:0:0]   disk    NETAPP   LUN C-Mode       9141  /dev/sdc
[34:0:0:0]   disk    NETAPP   LUN C-Mode       9141  /dev/sdb
[root@rhel1 ~]# iscsiadm -m session
tcp: [1] 192.168.0.135:3260,1030 iqn.1992-08.com.netapp:sn.7c8b4c9af76e11ee8aac005056b0f629:vs.4 (non-flash)
tcp: [2] 192.168.0.136:3260,1031 iqn.1992-08.com.netapp:sn.7c8b4c9af76e11ee8aac005056b0f629:vs.4 (non-flash)
```

#### 4. Shutdown Node Running the Pod

```
[root@rhel1 ~]# shutdown -h now
```

Chech the status of the pod.

```
# kubectl get node
NAME    STATUS     ROLES           AGE    VERSION
rhel1   NotReady   <none>          332d   v1.29.4
rhel2   Ready      <none>          332d   v1.29.4
rhel3   Ready      control-plane   332d   v1.29.4

# ./verify_status.sh
kubectl get deployment.apps/test-deployment -o wide
NAME              READY   UP-TO-DATE   AVAILABLE   AGE   CONTAINERS   IMAGES          SELECTOR
test-deployment   0/1     1            0           22m   alpine       alpine:3.19.1   app=test
kubectl get replicaset.apps/test-deployment-57fb685899 -o wide
NAME                         DESIRED   CURRENT   READY   AGE   CONTAINERS   IMAGES          SELECTOR
test-deployment-57fb685899   1         1         0       22m   alpine       alpine:3.19.1   app=test,pod-template-hash=57fb685899
kubectl get pod/test-deployment-57fb685899-66wmp
pod/test-deployment-57fb685899-6wg56 -o wide
NAME                               READY   STATUS              RESTARTS   AGE   IP             NODE    NOMINATED NODE   READINESS GATES
test-deployment-57fb685899-66wmp   1/1     Terminating         0          22m   192.168.26.9   rhel1   <none>           <none>
test-deployment-57fb685899-6wg56   0/1     ContainerCreating   0          54s   <none>         rhel3   <none>           <none>
kubectl get persistentvolumeclaim/pvc-iscsi -o wide
NAME        STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS          VOLUMEATTRIBUTESCLASS   AGE    VOLUMEMODE
pvc-iscsi   Bound    pvc-2a11e307-1582-4650-bde6-bb9c12e55661   2Gi        RWO            storage-class-iscsi   <unset>                 105m   Filesystem
kubectl get volumeattachment.storage.k8s.io/csi-da2b3538ecb54d57ccab422841bedb9516d5707ebe7656adc3b483d9901ef0a2 -o wide
NAME                                                                   ATTACHER                PV                                         NODE    ATTACHED   AGE
csi-da2b3538ecb54d57ccab422841bedb9516d5707ebe7656adc3b483d9901ef0a2   csi.trident.netapp.io   pvc-2a11e307-1582-4650-bde6-bb9c12e55661   rhel1   true       22m

# kubectl describe $(kubectl get pod -o name)
Name:                      test-deployment-57fb685899-66wmp
Namespace:                 default
Priority:                  0
Service Account:           default
Node:                      rhel1/192.168.0.61
Start Time:                Wed, 26 Mar 2025 02:27:10 +0000
Labels:                    app=test
                           pod-template-hash=57fb685899
Annotations:               cni.projectcalico.org/containerID: 1a109ecbe9d743329c23ab2b50ac14b15cfa913b58e60996cc4595d8293201d6
                           cni.projectcalico.org/podIP: 192.168.26.9/32
                           cni.projectcalico.org/podIPs: 192.168.26.9/32
Status:                    Terminating (lasts 105s)
Termination Grace Period:  30s
IP:                        192.168.26.9
IPs:
  IP:           192.168.26.9
Controlled By:  ReplicaSet/test-deployment-57fb685899
Containers:
  alpine:
    Container ID:  cri-o://1c42bb45f739f0a0918c0c7f73ac06cfb640cd1943295026f3c9b28ee2f902cf
    Image:         alpine:3.19.1
    Image ID:      docker.io/library/alpine@sha256:6457d53fb065d6f250e1504b9bc42d5b6c65941d57532c072d929dd0628977d0
    Port:          <none>
    Host Port:     <none>
    Command:
      /bin/sh
      -c
      sleep 7d
    State:          Running
      Started:      Wed, 26 Mar 2025 02:27:18 +0000
    Ready:          True
    Restart Count:  0
    Environment:    <none>
    Mounts:
      /data from iscsi-vol (rw)
      /var/run/secrets/kubernetes.io/serviceaccount from kube-api-access-p4c6s (ro)
Conditions:
  Type                        Status
  PodReadyToStartContainers   True
  Initialized                 True
  Ready                       False
  ContainersReady             True
  PodScheduled                True
  DisruptionTarget            True
Volumes:
  iscsi-vol:
    Type:       PersistentVolumeClaim (a reference to a PersistentVolumeClaim in the same namespace)
    ClaimName:  pvc-iscsi
    ReadOnly:   false
  kube-api-access-p4c6s:
    Type:                    Projected (a volume that contains injected data from multiple sources)
    TokenExpirationSeconds:  3607
    ConfigMapName:           kube-root-ca.crt
    ConfigMapOptional:       <nil>
    DownwardAPI:             true
QoS Class:                   BestEffort
Node-Selectors:              kubernetes.io/os=linux
Tolerations:                 node.kubernetes.io/not-ready:NoExecute op=Exists for 30s
                             node.kubernetes.io/unreachable:NoExecute op=Exists for 30s
Events:
  Type     Reason                  Age    From                     Message
  ----     ------                  ----   ----                     -------
  Normal   Scheduled               23m    default-scheduler        Successfully assigned default/test-deployment-57fb685899-66wmp to rhel1
  Normal   SuccessfulAttachVolume  23m    attachdetach-controller  AttachVolume.Attach succeeded for volume "pvc-2a11e307-1582-4650-bde6-bb9c12e55661"
  Normal   Pulled                  23m    kubelet                  Container image "alpine:3.19.1" already present on machine
  Normal   Created                 23m    kubelet                  Created container alpine
  Normal   Started                 23m    kubelet                  Started container alpine
  Warning  NodeNotReady            2m51s  node-controller          Node is not ready


Name:             test-deployment-57fb685899-6wg56
Namespace:        default
Priority:         0
Service Account:  default
Node:             rhel3/192.168.0.63
Start Time:       Wed, 26 Mar 2025 02:48:22 +0000
Labels:           app=test
                  pod-template-hash=57fb685899
Annotations:      <none>
Status:           Pending
IP:
IPs:              <none>
Controlled By:    ReplicaSet/test-deployment-57fb685899
Containers:
  alpine:
    Container ID:
    Image:         alpine:3.19.1
    Image ID:
    Port:          <none>
    Host Port:     <none>
    Command:
      /bin/sh
      -c
      sleep 7d
    State:          Waiting
      Reason:       ContainerCreating
    Ready:          False
    Restart Count:  0
    Environment:    <none>
    Mounts:
      /data from iscsi-vol (rw)
      /var/run/secrets/kubernetes.io/serviceaccount from kube-api-access-nhlgb (ro)
Conditions:
  Type                        Status
  PodReadyToStartContainers   False
  Initialized                 True
  Ready                       False
  ContainersReady             False
  PodScheduled                True
Volumes:
  iscsi-vol:
    Type:       PersistentVolumeClaim (a reference to a PersistentVolumeClaim in the same namespace)
    ClaimName:  pvc-iscsi
    ReadOnly:   false
  kube-api-access-nhlgb:
    Type:                    Projected (a volume that contains injected data from multiple sources)
    TokenExpirationSeconds:  3607
    ConfigMapName:           kube-root-ca.crt
    ConfigMapOptional:       <nil>
    DownwardAPI:             true
QoS Class:                   BestEffort
Node-Selectors:              kubernetes.io/os=linux
Tolerations:                 node.kubernetes.io/not-ready:NoExecute op=Exists for 30s
                             node.kubernetes.io/unreachable:NoExecute op=Exists for 30s
Events:
  Type     Reason              Age    From                     Message
  ----     ------              ----   ----                     -------
  Normal   Scheduled           2m15s  default-scheduler        Successfully assigned default/test-deployment-57fb685899-6wg56 to rhel3
  Warning  FailedAttachVolume  2m15s  attachdetach-controller  Multi-Attach error for volume "pvc-2a11e307-1582-4650-bde6-bb9c12e55661" Volume is already used by pod(s) test-deployment-57fb685899-66wmp
```

#### 5. Apply Taint to the Failed Node

```
# kubectl taint nodes rhel1 node.kubernetes.io/out-of-service=nodeshutdown:NoExecute
node/rhel1 tainted

# kubectl get nodes -o json | jq '.items[] | {name: .metadata.name, taints: .spec.taints}'
{
  "name": "rhel1",
  "taints": [
    {
      "effect": "NoExecute",
      "key": "node.kubernetes.io/out-of-service",
      "value": "nodeshutdown"
    },
    {
      "effect": "NoSchedule",
      "key": "node.kubernetes.io/unreachable",
      "timeAdded": "2025-03-26T02:47:46Z"
    },
    {
      "effect": "NoExecute",
      "key": "node.kubernetes.io/unreachable",
      "timeAdded": "2025-03-26T02:47:52Z"
    }
  ]
}
{
  "name": "rhel2",
  "taints": null
}
{
  "name": "rhel3",
  "taints": null
}

# tridentctl get node rhel1 -n trident -o yaml
items:
- deleted: false
  hostInfo:
    os:
      distro: rhel
      release: "9.3"
      version: "9.3"
    services:
    - NFS
    - iSCSI
    - nvme
  ips:
  - 192.168.0.61
  - 192.168.26.0
  iqn: iqn.1994-05.com.redhat:rhel1.demo.netapp.com
  logLayers: ""
  logLevel: ""
  logWorkflows: ""
  name: rhel1
  nodePrep:
    enabled: false
  nqn: nqn.2014-08.org.nvmexpress:uuid:541e3042-2619-c021-eb5f-e0e73e5d2210
  publicationState: dirty
```

#### 6. Verify iSCSI PVC Detachment and Pod Rescheduling

Verify that the pod has been rescheduled onto another node and that it has successfully mounted the iSCSI PVC.

```
# ./verify_status.sh                                                                 kubectl get deployment.apps/test-deployment -o wide
NAME              READY   UP-TO-DATE   AVAILABLE   AGE   CONTAINERS   IMAGES          SELECTOR
test-deployment   1/1     1            1           26m   alpine       alpine:3.19.1   app=test
kubectl get replicaset.apps/test-deployment-57fb685899 -o wide
NAME                         DESIRED   CURRENT   READY   AGE   CONTAINERS   IMAGES          SELECTOR
test-deployment-57fb685899   1         1         1       26m   alpine       alpine:3.19.1   app=test,pod-template-hash=57fb685899
kubectl get pod/test-deployment-57fb685899-6wg56 -o wide
NAME                               READY   STATUS    RESTARTS   AGE     IP               NODE    NOMINATED NODE   READINESS GATES
test-deployment-57fb685899-6wg56   1/1     Running   0          5m39s   192.168.25.105   rhel3   <none>           <none>
kubectl get persistentvolumeclaim/pvc-iscsi -o wide
NAME        STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS          VOLUMEATTRIBUTESCLASS   AGE    VOLUMEMODE
pvc-iscsi   Bound    pvc-2a11e307-1582-4650-bde6-bb9c12e55661   2Gi        RWO            storage-class-iscsi   <unset>                 110m   Filesystem
kubectl get volumeattachment.storage.k8s.io/csi-67f0ffca2611b7a2ff5c5ac2d8247cafd31b113ae4689799d5bcd210f3ea791b -o wide
NAME                                                                   ATTACHER                PV                                         NODE    ATTACHED   AGE
csi-67f0ffca2611b7a2ff5c5ac2d8247cafd31b113ae4689799d5bcd210f3ea791b   csi.trident.netapp.io   pvc-2a11e307-1582-4650-bde6-bb9c12e55661   rhel3   true       30s

# kubectl describe $(kubectl get pod -o name)
Name:             test-deployment-57fb685899-6wg56
Namespace:        default
Priority:         0
Service Account:  default
Node:             rhel3/192.168.0.63
Start Time:       Wed, 26 Mar 2025 02:48:22 +0000
Labels:           app=test
                  pod-template-hash=57fb685899
Annotations:      cni.projectcalico.org/containerID: 34807da8f943264dac95d434bd7a74aed40f4cea9b2576f2bc0b69855feb58a8
                  cni.projectcalico.org/podIP: 192.168.25.105/32
                  cni.projectcalico.org/podIPs: 192.168.25.105/32
Status:           Running
IP:               192.168.25.105
IPs:
  IP:           192.168.25.105
Controlled By:  ReplicaSet/test-deployment-57fb685899
Containers:
  alpine:
    Container ID:  cri-o://ac56f468141e1735559e6f57809b719aecdbcbe3c8634b0e3149886ae9abd59e
    Image:         alpine:3.19.1
    Image ID:      docker.io/library/alpine@sha256:6457d53fb065d6f250e1504b9bc42d5b6c65941d57532c072d929dd0628977d0
    Port:          <none>
    Host Port:     <none>
    Command:
      /bin/sh
      -c
      sleep 7d
    State:          Running
      Started:      Wed, 26 Mar 2025 02:53:34 +0000
    Ready:          True
    Restart Count:  0
    Environment:    <none>
    Mounts:
      /data from iscsi-vol (rw)
      /var/run/secrets/kubernetes.io/serviceaccount from kube-api-access-nhlgb (ro)
Conditions:
  Type                        Status
  PodReadyToStartContainers   True
  Initialized                 True
  Ready                       True
  ContainersReady             True
  PodScheduled                True
Volumes:
  iscsi-vol:
    Type:       PersistentVolumeClaim (a reference to a PersistentVolumeClaim in the same namespace)
    ClaimName:  pvc-iscsi
    ReadOnly:   false
  kube-api-access-nhlgb:
    Type:                    Projected (a volume that contains injected data from multiple sources)
    TokenExpirationSeconds:  3607
    ConfigMapName:           kube-root-ca.crt
    ConfigMapOptional:       <nil>
    DownwardAPI:             true
QoS Class:                   BestEffort
Node-Selectors:              kubernetes.io/os=linux
Tolerations:                 node.kubernetes.io/not-ready:NoExecute op=Exists for 30s
                             node.kubernetes.io/unreachable:NoExecute op=Exists for 30s
Events:
  Type     Reason                  Age    From                     Message
  ----     ------                  ----   ----                     -------
  Normal   Scheduled               6m58s  default-scheduler        Successfully assigned default/test-deployment-57fb685899-6wg56 to rhel3
  Warning  FailedAttachVolume      6m58s  attachdetach-controller  Multi-Attach error for volume "pvc-2a11e307-1582-4650-bde6-bb9c12e55661" Volume is already used by pod(s) test-deployment-57fb685899-66wmp
  Normal   SuccessfulAttachVolume  108s   attachdetach-controller  AttachVolume.Attach succeeded for volume "pvc-2a11e307-1582-4650-bde6-bb9c12e55661"
  Normal   Pulled                  106s   kubelet                  Container image "alpine:3.19.1" already present on machine
  Normal   Created                 106s   kubelet                  Created container alpine
  Normal   Started                 106s   kubelet                  Started container alpine
```

Verify iSCSI PVC attachment to the healthy node

```
[root@rhel3 ~]# multipath -ll
3600a0980774f6a34712b572d41767174 dm-3 NETAPP,LUN C-Mode
size=2.0G features='3 queue_if_no_path pg_init_retries 50' hwhandler='1 alua' wp=rw
`-+- policy='service-time 0' prio=50 status=active
  |- 34:0:0:0 sdb 8:16 active ready running
  `- 33:0:0:0 sdc 8:32 active ready running
[root@rhel3 ~]# iscsiadm -m session
tcp: [1] 192.168.0.135:3260,1030 iqn.1992-08.com.netapp:sn.7c8b4c9af76e11ee8aac005056b0f629:vs.4 (non-flash)
tcp: [2] 192.168.0.136:3260,1031 iqn.1992-08.com.netapp:sn.7c8b4c9af76e11ee8aac005056b0f629:vs.4 (non-flash)
```

#### 8. Verify Trident Node State after Recovery (Optional)

Power up the failed node and verify the node is in Ready state

```
# kubectl get node
NAME    STATUS   ROLES           AGE    VERSION
rhel1   Ready    <none>          332d   v1.29.4
rhel2   Ready    <none>          332d   v1.29.4
rhel3   Ready    control-plane   332d   v1.29.4
```

Remove the taint and verify the Trident node is in cleanable state

```
# kubectl taint nodes rhel1 node.kubernetes.io/out-of-service=nodeshutdown:NoExecute-
node/rhel1 untainted

# kubectl get nodes -o json | jq '.items[] | {name: .metadata.name, taints: .spec.taints}'
{
  "name": "rhel1",
  "taints": null
}
{
  "name": "rhel2",
  "taints": null
}
{
  "name": "rhel3",
  "taints": null
}

# tridentctl get node rhel1 -n trident -o yaml
items:
- deleted: false
  hostInfo:
    os:
      distro: rhel
      release: "9.3"
      version: "9.3"
    services:
    - iSCSI
    - nvme
  ips:
  - 192.168.0.61
  - 192.168.26.0
  iqn: iqn.1994-05.com.redhat:rhel1.demo.netapp.com
  logLayers: ""
  logLevel: info
  logWorkflows: ""
  name: rhel1
  nqn: nqn.2014-08.org.nvmexpress:uuid:541e3042-2619-c021-eb5f-e0e73e5d2210
  publicationState: cleanable
  topologyLabels:
    topology.kubernetes.io/region: west
    topology.kubernetes.io/zone: west1
```





