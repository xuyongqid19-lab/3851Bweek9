CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS community_activities (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL,
  date_time text NOT NULL,
  location text NOT NULL,
  category text NOT NULL,
  description text NOT NULL,
  latitude double precision NOT NULL,
  longitude double precision NOT NULL,
  grid_cell text NOT NULL,
  group_name text NOT NULL,
  created_by_user_id text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_community_activities_grid_cell
ON community_activities (grid_cell);

CREATE TABLE IF NOT EXISTS activity_attendees (
  activity_id uuid NOT NULL REFERENCES community_activities(id) ON DELETE CASCADE,
  user_id text NOT NULL,
  display_name text NOT NULL,
  joined_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (activity_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_activity_attendees_user
ON activity_attendees (user_id);

CREATE TABLE IF NOT EXISTS nearby_locations (
  user_id text PRIMARY KEY,
  display_name text NOT NULL,
  latitude double precision NOT NULL,
  longitude double precision NOT NULL,
  grid_cell text NOT NULL,
  recorded_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_nearby_locations_grid_expiry
ON nearby_locations (grid_cell, expires_at);

INSERT INTO community_activities (
  title,
  date_time,
  location,
  category,
  description,
  latitude,
  longitude,
  grid_cell,
  group_name,
  created_by_user_id
) VALUES
  (
    'Basketball Match',
    'Sun, May 25 - 9:00 AM',
    'Riverside Park Basketball Court',
    'sports',
    'Join us for a friendly match and fun together as a community.',
    39.7827,
    -89.6491,
    '8840:-19926',
    'Basketball Match Group',
    'seed'
  ),
  (
    'Green Space Picnic',
    'Sun, May 12 - 3:00 PM',
    'Riverside Park - Main Lawn',
    'social',
    'Bring snacks, blankets, and good energy for a relaxed afternoon together.',
    39.7837,
    -89.6511,
    '8840:-19926',
    'Green Space Picnic Group',
    'seed'
  ),
  (
    'Morning Yoga in the Park',
    'Sat, May 25 - 7:00 AM',
    'Central Park',
    'health',
    'Start the morning with a relaxed community walk through the park.',
    39.7842,
    -89.6481,
    '8840:-19922',
    'Morning Yoga Group',
    'seed'
  ),
  (
    'Community Clean-Up',
    'Sat, May 31 - 10:00 AM',
    'City Center',
    'volunteer',
    'Help keep our shared spaces clean. Gloves and bags will be provided.',
    39.7847,
    -89.6521,
    '8841:-19926',
    'Community Clean-Up Group',
    'seed'
  ),
  (
    'Book Club Meetup',
    'May 15 - 7:00 PM',
    'Community Library',
    'study',
    'Discuss this month''s book and vote for the next community read.',
    39.7792,
    -89.6486,
    '8839:-19922',
    'Book Club Meetup Group',
    'seed'
  ),
  (
    'Hiking Adventure',
    'Sun, May 26 - 8:00 AM',
    'Pine Ridge Trail',
    'sports',
    'Meet early for a scenic hike. Wear comfortable shoes and bring water.',
    39.7787,
    -89.6521,
    '8839:-19926',
    'Hiking Adventure Group',
    'seed'
  )
ON CONFLICT DO NOTHING;
