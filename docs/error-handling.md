# Error Handling Standards

## Overview
This document defines error handling patterns and standards for the Insurance Claims Management System.

---

## Core Principles

1. **Never Fail Silently**: All errors must be logged
2. **Provide Context**: Include meaningful error messages with context
3. **Centralized Logging**: Use ErrorLog__c for all error tracking
4. **User-Friendly Messages**: Display helpful messages to end users
5. **Preserve Stack Traces**: Always capture full stack traces for debugging
6. **Fail Fast**: Validate early and throw exceptions for invalid states

---

## Custom Exception Classes

### Standard Custom Exceptions

Create specific exception types for different error categories:

```apex
/**
 * Base exception for all custom exceptions
 */
public virtual class BaseException extends Exception {}

/**
 * Thrown when business rule validation fails
 */
public class ClaimValidationException extends BaseException {}

/**
 * Thrown when claim processing logic fails
 */
public class ClaimProcessingException extends BaseException {}

/**
 * Thrown when external payment gateway fails
 */
public class PaymentGatewayException extends BaseException {}

/**
 * Thrown when fraud detection fails or flags a claim
 */
public class FraudDetectionException extends BaseException {}

/**
 * Thrown when integration with external systems fails
 */
public class IntegrationException extends BaseException {}

/**
 * Thrown when notification sending fails
 */
public class NotificationException extends BaseException {}

/**
 * Thrown when data access or query issues occur
 */
public class DataAccessException extends BaseException {}
```

### When to Create Custom Exceptions

Create custom exceptions for:
- ✅ Business rule violations
- ✅ External system integration failures
- ✅ Complex validation scenarios
- ✅ Domain-specific error conditions

Do NOT create custom exceptions for:
- ❌ Standard Salesforce errors (DML, SOQL)
- ❌ Simple validation that can use addError()
- ❌ One-time use cases

---

## Standard Error Handling Pattern

### Service Layer Pattern

**Always use this pattern in service classes:**

```apex
public class ClaimService {
    
    public static void processClaimApproval(Id claimId) {
        // Declare savepoint for rollback
        Savepoint sp = Database.setSavepoint();
        
        try {
            // Validate inputs
            if(claimId == null) {
                throw new ClaimValidationException('Claim ID cannot be null');
            }
            
            // Query with null check
            List<Claim__c> claims = [
                SELECT Id, ClaimAmount__c, Status__c, PolicyNumber__c
                FROM Claim__c 
                WHERE Id = :claimId
                LIMIT 1
            ];
            
            if(claims.isEmpty()) {
                throw new ClaimValidationException(
                    'Claim not found: ' + claimId
                );
            }
            
            Claim__c claim = claims[0];
            
            // Business logic validation
            if(claim.Status__c != 'Under Review') {
                throw new ClaimProcessingException(
                    'Cannot approve claim in status: ' + claim.Status__c
                );
            }
            
            // Perform business logic
            claim.Status__c = 'Approved';
            claim.ApprovedDate__c = System.today();
            
            update claim;
            
            // Additional operations
            sendApprovalNotification(claim);
            
        } catch(ClaimValidationException e) {
            // Rollback transaction
            Database.rollback(sp);
            
            // Log error
            ErrorLogService.logError(
                e, 
                claimId, 
                'ClaimService.processClaimApproval',
                ErrorLogService.Severity.HIGH
            );
            
            // Re-throw for caller to handle
            throw e;
            
        } catch(DmlException e) {
            Database.rollback(sp);
            ErrorLogService.logError(
                e, 
                claimId, 
                'ClaimService.processClaimApproval',
                ErrorLogService.Severity.CRITICAL
            );
            throw new ClaimProcessingException(
                'Failed to update claim: ' + e.getMessage(), 
                e
            );
            
        } catch(Exception e) {
            // Catch-all for unexpected errors
            Database.rollback(sp);
            ErrorLogService.logError(
                e, 
                claimId, 
                'ClaimService.processClaimApproval',
                ErrorLogService.Severity.CRITICAL
            );
            throw new ClaimProcessingException(
                'Unexpected error during claim approval: ' + e.getMessage(), 
                e
            );
        }
    }
}
```

