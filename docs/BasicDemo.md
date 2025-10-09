# Scenario: Auto-Approve Low-Value Claims

- Object: `Claim__c`
- Trigger Event: `before insert`
- Business Rule: 
    If `Claim__c.ClaimAmount__c <= 5000`, then set `Status__c = 'Approved'`
- Otherwise, do not auto-approve.
