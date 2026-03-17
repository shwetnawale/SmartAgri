# STOP.md - If App Stops Working On New Network

Use this when you move to college/home/another WiFi and app cannot connect.

## Why it stops

Your backend runs on your laptop. When network changes, laptop IP changes.
Your app must use the current laptop IP unless backend is public.

## Quick decision

- Same network (phone + laptop): use laptop IP and it works.
- Different network/location: local laptop IP will not work.
- College WiFi with client isolation: may block phone -> laptop even on same WiFi.

## Fast fix at college

1. Start backend on laptop.
2. Get laptop IPv4.
3. Run app with updated `API_BASE_URL`.
4. If blocked on college WiFi, use laptop hotspot.

## Commands (Windows PowerShell)

### 1) Start backend
```powershell
cd C:\Users\nshwe\StudioProjects\agri_logistic_platform\backend
python app.py
```

### 2) Find laptop IP
```powershell
ipconfig
```
Use IPv4 value like `192.168.43.120`.

### 3) Run app with new URL
```powershell
cd C:\Users\nshwe\StudioProjects\agri_logistic_platform
flutter run --dart-define=API_BASE_URL=http://192.168.43.120:5000
```

### 4) Build APK with new URL (if sharing APK)
```powershell
cd C:\Users\nshwe\StudioProjects\agri_logistic_platform
flutter build apk --release --dart-define=API_BASE_URL=http://192.168.43.120:5000
```

APK path:
`build/app/outputs/flutter-apk/app-release.apk`

## If college WiFi still does not work

Some campuses block device-to-device traffic.

Use one of these:

1. **Laptop hotspot (recommended for demos)**
   - Turn on laptop hotspot.
   - Connect phone to laptop hotspot.
   - Use laptop hotspot IP in `API_BASE_URL`.

2. **Public backend URL (best long-term)**
   - Deploy backend to cloud.
   - Use one fixed URL in app, for example `https://api.agriapp.com`.

3. **Temporary tunnel (quick remote test)**
   - Use ngrok/cloudflared to expose `:5000`.

## Verify before login

From phone browser (same network), open:

`http://<LAPTOP_IP>:5000/health`

If this URL does not open, app will not connect either.

## Most common errors

- `Connection refused` -> backend not running or wrong IP/port.
- `Timeout` -> network blocked or firewall issue.
- `Unauthorized` -> API key mismatch (if enabled).

## One-line rule

Local laptop backend works only when phone can reach laptop IP.
For anywhere/any network use, backend must be public.

