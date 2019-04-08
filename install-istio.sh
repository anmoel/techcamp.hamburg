#!/bin/bash

export k8s_contexts="$(kubectl config get-contexts -o name)"
export ISTIO_VERSION="1.1.1"

curl -L https://git.io/getLatestIstio | sh -


cat istio-$ISTIO_VERSION/install/kubernetes/helm/istio-init/files/crd-* > ./istio.yaml
helm template istio-$ISTIO_VERSION/install/kubernetes/helm/istio --name istio --namespace istio-system -f istio-$ISTIO_VERSION/install/kubernetes/helm/istio/example-values/values-istio-multicluster-gateways.yaml >> ./istio.yaml


for k8s_context in $k8s_contexts
do
    echo "Cluster: $k8s_context"
    kubectl create namespace istio-system --context="$k8s_context"
    kubectl create secret generic cacerts --context="$k8s_context" -n istio-system \
        --from-file="certs/$k8s_context/ca-cert.pem" \
        --from-file="certs/$k8s_context/ca-key.pem" \
        --from-file="certs/root-cert.pem" \
        --from-file="certs/$k8s_context/cert-chain.pem"

    kubectl apply -f ./istio.yaml --context="$k8s_context"
    proxyip=$(kubectl get svc -n istio-system istiocoredns -o jsonpath={.spec.clusterIP} --context="$k8s_context" )
    kubectl apply --context="$k8s_context" -f - <<EOF
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: coredns
      namespace: kube-system
    data:
      Corefile: |
        .:53 {
            errors
            health
            kubernetes cluster.local in-addr.arpa ip6.arpa {
            pods insecure
            upstream
            fallthrough in-addr.arpa ip6.arpa
            }
            prometheus :9153
            proxy . /etc/resolv.conf
            cache 30
            loop
            reload
            loadbalance
        }
        global:53 {
            errors
            cache 30
            proxy . $proxyip
        }
EOF

done
