# CoinScan Privacy Policy

**Last Updated:** [Date]

## 1. Introduction

CoinScan ("we", "our", "the App") is a mobile application for numismatic coin identification and valuation. This Privacy Policy describes how we collect, use, and protect your information.

## 2. Information We Collect

### 2.1 Coin Images
- When you scan a coin, we temporarily process your coin images on our servers for identification purposes.
- **Images are processed in-memory and are NOT stored permanently on our servers.**
- Images are NOT logged, cached, or archived.
- After recognition is complete, image data is discarded.

### 2.2 Scan Results
- Identification results (coin name, year, denomination, confidence score) may be stored locally on your device for your scan history.
- This data remains on your device and is not synced to our servers unless you explicitly enable cloud sync.

### 2.3 Subscription Information
- If you subscribe, payment processing is handled entirely by Apple (via the App Store) or Google (via Google Play). We do not collect or store your payment card details.
- We receive a confirmation of your subscription status to manage access to premium features.

### 2.4 Usage Analytics
- We may collect anonymized, aggregated usage statistics (e.g., number of scans, feature usage) to improve the App.
- No personally identifiable information is included in analytics data.

## 3. Third-Party Services

### 3.1 AI Vision Analysis
- Coin images are sent to Google Gemini (Google AI) for visual analysis.
- Google's AI services process images under enterprise zero-data-retention policies — your images are not used to train AI models.
- See: [Google AI Privacy](https://ai.google.dev/terms)

### 3.2 Numismatic Catalogue (Numista)
- Coin identification results are verified against the Numista numismatic database.
- Only textual queries (country, denomination, year) are sent to Numista — not your images.
- Attribution: Numista N# identifiers are displayed per Numista's licensing requirements.

### 3.3 Valuation Data
- Live precious metal spot prices are retrieved from metals pricing APIs.
- Currency exchange rates are retrieved from exchange rate APIs.
- These queries do not include any personal information.

## 4. Data Security

- All communication between the App and our servers uses HTTPS encryption.
- Our backend runs on Google Cloud Run with industry-standard security controls.
- No API keys or secrets are stored in the mobile application.
- Server access is protected by API key authentication and rate limiting.

## 5. Data Retention

| Data Type | Retention |
|---|---|
| Coin images | Ephemeral (discarded after processing) |
| Scan history | Stored locally on device until deleted by user |
| Subscription status | Managed by Apple/Google |
| Analytics | Aggregated, anonymized, 90-day rolling window |

## 6. Your Rights

- **Delete scan history:** Settings > Clear Scan History
- **Cancel subscription:** Settings > Apple ID > Subscriptions
- **Request data deletion:** Contact [support@coinscan.app]

## 7. Children's Privacy

CoinScan does not knowingly collect information from children under 13. The App is not directed at children.

## 8. Changes to This Policy

We may update this Privacy Policy from time to time. The "Last Updated" date above indicates the most recent revision.

## 9. Contact

For questions about this Privacy Policy, contact:
- Email: [support@coinscan.app]
- Subject: "Privacy Policy Inquiry"
