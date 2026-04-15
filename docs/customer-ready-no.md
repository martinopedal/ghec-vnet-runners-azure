# Krav til Azure-infrastruktur for GitHub-hostede runnere med VNET-integrasjon
## GitHub Enterprise Cloud med EU-dataresidency

---

## 1. Bakgrunn

GitHub Enterprise Cloud med EU-dataresidency (GHE.com) krever at VNET-integrerte
GitHub-hostede runnere deployeres i en stoettet Azure-region. Settet med stoettede
regioner for GHE.com avviker fra de som er tilgjengelige paa github.com. Norway East
er ikke blant de stoettede regionene for denne konfigurasjonen.

Dette dokumentet beskriver den minimale Azure-infrastrukturen som kreves for aa deploye
VNET-integrerte GitHub-hostede runnere i Sweden Central, tilkoblet en hub-spoke
nettverkstopologi med primaere arbeidsbelastninger i Norway East.

Ref: Om GitHub Enterprise Cloud med dataresidency
https://docs.github.com/en/enterprise-cloud@latest/admin/data-residency/about-github-enterprise-cloud-with-data-residency

Ref: Funksjonsoversikt for GitHub Enterprise Cloud med dataresidency
https://docs.github.com/en/enterprise-cloud@latest/admin/data-residency/feature-overview-for-github-enterprise-cloud-with-data-residency

---

## 2. Stoettede Azure-regioner for VNET-integrerte runnere (GHE.com EU)

| Runner-type | Stoettede regioner                                                  |
|-------------|---------------------------------------------------------------------|
| x64         | France Central, Sweden Central, Germany West Central, North Europe  |
| arm64       | France Central, North Europe, Germany West Central                  |
| GPU         | Italy North, Sweden Central                                         |

Norway East er oppfoert som en stoettet region paa github.com, men denne listen gjelder
ikke for GitHub Enterprise Cloud med EU-dataresidency. Runner-backend-infrastrukturen
er forskjellig mellom de to plattformene. Det finnes per i dag ingen offentlig plan
(roadmap) for aa legge til Norway East som stoettet region for GHE.com.

Ref: Nettverksdetaljer for GHE.com (offisiell regionliste)
https://docs.github.com/en/enterprise-cloud@latest/admin/data-residency/network-details-for-ghecom

Ref: Om Azure privat nettverk for GitHub-hostede runnere (github.com-listen, gjelder IKKE GHE.com)
https://docs.github.com/en/enterprise-cloud@latest/admin/configuring-settings/configuring-private-networking-for-hosted-compute-products/about-azure-private-networking-for-github-hosted-runners-in-your-enterprise

---

## 3. Paakrevde Azure-ressurser i Sweden Central

| Ressurs                                   | Konfigurasjon                                                                                            |
|-------------------------------------------|----------------------------------------------------------------------------------------------------------|
| Azure Subscription                          | GitHub.Network-resource provider maa vaere registrert                                                   |
| Resource Group                             | Plassert i Sweden Central                                                                                |
| Virtual Network (spoke)                 | Plassert i Sweden Central, peeret til hub                                                                |
| Subnett (dedikert)                        | Delegert til GitHub.Network/networkSettings; maa vaere tomt; /24 minimum anbefalt                        |
| Network Security Group (NSG)           | Tilknyttet det delegerte subnettet; regler beskrevet i seksjon 4                                         |
| Route Table (UDR)                          | Tilknyttet det delegerte subnettet; ruter beskrevet i seksjon 5                                          |
| GitHub.Network/networkSettings-ressurs    | Deployert i samme abonnement og region som VNET-et; refererer til subnettet og enterprise databaseId     |
| VNET-peering                              | Spoke-til-hub-peering for utgaaende internettilgang og tilgang til arbeidsbelastninger i Norway East      |

En NAT Gateway er ikke paakrevd naar utgaaende internettrafikk rutes gjennom en
hub-firewall eller virtuell nettverksapparat (NVA) via UDR.

