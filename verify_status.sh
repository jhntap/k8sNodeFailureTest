#!/bin/bash
echo "kubectl get $(kubectl get deployment -o name) -o wide"
kubectl get $(kubectl get deployment -o name) -o wide
echo "kubectl get $(kubectl get rs -o name) -o wide"
kubectl get $(kubectl get rs -o name) -o wide
echo "kubectl get $(kubectl get pod -o name) -o wide"
kubectl get $(kubectl get pod -o name) -o wide
echo "kubectl get $(kubectl get pvc -o name) -o wide"
kubectl get $(kubectl get pvc -o name) -o wide
echo "kubectl get $(kubectl get volumeattachments -o name) -o wide"
kubectl get $(kubectl get volumeattachments -o name) -o wide
