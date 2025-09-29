# Common-Functions.ps1
# Shared functions for Azure Public IP migration automation
# Provides logging, error handling, and utility functions

#Requires -Version 7.0
#Requires -Modules Az.Network, Az.Resources

# Global variables for logging
$Global:LogFile = ""
$Global:MigrationStartTime = Get-Date
$Global:Config = $null

<#
.SYNOPSIS
    Initializes the migration environment and loads configuration
.DESCRIPTION
    Sets up logging, validates Azure CLI and PowerShell modules, loads configuration file
.PARAMETER ConfigPath
    Path to the migration configuration JSON file
#>
function Initialize-MigrationEnvironment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
    )
    
    try {
        # Set up logging
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $Global:LogFile = Join-Path -Path (Split-Path $ConfigPath -Parent) -ChildPath "..\Logs\migration_$timestamp.log"
        
        Write-MigrationLog -Message "=== Azure Public IP Migration - Initialization Started ===" -Level "Information"
        Write-MigrationLog -Message "Log file: $Global:LogFile" -Level "Information"
        
        # Validate PowerShell version
        if ($PSVersionTable.PSVersion.Major -lt 7) {
            throw "PowerShell 7.0 or higher is required. Current version: $($PSVersionTable.PSVersion)"
        }
        Write-MigrationLog -Message "PowerShell version validated: $($PSVersionTable.PSVersion)" -Level "Information"
        
        # Check for required modules
        $requiredModules = @('Az.Network', 'Az.Resources', 'Az.Accounts')
        foreach ($moduleName in $requiredModules) {
            if (-not (Get-Module -ListAvailable -Name $moduleName)) {
                throw "Required module '$moduleName' is not installed. Install with: Install-Module -Name $moduleName -Scope CurrentUser"
            }
            Import-Module $moduleName -ErrorAction Stop
            Write-MigrationLog -Message "Module loaded: $moduleName" -Level "Information"
        }
        
        # Verify Azure CLI is installed and updated
        try {
            $azVersion = az version --output json | ConvertFrom-Json
            $azCliVersion = $azVersion.'azure-cli'
            Write-MigrationLog -Message "Azure CLI version: $azCliVersion" -Level "Information"
            
            # Check minimum version (2.60.0)
            $minVersion = [version]"2.60.0"
            $currentVersion = [version]$azCliVersion
            if ($currentVersion -lt $minVersion) {
                Write-MigrationLog -Message "Azure CLI version $azCliVersion is below minimum required version $minVersion. Please upgrade." -Level "Warning"
            }
        }
        catch {
            throw "Azure CLI is not installed or not in PATH. Install from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        }
        
        # Load configuration file
        if (-not (Test-Path $ConfigPath)) {
            throw "Configuration file not found at: $ConfigPath"
        }
        
        $Global:Config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
        Write-MigrationLog -Message "Configuration loaded from: $ConfigPath" -Level "Information"
        
        # Validate configuration structure
        $requiredProperties = @('subscriptionId', 'migration', 'publicIps', 'logging', 'validation')
        foreach ($prop in $requiredProperties) {
            if (-not ($Global:Config.PSObject.Properties.Name -contains $prop)) {
                throw "Configuration file is missing required property: $prop"
            }
        }
        
        # Set Azure context
        $subscription = Set-AzContext -SubscriptionId $Global:Config.subscriptionId -ErrorAction Stop
        Write-MigrationLog -Message "Azure context set to subscription: $($subscription.Subscription.Name) ($($subscription.Subscription.Id))" -Level "Information"
        
        # Also set Azure CLI context
        az account set --subscription $Global:Config.subscriptionId
        Write-MigrationLog -Message "Azure CLI context set to subscription: $($Global:Config.subscriptionId)" -Level "Information"
        
        Write-MigrationLog -Message "=== Initialization Completed Successfully ===" -Level "Information"
        return $true
    }
    catch {
        Write-MigrationLog -Message "Initialization failed: $($_.Exception.Message)" -Level "Error"
        Write-MigrationLog -Message "Stack trace: $($_.ScriptStackTrace)" -Level "Error"
        throw
    }
}

<#
.SYNOPSIS
    Writes log messages to file and console
.DESCRIPTION
    Centralized logging function with timestamp, level, and optional error details
.PARAMETER Message
    The log message to write
.PARAMETER Level
    Log level: Information, Warning, Error, Debug
.PARAMETER Exception
    Optional exception object to log details