**AVNM (Azure Virtual Network Manager):** Hvis ALZ-plattformen bruker AVNM for
hub-spoke-kobling i stedet for manuell VNET-peering, kobles spoke-VNET-et fra
landing zone vending-modulen til huben via en AVNM network group. Runner-designet
er likt i begge tilfeller - modulen trenger bare spoke-VNET-ID og privat IP til
hub-firewallen. AVNM haandterer peering-livssyklus, rutepropagering og security
admin rules. Verifiser at connectivity configuration lar runner-subnettet naa
hub-firewallen via UDR-en.

Ref: Azure-maler for GitHub.Network/networkSettings (Bicep/ARM/Terraform)
https://learn.microsoft.com/azure/templates/github.network/networksettings

Ref: Hva er delegering av subnett i Azure?
https://learn.microsoft.com/azure/virtual-network/subnet-delegation-overview

Ref: Legge til eller fjerne subnettdelegering
https://learn.microsoft.com/azure/virtual-network/manage-subnet-delegation

Ref: Registrere en Azure-resource provider
https://learn.microsoft.com/azure/azure-resource-manager/management/resource-providers-and-types

---

## 4. NSG-regler

### 4.1 Ansvarsfordeling: NSG vs. Hub Firewall

I en hub-spoke topologi med UDR som ruter 0.0.0.0/0 til hub-firewallen, gaar all
outbound internettrafikk gjennom firewallen. NSG-en trenger ikke outbound-regler
for GitHub IP-er, Storage eller Entra ID - det er hub-firewallens ansvar
(se seksjon 6). Azure sine standard outbound-regler tillater trafikken aa naa
UDR next-hop, og firewallen haandterer allowlistene.

Aa legge til outbound IP-regler i NSG-en ville vaert redundant. Aa legge til en
eksplisitt DenyAllOutbound ville forhindret trafikk fra aa naa hub-firewallen
i det hele tatt, noe som bryter hub-spoke modellen.

NSG-ens rolle er begrenset til **inbound-isolasjon**.

### 4.2 Inbound-regler

| Priority | Navn             | Source | Destination | Port | Protocol | Action | Purpose                                                     |
|-----------|------------------|-------|-------------|------|-----------|----------|-------------------------------------------------------------|
| 100       | DenyAllInbound   | *     | *           | *    | *         | Deny     | GitHub krever aldri inbound-tilkobling til runnere. All inbound-trafikk skal blokkeres. |

Ingen ytterligere inbound-regler er paakrevd. GitHub injiserer runner-NIC-er i
VNET-et men initierer aldri tilkoblinger til dem. Den eksplisitte deny-regelen
overstyrer Azure sin standard AllowVNetInBound-regel, og forhindrer lateral
bevegelse fra peerete arbeidsbelastninger.

### 4.3 Outbound-regler

Ingen eksplisitte outbound NSG-regler er paakrevd. Outbound-trafikk flyter slik:

| Trafikktype | Flyt | Policy enforcement |
|---|---|---|
| Internet-bundet (GitHub, Storage, Entra ID) | Azure default AllowInternetOutBound (65001) til UDR til hub-firewall | Hub-firewall (seksjon 6) |
| VNet-intern (private endpoints, hub DNS) | Azure default AllowVNetOutBound (65000) direkte via peering | Ingen restriksjon noedvendig |

Alle outbound allowlister (GitHub IP-er, Storage, Entra ID, FQDN-er) er dokumentert
i seksjon 6 og maa konfigureres paa hub-firewallen.

Ref: Azure-Service Tagger for NSG
https://learn.microsoft.com/azure/virtual-network/service-tags-overview

### 4.3 GitHub Actions IP-adresser - EU (GHE.com)

| IP-adresse / rekkevidde |
|-------------------------|
| 74.241.192.231/32       |
| 20.4.161.108/32         |
| 74.241.204.117/32       |
| 20.31.193.160/32        |

### 4.4 GHE.com EU-region IP-adresser

