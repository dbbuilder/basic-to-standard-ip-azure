# Multi-Subscription Support

## Overview
The Azure IP Migration Tool now supports scanning and migrating Basic public IPs across multiple Azure subscriptions in a single execution.

## Configuration

### Enable Multi-Subscription Scanning

Edit `Config\migration-config.json`:

```json
{
  "subscriptionId": "7ad813f6-5b95-449a-b341-e1c1854d9d67",
  "subscriptionName": "School Vision Client Subscription",
  "scanAllSubscriptions": true,
  "includeSubscriptions": [],
  "excludeSubscriptions": [],
  ...
}
```

### Configuration Options

#### `scanAllSubscriptions` (boolean)
- **`true`**: Scans all accessible subscriptions
- **`false`**: Scans only the subscription specified in `subscriptionId`
- **Default**: `true`

#### `includeSubscriptions` (array)
List of subscription IDs or names to include (whitelist):
```json
"includeSubscriptions": [
  "7ad813f6-5b95-449a-b341-e1c1854d9d67",
  "Production Subscription",
  "Dev/Test Subscription"
]
```
- If empty: All subscriptions are scanned (subject to exclude list)
- If specified: Only these subscriptions are scanned

#### `excludeSubscriptions` (array)
List of subscription IDs or names to exclude (blacklist):
```json
"excludeSubscriptions": [
  "Visual Studio Enterprise",
  "Free Trial",
  "sandbox-subscription-id"
]
```
- Excluded subscriptions are skipped
- Takes precedence over include list

## Usage Examples

### Example 1: Scan All Subscriptions
```json
{
  "scanAllSubscriptions": true,
  "includeSubscriptions": [],
  "excludeSubscriptions": []
}
```

### Example 2: Scan Specific Subscriptions Only
```json
{
  "scanAllSubscriptions": true,
  "includeSubscriptions": [
    "Production",
    "Staging",
    "Development"
  ],
  "excludeSubscriptions": []
}
```

### Example 3: Scan All Except Certain Subscriptions
```json
{
  "scanAllSubscriptions": true,
  "includeSubscriptions": [],
  "excludeSubscriptions": [
    "Visual Studio",
    "Free Trial",
    "Sandbox"
  ]
}
```

### Example 4: Single Subscription (Original Behavior)
```json
{
  "scanAllSubscriptions": false,
  "subscriptionId": "7ad813f6-5b95-449a-b341-e1c1854d9d67"
}
```

## How It Works

### Discovery Phase
1. **Retrieve Subscriptions**: Gets list of all accessible subscriptions
2. **Apply Filters**: Applies include/exclude filters from configuration
3. **Scan Each Subscription**: 
   - Sets subscription context
   - Discovers Basic public IPs
   - Records subscription information with each IP
4. **Aggregate Results**: Combines IPs from all subscriptions into single inventory

### Create/Validate/Cleanup Phases
- Automatically sets correct subscription context for each IP
- All operations are subscription-aware
- IPs are processed in their original subscriptions

## Inventory Output

### CSV Columns
The inventory CSV now includes subscription information:

| Column | Description |
|--------|-------------|
| `SubscriptionId` | Azure subscription ID where IP exists |
| `SubscriptionName` | Human-readable subscription name |
| `Name` | Public IP name |
| `ResourceGroup` | Resource group name |
| `Location` | Azure region |
| ... | (all other existing columns) |

### Example CSV Output
```csv
SubscriptionId,SubscriptionName,Name,ResourceGroup,Location,...
7ad813f6-5b95...,School Vision Client,DataCentral-ip,rg-Central,westus,...
a1b2c3d4-e5f6...,Production Subscription,AppServer-ip,rg-prod,eastus,...
```

## New Functions

### `Get-AzureSubscriptions`
Retrieves and filters subscriptions based on configuration.

**Returns**: Array of subscription objects

### `Get-BasicPublicIpsMultiSubscription`
Discovers Basic IPs across multiple subscriptions.

**Parameters**:
- `Subscriptions`: Array of subscription objects to scan

