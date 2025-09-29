# Azure Basic to Standard Public IP Migration Tool

Automated PowerShell solution for migrating Azure Basic SKU Public IPs to Standard SKU with zero downtime before the **September 30, 2025** retirement deadline.

## Quick Start

### Prerequisites
- PowerShell 7.0+
- Azure CLI 2.60+
- Az PowerShell Modules (Az.Network, Az.Resources, Az.Accounts)

### Installation
```powershell
# Install PowerShell modules
Install-Module -Name Az.Network, Az.Resources, Az.Accounts -Scope CurrentUser

# Login to Azure
az login
Connect-AzAccount
```

### Usage

```powershell
cd Scripts

# 1. Discovery
.\Migrate-BasicToStandardIP.ps1 -ConfigPath ..\Config\migration-config.json -Phase Discovery

# 2. Create Standard IPs (dry run first!)
.\Migrate-BasicToStandardIP.ps1 -ConfigPath ..\Config\migration-config.json -Phase Create -DryRun

# 3. Create Standard IPs (actual)
.\Migrate-BasicToStandardIP.ps1 -ConfigPath ..\Config\migration-config.json -Phase Create

# 4. Validate
.\Migrate-BasicToStandardIP.ps1 -ConfigPath ..\Config\migration-config.json -Phase Validate

# 5. Update DNS manually (use exported CSV for IP mapping)

# 6. Cleanup after soak period (48 hours)
.\Migrate-BasicToStandardIP.ps1 -ConfigPath ..\Config\migration-config.json -Phase Cleanup
```

## Features

- **Zero-downtime migration** with dual-IP overlap
- **Automated discovery** of all Basic public IPs  
- **Batch processing** with configurable delays
- **Comprehensive validation** (connectivity, DNS, NSG)
- **Rollback capability** for safety
- **Detailed logging** and reporting

## Project Structure

```
basic-to-standard-ip-azure/
├── Config/
│   └── migration-config.json       # Configuration file
├── Scripts/
│   ├── Common-Functions.ps1        # Shared functions
│   ├── Migrate-BasicToStandardIP.ps1 # Main migration script  
│   ├── Validate-Migration.ps1      # Validation script
│   └── Rollback-Migration.ps1      # Rollback script
├── Docs/
│   ├── README.md                   # Full documentation
│   ├── REQUIREMENTS.md             # Requirements specification
│   ├── TODO.md                     # Implementation roadmap
│   └── FUTURE.md                   # Future enhancements
├── Logs/                           # Log files (auto-generated)
└── Output/                         # Inventory and reports (auto-generated)
```

## Migration Strategy

The tool uses a **dual-IP overlap** strategy:

1. **Create**: Standard IPs added as secondary configs (Basic IP stays active)
2. **Validate**: Test connectivity and NSG rules
3. **DNS Cutover**: Update DNS to Standard IP (manual step)
4. **Soak Period**: Monitor for 48 hours with both IPs active
5. **Cleanup**: Remove Basic IP after successful validation

## Special Cases

- **Load Balancers**: Require manual LB upgrade first
- **VPN Gateways**: Require gateway migration to AZ SKUs
- **Application Gateways**: Contact support for guidance

## Documentation

Full documentation available in Docs/ directory:
- [README.md](Docs/README.md) - Complete user guide
- [REQUIREMENTS.md](Docs/REQUIREMENTS.md) - Technical requirements
- [TODO.md](Docs/TODO.md) - Implementation plan
- [FUTURE.md](Docs/FUTURE.md) - Future enhancements

## Support

For Microsoft resources and guidance:
- [Basic IP Retirement Announcement](https://azure.microsoft.com/updates/upgrade-to-standard-sku-public-ip-addresses-in-azure-by-30-september-2025-basic-sku-will-be-retired/)
- [Migration Guide](https://learn.microsoft.com/azure/virtual-network/ip-services/public-ip-basic-upgrade-guidance)

## License

This tool is provided as-is for Azure public IP migration purposes.
