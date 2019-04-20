#!/bin/bash


export proj=$(gcloud config get-value project)
export zone="us-east1-b"

root="/home/ed_mitchell/myscript/istio/istio-1.1.2"
# cd $root


# Download istio 1.1.2
# Download istio 1.1.2
# curl -LO https://github.com/istio/istio/releases/download/1.1.2/istio-1.1.2-linux.tar.gz
# tar xzf istio-1.1.2-linux.tar.gz && rm istio-1.1.2-linux.tar.gz


# Clusters creation

function setup-cluster () {

gcloud container clusters create $1 --zone $zone --username "admin" \
  --cluster-version latest --machine-type "n1-standard-2" --image-type "COS" --disk-size "100" \
  --scopes "https://www.googleapis.com/auth/compute","https://www.googleapis.com/auth/devstorage.read_only",\
"https://www.googleapis.com/auth/logging.write","https://www.googleapis.com/auth/monitoring",\
"https://www.googleapis.com/auth/servicecontrol","https://www.googleapis.com/auth/service.management.readonly",\
"https://www.googleapis.com/auth/trace.append" \
--num-nodes "4" --network "default" --enable-cloud-logging --enable-cloud-monitoring --enable-ip-alias

# --async is used here.. and hopefully cluster-1 will be up when cluster-2 will be finished..
#  async while cluster-2 creation is working didn't work....


gcloud container clusters get-credentials $1 --zone $zone

kubectl config use-context "gke_${proj}_${zone}_$1"
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

function setup-clusters () {

setup-cluster "cluster-1"
setup-cluster "cluster-2"

setup-firewall
}






function setup-istio-master () {
echo "------setup istio master control plane"
echo "based on https://istio.io/docs/setup/kubernetes/install/kubernetes/#installation-steps "
cd $root
kubectl config use-context "gke_${proj}_${zone}_$1"
for i in install/kubernetes/helm/istio-init/files/crd*yaml; do kubectl apply -f $i; done
kubectl apply -f install/kubernetes/istio-demo-auth.yaml
#  I didn't have to create the namespace !!
kubectl label namespace default istio-injection=enabled
}


function setup-istio-master-vpn () {
echo "--------setup istio controle plane for multicluster vpn config"
echo "taken from https://istio.io/docs/examples/multicluster/gke/"

cd $root
kubectl config use-context "gke_${proj}_${zone}_$1"
cat install/kubernetes/helm/istio-init/files/crd-* > istio_master.yaml
helm template install/kubernetes/helm/istio --name istio --namespace istio-system >> istio_master.yaml
kubectl create ns istio-system
kubectl apply -f istio_master.yaml
kubectl label namespace default istio-injection=enabled

echo "wait before setting up the remote istio"
}

function setup-istio-remote-vpn () {

echo "--------setup remote istio vpn config"
echo "taken from https://istio.io/docs/setup/kubernetes/install/multicluster/vpn/"
echo "you must wait istio control plane to be up before applying this config"

cd $root
echo "fetching cluster-1 ips"
kubectl config use-context "gke_${proj}_${zone}_cluster-1"
export PILOT_POD_IP=$(kubectl -n istio-system get pod -l istio=pilot -o jsonpath='{.items[0].status.podIP}')
export POLICY_POD_IP=$(kubectl -n istio-system get pod -l istio=mixer -o jsonpath='{.items[0].status.podIP}')
export TELEMETRY_POD_IP=$(kubectl -n istio-system get pod -l istio-mixer-type=telemetry -o jsonpath='{.items[0].status.podIP}')

echo "pilot pod ip is ${PILOT_POD_IP}"
echo "policy pod ip is ${POLICY_POD_IP}"
echo "telemetry pod ip is ${TELEMETRY_POD_IP}"

echo " creating helm template"
 helm template install/kubernetes/helm/istio --namespace istio-system \
--name istio-remote \
--values install/kubernetes/helm/istio/values-istio-remote.yaml \
--set global.remotePilotAddress=${PILOT_POD_IP} \
--set global.remotePolicyAddress=${POLICY_POD_IP} \
--set global.remoteTelemetryAddress=${TELEMETRY_POD_IP} > $root/istio-remote.yaml


 echo "-------remote installing.."
kubectl config use-context "gke_${proj}_${zone}_cluster-2" 
kubectl create ns istio-system
kubectl apply -f $root/istio-remote.yaml
kubectl label namespace default istio-injection=enabled


echo "------creating remote config files"

export WORK_DIR=$(pwd)
CLUSTER_NAME=$(kubectl config view --minify=true -o jsonpath='{.clusters[].name}')
CLUSTER_NAME="${CLUSTER_NAME##*_}"
export KUBECFG_FILE=${WORK_DIR}/${CLUSTER_NAME}
SERVER=$(kubectl config view --minify=true -o jsonpath='{.clusters[].cluster.server}')
NAMESPACE=istio-system
SERVICE_ACCOUNT=istio-multi
SECRET_NAME=$(kubectl get sa ${SERVICE_ACCOUNT} -n ${NAMESPACE} -o jsonpath='{.secrets[].name}')
CA_DATA=$(kubectl get secret ${SECRET_NAME} -n ${NAMESPACE} -o jsonpath="{.data['ca\.crt']}")
TOKEN=$(kubectl get secret ${SECRET_NAME} -n ${NAMESPACE} -o jsonpath="{.data['token']}" | base64 --decode)

cat <<EOF > ${KUBECFG_FILE}
apiVersion: v1
clusters:
   - cluster:
       certificate-authority-data: ${CA_DATA}
       server: ${SERVER}
     name: ${CLUSTER_NAME}
contexts:
   - context:
       cluster: ${CLUSTER_NAME}
       user: ${CLUSTER_NAME}
     name: ${CLUSTER_NAME}
current-context: ${CLUSTER_NAME}
kind: Config
preferences: {}
users:
   - name: ${CLUSTER_NAME}
     user:
       token: ${TOKEN}
EOF


echo "instantiating secrets on cluster-1..."
kubectl config use-context "gke_${proj}_${zone}_cluster-1"
kubectl create secret generic ${CLUSTER_NAME} --from-file ${KUBECFG_FILE} -n ${NAMESPACE}
kubectl label secret ${CLUSTER_NAME} istio/multiCluster=true -n ${NAMESPACE}



}

function setup-istio-all-vpn () {

setup-istio-master-vpn "cluster-1" 
setup-istio-istio-vpn

}

function setup-multicluster-vpn () {

setup-clusters
setup-istio-all-vpn

}

function setup-istio-gw () {
echo "------setup istio control plane in 1 cluster for multicluster with gateway connectivity"
echo "based on https://istio.io/docs/setup/kubernetes/install/multicluster/gateways/"

cd $root
cat install/kubernetes/helm/istio-init/files/crd-* > istio.yaml
helm template install/kubernetes/helm/istio --name istio --namespace istio-system \
    -f install/kubernetes/helm/istio/example-values/values-istio-multicluster-gateways.yaml >> istio.yaml

kubectl config use-context "gke_${proj}_${zone}_$1"

kubectl create namespace istio-system
kubectl create secret generic cacerts -n istio-system \
    --from-file=samples/certs/ca-cert.pem \
    --from-file=samples/certs/ca-key.pem \
    --from-file=samples/certs/root-cert.pem \
    --from-file=samples/certs/cert-chain.pem

kubectl apply -f istio.yaml

kubectl label namespace default istio-injection=enabled

}

function setup-dns-gw () {

echo "creating DNS on $1"

kubectl config use-context "gke_${proj}_${zone}_$1"
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: kube-dns
  namespace: kube-system
data:
  stubDomains: |
    {"global": ["$(kubectl get svc -n istio-system istiocoredns -o jsonpath={.spec.clusterIP})"]}
EOF


}


function setup-istio-all-gw () {

echo "------setup istio control plane in both clusters with gateway connectivity"
echo "based on https://istio.io/docs/setup/kubernetes/install/multicluster/gateways/"

setup-istio-gw "cluster-1"
setup-istio-gw "cluster-2"

setup-dns-gw "cluster-1"
setup-dns-gw "cluster-2"

}

function setup-multicluster-gw () {
echo "------setup 2 gke clusters based on istio multicluster with gateway connectivity"
echo "based on https://istio.io/docs/setup/kubernetes/install/multicluster/gateways/"

setup-clusters
setup-istio-all-gw

}



#  
#setup-cluster "cluster-1"
#setup-cluster "cluster-2"
