
# Claim Management System – Business Scenarios for Salesforce Development

This document outlines real-world business scenarios to implement and test in your Salesforce-based Claim Management application.

---

## Scenario 1: Auto-Assignment of Claims Based on Region

### Description:
When a new claim is submitted, it should be automatically assigned to a Claims Agent based on the region of the incident.

### Implementation Hints:
- Create a mapping between region and agent.
- Use Apex Trigger or Flow to auto-assign agent.
- Update `AssignedAgent__c` field on the Claim__c record.

---

## Scenario 2: Escalate Claim After 5 Days Without Action

### Description:
If a claim is not moved to “Under Review” or “Approved” status within 5 days of creation, it should be escalated to a supervisor.

### Implementation Hints:
- Use a Scheduled Apex job or Flow.
- Filter records in “New” status older than 5 days.
- Update status to “Escalated” and notify supervisor.

---

## Scenario 3: Claim Auto-Closure After 30 Days of Inactivity

### Description:
If a claim remains in “Pending Documents” status for more than 30 days, auto-close the claim.

### Implementation Hints:
- Use Apex batch or scheduled Flow.
- Track `LastModifiedDate`.
- Change status to “Closed - No Response”.

---

## Scenario 4: Fraud Detection Flag Based on Claim History

### Description:
If a claimant has submitted more than 3 claims in the last year, or a claim exceeds ₹50,000 shortly after policy activation, flag it for fraud review.

### Implementation Hints:
- Use Apex logic in service class.
- Add boolean field `FlaggedForFraud__c`.
- Optionally create a related Case for investigation.

---

## Scenario 5: Dynamic Approval Routing

### Description:
Route the claim approval based on the amount:
- < ₹10,000 → Auto-approved
- ₹10,000 - ₹50,000 → Claim Manager
- > ₹50,000 → Regional Manager

### Implementation Hints:
- Use Apex or Flow to determine approval level.
- Set `ApprovalLevel__c` picklist.
- Create Task or Notification for approver.

---

## Scenario 6: Email Notification on Claim Status Change

### Description:
Send an email to the claimant whenever the claim status changes.

### Implementation Hints:
- Use Process Builder or Flow with Email Alert.
- Include claim number and new status in the email body.

---

## Scenario 7: Integration with Payment Gateway

### Description:
When a claim is approved, initiate payout using an external REST API and mark status as “Paid” upon success.

### Implementation Hints:
- Use `@future` or `Queueable` Apex for HTTP callout.
- Update status field and log transaction details.

---

## Scenario 8: Validation on Claim Submission

### Description:
Prevent submission of claims without a valid policy, missing mandatory documents, or if policy is inactive.

### Implementation Hints:
- Validate using Apex before insert.
- Throw custom exception with proper error message.

---

## Scenario 9: Claim Summary Dashboard for Agents

### Description:
Create a Lightning Web Component dashboard that shows:
- Number of open claims
- Total amount under review
- List of recently submitted claims

### Implementation Hints:
- Use Apex controller to fetch data.
- Display in LWC using lightning-datatable and chart.

---

## Scenario 10: Generate PDF Report of Claim Details

### Description:
Allow users to generate a PDF report of the claim and download it from the UI.

### Implementation Hints:
- Use LWC + Apex to generate report.
- Use `PageReference` + `ContentVersion` or third-party PDF service.
