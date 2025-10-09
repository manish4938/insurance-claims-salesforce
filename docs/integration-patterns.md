# Integration Patterns

## Overview
This document defines standard patterns for integrating with external systems in the Insurance Claims Management System.

---

## Integration Architecture

### External Systems

Our Salesforce org integrates with:

1. **Payment Gateway API** - Process claim payments
2. **Fraud Detection Service** - Real-time fraud screening
3. **Document Management System** - Store/retrieve claim documents
4. **Policy Management System** - Validate policy information
5. **Notification Service** - Send SMS/Email notifications
6. **Data Warehouse** - Analytics and reporting

---

## Authentication Standards

### Named Credentials

**ALWAYS use Named Credentials - never hardcode credentials**

```apex
// ✅ CORRECT: Using Named Credential
HttpRequest req = new HttpRequest();
req.setEndpoint('callout:PaymentGateway/api/v2/payments');

// ❌ WRONG: Hardcoded endpoint
HttpRequest req = new HttpRequest();
req.setEndpoint('https://api.payment.com/v2/payments');
```

### Named Credential Configuration

**Naming Convention**: `[SystemName]` or `[SystemName]_[Environment]`

Examples:
- `PaymentGateway`
- `PaymentGateway_Sandbox`
- `FraudDetectionService`
- `DocumentManagementSystem`

**Security Settings**:
- ✅ Use OAuth 2.0 when available
- ✅ Enable "Generate Authorization Header"
- ✅ Store credentials in Protected Custom Settings
- ✅ Use Per-User authentication for sensitive operations

---

## HTTP Callout Pattern

### Standard Service Class Structure

```apex
public class PaymentGatewayService {
    
    // Constants
    private static final String NAMED_CREDENTIAL = 'callout:PaymentGateway';
    private static final Integer TIMEOUT_MS = 30000; // 30 seconds
    private static final Integer MAX_RETRIES = 3;
    
    /**
     * Process payment for approved claim
     * @param claim The claim to process payment for
     * @return PaymentResponse with transaction details
     * @throws PaymentGatewayException if payment fails
     */
    public static PaymentResponse processPayment(Claim__c claim) {
        // Input validation
        if(claim == null || claim.Id == null) {
            throw new PaymentGatewayException('Invalid claim provided');
        }
        
        if(claim.ClaimAmount__c == null || claim.ClaimAmount__c <= 0) {
            throw new PaymentGatewayException('Invalid claim amount');
        }
        
        // Build request
        HttpRequest req = buildPaymentRequest(claim);
        
        // Execute with retry logic
        HttpResponse res = executeWithRetry(req, claim.Id);
        
        // Parse and return response
        return parsePaymentResponse(res, claim.Id);
    }
    
    /**
     * Build HTTP request for payment
     */
    private static HttpRequest buildPaymentRequest(Claim__c claim) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(NAMED_CREDENTIAL + '/api/v2/payments');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Accept', 'application/json');
        req.setHeader('X-Request-ID', generateRequestId());
        req.setTimeout(TIMEOUT_MS);
        
        // Build payload
        PaymentRequest payloadObj = new PaymentRequest();
        payloadObj.claimId = claim.Id;
        payloadObj.amount = claim.ClaimAmount__c;
        payloadObj.currency = 'USD';
        payloadObj.policyNumber = claim.PolicyNumber__c;
        payloadObj.timestamp = System.now().format('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
        
        req.setBody(JSON.serialize(payloadObj));
        
        return req;
    }
    
    /**
     * Execute HTTP callout with retry logic
     */
    private static HttpResponse executeWithRetry(HttpRequest req, Id recordId) {
        Http http = new Http();
        HttpResponse res = null;
        Integer attemptCount = 0;
        Exception lastException = null;
        
        while(attemptCount < MAX_RETRIES) {
            attemptCount++;
            
            try {
                // Make callout
                Long startTime = System.currentTimeMillis();
                res = http.send(req);
                Long duration = System.currentTimeMillis() - startTime;
                
                // Log integration
                IntegrationLogService.logCallout(
                    req,
                    res,
                    recordId,
                    'Payment Gateway',
                    attemptCount,
                    duration
                );
                
                // Success - return response
                if(res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
                    return res;
                }
                
                // Server error (5xx) - retry
                if(res.getStatusCode() >= 500) {
                    if(attemptCount < MAX_RETRIES) {
                        System.debug('Server error, retrying attempt ' + attemptCount);
                        continue;
                    }
                }
                
                // Client error (4xx) - don't retry
                throw new PaymentGatewayException(
                    'Payment request failed with status ' + res.getStatusCode() + 
                    ': ' + res.getBody()
                );
                
            } catch(System.CalloutException e) {
                lastException = e;
                
                // Log failed attempt
                IntegrationLogService.logFailedCallout(
                    req,
                    recordId,
                    'Payment Gateway',
                    attemptCount,
                    e.getMessage()
                );
                
                if(attemptCount < MAX_RETRIES) {
                    System.debug('Callout exception, retrying attempt ' + attemptCount);
                    // In production: implement exponential backoff using Queueable
                    continue;
                }
                
                throw new PaymentGatewayException(
                    'Payment callout failed after ' + MAX_RETRIES + ' attempts: ' + 
                    e.getMessage(),
                    e
                );
            }
        }
        
        // Should not reach here
        throw new PaymentGatewayException(
            'Payment failed after maximum retry attempts',
            lastException
        );
    }
    
    /**
     * Parse HTTP response into PaymentResponse
     */
    private static PaymentResponse parsePaymentResponse(HttpResponse res, Id recordId) {
        try {
            PaymentResponse response = (PaymentResponse)JSON.deserialize(
                res.getBody(),
                PaymentResponse.class
            );
            
            if(response == null) {
                throw new PaymentGatewayException('Empty response received from gateway');
            }
            
            return response;
            
        } catch(JSONException e) {
            ErrorLogService.logError(
                e,
                recordId,
                'PaymentGatewayService.parsePaymentResponse',
                ErrorLogService.Severity.HIGH
            );
            throw new PaymentGatewayException(
                'Failed to parse payment response: ' + e.getMessage(),
                e
            );
        }
    }
    
    /**
     * Generate unique request ID for tracing
     */
    private static String generateRequestId() {
        return 'SF-' + UserInfo.getOrganizationId() + '-' + 
               System.currentTimeMillis() + '-' + 
               Math.round(Math.random() * 10000);
    }
    
    // Inner classes for request/response
    public class PaymentRequest {
        public String claimId;
        public Decimal amount;
        public String currency;
        public String policyNumber;
        public String timestamp;
    }
    
    public class PaymentResponse {
        public Boolean success;
        public String transactionId;
        public String status;
        public String message;
        public Decimal amountProcessed;
        public String timestamp;
    }
}
```

