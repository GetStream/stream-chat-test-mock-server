# Stream Chat

__[Stream Chat SDKs](https://getstream.io/chat/docs/)__ are the official SDKs for [Stream Chat](https://getstream.io/chat/), a service for building chat and messaging applications.

Please refer to the main repositories for more information:

- [Stream Chat SDK for iOS (UIKit) on GitHub](https://github.com/getstream/stream-chat-swift)
- [Stream Chat SDK for iOS (SwiftUI) on GitHub](https://github.com/getstream/stream-chat-swiftui)
- [Stream Chat SDK for Android on GitHub](https://github.com/getstream/stream-chat-android)
- [Stream Chat SDK for Flutter on GitHub](https://github.com/getstream/stream-chat-flutter)
- [Stream Chat SDK for React Native on GitHub](https://github.com/GetStream/stream-chat-react-native)

# Stream Chat Mock Server

This repository serves as a mock server for our internal cross-platform automated testing purposes.

## Usage

### Install dependencies:

```bash
bundle install
```

### Sync mock server with real backend:

```bash
bundle exec ruby sync.rb
```

### Run mock server for manual testing:

```bash
bundle exec ruby src/server.rb
```

### Run mock server for automated testing:

```bash
bundle exec ruby driver.rb
```
