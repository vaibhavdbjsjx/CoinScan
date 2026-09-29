# CoinScan Phase 6: Image Privacy & Data Lifecycle Audit

**Date:** 2026-08-26  
**Auditor:** Senior Principal Security Engineer  
**Objective:** End-to-end audit of photographic capture transmission, server memory lifecycle, logging hygiene, and external AI provider data retention policies.

---

## 1. Local Device Lifecycle (iOS / Flutter Client)
* **Intake:** Real camera captures or gallery imports create a temporary image file in the application's isolated sandbox cache directory (`NSTemporaryDirectory()` on iOS).
* **Transmission:** Compressed JPEG bytes are streamed directly via HTTP multipart POST over TLS (HTTPS).
* **Cleanup:** The temporary local image files can be cleared on scan session completion.

---

## 2. Server Memory & Disk Retention (FastAPI Backend)
* **Disk Write Audit:** The backend (`backend/app/api/recognition.py`) reads uploaded images directly into ephemeral memory via `await front_image.read()`. **Zero image files are written to server disk or `/tmp`.**
* **Memory Lifecycle:** Ephemeral byte buffers are processed through Pillow/NumPy for quality validation, normalized, base64-encoded, sent to the vision provider over HTTPS, and immediately deallocated upon route return.
* **Logging Hygiene:** Server logs contain structured metadata only (`request_id`, client IP hash, latency ms, status code, identified coin title). **No image bytes, base64 strings, or personal identifying tokens are logged.**

---

## 3. External AI Provider Data Policies
* **Google Gemini API (Generative Language API):**
  - Requests sent with API keys on paid tier or enterprise projects are not used to train or fine-tune Google AI models.
  - Data is processed in transient memory for the duration of inference.
* **OpenAI API (GPT-4o / GPT-4o-mini):**
  - Zero Data Retention (ZDR) policy: API inputs are not used for model training.

---

## 4. Compliance & Privacy Rating
* **Verdict:** **COMPLIANT & SECURE**.
* **Recommendations:** Implement automatic 24-hour cache eviction in Flutter client sandbox and provide an explicit in-app Privacy Policy link.
