# Azure Infrastructure Requirements for GitHub-Hosted Runners with VNET Integration
## GitHub Enterprise Cloud with EU Data Residency

---

## 1. Background

GitHub Enterprise Cloud with EU Data Residency (GHE.com) requires that VNET-integrated
GitHub-hosted runners be deployed in a supported Azure region. The set of supported regions
for GHE.com differs from those available on github.com. Norway East is not among the
supported regions for this configuration.

This document describes the minimum Azure infrastructure required to deploy VNET-integrated
GitHub-hosted runners in Sweden Central, connected to a hub-spoke network topology with
primary workloads in Norway East.

---

## 2. Supported Azure Regions for VNET-Integrated Runners (GHE.com EU)

| Runner Type | Supported Regions                                                   |
|-------------|---------------------------------------------------------------------|
| x64         | France Central, Sweden Central, Germany West Central, North Europe  |
| arm64       | France Central, North Europe, Germany West Central                  |
| GPU         | Italy North, Sweden Central                                         |

Norway East is listed as a supported region on github.com, but that list does not apply
to GitHub Enterprise Cloud with EU Data Residency. The runner backend infrastructure
differs between the two platforms.

Reference: https://docs.github.com/en/enterprise-cloud@latest/admin/data-residency/network-details-for-ghecom

---

## 3. Required Azure Resources in Sweden Central

| Resource                                  | Configuration                                                                                           |
|-------------------------------------------|---------------------------------------------------------------------------------------------------------|
| Azure Subscription                        | GitHub.Network resource provider must be registered                                                     |
| Resource Group                            | Located in Sweden Central                                                                               |
| Virtual Network (spoke)                   | Located in Sweden Central, peered to hub                                                                |
| Subnet (dedicated)                        | Delegated to GitHub.Network/networkSettings; must be empty; /24 minimum recommended                     |
| Network Security Group                    | Attached to the delegated subnet; rules detailed in Section 4                                           |
| Route Table (UDR)                         | Attached to the delegated subnet; routes detailed in Section 5                                          |
| GitHub.Network/networkSettings resource   | Deployed in the same subscription and region as the VNET; references the subnet and enterprise databaseId |
| VNET Peering                              | Spoke-to-hub peering for internet egress and access to Norway East workloads                            |

A NAT Gateway is not required when outbound internet egress is routed through a hub
firewall or network virtual appliance via UDR.

---

## 4. Network Security Group Rules

### 4.1 Responsibility Split: NSG vs. Hub Firewall

In a hub-spoke topology with a UDR routing 0.0.0.0/0 to the hub firewall, outbound
internet traffic always passes through the firewall. The NSG does not need outbound
rules for GitHub IPs, Storage, or Entra ID — that is the hub firewall's responsibility
(see Section 6). Azure's default outbound rules allow traffic to flow to the UDR
next-hop, and the firewall applies the allowlists.

Adding outbound IP rules to the NSG would be redundant. Adding an explicit
DenyAllOutbound would prevent traffic from reaching the hub firewall entirely,
defeating the hub-spoke model.

The NSG's role is limited to **inbound isolation**.

### 4.2 Inbound Rules

| Priority | Name             | Source | Destination | Port | Protocol | Action | Purpose                                          |
|----------|------------------|--------|-------------|------|----------|--------|--------------------------------------------------|
| 100      | DenyAllInbound   | *      | *           | *    | *        | Deny   | GitHub does not require inbound connectivity to runners. All inbound traffic must be blocked. |

No additional inbound rules are required. GitHub injects runner NICs into the VNET
but never initiates connections to them. The explicit deny overrides the Azure default
AllowVNetInBound rule, preventing lateral movement from peered workloads.

### 4.3 Outbound Rules

No explicit outbound NSG rules are required. Outbound traffic flows as follows:

| Traffic type | Path | Policy enforcement |
|---|---|---|
| Internet-bound (GitHub, Storage, Entra ID) | Azure default AllowInternetOutBound (65001) to UDR to hub firewall | Hub firewall (Section 6) |
| VNet-internal (private endpoints, hub DNS) | Azure default AllowVNetOutBound (65000) direct via peering | No restriction needed |

All outbound allowlists (GitHub IPs, Storage, Entra ID, FQDNs) are documented in
Section 6 and must be configured on the hub firewall.