---

## Integration Logging Service

### IntegrationLogService Implementation

```apex
public class IntegrationLogService {
    
    /**
     * Log successful HTTP callout
     */
    public static void logCallout(
        HttpRequest req,
        HttpResponse res,
        Id recordId,
        String integrationName,
        Integer attemptNumber,
        Long durationMs
    ) {
        try {
            IntegrationLog__c log = new IntegrationLog__c(
                Claim__c = recordId,
                IntegrationName__c = integrationName,
                Endpoint__c = extractEndpoint(req.getEndpoint()),
                RequestMethod__c = req.getMethod(),
                RequestPayload__c = truncatePayload(req.getBody()),
                ResponsePayload__c = truncatePayload(res.getBody()),
                StatusCode__c = res.getStatusCode(),
                IsSuccess__c = (res.getStatusCode() >= 200 && res.getStatusCode() < 300),
                DurationMs__c = durationMs,
                RetryCount__c = attemptNumber - 1,
                Timestamp__c = System.now()
            );
            
            Database.insert(log, false);
            
        } catch(Exception e) {
            System.debug(LoggingLevel.ERROR, 
                'Failed to log integration: ' + e.getMessage());
        }
    }
    
    /**
     * Log failed callout
     */
    public static void logFailedCallout(
        HttpRequest req,
        Id recordId,
        String integrationName,
        Integer attemptNumber,
        String errorMessage
    ) {
        try {
            IntegrationLog__c log = new IntegrationLog__c(
                Claim__c = recordId,
                IntegrationName__c = integrationName,
                Endpoint__c = extractEndpoint(req.getEndpoint()),
                RequestMethod__c = req.getMethod(),
                RequestPayload__c = truncatePayload(req.getBody()),
                ResponsePayload__c = 'ERROR: ' + errorMessage,
                StatusCode__c = 0,
                IsSuccess__c = false,
                RetryCount__c = attemptNumber - 1,
                Timestamp__c = System.now()
            );
            
            Database.insert(log, false);
            
        } catch(Exception e) {
            System.debug(LoggingLevel.ERROR, 
                'Failed to log integration failure: ' + e.getMessage());
        }
    }
    
    /**
     * Extract endpoint without named credential prefix
     */
    private static String extractEndpoint(String fullEndpoint) {
        if(fullEndpoint.startsWith('callout:')) {
            Integer slashIndex = fullEndpoint.indexOf('/', 8);
            if(slashIndex > 0) {
                return fullEndpoint.substring(slashIndex);
            }
        }
        return fullEndpoint;
    }
    
    /**
     * Truncate payload to fit in long text field (131,072 characters)
     */
    private static String truncatePayload(String payload) {
        if(String.isBlank(payload)) {
            return null;
        }
        
        Integer maxLength = 130000; // Leave buffer
        if(payload.length() > maxLength) {
            return payload.substring(0, maxLength) + '\n... [TRUNCATED]';
        }
        
        return payload;
    }
}
```

