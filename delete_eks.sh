#!/bin/bash

clustername="amoeller"

aws --region eu-central-1 --profile saml cloudformation delete-stack --stack-name VPC-EKS-$clustername-worker-nodes
aws --region eu-central-1 --profile saml eks delete-cluster --name eks-$clustername
aws --region eu-central-1 --profile saml cloudformation delete-stack --stack-name VPC-EKS-$clustername
