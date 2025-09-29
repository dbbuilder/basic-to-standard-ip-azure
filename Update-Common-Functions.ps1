# Script to complete Common-Functions.ps1 with all remaining functions

$targetFile = "D:\dev2\basic-to-standard-ip-azure\Scripts\Common-Functions.ps1"

# Read current content
$currentContent = Get-Content $targetFile -Raw

# Define all remaining functions as a here-string
$remainingFunctions = @'

<#
.SYNOPSIS
    Discovers all Basic SKU public IPs in the subscription
.DESCRIPTION
    Queries Azure to find all Basic public IPs and their associated resources
.OUTPUTS
    Array of custom objects containing public IP details and associations
#>
function Get-BasicPublicIps {
    [CmdletBinding()]
    param()
    
    try {
        Write-MigrationLog -Message "Discovering Basic SKU public IPs in subscription..." -Level "Information"
        
        # Use Azure CLI for comprehensive query
        $basicIpsJson = az network public-ip list --query "[?sku.name=='Basic']" --output json
        
        if (-not $basicIpsJson) {
            Write-MigrationLog -Message "No Basic SKU public IPs found in subscription" -Level "Warning"
            return @()
        }
        
        $basicIps = $basicIpsJson | ConvertFrom-Json
        Write-MigrationLog -Message "Found $($basicIps.Count) Basic SKU public IP(s)" -Level "Information"
        
        $ipInventory = @()
        
        foreach ($pip in $basicIps) {
            Write-MigrationLog -Message "Processing public IP: $($pip.name)" -Level "Debug"
            
            # Determine consumer type and ID
            $consumerType = "unattached"
            $consumerId = ""
            $consumerName = ""
            $nicName = ""
            $nicResourceGroup = ""
            
            if ($pip.ipConfiguration) {
                $ipConfigId = $pip.ipConfiguration.id
                
                # Parse the IP configuration ID to determine resource type
                if ($ipConfigId -match '/networkInterfaces/([^/]+)') {
                    $consumerType = "nic"
                    $nicName = $matches[1]
                    $consumerId = $ipConfigId -replace '/ipConfigurations/.*', ''
                    $consumerName = $nicName
                    
                    # Get NIC details to find resource group
                    $nicDetails = az network nic show --ids $consumerId --output json | ConvertFrom-Json
                    $nicResourceGroup = $nicDetails.resourceGroup
                    
                    Write-MigrationLog -Message "  Attached to NIC: $nicName in RG: $nicResourceGroup" -Level "Debug"
                }
                elseif ($ipConfigId -match '/loadBalancers/([^/]+)') {
                    $consumerType = "loadBalancer"
                    $consumerName = $matches[1]
                    $consumerId = $ipConfigId -replace '/frontendIPConfigurations/.*', ''
                    Write-MigrationLog -Message "  Attached to Load Balancer: $consumerName" -Level "Debug"
                }
                elseif ($ipConfigId -match '/applicationGateways/([^/]+)') {
                    $consumerType = "applicationGateway"
                    $consumerName = $matches[1]
                    $consumerId = $ipConfigId -replace '/frontendIPConfigurations/.*', ''
                    Write-MigrationLog -Message "  Attached to Application Gateway: $consumerName" -Level "Debug"
                }
                elseif ($ipConfigId -match '/virtualNetworkGateways/([^/]+)') {
                    $consumerType = "vpnGateway"
                    $consumerName = $matches[1]
                    $consumerId = $ipConfigId -replace '/ipConfigurations/.*', ''
                    Write-MigrationLog -Message "  Attached to VPN Gateway: $consumerName" -Level "Debug"
                }
                else {
                    $consumerType = "other"
                    $consumerId = $ipConfigId
                    Write-MigrationLog -Message "  Attached to unknown resource type: $ipConfigId" -Level "Warning"
                }
            }
            
            # Build inventory object
            $ipInfo = [PSCustomObject]@{
                Name = $pip.name
                ResourceGroup = $pip.resourceGroup
                Location = $pip.location
                IpAddress = if ($pip.ipAddress) { $pip.ipAddress } else { "(not allocated)" }
                AllocationMethod = $pip.publicIPAllocationMethod
                Sku = $pip.sku.name
                ResourceId = $pip.id
                ConsumerType = $consumerType
                ConsumerId = $consumerId
                ConsumerName = $consumerName
                NicName = $nicName
                NicResourceGroup = $nicResourceGroup
                DnsLabel = if ($pip.dnsSettings) { $pip.dnsSettings.domainNameLabel } else { $null }
                DnsFqdn = if ($pip.dnsSettings) { $pip.dnsSettings.fqdn } else { $null }
                Tags = $pip.tags
                MigrationStatus = "pending"
                StandardIpName = "$($pip.name)-std"
                StandardIpAddress = ""
                StandardIpResourceId = ""
                MigrationTimestamp = ""
                Notes = ""
            }
            
            $ipInventory += $ipInfo
        }
        
        Write-MigrationLog -Message "Basic IP inventory completed: $($ipInventory.Count) IPs cataloged" -Level "Information"
        return $ipInventory
    }
    catch {
        Write-MigrationLog -Message "Failed to discover Basic public IPs: $($_.Exception.Message)" -Level "Error" -Exception $_.Exception
        throw
    }
}

