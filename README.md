# Private Font Repository

A secure, automated font collection for Windows with AES-256 encrypted archives, multi-threaded parallel installation, and a modern CLI installer utility.

> [!IMPORTANT]
> This repository contains private encrypted font archives. Decryption requires an authorized password.

---

## 🚀 Quick Install (Windows)

Open PowerShell and run:

```powershell
irm https://raw.githubusercontent.com/aaxyat/fonts/main/install.ps1 | iex
```

### 🧪 Dry Run Test (No System Changes)

To test password verification, download pipeline, and archive integrity without modifying system fonts:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/aaxyat/fonts/main/install.ps1))) -DryRun
```

---

## ✨ Features

- **⚡ Fast Concurrent Downloads**: Uses portable `aria2c` with 16 connections per file for maximum speed.
- **⚡ Parallel Installation**: Multithreaded font copying & registry registration across 16 worker threads (PowerShell 7+).
- **🔒 AES-256 Encryption**: Header-encrypted 7z archives with SHA-256 password hash verification.
- **📊 Modern Progress Bar**: Custom single-line live console progress indicator.
- **🛡️ Lock Prevention**: GDI32 font resource unhooking prevents Windows active file lock errors.

---

## 🛠️ Repository Structure

```
.
├── Fonts/
│   ├── Fonts.7z.001   # AES-256 encrypted volume part 1 (35.00 MB)
│   ├── Fonts.7z.002   # AES-256 encrypted volume part 2 (35.00 MB)
│   ├── Fonts.7z.003   # AES-256 encrypted volume part 3 (35.00 MB)
│   ├── Fonts.7z.004   # AES-256 encrypted volume part 4 (35.00 MB)
│   ├── Fonts.7z.005   # AES-256 encrypted volume part 5 (35.00 MB)
│   └── Fonts.7z.006   # AES-256 encrypted volume part 6 (15.80 MB)
├── install.ps1        # PowerShell automated installer with progress UI & parallel engine
├── LICENSE            # Restrictive Proprietary License
└── README.md          # Documentation
```

---

## 🔒 License

All rights reserved © 2026 Aaxyat. 

This repository is private and proprietary. Unauthorized redistribution, extraction, or public hosting is strictly prohibited. See [LICENSE](file:///c:/Users/aaxyat/Documents/Github/Fonts/LICENSE) for details.
