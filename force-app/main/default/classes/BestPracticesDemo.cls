// Create a class to demonstrate best practices in Apex
public with sharing class BestPracticesDemo {
    
    // Use constants for fixed values
    private static final Integer MAX_RETRY_ATTEMPTS = 3;
    private static final String STATUS_NEW = 'New';
    private static final String STATUS_APPROVED = 'Approved';
    private static final String STATUS_REJECTED = 'Rejected';
    
    // Method to process claims
    public static void processClaims(List<Claim__c> claims) {
        if(claims == null || claims.isEmpty()) {
            return; // Early exit for null or empty lists
        }
        
        for(Claim__c claim : claims) {
            try {
                // Validate claim data
                validateClaim(claim);
                
                // Process claim based on status
                if(claim.Status__c == STATUS_NEW) {
                    claim.Status__c = STATUS_APPROVED; // Example logic
                } else if(claim.Status__c == STATUS_APPROVED) {
                    claim.Status__c = STATUS_REJECTED; // Example logic
                }
                
            } catch(Exception e) {
                // Handle exceptions gracefully
                System.debug('Error processing claim ID ' + claim.Id + ': ' + e.getMessage());
            }
        }
        
        // Perform DML operation outside of loops
        update claims;
    }
    
    // Method to validate individual claim
    private static void validateClaim(Claim__c claim) {
        if(claim.Amount__c == null || claim.Amount__c <= 0) {
            throw new IllegalArgumentException('Claim amount must be greater than zero');
        }
        
        if(String.isBlank(claim.ClaimantName__c)) {
            throw new IllegalArgumentException('Claimant name cannot be blank');
        }
    }
    
    // Example of a utility method
    public static Decimal calculateTotalAmount(List<Claim__c> claims) {
        Decimal total = 0;
        for(Claim__c claim : claims) {
            if(claim.Amount__c != null) {
                total += claim.Amount__c;
            }
        }
        return total;
    }
}