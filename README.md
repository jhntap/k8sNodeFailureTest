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

#### 1. Create the PVC
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
# kubectl get pvc
NAME        STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS          VOLUM
pvc-iscsi   Bound    pvc-134a4a2c-8bb7-40bf-b382-9392a0769d49   2Gi        RWO            storage-class-iscsi   <unse
```

#### 2. Create the deployment
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
NAME              READY   UP-TO-DATE   AVAILABLE   AGE     CONTAINERS   IMAGES          SELECTOR
test-deployment   1/1     1            1           2m49s   alpine       alpine:3.19.1   app=test
NAME                         DESIRED   CURRENT   READY   AGE     CONTAINERS   IMAGES          SELECTOR
test-deployment-57fb685899   1         1         1       2m49s   alpine       alpine:3.19.1   app=test,pod-template-hash=57fb685899
NAME                               READY   STATUS    RESTARTS   AGE     IP               NODE    NOMINATED NODE   READINESS GATES
test-deployment-57fb685899-d5r6n   1/1     Running   0          2m49s   192.168.28.116   rhel2   <none>           <none>
```

Identify the node running the pod from the deployment.

```
# kubectl get pod -o wide
NAME                               READY   STATUS    RESTARTS   AGE     IP               NODE    NOMINATED NODE   READINESS GATES
test-deployment-57fb685899-d5r6n   1/1     Running   0          3m10s   192.168.28.116   rhel2   <none>           <none>
```

Verify iSCSI PVC attachment to the node.

```
[root@rhel2 ~]# multipath -ll
3600a0980774f6a34712b572d41767173 dm-3 NETAPP,LUN C-Mode
size=2.0G features='3 queue_if_no_path pg_init_retries 50' hwhandler='1 alua' wp=rw
`-+- policy='service-time 0' prio=50 status=active
  |- 34:0:0:0 sdc 8:32 active ready running
  `- 33:0:0:0 sdb 8:16 active ready running

[root@rhel2 ~]# iscsiadm -m session
tcp: [1] 192.168.0.135:3260,1030 iqn.1992-08.com.netapp:sn.7c8b4c9af76e11ee8aac005056b0f629:vs.4 (non-flash)
tcp: [2] 192.168.0.136:3260,1031 iqn.1992-08.com.netapp:sn.7c8b4c9af76e11ee8aac005056b0f629:vs.4 (non-flash)
```

#### 3. Shutdown Node Running the Pod

```
[root@rhel2 ~]# shutdown -h now
```

Chech the status of the pod.

