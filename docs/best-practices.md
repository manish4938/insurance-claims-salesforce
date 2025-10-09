# Salesforce Development Best Practices

## Overview
This document defines coding standards, design patterns, and best practices for the Insurance Claims Management System.

---

## Code Organization

### Package Structure

```
force-app/main/default/
├── classes/
│   ├── controllers/          # LWC and Aura controllers
│   ├── services/             # Business logic services
│   ├── handlers/             # Trigger handlers
│   ├── utilities/            # Helper and utility classes
│   ├── models/               # Data wrapper classes
│   ├── integrations/         # External system integrations
│   ├── exceptions/           # Custom exception classes
│   └── tests/                # Test classes
├── triggers/                 # One trigger per object
├── lwc/                      # Lightning Web Components
├── aura/                     # Aura Components (legacy)
├── objects/                  # Custom objects and fields
├── flows/                    # Screen flows and autolaunched flows
└── permissionsets/          # Permission sets
```

---

## Naming Conventions

### Classes

| Type | Pattern | Example |
|------|---------|---------|
| Controller | `[Object]Controller` | `ClaimController` |
| Service | `[Object]Service` | `ClaimService` |
| Trigger Handler | `[Object]TriggerHandler` | `ClaimTriggerHandler` |
| Utility | `[Purpose]Utility` | `ValidationUtility` |
| Test Class | `[ClassName]Test` | `ClaimServiceTest` |
| Exception | `[Purpose]Exception` | `ClaimValidationException` |
| Batch | `[Purpose]Batch` | `ClaimProcessingBatch` |
| Queueable | `[Purpose]Queueable` | `PaymentProcessorQueueable` |
| Schedulable | `[Purpose]Scheduler` | `DailyClaimProcessorScheduler` |

### Methods

Use verb + noun pattern with camelCase:

```apex
// ✅ GOOD
public static void validateClaimAmount(Claim__c claim)
public static Decimal calculateTotalClaim(List<ClaimLineItem__c> items)
public static void processClaimApproval(Id claimId)
public static List<Claim__c> getApprovedClaimsByDate(Date approvalDate)

// ❌ BAD
public static void validate(Claim__c c)
public static Decimal calc(List<ClaimLineItem__c> items)
public static void process(Id id)
public static List<Claim__c> getClaims(Date d)
```

### Variables

```apex
// ✅ GOOD - Descriptive names
Decimal totalClaimAmount = 0;
List<Claim__c> approvedClaims = new List<Claim__c>();
Map<Id, Claim__c> claimsByPolicyId = new Map<Id, Claim__c>();

// ✅ ACCEPTABLE - Short names in loops
for(Integer i = 0; i < items.size(); i++) {
    ClaimLineItem__c item = items[i];
}

// ❌ BAD - Unclear abbreviations
Decimal tca = 0;
List<Claim__c> ac = new List<Claim__c>();
Map<Id, Claim__c> cbpi = new Map<Id, Claim__c>();
```

### Constants

Use UPPER_SNAKE_CASE:

```apex
private static final Decimal AUTO_APPROVE_THRESHOLD = 5000;
private static final Integer MAX_RETRY_ATTEMPTS = 3;
private static final String PAYMENT_STATUS_PAID = 'Paid';
```

---

## Trigger Pattern

### One Trigger Per Object

**ALWAYS use this pattern - one trigger calling a handler:**

```apex
// ClaimTrigger.trigger
trigger ClaimTrigger on Claim__c (
    before insert, before update, before delete,
    after insert, after update, after delete, after undelete
) {
    new ClaimTriggerHandler().run();
}
```

### Trigger Handler Base Class