---

## Error Logging Service

### ErrorLogService Implementation

**Always use this service for logging errors:**

```apex
public class ErrorLogService {
    
    public enum Severity {
        LOW,
        MEDIUM,
        HIGH,
        CRITICAL
    }
    
    /**
     * Log an error with full context
     */
    public static void logError(
        Exception e, 
        Id recordId, 
        String methodContext
    ) {
        logError(e, recordId, methodContext, Severity.MEDIUM);
    }
    
    /**
     * Log an error with severity level
     */
    public static void logError(
        Exception e, 
        Id recordId, 
        String methodContext,
        Severity severity
    ) {
        try {
            // Parse method context
            List<String> contextParts = methodContext.split('\\.');
            String className = contextParts.size() > 0 ? contextParts[0] : 'Unknown';
            String methodName = contextParts.size() > 1 ? contextParts[1] : 'Unknown';
            
            // Determine error type
            String errorType = determineErrorType(e);
            
            // Create error log record
            ErrorLog__c errorLog = new ErrorLog__c(
                ErrorMessage__c = e.getMessage(),
                StackTrace__c = e.getStackTraceString(),
                ClassName__c = className,
                MethodName__c = methodName,
                RecordId__c = recordId,
                ErrorType__c = errorType,
                Severity__c = severity.name(),
                Timestamp__c = System.now(),
                User__c = UserInfo.getUserId(),
                IsResolved__c = false
            );
            
            // Insert without throwing exception if logging fails
            Database.insert(errorLog, false);
            
            // For critical errors, send email notification
            if(severity == Severity.CRITICAL) {
                sendCriticalErrorNotification(errorLog);
            }
            
        } catch(Exception loggingException) {
            // Last resort: System.debug if logging fails
            System.debug(LoggingLevel.ERROR, 
                'Failed to log error: ' + loggingException.getMessage());
            System.debug(LoggingLevel.ERROR, 
                'Original error: ' + e.getMessage());
        }
    }
    
    /**
     * Determine error type from exception
     */
    private static String determineErrorType(Exception e) {
        if(e instanceof ClaimValidationException) {
            return 'Validation';
        } else if(e instanceof IntegrationException || 
                  e instanceof PaymentGatewayException) {
            return 'Integration';
        } else if(e instanceof DmlException) {
            return 'Database';
        } else if(e instanceof ClaimProcessingException) {
            return 'Business Logic';
        }
        return 'Unknown';
    }
    
    /**
     * Send email for critical errors
     */
    private static void sendCriticalErrorNotification(ErrorLog__c errorLog) {
        // Implementation: Send email to admin team
        try {
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(new String[] { 'admin@company.com' });
            email.setSubject('CRITICAL ERROR: ' + errorLog.ClassName__c);
            email.setPlainTextBody(
                'Critical error occurred:\n\n' +
                'Class: ' + errorLog.ClassName__c + '\n' +
                'Method: ' + errorLog.MethodName__c + '\n' +
                'Error: ' + errorLog.ErrorMessage__c + '\n' +
                'Record ID: ' + errorLog.RecordId__c
            );
            Messaging.sendEmail(new Messaging.SingleEmailMessage[] { email });
        } catch(Exception e) {
            System.debug(LoggingLevel.ERROR, 
                'Failed to send critical error notification: ' + e.getMessage());
        }
    }
    
    /**
     * Bulk log multiple errors
     */
    public static void logErrors(List<ErrorLogEntry> entries) {
        List<ErrorLog__c> errorLogs = new List<ErrorLog__c>();
        
        for(ErrorLogEntry entry : entries) {
            List<String> contextParts = entry.methodContext.split('\\.');
            String className = contextParts.size() > 0 ? contextParts[0] : 'Unknown';
            String methodName = contextParts.size() > 1 ? contextParts[1] : 'Unknown';
            
            errorLogs.add(new ErrorLog__c(
                ErrorMessage__c = entry.exception.getMessage(),
                StackTrace__c = entry.exception.getStackTraceString(),
                ClassName__c = className,
                MethodName__c = methodName,
                RecordId__c = entry.recordId,
                ErrorType__c = determineErrorType(entry.exception),
                Severity__c = entry.severity.name(),
                Timestamp__c = System.now(),
                User__c = UserInfo.getUserId()
            ));
        }
        
        if(!errorLogs.isEmpty()) {
            Database.insert(errorLogs, false);
        }
    }
    
    /**
     * Wrapper class for bulk error logging
     */
    public class ErrorLogEntry {
        public Exception exception;
        public Id recordId;
        public String methodContext;
        public Severity severity;
        
        public ErrorLogEntry(
            Exception ex, 
            Id recId, 
            String context, 
            Severity sev
        ) {
            this.exception = ex;
            this.recordId = recId;
            this.methodContext = context;
            this.severity = sev;
        }
    }
}
```

