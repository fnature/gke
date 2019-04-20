#!/bin/bash


export proj=$(gcloud config get-value project)
export zone="us-east1-b"

root="/home/ed_mitchell/myscript/istio"
cd "$root/istio-1.1.2"


#Install the Istio control plane in master cluster with strict TLS

kubectl config use-context "gke_${proj}_${zone}_cluster-1"

for i in install/kubernetes/helm/istio-init/files/crd*yaml; do kubectl apply -f $i; done
kubectl apply -f install/kubernetes/istio-demo-auth.yaml

