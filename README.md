# NEXORA AI

NEXORA AI is a single-screen Android conversational assistant.

## App experience

- One chat interface; no owner dashboard, admin panel, cell tabs, or server-address setup.
- User messages are handled automatically.
- For non-greeting questions, the app searches the web and passes the collected results to Gemini for analysis and a response.
- Answers are shown in the same conversation.
- In-app update check downloads the latest APK release and opens Android's installer after user approval.

## First launch

On the first message, the app asks for a Gemini API key. The key is stored in Android secure storage on the device and sent directly to Google's Gemini API. No private backend or hosting service is required.

Create a key using Google AI Studio:
https://aistudio.google.com/app/apikey

The app currently uses the Gemini `gemini-2.5-flash` model and DuckDuckGo HTML search results. Web search availability depends on DuckDuckGo's public endpoint and may occasionally be unavailable.

## Build

GitHub Actions builds the Android release APK on pushes to `main` and publishes it as a GitHub Release asset.