Disse er Inbound IP-rekkevidder for GHE.com EU-infrastruktur som runnere maa
kunne naa som outbound-destinasjoner.

| IP-rekkevidde            |
|--------------------------|
| 108.143.197.176/28       |
| 20.123.213.96/28         |
| 20.224.46.144/28         |
| 20.240.194.240/28        |
| 20.240.220.192/28        |
| 20.240.211.208/28        |

### 4.5 GitHub.com IP-adresser (paakrevd for alle GHE.com-regioner)

| IP-adresse / rekkevidde |
|-------------------------|
| 192.30.252.0/22         |
| 185.199.108.0/22        |
| 140.82.112.0/20         |
| 143.55.64.0/20          |
| 20.201.28.151/32        |
| 20.205.243.166/32       |
| 20.87.245.0/32          |
| 4.237.22.38/32          |
| 20.207.73.82/32         |
| 20.27.177.113/32        |
| 20.200.245.247/32       |
| 20.175.192.147/32       |
| 20.233.83.145/32        |
| 20.29.134.23/32         |
| 20.199.39.232/32        |
| 20.217.135.5/32         |
| 4.225.11.198/32         |
| 4.208.26.197/32         |
| 20.26.156.215/32        |

Ref: GHE.com nettverksdetaljer (komplett IP-liste og domener)
https://docs.github.com/en/enterprise-cloud@latest/admin/data-residency/network-details-for-ghecom

Ref: GitHub meta-API for dynamiske IP-oppdateringer
https://docs.github.com/en/rest/meta/meta

### 4.6 GHE.com EU outbound IP-adresser (for inbound allow-lister paa hub-firewall)

Disse rekkeviddene representerer trafikk som kommer fra GitHub mot din infrastruktur.
Konfigurer disse paa hub-firewallen dersom inbound-filtrering anvendes paa hub-nivaa.

| IP-rekkevidde            |
|--------------------------|
| 108.143.221.96/28        |
| 20.61.46.32/28           |
| 20.224.62.160/28         |
| 51.12.252.16/28          |
| 74.241.131.48/28         |

---

## 5. Route Table (UDR)

| Route Name              | Address Prefix  | Next Hop Type    | Next Hop Address        | Purpose                                                         |
|-----------------------|-----------------|--------------------|---------------------------|-----------------------------------------------------------------|
| default-to-hub        | 0.0.0.0/0       | VirtualAppliance   | hub-firewallens private IP | All internettbundet trafikk rutes gjennom hub-firewall eller NVA |

Dersom VNET-peering er konfigurert med gateway-transitt og huben annonserer ruter
via BGP, er det ikke noedvendig med eksplisitte spoke-ruter til Norway East.
Dersom hub-transitiv ruting ikke er i bruk, legg til foelgende:

| Route Name                  | Address Prefix               | Next Hop Type    | Next Hop Address        | Purpose                                            |
|---------------------------|------------------------------|--------------------|---------------------------|----------------------------------------------------|
| norway-east-workloads     | Norway East VNET-rekkevidde  | VirtualAppliance   | hub-firewallens private IP | Ruting til primaere arbeidsbelastninger via hub    |

Ref: Brukerdefinerte ruter i Azure (UDR-oversikt)
https://learn.microsoft.com/azure/virtual-network/virtual-networks-udr-overview

Ref: Administrere UDR-er paa tvers av hub-spoke-topologier
https://learn.microsoft.com/azure/virtual-network-manager/how-to-manage-user-defined-routes-multiple-hub-spoke-topologies

Ref: Hub-spoke nettverkstopologi i Azure
https://learn.microsoft.com/azure/architecture/networking/architecture/hub-spoke

---

## 6. Krav til hub-firewall

hub-firewallen eller NVA-en maa tillate de samme utgaaende destinasjonene som er oppfoert
i NSG-reglene ovenfor. Foelgende tabell oppsummerer det paakrevde firewallregelsettet.