```apex
public virtual class TriggerHandler {
    
    // Context variables
    protected Boolean isBefore;
    protected Boolean isAfter;
    protected Boolean isInsert;
    protected Boolean isUpdate;
    protected Boolean isDelete;
    protected Boolean isUndelete;
    
    public TriggerHandler() {
        this.isBefore = Trigger.isBefore;
        this.isAfter = Trigger.isAfter;
        this.isInsert = Trigger.isInsert;
        this.isUpdate = Trigger.isUpdate;
        this.isDelete = Trigger.isDelete;
        this.isUndelete = Trigger.isUndelete;
    }
    
    public void run() {
        if(this.isBefore) {
            if(this.isInsert) {
                this.beforeInsert();
            } else if(this.isUpdate) {
                this.beforeUpdate();
            } else if(this.isDelete) {
                this.beforeDelete();
            }
        } else if(this.isAfter) {
            if(this.isInsert) {
                this.afterInsert();
            } else if(this.isUpdate) {
                this.afterUpdate();
            } else if(this.isDelete) {
                this.afterDelete();
            } else if(this.isUndelete) {
                this.afterUndelete();
            }
        }
    }
    
    // Virtual methods to be overridden
    protected virtual void beforeInsert() {}
    protected virtual void beforeUpdate() {}
    protected virtual void beforeDelete() {}
    protected virtual void afterInsert() {}
    protected virtual void afterUpdate() {}
    protected virtual void afterDelete() {}
    protected virtual void afterUndelete() {}
}
```

### Trigger Handler Implementation

```apex
public with sharing class ClaimTriggerHandler extends TriggerHandler {
    
    private List<Claim__c> newClaims;
    private List<Claim__c> oldClaims;
    private Map<Id, Claim__c> newClaimMap;
    private Map<Id, Claim__c> oldClaimMap;
    
    public ClaimTriggerHandler() {
        super();
        this.newClaims = (List<Claim__c>) Trigger.new;
        this.oldClaims = (List<Claim__c>) Trigger.old;
        this.newClaimMap = (Map<Id, Claim__c>) Trigger.newMap;
        this.oldClaimMap = (Map<Id, Claim__c>) Trigger.oldMap;
    }
    
    protected override void beforeInsert() {
        ClaimService.validateClaimAmounts(newClaims);
        ClaimService.assignApprovalLevel(newClaims);
    }
    
    protected override void beforeUpdate() {
        ClaimService.validateClaimAmounts(newClaims);
        ClaimService.validateStatusTransitions(newClaims, oldClaimMap);
    }
    
    protected override void afterUpdate() {
        // Collect approved claims
        List<Claim__c> approvedClaims = new List<Claim__c>();
        for(Claim__c claim : newClaims) {
            Claim__c oldClaim = oldClaimMap.get(claim.Id);
            if(claim.Status__c == 'Approved' && oldClaim.Status__c != 'Approved') {
                approvedClaims.add(claim);
            }
        }
        
        if(!approvedClaims.isEmpty()) {
            ClaimService.processApprovedClaims(approvedClaims);
        }
    }
}
```

---

## Bulkification

### ALWAYS Write Bulk-Safe Code

```apex
// ✅ GOOD - Bulk pattern
public static void updateClaimStatus(List<Claim__c> claims) {
    // Collect IDs
    Set<Id> claimIds = new Set<Id>();
    for(Claim__c claim : claims) {
        claimIds.add(claim.Id);
    }
    
    // Single SOQL query
    Map<Id, List<ClaimLineItem__c>> lineItemsByClaim = new Map<Id, List<ClaimLineItem__c>>();
    for(ClaimLineItem__c item : [
        SELECT Id, Claim__c, ItemAmount__c 
        FROM ClaimLineItem__c 
        WHERE Claim__c IN :claimIds
    ]) {
        if(!lineItemsByClaim.containsKey(item.Claim__c)) {
            lineItemsByClaim.put(item.Claim__c, new List<ClaimLineItem__c>());
        }
        lineItemsByClaim.get(item.Claim__c).add(item);
    }
    
    // Process in memory
    List<Claim__c> claimsToUpdate = new List<Claim__c>();
    for(Claim__c claim : claims) {
        List<ClaimLineItem__c> items = lineItemsByClaim.get(claim.Id);
        if(items != null) {
            Decimal total = 0;
            for(ClaimLineItem__c item : items) {
                total += item.ItemAmount__c;
            }
            
            if(claim.ClaimAmount__c == total) {
                claim.Status__c = 'Validated';
                claimsToUpdate.add(claim);
            }
        }
    }
    
    // Single DML operation
    if(!claimsToUpdate.isEmpty()) {
        update claimsToUpdate;
    }
}

// ❌ BAD - Not bulk-safe
public static void updateClaimStatus(List<Claim__c> claims) {
    for(Claim__c claim : claims) {
        // SOQL in loop!
        List<ClaimLineItem__c> items = [
            SELECT ItemAmount__c 
            FROM ClaimLineItem__c 
            WHERE Claim__c = :claim.Id
        ];
        
        Decimal total = 0;
        for(ClaimLineItem__c item : items) {
            total += item.ItemAmount__c;
        }
        
        if(claim.ClaimAmount__c == total) {
            claim.Status__c = 'Validated';
            // DML in loop!
            update claim;
        }
    }
}
```