---

## Asynchronous Integration Pattern

### Using Future Methods

```apex
public class ClaimService {
    
    /**
     * Process approved claims asynchronously
     */
    @future(callout=true)
    public static void processApprovedClaimsAsync(Set<Id> claimIds) {
        List<Claim__c> claims = [
            SELECT Id, ClaimAmount__c, PolicyNumber__c, Status__c
            FROM Claim__c
            WHERE Id IN :claimIds
        ];
        
        List<Claim__c> claimsToUpdate = new List<Claim__c>();
        
        for(Claim__c claim : claims) {
            try {
                PaymentGatewayService.PaymentResponse response = 
                    PaymentGatewayService.processPayment(claim);
                
                if(response.success) {
                    claim.Status__c = 'Paid';
                    claim.PaymentTransactionId__c = response.transactionId;
                    claim.PaidDate__c = System.today();
                    claimsToUpdate.add(claim);
                }
                
            } catch(Exception e) {
                ErrorLogService.logError(
                    e,
                    claim.Id,
                    'ClaimService.processApprovedClaimsAsync',
                    ErrorLogService.Severity.HIGH
                );
            }
        }
        
        if(!claimsToUpdate.isEmpty()) {
            update claimsToUpdate;
        }
    }
}
```

### Using Queueable (Preferred for Complex Operations)

```apex
public class PaymentProcessorQueueable implements Queueable, Database.AllowsCallouts {
    
    private List<Claim__c> claims;
    private Integer currentIndex;
    private Integer retryCount;
    
    public PaymentProcessorQueueable(List<Claim__c> claims) {
        this(claims, 0, 0);
    }
    
    private PaymentProcessorQueueable(
        List<Claim__c> claims, 
        Integer currentIndex, 
        Integer retryCount
    ) {
        this.claims = claims;
        this.currentIndex = currentIndex;
        this.retryCount = retryCount;
    }
    
    public void execute(QueueableContext context) {
        if(currentIndex >= claims.size()) {
            // All claims processed
            return;
        }
        
        Claim__c claim = claims[currentIndex];
        
        try {
            PaymentGatewayService.PaymentResponse response = 
                PaymentGatewayService.processPayment(claim);
            
            if(response.success) {
                claim.Status__c = 'Paid';
                claim.PaymentTransactionId__c = response.transactionId;
                claim.PaidDate__c = System.today();
                update claim;
                
                // Process next claim
                if(currentIndex + 1 < claims.size()) {
                    System.enqueueJob(new PaymentProcessorQueueable(
                        claims, 
                        currentIndex + 1, 
                        0
                    ));
                }
            }
            
        } catch(PaymentGatewayException e) {
            ErrorLogService.logError(
                e,
                claim.Id,
                'PaymentProcessorQueueable.execute',
                ErrorLogService.Severity.HIGH
            );
            
            // Retry logic with exponential backoff
            if(retryCount < 3) {
                // Schedule retry after delay
                // Note: Implement actual delay using Scheduled Apex
                System.enqueueJob(new PaymentProcessorQueueable(
                    claims,
                    currentIndex,
                    retryCount + 1
                ));
            } else {
                // Max retries reached, move to next claim
                if(currentIndex + 1 < claims.size()) {
                    System.enqueueJob(new PaymentProcessorQueueable(
                        claims,
                        currentIndex + 1,
                        0
                    ));
                }
            }
        }
    }
}
```