| Regelformaal                         | Destination                                        | Port | Protocol |
|--------------------------------------|----------------------------------------------------|------|-----------|
| GitHub Actions-tjeneste (EU)         | IP-adresser fra tabell 4.3                         | 443  | TCP       |
| GHE.com EU-infrastruktur             | IP-adresser fra tabell 4.4                         | 443  | TCP       |
| GitHub.com                           | IP-adresser fra tabell 4.5                         | 443  | TCP       |
| Azure Blob Storage                   | Storage-Service Tag eller FQDN-er fra seksjon 6.1-6.2 | 443  | TCP       |
| Microsoft Entra ID                   | AzureActiveDirectory-Service Tag                     | 443  | TCP       |
| Azure Monitor (valgfritt)            | AzureMonitor-Service Tag eller FQDN-er fra seksjon 6.3 | 443  | TCP       |

### 6.1 FQDN-baserte firewall-regler

Dersom hub-firewallen stoetter FQDN-filtrering, maa foelgende domener vaere tillatt.

| Domene | Hvorfor |
|--------|---------|
| `*.[TENANT].ghe.com` | GHE.com enterprise API, Git, pakker. Alle enterprise-tjenester rutes hit |
| `[TENANT].ghe.com` | GHE.com enterprise webportal |
| `auth.ghe.com` | GHE.com autentiseringstjeneste |
| `github.com` | GitHub plattformtjenester. Paakrevd for alle GHE.com-regioner ifoelge GitHub-dokumentasjonen |
| `*.githubusercontent.com` | Runner-versjonsoppdateringer, raainnhold, release-assets |
| `*.blob.core.windows.net` | Azure Blob Storage. Brukes til jobbsammendrag, logger, artefakter, cacher |
| `*.web.core.windows.net` | Azure Web Storage. Brukes av GitHub for webbasert innhold |
| `*.githubassets.com` | GitHub statiske ressurser (JS, CSS, bilder) |
| `login.microsoftonline.com` | Primaert Entra ID-endepunkt. Henting av managed identity-token |
| `*.login.microsoftonline.com` | Regionale Entra ID-endepunkter |
| `*.login.microsoft.com` | Entra ID fallback. Noen Azure SDK-er bruker dette domenet |
| `management.azure.com` | Azure Resource Manager. Trengs hvis runnere skal ha tilgang til Azure-ressurser |
| `*.identity.azure.net` | IMDS managed identity-tokenendepunkt. Runner-VM-er ber om token ved oppstart |

### 6.2 EU-spesifikke Storage Account-FQDN-er (anbefalt innsnevring)

I stedet for aa tillate `*.blob.core.windows.net` kan foelgende FQDN-er brukes for en
strammere firewallpolitikk.

| FQDN |
|------|
| `prodsdc01resultssa0.blob.core.windows.net` |
| `prodsdc01resultssa1.blob.core.windows.net` |
| `prodsdc01resultssa2.blob.core.windows.net` |
| `prodsdc01resultssa3.blob.core.windows.net` |
| `prodweu01resultssa0.blob.core.windows.net` |
| `prodweu01resultssa1.blob.core.windows.net` |
| `prodweu01resultssa2.blob.core.windows.net` |
| `prodweu01resultssa3.blob.core.windows.net` |

### 6.3 Valgfrie Azure Monitor-FQDN-er

Hvis diagnostikk er aktivert, tillat foelgende domener.

| Domene | Hvorfor |
|--------|---------|
| `*.ods.opinsights.azure.com` | Log Analytics dataingest (hvis diagnostikk brukes) |
| `*.oms.opinsights.azure.com` | Log Analytics-operasjoner (hvis diagnostikk brukes) |
| `*.ingest.monitor.azure.com` | Data Collection Endpoint (hvis diagnostikk brukes) |
| `*.monitor.azure.com` | Azure Monitor kontrollplan (hvis diagnostikk brukes) |

### 6.4 Copy-Pasteable Azure Firewall Rule Collection

