#!/bin/bash

#variables
export AWS_PROFILE="saml"
export AWS_REGION="eu-central-1"

clustername="amoeller"
owner_email="andre.moeller@plusserver.com"
aws_RoleArn="arn:aws:iam::703341388306:role/PS-EKSServiceRole"
aws_NodeInstanceType="t3.micro"
aws_NodeImageId="ami-0d741ed58ca5b342e"
aws_KeyName="MASTER"

# installation start
echo "##### Create VPC #####"
aws cloudformation create-stack --stack-name VPC-EKS-$clustername --template-body https://amazon-eks.s3-us-west-2.amazonaws.com/cloudformation/2019-02-11/amazon-eks-vpc-sample.yaml --tags Key=owner,Value=$owner_email

aws cloudformation wait stack-create-complete --stack-name VPC-EKS-$clustername

aws cloudformation describe-stacks --stack-name VPC-EKS-$clustername
aws_EksSubnetIds=$(aws cloudformation describe-stacks --stack-name VPC-EKS-$clustername | jq -r '.Stacks[0].Outputs[] | select(.OutputKey=="SubnetIds") | .OutputValue')
aws_EksSecurityGroupIds=$(aws cloudformation describe-stacks --stack-name VPC-EKS-$clustername | jq -r '.Stacks[0].Outputs[] | select(.OutputKey=="SecurityGroups") | .OutputValue')
aws_EksVpcId=$(aws cloudformation describe-stacks --stack-name VPC-EKS-$clustername | jq -r '.Stacks[0].Outputs[] | select(.OutputKey=="VpcId") | .OutputValue')

echo "##### Finished VPC #####"
echo "##### Create EKS control plane #####"
aws eks create-cluster --name "eks-$clustername" --role-arn $aws_RoleArn --resources-vpc-config subnetIds="$aws_EksSubnetIds",securityGroupIds="$aws_EksSecurityGroupIds"

i=0
while [ $i -le 180 ] #max 30 min
do
  ((i++))
  sleep 10
  creation_status=$(aws eks describe-cluster --name "eks-$clustername" --query cluster.status)
  echo $creation_status
  if [[ $creation_status == '"ACTIVE"' ]]; then
    break
  fi
done
if [[ $creation_status != '"ACTIVE"' ]]; then
  echo "ERROR: timeout at eks cluster creation"
  exit 1
fi
echo "##### Finished EKS control plane #####"
echo "##### Create EKS worker nodes #####"
aws cloudformation create-stack --stack-name VPC-EKS-$clustername-worker-nodes --template-body https://amazon-eks.s3-us-west-2.amazonaws.com/cloudformation/2019-02-11/amazon-eks-nodegroup.yaml \
--parameters '[
  {"ParameterKey":"Subnets","ParameterValue":"'"$aws_EksSubnetIds"'"},
  {"ParameterKey":"ClusterName","ParameterValue":"eks-'"$clustername"'"},
  {"ParameterKey":"ClusterControlPlaneSecurityGroup","ParameterValue":"'"$aws_EksSecurityGroupIds"'"},
  {"ParameterKey":"NodeGroupName","ParameterValue":"eks-'"$clustername"'-nodes"},
  {"ParameterKey":"NodeInstanceType","ParameterValue":"'"$aws_NodeInstanceType"'"},
  {"ParameterKey":"NodeImageId","ParameterValue":"'"$aws_NodeImageId"'"},
  {"ParameterKey":"KeyName","ParameterValue":"'"$aws_KeyName"'"},
  {"ParameterKey":"VpcId","ParameterValue":"'"$aws_EksVpcId"'"}
]' \
 --tags Key=owner,Value=andre.moeller@plusserver.com \
 --capabilities CAPABILITY_IAM

aws cloudformation wait stack-create-complete --stack-name VPC-EKS-$clustername-worker-nodes
aws cloudformation describe-stacks --stack-name VPC-EKS-$clustername-worker-nodes

aws_EksNodeInstanceRole=$(aws cloudformation describe-stacks --stack-name VPC-EKS-$clustername-worker-nodes | jq -r '.Stacks[0].Outputs[] | select(.OutputKey=="NodeInstanceRole") | .OutputValue')
echo "$aws_EksNodeInstanceRole"
aws eks update-kubeconfig --name eks-$clustername

curl https://amazon-eks.s3-us-west-2.amazonaws.com/cloudformation/2018-11-07/aws-auth-cm.yaml | sed "s|<ARN of instance role (not instance profile)>|$aws_EksNodeInstanceRole|" | kubectl apply -f -

echo "##### Finished EKS worker nodes #####"

sleep 5
kubectl get nodes