---

## REST API Pattern (Inbound)

### Standard REST Service Structure

```apex
@RestResource(urlMapping='/api/claims/*')
global with sharing class ClaimRestService {
    
    /**
     * GET /api/claims/:claimId
     * Retrieve claim details
     */
    @HttpGet
    global static ClaimResponse getClaim() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        
        try {
            // Extract claim ID from URI
            String uri = req.requestURI;
            String claimId = uri.substring(uri.lastIndexOf('/') + 1);
            
            // Validate claim ID
            if(!isValidId(claimId)) {
                res.statusCode = 400;
                return new ClaimResponse(false, 'Invalid claim ID', null);
            }
            
            // Query claim
            List<Claim__c> claims = [
                SELECT Id, ClaimNumber__c, ClaimAmount__c, Status__c,
                    PolicyNumber__c, SubmittedDate__c,
                    (SELECT Id, ItemDescription__c, ItemAmount__c 
                     FROM ClaimLineItems__r)
                FROM Claim__c
                WHERE Id = :claimId
                LIMIT 1
            ];
            
            if(claims.isEmpty()) {
                res.statusCode = 404;
                return new ClaimResponse(false, 'Claim not found', null);
            }
            
            res.statusCode = 200;
            return new ClaimResponse(true, 'Success', claims[0]);
            
        } catch(Exception e) {
            ErrorLogService.logError(
                e,
                null,
                'ClaimRestService.getClaim',
                ErrorLogService.Severity.MEDIUM
            );
            
            res.statusCode = 500;
            return new ClaimResponse(false, 'Internal server error', null);
        }
    }
    
    /**
     * POST /api/claims
     * Create new claim
     */
    @HttpPost
    global static ClaimResponse createClaim(ClaimRequest requestData) {
        RestResponse res = RestContext.response;
        
        try {
            // Validate request
            if(requestData == null) {
                res.statusCode = 400;
                return new ClaimResponse(false, 'Request body is required', null);
            }
            
            if(String.isBlank(requestData.policyNumber)) {
                res.statusCode = 400;
                return new ClaimResponse(false, 'Policy number is required', null);
            }
            
            // Verify policy exists
            List<Policy__c> policies = [
                SELECT Id, PolicyNumber__c, Status__c
                FROM Policy__c
                WHERE PolicyNumber__c = :requestData.policyNumber
                LIMIT 1
            ];
            
            if(policies.isEmpty()) {
                res.statusCode = 404;
                return new ClaimResponse(false, 'Policy not found', null);
            }
            
            Policy__c policy = policies[0];
            
            if(policy.Status__c != 'Active') {
                res.statusCode = 400;
                return new ClaimResponse(
                    false, 
                    'Cannot create claim for inactive policy', 
                    null
                );
            }
            
            // Create claim
            Claim__c claim = new Claim__c(
                Policy__c = policy.Id,
                PolicyNumber__c = requestData.policyNumber,
                ClaimAmount__c = requestData.amount,
                ClaimDescription__c = requestData.description,
                IncidentDate__c = requestData.incidentDate,
                Status__c = 'New',
                SubmittedDate__c = System.today()
            );
            
            insert claim;
            
            // Reload to get auto-number field
            claim = [
                SELECT Id, ClaimNumber__c, ClaimAmount__c, Status__c,
                    PolicyNumber__c, SubmittedDate__c
                FROM Claim__c
                WHERE Id = :claim.Id
            ];
            
            res.statusCode = 201;
            return new ClaimResponse(true, 'Claim created successfully', claim);
            
        } catch(DmlException e) {
            ErrorLogService.logError(
                e,
                null,
                'ClaimRestService.createClaim',
                ErrorLogService.Severity.HIGH
            );
            
            res.statusCode = 500;
            return new ClaimResponse(false, 'Failed to create claim', null);
        }
    }
    
    /**
     * PATCH /api/claims/:claimId
     * Update claim status
     */
    @HttpPatch
    global static ClaimResponse updateClaim() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        
        try {
            // Extract claim ID
            String uri = req.requestURI;
            String claimId = uri.substring(uri.lastIndexOf('/') + 1);
            
            // Parse request body
            Map<String, Object> requestBody = 
                (Map<String, Object>)JSON.deserializeUntyped(req.requestBody.toString());
            
            if(!requestBody.containsKey('status')) {
                res.statusCode = 400;
                return new ClaimResponse(false, 'Status field is required', null);
            }
            
            String newStatus = (String)requestBody.get('status');
            
            // Validate status value
            List<String> validStatuses = new List<String>{
                'New', 'Under Review', 'Approved', 'Rejected', 'Paid'
            };
            
            if(!validStatuses.contains(newStatus)) {
                res.statusCode = 400;
                return new ClaimResponse(false, 'Invalid status value', null);
            }
            
            // Update claim
            Claim__c claim = new Claim__c(
                Id = claimId,
                Status__c = newStatus
            );
            
            if(newStatus == 'Approved') {
                claim.ApprovedDate__c = System.today();
            }
            
            update claim;
            
            // Reload claim
            claim = [
                SELECT Id, ClaimNumber__c, ClaimAmount__c, Status__c
                FROM Claim__c
                WHERE Id = :claimId
            ];
            
            res.statusCode = 200;
            return new ClaimResponse(true, 'Claim updated successfully', claim);
            
        } catch(Exception e) {
            ErrorLogService.logError(
                e,
                null,
                'ClaimRestService.updateClaim',
                ErrorLogService.Severity.HIGH
            );
            
            res.statusCode = 500;
            return new ClaimResponse(false, 'Failed to update claim', null);
        }
    }
    
    // Helper method
    private static Boolean isValidId(String idStr) {
        try {
            Id testId = Id.valueOf(idStr);
            return true;
        } catch(Exception e) {
            return false;
        }
    }
    
    // Inner classes
    global class ClaimRequest {
        global String policyNumber;
        global Decimal amount;
        global String description;
        global Date incidentDate;
    }
    
    global class ClaimResponse {
        global Boolean success;
        global String message;
        global ClaimData data;
        
        global ClaimResponse(Boolean success, String message, Claim__c claim) {
            this.success = success;
            this.message = message;
            if(claim != null) {
                this.data = new ClaimData(claim);
            }
        }
    }
    
    global class ClaimData {
        global String id;
        global String claimNumber;
        global Decimal amount;
        global String status;
        global String policyNumber;
        global Date submittedDate;
        global List<LineItemData> lineItems;
        
        global ClaimData(Claim__c claim) {
            this.id = claim.Id;
            this.claimNumber = claim.ClaimNumber__c;
            this.amount = claim.ClaimAmount__c;
            this.status = claim.Status__c;
            this.policyNumber = claim.PolicyNumber__c;
            this.submittedDate = claim.SubmittedDate__c;
            
            if(claim.ClaimLineItems__r != null) {
                this.lineItems = new List<LineItemData>();
                for(ClaimLineItem__c item : claim.ClaimLineItems__r) {
                    this.lineItems.add(new LineItemData(item));
                }
            }
        }
    }
    
    global class LineItemData {
        global String id;
        global String description;
        global Decimal amount;
        
        global LineItemData(ClaimLineItem__c item) {
            this.id = item.Id;
            this.description = item.ItemDescription__c;
            this.amount = item.ItemAmount__c;
        }
    }
}
```