Replace `<runner-subnet-cidr>` with the runner subnet CIDR and `[TENANT]` with your
GHE.com subdomain.

```text
Rule Collection: rc-ghec-runners-application
Priority: 200
Action: Allow

Rules:
  - Name: ghecom-runners
    Source: <runner-subnet-cidr>
    FQDNs: [TENANT].ghe.com, *.[TENANT].ghe.com,
           *.actions.[TENANT].ghe.com, auth.ghe.com,
           github.com, *.githubassets.com,
           *.githubusercontent.com,
           *.blob.core.windows.net, *.web.core.windows.net
    Protocol: Https:443

  - Name: azure-platform
    Source: <runner-subnet-cidr>
    FQDNs: login.microsoftonline.com, *.login.microsoftonline.com,
           *.login.microsoft.com, management.azure.com,
           *.identity.azure.net
    Protocol: Https:443

  - Name: azure-monitor (optional - if diagnostics enabled)
    Source: <runner-subnet-cidr>
    FQDNs: *.ods.opinsights.azure.com, *.oms.opinsights.azure.com,
           *.ingest.monitor.azure.com, *.monitor.azure.com
    Protocol: Https:443
```

```text
Rule Collection: rc-ghec-runners-network
Priority: 200
Action: Allow

Rules:
  - Name: azure-services
    Source: <runner-subnet-cidr>
    Service Tags: Storage, AzureActiveDirectory, AzureMonitor
    Protocol: TCP
    Port: 443
```

Ref: Azure Firewall FQDN-filtrering
https://learn.microsoft.com/azure/firewall/fqdn-filtering-network-rules

Ref: Azure Firewall DNS-proxy
https://learn.microsoft.com/azure/firewall/dns-settings

---

## 7. Krav om ingen TLS-inspeksjon

outbound-trafikk fra runner-subnettet maa ikke underlegges TLS-inspeksjon (TLS
interception). Dette gjelder Azure Firewall Premium TLS-inspeksjon,
tredjeparts SSL-dekrypteringsapparater, eller enhver proxy som terminerer og
re-signerer TLS-forbindelser.

GitHub-hostede runner-VM-er stoler ikke paa mellomliggende sertifikater som injiseres
av inspeksjonsenheter. Dersom TLS-inspeksjon haandheves paa huben, maa GitHub- og
GHE.com-trafikk ekskluderes fra inspeksjonspolitikken.

Alternativet er aa deploye tilpassede runner-images med de paakrevde mellomliggende
sertifikatene forhaaandsinstallert.

Ref: GitHub-dokumentasjon om TLS-inspeksjonskrav
https://docs.github.com/en/enterprise-cloud@latest/admin/configuring-settings/configuring-private-networking-for-hosted-compute-products/configuring-private-networking-for-github-hosted-runners-in-your-enterprise

Ref: Azure Firewall Premium TLS-inspeksjon
https://learn.microsoft.com/azure/firewall/premium-features#tls-inspection

Ref: Sertifikater brukt av Azure Firewall Premium
https://learn.microsoft.com/azure/firewall/premium-certificates

---

## 8. Subnettdelegering og begrensninger

| Egenskap              | Verdi                                                                              |
|-----------------------|------------------------------------------------------------------------------------|
| Delegering            | GitHub.Network/networkSettings                                                     |
| Subnettstatus         | Maa vaere tomt ved delegeringstidspunkt; ingen eksisterende NIC-er eller ressurser |
| Minimumstoerrelse     | /24 (251 brukbare IP-adresser)                                                     |
| Stoerrelsesveiledning | Maksimalt forventet samtidige runnere pluss 30 prosent buffer                      |
| Tjenesteassosiasjonslenke | Anvendes automatisk og forhindrer utilsiktet sletting av subnettet            |
| Delt bruk             | Subnettet kan ikke brukes til andre Azure-tjenester eller delegeringer              |

Ref: Subnettdelegering i Azure
https://learn.microsoft.com/azure/virtual-network/subnet-delegation-overview