**Returns**: Array of IP inventory objects with subscription information

### `Set-AzureSubscriptionContext`
Sets both Azure CLI and PowerShell contexts to specified subscription.

**Parameters**:
- `SubscriptionId`: Subscription ID to set
- `SubscriptionName`: Subscription name (for logging)

### `New-StandardPublicIpWithSubscription`
Creates Standard IP in the correct subscription.

**Parameters**:
- Standard parameters (Name, ResourceGroup, Location)
- `SubscriptionId`: Target subscription

### `Add-SecondaryIpConfigToNicWithSubscription`
Adds secondary IP config with subscription awareness.

**Parameters**:
- Standard parameters (NicName, etc.)
- `SubscriptionId`: Subscription where NIC exists

### `Remove-BasicPublicIpWithSubscription`
Removes Basic IP from correct subscription.

**Parameters**:
- Standard parameters (BasicIpName, etc.)
- `SubscriptionId`: Subscription where IP exists

## Output and Reporting

### Discovery Summary
```
=== Multi-Subscription Discovery ===
Scanning 3 subscription(s)

--- Subscription 1 of 3 ---
Name: Production Subscription
ID: 7ad813f6-5b95-449a-b341-e1c1854d9d67
Found 5 Basic SKU public IP(s)

--- Subscription 2 of 3 ---
Name: Development Subscription
ID: a1b2c3d4-e5f6-7890-abcd-ef1234567890
Found 3 Basic SKU public IP(s)

--- Subscription 3 of 3 ---
Name: Staging Subscription
ID: 12345678-90ab-cdef-1234-567890abcdef
Found 2 Basic SKU public IP(s)

=== Multi-Subscription Discovery Complete ===
Total Basic IPs across all subscriptions: 10

By Subscription:
  Production Subscription: 5 IPs
  Development Subscription: 3 IPs
  Staging Subscription: 2 IPs
```

### Inventory Summary
The summary file includes breakdown by subscription:

```
By Subscription:
  Production Subscription: 5
  Development Subscription: 3
  Staging Subscription: 2

By Consumer Type:
  nic: 6
  unattached: 4

By Location:
  eastus: 7
  westus: 3
```

## Running Multi-Subscription Migration

### Step 1: Configure
Edit `Config\migration-config.json` to enable multi-subscription mode.

### Step 2: Discover
```powershell
.\Migrate-BasicToStandardIP.ps1 `
    -ConfigPath ..\Config\migration-config.json `
    -Phase Discovery
```

### Step 3: Review Inventory
```powershell
# View IPs by subscription
$csv = Get-ChildItem ..\Output\inventory_*.csv | Sort-Object LastWriteTime -Descending | Select-Object -First 1
Import-Csv $csv.FullName | Group-Object SubscriptionName | Format-Table Name, Count
```

### Step 4: Migrate
The Create, Validate, and Cleanup phases work identically:

```powershell
# Create Standard IPs (DryRun first)
.\Migrate-BasicToStandardIP.ps1 -ConfigPath ..\Config\migration-config.json -Phase Create -DryRun

# Create Standard IPs (actual)
.\Migrate-BasicToStandardIP.ps1 -ConfigPath ..\Config\migration-config.json -Phase Create

# Validate
.\Migrate-BasicToStandardIP.ps1 -ConfigPath ..\Config\migration-config.json -Phase Validate

# Cleanup
.\Migrate-BasicToStandardIP.ps1 -ConfigPath ..\Config\migration-config.json -Phase Cleanup
```

## Benefits

### Centralized Migration
- Migrate IPs from multiple subscriptions in one operation
- Single inventory file tracks all IPs
- Consistent migration process across subscriptions

### Simplified Management
- One configuration file for all subscriptions
- Unified logging and reporting
- Single execution workflow

### Flexibility
- Choose which subscriptions to scan
- Exclude test/sandbox subscriptions
- Process subsets of subscriptions

### Automatic Context Management
- Tool automatically switches subscription contexts
- No manual subscription switching required
- Prevents errors from incorrect context

## Best Practices

