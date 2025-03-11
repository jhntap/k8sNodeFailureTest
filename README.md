# Trident Force Detach Test for iSCSI Backend

This repository contains sample YAML files for a PersistentVolumeClaim (PVC) and a deployment that can be used to test the force detach feature of NetApp's Trident storage orchestrator during non-graceful Kubernetes node failures.

### Overview

Starting with Kubernetes v1.28, non-graceful node shutdown (NGNS) is enabled by default. This feature allows storage orchestrators like Trident to forcefully detach volumes from nodes that are not responding. This is particularly useful in scenarios where a node becomes unresponsive due to a crash, hardware failure, or network partitioning.

The force detach feature ensures that storage volumes can be quickly and safely detached from failed nodes and attached to other nodes, minimizing downtime and potential data corruption.

* Force detach is available for all of Trident drivers including ontap-san, ontap-san-economy, onatp-nas, and onatp-nas-economy with v25.02.0

### Testing Environment
All samples have been tested with the following environment:

* Trident with Kubernetes Advanced v6.0 (Trident 24.02.0 & Kubernetes 1.29.4) <https://labondemand.netapp.com/node/878>

Please note that while these samples have been tested in a specific environment, they may need to be adjusted for use in other setups.

### Test Steps for Force Detach Feature in Trident iSCSI Backend

The following steps outline how to test the force detach feature of the Trident iSCSI backend. This feature ensures that a Persistent Volume Claim (PVC) can be detached from a failed node and reattached to a healthy node, allowing the pod that uses the PVC to be rescheduled.

#### 1. Create the PVC
Create a Persistent Volume Claim (PVC) that will be used by the pod. Ensure that the PVC specifications are set to use the Trident iSCSI backend storage class.

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
Create a deployment that uses the PVC created in the previous step. The deployment should define a pod that mounts the PVC.

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





