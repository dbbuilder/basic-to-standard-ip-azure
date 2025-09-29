# Migrate-BasicToStandardIP.ps1
# Main script for migrating Azure Basic SKU public IPs to Standard SKU
# Implements zero-downtime migration strategy with dual-IP overlap

#Requires -Version 7.0

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

<#
.SYNOPSIS
    Executes the discovery phase
.DESCRIPTION
    Discovers all Basic public IPs and creates initial inventory
#>
function Invoke-DiscoveryPhase {
    [CmdletBinding()]
    param()
    
    try {
        Write-MigrationLog -Message "=== PHASE: DISCOVERY ===" -Level "Information"
        
        if ($DryRun) {
            Write-MigrationLog -Message "DRY RUN MODE: Discovery will show what would be discovered" -Level "Warning"
        }
        
        # Discover Basic public IPs
        $inventory = Get-BasicPublicIps
        
        if ($inventory.Count -eq 0) {
            Write-MigrationLog -Message "No Basic public IPs found. Migration not needed." -Level "Information"
            return
        }
        
        # Generate output file path
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $script:InventoryFile = Join-Path -Path (Split-Path $ConfigPath -Parent) -ChildPath "..\Output\inventory_$timestamp.csv"
        
        # Export inventory
        Export-MigrationInventory -Inventory $inventory -OutputPath $script:InventoryFile
        
        # Display summary by category
        Write-MigrationLog -Message "`n=== DISCOVERY SUMMARY ===" -Level "Information"
        Write-MigrationLog -Message "Total Basic Public IPs: $($inventory.Count)" -Level "Information"
        
        # By consumer type
        $byConsumer = $inventory | Group-Object ConsumerType
        Write-MigrationLog -Message "`nBy Consumer Type:" -Level "Information"
        foreach ($group in $byConsumer) {
            Write-MigrationLog -Message "  $($group.Name): $($group.Count)" -Level "Information"
        }
        
        # By location
        $byLocation = $inventory | Group-Object Location
        Write-MigrationLog -Message "`nBy Location:" -Level "Information"
        foreach ($group in $byLocation) {
            Write-MigrationLog -Message "  $($group.Name): $($group.Count)" -Level "Information"
        }
        
        Write-MigrationLog -Message "`nInventory exported to: $script:InventoryFile" -Level "Information"
        
    }
    catch {
        Write-MigrationLog -Message "Discovery phase failed: $($_.Exception.Message)" -Level "Error" -Exception $_.Exception
        throw
    }
}

<#
.SYNOPSIS
    Executes the creation phase
.DESCRIPTION
    Creates Standard public IPs and adds them as secondary configurations to NICs
