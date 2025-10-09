# Testing Standards

## Overview
Comprehensive testing guidelines for the Insurance Claims Management System to ensure code quality, reliability, and maintainability.

---

## Testing Requirements

### Code Coverage Goals

| Component Type | Minimum Coverage | Target Coverage |
|---------------|------------------|-----------------|
| Apex Classes | 85% | 95% |
| Triggers | 100% | 100% |
| Controllers | 85% | 90% |
| Service Classes | 90% | 95% |
| Utility Classes | 85% | 95% |

**Production Deployment Requirement**: Minimum 75% overall code coverage

---

## Test Class Naming and Organization

### Naming Convention

```apex
// Format: [ClassName]Test
ClaimService.cls → ClaimServiceTest.cls
ClaimController.cls → ClaimControllerTest.cls
PaymentGatewayService.cls → PaymentGatewayServiceTest.cls
```

### Test Class Structure

```apex
@isTest
private class ClaimServiceTest {
    
    // 1. Test Setup Method
    @TestSetup
    static void setup() {
        // Create common test data
    }
    
    // 2. Positive Test Cases
    @isTest
    static void testProcessClaimApproval_ValidClaim_Success() {
        // Test successful scenario
    }
    
    @isTest
    static void testProcessClaimApproval_AutoApprove_Success() {
        // Test auto-approval threshold
    }
    
    // 3. Negative Test Cases
    @isTest
    static void testProcessClaimApproval_InvalidStatus_ThrowsException() {
        // Test error handling
    }
    
    @isTest
    static void testProcessClaimApproval_NullClaim_ThrowsException() {
        // Test null handling
    }
    
    // 4. Boundary Test Cases
    @isTest
    static void testProcessClaimApproval_ThresholdBoundary_CorrectApproval() {
        // Test boundary conditions
    }
    
    // 5. Bulk Test Cases
    @isTest
    static void testProcessClaimApproval_Bulk200Records_Success() {
        // Test with 200 records
    }
}
```

---

## Test Data Factory Pattern

### Standard Test Data Factory

```apex
@isTest
public class TestDataFactory {
    
    /**
     * Create a single policy with default values
     */
    public static Policy__c createPolicy() {
        return createPolicy('POL-' + generateRandomNumber(), 'Active', 100000);
    }
    
    /**
     * Create a policy with custom values
     */
    public static Policy__c createPolicy(
        String policyNumber, 
        String status, 
        Decimal coverageAmount
    ) {
        return new Policy__c(
            PolicyNumber__c = policyNumber,
            Status__c = status,
            CoverageAmount__c = coverageAmount,
            Premium__c = 500,
            StartDate__c = System.today(),
            EndDate__c = System.today().addYears(1),
            Deductible__c = 1000
        );
    }
    
    /**
     * Create multiple policies
     */
    public static List<Policy__c> createPolicies(Integer count) {
        List<Policy__c> policies = new List<Policy__c>();
        for(Integer i = 0; i < count; i++) {
            policies.add(createPolicy(
                'POL-' + generateRandomNumber() + '-' + i,
                'Active',
                100000
            ));
        }
        return policies;
    }
    
    /**
     * Create a claim with custom values
     */
    public static Claim__c createClaim(
        Decimal amount, 
        String status
    ) {
        Policy__c policy = createPolicy();
        insert policy;
        
        return new Claim__c(
            Policy__c = policy.Id,
            PolicyNumber__c = policy.PolicyNumber__c,
            ClaimAmount__c = amount,
            Status__c = status,
            ClaimDescription__c = 'Test claim description',
            IncidentDate__c = System.today().addDays(-7),
            SubmittedDate__c = System.today()
        );
    }
    
    /**
     * Create claim with line items
     */
    public static Claim__c createClaimWithLineItems(
        Decimal amount, 
        Integer lineItemCount
    ) {
        Claim__c claim = createClaim(amount, 'New');
        insert claim;
        
        List<ClaimLineItem__c> items = new List<ClaimLineItem__c>();
        Decimal itemAmount = amount / lineItemCount;
        
        for(Integer i = 0; i < lineItemCount; i++) {
            items.add(new ClaimLineItem__c(
                Claim__c = claim.Id,
                ItemDescription__c = 'Test item ' + i,
                ItemAmount__c = itemAmount,
                Category__c = 'Property Damage',
                Quantity__c = 1
            ));
        }
        insert items;
        
        return claim;
    }
    
    /**
     * Create bulk claims for testing
     */
    public static List<Claim__c> createBulkClaims(
        Integer count, 
        Decimal amount, 
        String status
    ) {
        List<Policy__c> policies = createPolicies(count);
        insert policies;
        
        List<Claim__c> claims = new List<Claim__c>();
        for(Policy__c policy : policies) {
            claims.add(new Claim__c(
                Policy__c = policy.Id,
                PolicyNumber__c = policy.PolicyNumber__c,
                ClaimAmount__c = amount,
                Status__c = status,
                ClaimDescription__c = 'Bulk test claim',
                IncidentDate__c = System.today().addDays(-7),
                SubmittedDate__c = System.today()
            ));
        }
        
        return claims;
    }
    
    /**
     * Create test user with specific profile
     */
    public static User createTestUser(String profileName) {
        Profile profile = [SELECT Id FROM Profile WHERE Name = :profileName LIMIT 1];
        
        String uniqueName = 'test' + generateRandomNumber() + '@example.com';
        
        return new User(
            Alias = 'tuser',
            Email = uniqueName,
            EmailEncodingKey = 'UTF-8',
            LastName = 'Testing',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = profile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = uniqueName
        );
    }
    
    /**
     * Generate random number for unique identifiers
     */
    private static Integer generateRandomNumber() {
        return Integer.valueOf(Math.random() * 1000000);
    }
}
```

