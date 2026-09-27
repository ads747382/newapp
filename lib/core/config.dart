/// Main server (new domain).
const String kDefaultServerUrl = 'https://makkahhostel.com/hostel';

/// Where logins saved by builds before multi-hostel (v1.5 and older) belong.
const String kLegacyServerUrl = 'https://ai.seojasoos.com/hostel';

/// Hostel lists, tried in order; the first one that loads wins. Edit the file on the server to
/// add a hostel; no app update needed. Format: see server/hostels.json in the project.
/// The ai.seojasoos.com copies keep the app working until makkahhostel.com is live.
const List<String> kHostelDirectoryUrls = [
  'https://makkahhostel.com/hostels.json',
  'https://www.makkahhostel.com/hostels.json',
  'https://ai.seojasoos.com/hostels.json',
  'https://ai.seojasoos.com/hostel.json',
];

/// Only hostels on these hosts (over https) are accepted from the list. This stops a
/// tampered or mistaken list from sending staff passwords to some other server.
/// ai.seojasoos.com stays while the move finishes; remove it in a later build.
const Set<String> kAllowedHostelHosts = {'makkahhostel.com', 'www.makkahhostel.com', 'ai.seojasoos.com'};

/// Used when no list can be downloaded and nothing is cached yet (first start offline).
const List<({String name, String url})> kBuiltInHostels = [
  (name: 'Makkah Hostel', url: 'https://makkahhostel.com/hostel'),
];

/// App name, shown in the app bar before the hostel name is loaded from the server.
const String kAppTitle = 'Makkah Hostel';