---

## SOQL Best Practices

### Query Optimization

```apex
// ✅ GOOD - Selective query with required fields only
List<Claim__c> claims = [
    SELECT Id, ClaimNumber__c, ClaimAmount__c, Status__c
    FROM Claim__c
    WHERE Status__c = 'Under Review'
    AND SubmittedDate__c = LAST_N_DAYS:30
    AND ClaimAmount__c > 10000
    LIMIT 200
];

// ✅ GOOD - Using indexed fields for filtering
List<Claim__c> claims = [
    SELECT Id, ClaimNumber__c
    FROM Claim__c
    WHERE ClaimNumber__c = :claimNumber // External ID field (indexed)
    LIMIT 1
];

// ❌ BAD - Non-selective query
List<Claim__c> claims = [
    SELECT Id, (SELECT Id FROM ClaimLineItems__r), 
           (SELECT Id FROM ClaimDocuments__r)
    FROM Claim__c
    // No WHERE clause, returns all records!
];

// ❌ BAD - Querying unnecessary fields
List<Claim__c> claims = [
    SELECT Id, ClaimNumber__c, ClaimAmount__c, Status__c,
           ClaimDescription__c, RejectionReason__c, // Not needed
           CreatedBy.Name, CreatedBy.Email, // Not needed
           Policy__r.Id, Policy__r.PolicyNumber__c // Not needed
    FROM Claim__c
    WHERE Id = :claimId
];
```

### Relationship Queries

```apex
// ✅ GOOD - Parent to child (1 to many)
List<Claim__c> claims = [
    SELECT Id, ClaimNumber__c,
        (SELECT Id, ItemDescription__c, ItemAmount__c 
         FROM ClaimLineItems__r
         ORDER BY ItemAmount__c DESC)
    FROM Claim__c
    WHERE Id IN :claimIds
];

// ✅ GOOD - Child to parent (many to 1)
List<ClaimLineItem__c> items = [
    SELECT Id, ItemAmount__c,
        Claim__r.ClaimNumber__c,
        Claim__r.Status__c
    FROM ClaimLineItem__c
    WHERE Claim__c IN :claimIds
];

// ❌ BAD - Nested queries beyond 1 level
List<Policy__c> policies = [
    SELECT Id,
        (SELECT Id,
            (SELECT Id FROM ClaimLineItems__r) // Don't nest this deep!
         FROM Claims__r)
    FROM Policy__c
];
```

### Using FOR Loops with SOQL

```apex
// ✅ GOOD - For large datasets
for(Claim__c claim : [
    SELECT Id, ClaimAmount__c, Status__c
    FROM Claim__c
    WHERE Status__c = 'Approved'
]) {
    // Process one claim at a time
    // Prevents heap size limit
}

// ❌ BAD - For large datasets
List<Claim__c> claims = [
    SELECT Id, ClaimAmount__c, Status__c
    FROM Claim__c
    WHERE Status__c = 'Approved'
]; // Loads all claims into memory at once!

for(Claim__c claim : claims) {
    // Process
}
```

---

## DML Best Practices

### Partial Success Pattern

```apex
// ✅ GOOD - Handle partial success
public static void processClaimUpdates(List<Claim__c> claims) {
    Database.SaveResult[] results = Database.update(claims, false); // Allow partial success
    
    List<ErrorLogService.ErrorLogEntry> errors = new List<ErrorLogService.ErrorLogEntry>();
    
    for(Integer i = 0; i < results.size(); i++) {
        if(!results[i].isSuccess()) {
            Database.Error error = results[i].getErrors()[0];
            errors.add(new ErrorLogService.ErrorLogEntry(
                new DmlException(error.getMessage()),
                claims[i].Id,
                'ClaimService.processClaimUpdates',
                ErrorLogService.Severity.MEDIUM
            ));
        }
    }
    
    if(!errors.isEmpty()) {
        ErrorLogService.logErrors(errors);
    }
}

// ❌ BAD - All-or-nothing fails entire batch
public static void processClaimUpdates(List<Claim__c> claims) {
    update claims; // One failure = entire operation fails
}
```

