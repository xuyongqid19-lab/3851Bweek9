import cors from "cors";
import express from "express";
import pg from "pg";

const { Pool } = pg;

const port = Number(process.env.PORT || 3000);
const pool = new Pool({
  connectionString:
    process.env.DATABASE_URL ||
    "postgres://global_village:global_village@localhost:5433/global_village",
});
const authMeUrl = process.env.AUTH_API_ME_URL || "http://localhost:3002/auth/me";

const app = express();
app.use(cors());
app.use(express.json());

const gridCellSizeDegrees = 0.0045;
const nearbyRetentionMinutes = 5;
const nearbyCandidateLimit = 100;
const nearbyResultLimit = 10;

function gridCellFor(latitude, longitude) {
  return `${Math.floor(latitude / gridCellSizeDegrees)}:${Math.floor(
    longitude / gridCellSizeDegrees,
  )}`;
}

function nearbyCells(latitude, longitude) {
  const latIndex = Math.floor(latitude / gridCellSizeDegrees);
  const lonIndex = Math.floor(longitude / gridCellSizeDegrees);
  const cells = [];
  for (let latOffset = -1; latOffset <= 1; latOffset += 1) {
    for (let lonOffset = -1; lonOffset <= 1; lonOffset += 1) {
      cells.push(`${latIndex + latOffset}:${lonIndex + lonOffset}`);
    }
  }
  return cells;
}

