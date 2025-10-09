# Business Rules for Claims Processing

## Claim Validation Rules

### Automatic Approval Threshold
- Claims under $5,000: Auto-approve
- Claims $5,000-$25,000: Manager approval required
- Claims over $25,000: Senior manager approval required

### Claim Amount Validation
```apex
// Always validate claim amount equals sum of line items
Decimal totalLineItems = 0;
for(ClaimLineItem__c item : claim.ClaimLineItems__r) {
    totalLineItems += item.ItemAmount__c;
}
if(claim.ClaimAmount__c != totalLineItems) {
    throw new ClaimValidationException('Claim amount must equal sum of line items');
}