#>
function Write-MigrationLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('Information', 'Warning', 'Error', 'Debug')]
        [string]$Level = 'Information',
        
        [Parameter(Mandatory = $false)]
        [System.Exception]$Exception = $null
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # Add exception details if provided
    if ($Exception) {
        $logEntry += "`r`n    Exception: $($Exception.Message)"
        $logEntry += "`r`n    StackTrace: $($Exception.StackTrace)"
    }
    
    # Write to file if log file is set
    if ($Global:LogFile) {
        Add-Content -Path $Global:LogFile -Value $logEntry -ErrorAction SilentlyContinue
    }
    
    # Write to console based on configuration and level
    if ($Global:Config.logging.enableConsoleOutput -or -not $Global:Config) {
        switch ($Level) {
            'Information' { Write-Host $logEntry -ForegroundColor Cyan }
            'Warning' { Write-Host $logEntry -ForegroundColor Yellow }
            'Error' { Write-Host $logEntry -ForegroundColor Red }
            'Debug' { Write-Host $logEntry -ForegroundColor Gray }
        }
    }
}

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
        
        # Use Azure CLI for comprehensive query (handles pagination better than PowerShell for large sets)
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
                    # Extract NIC resource ID (everything before /ipConfigurations)
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
    Creates a Standard SKU public IP
.DESCRIPTION
    Creates a new Standard SKU public IP with specified configuration
.PARAMETER Name
    Name for the new Standard public IP
.PARAMETER ResourceGroup
    Resource group for the new IP
.PARAMETER Location
    Azure region for the new IP
.OUTPUTS
    Custom object with new public IP details
#>
function New-StandardPublicIp {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroup,
        
        [Parameter(Mandatory = $true)]
        [string]$Location
    )
    
    try {
        Write-MigrationLog -Message "Creating Standard public IP: $Name in RG: $ResourceGroup, Location: $Location" -Level "Information"
        
        # Build creation command with all parameters
        $createParams = @(
            "--name", $Name,
            "--resource-group", $ResourceGroup,
            "--location", $Location,
            "--sku", "Standard",
            "--allocation-method", $Global:Config.migration.standardSkuAllocationMethod,
            "--version", $Global:Config.migration.standardSkuVersion,
            "--tags", "$($Global:Config.migration.tagKey)=$($Global:Config.migration.tagValue)",
            "--output", "json"
        )
        
        # Add zones if configured
        if ($Global:Config.migration.useZones -and $Global:Config.migration.zones.Count -gt 0) {
            foreach ($zone in $Global:Config.migration.zones) {
                $createParams += "--zone"
                $createParams += $zone
            }
            Write-MigrationLog -Message "  Configuring zones: $($Global:Config.migration.zones -join ', ')" -Level "Debug"
        }
        
        # Execute creation
        $newIpJson = az network public-ip create @createParams
        
        if (-not $newIpJson) {
            throw "Failed to create Standard public IP: $Name. Azure CLI returned no output."
        }
        
        $newIp = $newIpJson | ConvertFrom-Json
        
        Write-MigrationLog -Message "  Standard IP created successfully" -Level "Information"
        Write-MigrationLog -Message "  IP Address: $($newIp.publicIp.ipAddress)" -Level "Information"
        Write-MigrationLog -Message "  Resource ID: $($newIp.publicIp.id)" -Level "Debug"
        
        return [PSCustomObject]@{
            Name = $newIp.publicIp.name
            ResourceGroup = $ResourceGroup
            IpAddress = $newIp.publicIp.ipAddress
            ResourceId = $newIp.publicIp.id
            Location = $newIp.publicIp.location
            Sku = $newIp.publicIp.sku.name
        }
    }
    catch {
        Write-MigrationLog -Message "Failed to create Standard public IP '$Name': $($_.Exception.Message)" -Level "Error" -Exception $_.Exception
        throw
    }
}

<#
.SYNOPSIS
    Adds a secondary IP configuration to a NIC with Standard public IP
.DESCRIPTION
    Creates a new IP configuration on an existing NIC and associates the Standard public IP
.PARAMETER NicName
    Name of the network interface
.PARAMETER NicResourceGroup
    Resource group containing the NIC
.PARAMETER IpConfigName
    Name for the new IP configuration
.PARAMETER PublicIpName
    Name of the Standard public IP to associate