---

## Controller Error Handling

### Lightning Web Component Controllers

```apex
public with sharing class ClaimController {
    
    @AuraEnabled
    public static ClaimWrapper getClaimDetails(Id claimId) {
        try {
            // Input validation
            if(claimId == null) {
                throw new AuraHandledException('Claim ID is required');
            }
            
            // Query claim
            List<Claim__c> claims = [
                SELECT Id, ClaimNumber__c, ClaimAmount__c, Status__c,
                    PolicyHolder__r.Name,
                    (SELECT Id, ItemDescription__c, ItemAmount__c 
                     FROM ClaimLineItems__r)
                FROM Claim__c
                WHERE Id = :claimId
                LIMIT 1
            ];
            
            if(claims.isEmpty()) {
                throw new AuraHandledException('Claim not found');
            }
            
            // Return data wrapper
            return new ClaimWrapper(claims[0]);
            
        } catch(AuraHandledException e) {
            // AuraHandledException can be thrown directly
            throw e;
            
        } catch(Exception e) {
            // Log unexpected errors
            ErrorLogService.logError(
                e, 
                claimId, 
                'ClaimController.getClaimDetails',
                ErrorLogService.Severity.MEDIUM
            );
            
            // Throw user-friendly message
            throw new AuraHandledException(
                'Unable to retrieve claim details. Please try again or contact support.'
            );
        }
    }
    
    @AuraEnabled
    public static void approveClaim(Id claimId) {
        try {
            ClaimService.processClaimApproval(claimId);
            
        } catch(ClaimValidationException e) {
            throw new AuraHandledException(e.getMessage());
            
        } catch(ClaimProcessingException e) {
            throw new AuraHandledException(
                'Unable to approve claim: ' + e.getMessage()
            );
            
        } catch(Exception e) {
            ErrorLogService.logError(
                e, 
                claimId, 
                'ClaimController.approveClaim',
                ErrorLogService.Severity.HIGH
            );
            throw new AuraHandledException(
                'An unexpected error occurred. Please contact support.'
            );
        }
    }
}
```

---

## Trigger Error Handling

### Trigger Handler Pattern

