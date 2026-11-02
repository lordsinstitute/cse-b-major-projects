# SecureAuthX

## Team Details

| Field | Details |
|---|---|
| **Team Name** | **B1_2** |
| **Project Title** | SecureAuthX: A Cross-Browser Extension for Secure Password Management and Website Security Analysis |
| **Institution** | Lords Institute of Engineering & Technology |
| **Department** | Computer Science and Engineering [B] |
| **Repository** | `1609237333106-SecureAuthX` |

## Team Members

| S. No. | Name | Roll Number |
|---:|---|---|
| 1 | Md Abdul Ahad Saud | `1609237333106` |
| 2 | Md Umar Ayaan | `160923733114` |
| 3 | Syed Abdur Rasheed | `160923733118` |
| 4 | Md Umar Farooq | `160923733110` |

## Project Overview

SecureAuthX is a browser extension project that combines local password management with website security and privacy analysis. It aims to help users protect their credentials and understand selected security and privacy risks on the websites they visit.

The project includes site-specific password derivation, password-strength and reuse analysis, an encrypted local credential vault, user-initiated autofill, website-security checks, selected browser-fingerprinting signals, tracker-signature detection, and rule-based risk assessment.

The current implementation is Chromium-oriented. Compatibility with browsers beyond Chromium has not yet been validated.

## Repository Contents

This repository is organized into the following folders:

| Folder | Contents |
|---|---|
| `SecureAuthx_Extension/` | Project source code and browser-extension files |
| `Research_Paper/` | Research paper and related academic material |
| `Project_Reviews_PPTS/` | Project review presentations and their PDF versions |

## Main Technologies

- **HTML, CSS and JavaScript** – extension interface and application logic
- **Chrome Extension Manifest V3** – browser-extension platform
- **Web Crypto API** – browser-native cryptographic operations
- **PBKDF2-HMAC-SHA-256** – password and key derivation
- **AES-256-GCM** – encrypted local vault
- **SHA-256** – password-reuse comparison hashes
- **Node.js** – test runtime
- **Playwright** – end-to-end browser testing

---

**SecureAuthX — Secure credentials. Safer browsing. Privacy by design.**
