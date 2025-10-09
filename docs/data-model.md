# Data Model Documentation

## Overview
This document describes the data model for the Insurance Claims Management System in Salesforce.

---

## Custom Objects

### 1. Claim__c (Main Claims Object)

**Purpose**: Stores insurance claim information

**Fields**:

| Field API Name | Type | Description | Validation Rules |
|---------------|------|-------------|------------------|
| ClaimNumber__c | Auto-Number | Unique claim identifier | Format: CLM-{0000000} |
| PolicyNumber__c | Text(20) | Associated policy number | Required, 10-20 characters |
| PolicyHolder__c | Lookup(Contact) | Person who owns the policy | Required |
| ClaimAmount__c | Currency(16,2) | Total claim amount | Must be > 0, Max: $1,000,000 |
| Status__c | Picklist | Current claim status | Values: New, Under Review, Approved, Rejected, Paid |
| ApprovalLevel__c | Picklist | Required approval level | Values: Auto Approved, Manager, Senior Manager |
| SubmittedDate__c | Date | When claim was submitted | Auto-populated on creation |
| ApprovedDate__c | Date | When claim was approved | Set when Status = Approved |
| PaidDate__c | Date | When payment was processed | Set when Status = Paid |
| RejectionReason__c | Long Text Area | Reason for rejection | Required if Status = Rejected |
| ClaimDescription__c | Long Text Area | Description of claim | Required, Max: 5000 chars |
| IncidentDate__c | Date | When incident occurred | Required, Cannot be future date |
| PaymentTransactionId__c | Text(50) | External payment reference | Populated by payment gateway |
| FraudScore__c | Number(3,2) | Fraud detection score | Range: 0.00 to 1.00 |
| IsFraudulent__c | Checkbox | Flagged as fraudulent | Auto-calculated if FraudScore > 0.75 |

**Record Types**:
- Auto Claims
- Property Claims
- Health Claims

**Relationships**:
- Master-Detail to Policy__c
- Lookup to Contact (PolicyHolder__c)
- Lookup to User (ApprovedBy__c)
- Has many ClaimLineItem__c (child)
- Has many ClaimDocument__c (child)

**Validation Rules**:

```apex
// VR_ClaimAmount_MatchesLineItems
// Claim amount must equal sum of line items
AND(
    NOT(ISNEW()),
    ClaimAmount__c != 0,
    ClaimAmount__c != TotalLineItemAmount__c
)

// Error: "Claim amount must equal sum of line items"
```

```apex
// VR_IncidentDate_NotFuture
// Incident date cannot be in the future
IncidentDate__c > TODAY()

// Error: "Incident date cannot be in the future"
```

```apex
// VR_Status_RequireRejectionReason
// Rejection reason required when status is Rejected
AND(
    ISPICKVAL(Status__c, "Rejected"),
    ISBLANK(RejectionReason__c)
)

// Error: "Rejection reason is required for rejected claims"
```

---

### 2. ClaimLineItem__c (Claim Line Items)

**Purpose**: Individual items within a claim

**Fields**:

| Field API Name | Type | Description | Validation Rules |
|---------------|------|-------------|------------------|
| Claim__c | Master-Detail(Claim__c) | Parent claim | Required |
| ItemDescription__c | Text(255) | Description of item | Required |
| ItemAmount__c | Currency(16,2) | Amount for this item | Required, Must be > 0 |
| Category__c | Picklist | Item category | Values: Medical, Property Damage, Lost Wages, Other |
| Quantity__c | Number(10,2) | Quantity of items | Default: 1, Must be > 0 |
| UnitPrice__c | Currency(16,2) | Price per unit | Calculated: ItemAmount__c / Quantity__c |
| SupportingDocuments__c | Number(2,0) | Count of documents | Roll-up from ClaimDocument__c |

**Validation Rules**:

```apex
// VR_ItemAmount_Positive
// Item amount must be positive
ItemAmount__c <= 0

// Error: "Item amount must be greater than zero"
```

**Rollup Summary Fields** (on Claim__c):
- TotalLineItemAmount__c: SUM(ClaimLineItem__c.ItemAmount__c)
- LineItemCount__c: COUNT(ClaimLineItem__c)

---

### 3. ClaimDocument__c (Claim Supporting Documents)

**Purpose**: Stores references to uploaded documents

**Fields**:

| Field API Name | Type | Description | Validation Rules |
|---------------|------|-------------|------------------|
| Claim__c | Master-Detail(Claim__c) | Parent claim | Required |
| ClaimLineItem__c | Lookup(ClaimLineItem__c) | Related line item | Optional |
| DocumentName__c | Text(255) | Name of document | Required |
| DocumentType__c | Picklist | Type of document | Values: Receipt, Invoice, Police Report, Medical Record, Photo, Other |
| ContentVersionId__c | Text(18) | Salesforce Content ID | Required |
| UploadedDate__c | DateTime | When uploaded | Auto-populated |
| UploadedBy__c | Lookup(User) | Who uploaded | Auto-populated |
| FileSize__c | Number(10,0) | Size in bytes | Auto-populated |
| IsVerified__c | Checkbox | Document verified | Default: false |

---

### 4. Policy__c (Insurance Policies)

**Purpose**: Stores insurance policy information

**Fields**:

| Field API Name | Type | Description | Validation Rules |
|---------------|------|-------------|------------------|
| PolicyNumber__c | Text(20) | Unique policy number | Required, External ID |
| PolicyHolder__c | Lookup(Contact) | Policy owner | Required |
| PolicyType__c | Picklist | Type of policy | Values: Auto, Home, Health, Life |
| CoverageAmount__c | Currency(16,2) | Maximum coverage | Required, Must be > 0 |
| Premium__c | Currency(16,2) | Monthly premium | Required |
| StartDate__c | Date | Policy start date | Required |
| EndDate__c | Date | Policy end date | Must be after StartDate__c |
| Status__c | Picklist | Policy status | Values: Active, Expired, Cancelled, Suspended |
| Deductible__c | Currency(16,2) | Deductible amount | Required |

**Relationships**:
- Has many Claim__c (children)

---

### 5. ErrorLog__c (Error Logging)

**Purpose**: Centralized error logging for troubleshooting

**Fields**:

| Field API Name | Type | Description | Validation Rules |
|---------------|------|-------------|------------------|
| ErrorMessage__c | Long Text Area | Error message | Required |
| StackTrace__c | Long Text Area | Full stack trace | Optional |
| ClassName__c | Text(255) | Class where error occurred | Required |
| MethodName__c | Text(255) | Method where error occurred | Required |
| RecordId__c | Text(18) | Related record ID | Optional |
| ErrorType__c | Picklist | Type of error | Values: Validation, Integration, Database, Business Logic, Unknown |
| Severity__c | Picklist | Error severity | Values: Low, Medium, High, Critical |
| Timestamp__c | DateTime | When error occurred | Required, Auto-populated |
| User__c | Lookup(User) | User who encountered error | Auto-populated |
| IsResolved__c | Checkbox | Error resolved | Default: false |

---

### 6. IntegrationLog__c (Integration Audit Trail)

**Purpose**: Tracks all external system integrations

**Fields**:

| Field API Name | Type | Description | Validation Rules |
|---------------|------|-------------|------------------|
| Claim__c | Lookup(Claim__c) | Related claim | Optional |
| IntegrationName__c | Text(100) | Name of integration | Required |
| Endpoint__c | Text(255) | API endpoint called | Required |
| RequestMethod__c | Picklist | HTTP method | Values: GET, POST, PUT, PATCH, DELETE |
| RequestPayload__c | Long Text Area | Request body | Optional |
| ResponsePayload__c | Long Text Area | Response body | Optional |
| StatusCode__c | Number(3,0) | HTTP status code | Required |
| IsSuccess__c | Checkbox | Integration succeeded | Calculated: StatusCode__c = 200 |
| DurationMs__c | Number(10,0) | Duration in milliseconds | Required |
| Timestamp__c | DateTime | When called | Required, Auto-populated |
| RetryCount__c | Number(2,0) | Number of retries | Default: 0 |

---

## Standard Objects (Extended)

### Contact

**Custom Fields Added**:

| Field API Name | Type | Description |
|---------------|------|-------------|
| PolicyCount__c | Number(10,0) | Count of active policies (Rollup) |
| TotalClaimsValue__c | Currency(16,2) | Sum of all claims (Rollup) |
| LastClaimDate__c | Date | Date of most recent claim |
| RiskScore__c | Number(3,2) | Calculated risk score (0-1) |
| PreferredContactMethod__c | Picklist | Email, Phone, SMS |

---

## Relationship Diagram

```
Policy__c (1)
    ↓ (Master-Detail)
Claim__c (N)
    ↓ (Master-Detail)
ClaimLineItem__c (N)

Claim__c (1)
    ↓ (Master-Detail)
ClaimDocument__c (N)

Contact (1)
    ↓ (Lookup)
Policy__c (N)
    ↓
Claim__c (N)

Claim__c (1)
    ↓ (Related List)
IntegrationLog__c (N)

All Objects
    ↓ (Error Logging)
ErrorLog__c
```

---

## Field Dependencies

### Claim__c Status Picklist Dependencies

**Controlling Field**: Status__c  
**Dependent Field**: ApprovalLevel__c