```apex
public with sharing class ClaimTriggerHandler extends TriggerHandler {
    
    private List<Claim__c> newClaims;
    private Map<Id, Claim__c> oldClaimMap;
    
    public ClaimTriggerHandler() {
        this.newClaims = (List<Claim__c>) Trigger.new;
        this.oldClaimMap = (Map<Id, Claim__c>) Trigger.oldMap;
    }
    
    public override void beforeInsert() {
        try {
            ClaimService.validateClaimAmounts(newClaims);
            ClaimService.assignApprovalLevel(newClaims);
            
        } catch(ClaimValidationException e) {
            // Add error to record for user feedback
            for(Claim__c claim : newClaims) {
                claim.addError(e.getMessage());
            }
            
            // Log error
            ErrorLogService.logError(
                e, 
                null, 
                'ClaimTriggerHandler.beforeInsert',
                ErrorLogService.Severity.LOW
            );
        } catch(Exception e) {
            // Log unexpected errors
            ErrorLogService.logError(
                e, 
                null, 
                'ClaimTriggerHandler.beforeInsert',
                ErrorLogService.Severity.HIGH
            );
            
            // Add generic error to all records
            for(Claim__c claim : newClaims) {
                claim.addError(
                    'Unable to process claim. Please contact support.'
                );
            }
        }
    }
    
    public override void afterUpdate() {
        // Collect errors instead of throwing
        List<ErrorLogService.ErrorLogEntry> errors = 
            new List<ErrorLogService.ErrorLogEntry>();
        
        try {
            List<Claim__c> approvedClaims = new List<Claim__c>();
            
            for(Claim__c claim : newClaims) {
                Claim__c oldClaim = oldClaimMap.get(claim.Id);
                if(claim.Status__c == 'Approved' && 
                   oldClaim.Status__c != 'Approved') {
                    approvedClaims.add(claim);
                }
            }
            
            if(!approvedClaims.isEmpty()) {
                ClaimService.processApprovedClaims(approvedClaims);
            }
            
        } catch(Exception e) {
            // In after triggers, can't add error to record
            // Log and continue processing
            ErrorLogService.logError(
                e, 
                null, 
                'ClaimTriggerHandler.afterUpdate',
                ErrorLogService.Severity.HIGH
            );
        }
    }
}
```

---

## Integration Error Handling

### HTTP Callout Pattern with Retry Logic

```apex
public class PaymentGatewayService {
    
    private static final Integer MAX_RETRIES = 3;
    private static final Integer INITIAL_WAIT_TIME = 1000; // milliseconds
    
    /**
     * Process payment with retry logic
     */
    public static PaymentResponse processPayment(Claim__c claim) {
        Integer retryCount = 0;
        Exception lastException = null;
        
        while(retryCount <= MAX_RETRIES) {
            try {
                return makePaymentCallout(claim);
                
            } catch(PaymentGatewayException e) {
                lastException = e;
                retryCount++;
                
                // Log each retry attempt
                IntegrationLogService.logAttempt(
                    claim.Id,
                    'Payment Gateway',
                    retryCount,
                    false,
                    e.getMessage()
                );
                
                if(retryCount > MAX_RETRIES) {
                    // Final failure
                    ErrorLogService.logError(
                        e, 
                        claim.Id, 
                        'PaymentGatewayService.processPayment',
                        ErrorLogService.Severity.CRITICAL
                    );
                    throw e;
                }
                
                // Wait before retry (exponential backoff)
                // Note: In production, use Queueable for proper async handling
                Integer waitTime = INITIAL_WAIT_TIME * (Integer)Math.pow(2, retryCount - 1);
                System.debug('Retrying in ' + waitTime + 'ms...');
            }
        }
        
        // Should never reach here, but for safety
        throw new PaymentGatewayException(
            'Payment failed after ' + MAX_RETRIES + ' retries',
            lastException
        );
    }
    
    /**
     * Make HTTP callout to payment gateway
     */
    private static PaymentResponse makePaymentCallout(Claim__c claim) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:PaymentGateway/api/v2/payments');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(30000);
        
        Map<String, Object> payload = new Map<String, Object>{
            'claimId' => claim.Id,
            'amount' => claim.ClaimAmount__c,
            'policyNumber' => claim.PolicyNumber__c
        };
        req.setBody(JSON.serialize(payload));
        
        Http http = new Http();
        HttpResponse res;
        
        try {
            res = http.send(req);
            
            // Log integration
            IntegrationLogService.logCallout(
                req,
                res,
                claim.Id,
                'Payment Gateway'
            );
            
            if(res.getStatusCode() == 200) {
                return (PaymentResponse)JSON.deserialize(
                    res.getBody(), 
                    PaymentResponse.class
                );
            } else if(res.getStatusCode() >= 500) {
                // Server error - retry
                throw new PaymentGatewayException(
                    'Gateway server error: ' + res.getStatusCode() + 
                    ' - ' + res.getBody()
                );
            } else {
                // Client error - don't retry
                throw new PaymentGatewayException(
                    'Payment rejected: ' + res.getStatusCode() + 
                    ' - ' + res.getBody()
                );
            }
            
        } catch(System.CalloutException e) {
            // Network/timeout error
            throw new PaymentGatewayException(
                'Callout failed: ' + e.getMessage(), 
                e
            );
        }
    }
}
```

