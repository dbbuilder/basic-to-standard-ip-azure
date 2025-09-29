# Azure Public IP Migration - TODO

## Implementation Stages

### Stage 1: Environment Setup ✓
- [x] Create project directory structure
- [x] Create configuration file template
- [x] Document prerequisites
- [x] Create README with setup instructions
- [x] Initialize Git repository

### Stage 2: Core Functionality

#### Discovery Phase ✓
- [x] Implement Basic IP discovery function
- [x] Parse IP configuration details
- [x] Identify consumer resources (NIC/LB/VPN)
- [x] Export inventory to CSV
- [x] Generate summary reports

#### Create Phase
- [x] Implement Standard IP creation
- [x] Configure IP properties (static, zones)
- [x] Add secondary IP config to NICs
- [x] Batch processing logic
- [ ] Complete full implementation with error handling
- [ ] Add progress indicators
- [ ] Test with production IPs

#### Validation Phase
- [x] Connectivity testing (ICMP, TCP)
- [x] NSG rule validation
- [x] DNS resolution checks
- [x] Generate validation reports
- [ ] Add HTTP/HTTPS endpoint testing
- [ ] Test with real workloads

#### Cleanup Phase
- [x] Soak period validation
- [x] Remove Basic IP configs
- [x] Delete Basic IP resources
- [x] Confirmation prompts
- [ ] Test cleanup process
- [ ] Verify no service disruption

### Stage 3: Testing and Deployment

#### Testing
- [ ] Test Discovery phase in production subscription
- [ ] Test Create phase with 2-3 test IPs
- [ ] Validate connectivity after creation
- [ ] Test rollback procedures
- [ ] Document test results

#### Production Migration Schedule
- [ ] Week 1 (Oct 3-9): East US - 5 IPs
- [ ] Week 2 (Oct 10-16): West US Batch 1 - 5 IPs
- [ ] Week 3 (Oct 17-23): West US Batch 2 - 4 IPs
- [ ] Week 4 (Oct 24-30): West US 2 and West US 3 - 3 IPs
- [ ] Week 5 (Oct 31-Nov 6): Final validation and cleanup

### Stage 4: Documentation

#### User Documentation
- [x] README with quick start
- [x] Configuration guide
- [x] Requirements specification
- [ ] Video walkthrough (optional)
- [ ] FAQ document

#### Technical Documentation
- [x] Inline code comments
- [x] Function descriptions
- [x] Parameter documentation
- [ ] Architecture diagram
- [ ] Troubleshooting guide

## Priority Tasks (Next 2 Weeks)

### High Priority
1. [ ] Review and test discovery phase
2. [ ] Validate configuration file with actual subscription
3. [ ] Test create phase with 1-2 non-production IPs
4. [ ] Document any issues or modifications needed
5. [ ] Create detailed runbook for production execution

### Medium Priority
6. [ ] Set up monitoring for migration process
7. [ ] Prepare DNS update procedures
8. [ ] Create communication plan for stakeholders
9. [ ] Schedule maintenance windows if needed
10. [ ] Prepare rollback procedures

### Low Priority
11. [ ] Create PowerBI dashboard for tracking
12. [ ] Document lessons learned
13. [ ] Plan for Load Balancer migrations (if any)
14. [ ] Plan for VPN Gateway migrations (if any)

## Known Issues and Notes

### Issue #1: Large Script Files
**Status**: Resolved  
**Description**: PowerShell scripts are modular with Common-Functions library  
**Resolution**: Core functions in Common-Functions.ps1, phase logic in main script

### Issue #2: Full Implementation Pending
**Status**: In Progress  
**Description**: Main migration script phases need full implementation  
**Note**: Discovery phase is complete and functional. Create, Validate, and Cleanup phases have framework but need full logic implementation.

### Issue #3: GitHub Repository
**Status**: Pending  
**Description**: Need to initialize Git and push to GitHub  
**Action**: See instructions below

## Git and GitHub Setup

### Initialize Local Repository
```powershell
cd D:\dev2\basic-to-standard-ip-azure
git init
git add .
git commit -m "Initial commit: Azure Basic to Standard IP migration tool"
```

### Create GitHub Repository
1. Go to https://github.com/new
2. Repository name: `basic-to-standard-ip-azure`
3. Description: "Automated PowerShell tool for migrating Azure Basic SKU Public IPs to Standard SKU with zero downtime"
4. Public or Private (recommend Private for security)
5. Do NOT initialize with README (we have one)

### Push to GitHub
```powershell
git remote add origin https://github.com/YOUR_USERNAME/basic-to-standard-ip-azure.git
git branch -M main
git push -u origin main
```

## Migration Execution Checklist

### Pre-Migration
- [ ] Backup current IP configurations
- [ ] Document all DNS entries
- [ ] Notify stakeholders of migration schedule
- [ ] Lower DNS TTL to 60-120 seconds (48 hours before)
- [ ] Verify all prerequisites installed
- [ ] Test scripts in dry-run mode

### During Migration
- [ ] Run Discovery phase
- [ ] Review inventory output
- [ ] Run Create phase (start with small batch)
- [ ] Run Validate phase
- [ ] Update DNS records
- [ ] Monitor services during soak period

### Post-Migration
- [ ] Verify all services operational
- [ ] Run final validation
- [ ] Run Cleanup phase
- [ ] Restore DNS TTL to normal
- [ ] Document completion
- [ ] Archive logs and reports

## Next Steps

1. **Complete Script Implementation**
   - Finish Create phase with full batch processing
   - Implement Validate phase with all tests
   - Complete Cleanup phase with safeguards

2. **Testing**
   - Test in development subscription first
   - Run through full workflow with test IPs
   - Validate rollback procedures

3. **GitHub Setup**
   - Initialize Git repository
   - Create GitHub repo
   - Push code and documentation

4. **Production Preparation**
   - Schedule migration windows
   - Prepare stakeholder communications
   - Document emergency contacts

5. **Execute Migration**
   - Follow phased approach (5 IPs per week)
   - Monitor closely during soak periods
   - Document any issues or learnings