---

## Testing Patterns

### Pattern 1: Test Setup Method

**Use @TestSetup for data used by multiple test methods:**

```apex
@isTest
private class ClaimServiceTest {
    
    @TestSetup
    static void setup() {
        // Create data once, used by all test methods
        List<Claim__c> claims = TestDataFactory.createBulkClaims(5, 10000, 'New');
        insert claims;
    }
    
    @isTest
    static void testMethod1() {
        // Query data created in setup
        List<Claim__c> claims = [SELECT Id FROM Claim__c];
        System.assertEquals(5, claims.size());
    }
    
    @isTest
    static void testMethod2() {
        // Same data available here
        List<Claim__c> claims = [SELECT Id FROM Claim__c];
        System.assertEquals(5, claims.size());
    }
}
```

### Pattern 2: Test.startTest() and Test.stopTest()

**Always use Test boundaries to reset governor limits:**

```apex
@isTest
static void testBulkProcessing() {
    // Setup (counts toward governor limits)
    List<Claim__c> claims = TestDataFactory.createBulkClaims(200, 10000, 'Approved');
    insert claims;
    
    // Test.startTest() resets governor limits
    Test.startTest();
    
    // This code gets fresh governor limits
    ClaimService.processBulkApprovals(claims);
    
    // Test.stopTest() executes async operations synchronously
    Test.stopTest();
    
    // Verify results
    List<Claim__c> processedClaims = [
        SELECT Status__c FROM Claim__c WHERE Status__c = 'Paid'
    ];
    System.assertEquals(200, processedClaims.size());
}
```

### Pattern 3: Testing Exceptions

**Test both successful and error scenarios:**

```apex
@isTest
static void testProcessClaim_InvalidStatus_ThrowsException() {
    Claim__c claim = TestDataFactory.createClaim(10000, 'Paid');
    insert claim;
    
    Test.startTest();
    
    String errorMessage;
    try {
        ClaimService.processClaimApproval(claim.Id);
        System.assert(false, 'Expected ClaimProcessingException was not thrown');
    } catch(ClaimProcessingException e) {
        errorMessage = e.getMessage();
    }
    
    Test.stopTest();
    
    // Verify error message
    System.assertNotEquals(null, errorMessage);
    System.assert(errorMessage.contains('Cannot approve'), 
                  'Error message should explain the issue');
    
    // Verify error was logged
    List<ErrorLog__c> logs = [
        SELECT Id, ClassName__c, Severity__c
        FROM ErrorLog__c
        WHERE RecordId__c = :claim.Id
    ];
    System.assertEquals(1, logs.size());
}
```

### Pattern 4: Testing DML Operations

**Use Database methods with allOrNone parameter:**