---

## Batch Apex Error Handling

### Standard Pattern for Batch Jobs

```apex
public class ClaimProcessingBatch implements Database.Batchable<SObject>, Database.Stateful {
    
    // Track errors across batches
    private List<ErrorLogService.ErrorLogEntry> batchErrors = 
        new List<ErrorLogService.ErrorLogEntry>();
    private Integer successCount = 0;
    private Integer errorCount = 0;
    
    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, ClaimAmount__c, Status__c
            FROM Claim__c
            WHERE Status__c = 'Approved'
            AND PaymentDate__c = null
        ]);
    }
    
    public void execute(Database.BatchableContext bc, List<Claim__c> scope) {
        List<Claim__c> claimsToUpdate = new List<Claim__c>();
        
        for(Claim__c claim : scope) {
            try {
                // Process individual claim
                PaymentGatewayService.PaymentResponse response = 
                    PaymentGatewayService.processPayment(claim);
                
                if(response.success) {
                    claim.Status__c = 'Paid';
                    claim.PaymentDate__c = System.today();
                    claim.PaymentTransactionId__c = response.transactionId;
                    claimsToUpdate.add(claim);
                    successCount++;
                }
                
            } catch(Exception e) {
                // Collect error but continue processing other records
                batchErrors.add(new ErrorLogService.ErrorLogEntry(
                    e,
                    claim.Id,
                    'ClaimProcessingBatch.execute',
                    ErrorLogService.Severity.HIGH
                ));
                errorCount++;
            }
        }
        
        // Update successful claims
        if(!claimsToUpdate.isEmpty()) {
            Database.SaveResult[] results = Database.update(claimsToUpdate, false);
            
            // Check for DML errors
            for(Integer i = 0; i < results.size(); i++) {
                if(!results[i].isSuccess()) {
                    Database.Error error = results[i].getErrors()[0];
                    batchErrors.add(new ErrorLogService.ErrorLogEntry(
                        new DmlException(error.getMessage()),
                        claimsToUpdate[i].Id,
                        'ClaimProcessingBatch.execute',
                        ErrorLogService.Severity.HIGH
                    ));
                    errorCount++;
                    successCount--;
                }
            }
        }
    }
    
    public void finish(Database.BatchableContext bc) {
        // Log all collected errors
        if(!batchErrors.isEmpty()) {
            ErrorLogService.logErrors(batchErrors);
        }
        
        // Send summary email
        sendBatchSummaryEmail(bc, successCount, errorCount);
        
        // Log batch completion
        System.debug('Batch completed: ' + successCount + ' succeeded, ' + 
                     errorCount + ' failed');
    }
    
    private void sendBatchSummaryEmail(
        Database.BatchableContext bc, 
        Integer success, 
        Integer errors
    ) {
        AsyncApexJob job = [
            SELECT Id, Status, NumberOfErrors, JobItemsProcessed,
                TotalJobItems, CreatedDate, CompletedDate
            FROM AsyncApexJob
            WHERE Id = :bc.getJobId()
        ];
        
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(new String[] { 'admin@company.com' });
        email.setSubject('Claim Processing Batch Completed');
        email.setPlainTextBody(
            'Batch Job Summary:\n\n' +
            'Status: ' + job.Status + '\n' +
            'Total Records: ' + job.TotalJobItems + '\n' +
            'Successful: ' + success + '\n' +
            'Errors: ' + errors + '\n' +
            'Started: ' + job.CreatedDate + '\n' +
            'Completed: ' + job.CompletedDate
        );
        
        Messaging.sendEmail(new Messaging.SingleEmailMessage[] { email });
    }
}
```

---

## User-Facing Error Messages