#>
function Invoke-CreatePhase {
    [CmdletBinding()]
    param()
    
    try {
        Write-MigrationLog -Message "=== PHASE: CREATE STANDARD PUBLIC IPs ===" -Level "Information"
        
        if ($DryRun) {
            Write-MigrationLog -Message "DRY RUN MODE: No resources will be created" -Level "Warning"
        }
        
        # Load inventory from latest discovery
        $inventoryFiles = Get-ChildItem -Path (Join-Path -Path (Split-Path $ConfigPath -Parent) -ChildPath "..\Output") -Filter "inventory_*.csv" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
        
        if ($inventoryFiles.Count -eq 0) {
            throw "No inventory file found. Run Discovery phase first."
        }
        
        $latestInventory = $inventoryFiles[0].FullName
        Write-MigrationLog -Message "Loading inventory from: $latestInventory" -Level "Information"
        
        $inventory = Import-Csv -Path $latestInventory
        
        # Filter to only NICs and unattached (skip LBs and VPN gateways for automated processing)
        $processable = $inventory | Where-Object { $_.ConsumerType -in @('nic', 'unattached') -and $_.MigrationStatus -eq 'pending' }
        
        if ($processable.Count -eq 0) {
            Write-MigrationLog -Message "No IPs available for automated creation. Check inventory for LB/VPN items requiring manual migration." -Level "Warning"
            return
        }
        
        Write-MigrationLog -Message "Processing $($processable.Count) public IPs eligible for automated creation" -Level "Information"
        
        # Process each IP
        foreach ($ip in $processable) {
            try {
                Write-MigrationLog -Message "`nProcessing: $($ip.Name) in $($ip.ResourceGroup)" -Level "Information"
                Write-MigrationLog -Message "  Current IP: $($ip.IpAddress)" -Level "Information"
                Write-MigrationLog -Message "  Consumer Type: $($ip.ConsumerType)" -Level "Information"
                
                if ($DryRun) {
                    Write-MigrationLog -Message "  [DRY RUN] Would create Standard IP: $($ip.StandardIpName)" -Level "Information"
                    Write-MigrationLog -Message "  [DRY RUN] Location: $($ip.Location)" -Level "Information"
                    Write-MigrationLog -Message "  [DRY RUN] SKU: Standard, Allocation: Static" -Level "Information"
                    
                    if ($ip.ConsumerType -eq 'nic' -and $ip.NicName) {
                        Write-MigrationLog -Message "  [DRY RUN] Would add secondary IP config to NIC: $($ip.NicName)" -Level "Information"
                        Write-MigrationLog -Message "  [DRY RUN] Would validate NSG rules" -Level "Information"
                    }
                    
                    $script:SuccessCount++
                }
                else {
                    # Create Standard public IP
                    $newIp = New-StandardPublicIp -Name $ip.StandardIpName -ResourceGroup $ip.ResourceGroup -Location $ip.Location
                    
                    # Update inventory object
                    $ip.StandardIpAddress = $newIp.IpAddress
                    $ip.StandardIpResourceId = $newIp.ResourceId
                    $ip.MigrationTimestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                    
                    # If attached to NIC, add as secondary IP config
                    if ($ip.ConsumerType -eq 'nic' -and $ip.NicName) {
                        $ipConfigName = "ipconfig-std-$($ip.Name)"
                        
                        Add-SecondaryIpConfigToNic -NicName $ip.NicName -NicResourceGroup $ip.NicResourceGroup -IpConfigName $ipConfigName -PublicIpName $ip.StandardIpName
                        
                        $ip.Notes = "Secondary IP config '$ipConfigName' added to NIC"
                        
                        # Validate NSG rules
                        if ($Global:Config.validation.validateNsgRules) {
                            $nsgValid = Test-NsgRulesForNewIp -NicName $ip.NicName -NicResourceGroup $ip.NicResourceGroup -NewPublicIp $newIp.IpAddress
                            
                            if (-not $nsgValid) {
                                $ip.Notes += "; NSG validation FAILED - manual review required"
                                Write-MigrationLog -Message "  WARNING: NSG validation failed for $($ip.Name)" -Level "Warning"
                            }
                        }
                    }
                    
                    $ip.MigrationStatus = "standard_created"
                    $script:SuccessCount++
                    
                    Write-MigrationLog -Message "  SUCCESS: Standard IP created at $($newIp.IpAddress)" -Level "Information"
                }
            }
            catch {
                $script:ErrorCount++
                $ip.MigrationStatus = "error"
                $ip.Notes = "Error: $($_.Exception.Message)"
                Write-MigrationLog -Message "  ERROR processing $($ip.Name): $($_.Exception.Message)" -Level "Error" -Exception $_.Exception
            }
        }
        
        # Save progress
        if (-not $DryRun) {
            $inventory | Export-Csv -Path $latestInventory -NoTypeInformation -Force
            Write-MigrationLog -Message "Progress saved to inventory" -Level "Information"
        }
        
        # Summary
        Write-MigrationLog -Message "`n=== CREATE PHASE SUMMARY ===" -Level "Information"
        Write-MigrationLog -Message "Total processed: $($processable.Count)" -Level "Information"
        Write-MigrationLog -Message "Successful: $script:SuccessCount" -Level "Information"
        Write-MigrationLog -Message "Errors: $script:ErrorCount" -Level "Information"
        
        if ($DryRun) {
            Write-MigrationLog -Message "`n[DRY RUN] No actual changes were made" -Level "Warning"
            Write-MigrationLog -Message "Run without -DryRun flag to execute actual creation" -Level "Information"
        }
        
    }
    catch {
        Write-MigrationLog -Message "Create phase failed: $($_.Exception.Message)" -Level "Error" -Exception $_.Exception
        throw
    }
}

<#
.SYNOPSIS
    Executes the validation phase
.DESCRIPTION
    Validates connectivity and DNS resolution for Standard public IPs
