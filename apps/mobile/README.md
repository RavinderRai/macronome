# Macronome Mobile App

**Eat in Rhythm, Not in Restriction**

Macronome is an AI-powered nutrition co-pilot that helps you decide what to eat next — not by counting calories, but by keeping your meals in rhythm with your goals, cravings, and what's in your kitchen.

## Features

- 💬 **AI Chat Interface** - Chat with Macronome about your diet and get personalized meal recommendations
- 📷 **Pantry Scanning** - Scan your fridge to see what ingredients you have using computer vision
- 🎯 **Smart Filtering** - Filter recommendations by calories, macros, diet type, prep time, and allergies
- 🍽️ **Instant Recommendations** - Get personalized meal suggestions that fit your constraints
- 📊 **Preference Learning** - AI learns your preferences over time

## Tech Stack

- **React Native** with **Expo**
- **TypeScript**
- **Clerk** for authentication
- **Zustand** for state management
- **React Native Gesture Handler** & **Bottom Sheet** for UI interactions

## Development

### Prerequisites

- Node.js 18+
- Expo CLI
- iOS Simulator (for iOS) or Android Emulator (for Android)

### Setup

1. Install dependencies:
```bash
npm install
```

2. Create a `.env` file in the `apps/mobile` directory:
```env
CLERK_PUBLISHABLE_KEY=your_clerk_key
API_BASE_URL=your_api_url
```

3. Start the development server:
```bash
npx expo start
```

4. Run on device/simulator:
   - Press `i` for iOS simulator
   - Press `a` for Android emulator
   - Scan QR code with Expo Go app on physical device

## Building

### Development Build
```bash
eas build --platform android --profile preview
```

### Production Build
```bash
eas build --platform android --profile production
```

### Submit to Google Play
to regenerate android files (for icon image and related assets)
```bash
npx expo prebuild --platform android --clean
```

```bash
eas submit --platform android
```

## Project Structure

```
apps/mobile/
├── src/
│   ├── components/     # Reusable UI components
│   ├── screens/        # Screen components
│   ├── services/       # API services
│   ├── store/          # Zustand state management
│   ├── contexts/       # React contexts
│   ├── theme/          # Theme configuration
│   └── utils/          # Utility functions
├── assets/             # Images, icons, fonts
├── android/           # Android native code
└── app.config.ts      # Expo configuration
```

## Environment Variables

Set these in your `.env` file or via EAS Secrets:

- `CLERK_PUBLISHABLE_KEY` - Clerk authentication publishable key
- `API_BASE_URL` - Backend API base URL

## License

See main project README for license information.
