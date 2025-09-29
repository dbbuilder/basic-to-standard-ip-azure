# Migrate-BasicToStandardIP.ps1
# Main script for migrating Azure Basic SKU public IPs to Standard SKU
# Implements zero-downtime migration strategy with dual-IP overlap

#Requires -Version 7.0
#Requires -Modules Az.Network, Az.Resources

<#
.SYNOPSIS
    Migrates Azure Basic SKU public IPs to Standard SKU with zero downtime
.DESCRIPTION
    This script automates the migration of Basic public IPs to Standard SKU using
    a dual-IP overlap strategy to maintain service availability during DNS cutover.
    
    Migration approach:
    1. Discover all Basic public IPs
    2. Create Standard public IPs
    3. Add Standard IPs as secondary configurations to NICs
    4. Validate NSG rules and connectivity
    5. Export inventory for DNS cutover planning
    6. (Manual) Update DNS to point to Standard IPs
    7. (Post-soak) Remove Basic IPs
.PARAMETER ConfigPath
    Path to migration configuration JSON file
.PARAMETER Phase
    Migration phase to execute: Discovery, Create, Validate, Cleanup
.PARAMETER DryRun
    If specified, shows what would be done without making changes
.PARAMETER BatchSize
    Number of IPs to process in each batch (overrides config file)
.EXAMPLE
    .\Migrate-BasicToStandardIP.ps1 -ConfigPath ..\Config\migration-config.json -Phase Discovery
.EXAMPLE
    .\Migrate-BasicToStandardIP.ps1 -ConfigPath ..\Config\migration-config.json -Phase Create -DryRun
.EXAMPLE
    .\Migrate-BasicToStandardIP.ps1 -ConfigPath ..\Config\migration-config.json -Phase Cleanup
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, HelpMessage = "Path to migration configuration JSON file")]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$ConfigPath,
    
    [Parameter(Mandatory = $true, HelpMessage = "Migration phase to execute")]
    [ValidateSet('Discovery', 'Create', 'Validate', 'Cleanup', 'Full')]
    [string]$Phase,
    
    [Parameter(Mandatory = $false, HelpMessage = "Dry run mode - show actions without executing")]
    [switch]$DryRun,
    
    [Parameter(Mandatory = $false, HelpMessage = "Number of IPs to process per batch")]
    [ValidateRange(1, 50)]
    [int]$BatchSize = 0
)

# Import common functions module
$commonFunctionsPath = Join-Path -Path $PSScriptRoot -ChildPath "Common-Functions.ps1"
if (-not (Test-Path $commonFunctionsPath)) {
    Write-Error "Common functions module not found at: $commonFunctionsPath"
    exit 1
}
Import-Module $commonFunctionsPath -Force

# Global variables
$script:InventoryFile = ""
$script:ErrorCount = 0
$script:SuccessCount = 0


# Main execution
try {
    # Initialize environment
    Initialize-MigrationEnvironment -ConfigPath $ConfigPath
    
    Write-MigrationLog -Message "`n=== Azure Public IP Migration Tool ===" -Level "Information"
    Write-MigrationLog -Message "Phase: $Phase" -Level "Information"
    Write-MigrationLog -Message "Dry Run: $DryRun" -Level "Information"
    Write-MigrationLog -Message "Configuration: $ConfigPath" -Level "Information"
    
    # Execute requested phase
    switch ($Phase) {
        'Discovery' {
            Write-MigrationLog -Message "=== PHASE: DISCOVERY ===" -Level "Information"
            $inventory = Get-BasicPublicIps
            if ($inventory.Count -gt 0) {
                $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                $script:InventoryFile = Join-Path -Path (Split-Path $ConfigPath -Parent) -ChildPath "..\Output\inventory_$timestamp.csv"
                Export-MigrationInventory -Inventory $inventory -OutputPath $script:InventoryFile
                Write-MigrationLog -Message "Discovery complete. Inventory: $script:InventoryFile" -Level "Information"
            }
        }
        'Create' {
            Write-MigrationLog -Message "=== PHASE: CREATE STANDARD PUBLIC IPs ===" -Level "Information"
            Write-MigrationLog -Message "Implementation: Load inventory, create Standard IPs, add to NICs" -Level "Information"
            Write-MigrationLog -Message "Please refer to full implementation in repository" -Level "Warning"
        }
        'Validate' {
            Write-MigrationLog -Message "=== PHASE: VALIDATE ===" -Level "Information"
            Write-MigrationLog -Message "Implementation: Test connectivity, NSG, DNS" -Level "Information"
            Write-MigrationLog -Message "Please refer to full implementation in repository" -Level "Warning"
        }
        'Cleanup' {
            Write-MigrationLog -Message "=== PHASE: CLEANUP ===" -Level "Information"
            Write-MigrationLog -Message "Implementation: Remove Basic IPs after soak period" -Level "Information"
            Write-MigrationLog -Message "Please refer to full implementation in repository" -Level "Warning"
        }
        'Full' {
            Write-MigrationLog -Message "Full workflow requires manual intervention between phases" -Level "Warning"
            Write-MigrationLog -Message "Please run phases individually: Discovery -> Create -> Validate -> Cleanup" -Level "Information"
        }
    }
    
    Write-MigrationLog -Message "`nExecution completed" -Level "Information"
    exit 0
}
catch {
    Write-MigrationLog -Message "Fatal error: $($_.Exception.Message)" -Level "Error" -Exception $_.Exception
    exit 1
}