### Upsert Pattern

```apex
// ✅ GOOD - Using external ID for upsert
List<Claim__c> claims = new List<Claim__c>();
for(ExternalClaimData data : externalData) {
    claims.add(new Claim__c(
        ClaimNumber__c = data.claimNumber, // External ID field
        ClaimAmount__c = data.amount,
        Status__c = data.status
    ));
}

Database.upsert(claims, Claim__c.ClaimNumber__c, false);
```

---

## Security Best Practices

### Sharing Keywords

```apex
// ✅ GOOD - Explicit sharing
public with sharing class ClaimController {
    // Respects user's sharing rules
}

// ✅ GOOD - Explicit intent to bypass sharing
public without sharing class ClaimBatchProcessor {
    // System context - use carefully
}

// ⚠️ WARNING - Inherited sharing (use with caution)
public inherited sharing class ClaimUtility {
    // Inherits from calling class
}

// ❌ BAD - No sharing keyword (defaults to without sharing)
public class ClaimService {
    // Unclear intent
}
```

### Field-Level Security

```apex
// ✅ GOOD - Check FLS before DML
public static void createClaim(Claim__c claim) {
    // Check CREATE permission
    if(!Schema.sObjectType.Claim__c.isCreateable()) {
        throw new ClaimValidationException('Insufficient permissions to create claims');
    }
    
    // Check field permissions
    if(!Schema.sObjectType.Claim__c.fields.ClaimAmount__c.isCreateable()) {
        throw new ClaimValidationException('Insufficient permissions for ClaimAmount field');
    }
    
    insert claim;
}

// ✅ GOOD - Strip inaccessible fields
public static List<Claim__c> getClaims() {
    List<Claim__c> claims = [
        SELECT Id, ClaimNumber__c, ClaimAmount__c, Status__c
        FROM Claim__c
        WHERE Status__c = 'Approved'
    ];
    
    // Remove fields user can't access
    SObjectAccessDecision decision = Security.stripInaccessible(
        AccessType.READABLE,
        claims
    );
    
    return decision.getRecords();
}
```

### SOQL Injection Prevention

```apex
// ✅ GOOD - Using bind variables
public static List<Claim__c> getClaimsByStatus(String status) {
    return [
        SELECT Id, ClaimNumber__c
        FROM Claim__c
        WHERE Status__c = :status // Safe - bind variable
    ];
}

// ❌ BAD - String concatenation (SOQL injection risk)
public static List<Claim__c> getClaimsByStatus(String status) {
    String query = 'SELECT Id FROM Claim__c WHERE Status__c = \'' + status + '\'';
    return Database.query(query); // NEVER DO THIS!
}

// ✅ GOOD - If dynamic SOQL needed, validate/escape input
public static List<Claim__c> getDynamicClaims(String status) {
    // Whitelist allowed values
    Set<String> allowedStatuses = new Set<String>{
        'New', 'Under Review', 'Approved', 'Rejected', 'Paid'
    };
    
    if(!allowedStatuses.contains(status)) {
        throw new ClaimValidationException('Invalid status value');
    }
    
    String query = 'SELECT Id FROM Claim__c WHERE Status__c = \'' + 
                   String.escapeSingleQuotes(status) + '\'';
    return Database.query(query);
}
```

---

## Testing Best Practices

### Test Data Creation

