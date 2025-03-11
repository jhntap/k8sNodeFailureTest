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
# kubectl get pvc -o wide
NAME        STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS          VOLUMEATTRIBUTESCLASS   AGE   VOLUMEMODE
pvc-iscsi   Bound    pvc-5576a0d5-797e-4268-beed-ba3755439129   2Gi        RWO            storage-class-iscsi   <unset>                 23s   Filesystem
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
      nodeSelector:
        kubernetes.io/os: linux
```

Apply the deployment to the Kubernetes cluster:

```
# kubectl apply -f test-deployment.yaml
deployment.apps/test-deployment created
# kubectl get deployment -o wide
NAME              READY   UP-TO-DATE   AVAILABLE   AGE    CONTAINERS   IMAGES          SELECTOR
test-deployment   1/1     1            1           103m   alpine       alpine:3.19.1   app=test
# kubectl get rs -o wide
NAME                        DESIRED   CURRENT   READY   AGE    CONTAINERS   IMAGES          SELECTOR
test-deployment-f64c69647   1         1         1       103m   alpine       alpine:3.19.1   app=test,pod-template-hash=f64c69647
```

Identify the node running the pod from the deployment.

```
# kubectl get pod -o wide
NAME                              READY   STATUS    RESTARTS   AGE    IP               NODE    NOMINATED NODE   READINESS GATES
test-deployment-f64c69647-888g8   1/1     Running   0          104m   192.168.28.106   rhel2   <none>           <none>
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
# ./verify_status.sh
NAME              READY   UP-TO-DATE   AVAILABLE   AGE    CONTAINERS   IMAGES          SELECTOR
test-deployment   1/1     1            1           150m   alpine       alpine:3.19.1   app=test
NAME                        DESIRED   CURRENT   READY   AGE    CONTAINERS   IMAGES          SELECTOR
test-deployment-f64c69647   1         1         1       150m   alpine       alpine:3.19.1   app=test,pod-template-hash=f64c69647
NAME                              READY   STATUS    RESTARTS   AGE    IP               NODE    NOMINATED NODE   READINESS GATES
test-deployment-f64c69647-888g8   1/1     Running   0          150m   192.168.28.106   rhel2   <none>           <none>

# kubectl describe   pod   test-deployment-f64c69647-888g8
Name:             test-deployment-f64c69647-888g8
Namespace:        default
Priority:         0
Service Account:  default
Node:             rhel2/192.168.0.62
Start Time:       Tue, 11 Mar 2025 02:36:19 +0000
Labels:           app=test
                  pod-template-hash=f64c69647
Annotations:      cni.projectcalico.org/containerID: 02aaf923645fb1fe1ec383088a3c2c602173c27238eed3e32a7e5679c754c911
                  cni.projectcalico.org/podIP: 192.168.28.106/32
                  cni.projectcalico.org/podIPs: 192.168.28.106/32
Status:           Running
IP:               192.168.28.106
IPs:
  IP:           192.168.28.106
Controlled By:  ReplicaSet/test-deployment-f64c69647
Containers:
  alpine:
    Container ID:  cri-o://40dce8c345fdf56ba81fc0ef3b896e64a9228e99fd5962cfb716b06adccf2009
    Image:         alpine:3.19.1
    Image ID:      docker.io/library/alpine@sha256:6457d53fb065d6f250e1504b9bc42d5b6c65941d57532c072d929dd0628977d0
    Port:          <none>
    Host Port:     <none>
    Command:
      /bin/sh
      -c
      sleep 7d
    State:          Running
      Started:      Tue, 11 Mar 2025 02:36:26 +0000
    Ready:          True
    Restart Count:  0
    Environment:    <none>
    Mounts:
      /data from iscsi-vol (rw)
      /var/run/secrets/kubernetes.io/serviceaccount from kube-api-access-t7k2j (ro)
Conditions:
  Type                        Status
  PodReadyToStartContainers   True
  Initialized                 True
  Ready                       False
  ContainersReady             True
  PodScheduled                True
Volumes:
  iscsi-vol:
    Type:       PersistentVolumeClaim (a reference to a PersistentVolumeClaim in the same namespace)
    ClaimName:  pvc-iscsi
    ReadOnly:   false
  kube-api-access-t7k2j:
    Type:                    Projected (a volume that contains injected data from multiple sources)
    TokenExpirationSeconds:  3607
    ConfigMapName:           kube-root-ca.crt
    ConfigMapOptional:       <nil>
    DownwardAPI:             true
QoS Class:                   BestEffort
Node-Selectors:              kubernetes.io/os=linux
Tolerations:                 node.kubernetes.io/not-ready:NoExecute op=Exists for 300s
                             node.kubernetes.io/unreachable:NoExecute op=Exists for 300s
Events:
  Type     Reason        Age   From             Message
  ----     ------        ----  ----             -------
  Warning  NodeNotReady  61s   node-controller  Node is not ready