```apex
@isTest
static void testBulkInsert_PartialFailure_HandlesGracefully() {
    List<Claim__c> claims = new List<Claim__c>();
    
    // Add valid claim
    claims.add(TestDataFactory.createClaim(10000, 'New'));
    
    // Add invalid claim (will fail validation)
    Claim__c invalidClaim = TestDataFactory.createClaim(-100, 'New'); // Negative amount
    claims.add(invalidClaim);
    
    Test.startTest();
    Database.SaveResult[] results = Database.insert(claims, false);
    Test.stopTest();
    
    // Verify partial success
    System.assertEquals(true, results[0].isSuccess());
    System.assertEquals(false, results[1].isSuccess());
    
    // Verify error handling
    Database.Error error = results[1].getErrors()[0];
    System.assertNotEquals(null, error.getMessage());
}
```

### Pattern 5: Testing Async Operations

#### Future Methods

```apex
@isTest
static void testFutureMethod_ProcessesClaims() {
    List<Claim__c> claims = TestDataFactory.createBulkClaims(5, 10000, 'Approved');
    insert claims;
    
    Set<Id> claimIds = new Set<Id>();
    for(Claim__c claim : claims) {
        claimIds.add(claim.Id);
    }
    
    Test.startTest();
    ClaimService.processApprovedClaimsAsync(claimIds);
    Test.stopTest(); // Forces future method to execute synchronously
    
    // Verify results
    List<Claim__c> processedClaims = [
        SELECT Status__c FROM Claim__c WHERE Id IN :claimIds
    ];
    
    for(Claim__c claim : processedClaims) {
        System.assertEquals('Paid', claim.Status__c);
    }
}
```

#### Queueable

```apex
@isTest
static void testQueueable_ProcessesClaims() {
    List<Claim__c> claims = TestDataFactory.createBulkClaims(5, 10000, 'Approved');
    insert claims;
    
    Test.startTest();
    System.enqueueJob(new PaymentProcessorQueueable(claims));
    Test.stopTest(); // Executes queueable synchronously
    
    // Verify
    for(Claim__c claim : [SELECT Status__c FROM Claim__c WHERE Id IN :claims]) {
        System.assertEquals('Paid', claim.Status__c);
    }
}
```

#### Batch Apex

```apex
@isTest
static void testBatch_ProcessesClaims() {
    List<Claim__c> claims = TestDataFactory.createBulkClaims(200, 10000, 'Approved');
    insert claims;
    
    Test.startTest();
    Database.executeBatch(new ClaimProcessingBatch(), 200);
    Test.stopTest(); // Executes entire batch synchronously
    
    // Verify
    Integer paidCount = [
        SELECT COUNT() FROM Claim__c WHERE Status__c = 'Paid'
    ];
    System.assertEquals(200, paidCount);
}
```

#### Scheduled Apex

```apex
@isTest
static void testScheduledJob_ExecutesSuccessfully() {
    Test.startTest();
    
    String cronExp = '0 0 0 * * ?'; // Daily at midnight
    String jobId = System.schedule(
        'Test Claim Processor',
        cronExp,
        new ClaimProcessorScheduler()
    );
    
    Test.stopTest();
    
    // Verify job was scheduled
    CronTrigger ct = [
        SELECT Id, CronExpression, State
        FROM CronTrigger
        WHERE Id = :jobId
    ];
    System.assertEquals(cronExp, ct.CronExpression);
}
```

---

## Testing HTTP Callouts

### Standard Mock Pattern

```apex
@isTest
global class PaymentGatewayMock implements HttpCalloutMock {
    
    private Integer statusCode;
    private String responseBody;
    private Boolean shouldFail;
    
    global PaymentGatewayMock(Integer statusCode, String responseBody) {
        this.statusCode = statusCode;
        this.responseBody = responseBody;
        this.shouldFail = false;
    }
    
    global PaymentGatewayMock(Boolean shouldFail) {
        this.shouldFail = shouldFail;
    }
    
    global HTTPResponse respond(HTTPRequest req) {
        if(shouldFail) {
            throw new System.CalloutException('Connection timeout');
        }
        
        HttpResponse res = new HttpResponse();
        res.setHeader('Content-Type', 'application/json');
        res.setStatusCode(statusCode);
        res.setBody(responseBody);
        return res;
    }
    
    // Factory methods
    global static PaymentGatewayMock success() {
        return new PaymentGatewayMock(200, JSON.serialize(new Map<String, Object>{
            'success' => true,
            'transactionId' => 'TXN-' + String.valueOf(Math.random() * 100000),
            'status' => 'completed',
            'message' => 'Payment processed successfully',
            'amountProcessed' => 10000,
            'timestamp' => System.now().format()
        }));
    }
    
    global static PaymentGatewayMock failure() {
        return new PaymentGatewayMock(400, JSON.serialize(new Map<String, Object>{
            'success' => false,
            'message' => 'Payment declined - insufficient funds'
        }));
    }
    
    global static PaymentGatewayMock serverError() {
        return new PaymentGatewayMock(500, JSON.serialize(new Map<String, Object>{
            'error' => 'Internal server error'
        }));
    }
    
    global static PaymentGatewayMock timeout() {
        return new PaymentGatewayMock(true);
    }
}
```