```apex
// ✅ GOOD - Use @TestSetup for common data
@isTest
private class ClaimServiceTest {
    
    @TestSetup
    static void setup() {
        // Create test data once for all test methods
        Policy__c policy = new Policy__c(
            PolicyNumber__c = 'POL-12345',
            Status__c = 'Active',
            CoverageAmount__c = 100000
        );
        insert policy;
        
        List<Claim__c> claims = new List<Claim__c>();
        for(Integer i = 0; i < 5; i++) {
            claims.add(new Claim__c(
                Policy__c = policy.Id,
                PolicyNumber__c = policy.PolicyNumber__c,
                ClaimAmount__c = 10000 + (i * 1000),
                Status__c = 'New'
            ));
        }
        insert claims;
    }
    
    @isTest
    static void testProcessApproval() {
        // Query test data created in setup
        Claim__c claim = [SELECT Id, Status__c FROM Claim__c LIMIT 1];
        
        Test.startTest();
        ClaimService.processClaimApproval(claim.Id);
        Test.stopTest();
        
        claim = [SELECT Status__c FROM Claim__c WHERE Id = :claim.Id];
        System.assertEquals('Approved', claim.Status__c);
    }
}
```

### Test Coverage Requirements

```apex
// ✅ GOOD - Test both positive and negative scenarios
@isTest
static void testValidateClaimAmount_Valid() {
    // Test successful validation
}

@isTest
static void testValidateClaimAmount_Invalid() {
    // Test validation failure
}

@isTest
static void testValidateClaimAmount_Null() {
    // Test null handling
}

@isTest
static void testValidateClaimAmount_Bulk() {
    // Test with 200 records
}
```

### Mock HTTP Callouts

```apex
// ✅ GOOD - Always mock external callouts
@isTest
static void testPaymentProcessing() {
    Claim__c claim = TestDataFactory.createClaim(10000, 'Approved');
    insert claim;
    
    // Mock the HTTP callout
    Test.setMock(HttpCalloutMock.class, PaymentGatewayMock.success());
    
    Test.startTest();
    PaymentGatewayService.processPayment(claim);
    Test.stopTest();
    
    // Verify result
}
```

---

## Asynchronous Apex Best Practices

### Future Methods

```apex
// ✅ GOOD - Pass IDs, not sObjects
@future(callout=true)
public static void processClaimAsync(Set<Id> claimIds) {
    List<Claim__c> claims = [
        SELECT Id, ClaimAmount__c, Status__c
        FROM Claim__c
        WHERE Id IN :claimIds
    ];
    
    // Process claims
}

// ❌ BAD - Can't pass sObjects to future methods
@future(callout=true)
public static void processClaimAsync(List<Claim__c> claims) {
    // This won't compile!
}
```

### Queueable (Preferred)

```apex
// ✅ GOOD - Use Queueable for complex async operations
public class ClaimProcessorQueueable implements Queueable, Database.AllowsCallouts {
    
    private List<Claim__c> claims;
    
    public ClaimProcessorQueueable(List<Claim__c> claims) {
        this.claims = claims;
    }
    
    public void execute(QueueableContext context) {
        for(Claim__c claim : claims) {
            try {
                PaymentGatewayService.processPayment(claim);
            } catch(Exception e) {
                ErrorLogService.logError(
                    e,
                    claim.Id,
                    'ClaimProcessorQueueable.execute',
                    ErrorLogService.Severity.HIGH
                );
            }
        }
    }
}

// Usage
System.enqueueJob(new ClaimProcessorQueueable(claims));
```

---

## Governor Limits Awareness

### SOQL Limits (100 queries per transaction)

```apex
// ✅ GOOD - Single query with relationship
Map<Id, Policy__c> policiesWithClaims = new Map<Id, Policy__c>([
    SELECT Id, PolicyNumber__c,
        (SELECT Id, ClaimAmount__c FROM Claims__r)
    FROM Policy__c
    WHERE Id IN :policyIds
]);

// ❌ BAD - N+1 query problem
for(Policy__c policy : policies) {
    List<Claim__c> claims = [
        SELECT Id FROM Claim__c WHERE Policy__c = :policy.Id
    ]; // Query inside loop!
}
```

### DML Limits (150 statements per transaction)

```apex
// ✅ GOOD - Batch DML operations
List<Claim__c> allClaims = new List<Claim__c>();
allClaims.addAll(claimsSet1);
allClaims.addAll(claimsSet2);
update allClaims; // Single DML

// ❌ BAD - Multiple DML operations
update claimsSet1;
update claimsSet2; // Use only if required for separate error handling
```

### Heap Size (6MB synchronous, 12MB async)

