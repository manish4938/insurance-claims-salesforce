
# 📄 Salesforce Claim Management – Business Scenarios

This document outlines practical business scenarios for an Insurance Claim Management System. These scenarios can be used to design, implement, and test functionality using GitHub Copilot and Salesforce development tools.

---

## 🧠 Scenario 1: Auto-Approval of Low-Value Claims

### Business Rule:
If a claim amount is less than ₹5,000 and has no history of fraud or multiple claims, it should be auto-approved.

### Acceptance Criteria:
- Claim is approved automatically without human intervention.
- Approval level is set to "System Auto-Approval".

---

## 🧠 Scenario 2: Manager Review for Mid-Value Claims

### Business Rule:
If the claim amount is between ₹5,000 and ₹25,000, assign the claim to a Claim Manager for manual review.

### Acceptance Criteria:
- Approval level is set to "Claim Manager".
- Notification is sent to manager group.

---

## 🧠 Scenario 3: Senior Manager Approval for High-Value Claims

### Business Rule:
If the claim amount exceeds ₹25,000, the claim must be reviewed and approved by a Senior Manager.

### Acceptance Criteria:
- Claim status is set to "Pending Senior Approval".
- Approval level is "Senior Manager".
- Notification to Senior Manager and audit logging required.

---

## 🧠 Scenario 4: Claim Rejection Due to Incomplete Documentation

### Business Rule:
If required documents like FIR, medical report, or policy documents are missing, reject the claim.

### Acceptance Criteria:
- Claim status is updated to "Rejected".
- Rejection reason is captured.
- Claimant is notified via email.

---

## 🧠 Scenario 5: Duplicate Claims Detection

### Business Rule:
If a policyholder submits more than one claim with the same incident description and date, flag it as duplicate.

### Acceptance Criteria:
- Claim is flagged as "Potential Duplicate".
- Internal fraud team is notified.
- Claim is not auto-approved.

---

## 🧠 Scenario 6: Bulk Validation of Claims for Scheduled Job

### Business Rule:
Every night, a scheduled job validates all "New" claims and updates their status to "Under Review" if they pass basic checks.

### Acceptance Criteria:
- Bulk Apex job runs nightly.
- Claim statuses are updated in batch.
- Any failures are logged and retried.

---

## 🧠 Scenario 7: Payment Processing After Claim Approval

### Business Rule:
Once a claim is approved, initiate the payment process using a third-party payment gateway.

### Acceptance Criteria:
- Integration callout to payment service is made.
- Claim status updated to "Paid" on success.
- Failure is logged and retried via queueable Apex.

---

## 🧠 Scenario 8: Secure Access to Sensitive Fields

### Business Rule:
Only users with the "Claim Auditor" permission set can view and edit sensitive fields like ClaimAmount and PayoutDetails.

### Acceptance Criteria:
- Field-level security enforced in Apex and UI.
- Unauthorized users cannot access sensitive data.

---

## ✅ Usage with Copilot

For each scenario above, you can:
- Write Apex classes (e.g., `ClaimService`, `ClaimValidator`, `ClaimPaymentProcessor`)
- Write Triggers and Handlers (e.g., `ClaimTriggerHandler`)
- Write LWC components (e.g., `claimSummary`)
- Write Test Classes (e.g., `ClaimServiceTest`)
