# Trident Force Detach Test for iSCSI Backend

This repository contains sample YAML files for a PersistentVolumeClaim (PVC) and a deployment that can be used to test the force detach feature of NetApp's Trident storage orchestrator during non-graceful Kubernetes node failures.

## Overview

Starting with Kubernetes v1.28, non-graceful node shutdown (NGNS) is enabled by default. This feature allows storage orchestrators like Trident to forcefully detach volumes from nodes that are not responding. This is particularly useful in scenarios where a node becomes unresponsive due to a crash, hardware failure, or network partitioning.

The force detach feature ensures that storage volumes can be quickly and safely detached from failed nodes and attached to other nodes, minimizing downtime and potential data corruption.

* Force detach is available for ontap-san, ontap-san-economy, onatp-nas, and onatp-nas-economy with Trident v25.02 

### Testing Environment
All samples have been tested with the following environment:

* Trident with Kubernetes Advanced v6.0 (Trident 24.02.0 & Kubernetes 1.29.4) <https://labondemand.netapp.com/node/878>

Please note that while these samples have been tested in a specific environment, they may need to be adjusted for use in other setups.
