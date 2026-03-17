# 🚜 Agri Logistics Platform

Smart collective logistics platform for agricultural produce transportation with farmer, transporter, and retailer roles.

## Quick Start

### Terminal 1 - Start Backend
```powershell
cd backend
.\.venv\Scripts\Activate.ps1
python app.py
```

### Terminal 2 - Run App
```powershell
flutter run
```

## Backend Environments (Release/Dev Split)

- **Release builds** always use `https://api.agriapp.com` (REST) and `wss://api.agriapp.com` (WebSocket).
- **Dev runs** default to local backend endpoints:
  - Web/Desktop: `http://127.0.0.1:5000`
  - Android Emulator: `http://10.0.2.2:5000`
- For physical devices on same WiFi, pass your laptop IP via dart-define.

### Dev Run (Physical Device -> Laptop Backend)
```powershell
flutter run --dart-define=API_BASE_URL=http://192.168.1.100:5000
```

### Release Build (Locked to Production Domain)
```powershell
flutter build apk --release
```

## Test Accounts

| Role | Phone | Password |
|------|-------|----------|
| Farmer | 1234567890 | 123 |
| Transporter | 9623810809 | 123 |
| Retailer | 2222222222 | 123 |

## Features

- ✅ REST API integration
- ✅ Multi-user support (Farmer, Transporter, Retailer)
- ✅ MongoDB database
- ✅ Cost splitting for shared logistics
- ✅ Real-time data sync
- ✅ No IP configuration needed
- ✅ Works on any device, any location

## Prerequisites

- Python 3.8+
- MongoDB running locally
- Flutter SDK
- Android SDK or Emulator

## Technology Stack

- **Backend:** Flask + Python
- **Frontend:** Flutter + Dart
- **Database:** MongoDB
- **API:** REST API (HTTP)
- **Protocol:** JSON

## Data Access Clarification

Flutter cannot talk directly to databases like MongoDB or MySQL.
You need a server-side backend (for example Node.js, Python/FastAPI, or Go) as the middle layer.

Correct flow:

`Flutter App -> Backend API (REST/WebSocket) -> Database`

In this project, that backend middle layer is Python/Flask in `backend/app.py`.

## Project Structure

```
agri_logistic_platform/
├── lib/main.dart          # Flutter app
├── backend/
│   ├── app.py            # Flask server
│   ├── requirements.txt
│   └── .env
├── pubspec.yaml          # Flutter dependencies
└── README.md             # This file
```

## How It Works

1. **Farmer** posts transport request
2. **Transporter** accepts the request
3. **Retailer** broadcasts product demands
4. **Farmer** can accept retailer demands
5. All data synced via MongoDB

## No IP Configuration

No manual IP entry UI is needed in the app.

- In **release**, endpoint is fixed to production domain.
- In **dev**, defaults are auto-selected by platform, with optional dart-define override when using a physical device.

## Working on Physical Device

For local laptop backend in dev mode, phone and laptop should usually be on the same network unless you expose the backend publicly.

## Troubleshooting

**App won't connect:**
```powershell
# Check Flask is running
curl http://127.0.0.1:5000/health

# Check MongoDB
mongosh

# Restart Flask if needed
```

**Flutter issues:**
```powershell
flutter clean
flutter pub get
flutter run
```

## Build APK

```powershell
flutter build apk --release
```

Output: `build/app/outputs/apk/release/app-release.apk`

## Make It Work From Anywhere

To support any device, any network, and different IP locations, backend must be public.

Recommended setup:

1. Deploy backend to Render using `render.yaml` in repo root.
2. Use MongoDB Atlas for cloud database.
3. Point domain `api.agriapp.com` to deployed backend.
4. Build and share release app.

Release app endpoint targets:

- REST: `https://api.agriapp.com`
- WebSocket: `wss://api.agriapp.com`

Optional dev run override (physical phone to laptop backend):

```powershell
flutter run --dart-define=API_BASE_URL=http://192.168.1.100:5000
```

## College/Laptop Network Change Guide

When you move to college/home/another WiFi, your laptop IP usually changes.

- Start backend on laptop.
- Find new laptop IPv4 with `ipconfig`.
- Run Flutter with updated URL using `API_BASE_URL`.

See `STOP.md` for the full decision flow (same WiFi, hotspot, blocked college WiFi, and public access options).

## Notes

- Keep Flask backend running while using the app
- All data is automatically saved to MongoDB
- Multiple users can connect simultaneously
- Real-time updates via REST API
- No IP address configuration needed anywhere

---

**Ready to use! Just run the 2 commands above.** 🌾✨