Ref: GitHub-veiledning for subnettdimensjonering
https://docs.github.com/en/organizations/managing-organization-settings/configuring-private-networking-for-github-hosted-runners-in-your-organization

---

## 9. RBAC- og identitetskrav

| Krav                                  | Detaljer                                                                           |
|---------------------------------------|------------------------------------------------------------------------------------|
| Azure-rolle: Subscription Contributor | Paakrevd for aa registrere GitHub.Network-resource provideren                     |
| Azure-rolle: Network Contributor      | Paakrevd for aa delegere subnettet og administrere nettverksressurser              |
| Enterprise Application 1             | GitHub CPS Network Service (App-ID: 85c49807-809d-4249-86e7-192762525474)         |
| Enterprise Application 2             | GitHub Actions API (App-ID: 4435c199-c3da-46b9-a61d-76de3f2c9f82)                |

Begge enterprise-applikasjonene opprettes automatisk i Entra ID-tenanten naar Azure
privat nettverksintegrasjon konfigureres.

Ref: Innebygde Azure RBAC-roller
https://learn.microsoft.com/azure/role-based-access-control/built-in-roles

Ref: GitHub Actions-tjenestens paakrevde tillatelser
https://docs.github.com/en/enterprise-cloud@latest/admin/configuring-settings/configuring-private-networking-for-hosted-compute-products/about-azure-private-networking-for-github-hosted-runners-in-your-enterprise#about-the-github-actions-service-permissions

---

## 10. DNS-opploesning

Dersom runnere trenger tilgang til private endepunkter i Norway East, maa
DNS-opploesning konfigureres for aa opploese poster i private DNS-soner paa tvers av
de peerete nettverkene.

| Alternativ | Beskrivelse                                                                              |
|------------|------------------------------------------------------------------------------------------|
| A          | Koble Azure Private DNS-soner til baade hub-VNET-et og Sweden Central spoke-VNET-et      |
| B          | Deploye Azure DNS Private Resolver i huben; konfigurere spoke-VNET-et til aa bruke hubens DNS-servere |
| C          | Utnytte eksisterende DNS-videresendings-infrastruktur i huben; spoke arver via peering   |

Ref: Azure DNS Private Resolver
https://learn.microsoft.com/azure/dns/dns-private-resolver-overview

Ref: Azure Private DNS-soner
https://learn.microsoft.com/azure/dns/private-dns-overview

Ref: DNS-konfigurasjon i hub-spoke-topologier
https://learn.microsoft.com/azure/architecture/networking/architecture/private-link-virtual-wan-dns-guide

---

## 11. VNET-peering mellom Sweden Central og Norway East

| Egenskap                        | Konfigurasjon                                                                    |
|---------------------------------|----------------------------------------------------------------------------------|
| Peering-type                    | Global VNET-peering (regioner er forskjellige)                                   |
| Allow Forwarded Traffic         | Aktivert paa spoke-peering (for trafikk via hub-firewall)                        |
| Allow Gateway Transit           | Aktivert paa hub-peering (dersom VPN/ExpressRoute-gateway finnes i huben)        |
| Use Remote Gateway              | Aktivert paa spoke-peering (for aa bruke hubens gateway)                         |
| Kostnader                       | Utgaaende dataoeverfoering mellom regioner faktureres per GB                     |

Ref: Azure Virtual Network-peering
https://learn.microsoft.com/azure/virtual-network/virtual-network-peering-overview

Ref: Priser for VNET-peering
https://azure.microsoft.com/pricing/details/virtual-network/

---

## 12. Referanser

