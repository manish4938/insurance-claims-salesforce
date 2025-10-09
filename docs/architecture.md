# Insurance Claims System Architecture

## Custom Objects
- **Claim__c**: Main claim record
  - Fields: ClaimNumber__c, PolicyNumber__c, ClaimAmount__c, Status__c
  - Status Values: New, Under Review, Approved, Rejected, Paid
  
- **ClaimLineItem__c**: Individual items in a claim
  - Master-Detail to Claim__c
  - Fields: ItemDescription__c, ItemAmount__c, Category__c

## Naming Conventions
- Apex Classes: Use descriptive names ending with purpose
  - Controllers: `ClaimController`
  - Services: `ClaimService`
  - Handlers: `ClaimTriggerHandler`
  - Utilities: `ClaimUtility`
  
- Methods: Use verb + noun pattern
  - `validateClaimAmount()`
  - `calculateTotalClaim()`
  - `processClaimApproval()`

## Design Patterns
- **Trigger Pattern**: One trigger per object calling a handler class
- **Service Layer**: Business logic separated from controllers
- **Repository Pattern**: Data access methods in dedicated classes