```
# k get node
NAME    STATUS     ROLES           AGE    VERSION
rhel1   Ready      <none>          327d   v1.29.4
rhel2   NotReady   <none>          327d   v1.29.4
rhel3   Ready      control-plane   327d   v1.29.4
win1    Ready      <none>          327d   v1.29.4
win2    Ready      <none>          327d   v1.29.4

# ./verify_status.sh
NAME              READY   UP-TO-DATE   AVAILABLE   AGE     CONTAINERS   IMAGES          SELECTOR
test-deployment   0/1     1            0           4m52s   alpine       alpine:3.19.1   app=test
NAME                         DESIRED   CURRENT   READY   AGE     CONTAINERS   IMAGES          SELECTOR
test-deployment-57fb685899   1         1         0       4m52s   alpine       alpine:3.19.1   app=test,pod-template-hash=57fb685899
NAME                               READY   STATUS    RESTARTS   AGE     IP               NODE    NOMINATED NODE   READINESS GATES
test-deployment-57fb685899-d5r6n   1/1     Running   0          4m53s   192.168.28.116   rhel2   <none>           <none>

[root@rhel3 k8sNodeFailuretest]# ./verify_status.sh
NAME              READY   UP-TO-DATE   AVAILABLE   AGE     CONTAINERS   IMAGES          SELECTOR
test-deployment   0/1     1            0           5m43s   alpine       alpine:3.19.1   app=test
NAME                         DESIRED   CURRENT   READY   AGE     CONTAINERS   IMAGES          SELECTOR
test-deployment-57fb685899   1         1         0       5m43s   alpine       alpine:3.19.1   app=test,pod-template-hash=57fb685899
NAME                               READY   STATUS              RESTARTS   AGE     IP               NODE    NOMINATED NODE   READINESS GATES
test-deployment-57fb685899-d5r6n   1/1     Terminating         0          5m43s   192.168.28.116   rhel2   <none>           <none>
test-deployment-57fb685899-n4wmj   0/1     ContainerCreating   0          16s     <none>           rhel1   <none>           <none>

# kubectl describe pod test-deployment-57fb685899-d5r6n
Name:                      test-deployment-57fb685899-d5r6n
Namespace:                 default
Priority:                  0
Service Account:           default
Node:                      rhel2/192.168.0.62
Start Time:                Fri, 21 Mar 2025 01:34:43 +0000
Labels:                    app=test
                           pod-template-hash=57fb685899
Annotations:               cni.projectcalico.org/containerID: 281a8f0dea2aef51dbfe62f837f341fc1471b718f0b4fbd48c34977911969813
                           cni.projectcalico.org/podIP: 192.168.28.116/32
                           cni.projectcalico.org/podIPs: 192.168.28.116/32
Status:                    Terminating (lasts 24s)
Termination Grace Period:  30s
IP:                        192.168.28.116
IPs:
  IP:           192.168.28.116
Controlled By:  ReplicaSet/test-deployment-57fb685899
Containers:
  alpine:
    Container ID:  cri-o://0c787b18aa28eb0a34df8140c7d93416e32ecd20961d973ff5f94e91174ceeb7
    Image:         alpine:3.19.1
    Image ID:      docker.io/library/alpine@sha256:6457d53fb065d6f250e1504b9bc42d5b6c65941d57532c072d929dd0628977d0
    Port:          <none>
    Host Port:     <none>
    Command:
      /bin/sh
      -c
      sleep 7d
    State:          Running
      Started:      Fri, 21 Mar 2025 01:34:52 +0000
    Ready:          True
    Restart Count:  0
    Environment:    <none>
    Mounts:
      /data from iscsi-vol (rw)
      /var/run/secrets/kubernetes.io/serviceaccount from kube-api-access-44tgt (ro)
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
  kube-api-access-44tgt:
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
  Normal   Scheduled               6m21s  default-scheduler        Successfully assigned default/test-deployment-57fb685899-d5r6n to rhel2
  Normal   SuccessfulAttachVolume  6m20s  attachdetach-controller  AttachVolume.Attach succeeded for volume "pvc-134a4a2c-8bb7-40bf-b382-9392a0769d49"
  Normal   Pulled                  6m14s  kubelet                  Container image "alpine:3.19.1" already present on machine
  Normal   Created                 6m13s  kubelet                  Created container alpine
  Normal   Started                 6m13s  kubelet                  Started container alpine
  Warning  NodeNotReady            89s    node-controller          Node is not ready

# kubectl describe pod test-deployment-57fb685899-n4wmj
Name:             test-deployment-57fb685899-n4wmj
Namespace:        default
Priority:         0
Service Account:  default
Node:             rhel1/192.168.0.61
Start Time:       Fri, 21 Mar 2025 01:40:11 +0000
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
      /var/run/secrets/kubernetes.io/serviceaccount from kube-api-access-z45bg (ro)
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
  kube-api-access-z45bg:
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
  Type     Reason              Age   From                     Message
  ----     ------              ----  ----                     -------
  Normal   Scheduled           89s   default-scheduler        Successfully assigned default/test-deployment-57fb685899-n4wmj to rhel1
  Warning  FailedAttachVolume  89s   attachdetach-controller  Multi-Attach error for volume "pvc-134a4a2c-8bb7-40bf-b382-9392a0769d49" Volume is already used by pod(s) test-deployment-57fb685899-d5r6n
```

#### 4. Apply Taint to the failed Node

```
# kubectl taint nodes rhel2 node.kubernetes.io/out-of-service=nodeshutdown:NoExecute
node/rhel2 tainted
```

#### 5. Verify iSCSI PVC Detachment and Pod Rescheduling

Verify that the pod has been rescheduled onto another node and that it has successfully mounted the iSCSI PVC.