### 1. Test with Single Subscription First
Start with `scanAllSubscriptions: false` to test the tool.

### 2. Use Filters Wisely
- Exclude non-production subscriptions initially
- Test with dev/test subscriptions first
- Use include list for controlled rollout

### 3. Review Permissions
Ensure you have Network Contributor role in all target subscriptions:

```powershell
# Check role assignments across subscriptions
$subs = az account list --output json | ConvertFrom-Json
foreach ($sub in $subs) {
    Write-Host "`n$($sub.name):"
    az role assignment list --assignee YOUR_USER_ID --subscription $sub.id --query "[?roleDefinitionName=='Network Contributor' || roleDefinitionName=='Contributor' || roleDefinitionName=='Owner']" --output table
}
```

### 4. Monitor Resource Quotas
Each subscription has separate quotas for Standard public IPs.

### 5. Plan DNS Updates
Group IPs by subscription for organized DNS updates.

## Troubleshooting

### Issue: "Subscription not found"
**Cause**: Subscription ID in include list doesn't exist or is inaccessible  
**Solution**: Verify subscription ID and ensure you have access

### Issue: "Access denied" errors
**Cause**: Insufficient permissions in one or more subscriptions  
**Solution**: Ensure Network Contributor role in all target subscriptions

### Issue: Slow discovery
**Cause**: Scanning many subscriptions  
**Solution**: 
- Use include/exclude filters to limit scope
- Run during off-peak hours

### Issue: Context switching errors
**Cause**: Azure CLI or PowerShell session issues  
**Solution**: 
- Re-authenticate: `az login` and `Connect-AzAccount`
- Clear cached credentials
- Restart PowerShell session

## Migration Scenarios

### Scenario 1: Enterprise with Multiple Subscriptions
**Setup**: 10 subscriptions (Production, Dev, Test, Staging, etc.)  
**Strategy**:
1. Start with Test subscriptions
2. Move to Staging
3. Finally Production
4. Use exclude list to control rollout

### Scenario 2: Multiple Tenants/Customers
**Setup**: Managing IPs for multiple Azure tenants  
**Strategy**:
1. Process one tenant at a time
2. Use separate configuration files per tenant
3. Maintain separate inventory files

### Scenario 3: Departmental Subscriptions
**Setup**: Each department has own subscription  
**Strategy**:
1. Coordinate with department owners
2. Use include list for department-by-department migration
3. Schedule migrations during department maintenance windows

## Security Considerations

### Least Privilege
- Use service principal with Network Contributor only
- Scope permissions to specific resource groups if possible

### Audit Trail
- All subscription switches are logged
- Each operation logs subscription ID
- Complete audit trail in log files

### Credentials
- Use Azure AD authentication
- Enable MFA
- Rotate credentials regularly

## Performance

### Optimization Tips
1. **Parallel Processing**: Consider running separate instances for different subscription groups
2. **Filtering**: Use include/exclude to reduce scope
3. **Batch Size**: Adjust based on number of subscriptions
4. **Off-Peak**: Run during low-activity periods

### Expected Performance
- Discovery: ~30-60 seconds per subscription
- Creation: ~2-3 minutes per IP
- Validation: ~1-2 minutes per IP
- Cleanup: ~1-2 minutes per IP

## Limitations

### Current Limitations
1. All subscriptions must be in same Azure AD tenant
2. Requires Network Contributor in each subscription
3. Cannot span across different Azure clouds (Public, Government, China)

### Workarounds
- For multi-tenant: Run separate instances per tenant
- For different clouds: Use separate configurations
- For limited permissions: Use include list for accessible subscriptions only

## Future Enhancements

Planned features:
- Parallel subscription processing
- Subscription-specific configuration overrides
- Cross-tenant support
- Automated RBAC validation
- Subscription health checks before migration

## Support

For issues with multi-subscription features:
1. Check subscription list with `az account list`
2. Verify permissions in each subscription
3. Review logs for subscription context errors
4. Test with single subscription first

---

**Note**: Multi-subscription support is available in version 2.0+ of the Azure IP Migration Tool.