| Source                                                 | URL                                                                                                                                                                    |
|-------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| GHE.com nettverksdetaljer                             | https://docs.github.com/en/enterprise-cloud@latest/admin/data-residency/network-details-for-ghecom                                                                     |
| Om GitHub Enterprise Cloud med dataresidency          | https://docs.github.com/en/enterprise-cloud@latest/admin/data-residency/about-github-enterprise-cloud-with-data-residency                                              |
| Funksjonsoversikt for GHE.com med dataresidency       | https://docs.github.com/en/enterprise-cloud@latest/admin/data-residency/feature-overview-for-github-enterprise-cloud-with-data-residency                               |
| VNET-konfigurasjonsveiledning (Enterprise)            | https://docs.github.com/en/enterprise-cloud@latest/admin/configuring-settings/configuring-private-networking-for-hosted-compute-products/configuring-private-networking-for-github-hosted-runners-in-your-enterprise |
| VNET-konfigurasjonsveiledning (Organisasjon)          | https://docs.github.com/en/organizations/managing-organization-settings/configuring-private-networking-for-github-hosted-runners-in-your-organization                   |
| Om Azure privat nettverk for runnere                  | https://docs.github.com/en/enterprise-cloud@latest/admin/configuring-settings/configuring-private-networking-for-hosted-compute-products/about-azure-private-networking-for-github-hosted-runners-in-your-enterprise |
| Feilsoeking av Azure privat nettverk for runnere      | https://docs.github.com/en/enterprise-cloud@latest/admin/configuring-settings/configuring-private-networking-for-hosted-compute-products/troubleshooting-azure-private-network-configurations-for-github-hosted-runners-in-your-enterprise |
| GitHub.Network ARM/Bicep/Terraform-maler              | https://learn.microsoft.com/azure/templates/github.network/networksettings                                                                                              |
| Azure subnettdelegering                               | https://learn.microsoft.com/azure/virtual-network/subnet-delegation-overview                                                                                            |
| Administrere subnettdelegering                        | https://learn.microsoft.com/azure/virtual-network/manage-subnet-delegation                                                                                              |
| Azure VNET-peering                                    | https://learn.microsoft.com/azure/virtual-network/virtual-network-peering-overview                                                                                      |
| Brukerdefinerte ruter (UDR)                           | https://learn.microsoft.com/azure/virtual-network/virtual-networks-udr-overview                                                                                         |
| Hub-spoke nettverkstopologi                           | https://learn.microsoft.com/azure/architecture/networking/architecture/hub-spoke                                                                                         |
| Administrere UDR-er i hub-spoke                       | https://learn.microsoft.com/azure/virtual-network-manager/how-to-manage-user-defined-routes-multiple-hub-spoke-topologies                                                |
| Azure NSG-oversikt                                    | https://learn.microsoft.com/azure/virtual-network/network-security-groups-overview                                                                                       |
| Azure Service Tagger                                  | https://learn.microsoft.com/azure/virtual-network/service-tags-overview                                                                                                  |
| Azure RBAC innebygde roller                           | https://learn.microsoft.com/azure/role-based-access-control/built-in-roles                                                                                               |
| Azure DNS Private Resolver                            | https://learn.microsoft.com/azure/dns/dns-private-resolver-overview                                                                                                      |
| Azure Private DNS-soner                               | https://learn.microsoft.com/azure/dns/private-dns-overview                                                                                                               |
| Azure Firewall Premium TLS-inspeksjon                 | https://learn.microsoft.com/azure/firewall/premium-features#tls-inspection                                                                                               |
| Azure Firewall sertifikater                           | https://learn.microsoft.com/azure/firewall/premium-certificates                                                                                                          |
| Azure Firewall FQDN-filtrering                        | https://learn.microsoft.com/azure/firewall/fqdn-filtering-network-rules                                                                                                 |
| Registrere Azure-resource provider                   | https://learn.microsoft.com/azure/azure-resource-manager/management/resource-providers-and-types                                                                         |
| VNET-peering priser                                   | https://azure.microsoft.com/pricing/details/virtual-network/                                                                                                             |
| GitHub meta-API (dynamiske IP-oppdateringer)          | https://docs.github.com/en/rest/meta/meta                                                                                                                                |
| DNS i hub-spoke med Private Link                      | https://learn.microsoft.com/azure/architecture/networking/architecture/private-link-virtual-wan-dns-guide                                                                 |