```
]# ./verify_status.sh
NAME              READY   UP-TO-DATE   AVAILABLE   AGE     CONTAINERS   IMAGES          SELECTOR
test-deployment   1/1     1            1           7m35s   alpine       alpine:3.19.1   app=test
NAME                         DESIRED   CURRENT   READY   AGE     CONTAINERS   IMAGES          SELECTOR
test-deployment-57fb685899   1         1         1       7m35s   alpine       alpine:3.19.1   app=test,pod-template-hash=57fb685899
NAME                               READY   STATUS    RESTARTS   AGE    IP             NODE    NOMINATED NODE   READINESS GATES
test-deployment-57fb685899-n4wmj   1/1     Running   0          2m8s   192.168.26.2   rhel1   <none>           <none>

# kubectl describe pod test-deployment-57fb685899-n4wmj
Name:             test-deployment-57fb685899-n4wmj
Namespace:        default
Priority:         0
Service Account:  default
Node:             rhel1/192.168.0.61
Start Time:       Fri, 21 Mar 2025 01:40:11 +0000
Labels:           app=test
                  pod-template-hash=57fb685899
Annotations:      cni.projectcalico.org/containerID: 51809c5da41fc4f36be6aeccdce8b70e9cfa3abc0de8ce1c6dbf15000dc21aa1
                  cni.projectcalico.org/podIP: 192.168.26.2/32
                  cni.projectcalico.org/podIPs: 192.168.26.2/32
Status:           Running
IP:               192.168.26.2
IPs:
  IP:           192.168.26.2
Controlled By:  ReplicaSet/test-deployment-57fb685899
Containers:
  alpine:
    Container ID:  cri-o://e41fb92a03cb12ef23430621dd5d91ee098483a90a8ac933a261c31621f423c4
    Image:         alpine:3.19.1
    Image ID:      docker.io/library/alpine@sha256:6457d53fb065d6f250e1504b9bc42d5b6c65941d57532c072d929dd0628977d0
    Port:          <none>
    Host Port:     <none>
    Command:
      /bin/sh
      -c
      sleep 7d
    State:          Running
      Started:      Fri, 21 Mar 2025 01:42:13 +0000
    Ready:          True
    Restart Count:  0
    Environment:    <none>
    Mounts:
      /data from iscsi-vol (rw)
      /var/run/secrets/kubernetes.io/serviceaccount from kube-api-access-z45bg (ro)
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
  kube-api-access-z45bg:
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
  Normal   Scheduled               2m36s  default-scheduler        Successfully assigned default/test-deployment-57fb685899-n4wmj to rhel1
  Warning  FailedAttachVolume      2m36s  attachdetach-controller  Multi-Attach error for volume "pvc-134a4a2c-8bb7-40bf-b382-9392a0769d49" Volume is already used by pod(s) test-deployment-57fb685899-d5r6n
  Normal   SuccessfulAttachVolume  36s    attachdetach-controller  AttachVolume.Attach succeeded for volume "pvc-134a4a2c-8bb7-40bf-b382-9392a0769d49"
  Normal   Pulled                  34s    kubelet                  Container image "alpine:3.19.1" already present on machine
  Normal   Created                 34s    kubelet                  Created container alpine
  Normal   Started                 34s    kubelet                  Started container alpine
```

Verify iSCSI PVC attachment to the healthy node

```
[root@rhel1 ~]# multipath -ll
3600a0980774f6a34712b572d41767173 dm-3 NETAPP,LUN C-Mode
size=2.0G features='3 queue_if_no_path pg_init_retries 50' hwhandler='1 alua' wp=rw
`-+- policy='service-time 0' prio=50 status=active
  |- 33:0:0:0 sdb 8:16 active ready running
  `- 34:0:0:0 sdc 8:32 active ready running
[root@rhel1 ~]# iscsiadm -m session
tcp: [1] 192.168.0.135:3260,1030 iqn.1992-08.com.netapp:sn.7c8b4c9af76e11ee8aac005056b0f629:vs.4 (non-flash)
tcp: [2] 192.168.0.136:3260,1031 iqn.1992-08.com.netapp:sn.7c8b4c9af76e11ee8aac005056b0f629:vs.4 (non-flash)
```