#>
function Add-SecondaryIpConfigToNic {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$NicName,
        
        [Parameter(Mandatory = $true)]
        [string]$NicResourceGroup,
        
        [Parameter(Mandatory = $true)]
        [string]$IpConfigName,
        
        [Parameter(Mandatory = $true)]
        [string]$PublicIpName
    )
    
    try {
        Write-MigrationLog -Message "Adding secondary IP config '$IpConfigName' to NIC: $NicName" -Level "Information"
        
        # Get current NIC details to validate state
        $nicJson = az network nic show --name $NicName --resource-group $NicResourceGroup --output json
        $nic = $nicJson | ConvertFrom-Json
        
        # Check if IP config already exists
        $existingConfig = $nic.ipConfigurations | Where-Object { $_.name -eq $IpConfigName }
        if ($existingConfig) {
            Write-MigrationLog -Message "  IP configuration '$IpConfigName' already exists on NIC. Skipping creation." -Level "Warning"
            return $true
        }
        
        # Create the IP configuration
        $result = az network nic ip-config create `
            --resource-group $NicResourceGroup `
            --nic-name $NicName `
            --name $IpConfigName `
            --public-ip-address $PublicIpName `
            --output json
        
        if (-not $result) {
            throw "Failed to create IP configuration. Azure CLI returned no output."
        }
        
        Write-MigrationLog -Message "  Secondary IP configuration added successfully" -Level "Information"
        
        # Verify the configuration was added
        $updatedNicJson = az network nic show --name $NicName --resource-group $NicResourceGroup --output json
        $updatedNic = $updatedNicJson | ConvertFrom-Json
        $verifyConfig = $updatedNic.ipConfigurations | Where-Object { $_.name -eq $IpConfigName }
        
        if ($verifyConfig) {
            Write-MigrationLog -Message "  Verified IP configuration is present on NIC" -Level "Debug"
            return $true
        }
        else {
            throw "IP configuration was created but verification failed"
        }
    }
    catch {
        Write-MigrationLog -Message "Failed to add secondary IP config to NIC '$NicName': $($_.Exception.Message)" -Level "Error" -Exception $_.Exception
        throw
    }
}

<#
.SYNOPSIS
    Validates NSG rules allow traffic to new public IP
.DESCRIPTION
    Checks NSG associated with NIC and validates inbound rules
.PARAMETER NicName
    Name of the network interface
.PARAMETER NicResourceGroup
    Resource group containing the NIC
.PARAMETER NewPublicIp
    The new Standard public IP address
.OUTPUTS
    Boolean indicating if NSG rules are adequate
#>
function Test-NsgRulesForNewIp {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$NicName,
        
        [Parameter(Mandatory = $true)]
        [string]$NicResourceGroup,
        
        [Parameter(Mandatory = $true)]
        [string]$NewPublicIp
    )
    
    try {
        Write-MigrationLog -Message "Validating NSG rules for NIC: $NicName" -Level "Information"
        
        # Get NIC details including NSG
        $nicJson = az network nic show --name $NicName --resource-group $NicResourceGroup --output json
        $nic = $nicJson | ConvertFrom-Json
        
        if (-not $nic.networkSecurityGroup) {
            Write-MigrationLog -Message "  No NSG attached to NIC. Subnet-level NSG may apply." -Level "Warning"
            # Check subnet NSG
            if ($nic.ipConfigurations[0].subnet.id) {
                $subnetId = $nic.ipConfigurations[0].subnet.id
                $subnetJson = az network vnet subnet show --ids $subnetId --output json
                $subnet = $subnetJson | ConvertFrom-Json
                
                if ($subnet.networkSecurityGroup) {
                    $nsgId = $subnet.networkSecurityGroup.id
                    Write-MigrationLog -Message "  Found subnet-level NSG: $nsgId" -Level "Information"
                }
                else {
                    Write-MigrationLog -Message "  No NSG at NIC or subnet level. Traffic rules should be reviewed manually." -Level "Warning"
                    return $false
                }
            }
            else {
                return $false
            }
        }
        else {
            $nsgId = $nic.networkSecurityGroup.id
            Write-MigrationLog -Message "  NIC has NSG: $nsgId" -Level "Information"
        }
        
        # Note: Standard public IPs have deny-all inbound by default; NSG rules must explicitly allow traffic
        # This is different from Basic public IPs which are open by default
        Write-MigrationLog -Message "  IMPORTANT: Standard SKU public IPs require explicit NSG allow rules" -Level "Warning"
        Write-MigrationLog -Message "  Verify inbound rules allow required traffic for: $NewPublicIp" -Level "Warning"
        
        return $true
    }
    catch {
        Write-MigrationLog -Message "Failed to validate NSG rules: $($_.Exception.Message)" -Level "Error" -Exception $_.Exception
        return $false
    }
}

<#
.SYNOPSIS
    Validates that a public IP is reachable
.DESCRIPTION
    Performs connectivity tests to ensure the IP is accessible
.PARAMETER IpAddress
    The public IP address to test
.PARAMETER Ports
    Array of ports to test (default: 80, 443)
.OUTPUTS
    Boolean indicating if IP is reachable
#>
function Test-PublicIpConnectivity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$IpAddress,
        
        [Parameter(Mandatory = $false)]
        [int[]]$Ports = @(80, 443)
    )
    
    try {
        Write-MigrationLog -Message "Testing connectivity to IP: $IpAddress" -Level "Information"
        
        # Basic ICMP ping test
        $pingResult = Test-Connection -ComputerName $IpAddress -Count 2 -Quiet -ErrorAction SilentlyContinue
        
        if ($pingResult) {
            Write-MigrationLog -Message "  ICMP ping successful to $IpAddress" -Level "Information"
        }
        else {
            Write-MigrationLog -Message "  ICMP ping failed to $IpAddress (may be blocked by firewall)" -Level "Warning"
        }
        
        # Test specified ports
        $portTestResults = @()
        foreach ($port in $Ports) {
            $tcpTest = Test-NetConnection -ComputerName $IpAddress -Port $port -InformationLevel Quiet -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            $portTestResults += [PSCustomObject]@{
                Port = $port
                Accessible = $tcpTest
            }
            
            if ($tcpTest) {
                Write-MigrationLog -Message "  Port $port is accessible on $IpAddress" -Level "Information"
            }
            else {
                Write-MigrationLog -Message "  Port $port is NOT accessible on $IpAddress" -Level "Warning"
            }
        }
        
        # Overall assessment: at least one method should succeed
        $overallSuccess = $pingResult -or ($portTestResults | Where-Object { $_.Accessible }).Count -gt 0
        
        if ($overallSuccess) {
            Write-MigrationLog -Message "  Connectivity validation PASSED for $IpAddress" -Level "Information"
        }
        else {
            Write-MigrationLog -Message "  Connectivity validation FAILED for $IpAddress" -Level "Error"
        }
        
        return $overallSuccess
    }
    catch {
        Write-MigrationLog -Message "Connectivity test failed for $IpAddress: $($_.Exception.Message)" -Level "Error" -Exception $_.Exception
        return $false
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

<#
.SYNOPSIS
    Removes Basic public IP from NIC and deletes the resource
.DESCRIPTION
    Safely removes the Basic IP configuration and deletes the public IP after migration soak period
.PARAMETER BasicIpName
    Name of the Basic public IP to remove
.PARAMETER BasicIpResourceGroup
    Resource group containing the Basic IP
.PARAMETER NicName
    Name of the NIC to remove IP config from
.PARAMETER NicResourceGroup
    Resource group containing the NIC
.PARAMETER IpConfigName
    Name of the IP configuration to remove
#>
function Remove-BasicPublicIp {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BasicIpName,
        
        [Parameter(Mandatory = $true)]
        [string]$BasicIpResourceGroup,
        
        [Parameter(Mandatory = $false)]
        [string]$NicName,
        
        [Parameter(Mandatory = $false)]
        [string]$NicResourceGroup,
        
        [Parameter(Mandatory = $false)]
        [string]$IpConfigName
    )
    
    try {
        Write-MigrationLog -Message "Removing Basic public IP: $BasicIpName" -Level "Information"
        
        # If attached to NIC, remove IP configuration first
        if ($NicName -and $IpConfigName) {
            Write-MigrationLog -Message "  Removing IP configuration '$IpConfigName' from NIC: $NicName" -Level "Information"
            
            # Get NIC to find the IP config
            $nicJson = az network nic show --name $NicName --resource-group $NicResourceGroup --output json
            $nic = $nicJson | ConvertFrom-Json
            
            $ipConfig = $nic.ipConfigurations | Where-Object { $_.name -eq $IpConfigName }
            
            if ($ipConfig) {
                # Remove the IP configuration
                az network nic ip-config delete `
                    --resource-group $NicResourceGroup `
                    --nic-name $NicName `
                    --name $IpConfigName `
                    --output none 2>$null
                
                Write-MigrationLog -Message "  IP configuration removed from NIC" -Level "Information"
            }
            else {
                Write-MigrationLog -Message "  IP configuration '$IpConfigName' not found on NIC" -Level "Warning"
            }
        }
        
        # Delete the Basic public IP resource
        Write-MigrationLog -Message "  Deleting Basic public IP resource: $BasicIpName" -Level "Information"
        
        az network public-ip delete `
            --name $BasicIpName `
            --resource-group $BasicIpResourceGroup `
            --output none
        
        Write-MigrationLog -Message "  Basic public IP deleted successfully" -Level "Information"
        
        return $true
    }
    catch {
        Write-MigrationLog -Message "Failed to remove Basic public IP '$BasicIpName': $($_.Exception.Message)" -Level "Error" -Exception $_.Exception
        throw
    }
}

# Export module members
Export-ModuleMember -Function @(
    'Initialize-MigrationEnvironment',
    'Write-MigrationLog',
    'Get-BasicPublicIps',
    'New-StandardPublicIp',
    'Add-SecondaryIpConfigToNic',
    'Test-NsgRulesForNewIp',
    'Test-PublicIpConnectivity',
    'Export-MigrationInventory',
    'Remove-BasicPublicIp'
)