```

#### 4. Apply Taint to the failed Node

```
# kubectl taint nodes rhel2 node.kubernetes.io/out-of-service=nodeshutdown:NoExecute
node/rhel2 tainted
```

#### 5. Verify iSCSI PVC Detachment and Pod Rescheduling

Verify that the pod has been rescheduled onto another node and that it has successfully mounted the iSCSI PVC.

```
# ./verify_status.sh
NAME              READY   UP-TO-DATE   AVAILABLE   AGE    CONTAINERS   IMAGES          SELECTOR
test-deployment   1/1     1            1           153m   alpine       alpine:3.19.1   app=test
NAME                        DESIRED   CURRENT   READY   AGE    CONTAINERS   IMAGES          SELECTOR
test-deployment-f64c69647   1         1         1       153m   alpine       alpine:3.19.1   app=test,pod-template-hash=f64c69647
NAME                              READY   STATUS    RESTARTS   AGE   IP             NODE    NOMINATED NODE   READINESS GATES
test-deployment-f64c69647-nxg56   1/1     Running   0          11s   192.168.26.5   rhel1   <none>           <none>

# kubectl  describe  pod   test-deployment-f64c69647-nxg56
Name:             test-deployment-f64c69647-nxg56
Namespace:        default
Priority:         0
Service Account:  default
Node:             rhel1/192.168.0.61
Start Time:       Tue, 11 Mar 2025 05:09:34 +0000
Labels:           app=test
                  pod-template-hash=f64c69647
Annotations:      cni.projectcalico.org/containerID: 27613e1db214d3476698bca35c2051f3b35bd226809af209b433af63256f113c
                  cni.projectcalico.org/podIP: 192.168.26.5/32
                  cni.projectcalico.org/podIPs: 192.168.26.5/32
Status:           Running
IP:               192.168.26.5
IPs:
  IP:           192.168.26.5
Controlled By:  ReplicaSet/test-deployment-f64c69647
Containers:
  alpine:
    Container ID:  cri-o://125224aac822c61d3cbd067000a205e24329b81f17a203ab299941599a7eda73
    Image:         alpine:3.19.1
    Image ID:      docker.io/library/alpine@sha256:6457d53fb065d6f250e1504b9bc42d5b6c65941d57532c072d929dd0628977d0
    Port:          <none>
    Host Port:     <none>
    Command:
      /bin/sh
      -c
      sleep 7d
    State:          Running
      Started:      Tue, 11 Mar 2025 05:09:42 +0000
    Ready:          True
    Restart Count:  0
    Environment:    <none>
    Mounts:
      /data from iscsi-vol (rw)
      /var/run/secrets/kubernetes.io/serviceaccount from kube-api-access-fvzks (ro)
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
  kube-api-access-fvzks:
    Type:                    Projected (a volume that contains injected data from multiple sources)
    TokenExpirationSeconds:  3607
    ConfigMapName:           kube-root-ca.crt
    ConfigMapOptional:       <nil>
    DownwardAPI:             true
QoS Class:                   BestEffort
Node-Selectors:              kubernetes.io/os=linux
Tolerations:                 node.kubernetes.io/not-ready:NoExecute op=Exists for 300s
                             node.kubernetes.io/unreachable:NoExecute op=Exists for 300s
Events:
  Type     Reason                  Age   From                     Message
  ----     ------                  ----  ----                     -------
  Normal   Scheduled               50s   default-scheduler        Successfully assigned default/test-deployment-f64c69647-nxg56 to rhel1
  Warning  FailedAttachVolume      51s   attachdetach-controller  Multi-Attach error for volume "pvc-5576a0d5-797e-4268-beed-ba3755439129" Volume is already used by pod(s) test-deployment-f64c69647-888g8
  Normal   SuccessfulAttachVolume  48s   attachdetach-controller  AttachVolume.Attach succeeded for volume "pvc-5576a0d5-797e-4268-beed-ba3755439129"
  Normal   Pulled                  42s   kubelet                  Container image "alpine:3.19.1" already present on machine
  Normal   Created                 42s   kubelet                  Created container alpine
  Normal   Started                 42s   kubelet                  Started container alpine
```

Verify iSCSI PVC attachment to the healthy node

```
[root@rhel1 ~]# multipath -ll
3600a0980774f6a34712b572d41767173 dm-3 NETAPP,LUN C-Mode
size=2.0G features='3 queue_if_no_path pg_init_retries 50' hwhandler='1 alua' wp=rw
`-+- policy='service-time 0' prio=50 status=active
  |- 33:0:0:0 sdc 8:32 active ready running
  `- 34:0:0:0 sdb 8:16 active ready running
[root@rhel1 ~]# iscsiadm -m session
tcp: [1] 192.168.0.135:3260,1030 iqn.1992-08.com.netapp:sn.7c8b4c9af76e11ee8aac005056b0f629:vs.4 (non-flash)
tcp: [2] 192.168.0.136:3260,1031 iqn.1992-08.com.netapp:sn.7c8b4c9af76e11ee8aac005056b0f629:vs.4 (non-flash)
```







