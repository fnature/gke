#!/bin/bash


export proj=$(gcloud config get-value project)
export zone="us-east1-b"

root="/home/ed_mitchell/myscript/istio"
cd $root

# Download istio 1.1.2
# curl -LO https://github.com/istio/istio/releases/download/1.1.2/istio-1.1.2-linux.tar.gz
# tar xzf istio-1.1.2-linux.tar.gz && rm istio-1.1.2-linux.tar.gz


# Clusters creation

cluster="cluster-1"
gcloud container clusters create $cluster --zone $zone --username "admin" \
  --cluster-version latest --machine-type "n1-standard-2" --image-type "COS" --disk-size "100" \
  --scopes "https://www.googleapis.com/auth/compute","https://www.googleapis.com/auth/devstorage.read_only",\
"https://www.googleapis.com/auth/logging.write","https://www.googleapis.com/auth/monitoring",\
"https://www.googleapis.com/auth/servicecontrol","https://www.googleapis.com/auth/service.management.readonly",\
"https://www.googleapis.com/auth/trace.append" \
--num-nodes "4" --network "default" --enable-cloud-logging --enable-cloud-monitoring --enable-ip-alias

# --async is used here.. and hopefully cluster-1 will be up when cluster-2 will be finished..
#  async while cluster-2 creation is working didn't work....


gcloud container clusters get-credentials cluster-1 --zone $zone

kubectl config use-context "gke_${proj}_${zone}_cluster-1"
kubectl get pods --all-namespaces
kubectl create clusterrolebinding cluster-admin-binding --clusterrole=cluster-admin --user="$(gcloud config get-value core/account)"

#Install the Istio control plane in master cluster


kubectl config use-context "gke_${proj}_${zone}_cluster-1"
cat istio-1.1.2/install/kubernetes/helm/istio-init/files/crd-* > $root/istio_master.yaml
helm template istio-1.1.2/install/kubernetes/helm/istio --name istio --namespace istio-system >> $root/istio_master.yaml
kubectl create ns istio-system
kubectl apply -f $root/istio_master.yaml
kubectl label namespace default istio-injection=enabled


# Wait that istio is up and check
# kubectl get pods -n istio-system
# with 4 nodes n1-standard-2, it's fast less than 2minutes