function distanceMeters(fromLatitude, fromLongitude, toLatitude, toLongitude) {
  const earthRadiusMeters = 6371000;
  const lat1 = degreesToRadians(fromLatitude);
  const lat2 = degreesToRadians(toLatitude);
  const deltaLat = degreesToRadians(toLatitude - fromLatitude);
  const deltaLon = degreesToRadians(toLongitude - fromLongitude);
  const a =
    Math.sin(deltaLat / 2) * Math.sin(deltaLat / 2) +
    Math.cos(lat1) *
      Math.cos(lat2) *
      Math.sin(deltaLon / 2) *
      Math.sin(deltaLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return earthRadiusMeters * c;
}

function degreesToRadians(degrees) {
  return (degrees * Math.PI) / 180;
}

function proximityLabel(meters) {
  if (meters < 80) return "Very close";
  if (meters < 250) return "Nearby";
  return `${Math.round(meters)} m away`;
}

function displayNameFor(user) {
  return user.fullName || user.username || user.email || "Current User";
}

async function currentUserFromRequest(req, { required = false } = {}) {
  const header = req.headers.authorization || "";
  const token = header.startsWith("Bearer ") ? header.slice(7) : "";
  if (!token) {
    if (required) {
      const error = new Error("Authentication required.");
      error.statusCode = 401;
      throw error;
    }
    return null;
  }

  const response = await fetch(authMeUrl, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!response.ok) {
    const error = new Error("Invalid or expired session.");
    error.statusCode = 401;
    throw error;
  }
  const data = await response.json();
  return data.user || null;
}

function activityFromRow(row, attendeeRows = [], currentUser = null) {
  return {
    id: row.id,
    title: row.title,
    dateTime: row.date_time,
    location: row.location,
    category: row.category,
    description: row.description,
    latitude: Number(row.latitude),
    longitude: Number(row.longitude),
    groupName: row.group_name,
    isOwnedByCurrentUser: currentUser
      ? row.created_by_user_id === currentUser.id
      : false,
    attendees: attendeeRows.map((attendee) => attendee.display_name),
  };
}

function validateActivityBody(body) {
  const required = [
    "title",
    "dateTime",
    "location",
    "category",
    "description",
    "latitude",
    "longitude",
    "groupName",
  ];
  const missing = required.filter((key) => body[key] === undefined || body[key] === "");
  if (missing.length > 0) {
    return `Missing required fields: ${missing.join(", ")}`;
  }
  if (!Number.isFinite(Number(body.latitude)) || !Number.isFinite(Number(body.longitude))) {
    return "Latitude and longitude must be numbers.";
  }
  return null;
}

app.get("/health", async (_req, res) => {
  await pool.query("SELECT 1");
  res.json({ ok: true });
});

app.get("/community/activities", async (req, res, next) => {
  try {
    const currentUser = await currentUserFromRequest(req);
    const latitude = Number(req.query.lat);
    const longitude = Number(req.query.lng);
    const cells =
      Number.isFinite(latitude) && Number.isFinite(longitude)
        ? nearbyCells(latitude, longitude)
        : null;

    const query = cells
      ? {
          text: `
            SELECT *
            FROM community_activities
            WHERE grid_cell = ANY($1)
            ORDER BY created_at DESC
            LIMIT 100
          `,
          values: [cells],
        }
      : {
          text: `
            SELECT *
            FROM community_activities
            ORDER BY created_at DESC
            LIMIT 100
          `,
          values: [],
        };

    const { rows } = await pool.query(query);
    const attendeeResult =
      rows.length === 0
        ? { rows: [] }
        : await pool.query(
            `
              SELECT activity_id, display_name
              FROM activity_attendees
              WHERE activity_id = ANY($1::uuid[])
              ORDER BY joined_at ASC
            `,
            [rows.map((row) => row.id)],
          );
    const attendeesByActivity = new Map();
    for (const attendee of attendeeResult.rows) {
      const existing = attendeesByActivity.get(attendee.activity_id) || [];
      existing.push(attendee);
      attendeesByActivity.set(attendee.activity_id, existing);
    }

    res.json({
      activities: rows.map((row) =>
        activityFromRow(row, attendeesByActivity.get(row.id) || [], currentUser),
      ),
    });
  } catch (error) {
    next(error);
  }
});

app.post("/community/activities", async (req, res, next) => {
  try {
    const currentUser = await currentUserFromRequest(req, { required: true });
    const validationError = validateActivityBody(req.body);
    if (validationError) {
      res.status(400).json({ error: validationError });
      return;
    }

    const latitude = Number(req.body.latitude);
    const longitude = Number(req.body.longitude);
    const { rows } = await pool.query(
      `
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
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
        RETURNING *
      `,
      [
        req.body.title,
        req.body.dateTime,
        req.body.location,
        req.body.category,
        req.body.description,
        latitude,
        longitude,
        gridCellFor(latitude, longitude),
        req.body.groupName,
        currentUser.id,
      ],
    );

    res.status(201).json({ activity: activityFromRow(rows[0], [], currentUser) });
  } catch (error) {
    next(error);
  }
});

app.put("/community/activities/:id", async (req, res, next) => {
  try {
    const currentUser = await currentUserFromRequest(req, { required: true });
    const validationError = validateActivityBody(req.body);
    if (validationError) {
      res.status(400).json({ error: validationError });
      return;
    }

    const latitude = Number(req.body.latitude);
    const longitude = Number(req.body.longitude);
    const { rows } = await pool.query(
      `
        UPDATE community_activities
        SET title = $1,
            date_time = $2,
            location = $3,
            category = $4,
            description = $5,
            latitude = $6,
            longitude = $7,
            grid_cell = $8,
            group_name = $9,
            updated_at = now()
        WHERE id = $10 AND created_by_user_id = $11
        RETURNING *
      `,
      [
        req.body.title,
        req.body.dateTime,
        req.body.location,
        req.body.category,
        req.body.description,
        latitude,
        longitude,
        gridCellFor(latitude, longitude),
        req.body.groupName,
        req.params.id,
        currentUser.id,
      ],
    );

    if (rows.length === 0) {
      res.status(404).json({ error: "Activity not found." });
      return;
    }

    res.json({ activity: activityFromRow(rows[0], [], currentUser) });
  } catch (error) {
    next(error);
  }
});

app.delete("/community/activities/:id", async (req, res, next) => {
  try {
    const currentUser = await currentUserFromRequest(req, { required: true });
    await pool.query(
      "DELETE FROM community_activities WHERE id = $1 AND created_by_user_id = $2",
      [req.params.id, currentUser.id],
    );
    res.status(204).send();
  } catch (error) {
    next(error);
  }
});

app.post("/community/activities/:id/attendees", async (req, res, next) => {
  try {
    const currentUser = await currentUserFromRequest(req, { required: true });
    await pool.query(
      `
        INSERT INTO activity_attendees (activity_id, user_id, display_name)
        VALUES ($1, $2, $3)
        ON CONFLICT (activity_id, user_id)
        DO UPDATE SET display_name = EXCLUDED.display_name, joined_at = now()
      `,
      [req.params.id, currentUser.id, displayNameFor(currentUser)],
    );
    res.status(204).send();
  } catch (error) {
    next(error);
  }
});

app.delete("/community/activities/:id/attendees/current", async (req, res, next) => {
  try {
    const currentUser = await currentUserFromRequest(req, { required: true });
    await pool.query(
      "DELETE FROM activity_attendees WHERE activity_id = $1 AND user_id = $2",
      [req.params.id, currentUser.id],
    );
    res.status(204).send();
  } catch (error) {
    next(error);
  }
});

app.post("/community/nearby/people", async (req, res, next) => {
  try {
    const currentUser = await currentUserFromRequest(req, { required: true });
    const latitude = Number(req.body.latitude);
    const longitude = Number(req.body.longitude);
    const requestedRadiusMeters = Number(req.body.radiusMeters ?? 100);
    if (!Number.isFinite(requestedRadiusMeters) || requestedRadiusMeters <= 0) {
      res.status(400).json({ error: "Search radius must be a positive number." });
      return;
    }
    const radiusMeters = Math.min(requestedRadiusMeters, 100);
    const candidateLimit = Math.min(
      Number(req.body.candidateLimit || nearbyCandidateLimit),
      nearbyCandidateLimit,
    );
    const maximumResults = Math.min(
      Number(req.body.maximumResults || nearbyResultLimit),
      nearbyResultLimit,
    );
    if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
      res.status(400).json({ error: "Latitude and longitude must be numbers." });
      return;
    }

    const nowResult = await pool.query("SELECT now() AS now");
    const recordedAt = nowResult.rows[0].now;
    const expiresAtResult = await pool.query(
      "SELECT now() + ($1 || ' minutes')::interval AS expires_at",
      [nearbyRetentionMinutes],
    );
    const expiresAt = expiresAtResult.rows[0].expires_at;
    const gridCell = gridCellFor(latitude, longitude);

    await pool.query("DELETE FROM nearby_locations WHERE expires_at <= now()");
    await pool.query(
      `
        INSERT INTO nearby_locations (
          user_id,
          display_name,
          latitude,
          longitude,
          grid_cell,
          recorded_at,
          expires_at
        )
        VALUES ($1, $2, $3, $4, $5, now(), now() + ($6 || ' minutes')::interval)
        ON CONFLICT (user_id)
        DO UPDATE SET
          display_name = EXCLUDED.display_name,
          latitude = EXCLUDED.latitude,
          longitude = EXCLUDED.longitude,
          grid_cell = EXCLUDED.grid_cell,
          recorded_at = now(),
          expires_at = now() + ($6 || ' minutes')::interval
      `,
      [
        currentUser.id,
        displayNameFor(currentUser),
        latitude,
        longitude,
        gridCell,
        nearbyRetentionMinutes,
      ],
    );

    const cells = nearbyCells(latitude, longitude);
    const candidateResult = await pool.query(
      `
        SELECT *
        FROM nearby_locations
        WHERE user_id <> $1
          AND grid_cell = ANY($2)
          AND expires_at > now()
        ORDER BY recorded_at DESC
        LIMIT $3
      `,
      [currentUser.id, cells, candidateLimit],
    );

    const people = candidateResult.rows
      .map((row) => {
        const meters = distanceMeters(
          latitude,
          longitude,
          Number(row.latitude),
          Number(row.longitude),
        );
        return {
          name: row.display_name,
          relationshipStatus: "nonFriend",
          proximityLabel: proximityLabel(meters),
          latitude: Number(row.latitude),
          longitude: Number(row.longitude),
          distanceMeters: meters,
          lastSeenAt: row.recorded_at,
        };
      })
      .filter((person) => person.distanceMeters <= radiusMeters)
      .sort((a, b) => a.distanceMeters - b.distanceMeters)
      .slice(0, maximumResults);

    res.json({
      people,
      indexCellCount: cells.length,
      candidateCount: candidateResult.rows.length,
      recordedAt,
      expiresAt,
    });
  } catch (error) {
    next(error);
  }
});

app.use((error, _req, res, _next) => {
  console.error(error);
  res
    .status(error.statusCode || 500)
    .json({ error: error.message || "Community API failed." });
});

app.listen(port, process.env.HOST || "0.0.0.0", () => {
  console.log(`Community API listening on port ${port}`);
});