### 4.3 GitHub Actions IPs -- EU (GHE.com)

| IP Address / Range     |
|------------------------|
| 74.241.192.231/32      |
| 20.4.161.108/32        |
| 74.241.204.117/32      |
| 20.31.193.160/32       |

### 4.4 GHE.com EU Region IPs

These are the ingress IP ranges for GHE.com EU infrastructure that runners must be
able to reach as outbound destinations.

| IP Range               |
|------------------------|
| 108.143.197.176/28     |
| 20.123.213.96/28       |
| 20.224.46.144/28       |
| 20.240.194.240/28      |
| 20.240.220.192/28      |
| 20.240.211.208/28      |

### 4.5 GitHub.com IPs (Required for All GHE.com Regions)

| IP Address / Range     |
|------------------------|
| 192.30.252.0/22        |
| 185.199.108.0/22       |
| 140.82.112.0/20        |
| 143.55.64.0/20         |
| 20.201.28.151/32       |
| 20.205.243.166/32      |
| 20.87.245.0/32         |
| 4.237.22.38/32         |
| 20.207.73.82/32        |
| 20.27.177.113/32       |
| 20.200.245.247/32      |
| 20.175.192.147/32      |
| 20.233.83.145/32       |
| 20.29.134.23/32        |
| 20.199.39.232/32       |
| 20.217.135.5/32        |
| 4.225.11.198/32        |
| 4.208.26.197/32        |
| 20.26.156.215/32       |

### 4.6 GHE.com EU Egress IPs (For Hub Firewall Inbound Allow-Lists)

These ranges represent traffic originating from GitHub toward your infrastructure.
Configure these on the hub firewall if inbound filtering is applied at the hub level.

| IP Range               |
|------------------------|
| 108.143.221.96/28      |
| 20.61.46.32/28         |
| 20.224.62.160/28       |
| 51.12.252.16/28        |
| 74.241.131.48/28       |

---

## 5. Route Table (UDR)

| Route Name            | Address Prefix | Next Hop Type     | Next Hop Address      | Purpose                                                      |
|-----------------------|----------------|-------------------|-----------------------|--------------------------------------------------------------|
| default-to-hub        | 0.0.0.0/0      | VirtualAppliance  | Hub firewall private IP | All internet-bound egress routed through hub firewall or NVA |

If the hub VNET peering is configured with gateway transit and the hub advertises
routes via BGP, explicit routes to Norway East address space are not required. If
hub-transitive routing is not in use, add the following:

| Route Name               | Address Prefix            | Next Hop Type     | Next Hop Address      | Purpose                                            |
|--------------------------|---------------------------|-------------------|-----------------------|----------------------------------------------------|
| norway-east-workloads    | Norway East VNET range    | VirtualAppliance  | Hub firewall private IP | Route to primary workloads via hub                 |

---

## 6. Hub Firewall Requirements

The hub firewall or NVA must permit the same outbound destinations listed in the NSG
rules above. The following table summarizes the required firewall rule set.

| Rule Purpose                         | Destination                                       | Port | Protocol |
|--------------------------------------|---------------------------------------------------|------|----------|
| GitHub Actions service (EU)          | IPs from Table 4.3                                | 443  | TCP      |
| GHE.com EU infrastructure            | IPs from Table 4.4                                | 443  | TCP      |
| GitHub.com                           | IPs from Table 4.5                                | 443  | TCP      |
| Azure Blob Storage                   | Storage service tag or FQDNs from Table 6.1       | 443  | TCP      |
| Microsoft Entra ID                   | AzureActiveDirectory service tag                  | 443  | TCP      |

### 6.1 FQDN-Based Firewall Rules

If the hub firewall supports FQDN filtering, the following domains must be permitted.

| Domain                               | Purpose                                           |
|--------------------------------------|---------------------------------------------------|
| *.[TENANT].ghe.com                   | GHE.com enterprise instance                       |
| [TENANT].ghe.com                     | GHE.com enterprise instance                       |
| auth.ghe.com                         | GHE.com authentication                            |
| github.com                           | GitHub platform services                          |
| *.githubusercontent.com              | GitHub-hosted content (release assets, raw files) |
| *.blob.core.windows.net              | Azure Blob Storage (broad; restrict per Table 6.2)|
| *.web.core.windows.net               | Azure Web Storage                                 |
| *.githubassets.com                    | GitHub static assets                              |

