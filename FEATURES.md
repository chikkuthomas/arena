# 🎯 Arena Features

Complete feature documentation for Arena v1.0.2

## 🏠 Core Debate Features

### 1. Live Debate Rooms
- Create debate rooms on any topic
- **Public Rooms**: Anyone can discover and join
- **Private Rooms**: Password-protected access
- Real-time chat with Firestore
- Persistent room history
- Room creator info displayed

### 2. Stance System
- Choose "For" or "Against" when joining
- Clear visual distinction of stances
- Discussion organized by position
- Switch rooms to change stance

### 3. Live Chat
- Real-time messaging with latency < 1s
- Firestore message storage
- Full conversation history
- Timestamp on each message
- User name displayed with each message

### 4. Room Management
- **Create**: Start new debate room
- **Edit**: Modify room details
- **Delete**: Remove your own rooms
- **Leave**: Exit room anytime
- **Search**: Find rooms by name or topic

## 🔍 Room Discovery

### Browse Public Rooms
- **Room List**: See all public debates
- **Search**: Find rooms by name or topic
- **Category Filter**: Filter by debate category
  - Politics
  - Technology
  - Science
  - Sports
  - Entertainment
  - Society
  - Other

### Trending Rooms
- **Active Debates**: Show rooms with activity in last 24 hours
- **Participant Count**: See how many are debating
- **Latest Activity**: Sort by most recent chat

### One-Click Join
- Tap room to join instantly
- Select stance (For/Against)
- Enter live chat immediately

## 🔗 Room Sharing

### Share Dialog
- **Room ID**: Unique identifier (e.g., `debate-abc123xyz`)
- **Shareable Link**: Full deep link (e.g., `https://arena.app/room/debate-abc123xyz`)
- **Copy Buttons**: One-click copy to clipboard

### Share Methods
- WhatsApp integration
- Email integration
- Generic share options
- Direct link sharing

### Join Shared Rooms
- Click shared link
- Opens Arena app directly
- Falls back to Play Store if not installed
- Automatic room loading and join

## 🎯 Join Methods

### Method 1: Search & Tap
1. Open Discover screen
2. Search for room name
3. Tap room in results
4. Select stance
5. Join debate

### Method 2: Enter Code
1. Tap "Join by Code"
2. Paste room ID or full link
3. App extracts room ID
4. Validates and opens room
5. Select stance and join

### Method 3: Click Link
1. Receive shared link
2. Click link from any app
3. Arena opens automatically
4. Room loads and displays join screen
5. Select stance and enter

## 🎂 Topic of the Day

- **Featured Debate**: Daily rotating topic
- **Auto-Created Room**: System creates room at midnight
- **9 AM Notification**: Reminder at 9:00 AM local time
- **Easy Access**: Quick link to today's debate
- **Discussion**: Open for all users

## 🛡️ Moderation & Safety

### User Blocking
- Block users locally on your device
- Blocked users messages hidden
- Can unblock anytime

### Report Function
- Report inappropriate messages
- Report roomsNot suitable for debate
- Report reason selection
- Admin review of reports

### Message Moderation
- Delete your own messages
- Message edit/removal
- Room history maintained

### Room Management
- Creator controls room access
- Can make room private/public
- Can password-protect rooms
- Can delete room if needed

## 📊 Room Information

### Room Details Shown
- Room name/topic
- Category
- Created by (creator name)
- Participant count
- Creation date
- Last activity time
- Privacy status (Public/Private)

### Room Creation Options
- **Topic**: The debate question
- **Category**: Debate category selection
- **Privacy**: Public or Private
- **Password**: Optional for private rooms
- **Name**: Room name/title

## 🔐 Privacy & Security

### Room Privacy
- Public rooms: Discoverable and open
- Private rooms: Requires password
- Room creator: Controls access

### Data Security
- Firestore encryption
- Secure authentication
- User data privacy

### Content Moderation
- Report inappropriate content
- Block disruptive users
- Message deletion
- Room reporting

## ⚙️ Technical Features

### Real-Time Sync
- Live message delivery
- Instant room list updates
- Real-time participant count
- Active user status

### Local Features
- Offline message drafting
- Local user blocking
- Shared preferences storage
- Device notifications

### Performance
- Optimized queries
- Minimal data usage
- Fast search
- Smooth animations

### Firebase Integration
- **Firestore**: Room and message storage
- **Authentication**: User identity
- **Cloud Messaging**: Push notifications (planned)

## 🌍 Categories

Eight debate categories available:

1. **Politics** - Political discussions and debates
2. **Technology** - Tech news, gadgets, AI
3. **Science** - Scientific discoveries and theories
4. **Sports** - Sports events and athletes
5. **Entertainment** - Movies, music, celebrities
6. **Society** - Social issues and culture
7. **Other** - Miscellaneous topics
8. **All** - Show all categories

## 📱 User Interface

### Home Screen (Your Rooms)
- Your debate rooms only
- Search your rooms
- Filter by category
- Create new room button
- Quick access to recent

### Discover Screen
- All public rooms
- Search functionality
- Category filtering
- Trending section
- Join by code option

### Room Screen
- Live chat display
- Message input field
- Stance indicator
- Participant list
- Share button
- Moderation options

### Settings/Profile
- User preferences
- Account management
- Blocked users list
- Notification settings

## 🚀 Onboarding & App Settings

*(Added in 1.13.0, from the Testers Community feedback report.)*

### New-User Walkthrough
- Four-slide intro shown **once per phone** on first launch
- Covers: what Arena is, picking For/Against, debating live, voting on who won
- **Skip** button on every slide, so nobody is ever trapped in it
- Replayable any time from Settings → Replay walkthrough

### Settings Screen
Reached from the account menu (avatar, top right):
- **Rate Arena** — opens the Play Store listing
- **Share Arena** — opens the share sheet with an invite + store link
- **Replay walkthrough** — shows the intro again
- **Terms of Service** / **Privacy Policy** — previously login-screen only

### Smart Rating Prompt
- Google's native in-app review sheet appears **once**, after the user has come
  out of 5 debate rooms — never on first launch, never repeatedly
- Counted locally in `SharedPreferences`; no server involvement

## 🔜 Planned Features

### v1.1
- Google/phone authentication
- Push notifications
- Admin panel
- User profiles
- Reputation system

### v2.0
- Audio debates
- Video streaming
- Debate scheduling
- AI moderation
- Leaderboards
- Analytics

---

**Last Updated**: June 28, 2026  
**Version**: 1.0.2
