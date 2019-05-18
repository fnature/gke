#!/bin/bash


# Variables
export GCLOUD_PROJECT=$(gcloud config get-value project)
export GKE_ZONE="europe-west2-a"
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


function setup-cluster () {

if [ $2 = "policy" ]; then
echo "creating cluster with network policy enabled"
gcloud container clusters create $1 --zone ${GKE_ZONE} --username "admin" \
--cluster-version latest --machine-type "n1-standard-2" --image-type "COS" --disk-size "100" \
--scopes "https://www.googleapis.com/auth/compute","https://www.googleapis.com/auth/devstorage.read_only",\
"https://www.googleapis.com/auth/logging.write","https://www.googleapis.com/auth/monitoring",\
"https://www.googleapis.com/auth/servicecontrol","https://www.googleapis.com/auth/service.management.readonly",\
"https://www.googleapis.com/auth/trace.append" \
--num-nodes "4" --network "default" --enable-cloud-logging --enable-cloud-monitoring --enable-ip-alias --enable-network-policy
else
echo "creating cluster with network policy disabled"
gcloud container clusters create $1 --zone ${GKE_ZONE} --username "admin" \
--cluster-version latest --machine-type "n1-standard-2" --image-type "COS" --disk-size "100" \
--scopes "https://www.googleapis.com/auth/compute","https://www.googleapis.com/auth/devstorage.read_only",\
"https://www.googleapis.com/auth/logging.write","https://www.googleapis.com/auth/monitoring",\
"https://www.googleapis.com/auth/servicecontrol","https://www.googleapis.com/auth/service.management.readonly",\
"https://www.googleapis.com/auth/trace.append" \
--num-nodes "4" --network "default" --enable-cloud-logging --enable-cloud-monitoring --enable-ip-alias    
#  async option  while cluster-2 creation is processing didn't work....
fi

gcloud container clusters get-credentials $1 --zone ${GKE_ZONE}

kubectl config use-context "gke_${GCLOUD_PROJECT}_${GKE_ZONE}_$1"
kubectl get pods --all-namespaces
kubectl create clusterrolebinding cluster-admin-binding --clusterrole=cluster-admin --user="$(gcloud config get-value core/account)"

}

function setup-firewall () {
gcloud compute firewall-rules delete istio-multicluster-test-pods --quiet

function join_by { local IFS="$1"; shift; echo "$*"; }
ALL_CLUSTER_CIDRS=$(gcloud container clusters list --format='value(clusterIpv4Cidr)' | sort | uniq)
ALL_CLUSTER_CIDRS=$(join_by , $(echo "${ALL_CLUSTER_CIDRS}"))
ALL_CLUSTER_NETTAGS=$(gcloud compute instances list --format='value(tags.items.[0])' | sort | uniq)
ALL_CLUSTER_NETTAGS=$(join_by , $(echo "${ALL_CLUSTER_NETTAGS}"))
gcloud compute firewall-rules create istio-multicluster-test-pods \
  --allow=tcp,udp,icmp,esp,ah,sctp \
  --direction=INGRESS \
  --priority=900 \
  --source-ranges="${ALL_CLUSTER_CIDRS}" \
  --target-tags="${ALL_CLUSTER_NETTAGS}" --quiet
}

# Creation of clusters

# gcloud container clusters create ${CLUSTER1} --username "admin" --image-type COS --num-nodes 2 --zone ${GKE_ZONE} --enable-ip-alias --cluster-version=1.12.6-gke.10 
# gcloud container clusters create ${CLUSTER2} --username "admin" --image-type COS --num-nodes 2 --zone ${GKE_ZONE} --enable-ip-alias --cluster-version=1.12.6-gke.10 

# Following testbed to test performance 
# gcloud container clusters create ${CLUSTER1} --username "admin" --image-type COS --num-nodes 4 --zone ${GKE_ZONE} --enable-ip-alias --cluster-version latest --machine-type "n1-standard-2" 
# gcloud container clusters create ${CLUSTER2} --username "admin" --image-type COS --num-nodes 4 --zone ${GKE_ZONE} --enable-ip-alias --cluster-version latest --machine-type "n1-standard-2"

# Following is identical to how Istio was installed
setup-cluster ${CLUSTER1} 
setup-cluster ${CLUSTER2}
setup-firewall


# kubectx alias

kubectx ${CLUSTER1}=gke_${GCLOUD_PROJECT}_${GKE_ZONE}_${CLUSTER1}
kubectx ${CLUSTER2}=gke_${GCLOUD_PROJECT}_${GKE_ZONE}_${CLUSTER2}


# Cilium installation

cilium_install () {
# kubectl create clusterrolebinding cluster-admin-binding \
#    --clusterrole=cluster-admin \
#    --user=$(gcloud config get-value core/account)

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
until [ $(kubectl -n cilium get ds cilium -o jsonpath="{.status.numberReady}") == 4 ]; do echo -n "."; sleep 1; done; echo

kubectx ${CLUSTER2}
kubectl -n cilium delete pod -l k8s-app=cilium
echo "waiting for daemon set cilium to be ready"
until [ $(kubectl -n cilium get ds cilium -o jsonpath="{.status.numberReady}") == 4 ]; do echo -n "."; sleep 1; done; echo



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









