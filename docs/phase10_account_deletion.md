# CoinScan Phase 10: Permanent Account Deletion & Data Portability

**Date:** 2026-08-29  
**Author:** Principal Compliance & Security Architect  
**Document Version:** 1.0.0  
**Status:** **ACTIVE / VERIFIED**

---

## 1. Compliance Mandates

CoinScan complies fully with:
- **Apple App Store Guideline 5.1.1(v):** Mandatory in-app account deletion initiation and immediate cascading data purge for apps that support account creation.
- **GDPR Article 17 (Right to Erasure):** Complete permanent deletion of all associated personal identifiable information, collection records, and scan history.
- **GDPR Article 20 (Right to Data Portability):** In-app structured JSON export containing all user-submitted coin records and collection metadata without secret leakage.

---

## 2. Deletion Workflow & Safeguards

```
+---------------------------------------------------------------------------------------------------+
|                                 ACCOUNT DELETION EXECUTION FLOW                                   |
+---------------------------------------------------------------------------------------------------+

1. User navigates to Settings ──► Data Management & Privacy ──► Danger Zone: "Delete Account & Data"
2. Modal Confirmation Challenge displayed requiring explicit typing of "DELETE MY ACCOUNT".
3. Client issues authenticated request:
   POST /v1/account/delete
   Authorization: Bearer <user_jwt>
   Body: {"confirm_phrase": "DELETE MY ACCOUNT", "reason": "..."}
4. Backend verifies JWT authenticity and checks confirmation phrase.
5. Cascading Deletion Trigger:
   ├── Purge user profile metadata (`public.users`)
   ├── Delete collection vault items (`public.collection_items`)
   ├── Delete scan usage records (`public.scan_usage`)
   ├── Invalidate & revoke all developer API keys (`api_key_service.revoke_key()`)
   └── Trigger asynchronous object storage purge for private vault images
6. Client-Side Purge:
   ├── Clear Keychain tokens (`SecureStorageService.deleteAll()`)
   ├── Clear local scan history (`ScanHistoryService.clearHistory()`)
   ├── Clear local collection vault (`CollectionStorageService.clearCollection()`)
   └── Reset `AuthService` state to Guest mode.
```

---

## 3. Data Portability (Export Engine)

- Accessible via `GET /v1/account/export`.
- Exports:
  1. User profile data (display name, creation timestamp, tier)
  2. Complete collection vault items (dates added, purchase prices, valuations, notes, custom tags)
  3. Scan history records (timestamps, identified coins, confidence ratings)
  4. Submitted feedback reports
- **Security Guarantee:** Cryptographic salts, password hashes, payment webhook secrets, and developer API key hashes are strictly excluded from data exports.
