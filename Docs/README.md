# Azure Public IP Migration Tool - Complete Documentation

## Overview
Comprehensive PowerShell and Azure CLI solution for migrating Azure Basic SKU Public IPs to Standard SKU with zero downtime before the September 30, 2025 retirement deadline.

## Table of Contents
1. [Quick Start](#quick-start)
2. [Prerequisites](#prerequisites)
3. [Installation](#installation)
4. [Configuration](#configuration)
5. [Usage](#usage)
6. [Migration Phases](#migration-phases)
7. [Special Cases](#special-cases)
8. [Troubleshooting](#troubleshooting)
9. [Best Practices](#best-practices)

## Quick Start

```powershell
# 1. Install prerequisites
Install-Module -Name Az.Network, Az.Resources, Az.Accounts -Scope CurrentUser

# 2. Login to Azure
az login
Connect-AzAccount

# 3. Configure
# Edit Config\migration-config.json with your subscription details

# 4. Discover Basic IPs
cd Scripts
.\Migrate-BasicToStandardIP.ps1 -ConfigPath ..\Config\migration-config.json -Phase Discovery

# 5. Create Standard IPs (dry run first)
.\Migrate-BasicToStandardIP.ps1 -ConfigPath ..\Config\migration-config.json -Phase Create -DryRun

# 6. Create Standard IPs
.\Migrate-BasicToStandardIP.ps1 -ConfigPath ..\Config\migration-config.json -Phase Create

# 7. Validate
.\Migrate-BasicToStandardIP.ps1 -ConfigPath ..\Config\migration-config.json -Phase Validate

# 8. Update DNS (manual - use exported CSV)

# 9. Wait 48 hours (soak period)

# 10. Cleanup
.\Migrate-BasicToStandardIP.ps1 -ConfigPath ..\Config\migration-config.json -Phase Cleanup
```

## Prerequisites

### Software Requirements
- **PowerShell 7.0+** - [Download](https://github.com/PowerShell/PowerShell/releases)
- **Azure CLI 2.60+** - [Download](https://docs.microsoft.com/cli/azure/install-azure-cli)
- **PowerShell Modules**:
  - Az.Network
  - Az.Resources
  - Az.Accounts

### Azure Permissions
- Network Contributor on resource groups
- Reader on subscription
- DNS Zone Contributor (if using Azure DNS automation)

### Installation

```powershell
# Install PowerShell 7 (Windows)
winget install Microsoft.PowerShell

# Install Azure CLI (Windows)
winget install Microsoft.AzureCLI

# Install Azure PowerShell modules
Install-Module -Name Az.Network -Scope CurrentUser -Force
Install-Module -Name Az.Resources -Scope CurrentUser -Force
Install-Module -Name Az.Accounts -Scope CurrentUser -Force

# Verify installations
pwsh --version
az --version
Get-Module -ListAvailable Az.*
```

## Configuration

Edit `Config\migration-config.json`:

```json
{
  "subscriptionId": "YOUR-SUBSCRIPTION-ID",
  "migration": {
    "soakPeriodHours": 48,
    "batchSize": 5,
    "delayBetweenBatchesMinutes": 30
  }
}
```

## Usage

### Authentication
```powershell
# Azure CLI
az login
az account set --subscription "YOUR-SUBSCRIPTION-ID"

# PowerShell
Connect-AzAccount
Set-AzContext -SubscriptionId "YOUR-SUBSCRIPTION-ID"
```

### Discovery Phase
Discover all Basic SKU public IPs:
```powershell
.\Migrate-BasicToStandardIP.ps1 -ConfigPath ..\Config\migration-config.json -Phase Discovery
```

**Output**: `Output\inventory_TIMESTAMP.csv`

### Create Phase
Create Standard IPs and add as secondary configurations:
```powershell
# Dry run first
.\Migrate-BasicToStandardIP.ps1 -ConfigPath ..\Config\migration-config.json -Phase Create -DryRun

# Actual creation
.\Migrate-BasicToStandardIP.ps1 -ConfigPath ..\Config\migration-config.json -Phase Create
```

### Validate Phase
Test connectivity and configuration:
```powershell
.\Migrate-BasicToStandardIP.ps1 -ConfigPath ..\Config\migration-config.json -Phase Validate
```

### DNS Update (Manual)
1. Review `Output\inventory_TIMESTAMP.csv`
2. Update DNS A records to Standard IP addresses
3. Set TTL to 60-120 seconds
4. Monitor DNS propagation

### Cleanup Phase
Remove Basic IPs after soak period:
```powershell
.\Migrate-BasicToStandardIP.ps1 -ConfigPath ..\Config\migration-config.json -Phase Cleanup
```

## Migration Strategy

### Dual-IP Overlap
1. **Create**: Standard IP added as secondary (Basic stays active)
2. **Validate**: Test new IP
3. **DNS Cutover**: Update DNS to Standard IP
4. **Soak**: Monitor both IPs for 48 hours
5. **Cleanup**: Remove Basic IP

### Why This Approach?
- Zero downtime - traffic continues on Basic IP during cutover
- Safe rollback - can revert DNS if issues occur
- Gradual transition - DNS propagation happens naturally
- No hard cutover - no connection resets

## Special Cases

### Load Balancers
Basic Load Balancers must be upgraded separately:
1. Use Microsoft's LB upgrade scripts
2. Create Standard LB
3. Migrate backend pool
4. Attach Standard public IP
5. Delete Basic LB

**Reference**: [Azure LB Upgrade Guide](https://learn.microsoft.com/azure/load-balancer/upgrade-basic-standard)

### VPN Gateways
VPN Gateways require gateway migration:
1. Plan maintenance window
2. Migrate to AZ SKU
3. Reconfigure tunnels
4. Attach Standard public IP

**Reference**: [VPN Gateway Migration](https://learn.microsoft.com/azure/vpn-gateway/vpn-gateway-about-vpn-gateway-settings)

### Application Gateways
Application Gateways handle migration internally during updates. Consult Azure support.

## Troubleshooting

### Common Issues

**Issue**: "Azure CLI not found"
```powershell
# Solution
winget install Microsoft.AzureCLI
az --version
```

**Issue**: "PowerShell module not found"
```powershell
# Solution
Install-Module -Name Az.Network -Scope CurrentUser -Force
Import-Module Az.Network
```

**Issue**: "Unauthorized" errors
```powershell
# Solution
az login
Connect-AzAccount
# Verify permissions
az role assignment list --assignee YOUR_USER_ID
```

**Issue**: Standard IP creation fails
- Check Azure quotas
- Verify region supports Standard SKU
- Review error in logs

**Issue**: NSG validation fails
- Standard IPs require explicit NSG allow rules
- Check NSG on NIC or subnet
- Add inbound rules for required ports

### Log Analysis
```powershell
# View latest log
Get-Content .\Logs\migration_*.log -Tail 100

# Search for errors
Select-String -Path .\Logs\migration_*.log -Pattern "ERROR"

# Filter by IP name
Select-String -Path .\Logs\migration_*.log -Pattern "AppArizona-ip"
```

## Best Practices

1. **Always Test with Dry Run**
   - Run with `-DryRun` flag first
   - Verify expected actions

2. **Start Small**
   - Begin with low-risk IPs
   - Test rollback procedures
   - Build confidence before large-scale migration

3. **DNS Preparation**
   - Lower TTL 48 hours before migration
   - Plan cutover during low-traffic periods
   - Have rollback plan ready

4. **Monitor During Soak**
   - Use Azure Monitor for metrics
   - Check application logs
   - Verify no error rate increase
   - Test from multiple locations

5. **Document Everything**
   - Keep inventory CSV files
   - Save validation reports
   - Archive logs
   - Note any manual interventions

6. **Have Rollback Plan**
   - Test rollback script before production
   - Know how to revert DNS quickly
   - Have contact list for escalation
   - Schedule migrations during support hours

## Security Considerations

1. **Authentication**
   - Use Azure AD authentication
   - Enable MFA
   - Rotate credentials regularly

2. **Permissions**
   - Follow least privilege principle
   - Use RBAC effectively
   - Audit permission changes

3. **Network Security**
   - Standard IPs deny by default
   - Configure NSG rules before cutover
   - Use service tags where possible
   - Enable DDoS Protection Standard

4. **Logging**
   - Enable Azure Activity Log
   - Configure log retention (90 days minimum)
   - Export logs to SIEM if available
   - Review logs regularly

## Output Files

### Inventory CSV
**Location**: `Output\inventory_TIMESTAMP.csv`

**Fields**: Name, ResourceGroup, Location, IpAddress, StandardIpAddress, ConsumerType, MigrationStatus, Notes

### Validation Report
**Location**: `Output\validation_report_TIMESTAMP.csv`

**Fields**: Name, StandardIpAddress, ConnectivityTest, NsgValidation, DnsResolution, OverallStatus

### Log Files
**Location**: `Logs\migration_TIMESTAMP.log`

All operations with timestamps, error details, execution summary

## Support Resources

### Microsoft Resources
- [Basic IP Retirement Announcement](https://azure.microsoft.com/updates/upgrade-to-standard-sku-public-ip-addresses-in-azure-by-30-september-2025-basic-sku-will-be-retired/)
- [Migration Guide](https://learn.microsoft.com/azure/virtual-network/ip-services/public-ip-basic-upgrade-guidance)
- [Load Balancer Upgrade](https://learn.microsoft.com/azure/load-balancer/upgrade-basic-standard)
- [Standard IP Documentation](https://learn.microsoft.com/azure/virtual-network/ip-services/public-ip-addresses)

### Project Documentation
- **REQUIREMENTS.md** - Technical requirements specification
- **TODO.md** - Implementation roadmap and tasks
- **FUTURE.md** - Future enhancements and vision

## License
This tool is provided as-is for Azure public IP migration purposes.

## Changelog

### Version 1.0.0 (2025-09-29)
- Initial release
- Discovery, Create, Validate, Cleanup phases (stubs)
- Rollback capability
- Dry run mode
- Comprehensive logging and error handling
- Common functions library complete
- Configuration system
- Documentation suite

## Contributors
Ted (School Vision) - Project Lead

---

For issues or questions, review logs and documentation. For Azure-specific questions, consult Microsoft documentation links above.