| Status | Available Approval Levels |
|--------|--------------------------|
| New | Auto Approved, Manager, Senior Manager |
| Under Review | Manager, Senior Manager |
| Approved | (Read-only) |
| Rejected | (Read-only) |
| Paid | (Read-only) |

---

## Key Field Formulas

### Claim__c.DaysToApproval__c
```apex
// Number of days from submission to approval
IF(
    ISPICKVAL(Status__c, "Approved"),
    ApprovedDate__c - SubmittedDate__c,
    NULL
)
```

### Claim__c.IsOverThreshold__c
```apex
// Flag claims over $25,000
ClaimAmount__c > 25000
```

### Claim__c.RequiresManagerApproval__c
```apex
// Business rule: Claims $5K-$25K need manager approval
AND(
    ClaimAmount__c >= 5000,
    ClaimAmount__c < 25000
)
```

---

## Data Archival Rules

### Claim Records
- **Paid Claims**: Archive after 7 years
- **Rejected Claims**: Archive after 3 years
- **Cancelled Claims**: Archive after 1 year

### Error Logs
- **Resolved Errors**: Archive after 90 days
- **Unresolved Errors**: Keep for 1 year

### Integration Logs
- **Successful Calls**: Archive after 30 days
- **Failed Calls**: Keep for 90 days

---

## Data Access Patterns

### Common Queries

**Get Claim with All Related Data**:
```apex
SELECT Id, ClaimNumber__c, ClaimAmount__c, Status__c,
    Policy__r.PolicyNumber__c,
    PolicyHolder__r.Name,
    PolicyHolder__r.Email,
    (SELECT Id, ItemDescription__c, ItemAmount__c FROM ClaimLineItems__r),
    (SELECT Id, DocumentName__c, DocumentType__c FROM ClaimDocuments__r)
FROM Claim__c
WHERE Id = :claimId
```

**Get Pending Claims by Approval Level**:
```apex
SELECT Id, ClaimNumber__c, ClaimAmount__c, SubmittedDate__c
FROM Claim__c
WHERE Status__c = 'Under Review'
AND ApprovalLevel__c = 'Manager'
ORDER BY SubmittedDate__c ASC
```

**Get High-Risk Claims**:
```apex
SELECT Id, ClaimNumber__c, ClaimAmount__c, FraudScore__c
FROM Claim__c
WHERE FraudScore__c > 0.75
OR IsFraudulent__c = true
ORDER BY FraudScore__c DESC
```

---

## Indexing Strategy

### Custom Indexes

**Claim__c**:
- ClaimNumber__c (Unique, External ID)
- PolicyNumber__c (for lookups)
- Status__c (frequently filtered)
- SubmittedDate__c (for date range queries)

**ClaimLineItem__c**:
- Claim__c (Master-Detail auto-indexed)

**ErrorLog__c**:
- Timestamp__c (for time-based queries)
- ClassName__c + MethodName__c (for debugging)

---

## Data Volume Estimates

### Current Production (Example)
- **Policies**: ~50,000 records
- **Claims**: ~150,000 records (3 per policy on average)
- **Claim Line Items**: ~450,000 records (3 per claim on average)
- **Documents**: ~600,000 records (4 per claim on average)
- **Error Logs**: ~10,000 records/month
- **Integration Logs**: ~50,000 records/month

### Growth Rate
- **Claims**: ~2,000 new claims/month
- **Documents**: ~8,000 new documents/month

---

## Best Practices for Data Operations

### Bulk Operations
```apex
// Always use bulk patterns for DML
List<Claim__c> claimsToUpdate = new List<Claim__c>();

for(Claim__c claim : claims) {
    if(claim.ClaimAmount__c > 25000) {
        claim.ApprovalLevel__c = 'Senior Manager';
        claimsToUpdate.add(claim);
    }
}

if(!claimsToUpdate.isEmpty()) {
    update claimsToUpdate;
}
```

### Query Optimization
```apex
// Use selective filters and minimize returned fields
List<Claim__c> recentClaims = [
    SELECT Id, ClaimNumber__c, ClaimAmount__c
    FROM Claim__c
    WHERE Status__c = 'Under Review'
    AND SubmittedDate__c = LAST_N_DAYS:30
    LIMIT 200
];
```

### Field-Level Security
- Always respect FLS when querying
- Use WITH SECURITY_ENFORCED for dynamic SOQL
- Check CRUD permissions before DML operations

---

## Migration Notes

### From Legacy System
- Map legacy claim IDs to ExternalId__c field
- Preserve original submission dates
- Archive documents in Salesforce Files
- Maintain audit trail of migration

### Data Quality Rules
- No orphaned line items (enforce Master-Detail)
- Claim amounts always match line item totals
- Required documents based on claim type
- Valid policy numbers (external validation)