<#
.SYNOPSIS
    Exports migration inventory to CSV
.DESCRIPTION
    Saves the public IP inventory to a CSV file for tracking and reporting
.PARAMETER Inventory
    Array of public IP inventory objects
.PARAMETER OutputPath
    Path for the output CSV file
#>
function Export-MigrationInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Inventory,
        
        [Parameter(Mandatory = $true)]
        [string]$OutputPath
    )
    
    try {
        Write-MigrationLog -Message "Exporting migration inventory to: $OutputPath" -Level "Information"
        
        # Ensure output directory exists
        $outputDir = Split-Path $OutputPath -Parent
        if (-not (Test-Path $outputDir)) {
            New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
        }
        
        # Export to CSV with all properties
        $Inventory | Export-Csv -Path $OutputPath -NoTypeInformation -Force
        
        Write-MigrationLog -Message "Inventory exported successfully: $($Inventory.Count) records written" -Level "Information"
        
        # Also create a summary file
        $summaryPath = $OutputPath -replace '\.csv$', '_summary.txt'
        $summary = @"
Azure Public IP Migration Inventory Summary
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Subscription: $($Global:Config.subscriptionName) ($($Global:Config.subscriptionId))

Total Basic Public IPs: $($Inventory.Count)

By Consumer Type:
$($Inventory | Group-Object ConsumerType | ForEach-Object { "  $($_.Name): $($_.Count)" } | Out-String)

By Location:
$($Inventory | Group-Object Location | ForEach-Object { "  $($_.Name): $($_.Count)" } | Out-String)

By Migration Status:
$($Inventory | Group-Object MigrationStatus | ForEach-Object { "  $($_.Name): $($_.Count)" } | Out-String)

Full details available in: $OutputPath
"@
        
        $summary | Out-File -FilePath $summaryPath -Force
        Write-MigrationLog -Message "Summary file created: $summaryPath" -Level "Information"
        
        return $true
    }
    catch {
        Write-MigrationLog -Message "Failed to export inventory: $($_.Exception.Message)" -Level "Error" -Exception $_.Exception
        throw
    }
}

# Export module members
Export-ModuleMember -Function @(
    'Initialize-MigrationEnvironment',
    'Write-MigrationLog',
    'Get-BasicPublicIps',
    'Export-MigrationInventory'
)
'@

# Append the functions
Add-Content -Path $targetFile -Value $remainingFunctions

Write-Host "Common-Functions.ps1 updated successfully!" -ForegroundColor Green
