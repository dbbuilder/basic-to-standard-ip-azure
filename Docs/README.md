# Azure Public IP Migration Tool - Complete Documentation

## Table of Contents
1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Installation](#installation)
4. [Configuration](#configuration)
5. [Usage](#usage)
6. [Migration Phases](#migration-phases)
7. [Special Cases](#special-cases)
8. [Troubleshooting](#troubleshooting)
9. [Best Practices](#best-practices)

## Overview

This tool automates the migration of Azure Basic SKU Public IPs to Standard SKU before the **September 30, 2025** retirement deadline. It implements a zero-downtime dual-IP overlap strategy to ensure continuous service availability.

### Key Features
- **Zero-downtime migration** using dual-IP overlap
- **Automated discovery** of all Basic SKU public IPs
- **Batch processing** with configurable delays
- **Comprehensive validation** (connectivity, DNS, NSG)
- **Rollback capability** for safety
- **Detailed logging and reporting**
- **Dry run mode** for testing

### Migration Strategy

The tool uses a **dual-IP overlap** approach:

1. **Create Phase**: Standard IPs added as secondary configs (Basic IP stays active)
2. **Validate Phase**: Test connectivity, NSG rules, DNS
3. **DNS Cutover**: Update DNS to Standard IP (manual step)
4. **Soak Period**: Monitor for 48 hours with both IPs active
5. **Cleanup Phase**: Remove Basic IP after successful validation

This ensures that:
- No service interruption occurs
- Traffic can be quickly reverted if issues arise
- DNS propagation happens gradually
- Monitoring can detect issues before committing

## Prerequisites

### Software Requirements

1. **PowerShell 7.0 or higher**
   ```powershell
   # Check version
   $PSVersionTable.PSVersion
   
   # Install if needed
   winget install Microsoft.PowerShell
   ```

2. **Azure CLI 2.60.0 or higher**
   ```powershell
   # Check version
   az --version
   
   # Install if needed
   winget install Microsoft.AzureCLI
   ```

3. **PowerShell Az Modules**
   ```powershell
   # Install required modules
   Install-Module -Name Az.Network -Scope CurrentUser -Force
   Install-Module -Name Az.Resources -Scope CurrentUser -Force
   Install-Module -Name Az.Accounts -Scope CurrentUser -Force
   ```

### Azure Permissions

Minimum required permissions:
- **Network Contributor** on resource groups containing public IPs
- **Reader** on subscription (for discovery)
- **DNS Zone Contributor** (if using Azure DNS automation)

### Network Requirements
- Outbound internet access to Azure management endpoints
- Azure CLI and PowerShell authentication configured

## Installation

### From GitHub

```powershell
# Clone repository
git clone https://github.com/dbbuilder/basic-to-standard-ip-azure.git
cd basic-to-standard-ip-azure

# Verify structure
Get-ChildItem -Recurse
```

### From Local Copy

```powershell
# Copy to desired location
Copy-Item -Path "D:\dev2\basic-to-standard-ip-azure" -Destination "C:\AzureIPMigration" -Recurse

# Navigate to directory
cd C:\AzureIPMigration
```

## Configuration

### Edit Configuration File

1. Open `Config\migration-config.json`
2. Update the following settings:

```json
{
  "subscriptionId": "YOUR-SUBSCRIPTION-ID",
  "subscriptionName": "YOUR-SUBSCRIPTION-NAME",
  "migration": {
    "batchSize": 5,                    // IPs per batch
    "delayBetweenBatchesMinutes": 30,  // Wait between batches
    "soakPeriodHours": 48,             // Monitoring period
    "useZones": false,                 // Availability zones
    "zones": []                        // e.g., ["1","2","3"]
  }
}
```

### Key Configuration Options

| Setting | Description | Default | Recommendation |
|---------|-------------|---------|----------------|
| `batchSize` | IPs processed per batch | 5 | Start with 5, increase after success |
| `soakPeriodHours` | Monitoring before cleanup | 48 | Minimum 48 hours recommended |
| `delayBetweenBatchesMinutes` | Wait between batches | 30 | Adjust based on team capacity |
| `useZones` | Enable availability zones | false | Set true for production workloads |
| `dnsTtlSeconds` | DNS TTL for cutover | 120 | Lower for faster propagation |

## Usage

### Authentication

Before running any commands, authenticate to Azure:

```powershell
# Azure CLI
az login
az account set --subscription "YOUR-SUBSCRIPTION-ID"

# PowerShell
Connect-AzAccount
Set-AzContext -SubscriptionId "YOUR-SUBSCRIPTION-ID"
```

### Basic Workflow

```powershell
cd Scripts

# 1. Discover all Basic public IPs
.\Migrate-BasicToStandardIP.ps1 `
    -ConfigPath ..\Config\migration-config.json `
    -Phase Discovery

# 2. Review inventory
cd ..\Output
notepad inventory_*.csv

# 3. Create Standard IPs (DRY RUN first!)
cd ..\Scripts
.\Migrate-BasicToStandardIP.ps1 `
    -ConfigPath ..\Config\migration-config.json `
    -Phase Create `
    -DryRun

# 4. Create Standard IPs (actual)
.\Migrate-BasicToStandardIP.ps1 `
    -ConfigPath ..\Config\migration-config.json `
    -Phase Create

# 5. Validate migration
.\Migrate-BasicToStandardIP.ps1 `
    -ConfigPath ..\Config\migration-config.json `
    -Phase Validate

# 6. Update DNS manually (use inventory CSV for IP mapping)

# 7. Wait for soak period (48 hours)

# 8. Cleanup Basic IPs
.\Migrate-BasicToStandardIP.ps1 `
    -ConfigPath ..\Config\migration-config.json `
    -Phase Cleanup
```

## Migration Phases

### Phase 1: Discovery

**Purpose**: Identify all Basic SKU public IPs in the subscription

**Command**:
```powershell
.\Migrate-BasicToStandardIP.ps1 -ConfigPath ..\Config\migration-config.json -Phase Discovery
```

**Output**:
- `Output\inventory_TIMESTAMP.csv` - Complete inventory with:
  - IP names, addresses, resource groups, locations
  - Consumer types (NIC, Load Balancer, VPN Gateway, etc.)
  - DNS information
  - Migration status

**What to Review**:
- Total count of Basic IPs
- Consumer types distribution
- Special cases (Load Balancers, VPN Gateways)
- DNS configuration

### Phase 2: Create

**Purpose**: Create Standard SKU public IPs and add as secondary configurations

**Command**:
```powershell
# Always dry run first!
.\Migrate-BasicToStandardIP.ps1 -ConfigPath ..\Config\migration-config.json -Phase Create -DryRun

# Then actual creation
.\Migrate-BasicToStandardIP.ps1 -ConfigPath ..\Config\migration-config.json -Phase Create
```

**Actions Performed**:
1. Creates Standard SKU public IP for each Basic IP
2. Adds Standard IP as secondary configuration on NICs
3. Validates NSG rules exist
4. Updates inventory with Standard IP details

**Duration**: ~5-10 minutes per IP (including delays)

**Output**:
- Standard public IPs created
- Secondary IP configs on NICs
- Updated inventory CSV
- Detailed logs in `Logs\` directory

### Phase 3: Validate

**Purpose**: Verify Standard IPs are accessible and configured correctly

**Command**:
```powershell
.\Migrate-BasicToStandardIP.ps1 -ConfigPath ..\Config\migration-config.json -Phase Validate
```

**Tests Performed**:
- ICMP ping to Standard IP
- TCP port connectivity (80, 443)
- NSG rule validation
- DNS resolution checks

**Output**:
- `Output\validation_report_TIMESTAMP.csv`
- Pass/fail status for each IP
- Connectivity test results

### Phase 4: DNS Cutover (Manual)

**Purpose**: Update DNS records to point to Standard IPs

**Process**:
1. Review `inventory_TIMESTAMP.csv` for IP mappings
2. Lower DNS TTL to 60-120 seconds (48 hours before cutover)
3. Update A records to Standard IP addresses
4. Monitor DNS propagation
5. Verify traffic flows through Standard IPs

**Tools**:
- Name.com web interface
- Azure DNS (if applicable)
- `nslookup` / `Resolve-DnsName` for verification

### Phase 5: Soak Period

**Purpose**: Monitor services for 48 hours before cleanup

**Actions**:
- Monitor application logs for errors
- Check Azure Monitor metrics
- Verify traffic patterns
- Ensure no alerts triggered

**Duration**: 48 hours (configurable)

### Phase 6: Cleanup

**Purpose**: Remove Basic public IPs after successful migration

**Command**:
```powershell
.\Migrate-BasicToStandardIP.ps1 -ConfigPath ..\Config\migration-config.json -Phase Cleanup
```

**Safety Checks**:
- Validates soak period has elapsed
- Requires confirmation (type 'DELETE')
- Removes IP configs from NICs first
- Deletes Basic IP resources

**Output**:
- Basic IPs removed
- Final inventory status: "completed"

## Special Cases

### Load Balancers

**Issue**: Basic Load Balancers cannot use Standard public IPs

**Solution**:
1. Identified during Discovery phase
2. Upgrade Load Balancer to Standard first
3. Follow Microsoft's LB upgrade guide
4. Then migrate public IPs

**Reference**: https://learn.microsoft.com/azure/load-balancer/upgrade-basic-standard

### VPN Gateways

**Issue**: VPN Gateways require specific migration process

**Solution**:
1. Identified during Discovery phase
2. Follow VPN Gateway migration to AZ SKUs
3. Requires maintenance window
4. Reconfigure tunnels after migration

**Reference**: https://learn.microsoft.com/azure/vpn-gateway/vpn-gateway-about-vpn-gateway-settings

### Application Gateways

**Issue**: Application Gateways have specific requirements

**Solution**:
1. Review Azure documentation for App Gateway migration
2. May require recreation in some scenarios
3. Contact Azure support if uncertain

## Troubleshooting

### Common Issues

#### Issue 1: "Azure CLI not found"
**Solution**:
```powershell
winget install Microsoft.AzureCLI
# Restart PowerShell
az --version
```

#### Issue 2: "PowerShell module not found"
**Solution**:
```powershell
Install-Module -Name Az.Network -Scope CurrentUser -Force
Import-Module Az.Network
```

#### Issue 3: "Unauthorized" or "Forbidden" errors
**Solution**:
```powershell
# Re-authenticate
az login
Connect-AzAccount

# Verify permissions
az role assignment list --assignee YOUR_USER_ID
```

#### Issue 4: "Standard IP creation fails"
**Possible Causes**:
- Quota exceeded in region
- Invalid configuration
- Name already in use

**Solution**:
```powershell
# Check quotas
az network list-usages --location eastus --output table

# Review error in logs
Get-Content ..\Logs\migration_*.log | Select-String "ERROR"
```

#### Issue 5: "NSG validation fails"
**Solution**:
- Standard IPs require explicit NSG allow rules
- Check NSG attached to NIC or subnet
- Add required inbound rules for your services

```powershell
# View NSG rules
az network nsg rule list --resource-group YOUR_RG --nsg-name YOUR_NSG --output table
```

### Log Analysis

View detailed logs:
```powershell
# Latest log
Get-Content ..\Logs\migration_*.log -Tail 100

# Search for errors
Select-String -Path ..\Logs\migration_*.log -Pattern "ERROR"

# Filter by IP name
Select-String -Path ..\Logs\migration_*.log -Pattern "AppArizona-ip"
```

## Best Practices

### Planning
1. **Start Small**: Begin with 1-2 test IPs in non-production
2. **Use Dry Run**: Always test with `-DryRun` first
3. **Schedule Wisely**: Run during low-traffic periods
4. **Communicate**: Inform stakeholders of migration schedule

### Execution
1. **Batch Sizing**: Start with small batches (5 IPs), increase after success
2. **DNS Preparation**: Lower TTL 48 hours before cutover
3. **Monitoring**: Set up alerts for error rates and availability
4. **Documentation**: Keep notes of each migration batch

### Safety
1. **Backup Plans**: Have rollback procedure documented and tested
2. **Validation**: Thoroughly test Standard IPs before DNS cutover
3. **Soak Period**: Don't skip the monitoring period
4. **Logs**: Retain logs for audit trail

### Post-Migration
1. **Verify**: Confirm all Basic IPs removed
2. **Document**: Record lessons learned
3. **Update**: Update runbooks and documentation
4. **Cleanup**: Remove temporary resources

## Support and Resources

### Microsoft Resources
- [Basic IP Retirement](https://azure.microsoft.com/updates/upgrade-to-standard-sku-public-ip-addresses-in-azure-by-30-september-2025-basic-sku-will-be-retired/)
- [Migration Guidance](https://learn.microsoft.com/azure/virtual-network/ip-services/public-ip-basic-upgrade-guidance)
- [Public IP Documentation](https://learn.microsoft.com/azure/virtual-network/ip-services/public-ip-addresses)

### Project Resources
- **GitHub**: https://github.com/dbbuilder/basic-to-standard-ip-azure
- **Issues**: https://github.com/dbbuilder/basic-to-standard-ip-azure/issues
- **Documentation**: See `Docs\` directory

### Getting Help
1. Review logs in `Logs\` directory
2. Check validation reports in `Output\` directory
3. Consult TODO.md for known issues
4. Open GitHub issue with:
   - Error message
   - Relevant log excerpts
   - Configuration (sanitized)
   - Steps to reproduce

## License

This tool is provided as-is for Azure public IP migration purposes.

---
**Last Updated**: 2025-09-29
**Version**: 1.0.0
**Repository**: https://github.com/dbbuilder/basic-to-standard-ip-azure