```apex
// ✅ GOOD - Process in chunks
public void processLargeDataset() {
    Integer batchSize = 200;
    for(Integer i = 0; i < totalRecords; i += batchSize) {
        // Process chunk
        Database.executeBatch(new MyBatch(), batchSize);
    }
}

// ❌ BAD - Load everything into memory
List<Claim__c> allClaims = [SELECT Id, ClaimDescription__c FROM Claim__c];
// If millions of records, this will exceed heap limit!
```

---

## Documentation Standards

### Class Headers

```apex
/**
 * Service class for claim processing business logic
 * 
 * @author Development Team
 * @date 2024-01-15
 * @group Services
 * @description Handles validation, approval, and payment processing for claims
 */
public with sharing class ClaimService {
    // Implementation
}
```

### Method Documentation

```apex
/**
 * Process claim approval and trigger payment
 * 
 * @param claimId The ID of the claim to approve
 * @throws ClaimValidationException if claim is not in valid state
 * @throws ClaimProcessingException if approval process fails
 * @example
 * ClaimService.processClaimApproval(claimId);
 */
public static void processClaimApproval(Id claimId) {
    // Implementation
}
```

### Inline Comments

```apex
// ✅ GOOD - Explain why, not what
// Business rule: Claims over $25K require senior manager approval
if(claim.ClaimAmount__c > 25000) {
    claim.ApprovalLevel__c = 'Senior Manager';
}

// ❌ BAD - Obvious comments
// Set approval level to senior manager
claim.ApprovalLevel__c = 'Senior Manager';
```

---

## Lightning Web Components Best Practices

### Component Structure

```javascript
// claimSummary.js
import { LightningElement, api, wire } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import approveClaim from '@salesforce/apex/ClaimController.approveClaim';

const FIELDS = [
    'Claim__c.ClaimNumber__c',
    'Claim__c.ClaimAmount__c',
    'Claim__c.Status__c'
];

export default class ClaimSummary extends LightningElement {
    @api recordId;
    
    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    claim;
    
    get claimNumber() {
        return this.claim.data?.fields.ClaimNumber__c.value;
    }
    
    get claimAmount() {
        return this.claim.data?.fields.ClaimAmount__c.value;
    }
    
    handleApprove() {
        approveClaim({ claimId: this.recordId })
            .then(() => {
                this.showToast('Success', 'Claim approved successfully', 'success');
            })
            .catch(error => {
                this.showToast('Error', error.body.message, 'error');
            });
    }
    
    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
```

---

## Performance Optimization

### Selective Queries

```apex
// ✅ GOOD - Use indexed fields
WHERE ClaimNumber__c = :claimNumber // External ID (indexed)
WHERE Id = :claimId // Primary key (indexed)
WHERE Status__c = 'Approved' AND CreatedDate = LAST_N_DAYS:30 // Both indexed

// ❌ BAD - Non-selective filters
WHERE ClaimDescription__c LIKE '%accident%' // Long text field, not indexed
WHERE YEAR(CreatedDate) = 2024 // Function on indexed field prevents index use
```

### Caching Strategies

```apex
// ✅ GOOD - Cache static data
private static Map<String, IntegrationSetting__mdt> settingsCache;

public static IntegrationSetting__mdt getSetting(String name) {
    if(settingsCache == null) {
        settingsCache = new Map<String, IntegrationSetting__mdt>();
        for(IntegrationSetting__mdt setting : [
            SELECT DeveloperName, Endpoint__c, Timeout__c
            FROM IntegrationSetting__mdt
        ]) {
            settingsCache.put(setting.DeveloperName, setting);
        }
    }
    return settingsCache.get(name);
}
```

---

## Summary: Golden Rules

1. **Always bulkify** - Support 200 records minimum
2. **One trigger per object** - Use handler pattern
3. **No SOQL/DML in loops** - Query/DML outside loops
4. **Use explicit sharing** - `with sharing` by default
5. **Validate inputs** - Check nulls and business rules
6. **Log errors** - Use ErrorLogService consistently
7. **Test thoroughly** - 85%+ coverage, test edge cases
8. **Document code** - Class headers and complex logic
9. **Follow naming conventions** - Consistent and clear
10. **Monitor governor limits** - Stay well below limits