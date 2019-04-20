#!/bin/bash


export proj=$(gcloud config get-value project)
export zone="us-east1-b"

# Download istio 1.1.2
# curl -LO https://github.com/istio/istio/releases/download/1.1.2/istio-1.1.2-linux.tar.gz
# tar xzf istio-1.1.2-linux.tar.gz && rm istio-1.1.2-linux.tar.gz

root="/home/ed_mitchell/myscript/istio/istio-1.1.2"
cd $root


echo "-------Clusters creation--------"

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



cluster="cluster-2"
gcloud container clusters create $cluster --zone $zone --username "admin" \
  --cluster-version latest --machine-type "n1-standard-2" --image-type "COS" --disk-size "100" \
  --scopes "https://www.googleapis.com/auth/compute","https://www.googleapis.com/auth/devstorage.read_only",\
"https://www.googleapis.com/auth/logging.write","https://www.googleapis.com/auth/monitoring",\
"https://www.googleapis.com/auth/servicecontrol","https://www.googleapis.com/auth/service.management.readonly",\
"https://www.googleapis.com/auth/trace.append" \
--num-nodes "4" --network "default" --enable-cloud-logging --enable-cloud-monitoring --enable-ip-alias

# use --async if you won't want to wait, but clusters have to be up...
#--num-nodes "1" --enable-autoscaling --min-nodes=1 --max-nodes=5 \



gcloud container clusters get-credentials cluster-1 --zone $zone
gcloud container clusters get-credentials cluster-2 --zone $zone


kubectl config use-context "gke_${proj}_${zone}_cluster-1"
kubectl get pods --all-namespaces
kubectl create clusterrolebinding cluster-admin-binding --clusterrole=cluster-admin --user="$(gcloud config get-value core/account)"



kubectl config use-context "gke_${proj}_${zone}_cluster-2"
kubectl get pods --all-namespaces
kubectl create clusterrolebinding cluster-admin-binding --clusterrole=cluster-admin --user="$(gcloud config get-value core/account)"

	


echo "-------firewall creation--------"

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



echo "--------------Install the Istio control plane in master cluster with strict TLS"

kubectl config use-context "gke_${proj}_${zone}_cluster-1"
for i in install/kubernetes/helm/istio-init/files/crd*yaml; do kubectl apply -f $i; done
kubectl apply -f install/kubernetes/istio-demo-auth.yaml
#  I didn't have to create the namespace !!
kubectl label namespace default istio-injection=enabled

# Wait that istio is up and check
# kubectl get pods -n istio-system
# with 4 nodes n1-standard-2, it's fast less than 2minutes

echo "-----------------We wait 3m"
sleep 3m


echo "-------------- Install remote cluster manifest"


export PILOT_POD_IP=$(kubectl -n istio-system get pod -l istio=pilot -o jsonpath='{.items[0].status.podIP}')
export POLICY_POD_IP=$(kubectl -n istio-system get pod -l istio=mixer -o jsonpath='{.items[0].status.podIP}')
export TELEMETRY_POD_IP=$(kubectl -n istio-system get pod -l istio-mixer-type=telemetry -o jsonpath='{.items[0].status.podIP}')

echo "pilot pod ip is ${PILOT_POD_IP}"
echo "policy pod ip is ${POLICY_POD_IP}"
echo "telemetry pod ip is ${TELEMETRY_POD_IP}"

helm template install/kubernetes/helm/istio \
  --namespace istio-system --name istio-remote \
  --values install/kubernetes/helm/istio/values-istio-remote.yaml \
  --set global.remotePilotAddress=${PILOT_POD_IP} \
  --set global.remotePolicyAddress=${POLICY_POD_IP} \
  --set global.remoteTelemetryAddress=${TELEMETRY_POD_IP} > $root/istio-remote.yaml

	
echo ------------"installs the minimal Istio components on remote cluster"

kubectl config use-context "gke_${proj}_${zone}_cluster-2"
kubectl create ns istio-system
kubectl apply -f $root/istio-remote.yaml
kubectl label namespace default istio-injection=enabled

# it takes less than 1min

echo "we wait 2min"
sleep 2m

echo "-------------Create remote cluster’s kubeconfig for Istio Pilot"

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



echo "----------------Configure Istio control plane to discover the remote cluster"

kubectl config use-context "gke_${proj}_${zone}_cluster-1"
kubectl create secret generic ${CLUSTER_NAME} --from-file ${KUBECFG_FILE} -n ${NAMESPACE}
kubectl label secret ${CLUSTER_NAME} istio/multiCluster=true -n ${NAMESPACE}



# Deploy the app


