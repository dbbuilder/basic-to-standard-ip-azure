<#
.SYNOPSIS
    Executes the discovery phase with multi-subscription support
.DESCRIPTION
    Discovers all Basic public IPs across configured subscriptions and creates initial inventory
#>
function Invoke-DiscoveryPhase {
    [CmdletBinding()]
    param()
    
    try {
        Write-MigrationLog -Message "=== PHASE: DISCOVERY ===" -Level "Information"
        
        if ($DryRun) {
            Write-MigrationLog -Message "DRY RUN MODE: Discovery will show what would be discovered" -Level "Warning"
        }
        
        # Determine which subscriptions to scan
        if ($Global:Config.scanAllSubscriptions) {
            Write-MigrationLog -Message "Multi-subscription mode enabled" -Level "Information"
            
            # Get list of subscriptions
            $subscriptions = Get-AzureSubscriptions
            
            if ($subscriptions.Count -eq 0) {
                Write-MigrationLog -Message "No subscriptions available for scanning" -Level "Warning"
                return
            }
            
            # Discover Basic public IPs across all subscriptions
            $inventory = Get-BasicPublicIpsMultiSubscription -Subscriptions $subscriptions
        }
        else {
            Write-MigrationLog -Message "Single subscription mode" -Level "Information"
            
            # Use single subscription discovery (original method)
            $inventory = Get-BasicPublicIps
        }
        
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
        
        # By subscription (if multi-sub)
        if ($Global:Config.scanAllSubscriptions) {
            $bySubscription = $inventory | Group-Object SubscriptionName
            Write-MigrationLog -Message "`nBy Subscription:" -Level "Information"
            foreach ($group in $bySubscription) {
                Write-MigrationLog -Message "  $($group.Name): $($group.Count)" -Level "Information"
            }
        }
        
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
