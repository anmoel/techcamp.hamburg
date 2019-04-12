# techcamp.hamburg

## Communication across different managed kubernetes cluster with istio

### Preperation

1. get gcp and aws credentials
2. create clusters and generate kubeconfig

```bash
gcloud container clusters create europe -m n1-standard-2 --num-nodes=1 --preemptible -z europe-west4 --async --enable-autoupgrade --cluster-version=1.12.5-gke.5
gcloud container clusters create asia -m n1-standard-2 --num-nodes=1 --preemptible -z asia-east1 --async --enable-autoupgrade --cluster-version=1.12.5-gke.5
gcloud container clusters create north-america -m n1-standard-2 --num-nodes=1 --preemptible -z us-east1 --async --enable-autoupgrade --cluster-version=1.12.5-gke.5

gcloud container clusters list

rm ~/.kube/config
gcloud beta container clusters get-credentials asia --region asia-east1 --project techcamp-hamburg-demo
gcloud beta container clusters get-credentials north-america --region us-east1 --project techcamp-hamburg-demo
gcloud beta container clusters get-credentials europe --region europe-west4 --project techcamp-hamburg-demo

./install_eks.sh

vi ~/.kube/config
kubectl config use-context europe
```

3. make me to admin in gcp cluster

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
git checkout v0.0.7
```

5. generate certificates for istio

```bash
mkdir certs
mkdir certs/europe
mkdir certs/asia
mkdir certs/north-america
mkdir certs/aws-eks
cd certs
cp ../openssl.cnf ./ca.cnf
touch certindex
echo 1000 > certserial
echo 1000 > crlnumber
openssl genrsa -des3 -out root-key.pem 4096


openssl req -sha256 -new -x509 -days 1826 -key root-key.pem -out root-cert.pem -subj "/C=DE/ST=HH/O=Plusserver GmbH/CN=techcamp.plusserver.com"

openssl genrsa -out europe/ca-key.pem 4096
openssl req -sha256 -new -key europe/ca-key.pem -subj "/C=DE/ST=HH/O=Plusserver GmbH/CN=europe.techcamp.plusserver.com" -out europe.csr
openssl ca -batch -config ca.cnf -notext -in europe.csr -out europe/ca-cert.pem -days 92
cp europe/ca-cert.pem europe/cert-chain.pem

openssl genrsa -out asia/ca-key.pem 4096
openssl req -sha256 -new -key asia/ca-key.pem -subj "/C=DE/ST=HH/O=Plusserver GmbH/CN=asia.techcamp.plusserver.com" -out asia.csr
openssl ca -batch -config ca.cnf -notext -in asia.csr -out asia/ca-cert.pem -days 92
cp asia/ca-cert.pem asia/cert-chain.pem

openssl genrsa -out north-america/ca-key.pem 4096
openssl req -sha256 -new -key north-america/ca-key.pem -subj "/C=DE/ST=HH/O=Plusserver GmbH/CN=north-america.techcamp.plusserver.com" -out north-america.csr
openssl ca -batch -config ca.cnf -notext -in north-america.csr -out north-america/ca-cert.pem -days 92
cp north-america/ca-cert.pem north-america/cert-chain.pem

openssl genrsa -out aws-eks/ca-key.pem 4096
openssl req -sha256 -new -key aws-eks/ca-key.pem -subj "/C=DE/ST=HH/O=Plusserver GmbH/CN=aws-eks.techcamp.plusserver.com" -out aws-eks.csr
openssl ca -batch -config ca.cnf -notext -in aws-eks.csr -out aws-eks/ca-cert.pem -days 92
cp aws-eks/ca-cert.pem aws-eks/cert-chain.pem

```

6. install federation (federation folder)

```bash
./scripts/deploy-federation.sh quay.io/kubernetes-multicluster/federation-v2:v0.0.7 asia north-america aws-eks
kubectl get ns
kubectl -n federation-system get crds
kubectl -n kube-multicluster-public get clusters
kubectl -n federation-system get pods

```

7. create new namespace

```bash
kubectl apply -f fed-ns.yaml
kubectl get ns
kubectl get ns --context=asia
kubectl get ns --context=north-america
```

### Demo with wordpress

1. install istio

```bash
./install-istio.sh
```

2. label namespace

```bash
kubectl label namespace test-application istio-injection=enabled
kubectl describe ns test-application --context asia

```

3. create application and test it in current context

```bash
kubectl apply -f fed-wordpress.yaml
kubectl -n test-application get po --context=asia
kubectl -n test-application get po --context=north-america
kubectl -n test-application get po

```

4. apply service entries in remote cluster

```bash
ep_europe=$(kubectl get --context=europe svc --selector=app=istio-ingressgateway -n istio-system -o jsonpath="{.items[0].status.loadBalancer.ingress[0].ip}")

