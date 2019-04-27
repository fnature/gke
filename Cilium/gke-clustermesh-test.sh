#!/bin/bash


# Variables
export GCLOUD_PROJECT=$(gcloud config get-value project)
export GKE_ZONE="europe-west4-a"
export NAMESPACE="cilium"
export CLUSTER1="cilium19"
export CLUSTER2="cilium20"
export CLUSTERID1="19"
export CLUSTERID2="20"
export FOLDER="gke-clustermesh-test"

cd ~
rm -rf $CLUSTER1$CLUSTER2
mkdir $CLUSTER1$CLUSTER2
cd $CLUSTER1$CLUSTER2



# Creation of clusters

# gcloud container clusters create ${CLUSTER1} --username "admin" --image-type COS --num-nodes 2 --zone ${GKE_ZONE} --enable-ip-alias --cluster-version=1.12.6-gke.10 
# gcloud container clusters create ${CLUSTER2} --username "admin" --image-type COS --num-nodes 2 --zone ${GKE_ZONE} --enable-ip-alias --cluster-version=1.12.6-gke.10 

# Following testbed to test performance 
gcloud container clusters create ${CLUSTER1} --username "admin" --image-type COS --num-nodes 4 --zone ${GKE_ZONE} --enable-ip-alias --cluster-version latest --machine-type "n1-standard-2" 
gcloud container clusters create ${CLUSTER2} --username "admin" --image-type COS --num-nodes 4 --zone ${GKE_ZONE} --enable-ip-alias --cluster-version latest --machine-type "n1-standard-2"


# kubectx alias

kubectx ${CLUSTER1}=gke_${GCLOUD_PROJECT}_${GKE_ZONE}_${CLUSTER1}
kubectx ${CLUSTER2}=gke_${GCLOUD_PROJECT}_${GKE_ZONE}_${CLUSTER2}


# Cilium installation

cilium_install () {
kubectl create clusterrolebinding cluster-admin-binding \
    --clusterrole=cluster-admin \
    --user=$(gcloud config get-value core/account)

kubectl create namespace cilium
kubectl -n cilium apply -f https://raw.githubusercontent.com/cilium/cilium/v1.4/examples/kubernetes/node-init/node-init.yaml

kubectl -n kube-system delete pod -l k8s-app=kube-dns

#kubectl apply -f https://raw.githubusercontent.com/cilium/cilium/v1.4/examples/kubernetes/1.11/cilium-with-node-init.yaml
kubectl apply -f https://raw.githubusercontent.com/cilium/cilium/v1.4/examples/kubernetes/1.12/cilium-with-node-init.yaml

kubectl delete pods -n kube-system $(kubectl get pods -n kube-system -o custom-columns=NAME:.metadata.name,HOSTNETWORK:.spec.hostNetwork --no-headers=true | grep '<none>' | awk '{ print $1 }')
}

kubectx ${CLUSTER1}
cilium_install

kubectx  ${CLUSTER2}
cilium_install


# Specify the cluster name and ID

kubectx ${CLUSTER1}
kubectl -n cilium patch cm cilium-config -p '{"data":{"cluster-name":"'$CLUSTER1'"}}'
kubectl -n cilium patch cm cilium-config -p '{"data":{"cluster-id":"'$CLUSTERID1'"}}'

kubectx  ${CLUSTER2}
kubectl -n cilium patch cm cilium-config -p '{"data":{"cluster-name":"'$CLUSTER2'"}}'
kubectl -n cilium patch cm cilium-config -p '{"data":{"cluster-id":"'$CLUSTERID2'"}}'


# Expose the Cilium etcd to other clusters

kubectx ${CLUSTER1}
kubectl apply -f https://raw.githubusercontent.com/cilium/cilium/v1.4/examples/kubernetes/clustermesh/cilium-etcd-external-service/cilium-etcd-external-gke.yaml -n cilium

kubectx ${CLUSTER2}
kubectl apply -f https://raw.githubusercontent.com/cilium/cilium/v1.4/examples/kubernetes/clustermesh/cilium-etcd-external-service/cilium-etcd-external-gke.yaml -n cilium


# We wait for external IP of etcd service to come up
sleep 3m

# Extract the TLS keys and generate the etcd configuration
git clone https://github.com/cilium/clustermesh-tools.git
cd clustermesh-tools

kubectx ${CLUSTER1}
./extract-etcd-secrets.sh

kubectx ${CLUSTER2}
./extract-etcd-secrets.sh

./generate-secret-yaml.sh > clustermesh.yaml



# Ensure that the etcd service names can be resolved
./generate-name-mapping.sh > ds.patch

kubectx ${CLUSTER1}
kubectl -n cilium patch ds cilium -p "$(cat ds.patch)"

kubectx ${CLUSTER2}
kubectl -n cilium patch ds cilium -p "$(cat ds.patch)"


# Establish connections between clusters
# the cilium guide applies to default namespace only..

kubectx ${CLUSTER1}
kubectl -n cilium apply -f clustermesh.yaml 

kubectx ${CLUSTER2}
kubectl -n cilium apply -f clustermesh.yaml 

kubectx ${CLUSTER1}
kubectl -n cilium delete pod -l k8s-app=cilium
echo "waiting for daemon set cilium to be ready"
until [ $(kubectl -n cilium get ds cilium -o jsonpath="{.status.numberReady}") == 2 ]; do echo -n "."; sleep 1; done; echo

kubectx ${CLUSTER2}
kubectl -n cilium delete pod -l k8s-app=cilium
echo "waiting for daemon set cilium to be ready"
until [ $(kubectl -n cilium get ds cilium -o jsonpath="{.status.numberReady}") == 2 ]; do echo -n "."; sleep 1; done; echo



# missing step in doc: cilium-operator must be restarted
# "the cilium-operator deployment [...] is responsible to propagate Kubernetes services into the kvstore"
kubectx ${CLUSTER1}
kubectl -n cilium delete pod -l name=cilium-operator
echo "waiting for deployment cilium-operator to be available..."
kubectl -n cilium wait deploy/cilium-operator --for condition=available --timeout=60s

kubectx ${CLUSTER2}
kubectl -n cilium delete pod -l name=cilium-operator
echo "waiting for deployment cilium-operator to be available..."
kubectl -n cilium wait deploy/cilium-operator --for condition=available --timeout=60s


# Deploying a simple example service
kubectx ${CLUSTER1}
kubectl apply -f https://raw.githubusercontent.com/cilium/cilium/v1.4/examples/kubernetes/clustermesh/global-service-example/cluster1.yaml

kubectx ${CLUSTER2}
kubectl apply -f https://raw.githubusercontent.com/cilium/cilium/v1.4/examples/kubernetes/clustermesh/global-service-example/cluster2.yaml



# From either cluster, access the global service:
# kubectl exec -ti xwing-xxx -- curl rebel-base

# cilium node list shows me nodes from both clusters
# but I can only see response from one cluster only









