# 🚀 QUICK START: Backend Configuration

## ⚡ Fastest Way to Change Backend URL

### Step 1: Open App
Open the Flutter app on your device

### Step 2: Click Settings ⚙️
Look for the **settings button** in the top-right corner

### Step 3: Enter Backend URL
Example formats:
```
http://192.168.1.100:5000          (Same WiFi)
https://abc123.ngrok.io             (ngrok tunnel)
http://api.example.com:5000         (Remote server)
```

### Step 4: Click Save
That's it! URL is now saved locally.

---

## 📱 Most Common URLs

### For Physical Device (Same WiFi)
```
http://YOUR_LAPTOP_IP:5000
```

Find your laptop IP:
```bash
# Windows
ipconfig          # Look for IPv4 Address (usually 192.168.x.x)

# Mac
ifconfig          # Look for inet under en0/en1

# Linux
hostname -I       # First IP address
```

### For Android Emulator (No WiFi)
```
http://10.0.2.2:5000
```

### For Web Browser
```
http://127.0.0.1:5000
or
http://localhost:5000
```

### For Testing Anywhere (Use ngrok)
```
https://your-ngrok-url.ngrok.io
```

---

## 🔧 Alternative: Command Line

Pass URL when running app:

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.100:5000
```

---

## ✅ Verify It Works

1. Open Settings (⚙️ button)
2. Check current Backend URL
3. Try logging in
4. Should connect successfully ✅

---

## 🆘 If Connection Fails

1. **Same WiFi?** → Both laptop & phone on same network?
2. **Backend running?** → Is Flask server running?
3. **Correct IP?** → Did you enter laptop's IP correctly?
4. **URL format?** → Starts with `http://` or `https://`?

---

## 🌍 Work from Anywhere

For different networks/cities, use **ngrok**:

```bash
# Terminal 1: Run your backend
python app.py

# Terminal 2: Start ngrok tunnel
ngrok http 5000

# Get URL like: https://abc123.ngrok.io
# Enter this URL in app settings
```

---

## 📚 Full Guide

See `BACKEND_CONFIGURATION.md` for complete documentation

---

**TL;DR:** Click ⚙️ → Enter URL → Click Save → Done!

