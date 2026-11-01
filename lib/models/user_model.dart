class AppUser {
  final String name;
  final String username;
  final int mutualFriends;
  final List<String> sharedInterests;
  final List<String> sameGroups;

  const AppUser({
    required this.name,
    required this.username,
    required this.mutualFriends,
    this.sharedInterests = const [],
    this.sameGroups = const [],
  });
}

const allUsers = [
  AppUser(
    name: 'Alex Johnson',
    username: '@alexjohnson',
    mutualFriends: 3,
    sharedInterests: ['Hiking', 'Photography', 'Basketball'],
    sameGroups: ['Book Lovers Club', 'Hiking Enthusiasts'],
  ),
  AppUser(
    name: 'Sophie Chen',
    username: '@sophiec',
    mutualFriends: 5,
    sharedInterests: ['Cooking', 'Travel', 'Yoga'],
    sameGroups: ['Foodies United', 'Wellness Circle'],
  ),
  AppUser(
    name: 'Liam Brown',
    username: '@liamb',
    mutualFriends: 8,
    sharedInterests: ['Gaming', 'Music', 'Basketball'],
    sameGroups: ['Gamers Guild', 'Music Lovers'],
  ),
  AppUser(
    name: 'Emma Wang',
    username: '@emmaw',
    mutualFriends: 2,
    sharedInterests: ['Art', 'Photography'],
    sameGroups: ['Creative Collective'],
  ),
  AppUser(
    name: 'Noah Lee',
    username: '@noahl',
    mutualFriends: 6,
    sharedInterests: ['Running', 'Swimming', 'Cycling'],
    sameGroups: ['Fitness Freaks', 'Hiking Enthusiasts'],
  ),
  AppUser(
    name: 'Olivia Tan',
    username: '@oliviat',
    mutualFriends: 4,
    sharedInterests: ['Reading', 'Writing', 'Yoga'],
    sameGroups: ['Book Lovers Club'],
  ),
  AppUser(
    name: 'James Wong',
    username: '@jamesw',
    mutualFriends: 7,
    sharedInterests: ['Cooking', 'Travel', 'Photography'],
    sameGroups: ['Foodies United', 'Creative Collective'],
  ),
  AppUser(
    name: 'Mia Patel',
    username: '@miap',
    mutualFriends: 1,
    sharedInterests: ['Dancing', 'Music'],
    sameGroups: ['Music Lovers', 'Wellness Circle'],
  ),
];
