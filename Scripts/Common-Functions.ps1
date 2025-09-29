# Common-Functions.ps1
# Shared functions for Azure Public IP migration automation
# Provides logging, error handling, and utility functions

#Requires -Version 7.0
# Note: Az.Network and Az.Resources modules are checked at runtime instead of #Requires
# This allows for better error messages and graceful handling

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
        
        # Create log directory if it doesn't exist
        $logDir = Split-Path $Global:LogFile -Parent
        if (-not (Test-Path $logDir)) {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        }
        
        Write-MigrationLog -Message "=== Azure Public IP Migration - Initialization Started ===" -Level "Information"
        Write-MigrationLog -Message "Log file: $Global:LogFile" -Level "Information"
        
        # Validate PowerShell version
        if ($PSVersionTable.PSVersion.Major -lt 7) {
            throw "PowerShell 7.0 or higher is required. Current version: $($PSVersionTable.PSVersion)`nDownload from: https://github.com/PowerShell/PowerShell/releases"
        }
        Write-MigrationLog -Message "PowerShell version validated: $($PSVersionTable.PSVersion)" -Level "Information"
        
        # Check for required modules with helpful error messages
        $requiredModules = @('Az.Network', 'Az.Resources', 'Az.Accounts')
        $missingModules = @()
        
        foreach ($moduleName in $requiredModules) {
            if (-not (Get-Module -ListAvailable -Name $moduleName)) {
                $missingModules += $moduleName
                Write-MigrationLog -Message "Module '$moduleName' is not installed" -Level "Warning"
            }
        }
        
        if ($missingModules.Count -gt 0) {
            $installCommand = "Install-Module -Name $($missingModules -join ', ') -Scope CurrentUser -Force"
            Write-MigrationLog -Message "" -Level "Error"
            Write-MigrationLog -Message "MISSING REQUIRED MODULES" -Level "Error"
            Write-MigrationLog -Message "The following PowerShell modules are required but not installed:" -Level "Error"
            foreach ($module in $missingModules) {
                Write-MigrationLog -Message "  - $module" -Level "Error"
            }
            Write-MigrationLog -Message "" -Level "Error"
            Write-MigrationLog -Message "To install the missing modules, run this command:" -Level "Error"
            Write-MigrationLog -Message "  $installCommand" -Level "Error"
            Write-MigrationLog -Message "" -Level "Error"
            throw "Missing required PowerShell modules. Install with: $installCommand"
        }
        
        # Import the modules
        foreach ($moduleName in $requiredModules) {
            Import-Module $moduleName -ErrorAction Stop
            Write-MigrationLog -Message "Module loaded: $moduleName" -Level "Information"
        }
        
        # Verify Azure CLI is installed and updated
        try {
            $azVersion = az version --output json 2>$null | ConvertFrom-Json
            if (-not $azVersion) {
                throw "Azure CLI command returned no output"
            }
            $azCliVersion = $azVersion.'azure-cli'
            Write-MigrationLog -Message "Azure CLI version: $azCliVersion" -Level "Information"
            
            # Check minimum version (2.60.0)
            $minVersion = [version]"2.60.0"
            $currentVersion = [version]$azCliVersion
            if ($currentVersion -lt $minVersion) {
                Write-MigrationLog -Message "Azure CLI version $azCliVersion is below minimum required version $minVersion. Please upgrade." -Level "Warning"
                Write-MigrationLog -Message "  Download from: https://docs.microsoft.com/cli/azure/install-azure-cli" -Level "Warning"
            }
        }
        catch {
            Write-MigrationLog -Message "" -Level "Error"
            Write-MigrationLog -Message "AZURE CLI NOT FOUND" -Level "Error"
            Write-MigrationLog -Message "Azure CLI is required but not installed or not in PATH." -Level "Error"
            Write-MigrationLog -Message "" -Level "Error"
            Write-MigrationLog -Message "To install Azure CLI:" -Level "Error"
            Write-MigrationLog -Message "  Windows: winget install Microsoft.AzureCLI" -Level "Error"
            Write-MigrationLog -Message "  Or download from: https://docs.microsoft.com/cli/azure/install-azure-cli" -Level "Error"
            Write-MigrationLog -Message "" -Level "Error"
            throw "Azure CLI is not installed or not in PATH. Error: $($_.Exception.Message)"
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
        try {
            Write-MigrationLog -Message "Setting Azure context..." -Level "Information"
            $subscription = Set-AzContext -SubscriptionId $Global:Config.subscriptionId -ErrorAction Stop
            Write-MigrationLog -Message "Azure context set to subscription: $($subscription.Subscription.Name) ($($subscription.Subscription.Id))" -Level "Information"
        }
        catch {
            Write-MigrationLog -Message "" -Level "Error"
            Write-MigrationLog -Message "AZURE AUTHENTICATION REQUIRED" -Level "Error"
            Write-MigrationLog -Message "Failed to set Azure context. You may need to authenticate." -Level "Error"
            Write-MigrationLog -Message "" -Level "Error"
            Write-MigrationLog -Message "To authenticate to Azure, run:" -Level "Error"
            Write-MigrationLog -Message "  Connect-AzAccount" -Level "Error"
            Write-MigrationLog -Message "  Set-AzContext -SubscriptionId '$($Global:Config.subscriptionId)'" -Level "Error"
            Write-MigrationLog -Message "" -Level "Error"
            throw "Azure authentication required. Run: Connect-AzAccount"
        }
        
        # Also set Azure CLI context
        try {
            az account set --subscription $Global:Config.subscriptionId 2>$null
            Write-MigrationLog -Message "Azure CLI context set to subscription: $($Global:Config.subscriptionId)" -Level "Information"
        }
        catch {
            Write-MigrationLog -Message "" -Level "Error"
            Write-MigrationLog -Message "AZURE CLI AUTHENTICATION REQUIRED" -Level "Error"
            Write-MigrationLog -Message "Failed to set Azure CLI context. You may need to authenticate." -Level "Error"
            Write-MigrationLog -Message "" -Level "Error"
            Write-MigrationLog -Message "To authenticate Azure CLI, run:" -Level "Error"
            Write-MigrationLog -Message "  az login" -Level "Error"
            Write-MigrationLog -Message "  az account set --subscription '$($Global:Config.subscriptionId)'" -Level "Error"
            Write-MigrationLog -Message "" -Level "Error"
            throw "Azure CLI authentication required. Run: az login"
        }
        
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
        try {
            Add-Content -Path $Global:LogFile -Value $logEntry -ErrorAction SilentlyContinue
        }
        catch {
            # Silently ignore log file write errors to not break execution
        }
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

# Export module members - make functions available to importing scripts
Export-ModuleMember -Function @(
    'Initialize-MigrationEnvironment',
    'Write-MigrationLog',
    'Get-BasicPublicIps',
    'Export-MigrationInventory'
)
