# Enable APIs

gcloud services enable \
        cloudapis.googleapis.com \
        container.googleapis.com \
        containerregistry.googleapis.com \
        cloudbuild.googleapis.com


# Add tools to Cloud Shell

mkdir -p ~/.bin && \
cd ~/.bin && \
curl -LO https://raw.githubusercontent.com/ahmetb/kubectx/master/kubectx && \
chmod +x kubectx && \
curl -LO https://raw.githubusercontent.com/ahmetb/kubectx/master/kubens && \
chmod +x kubens && \
curl -LO  https://storage.googleapis.com/kubernetes-helm/helm-v2.12.0-linux-amd64.tar.gz && \
tar xzf helm-v2.12.0-linux-amd64.tar.gz && \
rm helm-v2.12.0-linux-amd64.tar.gz && \
mv linux-amd64/helm ./helm && \
rm -r linux-amd64 && \
# add that to bashrc !! export PATH=${HOME}/.bin:${PATH}
