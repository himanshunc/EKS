# Grafana Dashboard Setup Guide

After `terraform apply` completes, do this one-time setup in the AMG console.

## Step 1 - Open AMG

Run `.\scripts\outputs.ps1` and copy the `grafana_url` value. Open it in your browser.
Log in via AWS SSO.

## Step 2 - Add AMP Data Source (Metrics)

1. Go to **Configuration (gear icon) -> Data Sources -> Add data source**
2. Select **Prometheus**
3. Fill in:
   - **Name**: `AMP-dev`
   - **URL**: copy `amp_endpoint` from `.\scripts\outputs.ps1`
   - **Auth**: enable **SigV4 auth**
   - **SigV4 region**: `ap-south-1`
   - **SigV4 auth provider**: `Workspace IAM Role`
   - **HTTP Method**: `POST`
4. Click **Save & Test** - should show "Data source is working"

## Step 3 - Add CloudWatch Data Source (Logs)

1. Go to **Configuration -> Data Sources -> Add data source**
2. Select **CloudWatch**
3. Fill in:
   - **Name**: `CloudWatch-dev`
   - **Auth Provider**: `Workspace IAM Role`
   - **Default Region**: `ap-south-1`
4. Click **Save & Test** - should show "Data source is working"

## Step 4 - Import Dashboards

Go to **Dashboards -> Import**, enter the ID, click Load, select the AMP data source, click Import.

| Dashboard | ID | Data Source | What it shows |
|---|---|---|---|
| Kubernetes Cluster Overview | `315` | AMP | Nodes, namespaces, pod count |
| Kubernetes Namespace Resources | `3119` | AMP | CPU/memory per namespace |
| Kubernetes Pod Resources | `6417` | AMP | Per-pod CPU, memory, restarts |
| Node Exporter Full | `1860` | AMP | OS-level node metrics |

## Step 5 - Explore Container Logs

1. Go to **Explore (compass icon)**
2. Select **CloudWatch-dev** data source
3. Set **Query Mode** to `Logs`
4. **Log Group**: `/aws/eks/myeks-dev-eks-cluster/containers`
5. Run query

Example Logs Insights query:
```
fields @timestamp, kubernetes.namespace_name, kubernetes.pod_name, log
| sort @timestamp desc
| limit 50
```
