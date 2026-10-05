# Debugging & Troubleshooting Guide

Field reference for Cloud Engineer, DevOps, and SRE roles. Commands are organized by layer — run
them top-to-bottom when diagnosing an unknown issue, or jump to the relevant section.

---

## Table of Contents

1. [AWS Account & IAM](#1-aws-account--iam)
2. [Terraform](#2-terraform)
3. [VPC & Networking](#3-vpc--networking)
4. [EKS Cluster](#4-eks-cluster)
5. [EKS Nodes (Managed Node Groups)](#5-eks-nodes-managed-node-groups)
6. [Kubernetes Workloads](#6-kubernetes-workloads)
7. [EKS Add-ons](#7-eks-add-ons)
8. [Pod Identity & IRSA](#8-pod-identity--irsa)
9. [Autoscaling (KEDA / HPA / VPA)](#9-autoscaling-keda--hpa--vpa)
10. [Load Balancer & Ingress](#10-load-balancer--ingress)
11. [API Gateway & VPC Link](#11-api-gateway--vpc-link)
12. [DynamoDB](#12-dynamodb)
13. [Secrets Manager & External Secrets](#13-secrets-manager--external-secrets)
14. [Cognito & Lambda Authorizer](#14-cognito--lambda-authorizer)
15. [Observability (ADOT / CloudWatch / X-Ray)](#15-observability-adot--cloudwatch--x-ray)
16. [IAM Permission Debugging](#16-iam-permission-debugging)
17. [SCP & Permission Boundary Issues](#17-scp--permission-boundary-issues)
18. [Common Error Patterns](#18-common-error-patterns)

---

## 1. AWS Account & IAM

```bash
# Who am I?
aws sts get-caller-identity

# What roles can I assume?
aws iam list-roles --query 'Roles[?contains(RoleName, `deploy`)].RoleName' --output text

# Check effective permissions (simulate a specific action)
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::ACCOUNT_ID:role/ROLE_NAME \
  --action-names iam:CreateInstanceProfile \
  --resource-arns "*"

# List all policies attached to a role
aws iam list-attached-role-policies --role-name ROLE_NAME
aws iam list-role-policies --role-name ROLE_NAME        # inline policies

# View an inline policy
aws iam get-role-policy --role-name ROLE_NAME --policy-name POLICY_NAME

# Check instance profiles for a role
aws iam list-instance-profiles-for-role --role-name ROLE_NAME

# Find resources by tag
aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=Project,Values=anycompany-users \
  --query 'ResourceTagMappingList[].ResourceARN' --output text
```

---

## 2. Terraform

```bash
# Validate config without applying
terraform validate
terraform plan -var-file=environments/dev.tfvars

# Show current state
terraform state list
terraform state show aws_eks_cluster.main

# Why is a resource being recreated?
terraform plan -var-file=environments/dev.tfvars | grep -A 5 "must be replaced"

# Remove a resource from state without destroying it (orphan recovery)
terraform state rm helm_release.eso

# Import an existing resource into state
terraform import -var-file=environments/dev.tfvars \
  aws_eks_cluster.main anycompany-users-dev-cluster

# Force unlock a stuck state
terraform force-unlock LOCK_ID

# Target a single resource for apply/destroy
terraform apply -var-file=environments/dev.tfvars -target=aws_eks_cluster.main
terraform destroy -var-file=environments/dev.tfvars -target=helm_release.keda

# Refresh state without applying (sync state with real AWS)
terraform apply -var-file=environments/dev.tfvars -refresh-only

# Debug provider calls
TF_LOG=DEBUG terraform plan -var-file=environments/dev.tfvars 2>&1 | head -100
```

---

## 3. VPC & Networking

```bash
# List VPCs
aws ec2 describe-vpcs --query 'Vpcs[].{ID:VpcId,CIDR:CidrBlock,Name:Tags[?Key==`Name`].Value|[0]}'

# List subnets with tier tags
aws ec2 describe-subnets \
  --filters Name=vpc-id,Values=VPC_ID \
  --query 'Subnets[].{ID:SubnetId,AZ:AvailabilityZone,CIDR:CidrBlock,Tags:Tags[?Key==`Tier`].Value|[0]}'

# Check route tables
aws ec2 describe-route-tables \
  --filters Name=vpc-id,Values=VPC_ID \
  --query 'RouteTables[].{ID:RouteTableId,Routes:Routes[].DestinationCidrBlock}'

# Check NAT gateways
aws ec2 describe-nat-gateways \
  --filter Name=state,Values=available \
  --query 'NatGateways[].{ID:NatGatewayId,SubnetId:SubnetId,State:State}'

# Security group rules
aws ec2 describe-security-groups --group-ids sg-XXXXX \
  --query 'SecurityGroups[0].{Inbound:IpPermissions,Outbound:IpPermissionsEgress}'

# Test connectivity from a pod (run a debug container)
kubectl run netshoot --rm -it --image=nicolaka/netshoot -- bash
  # inside: curl -v http://SERVICE_IP:PORT/health
  # inside: nslookup kubernetes.default
  # inside: traceroute EXTERNAL_IP

# Check VPC Flow Logs (if enabled)
aws logs filter-log-events \
  --log-group-name /aws/vpc/flowlogs \
  --filter-pattern "[version, account, eni, source, destination, srcport, destport, protocol, packets, bytes, windowstart, windowend, action=REJECT, flowlogstatus]" \
  --start-time $(date -d '30 minutes ago' +%s000)
```

---

## 4. EKS Cluster

```bash
# Update kubeconfig
aws eks update-kubeconfig --region us-east-1 --name CLUSTER_NAME

# Cluster details
aws eks describe-cluster --name CLUSTER_NAME \
  --query 'cluster.{Status:status,Version:version,Endpoint:endpoint,Auth:accessConfig}'

# Check cluster health (control plane)
kubectl get componentstatuses 2>/dev/null || kubectl get --raw /healthz

# List all addons and their status
aws eks list-addons --cluster-name CLUSTER_NAME
aws eks describe-addon --cluster-name CLUSTER_NAME --addon-name vpc-cni \
  --query 'addon.{Status:status,Version:addonVersion,Issues:health.issues}'

# EKS access entries (API auth mode)
aws eks list-access-entries --cluster-name CLUSTER_NAME
aws eks describe-access-entry --cluster-name CLUSTER_NAME --principal-arn ARN

# Check for cluster events
kubectl get events --all-namespaces --sort-by='.lastTimestamp' | tail -20

# API server audit (via CloudWatch if enabled)
aws logs filter-log-events \
  --log-group-name /aws/eks/CLUSTER_NAME/cluster \
  --filter-pattern '"verb":"delete"' \
  --start-time $(date -d '1 hour ago' +%s000)
```

---

## 5. EKS Nodes (Managed Node Groups)

```bash
# List node groups
aws eks list-nodegroups --cluster-name CLUSTER_NAME
aws eks describe-nodegroup --cluster-name CLUSTER_NAME --nodegroup-name NG_NAME \
  --query 'nodegroup.{Status:status,DesiredSize:scalingConfig.desiredSize,InstanceType:instanceTypes,Health:health}'

# Scale a node group
aws eks update-nodegroup-config \
  --cluster-name CLUSTER_NAME \
  --nodegroup-name NG_NAME \
  --scaling-config desiredSize=3,minSize=2,maxSize=5

# Node status in Kubernetes
kubectl get nodes -o wide
kubectl describe node NODE_NAME | grep -A 20 "Conditions:"
kubectl describe node NODE_NAME | grep -A 30 "Allocatable:"

# Node resource usage
kubectl top nodes

# Check which pods are on a node
kubectl get pods --all-namespaces -o wide --field-selector spec.nodeName=NODE_NAME

# Drain a node (for maintenance)
kubectl drain NODE_NAME --ignore-daemonsets --delete-emptydir-data
kubectl uncordon NODE_NAME   # bring it back

# Check kubelet logs (via SSM if nodes have SSM agent)
aws ssm start-session --target INSTANCE_ID
  # journalctl -u kubelet -f

# Node group update (rolling replace)
aws eks update-nodegroup-version \
  --cluster-name CLUSTER_NAME \
  --nodegroup-name NG_NAME \
  --force
```

---

## 6. Kubernetes Workloads

```bash
# Pod status — the first thing to check
kubectl get pods -n NAMESPACE -o wide
kubectl get pods --all-namespaces | grep -v Running | grep -v Completed

# Detailed pod diagnosis
kubectl describe pod POD_NAME -n NAMESPACE
kubectl logs POD_NAME -n NAMESPACE
kubectl logs POD_NAME -n NAMESPACE --previous   # logs from crashed container
kubectl logs POD_NAME -n NAMESPACE -f            # follow live

# Events for a namespace (sorted by time)
kubectl get events -n NAMESPACE --sort-by='.lastTimestamp'

# Exec into a running pod
kubectl exec -it POD_NAME -n NAMESPACE -- /bin/sh

# Check resource requests/limits
kubectl get pods -n NAMESPACE -o json | \
  jq '.items[].spec.containers[].resources'

# Deployment rollout
kubectl rollout status deployment/DEPLOY_NAME -n NAMESPACE
kubectl rollout history deployment/DEPLOY_NAME -n NAMESPACE
kubectl rollout undo deployment/DEPLOY_NAME -n NAMESPACE   # rollback
kubectl rollout restart deployment/DEPLOY_NAME -n NAMESPACE

# Check pod scheduling constraints
kubectl describe pod POD_NAME -n NAMESPACE | grep -A 10 "Events:"
# Common: "0/2 nodes available" = resource pressure, taint, affinity mismatch

# OOMKilled diagnosis
kubectl describe pod POD_NAME -n NAMESPACE | grep -E "OOMKilled|Limits|Requests"
kubectl top pod POD_NAME -n NAMESPACE --containers

# CrashLoopBackOff diagnosis
kubectl describe pod POD_NAME -n NAMESPACE | grep "Restart Count"
kubectl logs POD_NAME -n NAMESPACE --previous

# ConfigMap and Secret mounts
kubectl get configmap -n NAMESPACE
kubectl describe configmap CONFIG_NAME -n NAMESPACE
kubectl get secret -n NAMESPACE
kubectl describe secret SECRET_NAME -n NAMESPACE
kubectl get secret SECRET_NAME -n NAMESPACE -o jsonpath='{.data}' | \
  python3 -c "import sys,json,base64; d=json.load(sys.stdin); [print(k,base64.b64decode(v).decode()) for k,v in d.items()]"
```

---

## 7. EKS Add-ons

```bash
# Check all addon statuses
aws eks list-addons --cluster-name CLUSTER_NAME --output text | \
  xargs -I{} aws eks describe-addon --cluster-name CLUSTER_NAME --addon-name {} \
  --query 'addon.{Name:addonName,Status:status,Issues:health.issues[*].message}'

# Get the latest available version for an addon
aws eks describe-addon-versions --addon-name vpc-cni \
  --kubernetes-version 1.31 \
  --query 'addons[0].addonVersions[0].addonVersion'

# vpc-cni specific
kubectl get daemonset aws-node -n kube-system
kubectl logs -n kube-system -l k8s-app=aws-node --tail=50
kubectl describe daemonset aws-node -n kube-system | grep Image

# coredns specific
kubectl get deployment coredns -n kube-system
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=50
kubectl get configmap coredns -n kube-system -o yaml

# kube-proxy
kubectl get daemonset kube-proxy -n kube-system
kubectl logs -n kube-system -l k8s-app=kube-proxy --tail=20

# ebs-csi-driver
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-ebs-csi-driver
kubectl logs -n kube-system -l app=ebs-csi-controller --tail=50

# pod-identity-agent
kubectl get daemonset eks-pod-identity-agent -n kube-system
kubectl logs -n kube-system -l app.kubernetes.io/name=eks-pod-identity-agent --tail=30
```

---

## 8. Pod Identity & IRSA

```bash
# List Pod Identity associations
aws eks list-pod-identity-associations --cluster-name CLUSTER_NAME \
  --query 'associations[].{NS:namespace,SA:serviceAccount,Role:roleArn}'

# Describe a specific association
aws eks describe-pod-identity-association \
  --cluster-name CLUSTER_NAME \
  --association-id ASSOC_ID

# Verify pod has credentials (from inside the pod)
kubectl exec -it POD_NAME -n NAMESPACE -- \
  aws sts get-caller-identity

# Check service account annotation (IRSA approach)
kubectl get serviceaccount SA_NAME -n NAMESPACE -o yaml | grep -A 5 annotations

# Test IRSA token exists
kubectl exec -it POD_NAME -n NAMESPACE -- \
  ls /var/run/secrets/eks.amazonaws.com/serviceaccount/

# Debug: Pod Identity token path
kubectl exec -it POD_NAME -n NAMESPACE -- \
  cat /var/run/secrets/pods.eks.amazonaws.com/serviceaccount/eks-pod-identity-token

# Common issue: role trust policy missing pods.eks.amazonaws.com
aws iam get-role --role-name ROLE_NAME \
  --query 'Role.AssumeRolePolicyDocument.Statement[*].Principal'
```

---

## 9. Autoscaling (KEDA / HPA / VPA)

```bash
# HPA status
kubectl get hpa -n NAMESPACE
kubectl describe hpa HPA_NAME -n NAMESPACE
# "unknown" metrics = metrics-server not running or no resource requests set

# Check metrics-server
kubectl get pods -n kube-system | grep metrics-server
kubectl top pods -n NAMESPACE
kubectl top nodes

# KEDA ScaledObjects
kubectl get scaledobject -n NAMESPACE
kubectl describe scaledobject SO_NAME -n NAMESPACE
# Check: conditions, lastActiveTime, currentReplicas

# KEDA operator logs
kubectl logs -n keda -l app=keda-operator --tail=50

# VPA recommendations
kubectl get vpa -n NAMESPACE
kubectl get vpa VPA_NAME -n NAMESPACE -o jsonpath='{.status.recommendation}' | python3 -m json.tool

# Cluster Autoscaler (if using CA instead of Karpenter/KEDA)
kubectl logs -n kube-system -l app=cluster-autoscaler --tail=100 | grep -E "scale|expander|node"

# Node group scaling events
aws autoscaling describe-scaling-activities \
  --auto-scaling-group-name ASG_NAME \
  --max-items 10 \
  --query 'Activities[].{Time:StartTime,Status:StatusCode,Cause:Cause}'
```

---

## 10. Load Balancer & Ingress

```bash
# AWS Load Balancer Controller
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --tail=50

# Ingress objects
kubectl get ingress --all-namespaces
kubectl describe ingress INGRESS_NAME -n NAMESPACE
# Check: Address field (should be ALB DNS), events for provisioning errors

# Target Group Bindings (direct pod registration)
kubectl get targetgroupbinding -n NAMESPACE
kubectl describe targetgroupbinding TGB_NAME -n NAMESPACE

# ALB in AWS
aws elbv2 describe-load-balancers \
  --query 'LoadBalancers[?contains(LoadBalancerName, `anycompany`)].{Name:LoadBalancerName,DNS:DNSName,State:State.Code}'

# Target group health
aws elbv2 describe-target-health \
  --target-group-arn ARN \
  --query 'TargetHealthDescriptions[].{Target:Target.Id,Port:Target.Port,Health:TargetHealth.State,Reason:TargetHealth.Reason}'

# Listener rules
aws elbv2 describe-rules \
  --listener-arn LISTENER_ARN \
  --query 'Rules[].{Priority:Priority,Conditions:Conditions[*].Values,Action:Actions[*].Type}'

# Common issue: unhealthy targets
# 1. Check /health endpoint: curl http://POD_IP:8080/health
# 2. Check security group allows ALB → pod traffic
# 3. Check readinessProbe in pod spec
kubectl describe pod POD_NAME -n NAMESPACE | grep -A 10 "Readiness:"
```

---

## 11. API Gateway & VPC Link

```bash
# List REST APIs
aws apigateway get-rest-apis \
  --query 'items[?contains(name, `anycompany`)].{ID:id,Name:name}'

# Check deployments and stages
aws apigateway get-stages --rest-api-id API_ID \
  --query 'item[].{Stage:stageName,Deployed:createdDate,Cache:cacheClusterEnabled}'

# VPC Links
aws apigateway get-vpc-links \
  --query 'items[].{ID:id,Name:name,Status:status,TargetARNs:targetArns}'

# Test endpoint directly
curl -v https://API_ID.execute-api.REGION.amazonaws.com/STAGE/users

# Check Lambda authorizer
aws apigateway get-authorizers --rest-api-id API_ID \
  --query 'items[].{Name:name,Type:type,TTL:authorizerResultTtlInSeconds}'

# Flush authorizer cache (fix stale 403s)
aws apigateway create-deployment \
  --rest-api-id API_ID \
  --stage-name STAGE \
  --description "flush-authorizer-cache"

# API Gateway logs (enable execution logging first)
aws logs filter-log-events \
  --log-group-name "API-Gateway-Execution-Logs_API_ID/STAGE" \
  --filter-pattern "ERROR" \
  --start-time $(date -d '30 minutes ago' +%s000)

# Integration response mapping errors
aws apigateway get-integration \
  --rest-api-id API_ID \
  --resource-id RESOURCE_ID \
  --http-method GET \
  --query '{URI:uri,Type:type,RequestParams:requestParameters}'
```

---

## 12. DynamoDB

```bash
# Table status and billing
aws dynamodb describe-table --table-name TABLE_NAME \
  --query 'Table.{Status:TableStatus,Billing:BillingModeSummary,ItemCount:ItemCount,SizeBytes:TableSizeBytes}'

# Check for throttling (last 5 minutes)
aws cloudwatch get-metric-statistics \
  --namespace AWS/DynamoDB \
  --metric-name UserErrors \
  --dimensions Name=TableName,Value=TABLE_NAME \
  --start-time $(date -d '5 minutes ago' -u +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 300 --statistics Sum

# Consumed capacity
aws cloudwatch get-metric-statistics \
  --namespace AWS/DynamoDB \
  --metric-name ConsumedReadCapacityUnits \
  --dimensions Name=TableName,Value=TABLE_NAME \
  --start-time $(date -d '1 hour ago' -u +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 --statistics Sum

# Scan a table (careful on large tables — use --limit)
aws dynamodb scan --table-name TABLE_NAME --limit 5

# Get a specific item
aws dynamodb get-item \
  --table-name TABLE_NAME \
  --key '{"id":{"S":"USER_ID"}}'

# Check table capacity alarms
aws cloudwatch describe-alarms \
  --alarm-name-prefix TABLE_NAME \
  --query 'MetricAlarms[].{Name:AlarmName,State:StateValue,Reason:StateReason}'
```

---

## 13. Secrets Manager & External Secrets

```bash
# List secrets
aws secretsmanager list-secrets \
  --query 'SecretList[?contains(Name, `anycompany`)].{Name:Name,LastChanged:LastChangedDate}'

# Get secret value
aws secretsmanager get-secret-value --secret-id SECRET_NAME \
  --query 'SecretString' --output text | python3 -m json.tool

# External Secrets Operator
kubectl get pods -n external-secrets
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets --tail=50

# ExternalSecret objects
kubectl get externalsecret -n NAMESPACE
kubectl describe externalsecret ES_NAME -n NAMESPACE
# Check: status.conditions — should be Ready=True, SecretSynced=True

# SecretStore
kubectl get secretstore -n NAMESPACE
kubectl describe secretstore SS_NAME -n NAMESPACE

# ClusterSecretStore
kubectl get clustersecretstore

# Force resync a secret
kubectl annotate externalsecret ES_NAME -n NAMESPACE \
  force-sync=$(date +%s) --overwrite

# Check the synced K8s Secret
kubectl get secret SYNCED_SECRET_NAME -n NAMESPACE -o yaml
```

---

## 14. Cognito & Lambda Authorizer

```bash
# List user pools
aws cognito-idp list-user-pools --max-results 10 \
  --query 'UserPools[?contains(Name, `anycompany`)].{ID:Id,Name:Name}'

# Describe a user pool
aws cognito-idp describe-user-pool --user-pool-id POOL_ID \
  --query 'UserPool.{Name:Name,MFA:MfaConfiguration,Policies:Policies}'

# User status
aws cognito-idp admin-get-user \
  --user-pool-id POOL_ID --username user@example.com \
  --query '{Status:UserStatus,Enabled:Enabled,Attributes:UserAttributes}'

# Reset user to permanent password (fix FORCE_CHANGE_PASSWORD)
aws cognito-idp admin-set-user-password \
  --user-pool-id POOL_ID \
  --username user@example.com \
  --password "NewPassword123!" \
  --permanent

# Get a token for testing
aws cognito-idp initiate-auth \
  --auth-flow USER_PASSWORD_AUTH \
  --auth-parameters USERNAME=user@example.com,PASSWORD=Password123! \
  --client-id CLIENT_ID \
  --query 'AuthenticationResult.IdToken' --output text

# Lambda authorizer logs
aws logs filter-log-events \
  --log-group-name /aws/lambda/anycompany-users-dev-token-authorizer \
  --start-time $(date -d '30 minutes ago' +%s000) \
  --filter-pattern "ERROR"

# Lambda invocation metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Errors \
  --dimensions Name=FunctionName,Value=anycompany-users-dev-token-authorizer \
  --start-time $(date -d '1 hour ago' -u +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 --statistics Sum
```

---

## 15. Observability (ADOT / CloudWatch / X-Ray)

```bash
# ADOT operator and collector
kubectl get pods -n opentelemetry-operator-system
kubectl logs -n opentelemetry-operator-system \
  -l app.kubernetes.io/name=opentelemetry-operator --tail=50

# OpenTelemetry collectors
kubectl get opentelemetrycollector --all-namespaces
kubectl describe opentelemetrycollector COLL_NAME -n NAMESPACE

# X-Ray traces — get service map
aws xray get-service-graph \
  --start-time $(date -d '1 hour ago' -u +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --query 'Services[].{Name:Name,Type:Type,Edges:Edges[*].ReferenceId}'

# CloudWatch Logs Insights query (pod errors last 1h)
aws logs start-query \
  --log-group-name /aws/containerinsights/CLUSTER_NAME/application \
  --start-time $(date -d '1 hour ago' +%s) \
  --end-time $(date +%s) \
  --query-string 'fields @timestamp, @message | filter @message like /ERROR/ | sort @timestamp desc | limit 50'

# Get query results
aws logs get-query-results --query-id QUERY_ID

# Container Insights metrics
aws cloudwatch get-metric-statistics \
  --namespace ContainerInsights \
  --metric-name pod_cpu_utilization \
  --dimensions Name=ClusterName,Value=CLUSTER_NAME Name=Namespace,Value=NAMESPACE \
  --start-time $(date -d '30 minutes ago' -u +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 --statistics Average

# cert-manager (required by ADOT)
kubectl get pods -n cert-manager
kubectl get certificate --all-namespaces
kubectl describe certificate CERT_NAME -n NAMESPACE | grep -A 5 "Status:"
```

---

## 16. IAM Permission Debugging

```bash
# Simulate a single action
aws iam simulate-principal-policy \
  --policy-source-arn ROLE_ARN \
  --action-names iam:CreateInstanceProfile \
  --resource-arns "*" \
  --query 'EvaluationResults[].{Action:EvalActionName,Decision:EvalDecision}'

# Simulate with a specific resource ARN
aws iam simulate-principal-policy \
  --policy-source-arn ROLE_ARN \
  --action-names iam:AddRoleToInstanceProfile \
  --resource-arns "arn:aws:iam::ACCOUNT:instance-profile/eks-*"

# Simulate multiple actions at once
aws iam simulate-principal-policy \
  --policy-source-arn ROLE_ARN \
  --action-names s3:GetObject s3:PutObject \
  --resource-arns "arn:aws:s3:::my-bucket/*"

# CloudTrail — find denied calls
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=CreateInstanceProfile \
  --start-time $(date -d '2 hours ago' -u +%Y-%m-%dT%H:%M:%SZ) \
  --query 'Events[].{Time:EventTime,User:Username,Error:CloudTrailEvent}' \
  --output text

# Denied events for a specific principal
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=Username,AttributeValue=ROLE_OR_USER \
  --start-time $(date -d '1 hour ago' -u +%Y-%m-%dT%H:%M:%SZ) \
  --query 'Events[?contains(CloudTrailEvent, `AccessDenied`)].{Time:EventTime,Event:EventName}'

# Get all policies for an entity (managed + inline)
aws iam list-attached-role-policies --role-name ROLE_NAME --output table
aws iam list-role-policies --role-name ROLE_NAME --output table

# View a managed policy document
POLICY_ARN="arn:aws:iam::aws:policy/AmazonEKSComputePolicy"
VERSION=$(aws iam get-policy --policy-arn $POLICY_ARN \
  --query 'Policy.DefaultVersionId' --output text)
aws iam get-policy-version --policy-arn $POLICY_ARN --version-id $VERSION \
  --query 'PolicyVersion.Document' | python3 -m json.tool
```

---

## 17. SCP & Permission Boundary Issues

SCPs (Service Control Policies) sit above IAM — even if a role's IAM policy allows an action, an SCP can deny it.

```bash
# Symptom: AccessDenied even though simulation returns "allowed"
# Cause: SCP denial — the simulation only evaluates the principal's IAM policies, not SCPs.

# Check if you're in an AWS Organization
aws organizations describe-organization 2>/dev/null

# List SCPs attached to your account (requires org admin or specific delegation)
aws organizations list-policies-for-target \
  --target-id ACCOUNT_ID \
  --filter SERVICE_CONTROL_POLICY \
  --query 'Policies[].{Name:Name,ID:Id}' 2>/dev/null

# Workarounds when SCP blocks an action:
# 1. Pre-create the resource (e.g., instance profile) and reference it directly
# 2. Grant the permission from an IAM role that is exempt from the SCP
# 3. Use a CloudFormation StackSet with OrganizationAccountAccessRole
# 4. Contact the AWS account/org admin to update the SCP

# Identifying SCP blocks in CloudTrail
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=THE_BLOCKED_ACTION \
  --start-time $(date -d '1 hour ago' -u +%Y-%m-%dT%H:%M:%SZ) \
  --query 'Events[*].CloudTrailEvent' --output text | \
  python3 -c "import sys,json; [print(json.dumps(json.loads(l), indent=2)) for l in sys.stdin if l.strip()]" | \
  grep -A 3 "errorCode\|errorMessage"
```

---

## 18. Common Error Patterns

### Pod stuck in `Pending`
```bash
kubectl describe pod POD_NAME -n NAMESPACE | grep -A 10 "Events:"
# "Insufficient cpu/memory"  → scale nodes or reduce requests
# "no nodes available"       → node group not ready or no nodes
# "didn't match node selector" → fix nodeSelector/affinity
# "Unschedulable: 0/N nodes" → all nodes have taints pod doesn't tolerate
```

### Pod in `CrashLoopBackOff`
```bash
kubectl logs POD_NAME -n NAMESPACE --previous
# Check: missing env var, bad config, failed DB connection, OOM
kubectl describe pod POD_NAME -n NAMESPACE | grep -E "Exit Code|OOMKilled|Signal"
```

### `ImagePullBackOff`
```bash
kubectl describe pod POD_NAME -n NAMESPACE | grep -A 5 "Failed to pull"
# Check: ECR repo exists, node role has AmazonEC2ContainerRegistryReadOnly
# Check: image tag exists
aws ecr describe-images --repository-name REPO --query 'imageDetails[*].imageTags'
```

### Terraform `Error: Kubernetes cluster unreachable`
```bash
# Cluster deleted but K8s resources still in state
terraform state rm helm_release.NAME
terraform state rm kubernetes_namespace.NAME
# Then re-run destroy
```

### EKS `NodeNotReady`
```bash
kubectl describe node NODE_NAME | grep -A 10 "Conditions:"
# Check kubelet: connect via SSM or EC2 console → journalctl -u kubelet -f
# Check VPC CNI: kubectl logs -n kube-system -l k8s-app=aws-node --tail=30
# Check disk pressure: df -h on node
```

### API Gateway `502 Bad Gateway`
```bash
# ALB target unhealthy
aws elbv2 describe-target-health --target-group-arn ARN
# Pod not ready
kubectl get pods -n NAMESPACE
kubectl describe pod POD_NAME -n NAMESPACE | grep -A 5 "Readiness"
```

### API Gateway `403 Unauthorized` after valid login
```bash
# Cached authorizer returning stale policy
aws apigateway create-deployment \
  --rest-api-id API_ID --stage-name STAGE --description "flush-cache"
# Long-term: ensure authorizer returns wildcard ARN (arn:aws:execute-api:*:*:*/*)
```

### `ProvisionedThroughputExceededException` (DynamoDB)
```bash
# Check for full table scans in application logs
kubectl logs -n NAMESPACE -l app=users-service | grep -i "scan\|throttl"
# Check DynamoDB metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/DynamoDB --metric-name ThrottledRequests \
  --dimensions Name=TableName,Value=TABLE_NAME \
  --start-time $(date -d '30 minutes ago' -u +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 --statistics Sum
```

### External Secrets not syncing
```bash
kubectl describe externalsecret ES_NAME -n NAMESPACE | grep -A 5 "Status:"
# "Could not get secret" → check Pod Identity association for ESO service account
# "Secret does not exist" → verify secret name in Secrets Manager
aws secretsmanager get-secret-value --secret-id SECRET_NAME
```

### KEDA not scaling
```bash
kubectl describe scaledobject SO_NAME -n NAMESPACE
# "READY=False" → check trigger (SQS queue exists? CloudWatch metric accessible?)
# Check KEDA operator logs for the specific error
kubectl logs -n keda -l app=keda-operator | grep -i "error\|fail" | tail -20
```

---

## Quick-Reference Cheat Sheet

```bash
# ── 60-second cluster health check ──────────────────────────────────────────
kubectl get nodes                                          # nodes ready?
kubectl get pods --all-namespaces | grep -v Running        # any non-Running pods?
kubectl get events --all-namespaces --sort-by='.lastTimestamp' | tail -10  # recent events
kubectl top nodes                                          # resource pressure?
aws eks describe-cluster --name CLUSTER --query 'cluster.status'  # control plane?

# ── Useful aliases ───────────────────────────────────────────────────────────
alias k='kubectl'
alias kgp='kubectl get pods -o wide'
alias kgpa='kubectl get pods --all-namespaces -o wide'
alias kdp='kubectl describe pod'
alias klogs='kubectl logs'
alias kns='kubectl config set-context --current --namespace'
```
