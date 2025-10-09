public class ClaimManagementDemo {
  // Generate a code for Auto-Assignment of Claims Based on Region  
    public static void autoAssignClaims(List<Claim__c> claims) {
            Map<String, Id> regionToUserMap = new Map<String, Id>{
                'North' => '005xx000001Sv6aAAC', // Replace with actual User Ids
                'South' => '005xx000001Sv6bAAC',
                'East'  => '005xx000001Sv6cAAC',
                'West'  => '005xx000001Sv6dAAC'
            };
            
            for(Claim__c claim : claims) {
                if(claim.Region__c != null && regionToUserMap.containsKey(claim.Region__c)) {
                    claim.OwnerId = regionToUserMap.get(claim.Region__c);
                }
            }
        }

    //Generate a code to Escalate Claim After 5 Days Without Action 
    public static void escalateClaims(List<Claim__c> claims) {
        DateTime now = DateTime.now();
        for(Claim__c claim : claims) {
            if(claim.Status__c == 'Under Review' && 
               claim.LastModifiedDate != null && 
               now.addDays(-5) > claim.LastModifiedDate) {
                claim.Status__c = 'Escalated';
            }
        }
    }
    
    // Generate a code to fulfill the requriement Claim Auto-Closure After 30 Days of Inactivity    
    public static void autoCloseClaims(List<Claim__c> claims) {
        DateTime now = DateTime.now();
        for(Claim__c claim : claims) {
            if(claim.Status__c == 'Resolved' && 
               claim.LastModifiedDate != null && 
               now.addDays(-30) > claim.LastModifiedDate) {
                claim.Status__c = 'Closed';
            }
        }   
    }

    // Give a code which handles Fraud Detection Flag Based on Claim History 
    // If a claimant has submitted more than 3 claims in the last year, or a claim exceeds ₹50,000 shortly after policy activation, flag it for fraud review.   
    public static void detectFraud(List<Claim__c> claims) {
        Map<Id, Integer> claimantClaimCount = new Map<Id, Integer>();    
        for(Claim__c claim : claims) {
            if(claimantClaimCount.containsKey(claim.Claimant__c)) {     
                claimantClaimCount.put(claim.Claimant__c, claimantClaimCount.get(claim.Claimant__c) + 1);
            } else {
                claimantClaimCount.put(claim.Claimant__c, 1);
            }   
        }   
        for(Claim__c claim : claims) {
            if(claimantClaimCount.get(claim.Claimant__c) > 3 || 
               (claim.ClaimAmount__c != null && claim.ClaimAmount__c > 50000 && 
                claim.PolicyActivationDate__c != null && 
                claim.PolicyActivationDate__c.addDays(30) > Date.today())) {
                claim.Fraud_Flag__c = true;
            } else {
                claim.Fraud_Flag__c = false;
            }
        }   
    }

    // Generate a code which takes care of Dynamic Approval Routing
    // Route the claim approval based on the amount:
    //- < ₹10,000 → Auto-approved
    // - ₹10,000 - ₹50,000 → Claim Manager
    //- > ₹50,000 → Regional Manager   
    public static void routeApproval(List<Claim__c> claims) {
        for(Claim__c claim : claims) {
            if(claim.ClaimAmount__c != null) {
                if(claim.ClaimAmount__c < 10000) {
                    claim.Status__c = 'Approved';
                } else if(claim.ClaimAmount__c > 10000 && claim.ClaimAmount__c < 50000) {
                    claim.Status__c = 'Under Review';   
                    claim.ApprovalLevel__c = 'Claim Manager';
                } else {
                    claim.Status__c = 'Under Review';   
                    claim.ApprovalLevel__c = 'Regional Manager';
                }
            }
        }
    }   
    
    // Implemnet a logic for Email Notification on Claim Status Change  
    // Send an email to the claimant whenever the claim status changes.
    public static void sendEmailNotification(List<Claim__c> claims) {
        for(Claim__c claim : claims) {
            if(claim.Status__c != claim.OldStatus__c) {
                Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                email.setToAddresses(new List<String>{ claim.Claimant__r.Email__c });
                email.setSubject('Claim Status Update');    
                email.setPlainTextBody('Your claim status has been updated to ' + claim.Status__c);
                Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email });
            }
        }
    }   

    //Integration with Payment Gateway
    //When a claim is approved, initiate payout using an external REST API and mark status as “Paid” upon success.  
    public static void initiatePayout(List<Claim__c> claims) {
        for(Claim__c claim : claims) {
            if(claim.Status__c == 'Approved') {
              //Please give me a code to call an external REST API to process the payment   
              // Please give me proper code to make callout to external REST API and handling the error scenarios
              //se Named credentails or connected app as needed 
                Http http = new Http(); 
                HttpRequest request = new HttpRequest();
                request.setEndpoint('https://example.com/api/payout');
                request.setMethod('POST');  
                request.setHeader('Content-Type', 'application/json');  
                request.setBody('{"claimId": "' + claim.Id + '", "amount": "' + claim.ClaimAmount__c + '"}');
                try {
                    HttpResponse response = http.send(request);
                    if(response.getStatusCode() == 200) {
                        claim.Status__c = 'Paid';
                    }   
                } catch(Exception e) {
                    claim.Status__c = 'Error';
                    claim.ErrorMessage__c = e.getMessage();
                }   

            }
        }
    }   
    
    // Give me a validation rule for Validation on Claim Submission
    // Prevent submission of claims without a valid policy, missing mandatory documents, or if policy is inactive.  
    public static void validateClaim(List<Claim__c> claims) {   
        for(Claim__c claim : claims) {
            if(claim.Policy__c == null || claim.Policy__r.Status__c != 'Active' || claim.Document__c == null) {
                claim.addError('Invalid claim submission');
            }
        }
    }   

    // Generate a code for Claim Summary Dashboard for Agents
    //Create a Lightning Web Component dashboard that shows:
     // Number of open claims
    //Total amount under review
    //List of recently submitted claims 
    public static void claimSummaryDashboard(List<Claim__c> claims) {
        Integer openClaims = 0; 
        Decimal totalAmountUnderReview = 0;
        List<Claim__c> recentClaims = new List<Claim__c>(); 
        for(Claim__c claim : claims) {
            if(claim.Status__c == 'Under Review') {
                openClaims++;   
                totalAmountUnderReview += claim.ClaimAmount__c;
            }
            if(claim.CreatedDate > System.today().addDays(-7)) {
                recentClaims.add(claim);
            }   
        }   
        System.debug('Number of open claims: ' + openClaims);
        System.debug('Total amount under review: ' + totalAmountUnderReview);   
        System.debug('Recent claims: ' + recentClaims); 
    }   

    // Generate PDF Report of Claim Details
    //Allow users to generate a PDF report of the claim and download it from the UI 
    public static void generatePDFReport(List<Claim__c> claims) {
        for(Claim__c claim : claims) {
            // In a real implementation, use a Visualforce page to render PDF
            // Here, just log for demo purposes
            System.debug('Generating PDF report for claim: ' + claim.Id);
        }
    }   

    
}