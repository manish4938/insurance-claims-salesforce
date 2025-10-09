/**
 * Service class for claim processing business logic
 * 
 * @description Handles validation, approval, and payment processing for claims
 */
public with sharing class ClaimService {
    
    // Approval thresholds
    private static final Decimal AUTO_APPROVE_THRESHOLD = 5000;
    private static final Decimal MANAGER_APPROVE_THRESHOLD = 25000; 
    
    /**
     * Assign approval level based on claim amount
     */
    public static void assignApprovalLevel(List<Claim__c> claims) {
        for(Claim__c claim : claims) {
            if(claim.ClaimAmount__c == null) {
                continue;
            }
            
            if(claim.ClaimAmount__c < AUTO_APPROVE_THRESHOLD) {
                claim.ApprovalLevel__c = 'Auto Approved';
                claim.Status__c = 'Approved';
            } else if(claim.ClaimAmount__c < MANAGER_APPROVE_THRESHOLD) {
                claim.ApprovalLevel__c = 'Manager';
                claim.Status__c = 'Under Review';
            } else {
                claim.ApprovalLevel__c = 'Senior Manager';
                claim.Status__c = 'Under Review';
            }
        }
    }
    
    /**
     * Validate claim amounts match line items
     */
    public static void validateClaimAmounts(List<Claim__c> claims) {
        for(Claim__c claim : claims) {
            if(claim.ClaimAmount__c == null || claim.ClaimAmount__c <= 0) {
                claim.addError('Claim amount must be greater than zero');
            }
        }
    }
    
    /**
     * Validate status transitions follow business rules
     */
    public static void validateStatusTransitions(
        List<Claim__c> newClaims, 
        Map<Id, Claim__c> oldClaimMap
    ) {
        for(Claim__c claim : newClaims) {
            Claim__c oldClaim = oldClaimMap.get(claim.Id);
            
            // Cannot transition back to New
            if(claim.Status__c == 'New' && oldClaim.Status__c != 'New') {
                claim.Status__c.addError('Cannot change status back to New');
            }
            
            // Paid claims cannot be modified
            if(oldClaim.Status__c == 'Paid' && claim.Status__c != 'Paid') {
                claim.Status__c.addError('Cannot modify paid claims');
            }
        }
    }
    
    /**
     * Process approved claims for payment
     */
    public static void processApprovedClaims(List<Claim__c> claims) {
        for(Claim__c claim : claims) {
            try {
                // In demo, just log
                System.debug('Processing payment for claim: ' + claim.Id);
                
                // In production, call PaymentGatewayService
                // PaymentGatewayService.processPayment(claim);
                
            } catch(Exception e) {
                ErrorLogService.logError(
                    e, 
                    claim.Id, 
                    'ClaimService.processApprovedClaims',
                    ErrorLogService.Severity.HIGH
                );
            }
        }
    }
    
    /**
     * Process claim approval
     */
    public static void processClaimApproval(Id claimId) {
        Savepoint sp = Database.setSavepoint();
        
        try {
            // Validate input
            if(claimId == null) {
                throw new ClaimValidationException('Claim ID cannot be null');
            }
            
            // Query claim
            List<Claim__c> claims = [
                SELECT Id, ClaimAmount__c, Status__c
                FROM Claim__c 
                WHERE Id = :claimId
                LIMIT 1
            ];
            
            if(claims.isEmpty()) {
                throw new ClaimValidationException('Claim not found: ' + claimId);
            }
            
            Claim__c claim = claims[0];
            
            // Validate status
            if(claim.Status__c != 'Under Review') {
                throw new ClaimProcessingException(
                    'Cannot approve claim in status: ' + claim.Status__c
                );
            }
            
            // Update claim
            claim.Status__c = 'Approved';
            claim.ApprovedDate__c = System.today();
            update claim;
            
        } catch(ClaimValidationException e) {
            Database.rollback(sp);
            ErrorLogService.logError(
                e, 
                claimId, 
                'ClaimService.processClaimApproval',
                ErrorLogService.Severity.HIGH
            );
            throw e;
            
        } catch(Exception e) {
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