### Testing Callout

```apex
@isTest
static void testProcessPayment_Success() {
    Claim__c claim = TestDataFactory.createClaim(10000, 'Approved');
    insert claim;
    
    Test.setMock(HttpCalloutMock.class, PaymentGatewayMock.success());
    
    Test.startTest();
    PaymentGatewayService.PaymentResponse response = 
        PaymentGatewayService.processPayment(claim);
    Test.stopTest();
    
    // Verify response
    System.assertEquals(true, response.success);
    System.assertNotEquals(null, response.transactionId);
    
    // Verify integration log was created
    List<IntegrationLog__c> logs = [
        SELECT IsSuccess__c, StatusCode__c
        FROM IntegrationLog__c
        WHERE Claim__c = :claim.Id
    ];
    System.assertEquals(1, logs.size());
    System.assertEquals(true, logs[0].IsSuccess__c);
    System.assertEquals(200, logs[0].StatusCode__c);
}

@isTest
static void testProcessPayment_ServerError_Retries() {
    Claim__c claim = TestDataFactory.createClaim(10000, 'Approved');
    insert claim;
    
    Test.setMock(HttpCalloutMock.class, PaymentGatewayMock.serverError());
    
    Test.startTest();
    try {
        PaymentGatewayService.processPayment(claim);
        System.assert(false, 'Should have thrown exception');
    } catch(PaymentGatewayException e) {
        System.assert(e.getMessage().contains('after'));
    }
    Test.stopTest();
    
    // Verify retry attempts were logged
    Integer logCount = [
        SELECT COUNT() FROM IntegrationLog__c WHERE Claim__c = :claim.Id
    ];
    System.assertEquals(3, logCount, 'Should have 3 retry attempts');
}
```

### Multi-Callout Mock

```apex
@isTest
global class MultiCalloutMock implements HttpCalloutMock {
    
    private Map<String, HttpCalloutMock> mocksByEndpoint = 
        new Map<String, HttpCalloutMock>();
    
    global void addMock(String endpoint, HttpCalloutMock mock) {
        mocksByEndpoint.put(endpoint, mock);
    }
    
    global HTTPResponse respond(HTTPRequest req) {
        String endpoint = extractEndpoint(req.getEndpoint());
        
        if(mocksByEndpoint.containsKey(endpoint)) {
            return mocksByEndpoint.get(endpoint).respond(req);
        }
        
        // Default response
        HttpResponse res = new HttpResponse();
        res.setStatusCode(404);
        res.setBody('Not found');
        return res;
    }
    
    private String extractEndpoint(String fullEndpoint) {
        if(fullEndpoint.contains('://')) {
            Integer slashIndex = fullEndpoint.indexOf('/', 8);
            return fullEndpoint.substring(slashIndex);
        }
        return fullEndpoint;
    }
}

// Usage
@isTest
static void testMultipleIntegrations() {
    MultiCalloutMock multiMock = new MultiCalloutMock();
    multiMock.addMock('/api/v2/payments', PaymentGatewayMock.success());
    multiMock.addMock('/api/fraud-check', FraudServiceMock.lowRisk());
    
    Test.setMock(HttpCalloutMock.class, multiMock);
    
    // Test code that makes multiple callouts
}
```

---

## Testing Triggers

### Complete Trigger Coverage

