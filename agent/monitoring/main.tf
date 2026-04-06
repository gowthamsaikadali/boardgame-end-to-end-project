terraform {
  required_version = ">= 1.5.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

# Azure Provider
provider "azurerm" {
  features {}
}

# Get AKS cluster details
data "azurerm_kubernetes_cluster" "aks" {
  name                = "gowtham-aks"
  resource_group_name = "gowtham-rg"
}

# Kubernetes Provider (FIXED)
provider "kubernetes" {
  host                   = data.azurerm_kubernetes_cluster.aks.kube_config[0].host
  client_certificate     = base64decode(data.azurerm_kubernetes_cluster.aks.kube_config[0].client_certificate)
  client_key             = base64decode(data.azurerm_kubernetes_cluster.aks.kube_config[0].client_key)
  cluster_ca_certificate = base64decode(data.azurerm_kubernetes_cluster.aks.kube_config[0].cluster_ca_certificate)
}

# -------------------------------
# Namespace
# -------------------------------
resource "kubernetes_namespace_v1" "monitoring" {
  metadata {
    name = "monitoring"
  }
}

# -------------------------------
# Prometheus Config
# -------------------------------
resource "kubernetes_config_map_v1" "prometheus_config" {
  metadata {
    name      = "prometheus-config"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }

  data = {
    "prometheus.yml" = <<-EOT
      global:
        scrape_interval: 15s

      scrape_configs:
        - job_name: "prometheus"
          static_configs:
            - targets: ["localhost:9090"]

        - job_name: "kube-state-metrics"
          static_configs:
            - targets: ["kube-state-metrics.monitoring.svc.cluster.local:8080"]

        - job_name: "backend"
          metrics_path: /actuator/prometheus
          static_configs:
            - targets: ["backend-service.app.svc.cluster.local:8080"]
    EOT
  }
}

# -------------------------------
# Prometheus Deployment
# -------------------------------
resource "kubernetes_deployment_v1" "prometheus" {
  metadata {
    name      = "prometheus"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
    labels = {
      app = "prometheus"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "prometheus"
      }
    }

    template {
      metadata {
        labels = {
          app = "prometheus"
        }
      }

      spec {
        container {
          name  = "prometheus"
          image = "prom/prometheus"

          port {
            container_port = 9090
          }

          args = ["--config.file=/etc/prometheus/prometheus.yml"]

          volume_mount {
            name       = "prometheus-config"
            mount_path = "/etc/prometheus"
          }
        }

        volume {
          name = "prometheus-config"

          config_map {
            name = kubernetes_config_map_v1.prometheus_config.metadata[0].name
          }
        }
      }
    }
  }
}

# -------------------------------
# Prometheus Service
# -------------------------------
resource "kubernetes_service_v1" "prometheus" {
  metadata {
    name      = "prometheus-service"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }

  spec {
    selector = {
      app = "prometheus"
    }

    port {
      port        = 9090
      target_port = 9090
      node_port   = 30090
    }

    type = "NodePort"
  }
}

# -------------------------------
# Grafana Deployment
# -------------------------------
resource "kubernetes_deployment_v1" "grafana" {
  metadata {
    name      = "grafana"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
    labels = {
      app = "grafana"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "grafana"
      }
    }

    template {
      metadata {
        labels = {
          app = "grafana"
        }
      }

      spec {
        container {
          name  = "grafana"
          image = "grafana/grafana-oss"

          port {
            container_port = 3000
          }
        }
      }
    }
  }
}

# -------------------------------
# Grafana Service
# -------------------------------
resource "kubernetes_service_v1" "grafana" {
  metadata {
    name      = "grafana-service"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }

  spec {
    selector = {
      app = "grafana"
    }

    port {
      port        = 3000
      target_port = 3000
      node_port   = 30300
    }

    type = "NodePort"
  }
}

# -------------------------------
# kube-state-metrics SA
# -------------------------------
resource "kubernetes_service_account_v1" "kube_state_metrics" {
  metadata {
    name      = "kube-state-metrics"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }
}

# -------------------------------
# Cluster Role
# -------------------------------
resource "kubernetes_cluster_role_v1" "kube_state_metrics" {
  metadata {
    name = "kube-state-metrics-role"
  }

  rule {
    api_groups = [""]
    resources  = ["pods","nodes","services","endpoints","persistentvolumeclaims","persistentvolumes","namespaces","configmaps","secrets"]
    verbs      = ["list","watch"]
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments","daemonsets","replicasets","statefulsets"]
    verbs      = ["list","watch"]
  }

  rule {
    api_groups = ["batch"]
    resources  = ["jobs","cronjobs"]
    verbs      = ["list","watch"]
  }

  rule {
    api_groups = ["autoscaling"]
    resources  = ["horizontalpodautoscalers"]
    verbs      = ["list","watch"]
  }

  rule {
    api_groups = ["policy"]
    resources  = ["poddisruptionbudgets"]
    verbs      = ["list","watch"]
  }

  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["ingresses","networkpolicies"]
    verbs      = ["list","watch"]
  }
}

# -------------------------------
# Cluster Role Binding
# -------------------------------
resource "kubernetes_cluster_role_binding_v1" "kube_state_metrics" {
  metadata {
    name = "kube-state-metrics-binding"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.kube_state_metrics.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.kube_state_metrics.metadata[0].name
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }
}

# -------------------------------
# kube-state-metrics Deployment
# -------------------------------
resource "kubernetes_deployment_v1" "kube_state_metrics" {
  metadata {
    name      = "kube-state-metrics"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
    labels = {
      app = "kube-state-metrics"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "kube-state-metrics"
      }
    }

    template {
      metadata {
        labels = {
          app = "kube-state-metrics"
        }
      }

      spec {
        service_account_name = kubernetes_service_account_v1.kube_state_metrics.metadata[0].name

        container {
          name  = "kube-state-metrics"
          image = "registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.12.0"

          port {
            container_port = 8080
          }
        }
      }
    }
  }
}

# -------------------------------
# kube-state-metrics Service
# -------------------------------
resource "kubernetes_service_v1" "kube_state_metrics" {
  metadata {
    name      = "kube-state-metrics"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }

  spec {
    selector = {
      app = "kube-state-metrics"
    }

    port {
      port        = 8080
      target_port = 8080
    }

    type = "ClusterIP"
  }
}