kubectl apply --context=asia -n test-application -f - <<EOF
apiVersion: networking.istio.io/v1alpha3
kind: ServiceEntry
metadata:
  name: wordpress-mysql-test-application
spec:
  hosts:
  # must be of form name.namespace.global
  - wordpress-mysql.test-application.global
  location: MESH_INTERNAL
  ports:
  - name: mysql
    number: 3306
    protocol: tcp
  resolution: DNS
  addresses:
  - 127.255.0.87 # must be unique in a cluster
  endpoints:
  - address: ${ep_europe}
    ports:
      mysql: 15443 # Do not change this port value
EOF
kubectl --context=asia -n test-application get serviceentry httpbin-test-application -o yaml

kubectl apply --context=north-america -n test-application -f - <<EOF
apiVersion: networking.istio.io/v1alpha3
kind: ServiceEntry
metadata:
  name: wordpress-mysql-test-application
spec:
  hosts:
  # must be of form name.namespace.global
  - wordpress-mysql.test-application.global
  location: MESH_INTERNAL
  ports:
  - name: mysql
    number: 3306
    protocol: tcp
  resolution: DNS
  addresses:
  - 127.255.0.87 # must be unique in a cluster
  endpoints:
  - address: ${ep_europe}
    ports:
      mysql: 15443 # Do not change this port value
EOF

kubectl apply --context=aws-eks -n test-application -f - <<EOF
apiVersion: networking.istio.io/v1alpha3
kind: ServiceEntry
metadata:
  name: wordpress-mysql-test-application
spec:
  hosts:
  # must be of form name.namespace.global
  - wordpress-mysql.test-application.global
  location: MESH_INTERNAL
  ports:
  - name: mysql
    number: 3306
    protocol: tcp
  resolution: DNS
  addresses:
  - 127.255.0.87 # must be unique in a cluster
  endpoints:
  - address: ${ep_europe}
    ports:
      mysql: 15443 # Do not change this port value
EOF
```

5. test with web-browser


### Demo with sleep and httpbin

1. install istio

```bash
./install-istio.sh
```

2. label namespace

```bash
kubectl label namespace test-application istio-injection=enabled
kubectl describe ns test-application --context asia

```

3. create application

```bash
kubectl apply -f fed-httpbin.yaml
kubectl -n test-application get po
kubectl -n test-application get po --context=asia
kubectl -n test-application get po --context=north-america

export SLEEP_POD=$(kubectl get -n test-application pod -l app=sleep -o jsonpath={.items..metadata.name})
kubectl exec  $SLEEP_POD -n test-application -c sleep -- curl -I httpbin:8000/headers

```

4. apply service entries in remote cluster

```bash
ep_europe=$(kubectl get --context=europe svc --selector=app=istio-ingressgateway -n istio-system -o jsonpath="{.items[0].status.loadBalancer.ingress[0].ip}")

kubectl apply --context=asia -n test-application -f - <<EOF
apiVersion: networking.istio.io/v1alpha3
kind: ServiceEntry
metadata:
  name: httpbin-test-application
spec:
  hosts:
  # must be of form name.namespace.global
  - httpbin.test-application.global
  location: MESH_INTERNAL
  ports:
  - name: http1
    number: 8000
    protocol: http
  resolution: DNS
  addresses:
  - 127.255.0.87
  endpoints:
  - address: ${ep_europe}
    ports:
      http1: 15443 # Do not change this port value
EOF
kubectl --context=asia -n test-application get serviceentry httpbin-test-application -o yaml

kubectl apply --context=north-america -n test-application -f - <<EOF
apiVersion: networking.istio.io/v1alpha3
kind: ServiceEntry
metadata:
  name: httpbin-test-application
spec:
  hosts:
  # must be of form name.namespace.global
  - httpbin.test-application.global
  location: MESH_INTERNAL
  ports:
  - name: http1
    number: 8000
    protocol: http
  resolution: DNS
  addresses:
  - 127.255.0.87
  endpoints:
  - address: ${ep_europe}
    ports:
      http1: 15443 # Do not change this port value
EOF

kubectl apply --context=aws-eks -n test-application -f - <<EOF
apiVersion: networking.istio.io/v1alpha3
kind: ServiceEntry
metadata:
  name: httpbin-test-application
spec:
  hosts:
  # must be of form name.namespace.global
  - httpbin.test-application.global
  location: MESH_INTERNAL
  ports:
  - name: http1
    number: 8000
    protocol: http
  resolution: DNS
  addresses:
  - 127.255.0.87
  endpoints:
  - address: ${ep_europe}
    ports:
      http1: 15443 # Do not change this port value
EOF
```

5. test

```
export SLEEP_POD=$(kubectl get --context=asia -n test-application pod -l app=sleep -o jsonpath={.items..metadata.name})
kubectl exec --context=asia $SLEEP_POD -n test-application -c sleep -- curl -I httpbin.test-application.global:8000/headers
```
