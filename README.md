# 📱 Groupify App

A real-time chat and instant messaging application built with Flutter and Firebase.

Groupify is a modern chat application that allows users to create accounts and communicate with other users in real time. Users can register and use their accounts to send and receive messages, including accounts created with non-real or anonymous profile information.

Messages and user data are stored in the cloud using Firebase Firestore, authentication is handled through Firebase Authentication, and real-time push notifications are provided using Firebase Cloud Messaging. The application also supports image and file sharing through Firebase Storage.

## ✨ Features

- 🔐 User registration and authentication with Firebase Auth
- 💬 Real-time and smooth messaging
- 🖼️ Image and file sharing
- 👤 User profiles and account creation
- 🎨 Modern and user-friendly UI

## 🛠️ Technologies

- Flutter
- Firebase
- Cloud Firestore
- Firebase Authentication
- Firebase Storage
- Firebase Cloud Messaging


## 📸 Screenshots

<p align="center">
  <img src="screenShots/image_1.jpg" width="200" />
  <img src="screenShots/image_2.jpg" width="200" />
  <img src="screenShots/image_3.jpg" width="200" />
  <img src="screenShots/image_4.jpg" width="200" />
</p>
<p align="center">
  <img src="screenShots/image_5.jpg" width="200" />
  <img src="screenShots/image_6.jpg" width="200" />
  <img src="screenShots/image_7.jpg" width="200" />
  <img src="screenShots/image_8.jpg" width="200" />
</p>

## 🚀 Getting Started

### Prerequisites

- Flutter SDK
- Firebase account
- Android Studio or VS Code

### Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/huzaifakhashan/GroupifyApp.git
   cd GroupifyApp
   ```

2. Install the dependencies:
   ```bash
   flutter pub get
   ```

3. Set up Firebase:
   - Create a new project on the [Firebase Console](https://console.firebase.google.com/)
   - Enable Authentication, Cloud Firestore, Storage, and Cloud Messaging
   - Add your Android/iOS app and download `google-services.json` / `GoogleService-Info.plist` into the appropriate platform folders
   - Or run `flutterfire configure` to generate `firebase_options.dart` automatically

4. Run the app:
   ```bash
   flutter run
   ```

## 📥 Download the App

👉 [Download Groupify APK](https://github.com/huzaifakhashan/GroupifyApp/releases/tag/v1.0.0)

## 📄 License

This project has no explicit license yet. All rights reserved by the author unless stated otherwise.

## 📬 Contact

Created by [Huzaifa Khashan](https://github.com/huzaifakhashan) — feel free to reach out with questions or suggestions.