---

## Platform Events Pattern

### Publishing Events

```apex
public class ClaimEventService {
    
    /**
     * Publish claim approved event
     */
    public static void publishClaimApproved(Claim__c claim) {
        ClaimApproved__e event = new ClaimApproved__e(
            ClaimId__c = claim.Id,
            ClaimNumber__c = claim.ClaimNumber__c,
            ClaimAmount__c = claim.ClaimAmount__c,
            PolicyNumber__c = claim.PolicyNumber__c,
            ApprovedDate__c = System.now()
        );
        
        Database.SaveResult result = EventBus.publish(event);
        
        if(!result.isSuccess()) {
            for(Database.Error error : result.getErrors()) {
                ErrorLogService.logError(
                    new IntegrationException('Failed to publish event: ' + error.getMessage()),
                    claim.Id,
                    'ClaimEventService.publishClaimApproved',
                    ErrorLogService.Severity.MEDIUM
                );
            }
        }
    }
}
```

### Subscribing to Events

```apex
trigger ClaimApprovedEventTrigger on ClaimApproved__e (after insert) {
    List<Claim__c> claimsToProcess = new List<Claim__c>();
    
    for(ClaimApproved__e event : Trigger.new) {
        claimsToProcess.add(new Claim__c(
            Id = event.ClaimId__c,
            Status__c = 'Processing Payment'
        ));
    }
    
    if(!claimsToProcess.isEmpty()) {
        // Process asynchronously
        Set<Id> claimIds = new Set<Id>();
        for(Claim__c claim : claimsToProcess) {
            claimIds.add(claim.Id);
        }
        
        ClaimService.processApprovedClaimsAsync(claimIds);
    }
}
```

