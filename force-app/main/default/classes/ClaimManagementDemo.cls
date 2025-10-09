/**
 * Unit tests for BestPracticesDemo
 */
@isTest
private class BestPracticesDemoTest {

    @isTest
    static void testCalculateTotalAmount_HappyPath() {
        // No DML required - purely in-memory calculation
        List<Claim__c> claims = new List<Claim__c>{
            new Claim__c(Amount__c = 100, ClaimantName__c = 'Alice'),
            new Claim__c(Amount__c = 250, ClaimantName__c = 'Bob'),
            new Claim__c(Amount__c = 50, ClaimantName__c = 'Carol')
        };

        Test.startTest();
        Decimal total = BestPracticesDemo.calculateTotalAmount(claims);
        Test.stopTest();

        System.assertEquals(400, total, 'Total should be sum of Amount__c values');
    }

    @isTest
    static void testProcessClaims_StatusTransitions() {
        // Create and insert two claims with required fields
        Claim__c cNew = new Claim__c(
            Amount__c = 500,
            ClaimantName__c = 'Test Person',
            Status__c = 'New'
        );

        Claim__c cApproved = new Claim__c(
            Amount__c = 750,
            ClaimantName__c = 'Other Person',
            Status__c = 'Approved'
        );

        insert new List<Claim__c>{ cNew, cApproved };

        List<Claim__c> toProcess = [SELECT Id, Status__c, Amount__c, ClaimantName__c FROM Claim__c WHERE Id IN :new List<Id>{cNew.Id, cApproved.Id}];

        Test.startTest();
        BestPracticesDemo.processClaims(toProcess);
        Test.stopTest();

        // Refresh from DB and assert transitions
        Claim__c cNewRef = [SELECT Id, Status__c FROM Claim__c WHERE Id = :cNew.Id];
        Claim__c cApprovedRef = [SELECT Id, Status__c FROM Claim__c WHERE Id = :cApproved.Id];

        System.assertEquals('Approved', cNewRef.Status__c, 'New should transition to Approved');
        System.assertEquals('Rejected', cApprovedRef.Status__c, 'Approved should transition to Rejected');
    }
}
// Generate a test class for BestPracticesDemo