### Message Guidelines

**❌ Bad Error Messages**:
- "An error occurred"
- "System error"
- "Contact administrator"
- "Error code: XYZ123"

**✅ Good Error Messages**:
- "Claim amount must equal the sum of line items ($5,000)"
- "Cannot approve claim - it must be in 'Under Review' status"
- "Payment processing failed. Please try again in a few minutes"
- "Document upload limit reached. Maximum 10 documents per claim"

### Error Message Pattern

```apex
// Include: What happened + Why + What to do next
throw new ClaimValidationException(
    'Cannot submit claim. ' +                          // What happened
    'Claim amount ($' + claim.ClaimAmount__c + ') ' + // Why (specific)
    'exceeds policy coverage ($' + policy.CoverageAmount__c + '). ' + 
    'Please reduce the claim amount or contact your agent.' // What to do
);
```

---

## Testing Error Scenarios

### Standard Test Pattern

```apex
@isTest
private class ClaimServiceTest {
    
    @isTest
    static void testProcessApproval_InvalidStatus_ThrowsException() {
        // Setup
        Claim__c claim = TestDataFactory.createClaim(
            10000, 
            'New' // Wrong status for approval
        );
        insert claim;
        
        // Test
        Test.startTest();
        
        String errorMessage;
        try {
            ClaimService.processClaimApproval(claim.Id);
            System.assert(false, 'Expected exception was not thrown');
        } catch(ClaimProcessingException e) {
            errorMessage = e.getMessage();
        }
        
        Test.stopTest();
        
        // Verify
        System.assertNotEquals(null, errorMessage, 'Error message should not be null');
        System.assert(
            errorMessage.contains('Cannot approve claim in status'),
            'Error message should explain the issue'
        );
        
        // Verify error was logged
        List<ErrorLog__c> logs = [
            SELECT Id, ErrorMessage__c, ClassName__c, RecordId__c
            FROM ErrorLog__c
            WHERE RecordId__c = :claim.Id
        ];
        System.assertEquals(1, logs.size(), 'Error should be logged');
        System.assertEquals('ClaimService', logs[0].ClassName__c);
    }
}
```

---

## Error Monitoring & Alerts

### Critical Error Alerts

Configure email alerts for:
- All errors with Severity = 'Critical'
- More than 10 errors from same class/method in 1 hour
- Integration failures affecting payment processing
- Batch job failures

### Error Dashboard

Create Lightning dashboard showing:
- Error count by type (last 24 hours)
- Top 5 error-prone classes
- Unresolved critical errors
- Integration failure rate

---

## Common Anti-Patterns to Avoid

### ❌ Catching and Ignoring

```apex
// NEVER DO THIS
try {
    update claim;
} catch(Exception e) {
    // Silent failure - no logging
}
```

### ❌ Generic Error Messages

```apex
// NEVER DO THIS
throw new ClaimValidationException('Error');
```

### ❌ Not Using Savepoints

```apex
// NEVER DO THIS
// Making DML without savepoint in complex operations
public static void complexOperation() {
    insert records1; // If this succeeds...
    doSomethingThatMightFail(); // ...but this fails...
    insert records2; // ...records1 are orphaned
}
```

### ❌ Throwing Exceptions in Triggers

```apex
// AVOID IN TRIGGERS
public override void beforeInsert() {
    throw new ClaimValidationException('Error'); // Stops all records
}

// INSTEAD USE
public override void beforeInsert() {
    for(Claim__c claim : newClaims) {
        if(isInvalid(claim)) {
            claim.addError('Specific error for this record');
        }
    }
}
```

---

## Summary Checklist

- ✅ Use custom exception classes for domain errors
- ✅ Always log errors with ErrorLogService
- ✅ Include full context: class, method, record ID
- ✅ Use savepoints for complex operations
- ✅ Provide user-friendly error messages
- ✅ Implement retry logic for integrations
- ✅ Test error scenarios explicitly
- ✅ Monitor critical errors with alerts
- ✅ Never fail silently
- ✅ Preserve stack traces for debugging