### 6.2 EU-Specific Storage Account FQDNs (Recommended Restriction)

Instead of permitting *.blob.core.windows.net, the following FQDNs may be used for a
tighter firewall posture.

| FQDN                                          |
|------------------------------------------------|
| prodsdc01resultssa0.blob.core.windows.net      |
| prodsdc01resultssa1.blob.core.windows.net      |
| prodsdc01resultssa2.blob.core.windows.net      |
| prodsdc01resultssa3.blob.core.windows.net      |
| prodweu01resultssa0.blob.core.windows.net      |
| prodweu01resultssa1.blob.core.windows.net      |
| prodweu01resultssa2.blob.core.windows.net      |
| prodweu01resultssa3.blob.core.windows.net      |

---

## 7. TLS Interception Constraint

Outbound traffic from the runner subnet must not be subject to TLS interception. This
applies to Azure Firewall Premium TLS inspection, third-party SSL decryption appliances,
or any proxy that terminates and re-signs TLS connections.

GitHub-hosted runner VMs do not trust intermediate certificates injected by inspection
devices. If TLS inspection is enforced at the hub, GitHub and GHE.com traffic must be
excluded from inspection policy.

The alternative is to deploy custom runner images with the required intermediate
certificates pre-installed.

Reference: https://docs.github.com/en/enterprise-cloud@latest/admin/configuring-settings/configuring-private-networking-for-hosted-compute-products/configuring-private-networking-for-github-hosted-runners-in-your-enterprise

---

## 8. Subnet Delegation and Constraints

| Property              | Value                                                                            |
|-----------------------|----------------------------------------------------------------------------------|
| Delegation            | GitHub.Network/networkSettings                                                   |
| Subnet state          | Must be empty at time of delegation; no pre-existing NICs or resources            |
| Minimum size          | /24 (251 usable IPs)                                                             |
| Sizing guidance       | Maximum expected concurrent runners plus 30 percent buffer                       |
| Service association   | A service association link is applied automatically and prevents accidental subnet deletion |
| Shared use            | The subnet cannot host other Azure services or delegations                       |

---

## 9. RBAC and Identity Requirements

| Requirement                          | Details                                                                          |
|--------------------------------------|----------------------------------------------------------------------------------|
| Azure role: Subscription Contributor | Required to register the GitHub.Network resource provider                        |
| Azure role: Network Contributor      | Required to delegate the subnet and manage network resources                     |
| Enterprise Application 1            | GitHub CPS Network Service (App ID: 85c49807-809d-4249-86e7-192762525474)       |
| Enterprise Application 2            | GitHub Actions API (App ID: 4435c199-c3da-46b9-a61d-76de3f2c9f82)              |

Both enterprise applications are created automatically in the Entra ID tenant when
Azure private networking is configured.

---

## 10. DNS Resolution

If runners require access to private endpoints in Norway East, DNS resolution must be
configured to resolve private DNS zone records across the peered networks.

| Option | Description                                                                          |
|--------|--------------------------------------------------------------------------------------|
| A      | Link Azure Private DNS Zones to both the hub VNET and the Sweden Central spoke VNET  |
| B      | Deploy Azure DNS Private Resolver in the hub; configure the spoke VNET to use hub DNS servers |
| C      | Use existing hub DNS forwarding infrastructure; spoke inherits via peering            |

---

## 11. References

| Source                                  | URL                                                                                                                                                           |
|-----------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------|
| GHE.com Network Details                 | https://docs.github.com/en/enterprise-cloud@latest/admin/data-residency/network-details-for-ghecom                                                            |
| VNET Configuration Guide (Enterprise)   | https://docs.github.com/en/enterprise-cloud@latest/admin/configuring-settings/configuring-private-networking-for-hosted-compute-products/configuring-private-networking-for-github-hosted-runners-in-your-enterprise |
| VNET Configuration Guide (Organization) | https://docs.github.com/en/organizations/managing-organization-settings/configuring-private-networking-for-github-hosted-runners-in-your-organization          |
| GitHub.Network ARM/Bicep Templates      | https://learn.microsoft.com/azure/templates/github.network/networksettings                                                                                     |
| Azure Subnet Delegation                 | https://learn.microsoft.com/azure/virtual-network/subnet-delegation-overview                                                                                   |