```apex
@isTest
private class ClaimTriggerHandlerTest {
    
    @TestSetup
    static void setup() {
        // Common test data
        Policy__c policy = TestDataFactory.createPolicy();
        insert policy;
    }
    
    // Before Insert Tests
    @isTest
    static void testBeforeInsert_ValidClaim_AssignsApprovalLevel() {
        Policy__c policy = [SELECT Id, PolicyNumber__c FROM Policy__c LIMIT 1];
        
        Claim__c claim = new Claim__c(
            Policy__c = policy.Id,
            PolicyNumber__c = policy.PolicyNumber__c,
            ClaimAmount__c = 10000,
            Status__c = 'New',
            ClaimDescription__c = 'Test claim',
            IncidentDate__c = System.today()
        );
        
        Test.startTest();
        insert claim;
        Test.stopTest();
        
        claim = [SELECT ApprovalLevel__c, Status__c FROM Claim__c WHERE Id = :claim.Id];
        System.assertEquals('Manager', claim.ApprovalLevel__c);
        System.assertEquals('Under Review', claim.Status__c);
    }
    
    @isTest
    static void testBeforeInsert_SmallClaim_AutoApproved() {
        Policy__c policy = [SELECT Id, PolicyNumber__c FROM Policy__c LIMIT 1];
        
        Claim__c claim = new Claim__c(
            Policy__c = policy.Id,
            PolicyNumber__c = policy.PolicyNumber__c,
            ClaimAmount__c = 3000, // Under $5K threshold
            Status__c = 'New',
            ClaimDescription__c = 'Small claim',
            IncidentDate__c = System.today()
        );
        
        Test.startTest();
        insert claim;
        Test.stopTest();
        
        claim = [SELECT ApprovalLevel__c, Status__c FROM Claim__c WHERE Id = :claim.Id];
        System.assertEquals('Auto Approved', claim.ApprovalLevel__c);
        System.assertEquals('Approved', claim.Status__c);
    }
    
    // Before Update Tests
    @isTest
    static void testBeforeUpdate_InvalidStatusTransition_AddError() {
        Claim__c claim = TestDataFactory.createClaim(10000, 'Paid');
        insert claim;
        
        claim.Status__c = 'New'; // Invalid transition
        
        Test.startTest();
        try {
            update claim;
            System.assert(false, 'Should have thrown exception');
        } catch(DmlException e) {
            System.assert(e.getMessage().contains('Cannot change status'));
        }
        Test.stopTest();
    }
    
    // After Update Tests
    @isTest
    static void testAfterUpdate_StatusApproved_TriggersPayment() {
        Claim__c claim = TestDataFactory.createClaim(10000, 'Under Review');
        insert claim;
        
        Test.setMock(HttpCalloutMock.class, PaymentGatewayMock.success());
        
        claim.Status__c = 'Approved';
        claim.ApprovedDate__c = System.today();
        
        Test.startTest();
        update claim;
        Test.stopTest();
        
        // Verify payment processing was triggered
        List<IntegrationLog__c> logs = [
            SELECT IsSuccess__c FROM IntegrationLog__c WHERE Claim__c = :claim.Id
        ];
        System.assertEquals(1, logs.size());
    }
    
    // Bulk Tests
    @isTest
    static void testTrigger_Bulk200Records_Success() {
        List<Claim__c> claims = TestDataFactory.createBulkClaims(200, 10000, 'New');
        
        Test.startTest();
        insert claims; // Should handle all 200 without hitting limits
        Test.stopTest();
        
        List<Claim__c> insertedClaims = [
            SELECT ApprovalLevel__c FROM Claim__c WHERE Id IN :claims
        ];
        System.assertEquals(200, insertedClaims.size());
        
        for(Claim__c claim : insertedClaims) {
            System.assertEquals('Manager', claim.ApprovalLevel__c);
        }
    }
}
```

---

## Testing Security

### Testing Sharing Rules

```apex
@isTest
static void testSharingRules_UserCannotAccessOtherClaims() {
    // Create user with limited access
    User testUser = TestDataFactory.createTestUser('Standard User');
    insert testUser;
    
    // Create claim as system admin
    Claim__c claim = TestDataFactory.createClaim(10000, 'New');
    insert claim;
    
    // Test as limited user
    System.runAs(testUser) {
        List<Claim__c> accessibleClaims = [
            SELECT Id FROM Claim__c WHERE Id = :claim.Id
        ];
        
        // User should not see claim due to sharing rules
        System.assertEquals(0, accessibleClaims.size());
    }
}
```

