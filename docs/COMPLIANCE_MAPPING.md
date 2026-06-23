# Compliance Mapping: Nokia PCF → AWS Config → Fintech (SOC 2 / PCI DSS)

> This document maps Nokia 5G Policy Control Function (PCF) concepts to AWS compliance controls, with specific SOC 2 and PCI DSS requirement references relevant to fintech/mortgage processing platforms.

---

## How This Mapping Works

Nokia 5G Core enforces runtime policies through the **PCF (Policy Control Function)**. The PCF delivers PCC (Policy and Charging Control) rules to the SMF, which enforces them on user sessions. In AWS, **AWS Config** plays the same role: it defines compliance rules and detects violations at the resource level.

The table below maps each Nokia PCF policy concept → the AWS Config rule that enforces it → the specific SOC 2 or PCI DSS requirement it satisfies.

---

## Mapping Table

| Nokia PCF Concept | What PCF Does | AWS Config Rule | Compliance Standard | Requirement |
|---|---|---|---|---|
| **Data protection policy** | PCF ensures subscriber data is encrypted in transit (TLS on SBI) and at rest (encrypted UDM storage) | `S3_BUCKET_SERVER_SIDE_ENCRYPTION_ENABLED` | PCI DSS | Req 3: Protect stored cardholder data |
| **Data protection policy** | Same | `RDS_STORAGE_ENCRYPTED` | PCI DSS | Req 3: Protect stored cardholder data |
| **Access gating** | PCF sends gating rules to SMF — block/allow traffic based on subscription state | `INCOMING_SSH_DISABLED` | SOC 2 | CC6.6: System boundary protection against external threats |
| **Access gating** | Same | `S3_BUCKET_PUBLIC_READ_PROHIBITED` | PCI DSS | Req 7: Restrict access to need-to-know |
| **Authentication enforcement** | PCF policies require UE authentication via AUSF before service access | `ROOT_ACCOUNT_MFA_ENABLED` | SOC 2 | CC6.1: Logical access security — multi-factor authentication |
| **Audit logging** | Nokia OAM logs all NF events; PCF logs all policy decisions for regulatory compliance | `CLOUD_TRAIL_ENABLED` | PCI DSS | Req 10: Track and monitor all access to network resources |
| **Session isolation** | PCF enforces per-slice QoS boundaries — traffic from one slice cannot impact another | VPC isolation + Security Groups | PCI DSS | Req 1: Install and maintain network security controls |
| **Change management** | Nokia CBAM tracks all CNF configuration changes; rollback capability | AWS Config change tracking + S3 versioning | SOC 2 | CC8.1: Change management controls |

---

## How to Use This in an Interview

When asked **"How would you ensure SOC 2 / PCI DSS compliance in our cloud infrastructure?"**, your answer structure should be:

1. **Reference the mapping:** "In my Nokia 5G work, we enforced compliance through the PCF — a centralized policy engine that pushed runtime rules to every network function. I've mapped that exact pattern to AWS Config."

2. **Give the concrete example:** "For PCI DSS Requirement 3 (protect stored data), Nokia PCF required encrypted storage in UDM. I've implemented the same control in AWS using Config rules that detect any S3 bucket or RDS instance without encryption enabled."

3. **Show the automation:** "In Nokia, PCF violations triggered automatic remediation via CBAM. In AWS, I've set up Config rules that trigger Lambda functions to auto-remediate — for example, automatically enabling encryption on an unencrypted S3 bucket."

---

## Sources

- 3GPP TS 23.501 Section 6.2.7 (PCF definition)
- Nokia CloudBand Application Manager documentation (nokia.com)
- AWS Config Managed Rules: https://docs.aws.amazon.com/config/latest/developerguide/managed-rules-by-aws-config.html
- SOC 2 Trust Services Criteria (AICPA)
- PCI DSS v4.0 Requirements: https://www.pcisecuritystandards.org/
