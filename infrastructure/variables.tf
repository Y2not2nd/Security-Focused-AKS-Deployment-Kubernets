variable "prefix" {
  description = "Prefix for naming Azure resources (should be unique to avoid name collisions)"
  type        = string
  default     = "akssecuredemo"
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "UK South"
}

variable "admin_group_object_id" {
  description = "Azure AD group Object ID to grant AKS Cluster Admin role (for Kubernetes RBAC via AAD)"
  type        = string
  default     = "d6eb1e73-edad-4c28-a909-f79805a89577"  # Azure AD group Object ID
} 