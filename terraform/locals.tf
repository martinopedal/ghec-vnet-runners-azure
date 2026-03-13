# -----------------------------------------------------------------------------
# GHE.com EU IP ranges
#
# Source: https://docs.github.com/en/enterprise-cloud@latest/admin/data-residency/network-details-for-ghecom
#
# These MUST be kept in sync with the GitHub documentation. GitHub may update
# ranges without notice. Verify against the /meta API endpoint or the docs
# page above before any production rollout.
# -----------------------------------------------------------------------------

locals {
  # GitHub Actions service endpoints - EU data residency backend.
  # CX doc Section 4.3
  github_actions_ips_eu = [
    "74.241.192.231/32",
    "20.4.161.108/32",
    "74.241.204.117/32",
    "20.31.193.160/32",
  ]

  # GHE.com EU region ingress IPs - runners must reach these outbound.
  # CX doc Section 4.4
  ghecom_eu_region_ips = [
    "108.143.197.176/28",
    "20.123.213.96/28",
    "20.224.46.144/28",
    "20.240.194.240/28",
    "20.240.220.192/28",
    "20.240.211.208/28",
  ]

  # GitHub.com IPs required for all GHE.com regions.
  # CX doc Section 4.5
  github_com_ips = [
    "192.30.252.0/22",
    "185.199.108.0/22",
    "140.82.112.0/20",
    "143.55.64.0/20",
    "20.201.28.151/32",
    "20.205.243.166/32",
    "20.87.245.0/32",
    "4.237.22.38/32",
    "20.207.73.82/32",
    "20.27.177.113/32",
    "20.200.245.247/32",
    "20.175.192.147/32",
    "20.233.83.145/32",
    "20.29.134.23/32",
    "20.199.39.232/32",
    "20.217.135.5/32",
    "4.225.11.198/32",
    "4.208.26.197/32",
    "20.26.156.215/32",
  ]

  tags = merge(var.tags, {
    managed-by = "terraform"
    purpose    = "github-hosted-runners-vnet"
  })
}
