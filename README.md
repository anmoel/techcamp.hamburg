# techcamp.hamburg

Preperation:

1. google get credentials
2. create clusters and generate kubeconfig

```bash
gcloud container clusters create europe -m g1-small --num-nodes=1 --preemptible -z europe-west4 --async --enable-autoupgrade --cluster-version=1.12.5-gke.5
gcloud container clusters create asia -m g1-small --num-nodes=1 --preemptible -z asia-east1 --async --enable-autoupgrade --cluster-version=1.12.5-gke.5
gcloud container clusters create north-america -m g1-small --num-nodes=1 --preemptible -z us-east1 --async --enable-autoupgrade --cluster-version=1.12.5-gke.5

gcloud container clusters list

gcloud beta container clusters get-credentials asia --region asia-east1 --project techcamp-hamburg-demo
gcloud beta container clusters get-credentials europe --region europe-west4 --project techcamp-hamburg-demo
gcloud beta container clusters get-credentials north-america --region us-east1 --project techcamp-hamburg-demo

vi ~/.kube/config
kubectl config use-context europe
```

3. make me to admin in cluster

```bash
kubectl create clusterrolebinding federation-cluster-admin-binding --clusterrole=cluster-admin --user=$(gcloud config get-value core/account) --context europe
kubectl create clusterrolebinding federation-cluster-admin-binding --clusterrole=cluster-admin --user=$(gcloud config get-value core/account) --context asia
kubectl create clusterrolebinding federation-cluster-admin-binding --clusterrole=cluster-admin --user=$(gcloud config get-value core/account) --context north-america
```

4. download federation repo

```bash
cd ~/go/src/github.com/kubernetes-sigs
git clone git@github.com:kubernetes-sigs/federation-v2.git
cd federation-v2
```

5. generate certificates for istio

```bash
mkdir certs
mkdir certs/europe
mkdir certs/asia
mkdir certs/north-america
openssl genrsa -des3 -out certs/root-key.pem 4096
openssl req -x509 -new -nodes -key certs/root-key.pem -sha256 -days 1024 -out certs/root-cert.pem -subj "/C=DE/ST=HH/O=Plusserver GmbH/CN=techcamp.plusserver.com"

openssl genrsa -out certs/europe/ca-key.pem 2048
openssl req -new -sha256 -key certs/europe/ca-key.pem -subj "/C=DE/ST=HH/O=Plusserver GmbH/CN=europe.techcamp.plusserver.com" -out certs/europe.csr
openssl x509 -req -in certs/europe.csr -CA certs/root-cert.pem -CAkey certs/root-key.pem -CAcreateserial -out certs/europe/ca-cert.pem -days 92 -sha256
cp certs/europe/ca-cert.pem certs/europe/cert-chain.pem

openssl genrsa -out certs/asia/ca-key.pem 2048
openssl req -new -sha256 -key certs/asia/ca-key.pem -subj "/C=DE/ST=HH/O=Plusserver GmbH/CN=asia.techcamp.plusserver.com" -out certs/asia.csr
openssl x509 -req -in certs/asia.csr -CA certs/root-cert.pem -CAkey certs/root-key.pem -CAcreateserial -out certs/asia/ca-cert.pem  -days 92 -sha256
cp certs/asia/ca-cert.pem certs/asia/cert-chain.pem

openssl genrsa -out certs/north-america/ca-key.pem 2048
openssl req -new -sha256 -key certs/north-america/ca-key.pem -subj "/C=DE/ST=HH/O=Plusserver GmbH/CN=north-america.techcamp.plusserver.com" -out certs/north-america.csr
openssl x509 -req -in certs/north-america.csr -CA certs/root-cert.pem -CAkey certs/root-key.pem -CAcreateserial -out certs/north-america/ca-cert.pem  -days 92 -sha256
cp certs/north-america/ca-cert.pem certs/north-america/cert-chain.pem

```

Demo:

1. install federation

```bash
./scripts/deploy-federation-latest.sh asia north-america
kubectl get ns
kubectl -n federation-system get crds
kubectl -n kube-multicluster-public get clusters
```

2. create new namespace

```bash
kubectl apply -f fed-ns.yaml
kubectl get ns
kubectl get ns --context=asia
kubectl get ns --context=north-america
```

3. create application

```bash
kubectl apply -f fed-wordpress.yaml
kubectl -n test-applikationget ns
kubectl get ns --context=asia
kubectl get ns --context=north-america
```

4. install istio

```bash
./install-istio.sh
```

4. configure istio endpoints

```bash

ep_europe=$(kubectl get --context=europe svc --selector=app=istio-ingressgateway -n istio-system -o jsonpath="{.items[0].status.loadBalancer.ingress[0].ip}")
ep_asia=$(kubectl get --context=asia svc --selector=app=istio-ingressgateway -n istio-system -o jsonpath="{.items[0].status.loadBalancer.ingress[0].ip}")
ep_north-america=$(kubectl get --context=north-america svc --selector=app=istio-ingressgateway -n istio-system -o jsonpath="{.items[0].status.loadBalancer.ingress[0].ip}")
```

5. label namespace

```bash
kubectl label namespace test-applikation istio-injection=enabled
kubectl describe ns test-applikation --context north-america

```

6. apply application

kubectl apply --context=europe -n foo -f - <<EOF
apiVersion: networking.istio.io/v1alpha3
kind: ServiceEntry
metadata:
  name: httpbin-bar
spec:
  hosts:
  - httpbin.bar.global
  location: MESH_INTERNAL
  ports:
  - name: http1
    number: 8000
    protocol: http
  resolution: DNS
  addresses:
  - 127.255.0.2
  endpoints:
  - address: ${ep_asia}
    ports:
      http1: 15443
  - address: ${ep_north-america}
    ports:
      http1: 15443
EOF

kubectl apply --context=asia -n foo -f - <<EOF
apiVersion: networking.istio.io/v1alpha3
kind: ServiceEntry
metadata:
  name: httpbin-bar
spec:
  hosts:
  - httpbin.bar.global
  location: MESH_INTERNAL
  ports:
  - name: http1
    number: 8000
    protocol: http
  resolution: DNS
  addresses:
  - 127.255.0.2
  endpoints:
  - address: ${ep_europe}
    ports:
      http1: 15443
  - address: ${ep_north-america}
    ports:
      http1: 15443
EOF

kubectl apply --context=north-america -n foo -f - <<EOF
apiVersion: networking.istio.io/v1alpha3
kind: ServiceEntry
metadata:
  name: httpbin-bar
spec:
  hosts:
  - httpbin.bar.global
  location: MESH_INTERNAL
  ports:
  - name: http1
    number: 8000
    protocol: http
  resolution: DNS
  addresses:
  - 127.255.0.2
  endpoints:
  - address: ${ep_asia}
    ports:
      http1: 15443
  - address: ${ep_europe}
    ports:
      http1: 15443
EOF