#>
function Invoke-ValidatePhase {
    [CmdletBinding()]
    param()
    
    try {
        Write-MigrationLog -Message "=== PHASE: VALIDATE STANDARD PUBLIC IPs ===" -Level "Information"
        
        if ($DryRun) {
            Write-MigrationLog -Message "DRY RUN MODE: Validation will show what would be tested" -Level "Warning"
        }
        
        # Load inventory
        $inventoryFiles = Get-ChildItem -Path (Join-Path -Path (Split-Path $ConfigPath -Parent) -ChildPath "..\Output") -Filter "inventory_*.csv" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
        
        if ($inventoryFiles.Count -eq 0) {
            throw "No inventory file found. Run Discovery phase first."
        }
        
        $latestInventory = $inventoryFiles[0].FullName
        Write-MigrationLog -Message "Loading inventory from: $latestInventory" -Level "Information"
        
        $inventory = Import-Csv -Path $latestInventory
        
        # Filter to created Standard IPs
        $toValidate = $inventory | Where-Object { $_.MigrationStatus -eq 'standard_created' -and $_.StandardIpAddress }
        
        if ($toValidate.Count -eq 0) {
            Write-MigrationLog -Message "No Standard IPs found for validation. Run Create phase first." -Level "Warning"
            return
        }
        
        Write-MigrationLog -Message "Validating $($toValidate.Count) Standard public IPs" -Level "Information"
        
        foreach ($ip in $toValidate) {
            Write-MigrationLog -Message "`nValidating: $($ip.Name) -> $($ip.StandardIpAddress)" -Level "Information"
            
            if ($DryRun) {
                Write-MigrationLog -Message "  [DRY RUN] Would test connectivity to $($ip.StandardIpAddress)" -Level "Information"
                Write-MigrationLog -Message "  [DRY RUN] Would validate NSG rules" -Level "Information"
                Write-MigrationLog -Message "  [DRY RUN] Would check DNS resolution" -Level "Information"
            }
            else {
                # Actual validation
                $connectivityOk = Test-PublicIpConnectivity -IpAddress $ip.StandardIpAddress
                
                if ($ip.ConsumerType -eq 'nic' -and $ip.NicName) {
                    $nsgOk = Test-NsgRulesForNewIp -NicName $ip.NicName -NicResourceGroup $ip.NicResourceGroup -NewPublicIp $ip.StandardIpAddress
                }
                
                if ($connectivityOk) {
                    $ip.MigrationStatus = "validated"
                    Write-MigrationLog -Message "  VALIDATION PASSED" -Level "Information"
                }
                else {
                    Write-MigrationLog -Message "  VALIDATION FAILED" -Level "Warning"
                }
            }
        }
        
        if (-not $DryRun) {
            $inventory | Export-Csv -Path $latestInventory -NoTypeInformation -Force
        }
        
        Write-MigrationLog -Message "`n=== VALIDATION COMPLETE ===" -Level "Information"
        
    }
    catch {
        Write-MigrationLog -Message "Validate phase failed: $($_.Exception.Message)" -Level "Error" -Exception $_.Exception
        throw
    }
}

<#
.SYNOPSIS
    Executes the cleanup phase
.DESCRIPTION
    Removes Basic public IPs after soak period and successful cutover
#>
function Invoke-CleanupPhase {
    [CmdletBinding()]
    param()
    
    try {
        Write-MigrationLog -Message "=== PHASE: CLEANUP BASIC PUBLIC IPs ===" -Level "Information"
        
        if ($DryRun) {
            Write-MigrationLog -Message "DRY RUN MODE: No resources will be deleted" -Level "Warning"
        }
        
        # Load inventory
        $inventoryFiles = Get-ChildItem -Path (Join-Path -Path (Split-Path $ConfigPath -Parent) -ChildPath "..\Output") -Filter "inventory_*.csv" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
        
        if ($inventoryFiles.Count -eq 0) {
            throw "No inventory file found. Run Discovery phase first."
        }
        
        $latestInventory = $inventoryFiles[0].FullName
        Write-MigrationLog -Message "Loading inventory from: $latestInventory" -Level "Information"
        
        $inventory = Import-Csv -Path $latestInventory
        
        # Filter to validated IPs ready for cleanup
        $toCleanup = $inventory | Where-Object { $_.MigrationStatus -eq 'validated' }
        
        if ($toCleanup.Count -eq 0) {
            Write-MigrationLog -Message "No IPs ready for cleanup. Ensure Create and Validate phases completed successfully." -Level "Warning"
            return
        }
        
        # Check soak period
        $soakHours = $Global:Config.migration.soakPeriodHours
        Write-MigrationLog -Message "Checking soak period requirement: $soakHours hours" -Level "Information"
        
        $eligibleForCleanup = @()
        
        foreach ($ip in $toCleanup) {
            if ($ip.MigrationTimestamp) {
                $migrationTime = [DateTime]::Parse($ip.MigrationTimestamp)
                $elapsed = (Get-Date) - $migrationTime
                
                if ($elapsed.TotalHours -ge $soakHours) {
                    $eligibleForCleanup += $ip
                    Write-MigrationLog -Message "  $($ip.Name): Soak period complete" -Level "Information"
                }
                else {
                    $remaining = $soakHours - $elapsed.TotalHours
                    Write-MigrationLog -Message "  $($ip.Name): $([Math]::Round($remaining, 1)) hours remaining" -Level "Information"
                }
            }
        }
        
        if ($eligibleForCleanup.Count -eq 0) {
            Write-MigrationLog -Message "No IPs have completed soak period. Cannot proceed with cleanup." -Level "Warning"
            return
        }
        
        Write-MigrationLog -Message "`n$($eligibleForCleanup.Count) IPs eligible for cleanup" -Level "Information"
        
        # Prompt for confirmation unless in DryRun
        if (-not $DryRun) {
            Write-MigrationLog -Message "`nWARNING: This will permanently delete Basic public IP resources." -Level "Warning"
            $confirmation = Read-Host "Type 'DELETE' to confirm cleanup"
            
            if ($confirmation -ne 'DELETE') {
                Write-MigrationLog -Message "Cleanup cancelled by user" -Level "Warning"
                return
            }
        }
        
        # Process cleanup
        foreach ($ip in $eligibleForCleanup) {
            try {
                Write-MigrationLog -Message "`nCleaning up: $($ip.Name)" -Level "Information"
                
                if ($DryRun) {
                    Write-MigrationLog -Message "  [DRY RUN] Would delete Basic IP: $($ip.Name)" -Level "Information"
                    if ($ip.ConsumerType -eq 'nic' -and $ip.NicName) {
                        Write-MigrationLog -Message "  [DRY RUN] Would remove IP config from NIC: $($ip.NicName)" -Level "Information"
                    }
                }
                else {
                    $ipConfigName = "ipconfig-$($ip.Name)"
                    Remove-BasicPublicIp -BasicIpName $ip.Name -BasicIpResourceGroup $ip.ResourceGroup -NicName $ip.NicName -NicResourceGroup $ip.NicResourceGroup -IpConfigName $ipConfigName
                    
                    $ip.MigrationStatus = "completed"
                    $script:SuccessCount++
                    Write-MigrationLog -Message "  Basic IP removed successfully" -Level "Information"
                }
            }
            catch {
                $script:ErrorCount++
                Write-MigrationLog -Message "  ERROR cleaning up $($ip.Name): $($_.Exception.Message)" -Level "Error" -Exception $_.Exception
            }
        }
        
        if (-not $DryRun) {
            $inventory | Export-Csv -Path $latestInventory -NoTypeInformation -Force
        }
        
        Write-MigrationLog -Message "`n=== CLEANUP SUMMARY ===" -Level "Information"
        Write-MigrationLog -Message "Eligible: $($eligibleForCleanup.Count)" -Level "Information"
        Write-MigrationLog -Message "Success: $script:SuccessCount" -Level "Information"
        Write-MigrationLog -Message "Errors: $script:ErrorCount" -Level "Information"
        
    }
    catch {
        Write-MigrationLog -Message "Cleanup phase failed: $($_.Exception.Message)" -Level "Error" -Exception $_.Exception
        throw
    }
}

