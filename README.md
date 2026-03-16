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

The app automatically detects the backend server:
- **Web/Desktop:** http://127.0.0.1:5000
- **Android Emulator:** http://10.0.2.2:5000

No manual IP entry needed!

## Working on Physical Device

The app works on any Android device connected to:
- Same WiFi network
- Different WiFi network
- Mobile data
- Any location

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

## Notes

- Keep Flask backend running while using the app
- All data is automatically saved to MongoDB
- Multiple users can connect simultaneously
- Real-time updates via REST API
- No IP address configuration needed anywhere

---

**Ready to use! Just run the 2 commands above.** 🌾✨