---

## Bulk API Pattern

### Processing Large Data Volumes

```apex
public class BulkClaimProcessor {
    
    /**
     * Process large batch of claims using Batchable
     */
    public static void processClaimsInBulk(List<Id> claimIds) {
        Database.executeBatch(
            new ClaimBulkProcessingBatch(claimIds),
            200 // Batch size
        );
    }
}

public class ClaimBulkProcessingBatch implements Database.Batchable<SObject>, 
                                                   Database.AllowsCallouts,
                                                   Database.Stateful {
    
    private Set<Id> claimIds;
    private Integer successCount = 0;
    private Integer errorCount = 0;
    
    public ClaimBulkProcessingBatch(List<Id> claimIds) {
        this.claimIds = new Set<Id>(claimIds);
    }
    
    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, ClaimAmount__c, Status__c, PolicyNumber__c
            FROM Claim__c
            WHERE Id IN :claimIds
            AND Status__c = 'Approved'
        ]);
    }
    
    public void execute(Database.BatchableContext bc, List<Claim__c> scope) {
        // Process batch
        for(Claim__c claim : scope) {
            try {
                PaymentGatewayService.PaymentResponse response = 
                    PaymentGatewayService.processPayment(claim);
                
                if(response.success) {
                    claim.Status__c = 'Paid';
                    claim.PaymentTransactionId__c = response.transactionId;
                    successCount++;
                }
            } catch(Exception e) {
                ErrorLogService.logError(
                    e,
                    claim.Id,
                    'ClaimBulkProcessingBatch.execute',
                    ErrorLogService.Severity.HIGH
                );
                errorCount++;
            }
        }
        
        update scope;
    }
    
    public void finish(Database.BatchableContext bc) {
        System.debug('Bulk processing complete. Success: ' + successCount + 
                     ', Errors: ' + errorCount);
    }
}
```

---

## Circuit Breaker Pattern

### Preventing Cascading Failures

```apex
public class CircuitBreaker {
    
    private static Map<String, CircuitBreakerState> states = 
        new Map<String, CircuitBreakerState>();
    
    public enum State { CLOSED, OPEN, HALF_OPEN }
    
    private static final Integer FAILURE_THRESHOLD = 5;
    private static final Integer SUCCESS_THRESHOLD = 2;
    private static final Integer TIMEOUT_MS = 60000; // 1 minute
    
    public static Boolean isOpen(String serviceName) {
        CircuitBreakerState state = getState(serviceName);
        
        if(state.state == State.OPEN) {
            // Check if timeout has passed
            if(System.currentTimeMillis() - state.lastFailureTime > TIMEOUT_MS) {
                state.state = State.HALF_OPEN;
                state.consecutiveSuccesses = 0;
            } else {
                return true; // Circuit is open, reject request
            }
        }
        
        return false;
    }
    
    public static void recordSuccess(String serviceName) {
        CircuitBreakerState state = getState(serviceName);
        
        if(state.state == State.HALF_OPEN) {
            state.consecutiveSuccesses++;
            if(state.consecutiveSuccesses >= SUCCESS_THRESHOLD) {
                state.state = State.CLOSED;
                state.failureCount = 0;
            }
        } else {
            state.failureCount = 0;
        }
    }
    
    public static void recordFailure(String serviceName) {
        CircuitBreakerState state = getState(serviceName);
        state.failureCount++;
        state.lastFailureTime = System.currentTimeMillis();
        state.consecutiveSuccesses = 0;
        
        if(state.failureCount >= FAILURE_THRESHOLD) {
            state.state = State.OPEN;
            System.debug('Circuit breaker opened for: ' + serviceName);
        }
    }
    
    private static CircuitBreakerState getState(String serviceName) {
        if(!states.containsKey(serviceName)) {
            states.put(serviceName, new CircuitBreakerState());
        }
        return states.get(serviceName);
    }
    
    private class CircuitBreakerState {
        State state = State.CLOSED;
        Integer failureCount = 0;
        Integer consecutiveSuccesses = 0;
        Long lastFailureTime = 0;
    }
}
```