### Testing Field-Level Security

```apex
@isTest
static void testFieldLevelSecurity_UserCannotUpdateSensitiveField() {
    User testUser = TestDataFactory.createTestUser('Standard User');
    insert testUser;
    
    Claim__c claim = TestDataFactory.createClaim(10000, 'New');
    insert claim;
    
    System.runAs(testUser) {
        claim.PaymentTransactionId__c = 'TXN-12345'; // Sensitive field
        
        try {
            update claim;
            System.assert(false, 'Should have thrown exception');
        } catch(DmlException e) {
            System.assert(e.getMessage().contains('insufficient access'));
        }
    }
}
```

---

## Test Assertions

### Standard Assertions

```apex
// Equality
System.assertEquals(expected, actual, 'Error message');
System.assertNotEquals(unexpected, actual);

// Boolean
System.assert(condition, 'Error message');

// Null checks
System.assertNotEquals(null, value);

// Collection size
System.assertEquals(5, myList.size());

// String contains
System.assert(errorMessage.contains('expected text'));
```

### Custom Assertions

```apex
public class TestAssertions {
    
    public static void assertClaimStatus(Claim__c claim, String expectedStatus) {
        System.assertEquals(
            expectedStatus, 
            claim.Status__c,
            'Claim ' + claim.ClaimNumber__c + ' should have status ' + expectedStatus
        );
    }
    
    public static void assertErrorLogged(Id recordId, String expectedClass) {
        List<ErrorLog__c> logs = [
            SELECT ClassName__c FROM ErrorLog__c WHERE RecordId__c = :recordId
        ];
        
        System.assert(!logs.isEmpty(), 'Error should be logged');
        System.assertEquals(expectedClass, logs[0].ClassName__c);
    }
}
```

---

## Test Debugging

### Using System.debug

```apex
@isTest
static void testDebugExample() {
    Claim__c claim = TestDataFactory.createClaim(10000, 'New');
    
    System.debug('Claim before insert: ' + claim);
    System.debug(LoggingLevel.ERROR, 'Important debug info');
    
    insert claim;
    
    System.debug('Claim ID after insert: ' + claim.Id);
}
```

### Checking Limits

```apex
@isTest
static void testGovernorLimits() {
    Test.startTest();
    
    // Run code
    ClaimService.processLargeBatch();
    
    Test.stopTest();
    
    // Check limits used
    System.debug('SOQL Queries: ' + Limits.getQueries() + '/' + Limits.getLimitQueries());
    System.debug('DML Statements: ' + Limits.getDmlStatements() + '/' + Limits.getLimitDmlStatements());
    System.debug('Heap Size: ' + Limits.getHeapSize() + '/' + Limits.getLimitHeapSize());
    
    // Assert within limits
    System.assert(Limits.getQueries() < 100, 'Too many SOQL queries');
}
```

---

## Best Practices Summary

### ✅ DO

- Use @TestSetup for common test data
- Test positive, negative, and boundary cases
- Always use Test.startTest() and Test.stopTest()
- Test bulk operations with 200 records
- Mock all HTTP callouts
- Test all trigger contexts
- Verify error logging
- Use TestDataFactory for all test data
- Assert expected results explicitly
- Test security and sharing rules

### ❌ DON'T

- Use @SeeAllData=true (exception: testing standard objects)
- Hard-code IDs in tests
- Rely on existing data in org
- Skip negative test cases
- Test only single records
- Make actual HTTP callouts
- Ignore governor limits
- Use System.runAs() unnecessarily
- Create test data inline (use factory)
- Skip assertions

---

## Test Coverage Report

### Running Tests

```bash
# Run all tests
sfdx force:apex:test:run --testlevel RunLocalTests --resultformat human

# Run specific test class
sfdx force:apex:test:run --classnames ClaimServiceTest --resultformat human

# Run tests with code coverage
sfdx force:apex:test:run --testlevel RunLocalTests --codecoverage --resultformat human
```

### Minimum Coverage Requirements

| Environment | Requirement |
|-------------|-------------|
| Sandbox | 75% |
| Production | 75% |
| Release Goal | 85%+ |

### Coverage Tracking

Track coverage in every sprint:
- Service classes: 95%+
- Controllers: 90%+
- Utilities: 90%+
- Triggers: 100%
- Overall: 85%+