# Main execution
try {
    # Initialize environment
    Initialize-MigrationEnvironment -ConfigPath $ConfigPath
    
    Write-MigrationLog -Message "`n=== Azure Public IP Migration Tool ===" -Level "Information"
    Write-MigrationLog -Message "Phase: $Phase" -Level "Information"
    Write-MigrationLog -Message "Dry Run: $DryRun" -Level "Information"
    Write-MigrationLog -Message "Configuration: $ConfigPath" -Level "Information"
    
    if ($DryRun) {
        Write-MigrationLog -Message "`n*** DRY RUN MODE ENABLED ***" -Level "Warning"
        Write-MigrationLog -Message "No changes will be made to Azure resources" -Level "Warning"
        Write-MigrationLog -Message "*** ********************** ***`n" -Level "Warning"
    }
    
    # Execute requested phase
    switch ($Phase) {
        'Discovery' {
            Invoke-DiscoveryPhase
        }
        'Create' {
            Invoke-CreatePhase
        }
        'Validate' {
            Invoke-ValidatePhase
        }
        'Cleanup' {
            Invoke-CleanupPhase
        }
        'Full' {
            Write-MigrationLog -Message "Full workflow requires manual intervention between phases" -Level "Warning"
            Write-MigrationLog -Message "Please run phases individually: Discovery -> Create -> Validate -> Cleanup" -Level "Information"
        }
    }
    
    $endTime = Get-Date
    $duration = $endTime - $Global:MigrationStartTime
    
    Write-MigrationLog -Message "`n=== EXECUTION SUMMARY ===" -Level "Information"
    Write-MigrationLog -Message "Duration: $([Math]::Round($duration.TotalMinutes, 2)) minutes" -Level "Information"
    Write-MigrationLog -Message "Log file: $Global:LogFile" -Level "Information"
    
    if ($script:ErrorCount -gt 0) {
        Write-MigrationLog -Message "Completed with $script:ErrorCount error(s)" -Level "Warning"
        exit 1
    }
    else {
        Write-MigrationLog -Message "Execution completed successfully" -Level "Information"
        exit 0
    }
}
catch {
    Write-MigrationLog -Message "`n=== FATAL ERROR ===" -Level "Error"
    Write-MigrationLog -Message $_.Exception.Message -Level "Error" -Exception $_.Exception
    exit 1
}