---

## Integration Best Practices Summary

### ✅ DO

- Use Named Credentials for all external endpoints
- Implement retry logic with exponential backoff
- Log all integration attempts (success and failure)
- Set appropriate timeouts (typically 30 seconds)
- Handle all exception types specifically
- Use async patterns (Future, Queueable) when possible
- Implement circuit breakers for unreliable services
- Include correlation IDs for request tracing
- Validate responses thoroughly
- Use bulk patterns for high-volume operations

### ❌ DON'T

- Hardcode endpoints or credentials
- Make synchronous callouts from triggers
- Ignore failed callouts
- Use generic exception handling
- Exceed governor limits (callout limits, CPU time)
- Store sensitive data in integration logs
- Skip input validation
- Make callouts without timeout settings
- Retry indefinitely without backoff
- Process large volumes synchronously

---

## Testing Integrations

### HTTP Callout Mock

```apex
@isTest
global class PaymentGatewayMock implements HttpCalloutMock {
    
    private Integer statusCode;
    private String responseBody;
    
    global PaymentGatewayMock(Integer statusCode, String responseBody) {
        this.statusCode = statusCode;
        this.responseBody = responseBody;
    }
    
    global HTTPResponse respond(HTTPRequest req) {
        HttpResponse res = new HttpResponse();
        res.setHeader('Content-Type', 'application/json');
        res.setStatusCode(statusCode);
        res.setBody(responseBody);
        return res;
    }
    
    // Factory methods for common scenarios
    global static PaymentGatewayMock success() {
        String body = JSON.serialize(new Map<String, Object>{
            'success' => true,
            'transactionId' => 'TXN-12345',
            'status' => 'completed',
            'message' => 'Payment processed successfully'
        });
        return new PaymentGatewayMock(200, body);
    }
    
    global static PaymentGatewayMock failure() {
        String body = JSON.serialize(new Map<String, Object>{
            'success' => false,
            'message' => 'Payment declined'
        });
        return new PaymentGatewayMock(400, body);
    }
    
    global static PaymentGatewayMock serverError() {
        return new PaymentGatewayMock(500, '{"error": "Internal server error"}');
    }
}
```

### Integration Test

```apex
@isTest
private class PaymentGatewayServiceTest {
    
    @isTest
    static void testProcessPayment_Success() {
        // Setup
        Claim__c claim = TestDataFactory.createClaim(10000, 'Approved');
        insert claim;
        
        // Set mock
        Test.setMock(HttpCalloutMock.class, PaymentGatewayMock.success());
        
        // Test
        Test.startTest();
        PaymentGatewayService.PaymentResponse response = 
            PaymentGatewayService.processPayment(claim);
        Test.stopTest();
        
        // Verify
        System.assertEquals(true, response.success);
        System.assertNotEquals(null, response.transactionId);
        
        // Verify integration was logged
        List<IntegrationLog__c> logs = [
            SELECT Id, IsSuccess__c, StatusCode__c
            FROM IntegrationLog__c
            WHERE Claim__c = :claim.Id
        ];
        System.assertEquals(1, logs.size());
        System.assertEquals(true, logs[0].IsSuccess__c);
        System.assertEquals(200, logs[0].StatusCode__c);
    }
    
    @isTest
    static void testProcessPayment_Retry() {
        // Setup
        Claim__c claim = TestDataFactory.createClaim(10000, 'Approved');
        insert claim;
        
        // Set mock to return server error
        Test.setMock(HttpCalloutMock.class, PaymentGatewayMock.serverError());
        
        // Test
        Test.startTest();
        try {
            PaymentGatewayService.processPayment(claim);
            System.assert(false, 'Should have thrown exception');
        } catch(PaymentGatewayException e) {
            System.assert(e.getMessage().contains('after'));
        }
        Test.stopTest();
        
        // Verify multiple attempts were logged
        List<IntegrationLog__c> logs = [
            SELECT Id FROM IntegrationLog__c WHERE Claim__c = :claim.Id
        ];
        System.assertEquals(3, logs.size(), 'Should have 3 retry attempts');
    }
}